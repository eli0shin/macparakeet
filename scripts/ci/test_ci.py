from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from classify_changes import classify, main as classify_main
from check_results import check
from run_tests import executed_count, parse_tests, partition, run_command


class ClassificationTests(unittest.TestCase):
    def test_prose_only(self):
        paths = ["README.md", "AGENTS.md", "CLAUDE.md", "docs/test.md",
                 "plans/one.md", "spec/contracts/cli.md", "integrations/README.md",
                 "Sources/MacParakeetCore/Audio/README.md"]
        self.assertEqual(classify(paths), {"code": False, "release": False})

    def test_unknown_inputs_and_test_fixtures_get_code_checks(self):
        for path in ["Sources/Core.swift", "Tests/test.swift", "Tests/fixture.md",
                     "docs/schema.json", "unknown-input", ".swift-format",
                     "Sources/CLI/CHANGELOG.md"]:
            with self.subTest(path=path):
                self.assertTrue(classify([path])["code"])

    def test_release_inputs(self):
        for path in ["Package.swift", "Package.resolved", ".github/workflows/ci.yml",
                     "scripts/ci/run_tests.py", "scripts/dist/build_app_bundle.sh",
                     "Assets/icon.png", "Sources/App/Resources/file.json",
                     "App.xcodeproj/project.pbxproj", "App.entitlements", "Info.plist"]:
            with self.subTest(path=path):
                self.assertEqual(classify([path]), {"code": True, "release": True})

    def test_mixed_changes_do_not_skip_code(self):
        self.assertEqual(classify(["README.md", "Sources/Core.swift"]),
                         {"code": True, "release": False})

    def test_main_and_manual_run_all_checks(self):
        for event in ["push", "workflow_dispatch"]:
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "outputs"
                with patch.dict(os.environ, {"GITHUB_EVENT_NAME": event, "GITHUB_OUTPUT": str(output)}):
                    classify_main()
                self.assertEqual(output.read_text(), "code=true\nrelease=true\n")

    def test_pr_diff_includes_old_and_new_rename_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "outputs"
            with patch.dict(os.environ, {"GITHUB_EVENT_NAME": "pull_request",
                                         "PR_BASE_SHA": "abc123", "GITHUB_OUTPUT": str(output)}):
                with patch("classify_changes.subprocess.check_output", return_value=
                           b"Assets/old.png\0docs/new.md\0") as git:
                    classify_main()
            self.assertEqual(output.read_text(), "code=true\nrelease=true\n")
            git.assert_called_once_with(
                ["git", "diff", "--name-only", "--no-renames", "-z", "abc123...HEAD"])


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.workflow = Path(".github/workflows/ci.yml").read_text()
        self.release_job = self.workflow.split("\n  release:\n", 1)[1].split("\n  # Preserve", 1)[0]

    def test_debug_tests_job_has_twenty_minute_timeout(self):
        debug_job = self.workflow.split("\n  debug-tests:\n", 1)[1].split("\n  swift6:\n", 1)[0]
        self.assertIn("\n    timeout-minutes: 20\n", debug_job)

    def test_fixture_bundle_inputs_cannot_reach_published_app(self):
        fixture = self.release_job.split("      - name: Release Bundle Fixture Smoke\n", 1)[1]
        fixture = fixture.split("      - name:", 1)[0]
        self.assertIn("if: github.event_name == 'pull_request'", fixture)
        self.assertIn('BUNDLE_YTDLP: "0"', fixture)
        self.assertIn('BUNDLE_NODE: "0"', fixture)
        self.assertIn("FFMPEG_PATH: /usr/bin/true", fixture)

        downloadable = self.release_job.split("      - name: Build downloadable unsigned app\n", 1)[1]
        downloadable = downloadable.split("      - name:", 1)[0]
        self.assertIn("github.event_name == 'workflow_dispatch'", downloadable)
        self.assertIn("github.ref == 'refs/heads/main'", downloadable)
        self.assertIn("BUILD_SOURCE: github-actions-unsigned-development", downloadable)
        self.assertIn("bash scripts/ci/verify_downloadable_app.sh dist/MacParakeet.app", downloadable)
        self.assertNotIn("BUNDLE_YTDLP", downloadable)
        self.assertNotIn("BUNDLE_NODE", downloadable)
        self.assertNotIn("FFMPEG_PATH", downloadable)
        self.assertLess(
            self.release_job.index("Release Bundle Fixture Smoke"),
            self.release_job.index("Build downloadable unsigned app"),
        )
        self.assertLess(
            self.release_job.index("Build downloadable unsigned app"),
            self.release_job.index("Package unsigned app disk image"),
        )

    def test_release_job_packages_finder_mountable_app_only_for_main_and_manual_runs(self):
        package = self.release_job.split("      - name: Package unsigned app disk image\n", 1)[1]
        package = package.split("      - name:", 1)[0]
        publish_condition = (
            "if: github.event_name == 'workflow_dispatch' || "
            "(github.event_name == 'push' && github.ref == 'refs/heads/main')"
        )
        self.assertIn(publish_condition, package)
        self.assertIn('APP_PATH="dist/MacParakeet.app"', package)
        self.assertIn('DMG_PATH="dist/MacParakeet-unsigned-non-notarized.dmg"', package)
        self.assertIn('/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/MacParakeet.app"', package)
        self.assertIn('ln -s /Applications "$STAGING_DIR/Applications"', package)
        self.assertIn("hdiutil create", package)
        self.assertIn('-format UDZO "$DMG_PATH"', package)
        self.assertIn("hdiutil imageinfo -plist", package)
        self.assertIn('= "UDZO"', package)
        self.assertIn('hdiutil verify "$DMG_PATH"', package)
        self.assertIn('hdiutil attach "$DMG_PATH" -readonly -nobrowse -noautoopen', package)
        self.assertIn("test -x", package)
        self.assertIn("stat -f '%p'", package)
        self.assertIn("readlink", package)
        self.assertIn("CFBundleIdentifier", package)
        self.assertIn("com.macparakeet.MacParakeet", package)
        self.assertIn(
            'bash scripts/ci/verify_downloadable_app.sh "$MOUNTED_APP"',
            package,
        )
        self.assertNotIn("ditto -c -k", package)
        self.assertNotIn("unsigned-non-notarized.zip", package)

    def test_release_job_uploads_named_disk_image_fail_closed_with_retention(self):
        upload = self.release_job.split("      - name: Upload unsigned non-notarized app\n", 1)[1]
        upload = upload.split("      - name:", 1)[0]
        publish_condition = (
            "if: github.event_name == 'workflow_dispatch' || "
            "(github.event_name == 'push' && github.ref == 'refs/heads/main')"
        )
        self.assertIn(publish_condition, upload)
        self.assertIn("uses: actions/upload-artifact@v7", upload)
        self.assertIn("name: MacParakeet-unsigned-non-notarized", upload)
        self.assertIn("path: dist/MacParakeet-unsigned-non-notarized.dmg", upload)
        self.assertNotIn(".zip", upload)
        self.assertIn("if-no-files-found: error", upload)
        self.assertIn("retention-days: 7", upload)
        self.assertNotIn("continue-on-error", upload)

    def test_release_log_artifact_remains_available(self):
        self.assertIn("name: swift-release-logs", self.release_job)
        self.assertIn("if: always()", self.release_job)


class DownloadableAppVerificationTests(unittest.TestCase):
    def make_app(self, root, ffmpeg_output="ffmpeg version fixture", include_ytdlp=True,
                 include_node=True):
        resources = Path(root) / "MacParakeet.app" / "Contents" / "Resources"
        resources.mkdir(parents=True)

        helpers = {"ffmpeg": ffmpeg_output}
        if include_ytdlp:
            helpers["yt-dlp"] = "2026.01.01"
        if include_node:
            helpers["node"] = "v24.13.1"
        for name, output in helpers.items():
            helper = resources / name
            helper.write_text(f"#!/bin/sh\nprintf '%s\\n' '{output}'\n")
            helper.chmod(0o755)
        return resources.parent.parent

    def verify(self, app):
        return subprocess.run(
            ["bash", "scripts/ci/verify_downloadable_app.sh", str(app)],
            text=True,
            capture_output=True,
        )

    def test_accepts_required_helpers_and_executes_version_smokes(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.verify(self.make_app(directory))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("FFmpeg: ffmpeg version fixture", result.stdout)
        self.assertIn("yt-dlp: 2026.01.01", result.stdout)
        self.assertIn("node: v24.13.1", result.stdout)

    def test_rejects_missing_runtime_helpers(self):
        for helper in ["yt-dlp", "node"]:
            with self.subTest(helper=helper), tempfile.TemporaryDirectory() as directory:
                app = self.make_app(
                    directory,
                    include_ytdlp=helper != "yt-dlp",
                    include_node=helper != "node",
                )
                self.assertNotEqual(self.verify(app).returncode, 0)

    def test_rejects_true_and_non_ffmpeg_fixtures(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.make_app(directory)
            shutil.copyfile("/usr/bin/true", app / "Contents" / "Resources" / "ffmpeg")
            self.assertNotEqual(self.verify(app).returncode, 0)

        with tempfile.TemporaryDirectory() as directory:
            app = self.make_app(directory, ffmpeg_output="")
            self.assertNotEqual(self.verify(app).returncode, 0)


class GateTests(unittest.TestCase):
    def results(self, code="true", release="false"):
        return {"changes": {"result": "success", "outputs": {"code": code, "release": release}},
                "debug-tests": {"result": "success" if code == "true" else "skipped"},
                "swift6": {"result": "success" if code == "true" else "skipped"},
                "release": {"result": "success" if release == "true" else "skipped"}}

    def test_code_release_and_prose_success(self):
        for code, release in [("true", "false"), ("true", "true"), ("false", "false")]:
            check(self.results(code, release))

    def test_required_failure_cancellation_and_unexpected_skip_fail(self):
        for job in ["changes", "debug-tests", "swift6", "release"]:
            for result in ["failure", "cancelled", "skipped"]:
                needs = self.results(release="true")
                needs[job]["result"] = result
                with self.subTest(job=job, result=result), self.assertRaises(ValueError):
                    check(needs)

    def test_missing_classification_fails(self):
        needs = self.results()
        del needs["changes"]["outputs"]["code"]
        with self.assertRaises(ValueError):
            check(needs)


class ShardingTests(unittest.TestCase):
    def test_discovery_is_fail_closed(self):
        for output in ["", "warning: unknown format", "M.C/a\nM.C/a"]:
            with self.subTest(output=output), self.assertRaises(ValueError):
                parse_tests(output)
        self.assertEqual(parse_tests("M.C/a\nM.D/b\n"), ["M.C/a", "M.D/b"])

    def test_all_cases_once_classes_together_and_stable(self):
        tests = [f"Module.Class{i}/test{j}" for i in range(12) for j in range(i + 1)]
        shards = partition(tests, 3)
        self.assertEqual(sorted(test for shard in shards for test in shard), sorted(tests))
        self.assertEqual(shards, partition(list(reversed(tests)), 3))
        assignments = {}
        for index, shard in enumerate(shards):
            for test in shard:
                name = test.split("/")[0]
                self.assertEqual(assignments.setdefault(name, index), index)
        self.assertLessEqual(max(map(len, shards)) - min(map(len, shards)), 2)

    def test_fewer_classes_than_workers(self):
        self.assertEqual(partition(["M.C/a", "M.C/b"], 8), [["M.C/a", "M.C/b"]])
        with self.assertRaises(ValueError):
            partition(["M.C/a"], 0)

    def test_last_summary_counts_skips_and_single_test(self):
        self.assertEqual(executed_count(
            "Executed 1 test, with 0 failures\nExecuted 12 tests, with 2 tests skipped and 0 failures"), 12)
        self.assertIsNone(executed_count("No matching test cases were run"))

    def run_fixture(self, source, expected=None, timeout=5):
        with tempfile.TemporaryDirectory() as directory:
            return run_command("fixture", [sys.executable, "-c", source],
                               Path(directory), timeout, expected)

    def test_success_requires_expected_count(self):
        source = "print('Executed 2 tests, with 0 failures')"
        self.assertEqual(self.run_fixture(source, 2)["exit_code"], 0)
        self.assertNotEqual(self.run_fixture(source, 3)["exit_code"], 0)
        self.assertNotEqual(self.run_fixture("print('no tests')", 1)["exit_code"], 0)

    def test_test_failure_is_not_hidden_by_correct_count(self):
        result = self.run_fixture("print('Executed 2 tests, with 1 failure'); raise SystemExit(1)", 2)
        self.assertNotEqual(result["exit_code"], 0)

    def test_early_assertion_is_visible_after_many_later_passes(self):
        output = io.StringIO()
        with redirect_stdout(output):
            result = self.run_fixture(
                "print('Fixture.swift:12: error: original assertion'); "
                "print('later passing test\\n' * 100); raise SystemExit(1)"
            )
        self.assertNotEqual(result["exit_code"], 0)
        self.assertIn("Fixture.swift:12: error: original assertion", output.getvalue())

    def test_timeout_fails(self):
        self.assertNotEqual(self.run_fixture("import time; time.sleep(5)", timeout=0.05)["exit_code"], 0)

    def test_swift_testing_failure_propagates_without_xctest_count(self):
        self.assertEqual(self.run_fixture("raise SystemExit(0)")["exit_code"], 0)
        self.assertNotEqual(self.run_fixture("raise SystemExit(1)")["exit_code"], 0)


if __name__ == "__main__":
    unittest.main()

from contextlib import redirect_stdout
import io
import os
from pathlib import Path
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

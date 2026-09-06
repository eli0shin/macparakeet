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
        self.release_job = self.workflow.split("\n  release:\n", 1)[1].split("\n  development-artifact:\n", 1)[0]
        self.development_job = self.workflow.split("\n  development-artifact:\n", 1)[1].split("\n  signed-artifact:\n", 1)[0]
        self.signed_job = self.workflow.split("\n  signed-artifact:\n", 1)[1].split("\n  # Preserve", 1)[0]
        self.prototype_job = self.workflow.split("\n  compact-transcript-prototype:\n", 1)[1].split("\n  debug-tests:\n", 1)[0]

    def test_compact_transcript_prototype_is_self_contained_and_downloadable(self):
        self.assertIn("github.event_name == 'pull_request'", self.prototype_job)
        self.assertIn("github.head_ref == '025-prototype-compact-borderless-meeting-transcript'", self.prototype_job)
        self.assertIn("github.event_name == 'workflow_dispatch'", self.prototype_job)
        self.assertIn("github.ref == 'refs/heads/025-prototype-compact-borderless-meeting-transcript'", self.prototype_job)
        self.assertIn("Verify self-contained prototype", self.prototype_job)
        self.assertIn('forbidden = ["<script src=", "<link rel=", "http://", "https://", "file:///"', self.prototype_job)
        upload = self.prototype_job.split("      - name: Upload compact transcript prototype\n", 1)[1]
        self.assertIn("uses: actions/upload-artifact@v7", upload)
        self.assertIn("name: MacParakeet-compact-borderless-transcript-prototype", upload)
        self.assertIn("path: prototypes/compact-borderless-meeting-transcript/index.html", upload)
        self.assertIn("if-no-files-found: error", upload)
        self.assertIn("retention-days: 14", upload)
        self.assertNotIn("secrets.", self.prototype_job)

    def test_debug_tests_job_has_twenty_minute_timeout(self):
        debug_job = self.workflow.split("\n  debug-tests:\n", 1)[1].split("\n  swift6:\n", 1)[0]
        self.assertIn("\n    timeout-minutes: 20\n", debug_job)

    def test_fixture_bundle_inputs_cannot_reach_published_app(self):
        fixture = self.release_job.split("      - name: Release Bundle Fixture Smoke\n", 1)[1]
        fixture = fixture.split("      - name:", 1)[0]
        self.assertIn("if: github.event_name == 'pull_request'", fixture)
        self.assertIn('BUILD_SYSTEM: xcodebuild', fixture)
        self.assertIn('BUNDLE_YTDLP: "0"', fixture)
        self.assertIn('BUNDLE_NODE: "0"', fixture)
        self.assertIn("FFMPEG_PATH: /usr/bin/true", fixture)

        self.assertNotIn("MacParakeet-signed-notarized-ci-test", self.release_job)
        self.assertNotIn("unsigned-non-notarized", self.workflow)

    def test_development_publication_waits_for_complete_gate_on_main_and_manual_runs(self):
        self.assertIn("needs: swift-test", self.development_job)
        self.assertIn("needs.swift-test.result == 'success'", self.development_job)
        self.assertIn("github.event_name == 'workflow_dispatch'", self.development_job)
        self.assertIn("github.event_name == 'push'", self.development_job)
        self.assertIn("github.ref == 'refs/heads/main'", self.development_job)
        self.assertNotIn("pull_request", self.development_job)
        self.assertNotIn("environment:", self.development_job)
        self.assertNotIn("secrets.", self.development_job)

    def test_development_upload_is_unambiguous_fail_closed_and_short_lived(self):
        self.assertIn("bash scripts/ci/publish_development_artifact.sh", self.development_job)
        upload = self.development_job.split("      - name: Upload owner-only development DMG\n", 1)[1]
        upload = upload.split("      - name:", 1)[0]
        self.assertIn("uses: actions/upload-artifact@v7", upload)
        self.assertIn("name: MacParakeet-owner-development-build", upload)
        self.assertIn("path: dist/MacParakeet-owner-development-build.dmg", upload)
        self.assertIn("if-no-files-found: error", upload)
        self.assertIn("retention-days: 3", upload)
        self.assertNotIn("continue-on-error", upload)
        self.assertNotIn("MacParakeet-signed-notarized-ci-test", upload)

    def test_signed_publication_waits_for_complete_fail_closed_gate(self):
        self.assertIn("needs: swift-test", self.signed_job)
        self.assertIn("needs.swift-test.result == 'success'", self.signed_job)
        self.assertNotIn("needs: [changes, release]", self.signed_job)

    def test_signed_publication_is_manual_main_and_environment_gated(self):
        self.assertIn("github.event_name == 'workflow_dispatch'", self.signed_job)
        self.assertIn("inputs.publish_signed_artifact == true", self.signed_job)
        self.assertIn("github.ref == 'refs/heads/main'", self.signed_job)
        self.assertIn("environment: signed-ci-artifact", self.signed_job)
        self.assertNotIn("pull_request", self.signed_job)
        self.assertIn("SIGNED_ARTIFACT_VERSION: ${{ inputs.signed_artifact_version }}", self.signed_job)

    def test_signing_secrets_exist_only_in_protected_job(self):
        secret_names = [
            "DEVELOPMENT_ID_CERTIFICATE_BASE64",
            "DEVELOPMENT_ID_CERTIFICATE_PASSWORD",
            "DEVELOPER_ID_APPLICATION_IDENTITY",
            "APPLE_TEAM_ID",
            "NOTARY_APPLE_ID",
            "NOTARY_APP_SPECIFIC_PASSWORD",
        ]
        unprotected = self.workflow.split("\n  signed-artifact:\n", 1)[0]
        for name in secret_names:
            with self.subTest(secret=name):
                self.assertIn("${{ secrets." + name + " }}", self.signed_job)
                self.assertNotIn(name, unprotected)

    def test_signed_upload_is_fail_closed_named_and_retained(self):
        upload = self.signed_job.split("      - name: Upload signed and notarized CI test DMG\n", 1)[1]
        upload = upload.split("      - name:", 1)[0]
        self.assertIn("uses: actions/upload-artifact@v7", upload)
        self.assertIn("name: MacParakeet-signed-notarized-ci-test", upload)
        self.assertIn("path: dist/MacParakeet-signed-notarized-ci-test.dmg", upload)
        self.assertIn("if-no-files-found: error", upload)
        self.assertIn("retention-days: 7", upload)
        self.assertNotIn("continue-on-error", upload)

    def test_release_log_artifact_remains_available(self):
        self.assertIn("name: swift-release-logs", self.release_job)
        self.assertIn("if: always()", self.release_job)


class SignedArtifactScriptTests(unittest.TestCase):
    def setUp(self):
        self.publish = Path("scripts/ci/publish_signed_artifact.sh").read_text()
        self.verify = Path("scripts/ci/verify_signed_dmg.sh").read_text()
        self.sign = Path("scripts/dist/sign_notarize.sh").read_text()
        self.privacy_verify = Path("scripts/dist/verify_app_privacy_surface.sh").read_text()
        self.downloadable_verify = Path("scripts/ci/verify_downloadable_app.sh").read_text()

    def test_credentials_use_ephemeral_keychain_with_failure_cleanup(self):
        self.assertIn("trap cleanup EXIT INT TERM", self.publish)
        self.assertIn('security create-keychain', self.publish)
        self.assertIn('security delete-keychain "$KEYCHAIN_PATH"', self.publish)
        self.assertIn('rm -f "$CERTIFICATE_PATH"', self.publish)
        self.assertIn('--keychain "$KEYCHAIN_PATH"', self.publish)
        self.assertIn('SIGN_KEYCHAIN="$KEYCHAIN_PATH"', self.publish)
        self.assertIn('NOTARYTOOL_KEYCHAIN="$KEYCHAIN_PATH"', self.publish)
        self.assertIn('codesign --keychain "$SIGN_KEYCHAIN"', self.sign)
        self.assertIn('xcrun notarytool "$@" --keychain "$NOTARYTOOL_KEYCHAIN"', self.sign)

    def test_missing_credentials_version_and_identity_fail_closed(self):
        for name in [
            "SIGNED_ARTIFACT_VERSION", "SIGNED_ARTIFACT_BUILD_NUMBER",
            "DEVELOPMENT_ID_CERTIFICATE_BASE64", "DEVELOPMENT_ID_CERTIFICATE_PASSWORD",
            "DEVELOPER_ID_APPLICATION_IDENTITY", "APPLE_TEAM_ID", "NOTARY_APPLE_ID",
            "NOTARY_APP_SPECIFIC_PASSWORD",
        ]:
            with self.subTest(variable=name):
                self.assertIn(name, self.publish)
        self.assertIn("explicit non-sentinel X.Y.Z", self.publish)
        self.assertIn('[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]', self.publish)
        self.assertIn('"Developer ID Application: "*" ($APPLE_TEAM_ID)"', self.publish)
        self.assertIn('grep -Fq "\\\"$DEVELOPER_ID_APPLICATION_IDENTITY\\\""', self.publish)
        self.assertIn('rm -f "$TRUSTED_DMG"', self.publish)
        self.assertLess(
            self.publish.index("verify_signed_dmg.sh"),
            self.publish.index('mv dist/MacParakeet.dmg "$TRUSTED_DMG"'),
        )

    def test_signing_and_verification_paths_do_not_hard_code_upstream_identity(self):
        signing_paths = "\n".join([
            self.publish, self.verify, self.sign, self.privacy_verify,
        ])
        self.assertNotIn("FYAF2ZD7RM", signing_paths)
        self.assertNotIn("Daniel Moon", signing_paths)

    def test_configured_identity_controls_notary_signing_and_verification(self):
        self.assertIn('--team-id "$APPLE_TEAM_ID"', self.publish)
        self.assertIn('SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION_IDENTITY"', self.publish)
        self.assertIn('EXPECTED_TEAM_ID="$APPLE_TEAM_ID"', self.publish)
        self.assertIn('EXPECTED_AUTHORITY="$DEVELOPER_ID_APPLICATION_IDENTITY"', self.publish)
        self.assertNotIn('echo "$identity_output"', self.publish)

    def test_build_reuses_release_gates_and_signed_helper_entitlements(self):
        self.assertIn("REQUIRE_MEETING_ECHO_ASSETS=1", self.publish)
        self.assertIn("scripts/dist/build_app_bundle.sh", self.publish)
        self.assertIn("scripts/dist/sign_notarize.sh", self.publish)
        self.assertIn("NODE_RUNTIME_ENTITLEMENTS", self.sign)
        self.assertIn("YTDLP_RUNTIME_ENTITLEMENTS", self.sign)
        self.assertIn("verify_app_privacy_surface.sh", self.sign)
        self.assertIn("verify_meeting_echo_assets.sh", self.sign)
        self.assertIn("verify_packaged_app_launch.sh", self.downloadable_verify)

    def test_landing_dmg_verification_covers_gatekeeper_stapling_and_helpers(self):
        for command in [
            "hdiutil verify", "codesign --verify --strict", "xcrun stapler validate",
            "spctl --assess --type open", "codesign --verify --deep --strict",
            "spctl --assess --type execute", "TeamIdentifier=$EXPECTED_TEAM_ID",
            "Authority=$EXPECTED_AUTHORITY", "verify_signature_identity",
            'find "$APP_PATH/Contents/Frameworks"',
            'find "$APP_PATH/Contents/Resources"',
            'find "$APP_PATH/Contents/MacOS"', "verify_downloadable_app.sh",
        ]:
            with self.subTest(command=command):
                self.assertIn(command, self.verify)


class DevelopmentArtifactScriptTests(unittest.TestCase):
    def setUp(self):
        self.publish = Path("scripts/ci/publish_development_artifact.sh").read_text()
        self.verify = Path("scripts/ci/verify_development_dmg.sh").read_text()
        self.downloadable_verify = Path("scripts/ci/verify_downloadable_app.sh").read_text()

    def test_build_uses_complete_runtime_defaults_without_credentials(self):
        self.assertIn("scripts/dist/build_app_bundle.sh", self.publish)
        self.assertIn("BUILD_SOURCE=github-actions-owner-development", self.publish)
        self.assertIn("BUILD_SYSTEM=xcodebuild", self.publish)
        self.assertNotIn("BUNDLE_YTDLP=0", self.publish)
        self.assertNotIn("BUNDLE_NODE=0", self.publish)
        self.assertNotIn("FFMPEG_PATH", self.publish)
        for sensitive_input in ["DEVELOPMENT_ID_CERTIFICATE", "NOTARY_APPLE_ID", "NOTARY_APP_SPECIFIC_PASSWORD"]:
            self.assertNotIn(sensitive_input, self.publish)

    def test_packaging_is_fail_closed_and_verifies_before_publication(self):
        self.assertIn("codesign --force --sign -", self.publish)
        self.assertIn("codesign --verify --deep --strict", self.publish)
        self.assertIn("verify_downloadable_app.sh", self.publish)
        self.assertIn("ln -s /Applications", self.publish)
        self.assertIn("-format UDZO", self.publish)
        self.assertIn("verify_development_dmg.sh", self.publish)
        self.assertLess(self.publish.index("verify_development_dmg.sh"),
                        self.publish.index("Owner-only development artifact is ready"))

    def test_landing_verification_locks_shape_signatures_symlinks_and_helpers(self):
        for expected in [
            "hdiutil verify", "plutil -extract Format raw", "Applications",
            "unexpected top-level item", "absolute bundle symlink",
            "codesign --verify --deep --strict", "codesign --verify --strict",
            "Signature=adhoc", "unexpectedly has a signing authority",
            "verify_downloadable_app.sh",
        ]:
            with self.subTest(expected=expected):
                self.assertIn(expected, self.verify)
        self.assertIn("verify_packaged_app_launch.sh", self.downloadable_verify)


class BundleAssemblyTests(unittest.TestCase):
    def test_packaged_apps_use_xcode_accessors_and_resource_layout(self):
        build = Path("scripts/dist/build_app_bundle.sh").read_text()
        signed_publish = Path("scripts/ci/publish_signed_artifact.sh").read_text()
        self.assertIn('BUILD_SYSTEM" != "xcodebuild"', build)
        self.assertIn("command-line resource accessors with checkout-path fallbacks", build)
        self.assertIn('app_resource_bundle="$product_dir/MacParakeet_MacParakeet.bundle"', build)
        self.assertIn('rm -rf "$RESOURCES_DIR/$name"', build)
        self.assertIn('cp -R "$bundle" "$RESOURCES_DIR/"', build)
        self.assertIn("BUILD_SYSTEM=xcodebuild", signed_publish)


class DownloadableAppVerificationTests(unittest.TestCase):
    def make_app(self, root, ffmpeg_output="ffmpeg version fixture", include_ytdlp=True,
                 include_node=True, include_app_resource_bundle=True, swiftpm_accessor=False,
                 checkout_bundle_fallback=False):
        app = Path(root) / "MacParakeet.app"
        contents = app / "Contents"
        resources = contents / "Resources"
        resources.mkdir(parents=True)
        if include_app_resource_bundle:
            (resources / "MacParakeet_MacParakeet.bundle").mkdir()
        (contents / "Frameworks" / "Sparkle.framework").mkdir(parents=True)
        macos = contents / "MacOS"
        macos.mkdir()
        app_executable = macos / "MacParakeet"
        resource_location = (
            "$app_root/MacParakeet_MacParakeet.bundle" if swiftpm_accessor
            else "$app_root/Contents/Resources/MacParakeet_MacParakeet.bundle"
        )
        app_executable.write_text(
            "#!/bin/sh\n"
            "app_root=$(cd \"$(dirname \"$0\")/../..\" && pwd)\n"
            f"if [ ! -d \"{resource_location}\" ]; then\n"
            "  echo 'MacParakeet/resource_bundle_accessor.swift:12: Fatal error: could not load resource bundle' >&2\n"
            "  exit 132\n"
            "fi\n"
            "while :; do sleep 1; done\n"
            + ("# /tmp/repo/.build/release/MacParakeet_MacParakeet.bundle\n"
               if checkout_bundle_fallback else "")
        )
        app_executable.chmod(0o755)
        cli = macos / "macparakeet-cli"
        cli.write_text("#!/bin/sh\nprintf '%s\\n' 'macparakeet-cli 3.0.0'\n")
        cli.chmod(0o755)

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

    def install_foundation_state_executable(self, app):
        executable = app / "Contents/MacOS/MacParakeet"
        if sys.platform != "darwin":
            # The changes job runs on Linux. Mirror Darwin Foundation's fixed-home
            # contract there; macOS runs the real Foundation fixture below.
            executable.write_text(
                "#!/bin/sh\n"
                "support=\"$CFFIXED_USER_HOME/Library/Application Support\"\n"
                "mkdir -p \"$support/MacParakeet\"\n"
                "touch \"$support/MacParakeet/launch-smoke-state\"\n"
                "printf '%s\\n%s\\n' \"$CFFIXED_USER_HOME\" \"$support\" > \"$LAUNCH_STATE_REPORT\"\n"
                "[ \"${LAUNCH_STATE_EXIT_AFTER_WRITE:-0}\" = 1 ] && exit 23\n"
                "while :; do sleep 1; done\n"
            )
            executable.chmod(0o755)
            return

        source = app.parent / "FoundationStateFixture.swift"
        source.write_text(
            "import Darwin\n"
            "import Foundation\n"
            "let environment = ProcessInfo.processInfo.environment\n"
            "let support = FileManager.default.urls(for: .applicationSupportDirectory, "
            "in: .userDomainMask)[0]\n"
            "let state = support.appendingPathComponent(\"MacParakeet/launch-smoke-state\")\n"
            "try FileManager.default.createDirectory(at: state.deletingLastPathComponent(), "
            "withIntermediateDirectories: true)\n"
            "try Data().write(to: state)\n"
            "let report = URL(fileURLWithPath: environment[\"LAUNCH_STATE_REPORT\"]!)\n"
            "let output = NSHomeDirectory() + \"\\n\" + support.path + \"\\n\"\n"
            "try output.write(to: report, atomically: true, encoding: .utf8)\n"
            "if environment[\"LAUNCH_STATE_EXIT_AFTER_WRITE\"] == \"1\" { exit(23) }\n"
            "RunLoop.current.run()\n"
        )
        subprocess.run(
            ["xcrun", "swiftc", str(source), "-o", str(executable)],
            check=True,
            capture_output=True,
            text=True,
        )

    def run_script(self, script, app, extra_environment=None):
        environment = os.environ.copy()
        environment["MACPARAKEET_PACKAGED_LAUNCH_SECONDS"] = "0.2"
        environment.update(extra_environment or {})
        return subprocess.run(
            ["bash", script, str(app)],
            text=True,
            capture_output=True,
            env=environment,
        )

    def verify(self, app):
        return self.run_script("scripts/ci/verify_downloadable_app.sh", app)

    def launch(self, app, extra_environment=None):
        return self.run_script(
            "scripts/ci/verify_packaged_app_launch.sh", app, extra_environment
        )

    def test_accepts_required_helpers_and_executes_version_smokes(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.verify(self.make_app(directory))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("FFmpeg: ffmpeg version fixture", result.stdout)
        self.assertIn("yt-dlp: 2026.01.01", result.stdout)
        self.assertIn("CLI: macparakeet-cli 3.0.0", result.stdout)
        self.assertIn("node: v24.13.1", result.stdout)

    def test_packaged_launch_smoke_catches_prefixed_resource_bundle_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.make_app(directory, swiftpm_accessor=True)
            result = self.launch(app)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SwiftPM resource bundle could not load", result.stderr)
        self.assertIn("resource_bundle_accessor.swift:12", result.stderr)

    def test_packaged_launch_isolates_and_cleans_foundation_user_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            real_home = root / "real-home"
            real_home.mkdir()
            report = root / "foundation-home.txt"
            app = self.make_app(root / "fixture")
            self.install_foundation_state_executable(app)
            result = self.launch(app, {
                "CFFIXED_USER_HOME": str(real_home),
                "HOME": str(real_home),
                "LAUNCH_STATE_REPORT": str(report),
                "MACPARAKEET_PACKAGED_LAUNCH_SECONDS": "1",
            })

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(
                (real_home / "Library/Application Support/MacParakeet/launch-smoke-state").exists()
            )
            isolated_home_text, application_support_text = report.read_text().splitlines()
            isolated_home = Path(isolated_home_text)
            application_support = Path(application_support_text)
            self.assertEqual(isolated_home.name, "home")
            self.assertEqual(application_support, isolated_home / "Library/Application Support")
            launch_root = isolated_home.parent
            self.assertTrue(launch_root.name.startswith("macparakeet-packaged-launch."))
            self.assertFalse(launch_root.exists(), "temporary launch root was not cleaned up")

    def test_failed_packaged_launch_cleans_isolated_foundation_user_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            real_home = root / "real-home"
            real_home.mkdir()
            report = root / "foundation-home.txt"
            app = self.make_app(root / "fixture")
            self.install_foundation_state_executable(app)
            result = self.launch(app, {
                "CFFIXED_USER_HOME": str(real_home),
                "HOME": str(real_home),
                "LAUNCH_STATE_REPORT": str(report),
                "LAUNCH_STATE_EXIT_AFTER_WRITE": "1",
                "MACPARAKEET_PACKAGED_LAUNCH_SECONDS": "1",
            })

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("terminated before", result.stderr)
            self.assertFalse(
                (real_home / "Library/Application Support/MacParakeet/launch-smoke-state").exists()
            )
            isolated_home_text, application_support_text = report.read_text().splitlines()
            isolated_home = Path(isolated_home_text)
            self.assertEqual(isolated_home.name, "home")
            self.assertEqual(Path(application_support_text), isolated_home / "Library/Application Support")
            self.assertFalse(isolated_home.parent.exists(), "failed launch root was not cleaned up")

    def test_verifier_requires_resource_bundle_at_bundle_resource_url(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.verify(self.make_app(directory, include_app_resource_bundle=False))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Bundle.main.resourceURL", result.stderr)

    def test_verifier_rejects_checkout_resource_fallbacks(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.make_app(directory, checkout_bundle_fallback=True)
            result = self.verify(app)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("fallback into a build checkout", result.stderr)

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

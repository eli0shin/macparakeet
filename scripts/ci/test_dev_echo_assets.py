"""Dev launch regression tests. No app launch, network, or user-data access.

Tests that inspect implementation files for literal text are absolutely unacceptable.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DevEchoAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("dev/run_app.sh", "dist/bundle_meeting_echo_assets.sh",
                     "dist/meeting_echo_asset_defaults.sh", "dist/verify_meeting_echo_assets.sh",
                     "dist/meeting_echo_runtime_probe.c", "dist/MacParakeet.entitlements"):
            target = self.root / "scripts" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / "scripts" / name, target)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls"
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("MACPARAKEET_", "BUNDLE_MEETING_", "REQUIRE_MEETING_",
                                         "VERIFY_", "STRICT_MEETING_"))}
        self.env.update(PATH=f"{self.bin}:{os.environ['PATH']}",
                        MACPARAKEET_CODESIGN_IDENTITY="fixture-signing-identity",
                        MACPARAKEET_MEETING_ECHO_AUTO_PREPARE="0")
        for cmd in ("xcodebuild", "install_name_tool", "codesign", "pkill", "sleep", "open", "nohup"):
            self.stub(cmd, f'echo {cmd} >> "{self.calls}"\nexit 0\n')
        self.stub("pgrep", "exit 1\n")
        self.stub("otool", "exit 0\n")
        products = self.root / ".build/xcode-dev/Build/Products/Debug"
        products.mkdir(parents=True)
        binary = products / "MacParakeet"
        binary.write_text("#!/bin/sh\nexit 0\n")
        binary.chmod(0o755)
        self.app = products / "MacParakeet-Dev.app"

    def stub(self, name, text):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + text)
        path.chmod(0o755)

    def run_dev(self):
        return subprocess.run(["bash", str(self.root / "scripts/dev/run_app.sh")],
                              env=self.env, capture_output=True, text=True, timeout=30)

    def run_asset_verifier(self):
        env = self.env.copy()
        env.update(REQUIRE_MEETING_ECHO_ASSETS="1",
                   MACPARAKEET_MEETING_ECHO_MODEL_NAME="localvqe-v1.4-aec-200K-f32.gguf")
        return subprocess.run(
            ["bash", str(self.root / "scripts/dist/verify_meeting_echo_assets.sh"),
             str(self.app)],
            env=env, capture_output=True, text=True, timeout=30)

    def test_required_asset_verification_fails_without_library(self):
        model = self.app / "Contents/Resources/MeetingEchoSuppression/localvqe-v1.4-aec-200K-f32.gguf"
        model.parent.mkdir(parents=True)
        model.touch()
        result = self.run_asset_verifier()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("assets must be bundled together", result.stderr)

    def test_required_asset_verification_fails_without_model(self):
        library = self.app / "Contents/Frameworks/liblocalvqe.dylib"
        library.parent.mkdir(parents=True)
        library.touch()
        result = self.run_asset_verifier()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("assets must be bundled together", result.stderr)

    def test_default_launch_fails_without_assets_before_stopping_app(self):
        result = self.run_dev()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("asset paths are unset", result.stderr)
        self.assertNotIn("pkill", self.calls.read_text())

    def test_optional_release_setting_does_not_disable_dev_gate(self):
        self.env["REQUIRE_MEETING_ECHO_ASSETS"] = "0"
        result = self.run_dev()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("asset paths are unset", result.stderr)
        self.assertNotIn("pkill", self.calls.read_text())

    def test_explicit_opt_out_warns_and_removes_stale_model(self):
        stale = self.app / "Contents/Resources/MeetingEchoSuppression/old.gguf"
        stale.parent.mkdir(parents=True)
        stale.touch()
        self.env["BUNDLE_MEETING_ECHO_ASSETS"] = "0"
        result = self.run_dev()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("echo cancellation is disabled", result.stderr)
        self.assertFalse(stale.exists())
        self.assertIn("pkill", self.calls.read_text())

    def test_required_assets_cannot_be_disabled(self):
        self.env.update(BUNDLE_MEETING_ECHO_ASSETS="0", REQUIRE_MEETING_ECHO_ASSETS="1")
        result = self.run_dev()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("pkill", self.calls.read_text())

    @unittest.skipUnless(sys.platform == "darwin", "Mach-O runtime fixture")
    def test_runtime_probe_blocks_broken_model_and_accepts_working_runtime(self):
        # Real Mach-O fixture and real dlopen/model-init/frame processing; only
        # external build, signing, and GUI process operations are stubbed.
        source = self.root / "fixture.c"
        source.write_text('''
#include <stdint.h>
#include <stdio.h>
uintptr_t localvqe_new(const char *path) {
    FILE *f = fopen(path, "r"); if (!f) return 0;
    int c = fgetc(f); fclose(f); return c == 'G' ? 1 : 0;
}
void localvqe_reset(uintptr_t c) {}
void localvqe_free(uintptr_t c) {}
int32_t localvqe_process_frame_f32(uintptr_t c, const float *m,
    const float *r, int32_t n, float *o) {
    for (int i = 0; i < n; i++) o[i] = 0; return 0;
}
''')
        library = self.root / "liblocalvqe.dylib"
        subprocess.run(["xcrun", "clang", "-dynamiclib", str(source),
                        "-Wl,-install_name,@rpath/liblocalvqe.dylib", "-o", str(library)], check=True)
        model = self.root / "fixture.gguf"
        self.env.update(MACPARAKEET_MEETING_ECHO_LIBRARY=str(library),
                        MACPARAKEET_MEETING_ECHO_MODEL=str(model))
        for content, success in ((b"Bad model", False), (b"Good model", True)):
            with self.subTest(success=success):
                model.write_bytes(content)
                self.env["MACPARAKEET_MEETING_ECHO_MODEL_SHA256"] = hashlib.sha256(content).hexdigest()
                self.calls.write_text("")
                result = self.run_dev()
                self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
                self.assertEqual("pkill" in self.calls.read_text(), success)
                if success:
                    self.assertIn("initialized and processed a frame", result.stdout)
                else:
                    self.assertIn("model initialization failed", result.stderr)

if __name__ == "__main__":
    unittest.main()

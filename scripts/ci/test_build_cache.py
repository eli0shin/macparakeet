import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from build_cache import INPUTS, LANES, cache_key


class CacheKeyTests(unittest.TestCase):
    def setUp(self):
        self.context = {"swift": "6.0.2", "xcode": "16.1", "sdk": "24B81",
                        "architecture": "arm64", "workspace": "/runner/repo",
                        "os": "23H311", "developer_dir": "/Applications/Xcode_16.1.app"}
        self.inputs = {path: f"hash:{path}" for path in INPUTS}

    def key(self, lane="debug-tests", context=None, inputs=None):
        return cache_key(lane, context or self.context, inputs or self.inputs)

    def test_lanes_are_separate(self):
        self.assertEqual(len({self.key(lane) for lane in LANES}), 3)
        with self.assertRaises(ValueError):
            self.key("unknown")

    def test_every_compatibility_input_invalidates(self):
        for field in self.context:
            with self.subTest(field=field):
                changed = dict(self.context, **{field: "changed"})
                self.assertNotEqual(self.key(), self.key(context=changed))
        for path in self.inputs:
            with self.subTest(path=path):
                changed = dict(self.inputs, **{path: "changed"})
                self.assertNotEqual(self.key(), self.key(inputs=changed))

    def test_order_is_stable_and_source_commits_are_not_cache_keys(self):
        self.assertEqual(self.key(), self.key(context=dict(reversed(list(self.context.items())))))
        self.assertIn("Package.swift", INPUTS)
        self.assertIn("Package.resolved", INPUTS)
        self.assertIn(".github/workflows/ci.yml", INPUTS)
        self.assertFalse(any(path.startswith(("Sources/", "Tests/")) for path in INPUTS))


@unittest.skipUnless(os.environ.get("CI_SWIFT_CACHE_INTEGRATION") == "1",
                     "Enable explicitly on a Swift runner; no Swift build in the cheap Linux gate")
class SwiftPMCacheIntegrationTests(unittest.TestCase):
    def test_restored_build_reuses_dependency_but_compiles_changed_source(self):
        # A local tagged Git dependency exercises the real .build/checkouts
        # layout without network calls or touching this checkout's build state.
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            dependency = base / "dependency"
            root = base / "app"
            (dependency / "Sources/CacheDependency").mkdir(parents=True)
            (root / "Sources/CacheProbe").mkdir(parents=True)
            (dependency / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CacheDependency",
    products: [.library(name: "CacheDependency", targets: ["CacheDependency"])],
    targets: [.target(name: "CacheDependency")])
''')
            (dependency / "Sources/CacheDependency/Value.swift").write_text(
                'public func dependencyValue() -> String { "dependency-v1" }\n')
            def run(command, cwd=root):
                result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, timeout=120)
                self.assertEqual(result.returncode, 0, result.stdout)
                return result.stdout
            run(["git", "init", "-q"], dependency)
            run(["git", "add", "."], dependency)
            run(["git", "-c", "user.name=Cache Test", "-c", "user.email=cache@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-qm", "fixture"], dependency)
            run(["git", "tag", "1.0.0"], dependency)
            (root / "Package.swift").write_text(f'''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CacheProbe",
    dependencies: [.package(url: "{dependency.as_uri()}", exact: "1.0.0")],
    targets: [.executableTarget(name: "CacheProbe",
        dependencies: [.product(name: "CacheDependency", package: "dependency")])])
''')
            source = root / "Sources/CacheProbe/main.swift"
            source.write_text('import CacheDependency\nprint(dependencyValue() + " app-v1")\n')
            build = ["swift", "build", "--cache-path", str(base / "swiftpm-cache")]
            cold = run(build)
            self.assertIn("Compiling CacheDependency", cold)
            binary = root / ".build/debug/CacheProbe"
            self.assertEqual(run([str(binary)]).strip(), "dependency-v1 app-v1")
            objects = list((root / ".build/debug/CacheDependency.build").glob("*.o"))
            self.assertTrue(objects)
            stamps = {p.name: p.stat().st_mtime_ns for p in objects}

            # Archive/extract preserves build and dependency mtimes. Unlike a
            # source-time restoration scheme, checked-in source remains fresh.
            # actions/cache uses GNU tar's POSIX/PAX format. Python tarfile's
            # float mtime conversion can lose nanoseconds and cause recompiles.
            tar = shutil.which("gtar") or "tar"
            archive = base / "compiled.tar"
            run([tar, "--format=pax", "-cf", str(archive), ".build"])
            shutil.rmtree(root / ".build")
            run([tar, "-xf", str(archive)])
            source.write_text('import CacheDependency\nprint(dependencyValue() + " app-v2")\n')
            restored = {p.name: p.stat().st_mtime_ns for p in objects}
            self.assertEqual(stamps, restored, "Archive must preserve object mtimes exactly")
            warm = run(build)
            self.assertNotIn("Compiling CacheDependency", warm)
            self.assertEqual({p.name: p.stat().st_mtime_ns for p in objects}, restored)
            self.assertEqual(run([str(binary)]).strip(), "dependency-v1 app-v2")
            print("Restored SwiftPM state: dependency objects reused; changed source executed as app-v2")


if __name__ == "__main__":
    unittest.main()

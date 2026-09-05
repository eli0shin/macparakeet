#!/usr/bin/env python3
"""Fingerprint compatible SwiftPM build state; source changes still rebuild."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


# Build flags and gated dependency routes live in the workflow. Include the
# cache implementation itself so policy changes cannot reuse an old archive.
INPUTS = (
    "Package.swift",
    "Package.resolved",
    ".github/workflows/ci.yml",
    ".github/actions/setup-swift/action.yml",
    "scripts/ci/build_cache.py",
)
LANES = ("debug-tests", "swift6", "release")


def cache_key(lane, context, inputs):
    if lane not in LANES:
        raise ValueError(f"Unknown build lane: {lane}")
    # Stable within one dependency/toolchain configuration. Do not create a
    # multi-GB archive for every source commit; SwiftPM checks current sources.
    payload = {"lane": lane, "context": context, "inputs": inputs}
    digest = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
    return f"swiftpm-build-v1-{lane}-{digest}"


def fingerprint(root, lane):
    commands = {
        "swift": ["xcrun", "swift", "--version"],
        "xcode": ["xcodebuild", "-version"],
        "developer_dir": ["xcode-select", "-p"],
        "sdk": ["xcrun", "--sdk", "macosx", "--show-sdk-build-version"],
        "os": ["sw_vers", "-buildVersion"],
        "architecture": ["uname", "-m"],
    }
    context = {name: subprocess.check_output(command, text=True).strip()
               for name, command in commands.items()}
    # Swift module caches and llbuild state contain absolute paths.
    context["workspace"] = str(root.resolve())
    inputs = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in INPUTS}
    return cache_key(lane, context, inputs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lane", choices=LANES, required=True)
    args = parser.parse_args()
    key = fingerprint(Path.cwd(), args.lane)
    print(f"Compiled SwiftPM cache key: {key}")
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        print(f"key={key}", file=output)


if __name__ == "__main__":
    main()

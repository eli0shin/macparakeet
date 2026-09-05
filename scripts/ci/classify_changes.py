#!/usr/bin/env python3
"""Keep prose-only PRs cheap; unknown inputs still receive code checks."""

import os
from pathlib import PurePosixPath
import subprocess


def classify(paths):
    code = False
    release = False
    for path in paths:
        p = PurePosixPath(path)
        prose = p.suffix == ".md" and (
            len(p.parts) == 1
            or p.parts[0] in {"docs", "plans", "spec", "integrations"}
            or (p.parts[0] == "Sources" and p.name == "README.md")
        )
        if prose:
            continue
        code = True
        release |= (
            path in {"Package.swift", "Package.resolved"}
            or p.parts[0] in {"Assets", ".github"}
            or path.startswith(("scripts/dist/", "scripts/ci/"))
            or "Resources" in p.parts
            or any(part.endswith((".xcodeproj", ".xcworkspace")) for part in p.parts)
            or p.suffix in {".plist", ".entitlements", ".xcconfig"}
        )
    return {"code": code, "release": release}


def main():
    if os.environ.get("GITHUB_EVENT_NAME") == "pull_request":
        base = os.environ["PR_BASE_SHA"]
        # Include both sides of renames and the full PR, not only the last commit.
        changed = subprocess.check_output(
            ["git", "diff", "--name-only", "--no-renames", "-z", f"{base}...HEAD"]
        ).decode().split("\0")
        result = classify(path for path in changed if path)
    else:
        # main and manual validation retain release coverage.
        result = {"code": True, "release": True}
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        for key, value in result.items():
            line = f"{key}={str(value).lower()}"
            print(line)
            print(line, file=output)


if __name__ == "__main__":
    main()

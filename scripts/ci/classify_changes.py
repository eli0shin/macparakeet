#!/usr/bin/env python3
"""Keep prose-only PRs cheap; unknown inputs still receive code checks."""

import os
from pathlib import PurePosixPath
import subprocess


def ignored_for_automation(path):
    p = PurePosixPath(path)
    return bool(p.parts) and (
        p.parts[0] in {".tickets", "docs", "plans", "spec", "integrations"}
        or (len(p.parts) == 1 and p.suffix == ".md")
        or (p.parts[0] == "Sources" and p.name == "README.md")
    )


def classify(paths):
    code = False
    release = False
    shipping = False
    for path in paths:
        p = PurePosixPath(path)
        if ignored_for_automation(path):
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
        non_shipping = (
            p.suffix == ".md"
            or p.parts[0] in {
                "Tests", "docs", "plans", "spec", ".tickets", "benchmarks", ".github"
            }
            or path.startswith(("scripts/ci/", "scripts/dev/"))
        )
        shipping |= not non_shipping and (
            path in {"Package.swift", "Package.resolved"}
            or p.parts[0] in {"Sources", "Assets"}
            or path.startswith("scripts/dist/")
            or "Resources" in p.parts
            or p.suffix in {".plist", ".entitlements", ".xcconfig"}
        )
    return {"code": code, "release": release, "shipping": shipping}


def main():
    event = os.environ.get("GITHUB_EVENT_NAME")
    if event in {"pull_request", "push"}:
        if event == "pull_request":
            revision = f"{os.environ['PR_BASE_SHA']}...HEAD"
        else:
            revision = f"{os.environ['PUSH_BASE_SHA']}..{os.environ['GITHUB_SHA']}"
        # Include both sides of renames and the complete PR or push.
        changed = subprocess.check_output(
            ["git", "diff", "--name-only", "--no-renames", "-z", revision]
        ).decode().split("\0")
        result = classify(path for path in changed if path)
        # Every non-documentation main push retains complete release validation.
        if event == "push" and result["code"]:
            result["release"] = True
    else:
        # Manual validation retains complete coverage.
        result = {"code": True, "release": True, "shipping": True}
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        for key, value in result.items():
            line = f"{key}={str(value).lower()}"
            print(line)
            print(line, file=output)


if __name__ == "__main__":
    main()

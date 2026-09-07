#!/usr/bin/env python3
"""Plan one tagged GitHub release from the repository history."""

import argparse
import os
import re
import subprocess
from dataclasses import dataclass

from classify_changes import classify


VERSION_TAG = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")


@dataclass(frozen=True)
class ReleasePlan:
    should_release: bool
    tag: str = ""
    version: str = ""


def next_tag(previous_tag, commit_messages):
    match = VERSION_TAG.fullmatch(previous_tag)
    if not match:
        raise ValueError(f"invalid previous version tag: {previous_tag}")

    major, minor, patch = map(int, match.groups())
    messages = "\n".join(commit_messages)
    if "[major]" in messages:
        major, minor, patch = major + 1, 0, 0
    elif "[minor]" in messages:
        minor, patch = minor + 1, 0
    else:
        patch += 1
    return f"v{major}.{minor}.{patch}"


def make_plan(previous_tag, changed_paths, commit_messages):
    if not classify(changed_paths)["shipping"]:
        return ReleasePlan(should_release=False)
    tag = next_tag(previous_tag, commit_messages)
    return ReleasePlan(should_release=True, tag=tag, version=tag.removeprefix("v"))


def git(*arguments):
    return subprocess.check_output(["git", *arguments], text=True).strip()


def latest_version_tag(head):
    tags = git("tag", "--merged", head, "--sort=-version:refname").splitlines()
    return next((tag for tag in tags if VERSION_TAG.fullmatch(tag)), "")


def repository_plan(head):
    previous_tag = latest_version_tag(head)
    if not previous_tag:
        raise RuntimeError("no vX.Y.Z baseline tag is reachable from the release commit")
    changed_paths = git(
        "diff", "--name-only", "--no-renames", "-z", f"{previous_tag}..{head}"
    ).split("\0")
    messages = git("log", "--format=%B%x00", f"{previous_tag}..{head}").split("\0")
    return make_plan(
        previous_tag,
        (path for path in changed_paths if path),
        (message for message in messages if message),
    )


def write_outputs(plan):
    lines = [
        f"should_release={str(plan.should_release).lower()}",
        f"tag={plan.tag}",
        f"version={plan.version}",
    ]
    for line in lines:
        print(line)
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as output:
            output.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--head", default="HEAD")
    args = parser.parse_args()
    write_outputs(repository_plan(args.head))


if __name__ == "__main__":
    main()

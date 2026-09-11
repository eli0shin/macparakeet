#!/usr/bin/env python3
"""Validate the stable merge gate, including expected skips."""

import json
import os


def check(needs):
    if needs["preflight"]["result"] != "success":
        raise ValueError("Preflight checks or change classification failed")

    code = needs["preflight"]["outputs"].get("code")
    if code not in ("true", "false"):
        raise ValueError("Missing code-change classification")

    expected = "success" if code == "true" else "skipped"
    result = needs["test_suite"]["result"]
    if result != expected:
        raise ValueError(f"test_suite: expected {expected}, got {result}")


if __name__ == "__main__":
    check(json.loads(os.environ["NEEDS"]))
    print("All required CI checks passed")

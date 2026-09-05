#!/usr/bin/env python3
"""Validate the stable merge gate, including expected skips."""

import json
import os


def check(needs):
    if needs["changes"]["result"] != "success":
        raise ValueError("Change classification or CI script checks failed")
    outputs = needs["changes"]["outputs"]
    for flag, jobs in [("code", ["debug-tests", "swift6"]), ("release", ["release"])]:
        if outputs.get(flag) not in ("true", "false"):
            raise ValueError(f"Missing classification: {flag}")
        expected = "success" if outputs[flag] == "true" else "skipped"
        for job in jobs:
            result = needs[job]["result"]
            if result != expected:
                raise ValueError(f"{job}: expected {expected}, got {result}")


if __name__ == "__main__":
    check(json.loads(os.environ["NEEDS"]))
    print("All required CI checks passed")

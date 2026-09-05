#!/usr/bin/env python3
"""Run already-built macOS tests in a few processes, not one per test.

XCTest classes stay together. Every discovered case must be assigned once and
its shard's executed count must match. Swift Testing runs separately, once.
"""

import argparse
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import subprocess
import time


def parse_tests(output):
    tests = []
    for line in output.splitlines():
        line = line.strip()
        if not line:
            continue
        if not re.fullmatch(r"[^\s/]+\.[^\s/]+/[^\s/]+", line):
            raise ValueError(f"Unexpected XCTest discovery output: {line!r}")
        tests.append(line)
    if not tests or len(tests) != len(set(tests)):
        raise ValueError("XCTest discovery must contain nonempty, unique test cases")
    return tests


def partition(tests, workers):
    if workers < 1:
        raise ValueError("workers must be positive")
    classes = defaultdict(list)
    for test in tests:
        classes[test.split("/", 1)[0]].append(test)
    shards = [[] for _ in range(min(workers, len(classes)))]
    # Largest classes first; stable ties make assignments reproducible.
    for name in sorted(classes, key=lambda name: (-len(classes[name]), name)):
        shard = min(shards, key=len)
        shard.extend(sorted(classes[name]))
    return shards


def executed_count(output):
    matches = re.findall(r"Executed (\d+) tests?, with", output)
    return int(matches[-1]) if matches else None


def run_command(name, command, log_dir, timeout, expected=None):
    start = time.monotonic()
    path = log_dir / f"{name}.log"
    error = None
    with path.open("w", encoding="utf-8") as log:
        try:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
            code = result.returncode
        except (subprocess.TimeoutExpired, OSError) as exc:
            code = 1
            error = str(exc)
            print(error, file=log)
    output = path.read_text(encoding="utf-8", errors="replace")
    actual = executed_count(output) if expected is not None else None
    if expected is not None and actual != expected:
        code = 1
        error = f"Expected {expected} XCTest cases, executed {actual}"
    seconds = round(time.monotonic() - start, 2)
    print(f"{name}: {seconds}s, exit={code}, tests={actual}, log={path}", flush=True)
    if code:
        print(error or f"{name} failed", flush=True)
        # Assertions can precede thousands of later passing cases. Preserve
        # the full failed process output even if artifact upload is unavailable.
        print(output, flush=True)
    return {"name": name, "seconds": seconds, "exit_code": code,
            "expected_tests": expected, "executed_tests": actual, "error": error}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--log-dir", type=Path, default=Path(".ci-logs"))
    parser.add_argument("--timeout", type=int, default=240, help="Seconds per test process")
    parser.add_argument("--filter", help="Regex for focused local verification only")
    args = parser.parse_args()
    if args.workers < 1 or args.timeout < 1:
        parser.error("workers and timeout must be positive")
    args.log_dir.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()

    # SwiftPM supplies discovery; reject unknown output rather than lose coverage.
    listing = subprocess.run(
        ["swift", "test", "list", "--skip-build", "--disable-swift-testing"],
        check=True, capture_output=True, text=True, timeout=60,
    )
    (args.log_dir / "test-discovery.log").write_text(listing.stdout + listing.stderr)
    tests = parse_tests(listing.stdout)
    if args.filter:
        tests = [test for test in tests if re.search(args.filter, test)]
        if not tests:
            raise ValueError("Filter selected no XCTest cases")
    bundles = list(Path(".build/debug").glob("*.xctest"))
    if len(bundles) != 1:
        raise ValueError(f"Expected one SwiftPM XCTest bundle, found {bundles}")
    shards = partition(tests, args.workers)
    (args.log_dir / "test-shards.json").write_text(json.dumps(shards, indent=2) + "\n")
    commands = []
    for index, shard in enumerate(shards):
        classes = sorted({test.split("/", 1)[0] for test in shard})
        # A focused filter may select only part of a class. Use exact case names
        # in that mode; normal CI uses short class selectors for the full suite.
        selectors = sorted(shard) if args.filter else classes
        command = ["xcrun", "xctest", "-XCTest", ",".join(selectors), str(bundles[0])]
        commands.append((f"xctest-{index + 1}", command, len(shard)))
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(run_command, name, command, args.log_dir, args.timeout, count)
                   for name, command, count in commands]
        results = [future.result() for future in futures]

    # Do not omit native Swift Testing suites or run them once per XCTest shard.
    command = ["swift", "test", "--skip-build", "--disable-xctest"]
    if args.filter:
        command += ["--filter", args.filter]
    results.append(run_command("swift-testing", command, args.log_dir, args.timeout))
    summary = {"seconds": round(time.monotonic() - start, 2),
               "xctest_cases": len(tests), "results": results}
    (args.log_dir / "test-timings.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"All test processes: {summary['seconds']}s", flush=True)
    return int(any(result["exit_code"] != 0 for result in results))


if __name__ == "__main__":
    raise SystemExit(main())

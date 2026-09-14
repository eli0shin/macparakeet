#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_FILTER="MacParakeetTests.FinalTranscriptDetailPerformanceTests/testProductionRendererReportsReleaseInteractionCPU"
INITIAL_READY_MS="${INITIAL_READY_MS:-1000}"
INITIAL_FRAME_MS="${INITIAL_FRAME_MS:-250}"
INTERACTION_FRAME_MS="${INTERACTION_FRAME_MS:-16}"
TEST_TIMEOUT_SECONDS="${TEST_TIMEOUT_SECONDS:-90}"

usage() {
  cat <<'EOF'
usage: scripts/dev/check_final_transcript_detail_performance.sh

Builds the test bundle with release optimization and drives TranscriptResultView
with a public synthetic 1,200-Reading-Turn, 72,000-word meeting in Reading and
Text modes. It reports initial readiness, ordinary scrolling, playback ticks,
find input, and settled find presentation.

The command fails when initial readiness reaches 1,000 ms, one initial main-run-
loop update reaches 250 ms, or an interaction update reaches 16 ms. Known gaps
and profiler evidence are in docs/final-transcript-detail-performance.md.

Environment:
  INITIAL_READY_MS       Initial main-thread CPU limit, default 1000.
  INITIAL_FRAME_MS       Initial update CPU limit, default 250.
  INTERACTION_FRAME_MS   Scroll, playback, find-input, and settled-find limit,
                         default 16.
  TEST_TIMEOUT_SECONDS   Release test-process watchdog, default 90.
EOF
}

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

cd "$ROOT_DIR"

# Compile outside the watchdog. SwiftPM must compile every test target before
# XCTest can load the optimized bundle. Invoking the bundle directly also avoids
# running unrelated executable products during release test discovery.
swift build -c release --build-tests -Xswiftc -enable-testing
release_bin_path="$(swift build -c release --show-bin-path)"
test_bundle="$release_bin_path/MacParakeetPackageTests.xctest"

output_file="$(mktemp -t macparakeet-final-transcript.XXXXXX)"
trap 'rm -f "$output_file"' EXIT

set +e
python3 - "$TEST_TIMEOUT_SECONDS" "$output_file" "$TEST_FILTER" "$test_bundle" <<'PY'
import os
import subprocess
import sys

timeout = float(sys.argv[1])
output_path = sys.argv[2]
test_filter = sys.argv[3]
test_bundle = sys.argv[4]
environment = dict(os.environ)
environment["MACPARAKEET_FINAL_TRANSCRIPT_PERFORMANCE"] = "1"
command = ["xcrun", "xctest", "-XCTest", test_filter, test_bundle]
try:
    result = subprocess.run(
        command,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
        check=False,
    )
    output = result.stdout
    return_code = result.returncode
except subprocess.TimeoutExpired as error:
    output = error.stdout or ""
    if isinstance(output, bytes):
        output = output.decode(errors="replace")
    output += f"\nerror: final transcript performance test exceeded {timeout:g} seconds\n"
    return_code = 124

with open(output_path, "w", encoding="utf-8") as output_file:
    output_file.write(output)
print(output, end="")
sys.exit(return_code)
PY
test_status=$?
set -e

if [[ "$test_status" -ne 0 ]]; then
  exit "$test_status"
fi

python3 - "$output_file" "$INITIAL_READY_MS" "$INITIAL_FRAME_MS" "$INTERACTION_FRAME_MS" <<'PY'
import re
import sys

path, initial_ready_raw, initial_frame_raw, interaction_raw = sys.argv[1:]
limits = {
    "initial_total_ms": float(initial_ready_raw),
    "initial_max_frame_ms": float(initial_frame_raw),
    "scroll_max_frame_ms": float(interaction_raw),
    "playback_max_tick_ms": float(interaction_raw),
    "find_input_max_ms": float(interaction_raw),
    "find_settled_max_frame_ms": float(interaction_raw),
}
rows = []
with open(path, encoding="utf-8") as source:
    for line in source:
        if not line.startswith("FINAL_TRANSCRIPT_PERF "):
            continue
        fields = dict(re.findall(r"([a-z0-9_]+)=([^ ]+)", line))
        rows.append(fields)

if {row.get("mode") for row in rows} != {"reading", "text"}:
    print("error: release test did not report Reading and Text metrics", file=sys.stderr)
    sys.exit(1)

failed = False
for row in rows:
    mode = row["mode"]
    print(f"{mode.capitalize()} mode ({row['turns']} turns, {row['words']} words, {row['utf16']} UTF-16 units)")
    for key, limit in limits.items():
        value = float(row[key])
        result = "PASS" if value < limit else "FAIL"
        print(f"  {key}: {value:.3f} ms (limit: < {limit:g} ms) [{result}]")
        failed |= value >= limit
    print(f"  settled find matches: {row['matches']}")

if failed:
    print(
        "error: final transcript detail missed a responsiveness criterion; "
        "see docs/final-transcript-detail-performance.md",
        file=sys.stderr,
    )
    sys.exit(1)
PY

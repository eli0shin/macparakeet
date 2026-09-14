#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
THRESHOLD_MS="${THRESHOLD_MS:-16}"
INITIAL_THRESHOLD_MS="${INITIAL_THRESHOLD_MS:-750}"
TEST_TIMEOUT_SECONDS="${TEST_TIMEOUT_SECONDS:-30}"
TEST_FILTER="MeetingReadingTurnScrollingTests/testRepresentativeMeetingReportsMainThreadFrameCPU"

usage() {
  cat <<'EOF'
usage: scripts/dev/check_transcript_scrolling_performance.sh

Builds the tests, drives the production AppKit transcript renderer with 1,200
variable-height Reading Turns, and fails if initial main-thread work reaches
750 ms or one ordinary 120-point scroll step reaches 16 ms. The test process also
fails if it does not return within 30 seconds.

Environment:
  THRESHOLD_MS         Frame CPU threshold, default 16.
  INITIAL_THRESHOLD_MS Initial CPU threshold, default 750.
  TEST_TIMEOUT_SECONDS Test-process watchdog, default 30.
EOF
}

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

cd "$ROOT_DIR"

# Build outside the watchdog so a cold dependency build cannot look like a UI stall.
swift test list >/dev/null

output_file="$(mktemp -t macparakeet-transcript-scroll.XXXXXX)"
trap 'rm -f "$output_file"' EXIT

set +e
python3 - "$TEST_TIMEOUT_SECONDS" "$output_file" "$TEST_FILTER" <<'PY'
import subprocess
import sys

timeout = float(sys.argv[1])
output_path = sys.argv[2]
test_filter = sys.argv[3]
command = ["swift", "test", "--skip-build", "--filter", test_filter]
try:
    result = subprocess.run(
        command,
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
    output += f"\nerror: transcript scrolling did not return within {timeout:g} seconds\n"
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

initial_ms="$(sed -n 's/.*TRANSCRIPT_INITIAL_THREAD_CPU_MS=\([0-9][0-9.]*\).*/\1/p' "$output_file" | tail -1)"
measured_ms="$(sed -n 's/.*TRANSCRIPT_SCROLL_MAX_FRAME_THREAD_CPU_MS=\([0-9][0-9.]*\).*/\1/p' "$output_file" | tail -1)"
if [[ -z "$initial_ms" || -z "$measured_ms" ]]; then
  echo "error: transcript renderer test did not report both measurements" >&2
  exit 1
fi

python3 - "$initial_ms" "$INITIAL_THRESHOLD_MS" "$measured_ms" "$THRESHOLD_MS" <<'PY'
import sys

initial = float(sys.argv[1])
initial_threshold = float(sys.argv[2])
measured = float(sys.argv[3])
threshold = float(sys.argv[4])
print(f"Transcript initial main-thread CPU: {initial:.3f} ms (limit: < {initial_threshold:g} ms)")
print(f"Transcript scroll worst main-thread frame: {measured:.3f} ms (limit: < {threshold:g} ms)")
if initial >= initial_threshold:
    print("error: transcript initial rendering exceeded the threshold", file=sys.stderr)
    sys.exit(1)
if measured >= threshold:
    print("error: transcript scrolling exceeded the frame-latency threshold", file=sys.stderr)
    sys.exit(1)
PY

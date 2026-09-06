#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

repetitions="${1:-120}"
workers="${2:-6}"
if ! [[ "$repetitions" =~ ^[1-9][0-9]*$ && "$workers" =~ ^[1-9][0-9]*$ ]]; then
    echo "Usage: $0 [positive-repetitions] [positive-workers]" >&2
    exit 2
fi

swift build --build-tests >/dev/null
bin_path="$(swift build --show-bin-path)"
bundles=("$bin_path"/*.xctest)
if [[ ${#bundles[@]} -ne 1 || ! -d "${bundles[0]}" ]]; then
    echo "Expected one XCTest bundle in $bin_path" >&2
    exit 1
fi

selector="MacParakeetTests.AudioRecorderFormatChangeTests/testSharedModeStartAfterStopDuringFirstStartSucceeds"
log_dir="$(mktemp -d "${TMPDIR:-/tmp}/macparakeet-shared-audio-restart.XXXXXX")"
export selector log_dir
bundle="${bundles[0]}"
export bundle

# The child shell reads the exported variables inside this single-quoted program.
# shellcheck disable=SC2016
seq 1 "$repetitions" | xargs -P "$workers" -I{} bash -c '
    set +e
    xcrun xctest -XCTest "$selector" "$bundle" >"$log_dir/{}.log" 2>&1
    echo $? >"$log_dir/{}.status"
'

failures=0
for status_file in "$log_dir"/*.status; do
    if [[ "$(<"$status_file")" != "0" ]]; then
        failures=$((failures + 1))
    fi
done
passes=$((repetitions - failures))
echo "Shared audio restart stress: passes=$passes failures=$failures total=$repetitions workers=$workers"

if [[ "$failures" -gt 0 ]]; then
    echo "Failure logs: $log_dir" >&2
    for status_file in "$log_dir"/*.status; do
        if [[ "$(<"$status_file")" != "0" ]]; then
            first_log="${status_file%.status}.log"
            break
        fi
    done
    grep -E -C 3 'error:|failed' "$first_log" >&2 || true
    exit 1
fi

rm -rf "$log_dir"

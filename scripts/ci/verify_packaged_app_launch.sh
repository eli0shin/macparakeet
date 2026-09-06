#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
LAUNCH_SECONDS="${MACPARAKEET_PACKAGED_LAUNCH_SECONDS:-3}"
TEMP_ROOT="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/macparakeet-packaged-launch.XXXXXX")"
COPIED_APP="$TEMP_ROOT/MacParakeet.app"
APP_PID=""

fail() {
  echo "Error: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    sleep 0.2
    kill -9 "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

[[ -d "$APP_PATH/Contents" ]] || fail "expected MacParakeet.app path"
[[ "$LAUNCH_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "MACPARAKEET_PACKAGED_LAUNCH_SECONDS must be numeric"

# Launch a copy outside the checkout. This prevents the smoke from succeeding
# because it is running the assembled app in its build-product directory.
if [[ -x /usr/bin/ditto ]]; then
  /usr/bin/ditto "$APP_PATH" "$COPIED_APP"
else
  cp -R "$APP_PATH" "$COPIED_APP"
fi
xattr -dr com.apple.quarantine "$COPIED_APP" 2>/dev/null || true

APP_EXECUTABLE="$COPIED_APP/Contents/MacOS/MacParakeet"
[[ -x "$APP_EXECUTABLE" ]] || fail "copied app executable is missing or not executable"

LAUNCH_LOG="$TEMP_ROOT/launch.log"
mkdir -p "$TEMP_ROOT/home" "$TEMP_ROOT/tmp"
(
  cd "$TEMP_ROOT"
  exec env HOME="$TEMP_ROOT/home" TMPDIR="$TEMP_ROOT/tmp" "$APP_EXECUTABLE"
) >"$LAUNCH_LOG" 2>&1 &
APP_PID=$!
sleep "$LAUNCH_SECONDS"

if ! kill -0 "$APP_PID" 2>/dev/null; then
  wait "$APP_PID" 2>/dev/null || status=$?
  status="${status:-0}"
  if grep -Fq "could not load resource bundle" "$LAUNCH_LOG"; then
    fail "packaged app terminated at startup because a SwiftPM resource bundle could not load (status $status):
$(cat "$LAUNCH_LOG")"
  fi
  fail "packaged app terminated before the ${LAUNCH_SECONDS}s startup smoke completed (status $status):
$(cat "$LAUNCH_LOG")"
fi

echo "Packaged app remained alive for ${LAUNCH_SECONDS}s outside the checkout."

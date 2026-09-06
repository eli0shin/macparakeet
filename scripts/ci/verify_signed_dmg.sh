#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:-dist/MacParakeet.dmg}"
EXPECTED_TEAM_ID="${EXPECTED_TEAM_ID:-}"
EXPECTED_AUTHORITY="${EXPECTED_AUTHORITY:-}"
MOUNT_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/macparakeet-signed-mount.XXXXXX")"
MOUNTED=0

fail() {
  echo "error: $*" >&2
  exit 1
}

cleanup() {
  if [[ "$MOUNTED" == "1" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet || true
  fi
  rm -rf "$MOUNT_DIR"
}
trap cleanup EXIT INT TERM

[[ -n "$EXPECTED_TEAM_ID" ]] || fail "EXPECTED_TEAM_ID is required."
[[ -n "$EXPECTED_AUTHORITY" ]] || fail "EXPECTED_AUTHORITY is required."
[[ -s "$DMG_PATH" ]] || fail "Signed DMG is missing: $DMG_PATH"

hdiutil verify "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"
dmg_signature="$(codesign -dv --verbose=4 "$DMG_PATH" 2>&1)"
grep -Fq "TeamIdentifier=$EXPECTED_TEAM_ID" <<<"$dmg_signature" || fail "The DMG has an unexpected Team ID."
grep -Fq "Authority=$EXPECTED_AUTHORITY" <<<"$dmg_signature" || fail "The DMG has an unexpected signing authority."
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

hdiutil attach "$DMG_PATH" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT_DIR"
MOUNTED=1
APP_PATH="$MOUNT_DIR/MacParakeet.app"
[[ -d "$APP_PATH/Contents" ]] || fail "The DMG does not contain MacParakeet.app."
[[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]] || fail "The DMG has no Applications shortcut."

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
app_signature="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
grep -Fq "TeamIdentifier=$EXPECTED_TEAM_ID" <<<"$app_signature" || fail "The app has an unexpected Team ID."
grep -Fq "Authority=$EXPECTED_AUTHORITY" <<<"$app_signature" || fail "The app has an unexpected signing authority."
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

EXPECTED_TEAM_ID="$EXPECTED_TEAM_ID" EXPECTED_AUTHORITY="$EXPECTED_AUTHORITY" \
  bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/dist/verify_app_privacy_surface.sh" "$APP_PATH"
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/ci/verify_downloadable_app.sh" "$APP_PATH"

echo "Verified signed and notarized DMG: $DMG_PATH"

#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:-dist/MacParakeet-owner-development-build.dmg}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOUNT_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/macparakeet-development-mount.XXXXXX")"
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

[[ -s "$DMG_PATH" ]] || fail "Development DMG is missing: $DMG_PATH"
[[ "$(basename "$DMG_PATH")" == "MacParakeet-owner-development-build.dmg" ]] || \
  fail "Development DMG has an unexpected or ambiguous name."

hdiutil verify "$DMG_PATH"
[[ "$(hdiutil imageinfo -plist "$DMG_PATH" | plutil -extract Format raw -)" == "UDZO" ]] || \
  fail "Development DMG is not a compressed read-only disk image."
hdiutil attach "$DMG_PATH" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT_DIR" >/dev/null
MOUNTED=1

APP_PATH="$MOUNT_DIR/MacParakeet.app"
[[ -d "$APP_PATH/Contents" ]] || fail "The DMG does not contain MacParakeet.app."
[[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]] || \
  fail "The DMG does not contain the Applications shortcut."

while IFS= read -r top_level; do
  case "$(basename "$top_level")" in
    MacParakeet.app|Applications) ;;
    *) fail "The DMG contains an unexpected top-level item: $(basename "$top_level")" ;;
  esac
done < <(find "$MOUNT_DIR" -mindepth 1 -maxdepth 1 -print)

# Bundle-internal links must be relative and must resolve inside the app. The
# top-level Applications shortcut is the one intentional absolute link.
python3 - "$APP_PATH" <<'PY'
import os
from pathlib import Path
import sys

app = Path(sys.argv[1]).resolve()
for directory, directory_names, file_names in os.walk(app, followlinks=False):
    for name in directory_names + file_names:
        path = Path(directory) / name
        if not path.is_symlink():
            continue
        target = os.readlink(path)
        if os.path.isabs(target):
            raise SystemExit(f"absolute bundle symlink: {path.relative_to(app)} -> {target}")
        resolved = (path.parent / target).resolve(strict=True)
        if resolved != app and app not in resolved.parents:
            raise SystemExit(f"bundle symlink escapes app: {path.relative_to(app)} -> {target}")
PY

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

verify_adhoc_signature() {
  local code_path="$1"
  local details
  details="$(codesign -dv --verbose=4 "$code_path" 2>&1)" || fail "Could not read signature: $code_path"
  grep -Fq "Signature=adhoc" <<<"$details" || fail "Code is not ad-hoc signed: $code_path"
  if grep -q '^Authority=' <<<"$details"; then
    fail "Development code unexpectedly has a signing authority: $code_path"
  fi
}

while IFS= read -r -d '' nested_code; do
  codesign --verify --strict --verbose=2 "$nested_code"
  verify_adhoc_signature "$nested_code"
done < <(
  find "$APP_PATH/Contents/Frameworks" -type d \
    \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' \) -print0 2>/dev/null
  find "$APP_PATH/Contents/Frameworks" -type f \
    \( -perm -111 -o -name '*.dylib' \) -print0 2>/dev/null
  find "$APP_PATH/Contents/Resources" -maxdepth 1 -type f \
    \( -name ffmpeg -o -name yt-dlp -o -name node -o -name node-arm64 -o -name node-x86_64 \) -print0
  find "$APP_PATH/Contents/MacOS" -maxdepth 1 -type f -perm -111 -print0
)
verify_adhoc_signature "$APP_PATH"

bash "$ROOT_DIR/scripts/ci/verify_downloadable_app.sh" "$APP_PATH"
echo "Verified ad-hoc-signed owner development DMG: $DMG_PATH"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_PATH="$ROOT_DIR/dist/MacParakeet.app"
DMG_PATH="$ROOT_DIR/dist/MacParakeet-owner-development-build.dmg"
STAGING_DIR=""

fail() {
  echo "error: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$STAGING_DIR" ]]; then
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup EXIT INT TERM

command -v codesign >/dev/null || fail "codesign is required."
command -v hdiutil >/dev/null || fail "hdiutil is required."

cd "$ROOT_DIR"
rm -f "$DMG_PATH"

BUILD_SYSTEM=swiftpm \
BUILD_SOURCE=github-actions-owner-development \
VERSION=0.0.0 \
BUILD_NUMBER="$(date -u +%Y%m%d%H%M%S)" \
  bash scripts/dist/build_app_bundle.sh

[[ -d "$APP_PATH/Contents" ]] || fail "The complete app bundle was not built."

# Replace linker and upstream signatures inside-out. These signatures only make
# the bundle structurally valid. They do not establish an Apple-trusted identity.
SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  while IFS= read -r -d '' code_bundle; do
    codesign --force --sign - "$code_bundle"
  done < <(find "$SPARKLE_FRAMEWORK" -type d \( -name '*.xpc' -o -name '*.app' \) -print0)

  while IFS= read -r -d '' executable; do
    codesign --force --sign - "$executable"
  done < <(find "$SPARKLE_FRAMEWORK/Versions/B" -maxdepth 1 -type f -perm -111 -print0)

  codesign --force --sign - "$SPARKLE_FRAMEWORK"
fi

while IFS= read -r -d '' dylib; do
  codesign --force --sign - "$dylib"
done < <(find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -type f -name '*.dylib' -print0)

while IFS= read -r -d '' helper; do
  codesign --force --sign - "$helper"
done < <(
  find "$APP_PATH/Contents/Resources" -maxdepth 1 -type f \
    \( -name ffmpeg -o -name yt-dlp -o -name node -o -name node-arm64 -o -name node-x86_64 \) -print0
  find "$APP_PATH/Contents/MacOS" -maxdepth 1 -type f -perm -111 \
    ! -name MacParakeet -print0
)

codesign --force --sign - --entitlements scripts/dist/MacParakeet.entitlements "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
bash scripts/ci/verify_downloadable_app.sh "$APP_PATH"

STAGING_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/macparakeet-development-dmg.XXXXXX")"
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/MacParakeet.app"
ln -s /Applications "$STAGING_DIR/Applications"

[[ "$(find "$STAGING_DIR" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" == "2" ]] || \
  fail "Development DMG staging contains unexpected top-level files."

hdiutil create \
  -volname "MacParakeet Owner Development" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO "$DMG_PATH" >/dev/null
[[ -s "$DMG_PATH" ]] || fail "Development DMG was not created."

bash scripts/ci/verify_development_dmg.sh "$DMG_PATH"
echo "Owner-only development artifact is ready: $DMG_PATH"

#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH/Contents" ]]; then
  echo "Error: expected MacParakeet.app path" >&2
  exit 1
fi

RESOURCES="$APP_PATH/Contents/Resources"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/MacParakeet"
CLI="$APP_PATH/Contents/MacOS/macparakeet-cli"
SPARKLE="$APP_PATH/Contents/Frameworks/Sparkle.framework"
FFMPEG="$RESOURCES/ffmpeg"
YTDLP="$RESOURCES/yt-dlp"
APP_RESOURCE_BUNDLE="$RESOURCES/MacParakeet_MacParakeet.bundle"

[[ -d "$APP_RESOURCE_BUNDLE" ]] || {
  echo "Error: SwiftPM app resource bundle is missing from Bundle.main.resourceURL: $APP_RESOURCE_BUNDLE" >&2
  exit 1
}
[[ -x "$APP_EXECUTABLE" ]] || {
  echo "Error: bundled app executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 1
}
[[ -x "$CLI" ]] || {
  echo "Error: bundled CLI is missing or not executable: $CLI" >&2
  exit 1
}
BUILD_BUNDLE_FALLBACKS="$(strings "$APP_EXECUTABLE" | grep -E '/\.build/[^[:space:]]*\.bundle' || true)"
if [[ -n "$BUILD_BUNDLE_FALLBACKS" ]]; then
  echo "Error: packaged app contains a SwiftPM resource fallback into a build checkout" >&2
  exit 1
fi
[[ -d "$SPARKLE" ]] || {
  echo "Error: Sparkle.framework is missing: $SPARKLE" >&2
  exit 1
}

for helper in "$FFMPEG" "$YTDLP"; do
  if [[ ! -x "$helper" ]]; then
    echo "Error: required bundled helper is missing or not executable: $helper" >&2
    exit 1
  fi
done

if [[ -x /usr/bin/true ]] && cmp -s "$FFMPEG" /usr/bin/true; then
  echo "Error: bundled FFmpeg is the /usr/bin/true smoke fixture" >&2
  exit 1
fi

FFMPEG_VERSION_OUTPUT="$("$FFMPEG" -version 2>&1)"
if ! grep -q '^ffmpeg version ' <<<"$FFMPEG_VERSION_OUTPUT"; then
  echo "Error: bundled FFmpeg did not report an FFmpeg version" >&2
  exit 1
fi

YTDLP_VERSION_OUTPUT="$("$YTDLP" --version 2>&1)"
if [[ -z "${YTDLP_VERSION_OUTPUT//[[:space:]]/}" ]]; then
  echo "Error: bundled yt-dlp did not report a version" >&2
  exit 1
fi

CLI_VERSION_OUTPUT="$("$CLI" --version 2>&1)"
if [[ -z "${CLI_VERSION_OUTPUT//[[:space:]]/}" ]]; then
  echo "Error: bundled CLI did not report a version" >&2
  exit 1
fi

NODE_HELPERS=()
if [[ -x "$RESOURCES/node" ]]; then
  NODE_HELPERS+=("$RESOURCES/node")
else
  for helper in "$RESOURCES/node-arm64" "$RESOURCES/node-x86_64"; do
    if [[ ! -x "$helper" ]]; then
      echo "Error: bundled Node runtime is missing or not executable" >&2
      exit 1
    fi
    NODE_HELPERS+=("$helper")
  done
fi

for helper in "${NODE_HELPERS[@]}"; do
  NODE_VERSION_OUTPUT="$("$helper" --version 2>&1)"
  if ! grep -Eq '^v[0-9]+\.' <<<"$NODE_VERSION_OUTPUT"; then
    echo "Error: bundled Node runtime did not report a Node version: $helper" >&2
    exit 1
  fi
done

printf 'FFmpeg: %s\n' "$(head -n 1 <<<"$FFMPEG_VERSION_OUTPUT")"
printf 'yt-dlp: %s\n' "$(head -n 1 <<<"$YTDLP_VERSION_OUTPUT")"
printf 'CLI: %s\n' "$(head -n 1 <<<"$CLI_VERSION_OUTPUT")"
for helper in "${NODE_HELPERS[@]}"; do
  printf '%s: %s\n' "$(basename "$helper")" "$("$helper" --version)"
done

bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify_packaged_app_launch.sh" "$APP_PATH"

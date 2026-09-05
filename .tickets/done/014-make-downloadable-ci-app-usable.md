---
Assigned-To: macparakeet@014-make-downloadable-ci-app-usable
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Make the unsigned CI app artifact a usable development build instead of archiving the release bundle smoke fixture. Main run `33991054004` produced artifact `9976794725`; direct inspection found that `Contents/Resources/ffmpeg` is the copied `/usr/bin/true` executable and that `yt-dlp` and Node are absent because the smoke step sets `FFMPEG_PATH=/usr/bin/true`, `BUNDLE_YTDLP=0`, and `BUNDLE_NODE=0`.

Keep the fast smoke validation if useful, but the published archive must be built with the real runtime helpers expected by a development app. It must remain clearly unsigned and non-notarized. Do not add signing credentials, publish to R2/Sparkle, or claim this is the official DMG.

## Acceptance criteria

- [x] The published app contains a real portable FFmpeg, not `/usr/bin/true` or another fixture.
- [x] The published app contains the runtime helpers required by the normal bundle defaults, including the yt-dlp seed and Node runtime.
- [x] CI verifies helper presence and executes safe helper smoke checks before upload.
- [x] The archive remains limited to `MacParakeet.app`, preserves bundle metadata, and is clearly unsigned and non-notarized.
- [x] CI workflow tests distinguish release-bundle smoke inputs from downloadable-build inputs and prevent fixture helpers from being published.
- [x] Main/manual publication conditions, fast-PR behavior, official distribution flow, and existing log artifacts remain intact.
- [x] Applicable CI checks pass.

## Resolution

Separated the pull-request fixture smoke from the main/manual downloadable build and added fail-closed helper verification. PR #14 merged at `3a83762661c1aa667a5782cb2aebe6e2d7ecccf1`. Main run `33992678869` passed and published artifact `9977231846`. Direct inspection confirmed an app-only archive with preserved executable modes and relative symlinks, FFmpeg 9.0.1, yt-dlp 2026.08.19, Node 24.13.1, no sensitive files, and the expected unsigned/ad-hoc identity.

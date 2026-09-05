---
Assigned-To:
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Make the unsigned CI app artifact a usable development build instead of archiving the release bundle smoke fixture. Main run `33991054004` produced artifact `9976794725`; direct inspection found that `Contents/Resources/ffmpeg` is the copied `/usr/bin/true` executable and that `yt-dlp` and Node are absent because the smoke step sets `FFMPEG_PATH=/usr/bin/true`, `BUNDLE_YTDLP=0`, and `BUNDLE_NODE=0`.

Keep the fast smoke validation if useful, but the published archive must be built with the real runtime helpers expected by a development app. It must remain clearly unsigned and non-notarized. Do not add signing credentials, publish to R2/Sparkle, or claim this is the official DMG.

## Acceptance criteria

- [ ] The published app contains a real portable FFmpeg, not `/usr/bin/true` or another fixture.
- [ ] The published app contains the runtime helpers required by the normal bundle defaults, including the yt-dlp seed and Node runtime.
- [ ] CI verifies helper presence and executes safe helper smoke checks before upload.
- [ ] The archive remains limited to `MacParakeet.app`, preserves bundle metadata, and is clearly unsigned and non-notarized.
- [ ] CI workflow tests distinguish release-bundle smoke inputs from downloadable-build inputs and prevent fixture helpers from being published.
- [ ] Main/manual publication conditions, fast-PR behavior, official distribution flow, and existing log artifacts remain intact.
- [ ] Applicable CI checks pass.

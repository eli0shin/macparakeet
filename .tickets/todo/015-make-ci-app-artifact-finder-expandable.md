---
Assigned-To:
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Fix the downloadable unsigned CI app artifact because macOS Finder/Archive Utility cannot expand the generated ZIP. The affected artifact is `MacParakeet-unsigned-non-notarized` from run `33993288705`, artifact ID `9977391806`. Command-line `ditto -x -k` succeeded during orchestration inspection, but the normal user-facing macOS expansion path fails.

Diagnose the exact archive compatibility problem and publish a Finder-compatible download. Preserve app metadata, executable modes, and framework symlinks. Avoid confusing nested archives if that contributes to the problem. The result must remain clearly unsigned and non-notarized and must not change the official signed DMG flow.

## Acceptance criteria

- [ ] The failure is reproduced through the standard macOS Finder or Archive Utility path.
- [ ] A downloaded GitHub Actions artifact expands successfully through the standard macOS UI path without requiring Terminal commands.
- [ ] The extracted result contains one clearly named `MacParakeet.app` or one standard mountable image containing it, without confusing archive nesting.
- [ ] App and helper executable permissions, framework symlinks, bundle identity, FFmpeg, yt-dlp, and Node remain intact.
- [ ] CI validates the final downloadable file format and extracted contents before upload.
- [ ] Workflow tests cover the archive format, artifact shape, failure behavior, and main/manual-only publication.
- [ ] Documentation gives concise Finder download and installation instructions and states that the build is unsigned and non-notarized.
- [ ] Applicable CI checks pass and the landing artifact is downloaded and inspected through the intended user path.

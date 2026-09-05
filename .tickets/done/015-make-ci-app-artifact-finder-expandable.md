---
Assigned-To: macparakeet@015-make-ci-app-artifact-finder-expandable
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Fix the downloadable unsigned CI app artifact because macOS Finder/Archive Utility cannot expand the generated ZIP. The affected artifact is `MacParakeet-unsigned-non-notarized` from run `33993288705`, artifact ID `9977391806`. Command-line `ditto -x -k` succeeded during orchestration inspection, but the normal user-facing macOS expansion path fails.

Diagnose the exact archive compatibility problem and publish a Finder-compatible download. Preserve app metadata, executable modes, and framework symlinks. Avoid confusing nested archives if that contributes to the problem. The result must remain clearly unsigned and non-notarized and must not change the official signed DMG flow.

## Acceptance criteria

- [x] The failure is reproduced through the standard macOS Finder or Archive Utility path.
- [x] A downloaded GitHub Actions artifact expands successfully through the standard macOS UI path without requiring Terminal commands.
- [x] The extracted result contains one clearly named `MacParakeet.app` or one standard mountable image containing it, without confusing archive nesting.
- [x] App and helper executable permissions, framework symlinks, bundle identity, FFmpeg, yt-dlp, and Node remain intact.
- [x] CI validates the final downloadable file format and extracted contents before upload.
- [x] Workflow tests cover the archive format, artifact shape, failure behavior, and main/manual-only publication.
- [x] Documentation gives concise Finder download and installation instructions and states that the build is unsigned and non-notarized.
- [x] Applicable CI checks pass and the landing artifact is downloaded and inspected through the intended user path.

## Implementation notes

Artifact `9977391806` is a valid GitHub-generated ZIP that contains one
`MacParakeet-unsigned-non-notarized.zip`. GitHub gives the downloaded outer ZIP
the same name as that inner ZIP. Archive Utility must therefore rename or
replace an archive while expanding it, and the user must expand two ZIPs. The
inner `ditto` archive itself passes `unzip -t` and expands with Archive Utility.
The fix replaces the inner ZIP with a compressed disk image, so the GitHub ZIP
expands to one clearly different, Finder-mountable file.

## Resolution

PR #15 merged at `0c6883ec539593b8d354491539322bdeef266e6f`. Main run `33998126320` passed and published artifact `9978769535`. The raw GitHub artifact ZIP passed integrity checks and Archive Utility expanded it to one DMG without a naming collision. The DMG checksum verified and it mounted read-only with `MacParakeet.app` plus the Applications shortcut. Direct inspection confirmed preserved executable modes and framework symlinks, working FFmpeg 9.0.1, yt-dlp 2026.08.19, and Node 24.13.1, no sensitive files, and the expected unsigned/ad-hoc identity.

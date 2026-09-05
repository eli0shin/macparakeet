---
Assigned-To: macparakeet@013-publish-downloadable-mac-app-from-ci
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Publish the app bundle produced by the CI `release` job as a downloadable GitHub Actions artifact. Today CI validates `dist/MacParakeet.app` and then uploads only logs, so a successful `main` build cannot be downloaded and tested.

This artifact is an unsigned, non-notarized development build, not an official MacParakeet release. Preserve the documented signed/notarized DMG release process and do not add signing credentials or implicit network publication. Package the app with a macOS-safe archive method that preserves bundle metadata and executable bits.

## Acceptance criteria

- [x] Successful `release` jobs on `main` and manual workflow runs upload a downloadable archive containing `MacParakeet.app`.
- [x] Pull requests do not publish downloadable app builds.
- [x] The artifact name and documentation clearly identify it as unsigned and non-notarized.
- [x] The archive preserves the app bundle layout, symlinks, metadata, and executable permissions.
- [x] Upload failure fails the applicable release job; missing app output is not silently accepted.
- [x] CI workflow tests cover publication conditions, archive creation, artifact path/name, and retention.
- [x] Existing release validation, fast-PR behavior, signing/notarization documentation, and log artifacts remain intact.
- [x] Applicable CI checks pass and generated artifact contents are inspected.

## Landing artifact finding

Main run `33991054004` passed and published artifact `9976794725`, but direct archive inspection found an unusable media helper: `Contents/Resources/ffmpeg` is `/usr/bin/true`, while yt-dlp and Node are absent. Ticket 014 corrected the published bundle.

## Resolution

PR #13 added the downloadable unsigned app flow at `603a3fdefbe948e8e608332c5ea88078d83fd738`; PR #14 corrected its runtime-helper inputs at `3a83762661c1aa667a5782cb2aebe6e2d7ecccf1`. Main run `33992678869` passed and published inspected artifact `9977231846`. The archive contains only `MacParakeet.app`, preserves executable modes and framework symlinks, includes working FFmpeg, yt-dlp, and Node helpers, contains no sensitive files, and is clearly unsigned and non-notarized.

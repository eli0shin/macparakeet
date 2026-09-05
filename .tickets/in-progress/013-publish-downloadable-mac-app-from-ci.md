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

- [ ] Successful `release` jobs on `main` and manual workflow runs upload a downloadable archive containing `MacParakeet.app`.
- [ ] Pull requests do not publish downloadable app builds.
- [ ] The artifact name and documentation clearly identify it as unsigned and non-notarized.
- [ ] The archive preserves the app bundle layout, symlinks, metadata, and executable permissions.
- [ ] Upload failure fails the applicable release job; missing app output is not silently accepted.
- [ ] CI workflow tests cover publication conditions, archive creation, artifact path/name, and retention.
- [ ] Existing release validation, fast-PR behavior, signing/notarization documentation, and log artifacts remain intact.
- [ ] Applicable CI checks pass and generated artifact contents are inspected.

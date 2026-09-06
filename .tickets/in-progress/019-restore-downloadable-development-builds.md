---
Assigned-To: macparakeet@019-restore-downloadable-development-builds
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Restore a downloadable macOS development build in CI while keeping the protected Developer ID signing/notarization workflow for real distribution. The development artifact is for the repository owner to test, not for public distribution. It must not be presented as signed, notarized, or Gatekeeper-ready.

Build and package the complete app with real FFmpeg, yt-dlp, Node, CLI, Sparkle framework, valid relative symlinks, and the Applications shortcut. Ensure the app bundle has a structurally valid ad-hoc signature instead of the invalid linker-only signature that produced `code has no resources but signature indicates they must be present`. Document the minimum owner-only install procedure, including quarantine removal when macOS requires it. Do not put certificates, credentials, private data, or private paths in Git.

## Acceptance criteria

- [ ] Main and manual CI publish a clearly named development-only artifact without accessing protected release secrets.
- [ ] The GitHub artifact expands with Archive Utility to one Finder-mountable DMG containing the app and Applications shortcut.
- [ ] `codesign --verify --deep --strict` passes for the ad-hoc-signed development app and all nested code has valid signatures.
- [ ] Documentation states that the build is not Developer ID signed or notarized and gives one exact quarantine-removal/install command for owner testing.
- [ ] The development artifact cannot be confused with `MacParakeet-signed-notarized-ci-test` or the official R2/Sparkle release.
- [ ] FFmpeg, yt-dlp, Node, the app, and CLI are executable; yt-dlp still runs after signing.
- [ ] No sensitive or surprising files are packaged.
- [ ] Workflow tests lock event gating, artifact naming, retention, fail-closed packaging, signature verification, and helper verification.
- [ ] Applicable CI checks pass, then the landing artifact is downloaded and verified through Archive Utility, mounting, strict signature checks, helper smokes, quarantine removal, and launch.

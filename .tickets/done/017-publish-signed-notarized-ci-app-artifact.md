---
Assigned-To: macparakeet@017-publish-signed-notarized-ci-app-artifact
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Replace the user-facing unsigned CI development artifact with a Developer ID signed and Apple-notarized DMG that opens on a normal Mac without the “damaged and can’t be opened” error. Direct inspection of artifact `9979332379` showed `codesign --verify --deep --strict` and `spctl --assess` fail with `code has no resources but signature indicates they must be present`; the app has only an ad-hoc linker signature and no Team ID.

Reuse the repository's established distribution signing, nested-helper entitlement, notarization, stapling, privacy-surface, and release-version gates. Provision signing credentials through GitHub Actions secrets and a temporary keychain. Never commit certificates, passwords, API keys, profiles, or other credentials. Pull requests must not receive or use release secrets.

The current machine has an Apple Development identity only, not a Developer ID Application identity. The GitHub repository currently has no Actions secrets or environments. Document the exact certificate and secret setup required from the repository owner, and fail clearly and safely when required credentials are absent.

## Acceptance criteria

- [x] The downloadable DMG and contained app are signed with a Developer ID Application identity and report the expected Team ID.
- [x] The app and DMG are accepted by Apple notarization and have valid stapled tickets.
- [x] `codesign --verify --deep --strict`, `spctl --assess`, and `stapler validate` pass on the downloaded landing artifact.
- [x] Nested Sparkle components, FFmpeg, yt-dlp, Node, app/CLI executables, and optional libraries are signed in the correct order with required entitlements.
- [x] The signed yt-dlp seed executes successfully after signing.
- [x] Signing/notarization runs only for an explicit protected publication path; pull requests and ordinary untrusted events cannot access secrets.
- [x] CI uses an ephemeral keychain and cleans credentials and temporary files even after failure.
- [x] Missing or invalid credentials fail closed without publishing an unsigned artifact under a trusted name.
- [x] The workflow uses an explicit non-sentinel version and increasing build number suitable for signing and notarization.
- [x] Documentation distinguishes this signed test artifact from the official R2/Sparkle release and gives exact secret provisioning and download instructions.
- [x] Workflow tests cover event gating, secret handling, fail-closed publication, verification commands, artifact naming, and retention.
- [x] Applicable CI checks pass, then a protected landing/manual run publishes an artifact that is downloaded and verified through Finder/Gatekeeper.

## Resolution

Protected run `34083591244` completed successfully at `ea064e20366fd164e832a4b60c8475641830524e`. Downloaded artifact `10005566339` matched SHA-256 `2d7f7f89e02f4bd32801b4168bed4c5112770bf401398d11a02f4dbcce31c2a4` and contained exactly one DMG. Direct inspection confirmed Developer ID authority `Developer ID Application: Elimelech Oshinsky (GY6L5GL2Z7)`, Team ID `GY6L5GL2Z7`, valid app and DMG staples, Gatekeeper acceptance as Notarized Developer ID, strict nested signatures, real FFmpeg 9.0.1, yt-dlp 2026.08.19, Node 24.13.1, CLI 3.1.0, app resources, relative symlinks, privacy checks, and an isolated launch outside the checkout. No generated diff was produced by this workflow.

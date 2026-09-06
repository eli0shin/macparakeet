---
Assigned-To:
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

- [ ] The downloadable DMG and contained app are signed with a Developer ID Application identity and report the expected Team ID.
- [ ] The app and DMG are accepted by Apple notarization and have valid stapled tickets.
- [ ] `codesign --verify --deep --strict`, `spctl --assess`, and `stapler validate` pass on the downloaded landing artifact.
- [ ] Nested Sparkle components, FFmpeg, yt-dlp, Node, app/CLI executables, and optional libraries are signed in the correct order with required entitlements.
- [ ] The signed yt-dlp seed executes successfully after signing.
- [ ] Signing/notarization runs only for an explicit protected publication path; pull requests and ordinary untrusted events cannot access secrets.
- [ ] CI uses an ephemeral keychain and cleans credentials and temporary files even after failure.
- [ ] Missing or invalid credentials fail closed without publishing an unsigned artifact under a trusted name.
- [ ] The workflow uses an explicit non-sentinel version and increasing build number suitable for signing and notarization.
- [ ] Documentation distinguishes this signed test artifact from the official R2/Sparkle release and gives exact secret provisioning and download instructions.
- [ ] Workflow tests cover event gating, secret handling, fail-closed publication, verification commands, artifact naming, and retention.
- [ ] Applicable CI checks pass, then a protected landing/manual run publishes an artifact that is downloaded and verified through Finder/Gatekeeper.

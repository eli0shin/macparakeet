---
Assigned-To:
Tags:
  - owner-action
Parent: 017-publish-signed-notarized-ci-app-artifact
Blocked-By: []
---

## What to do

Provision this fork's protected GitHub Actions environment with the Apple credentials required to produce a Developer ID signed and notarized release candidate. The `signed-ci-artifact` environment already exists, requires approval from `eli0shin`, and is limited to `main`. Do not put certificate data, passwords, Apple IDs, private keys, or secret values in Git, ticket text, chat, shell history, or workflow logs.

## Setup

1. In the Apple Developer portal, create a **Developer ID Application** certificate for Elimelech Oshinsky's team `3ZK76CKTXW`. Do not use the existing Apple Development certificate.
2. Install the certificate and its private key on a trusted Mac. Confirm `security find-identity -v -p codesigning` reports the full Developer ID Application identity.
3. Export the certificate and private key as a password-protected `.p12` in a secure temporary location.
4. Create an Apple ID app-specific password for notarization.
5. Provision these exact environment secrets in `signed-ci-artifact`:
   - `DEVELOPMENT_ID_CERTIFICATE_BASE64`
   - `DEVELOPMENT_ID_CERTIFICATE_PASSWORD`
   - `DEVELOPER_ID_APPLICATION_IDENTITY`
   - `APPLE_TEAM_ID`
   - `NOTARY_APPLE_ID`
   - `NOTARY_APP_SPECIFIC_PASSWORD`
6. Use `Developer ID Application: Elimelech Oshinsky (3ZK76CKTXW)` as the expected full identity and `3ZK76CKTXW` as the team ID.
7. Delete the exported `.p12` after GitHub confirms the secrets are stored.
8. Manually run the `CI` workflow on `main`, enable `publish_signed_artifact`, enter a non-sentinel `X.Y.Z` version, and approve the protected environment deployment.
9. Download the generated `MacParakeet-signed-notarized-ci-test` artifact and inspect the actual output.

## Acceptance criteria

- [ ] A valid Developer ID Application certificate and private key exist for team `3ZK76CKTXW`.
- [ ] All six required secrets exist only in the protected `signed-ci-artifact` environment.
- [ ] The environment remains reviewer-protected and limited to `main`.
- [ ] No credential or private key material enters Git, tickets, chat, command history, or logs.
- [ ] A protected manual run completes signing and Apple notarization successfully.
- [ ] The downloaded GitHub ZIP expands with Archive Utility to one DMG.
- [ ] `codesign --verify --deep --strict` passes on the contained app.
- [ ] Signature details report `TeamIdentifier=3ZK76CKTXW` and the configured Developer ID authority.
- [ ] `spctl --assess --type execute --verbose=4` reports an accepted notarized Developer ID app.
- [ ] `xcrun stapler validate` passes for both the app and DMG.
- [ ] FFmpeg, yt-dlp, Node, CLI, resource bundles, relative symlinks, privacy surface, and Applications shortcut are verified from the downloaded DMG.
- [ ] Finder installation and first launch work without quarantine-removal commands.
- [ ] Ticket `017-publish-signed-notarized-ci-app-artifact` is completed only after the downloaded artifact passes all checks.

---
Assigned-To:
Tags:
  - ready-for-agent
Parent: 017-publish-signed-notarized-ci-app-artifact
Blocked-By: []
---

## What to build

Correct the protected signed-artifact workflow for this fork's Apple Developer team. The merged PR #17 documentation and verification hard-code upstream team `FYAF2ZD7RM` and upstream identity `Developer ID Application: Daniel Moon (...)`. The repository owner can only issue certificates for their own team; the installed Apple Development identity confirms team `3ZK76CKTXW` for Elimelech Oshinsky.

Treat the protected environment's `APPLE_TEAM_ID` and `DEVELOPER_ID_APPLICATION_IDENTITY` secrets as the explicit expected identity. Do not weaken verification: prove the imported Developer ID Application certificate, signed app, nested code, DMG, and notarization request all use those configured values. Do not log secret values unnecessarily. Keep pull requests and untrusted events outside the credential boundary.

## Acceptance criteria

- [ ] No signing or verification path requires upstream team `FYAF2ZD7RM` or Daniel Moon's certificate.
- [ ] The configured `APPLE_TEAM_ID` is used consistently for notary submission and post-signing TeamIdentifier verification.
- [ ] The configured full Developer ID Application identity is selected exactly and verified as a Developer ID Application certificate.
- [ ] A wrong-team or wrong-identity certificate fails before publication.
- [ ] Documentation uses this fork owner's team `3ZK76CKTXW` and a matching identity example without exposing credentials.
- [ ] Workflow-control tests prove there is no hard-coded upstream signing identity and preserve protected-event, ephemeral-keychain, fail-closed, and complete-CI-gate behavior.
- [ ] Applicable CI checks pass.

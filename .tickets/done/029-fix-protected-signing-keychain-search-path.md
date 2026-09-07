---
Assigned-To: macparakeet@029-fix-protected-signing-keychain-search-path
Tags:
  - ready-for-agent
Parent: 017-publish-signed-notarized-ci-app-artifact
Blocked-By: []
---

## What to build

Fix protected signed-artifact CI signing after workflow-dispatch run `34078381270`, attempt 3, failed on the first nested Sparkle XPC with `The specified item could not be found in the keychain.` The certificate imported successfully, `security find-identity` found one valid identity, and notary credentials validated. The root cause is that the ephemeral keychain is passed through `codesign --keychain` but is not on the calling user's keychain search list, which `codesign` still uses to resolve the signing certificate chain.

Add the ephemeral keychain to the user search list before signing. Preserve the prior search list and restore it during cleanup, including failure paths. Keep the keychain isolated and deleted afterward. Add focused script tests for setup and cleanup. Do not change credentials, signing identity, notarization gating, publication gating, or ordinary development builds. Do not inspect or overwrite uncommitted changes in the landing worktree.

## Acceptance criteria

- [x] The ephemeral keychain is on the user search list before the first `codesign` call.
- [x] The previous user keychain search list is restored on success, failure, interruption, and missing/invalid credentials.
- [x] The temporary keychain and certificate file are still deleted safely.
- [x] Tests verify search-list setup, restoration, and safe quoting/path handling.
- [x] No credentials or private key material enters Git or logs.
- [x] Focused signing workflow tests pass.

## Resolution

PR #28 added the ephemeral signing keychain to the user search list before signing and restores the exact prior list before deleting temporary credentials. Focused tests cover ordering, success, failure, interruption, invalid credentials, and paths with spaces. All PR checks passed at `37411839767dca6fe4fd312a19bde52069104183`; the reviewed squash merge is `6d88d47b`.

---
Assigned-To: macparakeet@036-include-meeting-echo-assets-in-owner-development-artifact
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

# Include meeting echo assets in the owner development artifact

## Why

Direct inspection of CI run `34163462776` for merge `73cc1f204a266f0dfd73073bb974346d50e74f6a` found that the green owner development artifact does not contain either required meeting echo-suppression asset:

- `Contents/Frameworks/liblocalvqe.dylib`
- `Contents/Resources/MeetingEchoSuppression/localvqe-v1.4-aec-200K-f32.gguf`

The development artifact log explicitly says:

```text
Skipping meeting echo-suppression assets (BUNDLE_MEETING_ECHO_ASSETS=0)
```

The signed `v0.7.6` release DMG contains both files, but downloaded owner development artifact `10033792985` contains neither. Existing development-DMG verification still passed, so it does not enforce the new artifact contract.

## What to do

Make the GitHub Actions owner development artifact include the same required meeting echo-suppression library and model as a normal development app build. Make artifact verification fail if either asset is absent or unusable.

Keep the explicit local development opt-out introduced by PR #39. Do not remove that opt-out or change its warning. The CI owner development artifact must not use the opt-out.

## Scope

Change only the owner development artifact publication/configuration and the minimum verification/tests needed to enforce its echo-asset contents. Reuse the packaging and runtime verification introduced by PR #39.

Do not change speech recognition, meeting behavior, transcript filtering, release publication, release versioning, signing policy, the release artifact path, ADRs, or unrelated documentation. Do not refactor the echo implementation.

## Acceptance criteria

- [ ] The owner development artifact build does not set `BUNDLE_MEETING_ECHO_ASSETS=0`.
- [ ] Its DMG contains `liblocalvqe.dylib` and `localvqe-v1.4-aec-200K-f32.gguf` at the expected bundle paths.
- [ ] Development artifact verification fails when either required asset is absent.
- [ ] The existing echo runtime probe validates the packaged development assets where applicable.
- [ ] The explicit local development-only opt-out remains available and unchanged.
- [ ] Focused artifact/fixture tests pass.
- [ ] No release workflow, ADR, product behavior, or unrelated files change.

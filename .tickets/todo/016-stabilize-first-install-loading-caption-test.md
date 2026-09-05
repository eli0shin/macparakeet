---
Assigned-To:
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Diagnose and remove the timing flake in `DictationFlowCoordinatorLoadCaptionTests.testFirstInstallShowsPreparingThenClearsOnSuccess`. Main CI run `33998676839` failed in xctest-3 at line 88 because `XCTAssertTrue` did not observe the expected state. The other repeated XCTest processes passed, and the preceding main run passed the same code; SHA `a8570e56` changes tracker Markdown only.

Use a tight red-capable stress loop and determine whether the defect is test synchronization or production state ordering. Prefer deterministic state observation over sleeps, yields, or retries. Preserve the user contract: first installation shows the preparing caption while model startup is pending and clears it after successful startup.

## Acceptance criteria

- [ ] A repeated focused loop reproduces the original assertion failure before the fix, or the investigation documents why a deterministic red loop cannot be made.
- [ ] The test deterministically observes the intended pending-start and successful-completion states.
- [ ] The first-install preparing-caption user behavior remains unchanged.
- [ ] No sleep, retry, or arbitrary-yield workaround is added.
- [ ] Focused stress verification passes without retries.
- [ ] Applicable CI checks pass.

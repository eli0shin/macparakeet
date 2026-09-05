---
Assigned-To: macparakeet@016-stabilize-first-install-loading-caption-test
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

## Implementation notes

The unchanged focused test passed 200 runs under 20-process load, so the local
investigation could not make the rare CI failure deterministic without changing
the scenario. The test depended on a 90 ms transcription delay outlasting a
20 ms caption timer. Those elapsed-time assumptions do not prove that model
startup is still pending when the caption is observed on a loaded runner.

This is test synchronization, not a user-facing state-ordering defect. The test
now holds transcription at the existing async gate, observes the preparing
caption while startup is pending, releases startup, and then observes caption
clearance and successful telemetry. Production caption behavior is unchanged.

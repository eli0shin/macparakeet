---
Assigned-To: macparakeet@012-stabilize-queued-local-llm-unload-test
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Diagnose and remove the timing race in `InProcessLLMClientTests.testQueuedGenerationDoesNotUnloadRuntimeBetweenRequests`. CI run `33976770035`, attempt 1, failed because the runtime unloaded twice instead of once. The same SHA passed on PR CI and on rerun attempt 2, where all three XCTest repetitions passed, so use a stress loop that can reproduce the exact failure before changing code.

Preserve the contract: a request that is actually queued behind an active generation must prevent an idle unload between those requests. Prefer deterministic synchronization over sleeps or retries. Change production code only if the reproducible evidence proves a production race rather than a test scheduling race.

## Acceptance criteria

- [x] A tight repeated test loop reproduces the original failure before the fix, or the investigation documents why a deterministic red loop cannot be made.
- [x] The test deterministically proves that the second request is queued before the first request finishes.
- [x] The queued generation contract remains unchanged.
- [x] Focused stress verification passes without retries.
- [x] Applicable CI checks pass.

## Resolution

Replaced the test's single-yield scheduling assumption with direct, actor-isolated observation that the second generation entered the queue. The unchanged race reproduced 4 times in 100,000 iterations; the synchronized scenario passed 100,000 iterations. Production scheduling behavior is unchanged. Reviewed and merged in PR #12 at commit `9addeacc`.

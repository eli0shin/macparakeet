---
Assigned-To: macparakeet@028-stabilize-shared-audio-restart-test
Tags:
  - ready-for-agent
  - ci-reliability
Parent:
Blocked-By: []
---

## What to build

Diagnose and fix the shared-mode audio restart failure exposed on `main` by CI run `34043744982` at commit `cc5eddb47260d8cf885de155d5b69cfa10158a26`.

The failing test was:

```text
AudioRecorderFormatChangeTests.testSharedModeStartAfterStopDuringFirstStartSucceeds
```

The second start failed with `inputUnavailable(.noInputBuffers)`, did not leave the recorder in recording state, and did not retain the expected remaining subscriber. The Discover-removal and tracker-only landing commits did not intentionally change audio behavior. Determine whether this is a test synchronization race or a production lifecycle defect. Correct the governing seam rather than increasing sleeps or weakening assertions.

Build a fast, red-capable stress loop that raises the reproduction rate before forming a production theory. Preserve the CI `debug-tests` 20-minute job timeout and existing step-level timeouts.

## Acceptance criteria

- [ ] A focused agent-runnable loop reproduces the exact stop-during-first-start then second-start failure at a useful rate before the fix.
- [ ] The root cause is identified as test synchronization or production lifecycle behavior with direct evidence.
- [ ] The fix does not use arbitrary sleeps, retries that hide the race, weakened assertions, or a longer CI timeout.
- [ ] A regression test controls the load-bearing interleaving deterministically.
- [ ] The second shared-mode start succeeds after the first start aborts, leaves recording active, and retains exactly the expected subscriber.
- [ ] Stop/unsubscribe remains generation-safe and cannot cancel or detach a newer start.
- [ ] The focused stress loop passes enough repetitions after the fix to establish stability.
- [ ] Relevant audio tests and applicable CI checks pass.
- [ ] The PR records the pre-fix reproduction rate, post-fix repetitions, and proven root cause.

---
Assigned-To: macparakeet@046-expose-speaker-detection-controls-during-meetings
Tags: []
Parent:
Blocked-By: []
---

# Expose speaker-detection controls during meetings

## User request

Make Detect speakers on system audio and Detect speakers on microphone available within a meeting, like the existing echo-cancellation control. Users should not have to leave the meeting surface and open Settings to access them.

The user explicitly clarified that changing these controls during a meeting must apply to the live view as well. The earlier finalization-only scope and prohibition on live diarization were orchestrator errors and are superseded by this correction.

## Scope and behavior

- Reuse the current in-meeting echo-cancellation control as the placement and interaction reference, and the existing Settings speaker-detection controls as the functional reference.
- Expose both system-audio and microphone speaker-detection choices in the meeting recording surface. Make clear which track each controls and handle unavailable capture tracks appropriately.
- Controls used during an active meeting must affect the live transcript view during that recording AND that meeting's final speaker detection. They must not silently change only finalization or the next recording. Turning either track's detection on or off must update live attribution behavior without stopping or restarting the meeting. Clearly distinguish current-meeting state from global defaults; follow existing in-meeting control conventions for whether defaults are also updated, and document that behavior.
- Inspect governing capture, finalization, recovery, speaker correction, and archive retranscription contracts. Current speaker preferences are captured at recording start; deliberately update applicable contracts to support the requested current-meeting controls rather than bypassing persisted session state.
- Preserve the effective choices through session metadata/lock updates, normal stop, crash recovery, and archive retranscription as applicable. Keep explicit CLI opt-outs and legacy fallback behavior intact.
- Reuse existing local diarization and implement the live detection/attribution needed for the live view to honor both controls. Keep live work bounded and off the main actor; preserve capture reliability. Do not add cloud processing, automatic person identification, cross-track matching, or change echo cancellation, audio retention, canonical words, or capture routing.

## Acceptance and verification

- Both choices are accessible and understandable during a meeting without opening Settings.
- Changing either choice affects the correct track for that meeting without changing the other track's choice or disrupting recording.
- Current values stay consistent with effective live-view attribution, finalization, and recovery behavior; do not show a working toggle that is ignored by the live view.
- Add focused tests and live interaction evidence for toggling each track ON and OFF during an ongoing meeting, showing that subsequent live transcript updates honor the change independently. Document treatment of already displayed text and pending work; stale in-flight results must not restore the previous setting's attribution behavior.
- Add focused tests for independent choices, active-session changes, persistence/recovery, and finalization, including microphone-only and combined capture and legacy/default behavior.
- Update the governing behavior and persistence contracts alongside implementation.
- Provide rendered in-meeting evidence and request user visual approval before merge. Preserve established control sizing and design language.

## Resolution

Merged PR #52 into main as `53fd60b73efeee602a1f419fa83e8f9d1a98d2c9`, from reviewed head `3eafe2a0aeafff62d00f215e45552e26c73ccf7f`. Both controls affect live attribution and final detection, with saved choices honored in recovery and CLI retranscription. Independent review found no remaining issues after the update onto main. CI run `34303783938` passed; generated CLI help and specification match main exactly. User explicitly approved the visual evidence; approved rendering remained unchanged after rebase. Merge compatibility passed.


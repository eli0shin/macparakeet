---
Assigned-To: macparakeet@009-add-non-blocking-speaker-count-correction
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By: []
---

## What to build

Let users correct remote-speaker grouping after a meeting by rerunning attribution with Auto, exact, or bounded speaker counts. The normal completion flow must remain automatic and must not require a post-call modal.

## Acceptance criteria

- [x] Completed meetings show the detected speaker count and a non-blocking action to rerun speaker attribution.
- [x] Auto remains the default and does not require user input before or after meeting completion.
- [x] Users can provide an exact count or accepted lower and upper bounds when they know the expected attendance.
- [x] The UI defines the count as total people including Me and converts it correctly to the remote-speaker constraint used for system-audio diarization.
- [x] Invalid ranges and impossible remote counts are rejected with clear local feedback before processing starts.
- [x] Rerun progress, cancellation, and errors do not remove the last successful transcript presentation.
- [x] A successful rerun rebuilds Reading Turns and updates all visible speaker labels without changing raw transcription words.
- [x] The selected count behavior is available to the existing diarization constraint boundary instead of creating a second clustering implementation.
- [x] Tests cover Auto, exact, bounded, microphone-only, system-only, and dual-source meetings through the existing transcription orchestration boundary.
- [x] The feature introduces no mandatory post-call interruption.

## Blocked by

- 004 — Stabilize remote-speaker attribution by utterance

## Resolution

Shipped non-blocking Auto, Exact, and Range speaker correction through the existing diarization boundary, with total-person validation, atomic speaker-only persistence, stale-word rejection, cancellation and error safety, and rebuilt Reading Turns. Reviewed and merged in PR #6 at commit `0add262fff1827644f0c4628605586341ffb7180`.

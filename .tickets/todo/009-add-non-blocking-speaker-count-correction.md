---
Assigned-To:
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By:
  - 004-stabilize-remote-speaker-attribution-by-utterance
---

## What to build

Let users correct remote-speaker grouping after a meeting by rerunning attribution with Auto, exact, or bounded speaker counts. The normal completion flow must remain automatic and must not require a post-call modal.

## Acceptance criteria

- [ ] Completed meetings show the detected speaker count and a non-blocking action to rerun speaker attribution.
- [ ] Auto remains the default and does not require user input before or after meeting completion.
- [ ] Users can provide an exact count or accepted lower and upper bounds when they know the expected attendance.
- [ ] The UI defines the count as total people including Me and converts it correctly to the remote-speaker constraint used for system-audio diarization.
- [ ] Invalid ranges and impossible remote counts are rejected with clear local feedback before processing starts.
- [ ] Rerun progress, cancellation, and errors do not remove the last successful transcript presentation.
- [ ] A successful rerun rebuilds Reading Turns and updates all visible speaker labels without changing raw transcription words.
- [ ] The selected count behavior is available to the existing diarization constraint boundary instead of creating a second clustering implementation.
- [ ] Tests cover Auto, exact, bounded, microphone-only, system-only, and dual-source meetings through the existing transcription orchestration boundary.
- [ ] The feature introduces no mandatory post-call interruption.

## Blocked by

- 004 — Stabilize remote-speaker attribution by utterance

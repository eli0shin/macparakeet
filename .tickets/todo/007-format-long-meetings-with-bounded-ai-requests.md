---
Assigned-To:
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By:
  - 006-clean-and-paragraph-meeting-speech-blocks
---

## What to build

Allow optional AI formatting to improve long meetings by formatting bounded stable Reading Turns instead of sending or skipping one complete meeting string. AI formatting must never decide speaker identity or damage recoverable transcript evidence.

## Acceptance criteria

- [ ] A meeting longer than the current whole-transcript character limit can be formatted as bounded Reading Turn requests.
- [ ] Request boundaries preserve Reading Turn and speaker identity and do not split text in the middle of an unsafe semantic boundary.
- [ ] Formatting uses only the provider and settings that the user has already selected and introduces no implicit network behavior.
- [ ] AI output cannot add, remove, merge, or relabel speakers or alter playback timing.
- [ ] Empty, failed, excessively changed, or preservation-invalid output falls back to the deterministic readable text for the affected turn only.
- [ ] One failed turn does not discard valid formatting from unrelated turns or make the complete meeting unavailable.
- [ ] Original and deterministic readable text remain available after AI formatting.
- [ ] Progress and cancellation operate across bounded requests without leaving a partially corrupt presentation.
- [ ] Tests use a controlled formatter double to cover long meetings, request bounds, partial failure, cancellation, invalid output, and successful formatting.
- [ ] Meetings with AI formatting disabled retain the deterministic cleanup behavior without additional work or delay.

## Blocked by

- 006 — Clean and paragraph meeting speech blocks

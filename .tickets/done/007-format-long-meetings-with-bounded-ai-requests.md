---
Assigned-To: macparakeet@007-format-long-meetings-with-bounded-ai-requests
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By: []
---

## What to build

Allow optional AI formatting to improve long meetings by formatting bounded stable Reading Turns instead of sending or skipping one complete meeting string. AI formatting must never decide speaker identity or damage recoverable transcript evidence.

## Acceptance criteria

- [x] A meeting longer than the current whole-transcript character limit can be formatted as bounded Reading Turn requests.
- [x] Request boundaries preserve Reading Turn and speaker identity and do not split text in the middle of an unsafe semantic boundary.
- [x] Formatting uses only the provider and settings that the user has already selected and introduces no implicit network behavior.
- [x] AI output cannot add, remove, merge, or relabel speakers or alter playback timing.
- [x] Empty, failed, excessively changed, or preservation-invalid output falls back to the deterministic readable text for the affected turn only.
- [x] One failed turn does not discard valid formatting from unrelated turns or make the complete meeting unavailable.
- [x] Original and deterministic readable text remain available after AI formatting.
- [x] Progress and cancellation operate across bounded requests without leaving a partially corrupt presentation.
- [x] Tests use a controlled formatter double to cover long meetings, request bounds, partial failure, cancellation, invalid output, and successful formatting.
- [x] Meetings with AI formatting disabled retain the deterministic cleanup behavior without additional work or delay.

## Blocked by

- 006 — Clean and paragraph meeting speech blocks

## Resolution

Shipped bounded serial AI formatting over stable Reading Turns with per-turn validation and fallback, presentation-only overrides, provider reuse, progress, cancellation propagation, and deterministic-text preservation. Reviewed and merged in PR #8 at commit `f326ae1065818a7ff4ba70c92981187b7432855d`.

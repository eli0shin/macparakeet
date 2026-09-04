---
Assigned-To: macparakeet@002-prototype-reading-turn-transcript-layouts
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By: []
---

## What to build

Build a throwaway transcript presentation prototype that compares Conversation, Reading, and Hybrid layouts with identical noisy meeting data. The prototype must make long-form readability, uncertain attribution, overlap, timestamps, and playback affordances concrete enough to select the production presentation.

## Acceptance criteria

- [x] One deterministic synthetic meeting includes clean turns, long monologues, mic/system interleaving, one-word speaker flips, unattributed system words, short backchannels, genuine overlap, and duplicated speaker-mode speech.
- [x] Conversation, Reading, and Hybrid variants render the same synthetic Reading Turns and can be selected without changing the fixture.
- [x] Each variant demonstrates speaker headers, quiet timestamps, paragraphs inside long turns, overlap, text selection, and a playback-focus state.
- [x] The prototype remains isolated from production transcript behavior and does not introduce a durable data migration.
- [x] The evaluation records turns per minute, tiny blocks, median words per turn, and paragraphs over 120 words for the fixture.
- [x] A short decision record selects the production layout and explains why the other variants were rejected.

## Blocked by

None — can start immediately.

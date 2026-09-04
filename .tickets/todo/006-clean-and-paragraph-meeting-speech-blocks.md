---
Assigned-To:
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By:
  - 003-ship-the-minimum-reading-turn-experience
---

## What to build

Make each Reading Turn read like edited meeting prose with conservative, deterministic cleanup and bounded paragraphs. Cleanup must improve presentation without changing speaker grouping, timing evidence, or the recoverable verbatim transcript.

## Acceptance criteria

- [ ] Reading Turns split into paragraphs at natural sentence and pause boundaries, with bounded sentence and word counts.
- [ ] Initial paragraph behavior is calibrated from the established three-sentence, 80-word, and 2.5-second pause policy rather than inventing unrelated defaults.
- [ ] Paragraph boundaries never create a new speaker identity or repeat a Reading Turn header.
- [ ] Approved filler words, obvious adjacent repetition, whitespace, and punctuation artifacts are cleaned conservatively.
- [ ] Custom vocabulary corrections are present in readable text.
- [ ] Dictation-only expansion, insertion styling, and paste actions are not applied to meetings.
- [ ] Enabling or disabling cleanup does not change Reading Turn identity, speaker attribution, order, or timing.
- [ ] Verbatim words and timing evidence remain recoverable after cleanup.
- [ ] Long-monologue fixtures do not produce paragraphs over the accepted readability bound unless no safe sentence boundary exists.
- [ ] Tests cover meaning-sensitive filler words, repetition, long monologues, short pauses, long pauses, missing punctuation, and custom vocabulary through the final Reading Turn document.

## Blocked by

- 003 — Ship the minimum Reading Turn experience

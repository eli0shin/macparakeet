---
Assigned-To: macparakeet@006-clean-and-paragraph-meeting-speech-blocks
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By: []
---

## What to build

Make each Reading Turn read like edited meeting prose with conservative, deterministic cleanup and bounded paragraphs. Cleanup must improve presentation without changing speaker grouping, timing evidence, or the recoverable verbatim transcript.

## Acceptance criteria

- [x] Reading Turns split into paragraphs at natural sentence and pause boundaries, with bounded sentence and word counts.
- [x] Initial paragraph behavior is calibrated from the established three-sentence, 80-word, and 2.5-second pause policy rather than inventing unrelated defaults.
- [x] Paragraph boundaries never create a new speaker identity or repeat a Reading Turn header.
- [x] Approved filler words, obvious adjacent repetition, whitespace, and punctuation artifacts are cleaned conservatively.
- [x] Custom vocabulary corrections are present in readable text.
- [x] Dictation-only expansion, insertion styling, and paste actions are not applied to meetings.
- [x] Enabling or disabling cleanup does not change Reading Turn identity, speaker attribution, order, or timing.
- [x] Verbatim words and timing evidence remain recoverable after cleanup.
- [x] Long-monologue fixtures do not produce paragraphs over the accepted readability bound unless no safe sentence boundary exists.
- [x] Tests cover meaning-sensitive filler words, repetition, long monologues, short pauses, long pauses, missing punctuation, and custom vocabulary through the final Reading Turn document.

## Blocked by

- 003 — Ship the minimum Reading Turn experience

## Resolution

Shipped deterministic meeting cleanup and bounded paragraphing with stable Reading Turn structure, conservative punctuation and repetition handling, vocabulary corrections, Raw/Clean structural parity, and recoverable canonical evidence. Reviewed and merged in PR #3 at commit `5c7cc15930149e097fdddd54bdabff6ec53e075a`.

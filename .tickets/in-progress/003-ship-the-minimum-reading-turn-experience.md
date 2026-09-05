---
Assigned-To: macparakeet@003-ship-the-minimum-reading-turn-experience
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By: []
---

## What to build

Ship the smallest complete Reading Turn path for completed meetings. Existing source-aware transcript evidence must become a readable document with stable microphone/system blocks, paragraphs, secondary timestamps, seeking, selection, search, and accessibility. Raw evidence remains canonical.

## Acceptance criteria

- [ ] A pure meeting transcript presentation boundary converts completed source-aware transcript evidence into ordered Reading Turns with stable identity, speaker, source, time range, paragraphs, and underlying word references.
- [ ] Microphone speech is presented as Me, and system speech uses its available remote or fallback identity without interleaving the two sources word by word.
- [ ] The selected prototype layout becomes the completed-meeting reading surface with one speaker header and one quiet start timestamp per Reading Turn.
- [ ] Long same-speaker content can contain several paragraphs without repeating the speaker header.
- [ ] Clicking or activating a Reading Turn timestamp seeks to its start, and playback focus identifies the active turn.
- [ ] Text selection, transcript find, keyboard operation, and VoiceOver expose Reading Turns in a coherent order.
- [ ] Meetings without word timestamps or diarization retain a useful text/source fallback without claiming unavailable precision.
- [ ] Tests assert complete Reading Turn documents through the presentation boundary rather than private grouping helpers.
- [ ] A synthetic one-hour transcript builds and scrolls without creating a view for each word or causing a material responsiveness regression.
- [ ] Existing raw words, timestamps, source identity, and diarization regions are not rewritten.

## Blocked by

- 002 — Prototype Reading Turn transcript layouts

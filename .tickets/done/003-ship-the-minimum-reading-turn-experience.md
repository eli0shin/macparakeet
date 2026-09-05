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

- [x] A pure meeting transcript presentation boundary converts completed source-aware transcript evidence into ordered Reading Turns with stable identity, speaker, source, time range, paragraphs, and underlying word references.
- [x] Microphone speech is presented as Me, and system speech uses its available remote or fallback identity without interleaving the two sources word by word.
- [x] The selected prototype layout becomes the completed-meeting reading surface with one speaker header and one quiet start timestamp per Reading Turn.
- [x] Long same-speaker content can contain several paragraphs without repeating the speaker header.
- [x] Clicking or activating a Reading Turn timestamp seeks to its start, and playback focus identifies the active turn.
- [x] Text selection, transcript find, keyboard operation, and VoiceOver expose Reading Turns in a coherent order.
- [x] Meetings without word timestamps or diarization retain a useful text/source fallback without claiming unavailable precision.
- [x] Tests assert complete Reading Turn documents through the presentation boundary rather than private grouping helpers.
- [x] A synthetic one-hour transcript builds and scrolls without creating a view for each word or causing a material responsiveness regression.
- [x] Existing raw words, timestamps, source identity, and diarization regions are not rewritten.

## Blocked by

- 002 — Prototype Reading Turn transcript layouts

## Resolution

Shipped the pure completed-meeting Reading Turn presentation boundary and Conversation reading surface with seeking, playback focus, selection, find, accessibility, untimed fallback, and turn-bounded long-meeting behavior. Raw transcript evidence remains canonical. Reviewed and merged in PR #2 at commit `a1aa4bbb9ffdde7738e7c7490eaeac8cea844525`.

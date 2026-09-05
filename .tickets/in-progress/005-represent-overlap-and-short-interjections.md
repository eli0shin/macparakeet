---
Assigned-To: macparakeet@005-represent-overlap-and-short-interjections
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By: []
---

## What to build

Represent genuine simultaneous speech and short interjections without turning the transcript into alternating word fragments. Both contributions must remain readable and seekable, while the surrounding primary statement retains visual continuity.

## Acceptance criteria

- [x] Simultaneous microphone and system speech is represented as overlap rather than chronological one-word source alternation.
- [x] Simultaneous remote speakers are represented as overlap when diarization provides sufficient overlap evidence.
- [x] Each overlapping contribution retains its own speaker, time range, text, and playback target.
- [x] A genuine short backchannel remains visible and is not deleted by conservative speaker smoothing.
- [x] A short backchannel does not unnecessarily split the surrounding longer Reading Turn into disconnected visual fragments.
- [x] Weak or unattributed fragments do not claim a confident speaker only to satisfy the overlap presentation.
- [x] Reading order, keyboard order, and VoiceOver order remain deterministic for overlapping contributions.
- [x] Tests distinguish true overlap, short interjection, sequential interruption, and noisy one-word speaker-flip scenarios through complete Reading Turn output.
- [x] Existing non-overlapping meetings retain the behavior established by the minimum Reading Turn experience.

## Blocked by

- 004 — Stabilize remote-speaker attribution by utterance

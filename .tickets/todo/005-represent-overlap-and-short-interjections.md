---
Assigned-To:
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By: []
---

## What to build

Represent genuine simultaneous speech and short interjections without turning the transcript into alternating word fragments. Both contributions must remain readable and seekable, while the surrounding primary statement retains visual continuity.

## Acceptance criteria

- [ ] Simultaneous microphone and system speech is represented as overlap rather than chronological one-word source alternation.
- [ ] Simultaneous remote speakers are represented as overlap when diarization provides sufficient overlap evidence.
- [ ] Each overlapping contribution retains its own speaker, time range, text, and playback target.
- [ ] A genuine short backchannel remains visible and is not deleted by conservative speaker smoothing.
- [ ] A short backchannel does not unnecessarily split the surrounding longer Reading Turn into disconnected visual fragments.
- [ ] Weak or unattributed fragments do not claim a confident speaker only to satisfy the overlap presentation.
- [ ] Reading order, keyboard order, and VoiceOver order remain deterministic for overlapping contributions.
- [ ] Tests distinguish true overlap, short interjection, sequential interruption, and noisy one-word speaker-flip scenarios through complete Reading Turn output.
- [ ] Existing non-overlapping meetings retain the behavior established by the minimum Reading Turn experience.

## Blocked by

- 004 — Stabilize remote-speaker attribution by utterance

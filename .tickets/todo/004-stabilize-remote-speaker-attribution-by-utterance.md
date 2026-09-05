---
Assigned-To:
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By: []
---

## What to build

Make remote-speaker Reading Turns stable by assigning system speech from aggregate utterance evidence instead of exposing each word-level diarization transition. Ambiguous evidence must preserve the larger stable turn rather than create tiny speaker blocks.

## Acceptance criteria

- [ ] System-source utterances are formed before remote-speaker reconciliation and are assigned from aggregate diarization overlap.
- [ ] An isolated A/B/A label flip shorter than the calibrated evidence threshold does not create a visible Reading Turn.
- [ ] A sustained A/B/A exchange with reliable evidence remains three distinct speaker turns.
- [ ] Unattributed system words inherit the dominant speaker of their utterance when sufficient context exists.
- [ ] Generic system fallback labels do not appear as extra participants inside an otherwise stable refined-speaker utterance.
- [ ] Adjacent same-speaker utterances merge across an accepted short pause while clear conversational breaks remain visible.
- [ ] The policy for uncertain evidence is deterministic, local, and independent of an external AI provider.
- [ ] Microphone identity remains deterministic and is not passed through remote-speaker reconciliation.
- [ ] Fixture comparisons report turns per minute, blocks shorter than three words, isolated speaker flips, fallback-label transitions, and median words per turn before and after the change.
- [ ] Raw word labels and diarization regions remain available as evidence and are not overwritten by presentation smoothing.

## Blocked by

- 003 — Ship the minimum Reading Turn experience

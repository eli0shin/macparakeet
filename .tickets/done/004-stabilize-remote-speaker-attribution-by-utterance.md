---
Assigned-To: macparakeet@004-stabilize-remote-speaker-attribution-by-utterance
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By: []
---

## What to build

Make remote-speaker Reading Turns stable by assigning system speech from aggregate utterance evidence instead of exposing each word-level diarization transition. Ambiguous evidence must preserve the larger stable turn rather than create tiny speaker blocks.

## Acceptance criteria

- [x] System-source utterances are formed before remote-speaker reconciliation and are assigned from aggregate diarization overlap.
- [x] An isolated A/B/A label flip shorter than the calibrated evidence threshold does not create a visible Reading Turn.
- [x] A sustained A/B/A exchange with reliable evidence remains three distinct speaker turns.
- [x] Unattributed system words inherit the dominant speaker of their utterance when sufficient context exists.
- [x] Generic system fallback labels do not appear as extra participants inside an otherwise stable refined-speaker utterance.
- [x] Adjacent same-speaker utterances merge across an accepted short pause while clear conversational breaks remain visible.
- [x] The policy for uncertain evidence is deterministic, local, and independent of an external AI provider.
- [x] Microphone identity remains deterministic and is not passed through remote-speaker reconciliation.
- [x] Fixture comparisons report turns per minute, blocks shorter than three words, isolated speaker flips, fallback-label transitions, and median words per turn before and after the change.
- [x] Raw word labels and diarization regions remain available as evidence and are not overwritten by presentation smoothing.

## Blocked by

- 003 — Ship the minimum Reading Turn experience

## Resolution

Shipped utterance-first remote-speaker reconciliation with aggregate diarization evidence, conservative short-run smoothing, sustained fallback preservation, deterministic microphone identity, readability metrics, and raw-evidence retention. Reviewed and merged in PR #4 at commit `4e1768ba0a79a150bfbd9c9bc0a6da0d2fc6c86c`.

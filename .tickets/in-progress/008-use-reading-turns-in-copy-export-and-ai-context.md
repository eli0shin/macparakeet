---
Assigned-To: macparakeet@008-use-reading-turns-in-copy-export-and-ai-context
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By: []
---

## What to build

Use the same Reading Turn document wherever a user reads, copies, exports, summarizes, or chats about a completed meeting. Speaker structure and paragraphs must remain consistent across these surfaces while timing-specific subtitle formats keep their cue model.

## Acceptance criteria

- [ ] Copying a passage can include its speaker and Reading Turn start time without exposing every word timestamp.
- [ ] Readable TXT and Markdown meeting exports use the same speaker order, overlap representation, and paragraph boundaries as the completed-meeting view.
- [ ] Summary and chat context preserve Reading Turn speaker attribution and readable paragraph boundaries.
- [ ] Search citations or navigation targets resolve to the containing Reading Turn and seekable time range.
- [ ] Speaker rename is reflected consistently in the view, copy output, readable exports, and AI context.
- [ ] SRT and VTT exports retain cue-oriented timing and are not silently converted to Reading Turn-sized captions.
- [ ] Verbatim or timing-focused output remains available where the existing product contract requires it.
- [ ] Missing diarization or timing data produces graceful readable output without fabricated speakers or times.
- [ ] Contract and behavior tests compare each consumer against one shared Reading Turn fixture rather than reimplementing grouping expectations per surface.
- [ ] Existing meeting export and AI-context behavior that is unrelated to transcript structure remains compatible.

## Blocked by

- 004 — Stabilize remote-speaker attribution by utterance
- 005 — Represent overlap and short interjections
- 006 — Clean and paragraph meeting speech blocks

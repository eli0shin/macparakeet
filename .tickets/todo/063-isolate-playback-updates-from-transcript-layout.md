---
Assigned-To:
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By: []
---

# Isolate playback updates from transcript layout

## Problem

`TranscriptResultView` reads `MediaPlayerViewModel.currentTimeMs` in the same
large view that builds the complete transcript pane and owns its scroll reader.
Playback ticks can therefore invalidate broad transcript structure when only
the active Reading Turn and occasional follow-scroll target need to change.
The view also resolves active state through parent-level derived properties.

## What to build

Give playback-follow and active-turn presentation a narrow observation boundary.
Compute the active Reading Turn through the existing playback index, update only
the previously active and newly active visible presentation, and request scroll
movement only when the target changes. Keep manual-scroll pause and seek
behavior correct.

## Acceptance criteria

- [ ] A playback time tick does not rebuild or remeasure the transcript header,
  speaker summary, all Reading Turns, search UI, or unrelated detail controls.
- [ ] Profiler or signpost evidence reports bounded main-thread work per playback
  tick on a long meeting.
- [ ] Only active-turn presentation and a changed auto-scroll target update.
- [ ] Seeking, play/pause, manual-scroll pause, five-second resume behavior, find
  ownership of auto-scroll pause, and playback focus remain correct.
- [ ] Starting playback near the end of a long meeting does not require eager
  realization of preceding Reading Turns.
- [ ] Focused tests cover normal ticks, large seeks, manual scrolling, and find
  navigation during playback.

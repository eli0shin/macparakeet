---
Assigned-To:
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By:
  - 069-bound-reading-row-realization
---

# Bound Reading playback follow

## Problem

The combined release gate measures a Reading playback-follow update at
41.95 ms against a budget below 16 ms. Time Profiler reaches the instrumented
`Reading Turn Presentation Update`, but current evidence does not isolate a
narrower dominant operation.

## What to build

Profile and bound work inside and around the production Reading active-turn
change. Preserve the narrow observation boundary, direct near-end navigation,
and manual-scroll/find ownership rules.

## Acceptance criteria

- [ ] Every measured Reading playback-follow update is below 16 ms in the
  release gate.
- [ ] Time Profiler and Points of Interest evidence identify the corrected
  dominant work.
- [ ] Only previous/new active visible rows and changed navigation targets
  update.
- [ ] Seeking, manual-scroll pause, find ownership, and direct near-end startup
  remain correct.
- [ ] The production renderer drives the regression and budgets are unchanged.

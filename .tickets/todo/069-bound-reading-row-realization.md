---
Assigned-To:
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By:
  - 068-reduce-cold-reading-transaction
---

# Bound Reading row realization

## Problem

The combined release gate measures an ordinary Reading scroll update at
39.31 ms against a budget below 16 ms. Existing Time Profiler evidence does not
yet isolate a narrower cause. Native row-height calculation was not dominant in
the sampled cold path and must not be assumed to be the scroll cause without
new evidence.

## What to build

Profile one production Reading scroll update on the public 1,200-turn fixture,
identify the dominant row-realization or layout work, and bound it without
restoring the variable-height `LazyVStack` feedback loop.

## Acceptance criteria

- [ ] Every measured ordinary Reading scroll update is below 16 ms in the
  release gate.
- [ ] Time Profiler evidence identifies the corrected dominant operation.
- [ ] Only visible rows are realized and exact top/bottom bounds remain stable.
- [ ] Selection, speaker controls, timestamps, playback focus, search targets,
  accessibility, and font scaling remain correct.
- [ ] The production renderer drives the regression and budgets are unchanged.

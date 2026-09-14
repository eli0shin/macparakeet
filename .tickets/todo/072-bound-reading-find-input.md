---
Assigned-To:
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By:
  - 071-bound-settled-find-presentation
---

# Bound Reading find input

## Problem

The combined release gate measures the largest Reading find-field edit at
16.93 ms against a budget below 16 ms. Text mode passes at 8.85 ms. Existing
evidence does not isolate the remaining synchronous Reading-only work after
search blocks are installed.

## What to build

Measure and remove or bound the remaining synchronous Reading work in the field
edit path. Preserve immediate draft publication, debounce, cancellation, stale
result rejection, and matching semantics.

## Acceptance criteria

- [ ] Every Reading find-field edit is below 16 ms in the release gate.
- [ ] The measured synchronous cause and correction are documented.
- [ ] Rapid edits display immediately and only the latest query can publish.
- [ ] Empty/whitespace clearing, searching state, Unicode matching, counters,
  and keyboard navigation remain correct.
- [ ] No budget is increased and no spinner substitutes for responsiveness.

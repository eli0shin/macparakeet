---
Assigned-To:
Tags:
  - performance
Parent:
Blocked-By: []
---

# Make meeting transcript detail responsive

## Problem

The completed-meeting transcript detail is unacceptably slow to open, scroll,
play, and search. This is not one isolated regression. The current rendering,
search, and state ownership compound each other as a Final transcript grows.

A synthetic debug-build diagnosis measured:

- about 136 ms of main-thread matching for a one-letter find query;
- about 43 ms to group the resulting ranges;
- about 1,390 ms to construct highlighted attributed text;
- about 3,350 ms to lay out 1,200 eager Reading Turn rows;
- individual large scroll updates as high as about 480 ms.

These are diagnostic debug-build measurements, not release timings. They do
prove that the current paths can block interaction for far longer than one
frame.

## Child tickets

- `060`: make find input immediate and move matching off the main actor.
- `061`: bound highlight and find-navigation rendering work.
- `062`: replace eager Reading Turn layout with a scalable renderer.
- `063`: isolate playback updates from transcript layout.
- `064`: precompute transcript-derived display data.
- `065`: split transcript detail into narrow invalidation domains.
- `066`: optimize the long-transcript Text surface.
- `067`: measure the combined release path and identify remaining dominant work.
- `068`: reduce the cold Reading layout transaction below its release budget.
- `069`: bound ordinary Reading row realization and scrolling.
- `070`: bound Reading playback-follow updates.
- `071`: bound settled-find presentation in Reading and Text modes.
- `072`: bound the remaining Reading find-input work.
- `073`: rerun the final combined release gate and Time Profiler workflow.

## Program acceptance criteria

- [ ] Opening and scrolling a representative long Final transcript stays
  interactive without beachballs or multi-frame main-thread stalls.
- [ ] Cmd+F accepts every typed character immediately. Search completion cannot
  overwrite a newer query.
- [ ] Search, Reading Turns, speaker labels and renaming, timestamps, playback,
  selection, editing, copy/export, accessibility, and scroll navigation remain
  correct.
- [ ] Performance gates use public-safe synthetic data at realistic long-meeting
  scale and cover initial render, ordinary scrolling, playback, and find input.
- [ ] Before/after release measurements and Time Profiler evidence identify the
  remaining dominant work. Debug timings are labeled as debug timings.
- [ ] No private meeting content, identifiers, paths, or profiler captures enter
  Git.
- [ ] The work does not restore the selectable variable-height `LazyVStack`
  feedback loop fixed by ticket `020`.

## Out of scope

Do not reduce transcript content, disable core interactions, or add a spinner
around synchronous main-thread work as a substitute for fixing it.

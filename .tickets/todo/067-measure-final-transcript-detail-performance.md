---
Assigned-To:
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By: []
---

# Measure final transcript detail performance

## Problem

Tickets 060 through 066 changed search, Reading and Text rendering, playback
observation, preparation, and invalidation boundaries. The program acceptance
criteria still require combined release-build measurements and Time Profiler
evidence. Individual PRs reported debug measurements or focused boundaries, but
they did not establish the final production path after all changes landed.

## What to build

Measure the combined completed-meeting transcript detail through the actual
production renderer with public-safe synthetic long-meeting data. Cover initial
readiness, ordinary scrolling, playback ticks, find input, settled find
presentation, and both Reading and Text modes. Use a release build where the
repository supports it, and resolve existing test-fixture build constraints
without weakening production or test contracts.

Record reproducible commands, fixture scale, machine/build context, before and
after results, and Time Profiler evidence that identifies the remaining
dominant main-thread work. Commit only public-safe summaries and reusable gates;
do not commit private transcripts or profiler captures.

If a measured path does not meet the parent responsiveness criteria, do not hide
it behind a spinner or relaxed budget. Implement a tightly scoped correction if
it fits this ticket, or record the proven gap so a follow-up ticket can be
created before the parent closes.

## Acceptance criteria

- [ ] Release-build measurements cover initial render, ordinary scrolling,
  playback, find input, and settled find presentation at realistic long-meeting
  scale in Reading and Text modes.
- [ ] The production renderer, not a simplified look-alike, drives the gates.
- [ ] Time Profiler evidence identifies the remaining dominant main-thread work
  and confirms there are no unexplained multi-frame interaction stalls.
- [ ] Before/after results identify build mode, fixture size, machine context,
  and distinguish historical debug baselines from current release results.
- [ ] Reproducible public-safe gates and concise evidence are committed without
  private meeting content, identifiers, paths, or profiler captures.
- [ ] Any remaining failed program criterion is fixed or recorded as a precise
  follow-up blocker before this ticket is completed.

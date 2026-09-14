---
Assigned-To: macparakeet@068-reduce-cold-reading-transaction
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By: []
---

# Reduce cold Reading transaction

## Problem

The combined release gate measures the largest initial Reading update at
423.67 ms against a budget below 250 ms. Total Reading readiness passes at
650.47 ms, but this single main-thread update remains a multi-frame stall.
Time Profiler attributes the cold transaction mainly to SwiftUI AttributeGraph
updates, stack sizing and placement, AppKit subtree layout, and Core Animation
commit. Native Reading Turn row-height calculation was not dominant.

## What to build

Identify and split or defer the remaining cold `TranscriptResultView` and
Reading-header graph/layout transaction without hiding synchronous work behind
a spinner. Keep the production 1,200-turn, 72,000-word fixture and existing
interactions unchanged.

## Acceptance criteria

- [ ] The release gate's largest initial Reading update is below 250 ms on the
  documented fixture and machine context.
- [ ] Time Profiler evidence confirms which AttributeGraph, layout, or commit
  work was removed or bounded.
- [ ] Total Reading readiness remains below 1,000 ms.
- [ ] Header, speaker overview, actions, search, playback, selection, editing,
  accessibility, and exact document bounds remain correct.
- [ ] No budget is increased and no spinner masks synchronous work.

## Resolution

Reduced the largest cold Reading update from 516.95 ms to 190.71 ms and total
Reading readiness from 757.88 ms to 422.23 ms on the documented release fixture.
Time Profiler showed a substantial reduction in AttributeGraph update samples;
all existing budgets remained unchanged. Merged as
[PR #80](https://github.com/eli0shin/macparakeet/pull/80) in commit
`17e2483a`.

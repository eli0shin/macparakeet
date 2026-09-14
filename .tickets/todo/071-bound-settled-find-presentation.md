---
Assigned-To:
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By:
  - 070-bound-reading-playback-follow
---

# Bound settled find presentation

## Problem

After background matching settles, the release gate measures presentation
updates of 116.55 ms in Reading mode and 43.27 ms in Text mode against a budget
below 16 ms. Time Profiler shows a SwiftUI/AttributeGraph and Core Animation
presentation transaction in both surfaces.

## What to build

Isolate or split the post-search presentation transaction so publishing the
current results does not cause broad layout or commit work. Keep current-match
highlighting, counters, wrapping navigation, and range correctness.

## Acceptance criteria

- [ ] Settled-find presentation is below 16 ms in both Reading and Text release
  gates, including a high-match-count query.
- [ ] Time Profiler evidence identifies the removed or bounded graph/layout work.
- [ ] Search matching remains off-main and stale generations cannot publish.
- [ ] Current emphasis, counters, next/previous wrapping, Cmd+G navigation, and
  Unicode range validation remain correct.
- [ ] No full off-screen highlight construction or duplicate transcript layout
  returns.

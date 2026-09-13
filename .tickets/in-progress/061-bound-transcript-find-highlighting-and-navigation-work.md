---
Assigned-To: macparakeet@061-bound-transcript-find-highlighting-and-navigation-work
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By: []
---

# Bound transcript find highlighting and navigation work

## Problem

Find performance does not end with matching. The view rebuilds a dictionary of
all matches and creates attributed text for every matching block after each
query. A synthetic one-letter query produced 230,400 ranges: grouping took about
43 ms and attributed-string construction took about 1,390 ms on the main
thread. Text mode also creates a full transcript prefix and lays it out as an
invisible duplicate solely to obtain a scroll target.

## What to build

Make highlight and current-match navigation costs depend on the visible or
current result, not the total number of matches. Use native temporary layout
attributes, visible-range highlighting, current-match-only highlighting, or
another measured bounded design. Remove the invisible duplicate-prefix layout
from Text mode and provide an exact or acceptably precise navigation target
without shaping the transcript twice.

## Acceptance criteria

- [ ] A common one-character query does not construct attributed text for every
  match or every off-screen Reading Turn.
- [ ] Publishing and displaying find results stays within a documented frame
  budget on a long transcript, separately from background matching time.
- [ ] Next, previous, Cmd+G, Shift+Cmd+G, wrapping, the result counter, and the
  emphasized current match remain correct.
- [ ] Moving to a distant match does not allocate or lay out the complete text
  before that match as an invisible view.
- [ ] Highlight ranges remain Unicode-correct and cannot apply stale ranges to
  changed text.
- [ ] Focused tests include a very common query with a high match count and
  distant-match navigation.

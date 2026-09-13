---
Assigned-To:
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By: []
---

# Replace eager Reading Turn layout with scalable rendering

## Problem

The completed-meeting Reading surface places every variable-height selectable
Reading Turn in a plain `VStack`. A `ScrollView` must measure all of those rows
to determine its document size. Each row adds text shaping and wrapping,
selection, accessibility, controls, context menus, and speaker decoration. A
1,200-turn synthetic transcript required about 3,350 ms of initial main-thread
layout, and sampled large scroll updates reached about 480 ms.

Ticket `020` intentionally replaced `LazyVStack` because selectable,
variable-height rows caused a macOS 26 lazy-layout feedback loop. Do not restore
that fault. A diagnostic SwiftUI `List` reduced initial layout to about 400 ms,
but still produced approximately 75–90 ms row-realization frames and unstable
estimated scroll bounds. `List` alone is therefore not an accepted solution.

## What to build

Implement and measure a scalable transcript renderer. Evaluate a TextKit-backed
document, an AppKit virtualized collection/table with stable cached measurement,
or another design that bounds initial and per-scroll work. Choose the design
from profiler evidence and a public-safe prototype before changing production.

## Acceptance criteria

- [ ] Initial main-thread layout does not grow linearly with all off-screen
  Reading Turn view graphs.
- [ ] Ordinary wheel/trackpad scrolling and row realization remain within a
  documented frame budget on at least 1,200 variable-height Reading Turns.
- [ ] Scrolling reaches exact top and bottom bounds and settles without ongoing
  layout or the ticket `020` feedback loop.
- [ ] Search targets and playback targets can navigate directly to distant
  Reading Turns without first rendering all intervening rows.
- [ ] Speaker labels and renaming, timestamps and seeking, playback focus,
  selection, context copy, accessibility, font scaling, and compact borderless
  presentation remain available.
- [ ] The committed regression drives the actual production renderer, not a
  simplified look-alike.
- [ ] The PR records rejected prototypes and measured reasons, including any
  SwiftUI `List`, lazy stack, or TextKit trade-offs.

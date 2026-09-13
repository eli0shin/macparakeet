---
Assigned-To:
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By:
  - 065-split-transcript-detail-into-narrow-invalidation-domains
---

# Optimize long transcript Text mode rendering

## Problem

Text mode renders the complete transcript as one SwiftUI `Text`. Opening find
replaces it with one complete `AttributedString`; navigation then creates a
string containing the full prefix before the match and lays that prefix out as
an invisible duplicate scroll anchor. Long documents therefore pay complete
text shaping costs for highlighting and can pay them again for navigation.

The repository already uses an AppKit `NSTextView` for performant selectable
live transcript rendering. Evaluate whether a dedicated final-transcript Text
surface can use the same TextKit strengths without coupling it to live-preview
types.

## What to build

Provide a long-document Text surface with bounded initial layout, native
selection, incremental/current-match highlighting, and range-based scrolling.
Do not duplicate the complete transcript or prefix in the SwiftUI hierarchy.
Keep normal Text mode semantics, including cross-paragraph selection and
editing entry.

## Acceptance criteria

- [ ] Opening Text mode for a representative multi-hour transcript stays within
  a documented main-thread readiness budget.
- [ ] Search highlighting and navigation use text ranges or visible layout and
  never create an invisible full-prefix `Text`.
- [ ] Selection can span paragraphs and copy exact transcript text.
- [ ] Font scaling, colors, line spacing, accessibility, and switching between
  Reading and Text remain correct.
- [ ] Entering and leaving transcript editing preserves text and scroll position
  according to an explicit tested policy.
- [ ] Focused performance tests cover initial render, resize/reflow, selection,
  a high-match-count query, and a match near the end of the document.

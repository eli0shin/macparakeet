# Scalable Reading Turn renderer prototype

> **Throwaway prototype:** This branch-only AppKit script uses generated public
> text. It is not production code and has no persistence or network access.

## Question

Can an exact-height `NSTableView` keep the complete 1,200-turn document bounds
while it realizes only visible Reading Turns and jumps directly to the last one?

## Run

```bash
swift prototypes/scalable-reading-turn-renderer/Prototype.swift
```

The script reports initial wall time, realized row count, and direct navigation
to the final row.

## Decision

Use an AppKit table with cached exact text measurements. Keep one native row per
visible Reading Turn and one SwiftUI-hosted header row. This preserves per-turn
selection and controls without creating all off-screen SwiftUI view graphs.

Reject a single TextKit document because speaker rename controls, per-turn seek
controls, context actions, playback focus, and per-turn accessibility would need
attachments or a second overlay model. Reject SwiftUI `List` because the ticket
experiment measured 75–90 ms realization frames and unstable estimated bounds.
Reject `LazyVStack` because ticket 020 proved a selectable variable-height lazy
layout feedback loop on macOS 26.

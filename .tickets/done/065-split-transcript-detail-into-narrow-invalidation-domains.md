---
Assigned-To: macparakeet@065-split-transcript-detail-into-narrow-invalidation-domains
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By: []
---

# Split transcript detail into narrow invalidation domains

## Problem

`TranscriptResultView.swift` is more than 4,000 lines and one view owns detail
loading, transcript rendering, find, playback-follow, editing, speaker editing,
exports, prompts, chat, and many transient controls. This is a performance
problem because unrelated observable reads and local state changes share one
large SwiftUI body invalidation boundary. It also prevents precise performance
tests for the actual production seams.

## What to build

Split the detail into explicit presentation modules with narrow state inputs:
at minimum header/actions, transcript document, find session, playback-follow,
speaker overview/editing, and AI result/chat panes. Pass prepared immutable
snapshots rather than the full mutable transcription and view-model graph where
possible. Keep the module boundaries aligned with user interactions, not file
size alone.

## Acceptance criteria

- [ ] Changing find text invalidates find and affected transcript presentation,
  not header, chat, export, or playback controls.
- [ ] Playback ticks invalidate only playback-follow and active-turn state.
- [ ] Title, speaker, and transcript editing each have explicit state ownership
  and update only dependent modules.
- [ ] Each module can be hosted in a focused performance/correctness test using
  the same production view path.
- [ ] Instruments or SwiftUI change diagnostics demonstrate narrower body
  updates for search, playback, hover, and focus interactions.
- [ ] The split preserves all detail behavior and does not become a broad visual
  redesign or duplicate transcript domain logic.

## Resolution

Split transcript detail presentation into narrow header, actions, document,
find, playback-follow, speaker-editing, and AI domains with immutable revisions
and production Points of Interest instrumentation. Focused invalidation,
playback, host-path, and CI coverage passed. Merged as
[PR #77](https://github.com/eli0shin/macparakeet/pull/77) in commit
`6c75ee29`.

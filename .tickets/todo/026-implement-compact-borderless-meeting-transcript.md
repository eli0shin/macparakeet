---
Assigned-To:
Tags:
  - ready-for-agent
Parent: 023-simplify-meeting-transcript-experience
Blocked-By:
  - 025-prototype-compact-borderless-meeting-transcript
---

## What to build

Implement the owner-selected design from ticket `025` in the completed-meeting transcript view. Treat the prototype as a design decision, not production code: implement the result through existing SwiftUI and design-system patterns with production tests and accessibility.

The final design must make the speaker overview compact, remove the visible overlap container, and render Reading Turns as dense borderless blocks. Preserve all transcript semantics and interactions.

## Acceptance criteria

- [ ] Implementation matches the selected prototype decision recorded by ticket `025`.
- [ ] The speaker overview uses compact inline speaker entries and wraps only when available width is insufficient.
- [ ] Speaker renaming remains keyboard-accessible and compact speaker statistics remain available.
- [ ] Reading Turns have no card border or background fill and use materially reduced padding and vertical spacing.
- [ ] Overlapping turns render as ordinary adjacent blocks without an “Overlapping conversation” label, border, background, or wrapper spacing.
- [ ] Internal overlap identity, timestamp evidence, navigation, playback seeking, exports, and AI context remain unchanged.
- [ ] Speaker colors remain useful as restrained identity markers without recreating bubbles.
- [ ] Text selection across the transcript, rename controls, timestamps, playback focus, copy, and containing-turn navigation continue to work.
- [ ] The public-safe 401-row scrolling regression and transcript performance gate remain passing; the redesign does not restore lazy-layout beachballs or incorrect scroll targets.
- [ ] Focused visual-structure, accessibility, interaction, and performance tests lock the selected behavior.
- [ ] Relevant UI specifications are updated and applicable CI checks pass.

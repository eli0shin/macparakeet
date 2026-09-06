---
Assigned-To:
Tags:
  - ready-for-agent
  - prototype
Parent: 023-simplify-meeting-transcript-experience
Blocked-By: []
---

## Question to answer

What compact, borderless completed-meeting transcript layout best reduces wasted vertical space while keeping speaker identity, renaming, timing, seeking, text selection, overlap, and long-transcript readability clear?

Build a throwaway UI prototype before production implementation. Compare three structurally different variants in the context of the complete transcript page, not isolated cards. Use one deterministic synthetic meeting for every variant, including many speakers, long Reading Turns, short interjections, genuine overlap, rename state, playback focus, and enough content to judge scrolling density.

The prototype must be downloadable from GitHub Actions as a review artifact. It must be a simple self-contained artifact the owner can open without Xcode or a development checkout. Keep it isolated from production behavior and clearly label it as a prototype.

## Required design constraints

All variants must explore the agreed direction:

- Speaker overview wraps to additional compact lines only when speakers do not fit.
- Speaker names remain editable and useful compact statistics remain visible.
- Overlapping turns render as ordinary adjacent speaker blocks; there is no visible “Overlapping conversation” wrapper.
- Overlap timing/evidence remains represented in prototype state so the visual removal does not imply data loss.
- Reading Turns are borderless blocks without bubble backgrounds.
- Padding and inter-turn spacing are materially smaller than the current view.

Variants must differ in information hierarchy or alignment, not only color or a few spacing values.

## Acceptance criteria

- [ ] Three structurally different variants render the identical representative meeting fixture.
- [ ] A visible switcher and keyboard controls change variants without changing fixture data.
- [ ] The full transcript-page context, speaker overview wrapping, rename state, overlap, playback focus, timestamps, long turns, and short interjections are represented.
- [ ] Each variant removes turn borders/backgrounds and the overlap wrapper while using a distinct compact hierarchy.
- [ ] Density evidence compares vertical space or visible-turn count against a representation of the current layout.
- [ ] CI uploads a clearly named, self-contained prototype artifact that opens locally without a checkout or build tools.
- [ ] No private meeting content, local paths, production mutation, analytics, or network dependency enters the prototype or artifact.
- [ ] The PR and ticket record the artifact URL and concise review instructions.
- [ ] The owner selects a variant, or a precise combination of variants, before this ticket is completed.
- [ ] The selected design and rejected alternatives are recorded for ticket `026`.

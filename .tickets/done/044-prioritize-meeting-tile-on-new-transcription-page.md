---
Assigned-To: macparakeet@044-prioritize-meeting-tile-on-new-transcription-page
Tags: []
Parent:
Blocked-By: []
---

# Prioritize meeting recording on the New Transcription page

## User request

Rearrange the three existing entry sections on the New Transcription page to reflect product priorities. Meeting recording and file transcription are primary; media URL download/transcription is secondary. Dictation intentionally remains outside this page.

## Required layout

- Top left, large tile: start a new meeting recording, replacing the current large media URL/video transcription tile.
- Top right, large tile: file transcription, unchanged in position and prominence.
- Bottom, short full-width bar: media URL/video download and transcription, replacing the current compact meeting entry.

This swaps meeting and media URL placement and prominence. It is not a request to disable or remove video download/transcription, or to redesign the rest of the page.

## Invariants

- Keep all existing supported media URL providers, URL entry/paste, recognition, validation, download/transcribe actions, progress, cancellation, and error handling available and working in the compact bottom section.
- Preserve meeting start behavior, permissions, capture choices, existing configuration, and recording lifecycle. Do not change capture, STT, or media download logic to implement the layout change.
- Keep file selection, drag/drop, batch transcription, and related state behavior intact.
- Do not add a dictation tile, change feature flags, or remove any existing transcription capability.
- Reuse the established page design language and existing control appearance. Do not reduce already-correct button sizing or restyle unrelated controls.

## Acceptance and verification

- The rendered page clearly presents meeting recording as the large top-left tile, file transcription as the large top-right tile, and media URL transcription as the short bottom bar.
- Adapt content within the swapped sections so controls remain legible and usable at supported window sizes; avoid clipping, hidden actions, and oversized empty space.
- Keyboard focus order and accessibility follow the new visual arrangement.
- Verify meeting start, file entry, and media URL entry/actions still route to their existing behavior, with focused tests proportional to the change.
- Provide actual rendered before/after visual evidence for the page. Request user visual approval before merge; a build or code-path review alone does not establish visual acceptance.
- Update the relevant UI behavior documentation to reflect the new arrangement. Keep implementation scoped to layout and necessary view integration.


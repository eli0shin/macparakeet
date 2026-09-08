# Ticket 043: Library header visual evidence

These images render the production `TranscriptionLibraryView` at 1000 × 700
with an isolated in-memory database. No user Library data is used or changed.
The “before” images use the merged PR #46 code. The “after” images use this
change.

> The AppKit snapshot path does not composite native bordered-button labels in
> the before images. Their white native control bounds still show the rejected
> small sizing. The after images fully render because the restored Library
> controls use the accepted custom capsule treatment.

## Root

| Before (PR #46) | After |
| --- | --- |
| ![Root before](root-before.png) | ![Root after](root-after.png) |

## Nested folder

| Before (PR #46) | After |
| --- | --- |
| ![Nested folder before](nested-folder-before.png) | ![Nested folder after](nested-folder-after.png) |

## Selection mode

| Before (PR #46) | After |
| --- | --- |
| ![Selection before](selection-before.png) | ![Selection after](selection-after.png) |

Regenerate the after images with:

```bash
LIBRARY_HEADER_EVIDENCE_DIR=/tmp/library-header-after \
  swift test --filter LibraryHeaderVisualEvidenceTests/testRenderEvidence
```

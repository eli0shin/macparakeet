---
Assigned-To: OpenCode
Tags: []
Parent:
Blocked-By: []
---

# Streamline retranscription model selection

## Problem

Retranscribing a meeting from either the meeting page or a recording page in
the Library currently adds unnecessary friction:

1. The model picker includes models that are not downloaded and installed, but
   disables them. These unavailable choices confuse users at the point of
   action; model discovery and installation belong in Settings.
2. Selecting an available model opens another confirmation modal (for example,
   “Try Parakeet”), even though the user has already chosen **Retranscribe** and
   then explicitly selected a model. This makes retranscription a three-click
   flow.

## Requested behavior

- In every retranscription model picker, render only models that are currently
  downloaded, installed, and available for use. Omit unavailable models instead
  of showing disabled rows.
- Treat selecting a model as confirmation. Start retranscription immediately
  with that model and do not open a separate confirmation modal.
- Apply the same behavior to retranscription launched from both the meeting
  page and recording pages in the Library.
- Keep model browsing, download, and installation behavior in Settings
  unchanged.

## Acceptance criteria

- [x] The retranscription picker on a meeting page lists only available models.
- [x] The retranscription picker on a Library recording page lists only
  available models.
- [x] Models that are not downloaded or installed do not appear as disabled
  picker items.
- [x] Selecting a listed model immediately starts retranscription with that
  model.
- [x] No additional retranscription confirmation or “Try Parakeet” modal is
  shown after model selection.
- [x] Focused tests cover model filtering and the direct-start interaction in
  both retranscription entry points.

## Verification

- `swift test --filter RetranscriptionSelectionTests`
- `swift test --filter TranscriptionViewModelTests`
- `swift test --filter MeetingTimedTranscriptRecoveryBannerPresentationTests`
- `swift test` — 5,232 tests passed; 26 skipped
- `git diff --check`

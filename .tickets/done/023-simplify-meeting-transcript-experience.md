---
Assigned-To:
Tags:
  - map
Parent:
Blocked-By: []
---

## Outcome

Make the completed-meeting transcript quieter, denser, and easier to read. Remove the unrelated Discover surface. Keep raw speech evidence while making deterministic cleaned meeting text the normal user-facing transcript.

This is a container ticket. Do not implement it directly.

## Child tickets

- `024-remove-discover-feature`
- `025-prototype-compact-borderless-meeting-transcript`
- `026-implement-compact-borderless-meeting-transcript`
- `027-persist-cleaned-meeting-transcripts`

## Completion criteria

- [x] Discover and its complete supporting feature are removed.
- [x] The owner selects a compact transcript design from downloadable prototype artifacts.
- [x] The selected compact, borderless Reading Turn design ships without losing transcript behavior or performance.
- [x] New and re-transcribed meetings persist separate raw and deterministic cleaned transcripts.
- [x] Normal meeting surfaces use cleaned text independently of the global dictation Raw/Clean preference.
- [x] All child tickets are complete and applicable CI checks pass.

## Resolution

Completed child tickets `024`–`027`. The app no longer contains Discover, completed meetings use separate raw evidence and deterministic cleaned text, and the owner-selected Compact byline Reading Turn design is implemented with preserved performance and interaction contracts. Final implementation merged in PR #26 at commit `b6165a3b`.

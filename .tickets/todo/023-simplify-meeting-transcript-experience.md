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

- [ ] Discover and its complete supporting feature are removed.
- [ ] The owner selects a compact transcript design from downloadable prototype artifacts.
- [ ] The selected compact, borderless Reading Turn design ships without losing transcript behavior or performance.
- [ ] New and re-transcribed meetings persist separate raw and deterministic cleaned transcripts.
- [ ] Normal meeting surfaces use cleaned text independently of the global dictation Raw/Clean preference.
- [ ] All child tickets are complete and applicable CI checks pass.

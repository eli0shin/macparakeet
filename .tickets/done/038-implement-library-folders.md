---
Assigned-To: pi-gpt-5.6-sol-01a08118
Tags: []
Parent:
Blocked-By: []
---

# Implement Library folders

## Request

The user accepted prototype A (sidebar folder tree) and explicitly requests a worker to productionalize it now. Implement this as native production SwiftUI functionality, not a web prototype. Do not review or revise the throwaway prototype. Production work owns this ticket, one stacked worktree, and one PR into main.

## Accepted design sources

- Published prototype: https://artifacts.home.arpa/macparakeet-library-folders/?variant=tree
- Captured source commit: a854a87a32d47143a3c44c096f4fa5db653dbf0c
- Source branch: prototype/037-library-folders-source
- Prototype reference PR: https://github.com/eli0shin/macparakeet/pull/43
- Canonical prototype ticket: /Users/elioshinsky/code/macparakeet/.tickets/in-progress/037-prototype-library-folders.md

The user selected A, not B or C. Use the actual accepted source and artifact to preserve the visual and interaction choices; do not redesign. PR #43 is a reference-only PR, not an implementation dependency. Do not touch its worker or branch.

## Confirmed behavior

- Folders replace the current generic Library categories and support all existing Library item types, including meetings and imported transcripts.
- Library is the filesystem-like root. Items without a folder appear directly at Library root. There is no Unfiled section or label.
- Nested folders are supported. An item belongs to one folder or Library root.
- All Items, if included, is an aggregate view, not a folder or separate category. Preserve the accepted A treatment.
- Use Select, not Select Many. Keep bulk Move to for selected items.
- Each recording has a per-recording ellipsis menu with Open and Move to Folder.
- One contextual + Folder action creates at the current location: top-level at Library root and nested inside a folder. No separate subfolder action.
- Deleting a folder deletes it and its descendants but retains all contained Library items and returns them to Library root. Make this clear in confirmation. Deleting Library items is a separate operation.

## Production requirements and invariants

- Persist folder hierarchy and item membership locally through existing Core/GRDB repository patterns. Provide a safe migration: existing Library items remain intact at Library root. Hierarchy and membership survive app restart.
- Treat folders as Library organization metadata, not a request to relocate or delete managed audio files or meeting artifact directories. Preserve item identity, transcript contents, notes, summaries, chats, media references, and retention behavior.
- Keep existing item open, playback, export, title editing, and explicit item/audio deletion behavior working. Do not change meeting capture, STT, or the dedicated Meetings workspace except where shared Library contract integration requires it.
- Keep database mutations atomic, prohibit invalid hierarchy or dangling membership, and handle recursive folder deletion without deleting recordings. Use existing concurrency and UI action conventions and accessible keyboard/menu behavior.
- Inspect governing Library code, tests, ADRs, UI patterns, and database README before implementation. Update relevant behavior/persistence/boundary contract docs with focused tests where contracts change. Preserve public CLI compatibility; do not invent unrelated CLI features.
- Add proportional focused tests for persistence and migration, nested navigation, creating folders in current location, per-item and bulk movement (including moving to root), and recursive folder deletion retaining items. Test all supported Library item types and integration with existing item operations.
- Verify the native interface against accepted A with representative mixed Library items. Do not copy prototype debug state, variant switcher, or throwaway implementation into production.
- Follow repository focused-test guidance; full suite at most once as the final code-change gate. Production code review is required; the user's no-review instruction was for the prototype.

## Handoff

Open one production PR into main. Explain how the implementation matches accepted A, migration/data safety, focused and final verification, and any remaining limitations. Publish normal worker PR Watch membership. Do not change or clean up the prototype worker.

## Resolution

PR #44 merged into main as `4351b8982571a31a3d985a3e639b46f0083d4ac8` from reviewed head `41fa2b1e057a26496fa9dab16ea5a48d5f937c3c`. CI run `34234124289` passed for that head; independent production review found no actionable issues or ticket/contract violations. No generated files changed; packaging jobs were correctly skipped. Merge compatibility passed with no intervening landing changes. Accepted A is implemented with persisted nested folders, per-item/bulk movement, and recursive folder deletion that retains items at Library root. Prototype PR #43 and its worker remain untouched.



# Library Folders v1

> Status: ACTIVE

## Purpose

Protect the local persistence and data-safety contract for filesystem-like
Library organization.

## Producers

- `LibraryFolderRepository` creates and deletes folder rows.
- `TranscriptionRepository.moveToLibraryFolder` changes item membership.
- `TranscriptionLibraryViewModel` coordinates the native folder tree actions.

## Consumers

- The main Library folder sidebar, breadcrumbs, item queries, item menus, and
  bulk Move to flow.
- Existing transcription detail, playback, export, title editing, deletion,
  meeting, and CLI consumers continue to read the same transcription identity
  and content.

## Stable semantics

- `Library` is the root. A transcription with `libraryFolderID = NULL` is
  directly at that root.
- `All Items` is an aggregate query, not a persisted folder.
- Every file, video, podcast, and meeting transcription can belong to exactly
  one folder or root.
- `library_folders.parentID` supports nesting and cascades folder descendants.
- Deleting a folder tree sets affected transcription memberships to `NULL` in
  the same database transaction. It does not delete transcription rows, source
  media, managed audio, meeting artifact folders, notes, summaries, chats, or
  other child data.
- New and migrated transcription rows default to root.
- Folder names are non-empty after trimming and case-insensitively unique among
  siblings.
- Folder organization is local metadata. It never changes `filePath` or
  `meetingArtifactFolderPath`.
- Public CLI output remains compatible. Folder fields and commands are not part
  of CLI JSON v1.

## Non-stable details

Folder-pane width, symbols, expansion state, sort presentation, timestamps, and
confirmation layout can change without a contract version change. The safety
meaning of confirmation copy cannot change.

## Versioning and compatibility

Additive folder metadata can remain v1. A change that can delete Library items
through folder deletion, assign multiple folders to one item, relocate managed
files, or change root representation requires a new contract version and a safe
migration.

## Tests that enforce this

- `LibraryFolderRepositoryTests`
- Folder-specific tests in `TranscriptionLibraryViewModelTests`
- Library query tests in `TranscriptionRepositoryTests`

## When this changes

Update this contract, `spec/01-data-model.md`, `spec/02-features.md`,
`spec/04-ui-patterns.md`, database migrations, and focused persistence/view-model
tests in the same PR.

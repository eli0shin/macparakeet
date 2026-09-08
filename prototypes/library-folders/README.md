# Library folders prototype

> **Throwaway prototype:** This source-only branch is isolated from the Swift app. It uses frozen synthetic Library data and in-memory state. It has no persistence, migrations, analytics, network requests, or production behavior.

## Open question

Which layout makes the Library feel most like one understandable filesystem while nested folders, mixed recording types, direct item actions, and bulk movement stay clear?

## Decision

**Accepted: A — Sidebar folder tree (`?variant=tree`).** The user selected this variant after reviewing the published prototype. Production implementation remains separate work.

## Review

Open the published artifact: https://artifacts.home.arpa/macparakeet-library-folders/

Or open `index.html` directly:

```bash
open prototypes/library-folders/index.html
```

Use the bottom switcher or the Left and Right Arrow keys:

- `?variant=tree` — permanent folder tree beside Library items;
- `?variant=overview` — folders lead the main content area;
- `?variant=list` — dense recording list with folder navigation and bulk Move to.

## Review flow

All three variants share the same in-memory state:

1. At the Library root, select **+ Folder** and create **Sprint Planning**.
2. Open Sprint Planning. Select the same **+ Folder** action to create **Agenda and decisions** inside it. There is no separate “subfolder” command.
3. Return to the Library root, select **Select**, choose the three newest meetings, and use **Move to…**.
4. Open the destination folder and find the moved meetings.
5. Select a recording’s **•••** action and move that one recording to another folder.
6. Delete Sprint Planning. Confirm that deletion removes it and every folder inside it, but moves its Library items back to the Library root. It does not delete recordings.

The visible state panel shows the current folder, nested folder structure, root item count, selection, demo progress, and recent changes after each action. Reload the page to reset.

## Fixed behavior represented

- The Library root behaves like the top level of a filesystem.
- Existing items begin directly in the Library root. There is no separate Unfiled section.
- All recording types can move into folders.
- A folder can contain other folders.
- **+ Folder** creates at the current location: at the Library root or inside the open folder.
- **Select** enables bulk Move to.
- Each recording has a **•••** menu with Open recording and Move to folder.
- All Items is an aggregate view, not a folder or category.
- Deleting a folder tree keeps its recordings and returns them to the Library root.
- Deleting recordings is separate and is not part of this prototype.

# Library folders prototype reference

The published throwaway prototype compared three Library layouts for nested folders:

- A — sidebar folder tree;
- B — folder-first overview;
- C — list-first folder navigator.

## Confirmed behavior

- Library is the filesystem-like root. There is no separate Unfiled section.
- All Items is an aggregate view, not a folder or category.
- Existing recordings begin at the Library root.
- All recording types can move into one folder, and folders can contain folders.
- The single **+ Folder** action creates a folder at the current location.
- **Select** enables bulk **Move to…**.
- Each recording remains openable and has a **•••** menu with **Move to folder…**.
- Deleting a folder also deletes every folder inside it, but keeps all recordings and moves them to the Library root. Recording deletion is separate.

## Decision

The user accepted **A — sidebar folder tree** after reviewing the published prototype. Production implementation is separate work.

## Artifact and source

- Published artifact: https://artifacts.home.arpa/macparakeet-library-folders/
- Source branch: [`prototype/037-library-folders-source`](https://github.com/eli0shin/macparakeet/tree/prototype/037-library-folders-source/prototypes/library-folders)
- Source commit: [`a854a87a32d47143a3c44c096f4fa5db653dbf0c`](https://github.com/eli0shin/macparakeet/commit/a854a87a32d47143a3c44c096f4fa5db653dbf0c)

The prototype is one self-contained `index.html` file with synthetic in-memory data and no network or persistence. To run the captured source locally:

```bash
git show a854a87a32d47143a3c44c096f4fa5db653dbf0c:prototypes/library-folders/index.html > /tmp/macparakeet-library-folders.html
open /tmp/macparakeet-library-folders.html
```

Use `?variant=tree`, `?variant=overview`, or `?variant=list`, or use the floating switcher and Left and Right Arrow keys.

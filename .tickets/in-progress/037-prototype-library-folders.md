---
Assigned-To: macparakeet@037-prototype-library-folders
Tags: []
Parent:
Blocked-By: []
---

# Prototype Library folders

## Question and scope

Build a throwaway interactive UI prototype to compare three structurally different Library layouts for nested folders. This is a design exploration, not a production feature. Use the prototype skill (UI branch) and artifact skill. Inspect the current Library and its governing docs so the prototype resembles the app and has realistic density. Use synthetic sample data, no real user data or persistence.

## User-confirmed behavior

- Folders replace the current generic Library categories.
- All Library item types can belong to folders, including meetings and imported transcripts.
- Library is the filesystem-like root. Existing items start at that root; there is no separate Unfiled section.
- Folders can contain folders. Each item belongs to one folder or stays directly in Library.
- All Items shows everything as an aggregate view; it is not a folder or a removed category.
- The action is named **Select**, not “Select Many.” Each recording also has a **•••** menu with Open and Move to folder.
- There is one **+ Folder** action. At the Library root it creates a top-level folder; inside a folder it creates there. There is no separate subfolder action.
- Deleting a folder deletes that folder and every folder inside it, but keeps every Library item and returns those items to the Library root. Show clear confirmation. Deleting Library items is a separate action.

## Prototype acceptance

- Compare three layouts: sidebar folder tree, folder-first overview, and list-first with folder navigation/selector and bulk Move to. Keep nested folder navigation usable in each.
- Single browser entry point with variant URL parameter and floating bottom switcher; use the prototype skill. Because the host product is native SwiftUI, represent the surrounding Library shell in the browser rather than adding a production web route.
- Demonstrate creating Sprint Planning, creating a subfolder, moving three meetings into folders, finding them again, and deleting a folder with subfolders while retaining its items.
- Include mixed Library item types, the Library root, All Items, and visible relevant in-memory state. Keep this small and runnable; no production backend, migrations, or test suite work.
- Mark it clearly as a throwaway prototype. Do not claim a layout has been selected: the user must compare them first.

## Publication and source capture

The user explicitly requests publication with artifact. Put index.html at the publication directory root, run `artifact publish <path> --name <short-relevant-name>`, and report the actual returned URL in the PR and ticket. Publication is required, not just local files or screenshots.

Preserve prototype source on a published throwaway branch, out of main, with a commit pointer. The orchestration worker PR targets main, but must contain only a concise design/prototype reference document with confirmed behavior, the open layout question, artifact URL, source branch/commit, and run instructions. Do not merge prototype code into main. The worker owns one executable ticket and one PR; the separate source-only capture branch is not another implementation PR. Production implementation is explicitly out of scope.

## Review handoff

- Published artifact: https://artifacts.home.arpa/macparakeet-library-folders/
- Source branch: `prototype/037-library-folders-source`
- Source commit: `a854a87a32d47143a3c44c096f4fa5db653dbf0c`
- Review variants with `?variant=tree`, `?variant=overview`, and `?variant=list`, or the floating switcher.

## Decision

The user accepted **A — sidebar folder tree** after reviewing the published prototype. Production implementation remains separate work.


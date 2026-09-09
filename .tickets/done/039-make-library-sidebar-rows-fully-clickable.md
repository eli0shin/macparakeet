---
Assigned-To: macparakeet@039-make-library-sidebar-rows-fully-clickable
Tags: []
Parent:
Blocked-By: []
---

# Make Library sidebar rows fully clickable

## Report

Only the label text of Library sidebar items is clickable. The user expects the whole visible row to be clickable.

## Requested behavior

Make the full row hit area select its Library location, including the icon, label, padding, and unused horizontal space. Apply this consistently to Library root, nested folder rows, and any aggregate location shown in the Library sidebar.

## Acceptance

- Clicking anywhere in a row's visible bounds selects that location, not only its text.
- Folder disclosure controls remain independently usable and do not unexpectedly navigate when toggled.
- Existing context menus, keyboard navigation, focus, and accessibility behavior remain usable.
- Preserve the accepted sidebar layout and folder data; do not redesign the sidebar.
- Add focused verification appropriate to the hit-area change, including clicks on blank row space and nested rows.

## Resolution

PR #47 merged into main as `567311e2e2f8e6aec7becaa6536853ef62b56efa` from reviewed head `40825d14c780a35d81d855e6ea2b9b472afcbe55`. CI run `34262284119` passed for that head. Independent review found no issues; interaction tests cover blank row space, nested selection, and disclosure independence. No generated output changed or was required. Merge compatibility passed with no intervening landing changes.


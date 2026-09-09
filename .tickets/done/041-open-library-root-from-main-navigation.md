---
Assigned-To: macparakeet@041-open-library-root-from-main-navigation
Tags: []
Parent:
Blocked-By: []
---

# Open Library root from main navigation

## Report

Clicking Library in the main app sidebar currently returns to the last-used Library location. The user wants that navigation action to always open the Library root.

## Requested behavior

Every click on the main app sidebar's Library navigation item selects Library and resets its folder location to Library root, including when Library is already selected. Library root is not the aggregate All Items view.

## Acceptance

- From a nested folder, clicking the main Library navigation item opens Library root.
- After leaving Library for another app section, clicking Library opens root instead of restoring the previous folder or aggregate location.
- Repeated clicks while already in Library also resolve to root.
- Normal navigation within the Library folder tree still works; do not reset to root on ordinary view refreshes or folder selection.
- Do not modify folder hierarchy, item membership, or other persisted Library data.
- Add focused navigation/state regression tests and verify the main sidebar interaction in the app.

## Resolution

PR #48 merged into main as `6b2959503ef339517861c273a3f1162223a5786c` from reviewed head `2bf740538a9423f71311c8124ec6b84d9e60263c`. CI run `34268253847` passed for that head. Independent review found no issues or unresolved requests. Native production-row interaction checks and state tests cover root/detail reset and unchanged folder navigation; the complete List interaction harness limitation remains documented in the PR and was accepted. #46/#47 behavior is preserved. No generated changes were required; merge compatibility passed.


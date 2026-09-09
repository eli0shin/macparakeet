---
Assigned-To: macparakeet@043-restore-library-header-button-design
Tags: []
Parent:
Blocked-By: []
---

# Restore the intended Library header button design

## User correction

The user rejects the result of ticket 040 / PR #46. The intended request was to make the new New Folder and Select buttons match the existing design system. New Transcription already had the correct design and must have been preserved as the reference. Instead, PR #46 changed the established buttons to match the new, undersized controls. Merely applying a shared modifier is not proof of visual compliance.

## Required correction

- Restore the accepted pre-#46 appearance of New Transcription, including its size, typography, padding, shape, and interaction states.
- Bring New Folder and Select into that established visual system, with the appropriate secondary action hierarchy. Do not copy the rejected small-button appearance onto other controls.
- Audit the other button changes made by PR #46 and undo collateral visual regressions caused by that same mistaken interpretation. Keep this limited to restoring the intended Library header and affected shared selection controls, not a new app-wide redesign.

## References

- Rejected change: https://github.com/eli0shin/macparakeet/pull/46, merge commit 8228a2e10bb070bfd1307aa26e7d57f68ae460fe.
- Pre-change reference: 567311e2e2f8e6aec7becaa6536853ef62b56efa. Inspect New Transcription as it appeared there, alongside governing UI patterns and existing native controls.
- Supersedes the visual interpretation accepted in ticket 040. The user's correction is authoritative if that ticket or PR description conflicts with it.

## Acceptance

- New Transcription retains its established pre-#46 appearance; it is not reduced to match the rejected new controls.
- New Folder and Select have compatible size, typography, padding, and visual quality while retaining appropriate action hierarchy.
- Verify actual rendered root, nested-folder, and selection states. Supply before/after visual evidence and request user visual acceptance before merge; code-path review, successful builds, or modifier names alone are not sufficient.
- Preserve action behavior, enabled conditions, accessibility, keyboard access, the full-row Library hit areas from #47, and root-navigation behavior from #48.
- Do not change folder hierarchy, item membership, or other user data. Avoid unrelated refactoring.

## Resolution

User explicitly approved the visual result. Approval recorded at https://github.com/eli0shin/macparakeet/pull/49#issuecomment-5592232586. PR #49 merged into main as `2ee7b5e18d76ba0798348db6636edba5273c3786` from reviewed head `04215b5d1184906ac81131bb59a30a8167178126`. CI run `34280210653` passed for that head. Independent follow-up review confirmed corrected fixture membership and active-selection evidence, with no actionable findings. Generated screenshots were inspected; capture limitations remain documented. Merge compatibility passed.


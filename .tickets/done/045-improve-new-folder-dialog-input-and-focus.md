---
Assigned-To: macparakeet@045-improve-new-folder-dialog-input-and-focus
Tags: []
Parent:
Blocked-By: []
---

# Improve New Folder dialog input and initial focus

## User report

The folder-name input in the New Folder dialog is much too small. Cancel receives initial focus instead of the input.

## Requested correction

- Make the folder-name field comfortably sized and readable, using established app dialog dimensions, typography, and padding. Expand the dialog if needed instead of squeezing the field.
- Focus the name field when the dialog opens so the user can immediately type. Do not initially focus Cancel. Apply on every opening, including creation inside nested folders.

## Acceptance

- Opening New Folder at Library root or within a folder puts keyboard input directly into the name field without a click or Tab.
- The field has usable visible width and height for ordinary multiword folder names.
- Preserve existing validation, destination, creation, cancellation, Return/Escape behavior, and accessible focus navigation.
- Add focused interaction verification for initial focus and typing on repeated openings.
- Provide rendered visual evidence and request user visual approval before merge. Do not restyle unrelated controls or change folder data semantics.

## Resolution

User explicitly approved PR #51 visually; recorded at https://github.com/eli0shin/macparakeet/pull/51#issuecomment-5593308946. Merged into main as `5e741ae774023a2ad2d426b824d30b3db6b16c24` from reviewed head `1d9a783f1164ccf41506583157a79f81976bd786`. CI run `34289345432` passed; independent review found no actionable issues. Committed dialog image inspected; direct dialog interaction tests cover focus, dimensions, and typing across repeated openings. Merge compatibility passed.


---
Assigned-To: macparakeet@049-preserve-media-url-field-accessible-value
Tags: []
Parent:
Blocked-By: []
---

# Preserve the media URL field's accessible value

## Finding

Post-merge review of PR #50, commit 9fd2b12091379292457096c870439db5ce4bf1df, found that TranscribeView.swift's media URL text field overrides accessibilityValue with Valid media URL or an empty string. This replaces the actual entered URL in the accessibility value, preventing VoiceOver users from identifying the pasted link through that value.

## Correction

Preserve the native editable text field's accessible value containing the entered URL. Remove the validation-status value override; expose validation feedback through a separate accessible status or appropriate hint if needed. Keep URL entry, normalization, validation, submission, paste, and the newly accepted page layout unchanged.

## Acceptance

- Accessibility value reflects the actual field text for valid and invalid nonempty input, and remains usable while editing.
- Validation feedback does not replace or obscure the field value.
- Add focused accessibility regression verification and keep existing URL behavior checks passing.
- Keep this a narrow accessibility fix; no unrelated visual changes or provider changes.

Reference: https://github.com/eli0shin/macparakeet/pull/50. This is a follow-up to an already merged change, not a revision of that worker branch.

## Resolution

PR #53 merged into main as `9f8e95816f980cdfd48341d97828250a6489194d` from reviewed head `1ccb2fd071219847a67e6325d821bcc60178725e`. CI run `34291293212` passed for that head; independent review found no issues. Native accessible-value override removed, with regression coverage for valid and invalid nonempty text. No generated output changed or needed regeneration. Merge compatibility passed: no shared paths or known dependency with intervening #51.


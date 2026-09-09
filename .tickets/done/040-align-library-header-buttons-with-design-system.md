---
Assigned-To: macparakeet@040-align-library-header-buttons-with-design-system
Tags: []
Parent:
Blocked-By: []
---

# Align Library header buttons with the design system

## Request

The user reports that Library header buttons do not follow the app's design system. Align their presentation with the existing native app conventions.

## Scope

Inspect the current Library header actions and governing UI patterns. Reuse existing design-system components, styles, tokens, and `.parakeetAction(...)` conventions instead of adding a new button style. Include folder and selection-related header states where those actions appear.

## Acceptance

- Header buttons use the established visual hierarchy, sizing, spacing, typography, icons, and interaction states appropriate to their actions.
- Primary, secondary, and destructive actions follow existing app conventions; do not tint the whole hosting root.
- Button behavior, enabled conditions, keyboard access, accessibility labels, and folder navigation remain unchanged.
- Verify normal Library root, nested folder, and selection header states against the governing UI patterns and representative existing app controls.
- Keep this a focused design-system correction, not a Library redesign.

## Resolution

PR #46 merged into main as `8228a2e10bb070bfd1307aa26e7d57f68ae460fe` from reviewed head `10b0d6adb815cdadeb067198ed6add5427c59f4f`. CI run `34263895205` passed for that head; independent review found no issues or unresolved feedback. The update onto main preserves #47 full-row hit areas and independent disclosure controls. No generated changes were required. Merge compatibility passed.


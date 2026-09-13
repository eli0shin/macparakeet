---
Assigned-To: macparakeet@060-make-transcript-find-input-nonblocking
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By: []
---

# Make transcript find input nonblocking

## Problem

`TranscriptFindModel` currently scans every search block synchronously on the
main actor from the find field binding setter. SwiftUI cannot process the next
key event while that setter is running. On a long synthetic meeting, a
one-letter query spent about 136 ms matching before any highlight layout. This
explains delayed and missing-looking input when the user types faster than each
search completes.

## What to build

Separate the find field's draft query from settled search results. Publish each
field edit immediately, debounce superseded work, perform matching outside the
main actor, and use a generation or equivalent identity to reject stale results.
Cancellation must be checked during long scans, not only before they start.

Keep case-insensitive and diacritic-insensitive matching, UTF-16 ranges, match
ordering, counters, wrapping next/previous navigation, and query-with-spaces
behavior.

## Acceptance criteria

- [ ] The field displays every rapid edit through a sequence such as `e`, `en`,
  `eng`, `engi`, `engin`, `engine` without waiting for any scan.
- [ ] The main-thread field-edit handler remains below a documented one-frame
  budget on a public-safe long-meeting fixture.
- [ ] Only the latest query can publish matches; cleared and replaced queries
  cannot receive stale results.
- [ ] Superseded scans are debounced or cancelled, and long scans observe
  cancellation at bounded intervals.
- [ ] Empty and whitespace-only queries clear promptly. Match semantics and
  keyboard navigation remain covered by focused tests.
- [ ] The UI exposes a non-blocking searching state instead of reporting a
  transient false “No results.”

## Resolution

Implemented immediate draft-query publication, debounced off-main matching,
bounded cancellation checks, stale-generation rejection, and a non-blocking
searching state. Focused coverage and CI passed. Merged as
[PR #72](https://github.com/eli0shin/macparakeet/pull/72) in commit
`6226045c`.

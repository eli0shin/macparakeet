---
Assigned-To:
Tags:
  - performance
Parent: 059-make-meeting-transcript-detail-responsive
Blocked-By: []
---

# Precompute transcript-derived display data

## Problem

Transcript rendering reaches transcript-scale derived work from SwiftUI body
properties and view builders. Examples include cleaned/preferred transcript
text, text word counts, speaker statistics, speaker maps, and find-block maps.
Body evaluation can occur for focus, hover, playback, search, and unrelated
state changes. Even individually moderate scans become persistent lag when they
repeat during interaction.

## What to build

Extend the versioned transcript detail preparation snapshot with all immutable
or version-keyed display data needed by the header, speaker overview, Text
surface, and Reading surface. Prepare transcript-scale values off the main
actor, publish them atomically for the selected transcription, and define exact
invalidation keys for transcript edits, speaker renames, custom words, and
status changes.

## Acceptance criteria

- [ ] SwiftUI body evaluation performs no full transcript cleaning, splitting,
  timestamp scan, speaker-statistics scan, or all-match regrouping.
- [ ] Word counts, preferred text, speaker statistics, speaker labels/colors,
  and search blocks come from a prepared versioned snapshot or bounded cache.
- [ ] Snapshot preparation remains off the main actor and stale results cannot
  replace the selected recording.
- [ ] Transcript edits, speaker renames, custom-word changes, retranscription,
  and status changes invalidate exactly the affected values.
- [ ] Repeated hover, focus, playback, and unrelated control updates cause zero
  calls to instrumented transcript-scale derivation functions.
- [ ] Initial cached content remains correct while an updated snapshot prepares;
  no previous recording's values appear in the new detail.

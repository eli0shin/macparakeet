# Ticket 047 visual evidence

The production `MeetingReadingTurnContentView` was rendered in light mode at
700 × 420 points with the same four canonical Reading Turns.

- `before.png` renders the canonical turns directly and shows three consecutive
  **Me** bylines and timestamps.
- `after.png` applies `MeetingTranscriptDisplayBuilder` and shows one **Me**
  byline, one `10:00` seek target, and all three paragraphs in order with one
  line break and no empty separator line. The intervening **Alex** contribution
  remains separate.

Regenerate both images with:

```bash
MEETING_TRANSCRIPT_GROUPING_EVIDENCE_DIR="$PWD/docs/visual-evidence/ticket-047" \
  swift test --filter MeetingTranscriptGroupingVisualEvidenceTests
```

Explicit user visual approval is required before merge.

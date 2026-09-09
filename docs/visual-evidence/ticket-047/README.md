# Ticket 047 render artifacts — not release validation

These images came from an isolated test host, not the running release app.
They do not validate paragraph spacing in the completed-meeting UI. The earlier
claim that `after-one-empty-row.png` proved exactly one empty text row was wrong.
The release UI removed blank lines despite that claim.

- `before.png` renders four fixture Reading Turns directly.
- `after-one-empty-row.png` renders the former display grouping code, which
  removed empty lines and joined contributions with a single newline.

The corrected display builder preserves paragraph breaks and joins consecutive
same-speaker contributions with `\n\n`. Check spacing in the running app with
wrapped paragraphs and the actual transcript font. Do not use these images or
regenerated test-host screenshots as acceptance evidence.

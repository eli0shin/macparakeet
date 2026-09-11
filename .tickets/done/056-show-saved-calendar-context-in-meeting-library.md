---
Assigned-To: macparakeet@056-show-saved-calendar-context-in-meeting-library
Tags:
  - calendar
  - meetings
  - library
Parent:
Blocked-By: []
---

# Show saved calendar context in the meeting Library

## Problem

Meeting recordings can persist a `MeetingCalendarSnapshot` with the scheduled
time, participants, organizer, meeting service, URL, and match confidence. The
Meetings Library does not present that data. Its lightweight list projection
explicitly returns `NULL AS calendarEventSnapshot`, and the full meeting detail
receives the snapshot but does not render it.

## Scope

- Surface useful saved calendar context in Recent Meetings without turning each
  row into a dense event inspector.
- Add a clear calendar section to saved meeting detail with the scheduled time,
  meeting service, participants, organizer, and confidence when available.
- Make a saved meeting URL actionable.
- Preserve the distinction between a confirmed calendar auto-start match and a
  probable overlap inferred for a manual recording. Do not imply certainty for
  probable matches.
- Include only the bounded calendar data needed by list rows in lightweight
  Library loading. Keep full details on demand.
- Degrade cleanly for legacy meetings and recordings with no calendar match.
- Keep all calendar context local unless the user explicitly exports or shares
  an existing meeting artifact.

## Acceptance criteria

- [ ] A saved meeting with calendar context visibly indicates the calendar
  connection in Recent Meetings.
- [ ] Opening that meeting shows the available schedule, service, organizer,
  and participants.
- [ ] The meeting URL can be opened from saved meeting detail.
- [ ] Probable matches have clear copy and are not presented as confirmed.
- [ ] Meetings without a snapshot keep the current clean layout with no empty
  calendar section.
- [ ] Calendar context remains visible after app restart, meeting recovery,
  transcription retry, and audio retention or deletion.
- [ ] The normal Recent Meetings page remains responsive with large transcripts
  and many saved meetings.
- [ ] Completion includes a manual pass with confirmed, probable, partial, and
  absent calendar snapshots.

## Out of scope

- Searching or filtering by calendar title, participant, organizer, or service.
- Editing Calendar events from MacParakeet.
- Reconstructing calendar context for historical meetings that never saved it.

## Resolution

Implemented by PR #70 and squash-merged as `19d10b59`. Required CI passed for
head `db2bea55`. Recent Meetings now shows confirmed or probable calendar
connection state, and saved meeting detail presents the available schedule,
service, organizer, participants, confidence, and safe meeting-link action.
List loading retains only bounded match data; full context loads on demand.

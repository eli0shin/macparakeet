---
Assigned-To: macparakeet@054-pull-and-present-calendar-participant-details
Tags:
  - calendar
  - meetings
Parent:
Blocked-By: []
---

# Pull and present calendar participant details

## Problem

MacParakeet reads EventKit attendees and an organizer into `CalendarEvent`, but
the user-facing calendar experience reduces that information to a person count.
The email extraction path uses private KVC and has no demonstrated behavior with
real calendars. A user cannot see who a meeting is with before recording it.

## Scope

- Pull the participant and organizer details that macOS Calendar makes
  available for events from supported local calendar accounts.
- Use supported EventKit data where possible. Degrade cleanly when a provider
  does not expose a name, email address, RSVP state, or organizer.
- Present available participant names and the organizer in the Upcoming meeting
  experience. Show useful partial data instead of hiding the complete section.
- Keep participant data local. Do not add names, email addresses, or participant
  counts to telemetry.
- Preserve the existing event filters and current-user exclusion behavior.

## Acceptance criteria

- [ ] A real event from Apple Calendar with participants shows the available
  participant names in MacParakeet before the meeting starts.
- [ ] The organizer is identified when EventKit provides one.
- [ ] Events from locally available calendar account types degrade correctly
  when some fields are unavailable.
- [ ] Duplicate participant entries and the current user are not shown as other
  participants.
- [ ] Missing email addresses or names do not remove otherwise useful people.
- [ ] Calendar permission denial and events without participants remain clear,
  usable states.
- [ ] Real-calendar manual verification records what EventKit actually exposes;
  mocked model coverage alone is not sufficient to call the feature complete.

## Out of scope

- Searching or filtering the Library by participant.
- Adding Google or Microsoft sign-in flows outside macOS Calendar/EventKit.
- Sending participant information to an LLM or telemetry.

## Resolution

Implemented by PR #67 and squash-merged as `b2cc5fe7`. Required CI passed for
head `8609536f`. Real EventKit behavior was then validated with a signed app:
Organizer and With rows displayed without duplicating the current user or
organizer, and an event without attendees kept the compact row. The redacted
validation record landed through follow-up PR #69 as `a5d49b35`.

# EventKit calendar participant details

## Supported data source

MacParakeet reads participants only from EventKit. Apple documents that:

- `EKCalendarItem.attendees` returns the read-only participants for a calendar item and is `nil` when there are no attendees.[^attendees]
- `EKEvent.organizer` returns an `EKParticipant` and is `nil` when the event has no organizer.[^organizer]
- `EKParticipant` exposes `name`, attendance status, `isCurrentUser`, and `url`. A participant can also represent a group, room, or other resource.[^participant]

The macOS SDK declares `EKParticipant.URL` as public API. MacParakeet now reads that property directly instead of using Key-Value Coding. It accepts an email address only when the URL uses the `mailto` scheme. Other provider URLs remain unavailable as email addresses. A missing name, email address, RSVP status, or organizer does not cause the event or another available field to be dropped.

MacParakeet does not query Contacts. It does not add a Contacts permission requirement, and it does not send participant data to telemetry or a remote service.

## Real-calendar verification record

Verified on September 10, 2026 with a signed development app and a real invitation in a calendar configured in macOS Calendar. Personal values were not copied into this record.

For the invitation, EventKit exposed:

- two attendees;
- a name and a `mailto` URL for both attendees;
- one attendee with `isCurrentUser == true`;
- an organizer with both a name and a `mailto` URL.

**Meetings → Upcoming** showed the organizer on a separate `Organizer:` line and one other person on the `With:` line. It did not repeat the current user or organizer under `With:`. A separate real event with no attendees and no organizer kept the compact title, schedule, and calendar row without an empty people section.

The invitation was already in progress when inspected. This pass proves the EventKit field extraction and Upcoming presentation before recording starts, but it does not prove display before the scheduled event start. The configured account provider type was not recorded, so no claim is made for a specific iCloud, Google, or Exchange field set.

| Real Calendar case | Participant name | `mailto` URL | RSVP state | Organizer | Upcoming result |
| --- | --- | --- | --- | --- | --- |
| Invitation with two attendees | Both exposed | Both exposed | Calendar exposed accepted and unknown states | Name and `mailto` URL exposed | Separate organizer and one other participant; no current-user or organizer duplicate |
| Event without attendees | Not applicable | Not applicable | Not applicable | Not exposed | No empty participant section |

Automated coverage supplies the unavailable-field cases that could not be produced with this account: name-only, email-only, no identity fields, equal names with distinct identities, and duplicate provider identities. A future provider matrix is still useful when iCloud, Google, and Exchange accounts are available on one test Mac; this validation does not infer provider behavior that was not observed.

[^attendees]: Apple Developer Documentation, [EKCalendarItem.attendees](https://developer.apple.com/documentation/eventkit/ekcalendaritem/attendees).
[^organizer]: Apple Developer Documentation, [EKEvent.organizer](https://developer.apple.com/documentation/eventkit/ekevent/organizer).
[^participant]: Apple Developer Documentation, [EKParticipant](https://developer.apple.com/documentation/eventkit/ekparticipant).

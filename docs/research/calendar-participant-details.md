# EventKit calendar participant details

## Supported data source

MacParakeet reads participants only from EventKit. Apple documents that:

- `EKCalendarItem.attendees` returns the read-only participants for a calendar item and is `nil` when there are no attendees.[^attendees]
- `EKEvent.organizer` returns an `EKParticipant` and is `nil` when the event has no organizer.[^organizer]
- `EKParticipant` exposes `name`, attendance status, `isCurrentUser`, and `url`. A participant can also represent a group, room, or other resource.[^participant]

The macOS SDK declares `EKParticipant.URL` as public API. MacParakeet now reads that property directly instead of using Key-Value Coding. It accepts an email address only when the URL uses the `mailto` scheme. Other provider URLs remain unavailable as email addresses. A missing name, email address, RSVP status, or organizer does not cause the event or another available field to be dropped.

MacParakeet does not query Contacts. It does not add a Contacts permission requirement, and it does not send participant data to telemetry or a remote service.

## Real-calendar verification record

Verification was attempted from this checkout with:

```console
$ swift run macparakeet-cli calendar upcoming --days 7 --filter all
Error: Calendar access not yet requested. Launch MacParakeet, run onboarding (or visit Settings → Calendar), then retry.
```

The installed app CLI returned the same authorization state. This development machine therefore did not expose a real event to the process, so no provider-specific participant fields were recorded. Before release, repeat the command after granting the packaged app Calendar access and record only field availability, not personal values, in this table:

| Local Calendar account | Participant name | `mailto` URL | RSVP status | Organizer | Notes |
| --- | --- | --- | --- | --- | --- |
| iCloud | Not verified | Not verified | Not verified | Not verified | Calendar access was not determined on the development machine. |
| Google through macOS Calendar | Not verified | Not verified | Not verified | Not verified | Requires a locally configured account and a real invitation. |
| Exchange through macOS Calendar | Not verified | Not verified | Not verified | Not verified | Requires a locally configured account and a real invitation. |

For the UI pass, enable Calendar reminders, open **Meetings → Upcoming**, and verify these cases:

1. An invitation with names shows `Organizer:` and `With:` details before start.
2. A participant with no name uses the available email address.
3. A participant with neither field remains visible as `Participant`.
4. The current user, organizer duplicates, and repeated attendees do not appear under `With:`.
5. An event with no participants keeps the current compact event row, and denied Calendar permission keeps the current recovery state.

[^attendees]: Apple Developer Documentation, [EKCalendarItem.attendees](https://developer.apple.com/documentation/eventkit/ekcalendaritem/attendees).
[^organizer]: Apple Developer Documentation, [EKEvent.organizer](https://developer.apple.com/documentation/eventkit/ekevent/organizer).
[^participant]: Apple Developer Documentation, [EKParticipant](https://developer.apple.com/documentation/eventkit/ekparticipant).

---
Assigned-To: macparakeet@055-make-calendar-meeting-reminders-work-end-to-end
Tags:
  - calendar
  - meetings
Parent:
Blocked-By: []
---

# Make calendar meeting reminders work end to end

## Problem

Reminder decision logic and `UNUserNotificationCenter` calls exist, but the
feature has not been demonstrated end to end with a real calendar event and a
packaged MacParakeet app. Missed authorization or delivery currently produces
only logs. The late-join path is explicitly a no-op, and reminder notifications
do not provide a useful action for joining or opening the meeting.

## Scope

- Deliver a reliable reminder at the configured lead time, including the
  **At start time** setting.
- Make Calendar and Notifications permission state visible and recoverable from
  the Meetings surface.
- Include the meeting title, start time, and detected meeting service in the
  reminder when available.
- Let the user open the meeting URL directly from a reminder when EventKit
  provides one. Provide a useful MacParakeet action when no URL exists.
- Implement the current late-join monitor outcome instead of discarding it.
  A late-start notice must let the user start recording and must not start a
  recording without confirmation unless Auto-start already permits that action.
- Avoid duplicate reminders for one occurrence while still handling recurring
  and rescheduled events correctly.
- Keep reminders local and silent unless the existing product sound policy is
  deliberately changed.

## Acceptance criteria

- [ ] With a real event and packaged app, each lead-time option delivers at the
  expected time while MacParakeet is in the foreground or background.
- [ ] A denied or revoked Notifications permission produces an actionable state
  before the reminder is lost.
- [ ] Clicking a reminder with a meeting URL opens that URL.
- [ ] A meeting detected after its normal start window offers a functional
  late-join/start-recording action.
- [ ] Recurring, rescheduled, declined, all-day, and excluded-calendar events
  keep the existing eligibility rules and do not produce duplicate notices.
- [ ] Restarting the app or waking the Mac near a meeting does not silently miss
  a still-actionable reminder.
- [ ] Completion is based on real notification delivery and interaction, not
  only mocked monitor tests.

## Out of scope

- Calendar-event search.
- Scheduled meeting auto-stop.
- Remote calendar-provider sign-in outside EventKit.

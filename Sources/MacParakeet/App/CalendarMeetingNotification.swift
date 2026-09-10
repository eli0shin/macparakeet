import Foundation
import MacParakeetCore
import UserNotifications

/// The local notification contract for calendar reminders and late-start notices.
/// Values in `userInfo` are property-list types so macOS can persist and restore
/// the action after the app restarts.
enum CalendarMeetingNotification {
    static let reminderWithLinkCategory = "MACPARAKEET_CALENDAR_REMINDER_WITH_LINK"
    static let reminderWithoutLinkCategory = "MACPARAKEET_CALENDAR_REMINDER_WITHOUT_LINK"
    static let lateStartWithLinkCategory = "MACPARAKEET_CALENDAR_LATE_START_WITH_LINK"
    static let lateStartWithoutLinkCategory = "MACPARAKEET_CALENDAR_LATE_START_WITHOUT_LINK"

    static let joinAction = "MACPARAKEET_JOIN_MEETING"
    static let startRecordingAction = "MACPARAKEET_START_MEETING_RECORDING"
    static let openMeetingsAction = "MACPARAKEET_OPEN_MEETINGS"

    private enum UserInfoKey {
        static let eventID = "eventID"
        static let title = "title"
        static let startTime = "startTime"
        static let endTime = "endTime"
        static let meetingURL = "meetingURL"
        static let encodedEvent = "encodedEvent"
    }

    struct Response: Sendable, Equatable {
        let actionIdentifier: String
        let event: CalendarEvent

        var meetingURL: URL? {
            event.meetUrl.flatMap(URL.init(string:))
        }
    }

    static func registerCategories(on center: UNUserNotificationCenter) {
        let join = UNNotificationAction(
            identifier: joinAction,
            title: "Join Meeting",
            options: []
        )
        let start = UNNotificationAction(
            identifier: startRecordingAction,
            title: "Start Recording",
            options: [.foreground]
        )
        let open = UNNotificationAction(
            identifier: openMeetingsAction,
            title: "Open Meetings",
            options: [.foreground]
        )

        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: reminderWithLinkCategory,
                actions: [join, start],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: reminderWithoutLinkCategory,
                actions: [open, start],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: lateStartWithLinkCategory,
                actions: [join, start],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: lateStartWithoutLinkCategory,
                actions: [start, open],
                intentIdentifiers: []
            ),
        ])
    }

    static func reminderContent(for event: CalendarEvent, leadMinutes: Int) -> UNMutableNotificationContent {
        let content = baseContent(for: event)
        content.title = event.title
        content.subtitle =
            leadMinutes == 0
            ? "Starting now · \(formattedStartTime(event.startTime))" : formattedStartTime(event.startTime)
        content.body = serviceDescription(for: event)
        content.categoryIdentifier =
            event.meetUrl == nil
            ? reminderWithoutLinkCategory
            : reminderWithLinkCategory
        return content
    }

    static func lateStartContent(for event: CalendarEvent) -> UNMutableNotificationContent {
        let content = baseContent(for: event)
        content.title = "Did you join \(event.title)?"
        content.subtitle = "Started at \(formattedStartTime(event.startTime))"
        content.body = "\(serviceDescription(for: event)) · Start recording when you are ready."
        content.categoryIdentifier =
            event.meetUrl == nil
            ? lateStartWithoutLinkCategory
            : lateStartWithLinkCategory
        return content
    }

    static func reminderIdentifier(for event: CalendarEvent) -> String {
        "macparakeet.calendar.reminder.\(event.dedupeKey)"
    }

    static func lateStartIdentifier(for event: CalendarEvent) -> String {
        "macparakeet.calendar.late-start.\(event.dedupeKey)"
    }

    static func response(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> Response? {
        if let encodedEvent = userInfo[UserInfoKey.encodedEvent] as? String,
            let data = encodedEvent.data(using: .utf8),
            let event = try? JSONDecoder().decode(CalendarEvent.self, from: data)
        {
            return Response(actionIdentifier: actionIdentifier, event: event)
        }

        // Keep a field-by-field fallback so already-delivered notifications
        // from an older app build still open and start a recording.
        guard let eventID = userInfo[UserInfoKey.eventID] as? String,
            let title = userInfo[UserInfoKey.title] as? String,
            let startInterval = userInfo[UserInfoKey.startTime] as? TimeInterval,
            let endInterval = userInfo[UserInfoKey.endTime] as? TimeInterval
        else {
            return nil
        }

        let meetingURL = userInfo[UserInfoKey.meetingURL] as? String
        return Response(
            actionIdentifier: actionIdentifier,
            event: CalendarEvent(
                id: eventID,
                title: title,
                startTime: Date(timeIntervalSinceReferenceDate: startInterval),
                endTime: Date(timeIntervalSinceReferenceDate: endInterval),
                meetUrl: meetingURL
            )
        )
    }

    private static func baseContent(for event: CalendarEvent) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        var userInfo: [String: Any] = [
            UserInfoKey.eventID: event.id,
            UserInfoKey.title: event.title,
            UserInfoKey.startTime: event.startTime.timeIntervalSinceReferenceDate,
            UserInfoKey.endTime: event.endTime.timeIntervalSinceReferenceDate,
        ]
        if let meetingURL = event.meetUrl {
            userInfo[UserInfoKey.meetingURL] = meetingURL
        }
        if let data = try? JSONEncoder().encode(event),
            let encodedEvent = String(data: data, encoding: .utf8)
        {
            userInfo[UserInfoKey.encodedEvent] = encodedEvent
        }
        content.userInfo = userInfo
        content.sound = nil
        return content
    }

    private static func serviceDescription(for event: CalendarEvent) -> String {
        event.meetUrl.flatMap(MeetingLinkParser.shared.identifyService) ?? "MacParakeet meeting"
    }

    private static func formattedStartTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

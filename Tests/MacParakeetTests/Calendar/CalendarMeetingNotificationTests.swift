import UserNotifications
import XCTest
@testable import MacParakeet
@testable import MacParakeetCore

final class CalendarMeetingNotificationTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testReminderIncludesCalendarDetailsAndJoinActionContract() throws {
        let event = CalendarEvent(
            id: "event-1",
            title: "Roadmap Review",
            startTime: start,
            endTime: start.addingTimeInterval(1800),
            meetUrl: "https://meet.google.com/abc-defg-hij"
        )

        let content = CalendarMeetingNotification.reminderContent(for: event, leadMinutes: 5)

        XCTAssertEqual(content.title, "Roadmap Review")
        XCTAssertFalse(content.subtitle.isEmpty, "The reminder must include the local start time")
        XCTAssertEqual(content.body, "Google Meet")
        XCTAssertEqual(content.categoryIdentifier, CalendarMeetingNotification.reminderWithLinkCategory)
        XCTAssertNil(content.sound)

        let response = try XCTUnwrap(
            CalendarMeetingNotification.response(
                actionIdentifier: CalendarMeetingNotification.joinAction,
                userInfo: content.userInfo
            ))
        XCTAssertEqual(response.actionIdentifier, CalendarMeetingNotification.joinAction)
        XCTAssertEqual(response.event.id, event.id)
        XCTAssertEqual(response.event.title, event.title)
        XCTAssertEqual(response.event.startTime, event.startTime)
        XCTAssertEqual(response.event.endTime, event.endTime)
        XCTAssertEqual(response.meetingURL?.absoluteString, event.meetUrl)
    }

    func testAtStartReminderSaysStartingNow() {
        let event = CalendarEvent(
            id: "event-2",
            title: "Standup",
            startTime: start,
            endTime: start.addingTimeInterval(900)
        )

        let content = CalendarMeetingNotification.reminderContent(for: event, leadMinutes: 0)

        XCTAssertTrue(content.subtitle.hasPrefix("Starting now"))
        XCTAssertEqual(content.body, "MacParakeet meeting")
        XCTAssertEqual(content.categoryIdentifier, CalendarMeetingNotification.reminderWithoutLinkCategory)
    }

    func testOccurrenceIdentifiersSeparateRecurringAndRescheduledEvents() {
        let first = CalendarEvent(
            id: "recurring-event",
            title: "Weekly Sync",
            startTime: start,
            endTime: start.addingTimeInterval(1800)
        )
        var nextOccurrence = first
        nextOccurrence.startTime = start.addingTimeInterval(7 * 24 * 60 * 60)
        nextOccurrence.endTime = nextOccurrence.startTime.addingTimeInterval(1800)

        XCTAssertNotEqual(
            CalendarMeetingNotification.reminderIdentifier(for: first),
            CalendarMeetingNotification.reminderIdentifier(for: nextOccurrence)
        )
        XCTAssertNotEqual(
            CalendarMeetingNotification.lateStartIdentifier(for: first),
            CalendarMeetingNotification.lateStartIdentifier(for: nextOccurrence)
        )
    }

    func testLateStartNoticeOffersConfirmedRecordingAction() {
        let event = CalendarEvent(
            id: "event-3",
            title: "Design Review",
            startTime: start,
            endTime: start.addingTimeInterval(1800)
        )

        let content = CalendarMeetingNotification.lateStartContent(for: event)
        let response = CalendarMeetingNotification.response(
            actionIdentifier: CalendarMeetingNotification.startRecordingAction,
            userInfo: content.userInfo
        )

        XCTAssertEqual(content.title, "Did you join Design Review?")
        XCTAssertTrue(content.subtitle.hasPrefix("Started at"))
        XCTAssertEqual(content.categoryIdentifier, CalendarMeetingNotification.lateStartWithoutLinkCategory)
        XCTAssertEqual(response?.actionIdentifier, CalendarMeetingNotification.startRecordingAction)
        XCTAssertEqual(response?.event.id, event.id)
    }
}

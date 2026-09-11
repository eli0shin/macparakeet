import XCTest
import MacParakeetCore
@testable import MacParakeet

final class SavedMeetingCalendarPresentationTests: XCTestCase {
    func testConfirmedAndProbableMatchesUseDistinctCopy() {
        XCTAssertEqual(
            SavedMeetingCalendarPresentation.connectionTitle(for: .confirmed),
            "Calendar"
        )
        XCTAssertEqual(
            SavedMeetingCalendarPresentation.confidenceTitle(for: .confirmed),
            "Confirmed calendar event"
        )
        XCTAssertEqual(
            SavedMeetingCalendarPresentation.connectionTitle(for: .probable),
            "Possible match"
        )
        XCTAssertEqual(
            SavedMeetingCalendarPresentation.confidenceTitle(for: .probable),
            "Possible calendar match"
        )
        XCTAssertTrue(
            SavedMeetingCalendarPresentation.confidenceDetail(for: .probable)
                .contains("Verify the match")
        )
    }

    func testPeopleUseAvailableNamesAndEmailsAndOmitEmptyEntries() {
        XCTAssertEqual(
            SavedMeetingCalendarPresentation.personText(
                MeetingCalendarPerson(name: "Alice Example", email: "alice@example.com")
            ),
            "Alice Example (alice@example.com)"
        )
        XCTAssertEqual(
            SavedMeetingCalendarPresentation.attendeeText([
                MeetingCalendarPerson(name: "Name only"),
                MeetingCalendarPerson(email: "email@example.com"),
                MeetingCalendarPerson(name: "  ", email: ""),
            ]),
            "Name only, email@example.com"
        )
        XCTAssertNil(
            SavedMeetingCalendarPresentation.attendeeText([
                MeetingCalendarPerson(name: " ", email: nil)
            ])
        )
    }

    func testOnlyWebMeetingURLsAreActionable() {
        XCTAssertEqual(
            SavedMeetingCalendarPresentation.actionableMeetingURL(" https://zoom.us/j/123 ")?.absoluteString,
            "https://zoom.us/j/123"
        )
        XCTAssertNotNil(SavedMeetingCalendarPresentation.actionableMeetingURL("http://localhost:8080/meeting"))
        XCTAssertNil(SavedMeetingCalendarPresentation.actionableMeetingURL("javascript:alert(1)"))
        XCTAssertNil(SavedMeetingCalendarPresentation.actionableMeetingURL("not a URL"))
        XCTAssertNil(SavedMeetingCalendarPresentation.actionableMeetingURL(nil))
    }
}

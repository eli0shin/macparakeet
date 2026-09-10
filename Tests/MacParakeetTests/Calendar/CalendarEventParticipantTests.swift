import XCTest
@testable import MacParakeetCore

final class CalendarEventParticipantTests: XCTestCase {
    func testEmailAddressUsesSupportedMailtoURL() {
        XCTAssertEqual(
            EventParticipant.emailAddress(from: URL(string: "mailto:Ava%2Bcalendar@example.com")!),
            "Ava+calendar@example.com"
        )
        XCTAssertNil(EventParticipant.emailAddress(from: URL(string: "https://calendar.example.com/principal/ava")!))
    }

    func testCalendarEventNormalizesAndDeduplicatesParticipants() {
        let event = makeEvent(
            participants: [
                EventParticipant(email: " AVA@example.com ", name: "Ava"),
                EventParticipant(email: "ava@example.com", name: "Ava Smith"),
                EventParticipant(name: "  Ben  "),
                EventParticipant(email: "other-ava@example.com", name: "Ava"),
            ]
        )

        XCTAssertEqual(event.participants.count, 3)
        XCTAssertEqual(event.participants[0].email, "ava@example.com")
        XCTAssertEqual(event.participants[0].name, "Ava")
        XCTAssertEqual(event.participants[1].name, "Ben")
        XCTAssertEqual(event.participants[2].email, "other-ava@example.com")
    }

    func testCalendarEventDoesNotRepeatOrganizerAsParticipant() {
        let event = makeEvent(
            participants: [
                EventParticipant(email: "host@example.com", name: "Host"),
                EventParticipant(name: "Guest"),
            ],
            organizer: EventParticipant(email: "HOST@example.com", name: "Meeting Host")
        )

        XCTAssertEqual(event.organizerDisplayName, "Meeting Host")
        XCTAssertEqual(event.participants.count, 2, "The trigger filter still sees the attendee list.")
        XCTAssertEqual(event.participantDisplayNames, ["Guest"])
    }

    func testEqualNamesWithoutSupportedIdentityRemainDistinct() {
        let event = makeEvent(
            participants: [
                EventParticipant(name: "Alex"),
                EventParticipant(name: "Alex"),
            ]
        )

        XCTAssertEqual(event.participants.count, 2)
        XCTAssertEqual(event.participantDisplayNames, ["Alex", "Alex"])
    }

    func testSourceIdentifierDeduplicatesWithoutEnteringCodableOutput() throws {
        var first = EventParticipant(name: "Room")
        first.sourceIdentifier = "https://calendar.example.com/principal/room"
        var duplicate = EventParticipant()
        duplicate.sourceIdentifier = "https://calendar.example.com/principal/room"

        let event = makeEvent(participants: [first, duplicate])
        let data = try JSONEncoder().encode(event.participants[0])

        XCTAssertEqual(event.participants.count, 1)
        XCTAssertFalse(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("principal"))
    }

    func testParticipantDisplayUsesPartialProviderData() {
        let event = makeEvent(
            participants: [
                EventParticipant(name: "Name only"),
                EventParticipant(email: "email-only@example.com"),
                EventParticipant(status: .accepted),
                EventParticipant(status: .pending),
            ],
            organizer: EventParticipant()
        )

        XCTAssertEqual(event.organizerDisplayName, "Organizer")
        XCTAssertEqual(
            event.participantDisplayNames,
            ["Name only", "email-only@example.com", "Participant", "Participant"]
        )
    }

    private func makeEvent(
        participants: [EventParticipant],
        organizer: EventParticipant? = nil
    ) -> CalendarEvent {
        CalendarEvent(
            id: "event-id",
            title: "Design Review",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_003_600),
            participants: participants,
            organizer: organizer
        )
    }
}

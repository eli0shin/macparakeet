import XCTest
import MacParakeetCore
import MacParakeetViewModels

final class LiveSpeakerHeadingTests: XCTestCase {
    func testMeKeepsItsHeadingAndUndetectedSystemDoesNotInventOne() {
        let me = MeetingRecordingPreviewLine(
            id: "me", timestamp: "0:00", speakerLabel: "Me", text: "Hello",
            source: .microphone, speakerID: "microphone")
        let system = MeetingRecordingPreviewLine(
            id: "system", timestamp: "0:00", speakerLabel: "System audio", text: "Hello",
            source: .system, speakerID: "system")
        let detected = MeetingRecordingPreviewLine(
            id: "detected", timestamp: "0:00", speakerLabel: "Others 1", text: "Hello",
            source: .system, speakerID: "system:S1")
        XCTAssertTrue(me.showsSpeakerHeading)
        XCTAssertEqual(me.speakerLabel, "Me")
        XCTAssertFalse(system.showsSpeakerHeading)
        XCTAssertTrue(detected.showsSpeakerHeading)
    }
}

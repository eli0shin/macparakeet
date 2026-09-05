import XCTest
import MacParakeetCore
@testable import MacParakeet

final class MeetingReadingTurnIdentityTests: XCTestCase {
    func testCompletedMeetingDefaultsToTextWhenTranscriptWasEdited() {
        XCTAssertFalse(
            shouldDefaultToMeetingReadingSurface(
                isCompletedMeeting: true,
                isTranscriptEdited: true,
                hasReadingTurns: true
            ))
        XCTAssertTrue(
            shouldDefaultToMeetingReadingSurface(
                isCompletedMeeting: true,
                isTranscriptEdited: false,
                hasReadingTurns: true
            ))
    }

    func testScrollIdentityIsOnePerReadingTurnAndPlaybackSelectsTheLatestStart() {
        let turns = identifiedReadingTurns([
            turn(speaker: "microphone", source: .microphone, firstWord: 0, startMs: 0),
            turn(speaker: "system:S1", source: .system, firstWord: 3, startMs: 1_000),
            turn(speaker: "microphone", source: .microphone, firstWord: 6, startMs: 2_000),
        ])

        XCTAssertEqual(turns.count, 3)
        XCTAssertEqual(Set(turns.map(\.scrollID)).count, 3)
        XCTAssertNil(readingTurnScrollTarget(for: -1, in: turns))
        XCTAssertEqual(readingTurnScrollTarget(for: 1_500, in: turns), turns[1].scrollID)
        XCTAssertEqual(readingTurnScrollTarget(for: 2_500, in: turns), turns[2].scrollID)
    }

    func testUntimedFallbackHasAViewIdentityButNoPlaybackTarget() {
        let turns = identifiedReadingTurns([
            ReadingTurn(
                id: ReadingTurnIdentity(source: .unknown, speakerId: "unknown", firstWordIndex: nil),
                speakerId: "unknown",
                speakerLabel: "Transcript",
                source: .unknown,
                timeRange: nil,
                paragraphs: [ReadingTurnParagraph(text: "Legacy text", wordReferences: [])],
                wordReferences: []
            )
        ])

        XCTAssertEqual(turns.count, 1)
        XCTAssertNil(readingTurnScrollTarget(for: 1_000, in: turns))
    }

    private func turn(
        speaker: String,
        source: ReadingTurnSource,
        firstWord: Int,
        startMs: Int
    ) -> ReadingTurn {
        ReadingTurn(
            id: ReadingTurnIdentity(source: source, speakerId: speaker, firstWordIndex: firstWord),
            speakerId: speaker,
            speakerLabel: speaker,
            source: source,
            timeRange: ReadingTurnTimeRange(startMs: startMs, endMs: startMs + 500),
            paragraphs: [ReadingTurnParagraph(text: "Text", wordReferences: [firstWord])],
            wordReferences: [firstWord]
        )
    }
}

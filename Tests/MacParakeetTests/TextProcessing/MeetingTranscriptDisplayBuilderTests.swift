import XCTest
@testable import MacParakeetCore

final class MeetingTranscriptDisplayBuilderTests: XCTestCase {
    func testGroupsConsecutiveSpeakerRunAcrossLongPausesAndFormattingBoundaries() throws {
        let words = [
            word("First point.", 0, 500, "microphone"),
            word("Another point.", 10_000, 10_500, "microphone"),
            word("Final point.", 20_000, 20_500, "microphone"),
        ]
        let canonical = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: words,
            speakers: nil
        )
        XCTAssertEqual(canonical.turns.count, 3)
        let middle = try XCTUnwrap(canonical.turns.dropFirst().first)
        let formatted = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: words,
            speakers: nil,
            formatting: [
                MeetingReadingTurnFormatting(
                    turnID: middle.id,
                    deterministicText: middle.deterministicText,
                    formattedText: "Another polished point."
                )
            ]
        )

        let displayed = MeetingTranscriptDisplayBuilder.build(from: formatted)
        let turn = try XCTUnwrap(displayed.turns.only)

        XCTAssertEqual(turn.id, formatted.turns[0].id)
        XCTAssertEqual(turn.speakerId, "microphone")
        XCTAssertEqual(turn.timeRange, ReadingTurnTimeRange(startMs: 0, endMs: 20_500))
        XCTAssertEqual(turn.paragraphs.map(\.text), ["First point.", "Another point.", "Final point."])
        XCTAssertEqual(
            turn.text,
            "First point.\n\nAnother polished point.\n\nFinal point."
        )
        XCTAssertEqual(turn.wordReferences, [0, 1, 2])
        XCTAssertEqual(formatted.turns.count, 3, "Display grouping must not change canonical turns")

        let target = try XCTUnwrap(displayed.navigationTarget(containingWordReference: 1))
        XCTAssertEqual(target.turnID, formatted.turns[0].id)
        XCTAssertEqual(target.timeRange?.startMs, 0)
        XCTAssertEqual(target.wordReferences, [0, 1, 2])
    }

    func testOnlyDifferentSpeakerIdentityEndsAConsecutiveRun() {
        let document = MeetingTranscriptPresentationDocument(turns: [
            turn(speakerId: "system:S1", label: "Alex", firstWord: 0, startMs: 0),
            turn(speakerId: "system:S1", label: "Renamed", firstWord: 1, startMs: 1_000),
            turn(speakerId: "system:S2", label: "Alex", firstWord: 2, startMs: 2_000),
            turn(speakerId: "system:S1", label: "Alex", firstWord: 3, startMs: 3_000),
        ])

        let displayed = MeetingTranscriptDisplayBuilder.build(from: document)

        XCTAssertEqual(displayed.turns.map(\.speakerId), ["system:S1", "system:S2", "system:S1"])
        XCTAssertEqual(displayed.turns.map(\.speakerLabel), ["Alex", "Alex", "Alex"])
        XCTAssertEqual(displayed.turns[0].wordReferences, [0, 1])
        XCTAssertEqual(displayed.turns[0].paragraphs.map(\.text), ["Text 0", "Text 1"])
    }

    func testOverlapMetadataAndUntimedBoundariesDoNotSplitSpeakerRun() throws {
        let firstID = ReadingTurnIdentity(
            source: .unknown,
            speakerId: "legacy",
            firstWordIndex: nil
        )
        let document = MeetingTranscriptPresentationDocument(turns: [
            ReadingTurn(
                id: firstID,
                speakerId: "legacy",
                speakerLabel: "Transcript",
                source: .unknown,
                timeRange: nil,
                overlap: ReadingTurnOverlap(groupId: firstID),
                paragraphs: [ReadingTurnParagraph(text: "Legacy first.", wordReferences: [])],
                wordReferences: []
            ),
            ReadingTurn(
                id: firstID,
                speakerId: "legacy",
                speakerLabel: "Transcript",
                source: .unknown,
                timeRange: nil,
                paragraphs: [ReadingTurnParagraph(text: "Legacy second.", wordReferences: [])],
                wordReferences: []
            ),
        ])

        let turn = try XCTUnwrap(MeetingTranscriptDisplayBuilder.build(from: document).turns.only)

        XCTAssertNil(turn.timeRange)
        XCTAssertEqual(turn.text, "Legacy first.\n\nLegacy second.")
        XCTAssertEqual(turn.paragraphs.count, 2)
    }

    func testSkipsBlankTurnsBeforeGroupingSpeakerRuns() {
        let document = MeetingTranscriptPresentationDocument(turns: [
            turn(speakerId: "system:S2", label: "Other", firstWord: 0, startMs: 0, text: ""),
            turn(speakerId: "system:S1", label: "Alex", firstWord: 1, startMs: 1_000),
            turn(speakerId: "system:S2", label: "Other", firstWord: 2, startMs: 2_000, text: " \n\t"),
            turn(speakerId: "system:S1", label: "Alex", firstWord: 3, startMs: 3_000),
            turn(speakerId: "system:S2", label: "Other", firstWord: 4, startMs: 4_000, text: ""),
        ])

        let displayed = MeetingTranscriptDisplayBuilder.build(from: document)

        XCTAssertEqual(displayed.turns.count, 1)
        XCTAssertEqual(displayed.turns.first?.text, "Text 1\n\nText 3")
        XCTAssertEqual(displayed.turns.first?.id, document.turns[1].id)
        XCTAssertEqual(displayed.turns.first?.wordReferences, [1, 3])
        XCTAssertEqual(displayed.turns.first?.timeRange, ReadingTurnTimeRange(startMs: 1_000, endMs: 3_500))
        XCTAssertEqual(document.turns.count, 5)
    }

    func testAllBlankTurnsProduceEmptyDisplay() {
        let document = MeetingTranscriptPresentationDocument(turns: [
            turn(speakerId: "system:S1", label: "Alex", firstWord: 0, startMs: 0, text: " \n"),
        ])

        XCTAssertTrue(MeetingTranscriptDisplayBuilder.build(from: document).turns.isEmpty)
    }

    func testFillerOnlyTurnDoesNotSplitDisplayedSpeakerRun() {
        let canonical = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: [
                word("First point.", 0, 500, "microphone"),
                word("uh", 1_000, 1_500, "system"),
                word("Next point.", 2_000, 2_500, "microphone"),
            ],
            speakers: nil
        )

        XCTAssertEqual(canonical.turns.count, 3)
        XCTAssertEqual(canonical.turns[1].text, "")
        let displayed = MeetingTranscriptDisplayBuilder.build(from: canonical)
        XCTAssertEqual(displayed.turns.count, 1)
        XCTAssertEqual(displayed.turns.first?.text, "First point.\n\nNext point.")
    }

    private func turn(
        speakerId: String,
        label: String,
        firstWord: Int,
        startMs: Int,
        text: String? = nil
    ) -> ReadingTurn {
        ReadingTurn(
            id: ReadingTurnIdentity(
                source: .system,
                speakerId: speakerId,
                firstWordIndex: firstWord
            ),
            speakerId: speakerId,
            speakerLabel: label,
            source: .system,
            timeRange: ReadingTurnTimeRange(startMs: startMs, endMs: startMs + 500),
            paragraphs: [
                ReadingTurnParagraph(text: text ?? "Text \(firstWord)", wordReferences: [firstWord])
            ],
            wordReferences: [firstWord]
        )
    }

    private func word(
        _ text: String,
        _ startMs: Int,
        _ endMs: Int,
        _ speakerId: String?
    ) -> WordTimestamp {
        WordTimestamp(
            word: text,
            startMs: startMs,
            endMs: endMs,
            confidence: 1,
            speakerId: speakerId
        )
    }
}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}

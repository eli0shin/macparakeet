import os
import XCTest
@testable import MacParakeetCore

final class MeetingReadingTurnFormatterTests: XCTestCase {
    func testAllReadingTurnsAreSentInOneCompleteRequest() async {
        let formatter = MeetingReadingTurnFormatter()
        let requests = RequestRecorder { $0.uppercased() }
        let document = makeDocument([
            ["BEGIN_SENTINEL first turn."],
            ["MIDDLE_SENTINEL second turn."],
            ["END_SENTINEL third turn."],
        ])

        let result = await formatter.format(document) { input in
            try await requests.format(input)
        }

        let captured = await requests.requests
        XCTAssertEqual(captured.count, 1)
        XCTAssertTrue(captured[0].contains("BEGIN_SENTINEL first turn."))
        XCTAssertTrue(captured[0].contains("MIDDLE_SENTINEL second turn."))
        XCTAssertTrue(captured[0].contains("END_SENTINEL third turn."))
        XCTAssertEqual(result.formatting.count, 3)
        XCTAssertEqual(result.progress, .init(completedRequests: 1, totalRequests: 1))
        XCTAssertFalse(result.wasCancelled)
    }

    func testProviderFailureDoesNotRetryWithReducedContext() async {
        let formatter = MeetingReadingTurnFormatter()
        let requests = RequestRecorder { _ in throw FixtureError.failed }
        let document = makeDocument([["First."], ["Second."], ["Third."]])

        let result = await formatter.format(document) { input in
            try await requests.format(input)
        }

        let captured = await requests.requests
        XCTAssertEqual(captured.count, 1)
        XCTAssertTrue(result.formatting.isEmpty)
        XCTAssertFalse(result.wasCancelled)
    }

    func testMalformedOrContentChangingOutputLeavesAllTurnsDeterministic() async {
        let formatter = MeetingReadingTurnFormatter()
        let document = makeDocument([["Keep number 42."], ["Second turn."]])

        let result = await formatter.format(document) { _ in
            "Keep number 43."
        }

        XCTAssertTrue(result.formatting.isEmpty)
        XCTAssertEqual(
            apply(result.formatting, to: document).turns.map(\.text),
            document.turns.map(\.deterministicText)
        )
    }

    func testCancellationAfterRequestDoesNotCommitFormatting() async {
        let formatter = MeetingReadingTurnFormatter()
        let document = makeDocument([["Do not commit."], ["Never commit."]])

        let task = Task {
            await formatter.format(document) { input in
                withUnsafeCurrentTask { $0?.cancel() }
                return input
            }
        }
        let result = await task.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertTrue(result.formatting.isEmpty)
        XCTAssertEqual(result.progress, .init(completedRequests: 0, totalRequests: 1))
    }

    func testApplyingFormattingPreservesIdentitySpeakerTimingAndEvidence() async {
        let formatter = MeetingReadingTurnFormatter()
        let document = makeDocument([["hello world."]])

        let result = await formatter.format(document) { _ in "Hello, world." }
        let formatted = apply(result.formatting, to: document).turns[0]
        let original = document.turns[0]

        XCTAssertEqual(formatted.text, "Hello, world.")
        XCTAssertEqual(formatted.deterministicText, "hello world.")
        XCTAssertEqual(formatted.id, original.id)
        XCTAssertEqual(formatted.speakerId, original.speakerId)
        XCTAssertEqual(formatted.speakerLabel, original.speakerLabel)
        XCTAssertEqual(formatted.timeRange, original.timeRange)
        XCTAssertEqual(formatted.wordReferences, original.wordReferences)
        XCTAssertEqual(formatted.paragraphs, original.paragraphs)
    }

    private func makeDocument(_ turnParagraphs: [[String]]) -> MeetingTranscriptPresentationDocument {
        MeetingTranscriptPresentationDocument(
            turns: turnParagraphs.enumerated().map { turnIndex, paragraphs in
                let references = Array((turnIndex * 10)..<(turnIndex * 10 + paragraphs.count))
                return ReadingTurn(
                    id: .init(source: .system, speakerId: "speaker-\(turnIndex)", firstWordIndex: references.first),
                    speakerId: "speaker-\(turnIndex)",
                    speakerLabel: "Speaker \(turnIndex + 1)",
                    source: .system,
                    timeRange: .init(startMs: turnIndex * 1_000, endMs: turnIndex * 1_000 + 900),
                    paragraphs: zip(paragraphs, references).map {
                        ReadingTurnParagraph(text: $0.0, wordReferences: [$0.1])
                    },
                    wordReferences: references
                )
            }
        )
    }

    private func apply(
        _ formatting: [MeetingReadingTurnFormatting],
        to document: MeetingTranscriptPresentationDocument
    ) -> MeetingTranscriptPresentationDocument {
        let byID = Dictionary(uniqueKeysWithValues: formatting.map { ($0.turnID, $0) })
        return MeetingTranscriptPresentationDocument(
            turns: document.turns.map { turn in
                guard let value = byID[turn.id], value.deterministicText == turn.deterministicText else {
                    return turn
                }
                return ReadingTurn(
                    id: turn.id,
                    speakerId: turn.speakerId,
                    speakerLabel: turn.speakerLabel,
                    source: turn.source,
                    timeRange: turn.timeRange,
                    overlap: turn.overlap,
                    paragraphs: turn.paragraphs,
                    formattedText: value.formattedText,
                    wordReferences: turn.wordReferences
                )
            })
    }
}

private actor RequestRecorder {
    private(set) var requests: [String] = []
    private let response: @Sendable (String) throws -> String

    init(response: @escaping @Sendable (String) throws -> String) {
        self.response = response
    }

    func format(_ input: String) throws -> String {
        requests.append(input)
        return try response(input)
    }
}

private enum FixtureError: Error {
    case failed
}

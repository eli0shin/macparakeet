import os
import XCTest
@testable import MacParakeetCore

final class MeetingReadingTurnFormatterTests: XCTestCase {
    func testLongMeetingFormatsAsBoundedReadingTurnRequests() async {
        let formatter = MeetingReadingTurnFormatter(maximumRequestCharacters: 45)
        let requests = RequestRecorder { input in input.uppercased() }
        let document = makeDocument([
            ["First sentence stays inside turn one."],
            ["Second turn remains independently bounded."],
            ["Third turn is also below the request cap."],
        ])
        XCTAssertGreaterThan(document.turns.map(\.text.count).reduce(0, +), 45)

        let result = await formatter.format(
            document,
            using: { input in try await requests.format(input) }
        )

        let captured = await requests.requests
        XCTAssertEqual(captured, document.turns.map(\.text))
        XCTAssertTrue(captured.allSatisfy { $0.count <= 45 })
        XCTAssertEqual(result.formatting.count, 3)
        XCTAssertFalse(result.wasCancelled)
    }

    func testRequestBoundariesNeverCrossTurnsOrSplitParagraphs() async {
        let formatter = MeetingReadingTurnFormatter(maximumRequestCharacters: 24)
        let requests = RequestRecorder { $0 }
        let document = makeDocument([
            ["Turn one paragraph.", "Another paragraph."],
            ["Turn two paragraph."],
        ])

        _ = await formatter.format(
            document,
            using: { input in try await requests.format(input) }
        )

        let captured = await requests.requests
        XCTAssertEqual(
            captured,
            ["Turn one paragraph.", "Another paragraph.", "Turn two paragraph."]
        )
    }

    func testFailedTurnFallsBackWithoutDiscardingOtherFormattedTurns() async {
        let formatter = MeetingReadingTurnFormatter(maximumRequestCharacters: 100)
        let requests = RequestRecorder { input in
            if input.contains("fails") { throw FixtureError.failed }
            return input.uppercased()
        }
        let document = makeDocument([
            ["First succeeds."],
            ["Second fails."],
            ["Third succeeds."],
        ])

        let result = await formatter.format(
            document,
            using: { input in try await requests.format(input) }
        )
        let presented = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: nil,
            speakers: nil,
            formatting: result.formatting
        )

        XCTAssertEqual(result.formatting.map(\.turnID), [document.turns[0].id, document.turns[2].id])
        XCTAssertEqual(
            apply(result.formatting, to: document).turns.map(\.text),
            ["FIRST SUCCEEDS.", "Second fails.", "THIRD SUCCEEDS."]
        )
        XCTAssertTrue(presented.turns.isEmpty, "Unrelated evidence must not accept stale turn formatting")
    }

    func testCancellationKeepsCompletedTurnsAndLeavesCurrentAndRemainingTurnsDeterministic() async {
        let formatter = MeetingReadingTurnFormatter(maximumRequestCharacters: 100)
        let requests = RequestRecorder { input in
            if input.contains("cancel") { throw CancellationError() }
            return input.uppercased()
        }
        let document = makeDocument([
            ["First succeeds."],
            ["Now cancel."],
            ["Never requested."],
        ])
        let progress = OSAllocatedUnfairLock(initialState: [MeetingReadingTurnFormattingProgress]())

        let result = await formatter.format(
            document,
            using: { input in try await requests.format(input) },
            onProgress: { update in
                progress.withLock { $0.append(update) }
            }
        )

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.formatting.map(\.turnID), [document.turns[0].id])
        XCTAssertEqual(
            apply(result.formatting, to: document).turns.map(\.text),
            ["FIRST SUCCEEDS.", "Now cancel.", "Never requested."]
        )
        XCTAssertEqual(result.progress, .init(completedRequests: 1, totalRequests: 3))
        let progressUpdates = progress.withLock { $0 }
        XCTAssertEqual(progressUpdates.first, .init(completedRequests: 0, totalRequests: 3))
        XCTAssertEqual(progressUpdates.last, .init(completedRequests: 1, totalRequests: 3))
    }

    func testCancellationIsObservedWhenRequestReturnsNormally() async {
        let formatter = MeetingReadingTurnFormatter(maximumRequestCharacters: 100)
        let document = makeDocument([
            ["Do not commit this turn."],
            ["Never requested."],
        ])

        let task = Task {
            await formatter.format(document) { input in
                withUnsafeCurrentTask { $0?.cancel() }
                return input.uppercased()
            }
        }
        let result = await task.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertTrue(result.formatting.isEmpty)
        XCTAssertEqual(result.progress, .init(completedRequests: 0, totalRequests: 2))
    }

    func testInvalidOutputsFallBackOnlyForAffectedTurns() async {
        let formatter = MeetingReadingTurnFormatter(maximumRequestCharacters: 100)
        let requests = RequestRecorder { input in
            switch input {
            case let value where value.contains("empty"): return "  "
            case let value where value.contains("number 42"): return "Keep number 43."
            case let value where value.contains("changed"): return "Completely unrelated replacement."
            default: return input.uppercased()
            }
        }
        let document = makeDocument([
            ["Valid output."],
            ["Return empty output."],
            ["Keep number 42."],
            ["Everything here changed beyond recognition."],
        ])

        let result = await formatter.format(
            document,
            using: { input in try await requests.format(input) }
        )

        XCTAssertEqual(result.formatting.map(\.turnID), [document.turns[0].id])
        XCTAssertEqual(
            apply(result.formatting, to: document).turns.map(\.text),
            document.turns.enumerated().map { index, turn in
                index == 0 ? "VALID OUTPUT." : turn.deterministicText
            }
        )
    }

    func testOversizedUnsafeParagraphIsNotSplitOrRequested() async {
        let formatter = MeetingReadingTurnFormatter(maximumRequestCharacters: 20)
        let requests = RequestRecorder { $0 }
        let document = makeDocument([
            ["One unbroken semantic paragraph is too long."],
            ["Safe short turn."],
        ])

        let result = await formatter.format(
            document,
            using: { input in try await requests.format(input) }
        )

        let captured = await requests.requests
        XCTAssertEqual(captured, ["Safe short turn."])
        XCTAssertEqual(result.formatting.map(\.turnID), [document.turns[1].id])
    }

    func testApplyingFormattingPreservesIdentitySpeakerTimingAndEvidence() async {
        let formatter = MeetingReadingTurnFormatter(maximumRequestCharacters: 100)
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

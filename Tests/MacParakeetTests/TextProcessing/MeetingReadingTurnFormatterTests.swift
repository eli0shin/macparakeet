import os
import XCTest
@testable import MacParakeetCore

final class MeetingReadingTurnFormatterTests: XCTestCase {
    func testReadingTurnsUseSequentialFiveHundredCharacterBatches() async {
        let document = makeDocument([
            [String(repeating: "a", count: 500)],
            [String(repeating: "b", count: 200)],
            [String(repeating: "c", count: 300)],
            [String(repeating: "d", count: 301)],
        ])
        let recorder = BatchRecorder { Self.response(for: $0) }

        let result = await MeetingReadingTurnFormatter().format(document) {
            try await recorder.format($0)
        }

        let batches = await recorder.batches
        XCTAssertEqual(batches.map { $0.entries.map(\.text.count) }, [[500], [200, 300], [301]])
        XCTAssertEqual(result.formatting.count, 4)
        XCTAssertEqual(result.progress, .init(completedRequests: 3, totalRequests: 3))
        XCTAssertFalse(result.wasCancelled)
    }

    func testShortReadingTurnBatchContainsAtMostTenTurns() async {
        let document = makeDocument((1...21).map { ["turn-\($0)"] })
        let recorder = BatchRecorder { Self.response(for: $0) }

        let result = await MeetingReadingTurnFormatter().format(document) {
            try await recorder.format($0)
        }

        let batches = await recorder.batches
        XCTAssertEqual(batches.map { $0.entries.count }, [10, 10, 1])
        XCTAssertEqual(result.formatting.count, 21)
        XCTAssertEqual(result.progress, .init(completedRequests: 3, totalRequests: 3))
    }

    func testLongReadingTurnIsSentWholeAndAloneWithoutACap() async {
        let longText = "BEGIN" + String(repeating: "x", count: 25_000) + "END"
        let recorder = BatchRecorder { Self.response(for: $0) }

        let result = await MeetingReadingTurnFormatter().format(
            makeDocument([["short"], [longText], ["tail"]])
        ) { try await recorder.format($0) }

        let batches = await recorder.batches
        XCTAssertEqual(batches.count, 3)
        XCTAssertEqual(batches[1].entries.map(\.text), [longText])
        XCTAssertEqual(result.formatting.count, 3)
    }

    func testSingleAndMultipleTurnBatchesUseTheSameJSONShape() async throws {
        let recorder = BatchRecorder { Self.response(for: $0) }
        _ = await MeetingReadingTurnFormatter().format(
            makeDocument([[String(repeating: "a", count: 500)], ["b"], ["c"]])
        ) { try await recorder.format($0) }

        let batches = await recorder.batches
        XCTAssertEqual(batches.count, 2)
        let single = try JSONDecoder().decode(BatchEnvelope.self, from: Data(batches[0].encodedJSON().utf8))
        let multiple = try JSONDecoder().decode(BatchEnvelope.self, from: Data(batches[1].encodedJSON().utf8))
        XCTAssertEqual(single.entries.count, 1)
        XCTAssertEqual(multiple.entries.count, 2)
        XCTAssertEqual(Set(single.entries[0].keys), ["id", "text"])
        XCTAssertTrue(multiple.entries.allSatisfy { Set($0.keys) == ["id", "text"] })
    }

    func testFailedBatchDoesNotPreventLaterBatchesFromBeingCleaned() async {
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let first = String(repeating: "first ", count: 90)
        let second = String(repeating: "second ", count: 90)

        let result = await MeetingReadingTurnFormatter().format(makeDocument([[first], [second]])) { batch in
            let attempt = attempts.withLock { value in
                value += 1
                return value
            }
            if attempt == 1 { throw FixtureError.failed }
            return Self.response(for: batch, transform: { $0.uppercased() })
        }

        XCTAssertEqual(attempts.withLock { $0 }, 2)
        XCTAssertEqual(result.formatting.count, 1)
        XCTAssertEqual(result.formatting.first?.deterministicText, second)
        XCTAssertEqual(
            result.formatting.first?.formattedText,
            second.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        )
        XCTAssertEqual(result.progress, .init(completedRequests: 2, totalRequests: 2))
    }

    func testResponseIDsMapReorderedEntriesBackToReadingTurns() async {
        let document = makeDocument([["first"], ["second"], ["third"]])

        let result = await MeetingReadingTurnFormatter().format(document) { batch in
            Self.response(
                entries: batch.entries.reversed().map {
                    MeetingReadingTurnBatchEntry(id: $0.id, text: $0.text.uppercased())
                })
        }

        XCTAssertEqual(result.formatting.map(\.formattedText), ["FIRST", "SECOND", "THIRD"])
        XCTAssertEqual(result.formatting.map(\.turnID), document.turns.map(\.id))
    }

    func testInvalidIDsRejectOnlyTheirBatch() async {
        let diagnostics = DiagnosticRecorder()
        let formatter = MeetingReadingTurnFormatter(diagnosticSink: { await diagnostics.append($0) })
        let first = String(repeating: "first ", count: 90)
        let second = String(repeating: "second ", count: 90)
        let attempts = OSAllocatedUnfairLock(initialState: 0)

        let result = await formatter.format(makeDocument([[first], [second]])) { batch in
            let attempt = attempts.withLock { value in
                value += 1; return value
            }
            if attempt == 1 {
                return Self.response(entries: [batch.entries[0], batch.entries[0]])
            }
            return Self.response(for: batch)
        }

        let events = await diagnostics.events
        XCTAssertEqual(result.formatting.map(\.deterministicText), [second])
        XCTAssertEqual(events.map(\.outcome), ["rejected", "accepted"])
        XCTAssertTrue(events[0].reason?.contains("duplicate_id id=turn-0") == true)
    }

    func testMissingResponseEntryDoesNotDiscardValidEntryInTheSameBatch() async {
        let diagnostics = DiagnosticRecorder()
        let formatter = MeetingReadingTurnFormatter(diagnosticSink: { await diagnostics.append($0) })
        let document = makeDocument([["first"], ["second"]])

        let result = await formatter.format(document) { batch in
            Self.response(entries: [
                .init(id: batch.entries[0].id, text: "First.")
            ])
        }

        let events = await diagnostics.events
        XCTAssertEqual(result.formatting.map(\.formattedText), ["First."])
        XCTAssertEqual(events.first?.outcome, "partially_accepted")
        XCTAssertEqual(events.first?.reason, "missing_id id=turn-1")
    }

    func testOneContentRejectionDoesNotDiscardValidEntriesInTheSameBatch() async {
        let diagnostics = DiagnosticRecorder()
        let formatter = MeetingReadingTurnFormatter(diagnosticSink: { await diagnostics.append($0) })
        let document = makeDocument([["Keep number 42."], ["hello world."]])

        let result = await formatter.format(document) { batch in
            Self.response(entries: [
                .init(id: batch.entries[0].id, text: "Keep number 43."),
                .init(id: batch.entries[1].id, text: "Hello, world."),
            ])
        }

        let events = await diagnostics.events
        XCTAssertEqual(result.formatting.count, 1)
        XCTAssertEqual(result.formatting.first?.formattedText, "Hello, world.")
        XCTAssertEqual(events.first?.outcome, "partially_accepted")
        XCTAssertTrue(events.first?.reason?.contains("protected_values_changed turn=1") == true)
    }

    func testCancellationStopsFutureBatches() async {
        let first = String(repeating: "first ", count: 90)
        let second = String(repeating: "second ", count: 90)
        let recorder = BatchRecorder { batch in
            if batch.entries[0].text == second { throw CancellationError() }
            return Self.response(for: batch)
        }

        let result = await MeetingReadingTurnFormatter().format(makeDocument([[first], [second]])) {
            try await recorder.format($0)
        }

        XCTAssertTrue(result.wasCancelled)
        let requestCount = await recorder.batches.count
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(result.formatting.map(\.deterministicText), [first])
        XCTAssertEqual(result.progress, .init(completedRequests: 1, totalRequests: 2))
    }

    func testPromptUsesJSONEntriesInsteadOfBoundaryMarkers() {
        let prompt = MeetingReadingTurnFormatter.promptTemplate(AIFormatter.defaultPromptTemplate)
        XCTAssertTrue(prompt.contains("Preserve every entry ID exactly"))
        XCTAssertTrue(prompt.contains(#"{"entries":[{"id":"turn ID","text":"cleaned text"}]}"#))
        XCTAssertFalse(prompt.contains("MACPARAKEET_READING_TURN_BOUNDARY"))
        XCTAssertTrue(prompt.contains(AIFormatter.transcriptPlaceholder))
    }

    func testApplyingFormattingPreservesIdentitySpeakerTimingAndEvidence() async {
        let document = makeDocument([["hello world."]])
        let result = await MeetingReadingTurnFormatter().format(document) { batch in
            Self.response(entries: [.init(id: batch.entries[0].id, text: "Hello, world.")])
        }
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

    private static func response(
        for batch: MeetingReadingTurnFormattingBatch,
        transform: (String) -> String = { $0 }
    ) -> String {
        response(entries: batch.entries.map { .init(id: $0.id, text: transform($0.text)) })
    }

    private static func response(entries: [MeetingReadingTurnBatchEntry]) -> String {
        let data = try! JSONEncoder().encode(ResponseEnvelope(entries: entries))
        return String(decoding: data, as: UTF8.self)
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

private actor BatchRecorder {
    private(set) var batches: [MeetingReadingTurnFormattingBatch] = []
    private let response: @Sendable (MeetingReadingTurnFormattingBatch) throws -> String

    init(response: @escaping @Sendable (MeetingReadingTurnFormattingBatch) throws -> String) {
        self.response = response
    }

    func format(_ batch: MeetingReadingTurnFormattingBatch) throws -> String {
        batches.append(batch)
        return try response(batch)
    }
}

private actor DiagnosticRecorder {
    var events: [MeetingFormattingDiagnostic] = []
    func append(_ event: MeetingFormattingDiagnostic) { events.append(event) }
}

private struct ResponseEnvelope: Encodable {
    let entries: [MeetingReadingTurnBatchEntry]
}

private struct BatchEnvelope: Decodable {
    let entries: [[String: String]]
}

private enum FixtureError: Error {
    case failed
}

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

    func testMissingBoundariesLogsExactReasonAndFullText() async {
        let recorder = DiagnosticRecorder()
        let formatter = MeetingReadingTurnFormatter(diagnosticSink: { await recorder.append($0) })
        let document = makeDocument([["Um I I I think this matters."], ["Yes, it does."]])
        let output = "I think this matters.\n\nYes, it does."
        let result = await formatter.format(document) { _ in output }
        let events = await recorder.events
        XCTAssertTrue(result.formatting.isEmpty)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(
            events.first?.reason, "turn_count_mismatch expected=2 actual=1 expected_boundaries=1 actual_boundaries=0")
        XCTAssertTrue(events.first?.input.contains("Um I I I") == true)
        XCTAssertEqual(events.first?.output, output)
    }

    func testContentRejectionsLogTurnAndValidationValues() async {
        let cases: [(String, String, String)] = [
            ("Keep number 42.", "Keep number 43.", "protected_values_changed turn=1"),
            ("Keep this.", "", "empty_output turn=1"),
            ("Hello.", "!!!", "no_lexical_tokens turn=1"),
            ("Keep these exact words.", "Replace everything completely now.", "lexical_change_exceeded turn=1"),
            ("Hello.", "Hello" + String(repeating: "!", count: 250), "output_length_exceeded turn=1"),
        ]
        for (input, output, reason) in cases {
            let recorder = DiagnosticRecorder()
            let formatter = MeetingReadingTurnFormatter(diagnosticSink: { await recorder.append($0) })
            let result = await formatter.format(makeDocument([[input]])) { _ in output }
            let events = await recorder.events
            XCTAssertTrue(result.formatting.isEmpty)
            XCTAssertTrue(events.first?.reason?.hasPrefix(reason) == true, "\(events)")
            XCTAssertEqual(events.first?.input, input)
            XCTAssertEqual(events.first?.output, output)
        }
    }

    func testDiagnosticFileContainsCompleteResponseAndReason() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("cleanup.jsonl")
        let log = MeetingFormattingDiagnosticLog(fileURL: url)
        let formatter = MeetingReadingTurnFormatter(diagnosticSink: { await log.append($0) })
        let input = "Um I I I think this matters."
        let output = "A completely different response.\nWith another paragraph."
        _ = await formatter.format(makeDocument([[input]])) { _ in output }
        _ = await formatter.format(makeDocument([["Hello."]])) { _ in "Hello!" }
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(MeetingFormattingDiagnostic.self, from: Data(lines[0].utf8))
        XCTAssertEqual(event.input, input)
        XCTAssertEqual(event.output, output)
        XCTAssertEqual(event.outcome, "rejected")
        XCTAssertTrue(event.reason?.contains("ratio=") == true)
        XCTAssertTrue(event.reason?.contains("limit=0.35") == true)
    }

    func testCancellationLogsReturnedTextInsteadOfDroppingEvidence() async {
        let recorder = DiagnosticRecorder()
        let formatter = MeetingReadingTurnFormatter(diagnosticSink: { await recorder.append($0) })
        let document = makeDocument([["Hello."]])
        let task = Task {
            await formatter.format(document) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return "Hello!"
            }
        }
        let result = await task.value
        let events = await recorder.events
        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(events.first?.reason, "cancelled_after_response")
        XCTAssertEqual(events.first?.output, "Hello!")
    }

    func testPromptExplicitlyRequiresBoundaryPreservation() {
        let prompt = MeetingReadingTurnFormatter.promptTemplate(AIFormatter.defaultPromptTemplate)
        XCTAssertTrue(prompt.contains("Preserve every <<<MACPARAKEET_READING_TURN_BOUNDARY>>> marker exactly"))
        XCTAssertTrue(prompt.contains(AIFormatter.transcriptPlaceholder))
    }

    func testAcceptedOutputAndProviderFailureAreLogged() async {
        let recorder = DiagnosticRecorder()
        let formatter = MeetingReadingTurnFormatter(diagnosticSink: { await recorder.append($0) })
        _ = await formatter.format(makeDocument([["Hello world."]])) { _ in "Hello, world." }
        _ = await formatter.format(makeDocument([["Hello world."]])) { _ in throw FixtureError.failed }
        let events = await recorder.events
        XCTAssertEqual(events.map(\.outcome), ["accepted", "rejected"])
        XCTAssertNil(events[0].reason)
        XCTAssertTrue(events[1].reason?.contains("request_failed") == true)
        XCTAssertTrue(events[1].reason?.contains("failed") == true)
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

private actor DiagnosticRecorder {
    var events: [MeetingFormattingDiagnostic] = []
    func append(_ event: MeetingFormattingDiagnostic) { events.append(event) }
}

private enum FixtureError: Error {
    case failed
}

import os
import XCTest
@testable import MacParakeetCore

final class MeetingReadingTurnFormatterTests: XCTestCase {
    func testDefaultAndCustomPromptsRenderBatchContractWithoutUsingTextBudget() {
        XCTAssertTrue(AIFormatter.defaultPromptTemplate.contains("Remove repeated words and filler sounds."))
        XCTAssertFalse(AIFormatter.defaultPromptTemplate.contains("when unnecessary"))

        let template = AIFormatter.meetingBatchPromptTemplate(
            "Keep product jargon.\n\(AIFormatter.transcriptPlaceholder)"
        )
        let rendered = AIFormatter.renderPrompt(
            template: template,
            transcript: #"{"entries":[{"id":"entry-0","text":"source"}]}"#
        )

        XCTAssertTrue(rendered.contains("Keep product jargon."))
        XCTAssertTrue(rendered.contains("Clean each entry in the JSON batch independently."))
        XCTAssertTrue(rendered.contains("Preserve every entry ID exactly."))
        XCTAssertTrue(rendered.contains("Do not combine entries or move text between entries."))
        XCTAssertTrue(rendered.contains(#"{"entries":[{"id":"entry-0","text":"source"}]}"#))
    }

    func testThreeHundredTurnsPackAcrossSpeakersIntoThreeBatches() async {
        let texts = (0..<300).map { index in
            "\(index):" + String(repeating: "x", count: 200 - "\(index):".count)
        }
        let document = makeDocument(texts.map { [$0] })
        let recorder = BatchRecorder { Self.response(for: $0) }

        let result = await MeetingReadingTurnFormatter().format(document) {
            try await recorder.format($0)
        }

        let batches = await recorder.batches
        XCTAssertEqual(batches.count, 3)
        XCTAssertTrue(batches.allSatisfy { $0.transcriptCharacterCount <= 20_000 })
        XCTAssertEqual(batches.flatMap(\.entries).map(\.text), texts)
        XCTAssertEqual(result.formatting.count, 300)
        XCTAssertEqual(result.progress, .init(completedRequests: 3, totalRequests: 3))
    }

    func testBatchStopsBeforeFirstCompleteParagraphThatWouldExceedBudget() async {
        let document = makeDocument([
            [String(repeating: "a", count: 11), String(repeating: "b", count: 9)],
            [String(repeating: "c", count: 1)],
        ])
        let recorder = BatchRecorder { Self.response(for: $0) }

        _ = await MeetingReadingTurnFormatter(maximumRequestCharacters: 20).format(document) {
            try await recorder.format($0)
        }

        let batches = await recorder.batches
        XCTAssertEqual(
            batches.map { $0.entries.map(\.text) },
            [
                [String(repeating: "a", count: 11), String(repeating: "b", count: 9)],
                ["c"],
            ])
    }

    func testOversizedParagraphSplitsAtSentenceEndingsWithoutLosingText() async {
        let paragraph = "First sentence. Second sentence. Third sentence."
        let document = makeDocument([[paragraph]])
        let recorder = BatchRecorder { Self.response(for: $0) }

        let result = await MeetingReadingTurnFormatter(maximumRequestCharacters: 25).format(document) {
            try await recorder.format($0)
        }

        let entries = await recorder.batches.flatMap(\.entries)
        XCTAssertGreaterThan(entries.count, 1)
        XCTAssertTrue(entries.allSatisfy { $0.text.count <= 25 })
        XCTAssertEqual(entries.map(\.text).joined(), paragraph)
        XCTAssertEqual(result.formatting.first?.formattedText, paragraph)
    }

    func testOversizedCJKAndQuotedParagraphsSplitAtSentenceEndings() async {
        let cjk = String(repeating: "第一句。第二句。", count: 4)
        let quoted = String(repeating: "He said \"Done.\" She agreed. ", count: 3)
        let document = makeDocument([[cjk], [quoted]])
        let recorder = BatchRecorder { Self.response(for: $0) }

        _ = await MeetingReadingTurnFormatter(maximumRequestCharacters: 20).format(document) {
            try await recorder.format($0)
        }

        let entries = await recorder.batches.flatMap(\.entries)
        XCTAssertEqual(entries.map(\.text).joined(), cjk + quoted)
        XCTAssertTrue(entries.allSatisfy { $0.text.count <= 20 })
        XCTAssertTrue(
            entries.filter { cjk.contains($0.text) }.dropLast().allSatisfy {
                $0.text.hasSuffix("。")
            })
        XCTAssertTrue(entries.contains { $0.text.hasSuffix("\"") })
    }

    func testResponseIDsMapReorderedEntriesBackToSourceTurns() async {
        let document = makeDocument([["first"], ["second"], ["third"]])

        let result = await MeetingReadingTurnFormatter().format(document) { batch in
            let entries = batch.entries.reversed().map {
                MeetingReadingTurnBatchEntry(id: $0.id, text: $0.text.uppercased())
            }
            return Self.response(entries: Array(entries))
        }

        XCTAssertEqual(result.formatting.map(\.formattedText), ["FIRST", "SECOND", "THIRD"])
    }

    func testMalformedMissingAndDuplicateIDsRetryThenUseRawBatchText() async {
        let document = makeDocument([["raw first"], ["raw second"]])
        let attempts = OSAllocatedUnfairLock(initialState: 0)

        let result = await MeetingReadingTurnFormatter().format(document) { batch in
            let attempt = attempts.withLock { value in
                value += 1
                return value
            }
            switch attempt {
            case 1: return "not json"
            case 2: return Self.response(entries: [batch.entries[0]])
            default: return Self.response(entries: [batch.entries[0], batch.entries[0]])
            }
        }

        XCTAssertEqual(attempts.withLock { $0 }, 3)
        XCTAssertEqual(result.formatting.map(\.formattedText), ["raw first", "raw second"])
    }

    func testRequestFailureRetriesTwiceAndSuccessfulRetryWins() async {
        let document = makeDocument([["clean me"]])
        let attempts = OSAllocatedUnfairLock(initialState: 0)

        let result = await MeetingReadingTurnFormatter().format(document) { batch in
            let attempt = attempts.withLock { value in
                value += 1; return value
            }
            if attempt < 3 { throw FixtureError.failed }
            return Self.response(
                entries: batch.entries.map {
                    .init(id: $0.id, text: "cleaned")
                })
        }

        XCTAssertEqual(attempts.withLock { $0 }, 3)
        XCTAssertEqual(result.formatting.first?.formattedText, "cleaned")
    }

    func testFailedBatchUsesVerbatimSourceInsteadOfDeterministicCleanup() async {
        let deterministic = makeDocument([["Deterministic text."]])
        let verbatim = makeDocument([["uh raw raw text"]])

        let result = await MeetingReadingTurnFormatter(maximumAttempts: 3).format(
            deterministic,
            sourceDocument: verbatim
        ) { _ in
            throw FixtureError.failed
        }

        XCTAssertEqual(result.formatting.first?.deterministicText, "Deterministic text.")
        XCTAssertEqual(result.formatting.first?.formattedText, "uh raw raw text")
    }

    func testContentProtectedValuesAndLargeOutputAreAcceptedWhenIDsMap() async {
        let document = makeDocument([["Keep 42 and https://example.com"]])
        let replacement = String(repeating: "different ", count: 500)

        let result = await MeetingReadingTurnFormatter().format(document) { batch in
            Self.response(entries: [.init(id: batch.entries[0].id, text: replacement)])
        }

        XCTAssertEqual(result.formatting.first?.formattedText, replacement)
    }

    func testCancellationStopsFurtherBatches() async {
        let document = makeDocument([["first"], ["cancel"], ["never"]])
        let recorder = BatchRecorder { batch in
            if batch.entries[0].text == "cancel" { throw CancellationError() }
            return Self.response(for: batch)
        }

        let result = await MeetingReadingTurnFormatter(maximumRequestCharacters: 6).format(document) {
            try await recorder.format($0)
        }

        XCTAssertTrue(result.wasCancelled)
        let requestCount = await recorder.batches.count
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(result.formatting.map(\.formattedText), ["first"])
        XCTAssertEqual(result.progress, .init(completedRequests: 1, totalRequests: 3))
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

    private static func response(for batch: MeetingReadingTurnFormattingBatch) -> String {
        response(entries: batch.entries)
    }

    private static func response(entries: [MeetingReadingTurnBatchEntry]) -> String {
        let object: [String: Any] = [
            "entries": entries.map { ["id": $0.id, "text": $0.text] }
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
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
            })
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

private enum FixtureError: Error {
    case failed
}

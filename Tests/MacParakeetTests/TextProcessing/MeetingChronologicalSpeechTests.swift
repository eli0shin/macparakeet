import XCTest
@testable import MacParakeetCore

final class MeetingChronologicalSpeechTests: XCTestCase {
    private var words: [WordTimestamp] {
        [
            WordTimestamp(word: "Before", startMs: 0, endMs: 1_000, confidence: 1, speakerId: "system"),
            WordTimestamp(word: "after", startMs: 900, endMs: 1_500, confidence: 1, speakerId: "system"),
            WordTimestamp(word: "Why?", startMs: 500, endMs: 1_100, confidence: 1, speakerId: "microphone"),
        ]
    }

    func testSavedMeetingKeepsQuestionBeforeContinuation() {
        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "", words: words, speakers: nil
        )
        let displayed = MeetingTranscriptDisplayBuilder.build(from: document)
        XCTAssertEqual(displayed.turns.map(\.text), ["Before", "Why?", "After"])
        XCTAssertEqual(document.turns.flatMap(\.wordReferences), [0, 2, 1])
        XCTAssertTrue(document.turns.allSatisfy { $0.overlap == nil })
        XCTAssertFalse(MeetingTranscriptDocumentRenderer.markdown(document).contains("Simultaneous speech"))
    }

    func testFiveMinuteSpeechDoesNotPushRepeatedQuestionsToTheEnd() {
        let speech = (0..<600).map { index in
            WordTimestamp(
                word: "speech", startMs: index * 500, endMs: index * 500 + 500,
                confidence: 1, speakerId: "system"
            )
        }
        let questions = [30_250, 150_250].map { start in
            WordTimestamp(
                word: "Why?", startMs: start, endMs: start + 600,
                confidence: 1, speakerId: "microphone"
            )
        }
        let evidence = speech + questions
        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "", words: evidence, speakers: nil
        )
        let displayed = MeetingTranscriptDisplayBuilder.build(from: document)
        XCTAssertEqual(displayed.turns.map(\.speakerId), ["system", "microphone", "system", "microphone", "system"])
        XCTAssertEqual(displayed.turns.map { $0.timeRange?.startMs }, [0, 30_250, 30_500, 150_250, 150_500])
        XCTAssertEqual(document.turns.flatMap(\.wordReferences).sorted(), Array(evidence.indices))
        XCTAssertEqual(Set(document.turns.map(\.id)).count, document.turns.count)
        let live = TranscriptParagraphBuilder.build(from: evidence)
        for question in questions {
            let index = live.firstIndex { $0.startMs == question.startMs }!
            XCTAssertEqual(live[index].text, "Why?")
            XCTAssertEqual(live[index + 1].startMs, question.startMs + 250)
        }
    }

    func testEqualStartTimesUseEvidenceOrder() {
        let evidence = [
            WordTimestamp(word: "First", startMs: 0, endMs: 500, confidence: 1, speakerId: "system"),
            WordTimestamp(word: "Second", startMs: 0, endMs: 500, confidence: 1, speakerId: "microphone"),
        ]
        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "", words: evidence, speakers: nil
        )
        XCTAssertEqual(document.turns.map(\.text), ["First", "Second"])
        XCTAssertEqual(TranscriptParagraphBuilder.build(from: evidence).map(\.text), ["First", "Second"])
    }

    func testStaleFormattingCannotRestoreReorderedSpeech() {
        let oldID = ReadingTurnIdentity(source: .system, speakerId: "system", firstWordIndex: 0)
        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "", words: words, speakers: nil,
            formatting: [MeetingReadingTurnFormatting(
                turnID: oldID, deterministicText: "Before after", formattedText: "Before after."
            )]
        )
        XCTAssertEqual(document.turns.map(\.text), ["Before", "Why?", "After"])
        XCTAssertTrue(document.turns.allSatisfy { $0.formattedText == nil })
    }

    func testLiveParagraphsKeepQuestionBeforeContinuation() {
        let paragraphs = TranscriptParagraphBuilder.build(from: words)
        XCTAssertEqual(paragraphs.map(\.text), ["Before", "Why?", "after"])
        XCTAssertEqual(paragraphs.map(\.startMs), [0, 500, 900])
    }
}

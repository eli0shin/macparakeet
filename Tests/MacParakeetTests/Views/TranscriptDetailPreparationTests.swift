import XCTest
import MacParakeetCore
@testable import MacParakeet

final class TranscriptDetailPreparationTests: XCTestCase {
    func testSnapshotPrecomputesDisplayData() {
        let transcription = makeTranscription()
        let customWords = [CustomWord(word: "helo", replacement: "hello")]
        let input = TranscriptDetailPreparationInput(
            transcription: transcription,
            customWords: customWords
        )

        let snapshot = TranscriptDetailPreparation.make(
            transcription: transcription,
            customWords: customWords,
            input: input
        )

        XCTAssertEqual(snapshot.preferredText, "Hello world")
        XCTAssertEqual(snapshot.textWordCount, 2)
        XCTAssertEqual(snapshot.timedWordCount, 2)
        XCTAssertEqual(snapshot.speakerStatistics["speaker-1"]?.wordCount, 2)
        XCTAssertEqual(snapshot.speakerStatistics["speaker-1"]?.speakingTimeMs, 1_000)
        XCTAssertEqual(snapshot.speakerLabels, ["speaker-1": "Ada"])
        XCTAssertEqual(snapshot.speakerColorIndices, ["speaker-1": 0])
        XCTAssertEqual(snapshot.segmentFindBlocks.map(\.text), ["helo world"])
        XCTAssertEqual(snapshot.textFindBlocks.map(\.text), ["Hello world"])
    }

    func testInputInvalidatesOnlyDisplayDependencies() {
        let transcription = makeTranscription()
        let original = TranscriptDetailPreparationInput(
            transcription: transcription,
            customWords: []
        )

        var unrelatedEdit = transcription
        unrelatedEdit.titleOverride = "New title"
        unrelatedEdit.updatedAt = transcription.updatedAt.addingTimeInterval(10)
        XCTAssertEqual(
            original,
            TranscriptDetailPreparationInput(transcription: unrelatedEdit, customWords: [])
        )

        var transcriptEdit = transcription
        transcriptEdit.cleanTranscript = "Edited text"
        XCTAssertNotEqual(
            original,
            TranscriptDetailPreparationInput(transcription: transcriptEdit, customWords: [])
        )

        var speakerRename = transcription
        speakerRename.speakers?[0].label = "Grace"
        XCTAssertNotEqual(
            original,
            TranscriptDetailPreparationInput(transcription: speakerRename, customWords: [])
        )

        var statusChange = transcription
        statusChange.status = .processing
        XCTAssertNotEqual(
            original,
            TranscriptDetailPreparationInput(transcription: statusChange, customWords: [])
        )

        XCTAssertNotEqual(
            original,
            TranscriptDetailPreparationInput(
                transcription: transcription,
                customWords: [CustomWord(word: "helo", replacement: "hello")]
            )
        )
    }

    private func makeTranscription() -> Transcription {
        Transcription(
            fileName: "Meeting.m4a",
            rawTranscript: "helo world",
            cleanTranscript: "Hello world",
            wordTimestamps: [
                WordTimestamp(
                    word: "helo",
                    startMs: 0,
                    endMs: 500,
                    confidence: 1,
                    speakerId: "speaker-1"
                ),
                WordTimestamp(
                    word: "world",
                    startMs: 500,
                    endMs: 1_000,
                    confidence: 1,
                    speakerId: "speaker-1"
                ),
            ],
            speakers: [SpeakerInfo(id: "speaker-1", label: "Ada")],
            diarizationSegments: [
                DiarizationSegmentRecord(
                    speakerId: "speaker-1",
                    startMs: 0,
                    endMs: 1_000
                )
            ],
            status: .completed,
            sourceType: .meeting
        )
    }
}

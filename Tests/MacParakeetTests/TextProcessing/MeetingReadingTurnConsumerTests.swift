import XCTest
@testable import MacParakeetCore

final class MeetingReadingTurnConsumerTests: XCTestCase {
    private let exportService = ExportService()

    func testReadableConsumersProjectOneSharedReadingTurnFixture() throws {
        let transcription = fixture()
        let document = try XCTUnwrap(CompletedMeetingReadingDocument.build(from: transcription))
        let expectedMarkdown = MeetingTranscriptDocumentRenderer.markdown(document)
        let expectedPlainText = MeetingTranscriptDocumentRenderer.plainText(document)

        XCTAssertTrue(expectedMarkdown.contains("> Simultaneous speech"))
        XCTAssertTrue(expectedMarkdown.contains("**Dana · [0:00]**"))
        XCTAssertTrue(document.turns.contains { $0.paragraphs.count == 2 })

        XCTAssertEqual(
            TranscriptAIContextFormatter.format(transcription: transcription),
            expectedMarkdown
        )
        XCTAssertEqual(exportService.formatForClipboard(transcription: transcription), expectedMarkdown)
        XCTAssertTrue(
            exportService.formatMarkdown(transcription: transcription).contains(expectedMarkdown)
        )
        XCTAssertTrue(
            exportService.formatPlainText(transcription: transcription).contains(expectedPlainText)
        )
        XCTAssertTrue(
            MeetingMarkdownRenderer().renderForClipboard(transcription: transcription)
                .contains("## Transcript\n\n\(expectedMarkdown)")
        )
    }

    func testPassageCopyAndNavigationUseContainingReadingTurn() throws {
        let document = try XCTUnwrap(CompletedMeetingReadingDocument.build(from: fixture()))
        let target = try XCTUnwrap(document.navigationTarget(containingWordReference: 4))
        let passage = try XCTUnwrap(document.passage(containingWordReference: 4))
        let copied = MeetingTranscriptDocumentRenderer.markdown(passage)

        XCTAssertEqual(target.turnID, passage.turns[0].id)
        XCTAssertEqual(target.timeRange, passage.turns[0].timeRange)
        XCTAssertTrue(copied.contains("**Dana · [0:03]**"))
        XCTAssertTrue(copied.contains("First. Second. Third."))
        XCTAssertFalse(copied.contains("00:00:03,000"))
        XCTAssertEqual(
            document.navigationTarget(containingTimeMs: 3_250)?.turnID,
            target.turnID
        )
        XCTAssertNil(document.navigationTarget(containingTimeMs: 2_000))
    }

    func testRawPhraseVocabularyPolicyStaysIdenticalAcrossDirectArtifactBackgroundAIAndCLIExport() throws {
        var transcription = fixture()
        transcription.rawTranscript = "uh mac parakeet"
        transcription.cleanTranscript = "MacParakeet"
        transcription.wordTimestamps = [
            word("uh", 0, 100, "microphone"),
            word("mac", 200, 400, "microphone"),
            word("parakeet", 450, 800, "microphone"),
        ]
        let configuration = CompletedMeetingReadingConfiguration(
            processingMode: .raw,
            customWords: [CustomWord(word: "mac parakeet", replacement: "MacParakeet")]
        )
        let document = try XCTUnwrap(
            CompletedMeetingReadingDocument.build(
                from: transcription,
                configuration: configuration
            )
        )
        let expected = MeetingTranscriptDocumentRenderer.markdown(document)
        let cliExportService = ExportService(
            meetingReadingConfiguration: configuration
        )

        XCTAssertTrue(expected.contains("uh MacParakeet"))
        XCTAssertEqual(
            TranscriptAIContextFormatter.format(
                transcription: transcription,
                meetingReadingConfiguration: configuration
            ),
            expected
        )
        XCTAssertTrue(
            MeetingMarkdownRenderer().render(
                transcription: transcription,
                promptResults: [],
                readingDocument: document
            ).contains("## Transcript\n\n\(expected)")
        )
        XCTAssertTrue(
            cliExportService.formatMarkdown(transcription: transcription)
                .contains(expected)
        )
        XCTAssertEqual(
            cliExportService.formatForClipboard(transcription: transcription),
            expected
        )
    }

    func testValidatedReadingTurnFormattingFlowsThroughReadableConsumers() throws {
        var transcription = fixture()
        let deterministic = try XCTUnwrap(
            CompletedMeetingReadingDocument.build(from: transcription)?.turns.first
        )
        transcription.meetingReadingTurnFormatting = [
            MeetingReadingTurnFormatting(
                turnID: deterministic.id,
                deterministicText: deterministic.deterministicText,
                formattedText: "We reached agreement."
            )
        ]

        let document = try XCTUnwrap(CompletedMeetingReadingDocument.build(from: transcription))
        let expected = MeetingTranscriptDocumentRenderer.markdown(document)

        XCTAssertTrue(expected.contains("We reached agreement."))
        XCTAssertFalse(expected.contains("We agree."))
        XCTAssertEqual(TranscriptAIContextFormatter.format(transcription: transcription), expected)
        XCTAssertTrue(exportService.formatMarkdown(transcription: transcription).contains(expected))
        XCTAssertTrue(
            MeetingMarkdownRenderer().renderForClipboard(transcription: transcription)
                .contains(expected)
        )
    }

    func testSpeakerRenameFlowsThroughEveryReadableConsumer() throws {
        let renamed = fixture(remoteLabel: "Alex")
        let document = try XCTUnwrap(CompletedMeetingReadingDocument.build(from: renamed))
        let expected = MeetingTranscriptDocumentRenderer.markdown(document)

        XCTAssertTrue(expected.contains("**Alex · [0:00]**"))
        XCTAssertFalse(expected.contains("Dana"))
        XCTAssertEqual(TranscriptAIContextFormatter.format(transcription: renamed), expected)
        XCTAssertEqual(exportService.formatForClipboard(transcription: renamed), expected)
        XCTAssertTrue(exportService.formatMarkdown(transcription: renamed).contains(expected))
        XCTAssertTrue(
            MeetingMarkdownRenderer().renderForClipboard(transcription: renamed)
                .contains(expected)
        )
    }

    func testSubtitleExportsKeepCueTimingInsteadOfReadingTurnTiming() throws {
        let transcription = fixture()
        let document = try XCTUnwrap(CompletedMeetingReadingDocument.build(from: transcription))
        let words = try XCTUnwrap(transcription.wordTimestamps)
        let cues = exportService.buildSubtitleCues(from: words)

        XCTAssertGreaterThan(cues.count, document.turns.count)
        XCTAssertEqual(
            exportService.formatSRT(transcription: transcription),
            exportService.formatSRT(words: words, speakers: transcription.speakers))
        XCTAssertEqual(
            exportService.formatVTT(transcription: transcription),
            exportService.formatVTT(words: words, speakers: transcription.speakers))
    }

    func testTimedMeetingWithoutAttributionOmitsFabricatedSpeaker() throws {
        let transcription = Transcription(
            fileName: "Plain Meeting",
            rawTranscript: "No attribution.",
            wordTimestamps: [
                WordTimestamp(
                    word: "No attribution.",
                    startMs: 1_000,
                    endMs: 2_000,
                    confidence: 0.9,
                    speakerId: nil
                )
            ],
            speakers: nil,
            diarizationSegments: nil,
            status: .completed,
            sourceType: .meeting
        )
        let document = try XCTUnwrap(CompletedMeetingReadingDocument.build(from: transcription))

        XCTAssertEqual(
            MeetingTranscriptDocumentRenderer.markdown(document),
            """
            **[0:01]**

            No attribution.
            """
        )
    }

    func testUntimedMeetingOmitsFabricatedSpeakerAndTimeAndVerbatimRemainsAvailable() throws {
        let untimed = Transcription(
            fileName: "Legacy Meeting",
            rawTranscript: "Uh, original words.",
            cleanTranscript: "Stored clean substitute.",
            status: .completed,
            sourceType: .meeting
        )
        let cleaned = try XCTUnwrap(CompletedMeetingReadingDocument.build(from: untimed))
        let verbatim = try XCTUnwrap(
            CompletedMeetingReadingDocument.build(from: untimed, cleanup: .verbatim)
        )

        XCTAssertEqual(MeetingTranscriptDocumentRenderer.markdown(cleaned), "original words.")
        XCTAssertEqual(MeetingTranscriptDocumentRenderer.markdown(verbatim), "Uh, original words.")
    }

    private func fixture(remoteLabel: String = "Dana") -> Transcription {
        Transcription(
            fileName: "Reading Turn Review",
            durationMs: 7_000,
            rawTranscript: "We agree. Yes. First. Second. Third. Fourth.",
            cleanTranscript: "We agree. Yes. First. Second. Third. Fourth.",
            wordTimestamps: [
                word("We", 0, 400, "microphone"),
                word("Yes.", 100, 300, "system:S1"),
                word("agree.", 450, 800, "microphone"),
                word("First.", 3_000, 3_300, "system:S1"),
                word("Second.", 3_500, 3_800, "system:S1"),
                word("Third.", 4_000, 4_300, "system:S1"),
                word("Fourth.", 4_500, 4_800, "system:S1"),
            ],
            speakers: [
                SpeakerInfo(id: "microphone", label: "Me"),
                SpeakerInfo(id: "system:S1", label: remoteLabel),
            ],
            status: .completed,
            sourceType: .meeting
        )
    }

    private func word(_ text: String, _ startMs: Int, _ endMs: Int, _ speakerId: String) -> WordTimestamp {
        WordTimestamp(
            word: text,
            startMs: startMs,
            endMs: endMs,
            confidence: 0.99,
            speakerId: speakerId
        )
    }
}

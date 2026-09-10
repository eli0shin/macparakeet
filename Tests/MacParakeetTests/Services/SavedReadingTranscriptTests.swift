import XCTest
@testable import MacParakeetCore

/// Persistence/consumer contract checks, not evidence of acoustic diarization quality.
final class SavedReadingTranscriptTests: XCTestCase {
    private func word(_ text: String, _ start: Int, _ end: Int, _ speaker: String? = nil) -> WordTimestamp {
        WordTimestamp(word: text, startMs: start, endMs: end, confidence: 0.9, speakerId: speaker)
    }

    private func stt(_ words: [WordTimestamp]) -> STTResult {
        STTResult(text: words.map(\.word).joined(separator: " "), words: words.map {
            TimestampedWord(word: $0.word, startMs: $0.startMs, endMs: $0.endMs, confidence: $0.confidence)
        })
    }

    private func assertConsumers(_ saved: Transcription, expected: [String]) throws {
        let document = try XCTUnwrap(CompletedMeetingReadingDocument.build(from: saved))
        XCTAssertEqual(document.turns.map(\.text), expected)
        let markdown = MeetingTranscriptDocumentRenderer.markdown(document)
        let exporter = ExportService()
        XCTAssertEqual(exporter.formatForClipboard(transcription: saved), markdown)
        XCTAssertTrue(exporter.formatMarkdown(transcription: saved).contains(markdown))
        XCTAssertEqual(TranscriptAIContextFormatter.format(transcription: saved), markdown)
        XCTAssertEqual(document.turns.flatMap(\.wordReferences), Array((saved.wordTimestamps ?? []).indices))
        XCTAssertEqual(KnowledgeSegmenter.deriveSegments(for: saved).map(\.text), expected)
        let timed = Transcription(fileName: "evidence", wordTimestamps: saved.wordTimestamps,
                                  speakers: saved.speakers, status: .completed)
        XCTAssertEqual(exporter.formatSRT(transcription: saved), exporter.formatSRT(transcription: timed))
    }

    func testImportAlignsTimestampGapsAndPersistsCombinedContributions() async throws {
        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        let engine = MockSTTClient()
        let evidence = [word("Before", 0, 100), word("during", 200, 300), word("gap", 600, 700),
                        // The late gap stays S1; a word starting at S2's boundary belongs to S2.
                        word("after.", 1_700, 1_800), word("Reply.", 1_900, 2_000)]
        await engine.configure(result: stt(evidence))
        let diarizer = MockDiarizationService()
        await diarizer.configure(result: MacParakeetDiarizationResult(
            segments: [SpeakerSegment(speakerId: "S1", startMs: 150, endMs: 400),
                       SpeakerSegment(speakerId: "S1", startMs: 900, endMs: 1_150),
                       SpeakerSegment(speakerId: "S2", startMs: 1_900, endMs: 2_100)],
            speakerCount: 2, speakers: [SpeakerInfo(id: "S1", label: "Dana"), SpeakerInfo(id: "S2", label: "Lee")]))
        let service = TranscriptionService(audioProcessor: MockAudioProcessor(), sttTranscriber: engine,
                                           transcriptionRepo: repository, diarizationService: diarizer)
        let completed = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/fixture.wav"))
        let saved = try XCTUnwrap(repository.fetch(id: completed.id))
        XCTAssertEqual(saved.wordTimestamps?.map(\.speakerId), ["S1", "S1", "S1", "S1", "S2"])
        XCTAssertEqual(saved.wordTimestamps?.map(\.startMs), evidence.map(\.startMs))
        XCTAssertEqual(saved.wordTimestamps?.map(\.endMs), evidence.map(\.endMs))
        try assertConsumers(saved, expected: ["Before during gap after.", "Reply."])
        XCTAssertEqual(saved.transcriptSegments?.flatMap { $0.wordReferences ?? [] }, Array(evidence.indices))
        _ = try repository.updateSpeakerLabel(id: saved.id, speakerID: "S1", label: "Renamed")
        let renamed = try XCTUnwrap(repository.fetch(id: saved.id))
        XCTAssertEqual(renamed.readingDocument?.turns.map(\.id), saved.readingDocument?.turns.map(\.id))
        XCTAssertEqual(CompletedMeetingReadingDocument.build(from: renamed)?.turns.first?.speakerLabel, "Renamed")
    }

    func testLongPausesRemainParagraphsInsideOnePersistedContribution() async throws {
        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        let engine = MockSTTClient()
        await engine.configure(result: stt([word("Before.", 0, 1_000),
                                           word("Still speaking.", 20_000, 21_000), word("After.", 30_000, 31_000)]))
        let service = TranscriptionService(audioProcessor: MockAudioProcessor(), sttTranscriber: engine,
                                           transcriptionRepo: repository)
        let completed = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/fixture.wav"))
        let saved = try XCTUnwrap(repository.fetch(id: completed.id))
        XCTAssertEqual(saved.readingDocument?.turns.count, 1)
        try assertConsumers(saved, expected: ["Before.\n\nStill speaking.\n\nAfter."])
    }

    func testReadingAssemblyNeverMovesEvidenceAroundEnclosingSpeakerSpans() throws {
        let words = [word("A0", 0, 1_000, "A"), word("B0", 20_000, 21_000, "B"),
                     word("C", 30_000, 35_000, "C"), word("A1", 32_000, 33_000, "A"),
                     word("B1", 59_000, 60_000, "B"), word("A2", 99_000, 100_000, "A")]
        let document = FinalTranscriptAssembler.build(transcriptText: "", words: words, speakers: [], cleanup: .verbatim)
        XCTAssertEqual(document.turns.flatMap(\.wordReferences), Array(words.indices))
        XCTAssertEqual(document.turns.map(\.text), words.map(\.word))
    }

    func testFinalizationKeepsRepeatedWordsOnBothSources() {
        let evidence = [word("Please", 100, 300), word("continue", 400, 700)]
        let finalized = MeetingTranscriptFinalizer.finalize(sourceTranscripts: [
            .init(source: .microphone, result: stt(evidence), startOffsetMs: 0),
            .init(source: .system, result: stt(evidence), startOffsetMs: 0),
        ])
        XCTAssertEqual(finalized.words.count, 4)
        XCTAssertEqual(finalized.words.filter { $0.speakerId == "microphone" }.map(\.word), evidence.map(\.word))
        XCTAssertEqual(finalized.words.filter { $0.speakerId == "system" }.map(\.word), evidence.map(\.word))
    }

    func testFinalAccuracySettingsKeepExclusiveOutputAndEnableForkRepair() {
        let live = DiarizationService.offlineConfig(speakerConstraint: nil)
        let final = DiarizationService.offlineConfig(speakerConstraint: nil, finalTranscript: true)
        XCTAssertEqual(final.segmentationStepRatio, 0.1)
        XCTAssertEqual(final.minSegmentDuration, 0)
        XCTAssertTrue(final.exclusiveSegments)
        XCTAssertEqual(final.minGapDuration, live.minGapDuration)
        XCTAssertEqual(final.embeddingExcludeOverlap, live.embeddingExcludeOverlap)
        XCTAssertTrue(final.zeroVoteReembed.enabled)
        XCTAssertFalse(live.zeroVoteReembed.enabled)
        XCTAssertEqual(final.clusteringThreshold, live.clusteringThreshold)
        XCTAssertEqual(final.windowDuration, 10)
        XCTAssertEqual(live.segmentationStepRatio, 0.2)
    }

    private struct CancellingDiarizer: DiarizationServiceProtocol {
        func diarize(audioURL: URL) async throws -> MacParakeetDiarizationResult {
            // Model work can return normally even after its caller is cancelled.
            withUnsafeCurrentTask { $0?.cancel() }
            return MacParakeetDiarizationResult(
                segments: [SpeakerSegment(speakerId: "S1", startMs: 0, endMs: 1_000)],
                speakerCount: 1, speakers: [SpeakerInfo(id: "S1", label: "Speaker 1")])
        }
        func prepareModels(onProgress: (@Sendable (String) -> Void)?) async throws {}
        func isReady() async -> Bool { true }
    }

    func testCancellationAfterModelReturnDoesNotPersistCompletedImport() async throws {
        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        let engine = MockSTTClient()
        await engine.configure(result: stt([word("Keep", 0, 500)]))
        let service = TranscriptionService(audioProcessor: MockAudioProcessor(), sttTranscriber: engine,
                                           transcriptionRepo: repository, diarizationService: CancellingDiarizer())
        let task = Task {
            try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/cancelled.wav"))
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must reach the import lifecycle handler")
        } catch is CancellationError {
            let saved = try XCTUnwrap(repository.fetchAll().first)
            XCTAssertEqual(saved.status, .cancelled)
            XCTAssertNil(saved.readingDocument)
        }
    }

    func testLegacyDocumentIgnoresRetiredActivityMetadata() throws {
        let data = Data(#"{"turns":[],"activityGaps":[{"source":"system","startMs":0,"endMs":1000}]}"#.utf8)
        let document = try JSONDecoder().decode(MeetingTranscriptPresentationDocument.self, from: data)
        XCTAssertTrue(document.turns.isEmpty)
    }

    func testTimedImportAppliesVocabularyOnceAndOnlyExtractsTheActualTerminalAction() async throws {
        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        let vocabulary = CustomWordRepository(dbQueue: database.dbQueue)
        let snippets = TextSnippetRepository(dbQueue: database.dbQueue)
        try vocabulary.save(CustomWord(word: "acme", replacement: "ACME Corporation"))
        try snippets.save(TextSnippet(trigger: "press return", expansion: "", action: .returnKey))
        let engine = MockSTTClient()
        let evidence = [word("acme", 0, 500), word("please", 600, 800), word("press", 900, 1_100),
                        word("return", 1_200, 1_400), word("Then", 5_000, 5_500), word("continue", 5_600, 6_000),
                        word("press", 6_100, 6_300), word("return", 6_400, 6_700)]
        await engine.configure(result: stt(evidence))
        let service = TranscriptionService(audioProcessor: MockAudioProcessor(), sttTranscriber: engine,
                                           transcriptionRepo: repository, customWordRepo: vocabulary,
                                           snippetRepo: snippets, processingMode: { .clean })
        let completed = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/fixture.wav"))
        let saved = try XCTUnwrap(repository.fetch(id: completed.id))
        try assertConsumers(saved, expected: ["ACME Corporation please press return\n\nThen continue"])
        XCTAssertEqual(saved.wordTimestamps, evidence)
    }

    func testLegacyEditedAndUntimedResultsDoNotInventStructure() async throws {
        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        let legacy = Transcription(fileName: "legacy", rawTranscript: "Unchanged", status: .completed, sourceType: .meeting)
        try repository.save(legacy)
        _ = CompletedMeetingReadingDocument.build(from: legacy)
        XCTAssertNil(try repository.fetch(id: legacy.id)?.readingDocument)
        let engine = MockSTTClient()
        await engine.configure(result: STTResult(text: "Untimed result"))
        let service = TranscriptionService(audioProcessor: MockAudioProcessor(), sttTranscriber: engine,
                                           transcriptionRepo: repository)
        let untimed = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/untimed.wav"))
        XCTAssertEqual(untimed.rawTranscript, "Untimed result")
        XCTAssertNil(untimed.readingDocument)
        await engine.configure(result: stt([word("Original", 0, 500)]))
        let timed = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/timed.wav"))
        let edited = try XCTUnwrap(repository.updateTranscriptText(id: timed.id, cleanTranscript: "My edit", isTranscriptEdited: true))
        XCTAssertNil(CompletedMeetingReadingDocument.build(from: edited))
        XCTAssertEqual(ExportService().formatForClipboard(transcription: edited), "My edit")
        XCTAssertEqual(TranscriptAIContextFormatter.format(transcription: edited), "My edit")
    }
}

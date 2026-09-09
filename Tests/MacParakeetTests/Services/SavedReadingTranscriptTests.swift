import XCTest
import AVFoundation
@testable import MacParakeetCore
@testable import MacParakeet

struct FixtureSpeechActivity: OfflineSpeechActivityDetecting {
    let ranges: [ReadingTurnTimeRange]
    var error: (any Error)? = nil
    func quietRanges(audioURL: URL) async throws -> [ReadingTurnTimeRange] {
        if let error { throw error }
        return ranges
    }
}

final class SavedReadingTranscriptTests: XCTestCase {
    private func word(_ text: String, _ start: Int, _ end: Int, _ speaker: String? = nil) -> WordTimestamp {
        WordTimestamp(word: text, startMs: start, endMs: end, confidence: 0.9, speakerId: speaker)
    }

    private func stt(_ words: [WordTimestamp]) -> STTResult {
        STTResult(
            text: words.map(\.word).joined(separator: " "),
            words: words.map {
                TimestampedWord(word: $0.word, startMs: $0.startMs, endMs: $0.endMs, confidence: $0.confidence)
            })
    }

    private func assertConsumers(
        _ saved: Transcription, expected: [String], file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let document = try XCTUnwrap(CompletedMeetingReadingDocument.build(from: saved), file: file, line: line)
        XCTAssertEqual(document.turns.map(\.text), expected, file: file, line: line)
        let markdown = MeetingTranscriptDocumentRenderer.markdown(document)
        let exporter = ExportService()
        XCTAssertEqual(exporter.formatForClipboard(transcription: saved), markdown, file: file, line: line)
        XCTAssertTrue(exporter.formatMarkdown(transcription: saved).contains(markdown), file: file, line: line)
        XCTAssertTrue(
            exporter.formatPlainText(transcription: saved).contains(
                MeetingTranscriptDocumentRenderer.plainText(document)), file: file, line: line)
        XCTAssertEqual(TranscriptAIContextFormatter.format(transcription: saved), markdown, file: file, line: line)
        XCTAssertEqual(
            TranscriptAIContextFormatter.format(transcription: saved, mode: .plainTranscript),
            expected.joined(separator: "\n\n"), file: file, line: line)
        let refs = document.turns.flatMap(\.wordReferences)
        XCTAssertEqual(refs.sorted(), Array((saved.wordTimestamps ?? []).indices), file: file, line: line)
        XCTAssertEqual(Set(refs).count, refs.count, file: file, line: line)
        for reference in refs {
            let passage = try XCTUnwrap(document.passage(containingWordReference: reference), file: file, line: line)
            XCTAssertEqual(passage.turns.count, 1, file: file, line: line)
            XCTAssertTrue(passage.turns[0].wordReferences.contains(reference), file: file, line: line)
        }
        let timed = Transcription(
            fileName: "evidence", wordTimestamps: saved.wordTimestamps, speakers: saved.speakers, status: .completed)
        XCTAssertEqual(
            exporter.formatSRT(transcription: saved), exporter.formatSRT(transcription: timed), file: file, line: line)
    }

    func testMeetingFinalizationSavesContainedCrossingAndUncertainBlocks() async throws {
        let scenarios: [([WordTimestamp], [WordTimestamp], [String])] = [
            (
                [word("Before", 0, 1_000), word("concurrent", 4_500, 5_500), word("after", 9_000, 10_000)],
                [word("Short", 4_000, 4_600), word("reply", 5_000, 6_000)],
                ["Before", "Short reply", "Concurrent\n\nAfter"]
            ),
            (
                [word("First", 0, 1_000), word("finishes", 5_000, 6_000)],
                [word("Second", 4_000, 5_500), word("continues", 7_000, 8_000)],
                ["First\n\nFinishes", "Second continues"]
            ),
            (
                [word("Shared", 0, 1_000), word("start", 5_000, 6_000)],
                [word("Nearly", 100, 700), word("together", 1_000, 2_000)],
                ["Shared\n\nStart", "Nearly together"]
            ),
            (
                [word("Inside", 0, 5_000), word("resume", 9_000, 10_000)],
                [word("Do", 4_000, 4_500), word("not split", 5_000, 6_000)],
                ["Inside", "Do not split", "Resume"]
            ),
        ]
        for (microphone, system, expected) in scenarios {
            let database = try DatabaseManager()
            let repository = TranscriptionRepository(dbQueue: database.dbQueue)
            let segments = SegmentRepository(dbQueue: database.dbQueue)
            let engine = MockSTTClient()
            await engine.configureSequence(results: [stt(microphone), stt(system)])
            let service = TranscriptionService(
                audioProcessor: MockAudioProcessor(), sttTranscriber: engine,
                transcriptionRepo: repository, segmentRepo: segments,
                meetingArtifactStore: nil, meetingAutomationHookRunner: nil,
                speechActivityDetector: FixtureSpeechActivity(ranges: [])
            )
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let microphoneURL = folder.appendingPathComponent("mic.wav")
            let systemURL = folder.appendingPathComponent("system.wav")
            try Data().write(to: microphoneURL)
            try Data().write(to: systemURL)
            let recording = MeetingRecordingOutput(
                sessionID: UUID(), displayName: "Reading order", folderURL: folder,
                mixedAudioURL: folder.appendingPathComponent("mixed.m4a"),
                microphoneAudioURL: microphoneURL, systemAudioURL: systemURL, durationSeconds: 12,
                sourceAlignment: MeetingSourceAlignment(
                    meetingOriginHostTime: nil,
                    microphone: .init(
                        firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0,
                        writtenFrameCount: 576_000, sampleRate: 48_000),
                    system: .init(
                        firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0,
                        writtenFrameCount: 576_000, sampleRate: 48_000)
                )
            )
            let completed = try await service.transcribeMeeting(recording: recording)
            let saved = try XCTUnwrap(repository.fetch(id: completed.id))
            XCTAssertEqual(saved.readingDocument, completed.readingDocument)
            XCTAssertEqual(saved.wordTimestamps, completed.wordTimestamps)
            try assertConsumers(saved, expected: expected)
            XCTAssertEqual(try segments.fetch(transcriptionId: saved.id).map(\.text), expected)
            XCTAssertEqual(
                saved.transcriptSegments?.flatMap { $0.wordReferences ?? [] },
                saved.readingDocument?.turns.flatMap(\.wordReferences))
        }
    }

    func testImportedRecordingUsesSpeakerGapsAndSavesOneWordExchanges() async throws {
        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        let engine = MockSTTClient()
        let words = [word("Ready?", 0, 500), word("Yes.", 1_000, 1_500), word("Go.", 2_000, 2_500)]
        await engine.configure(result: stt(words))
        let diarizer = MockDiarizationService()
        await diarizer.configure(
            result: MacParakeetDiarizationResult(
                segments: [
                    SpeakerSegment(speakerId: "S1", startMs: 0, endMs: 600),
                    SpeakerSegment(speakerId: "S2", startMs: 900, endMs: 1_600),
                    SpeakerSegment(speakerId: "S1", startMs: 1_900, endMs: 2_600),
                ],
                speakerCount: 2, speakers: [SpeakerInfo(id: "S1", label: "Dana"), SpeakerInfo(id: "S2", label: "Lee")]
            ))
        let service = TranscriptionService(
            audioProcessor: MockAudioProcessor(), sttTranscriber: engine, transcriptionRepo: repository,
            diarizationService: diarizer, speechActivityDetector: FixtureSpeechActivity(ranges: [])
        )
        let result = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/fixture.wav"))
        let saved = try XCTUnwrap(repository.fetch(id: result.id))
        try assertConsumers(saved, expected: ["Ready?", "Yes.", "Go."])
        XCTAssertEqual(saved.wordTimestamps?.map(\.speakerId), ["S1", "S2", "S1"])
        _ = try repository.updateSpeakerLabel(id: saved.id, speakerID: "S1", label: "Renamed")
        let renamed = try XCTUnwrap(repository.fetch(id: saved.id))
        let renamedDocument = try XCTUnwrap(CompletedMeetingReadingDocument.build(from: renamed))
        XCTAssertEqual(renamedDocument.turns.map(\.id), saved.readingDocument?.turns.map(\.id))
        XCTAssertEqual(renamedDocument.turns[0].speakerLabel, "Renamed")
    }

    func testActivitySplitsLongSingleSpeakerImportWithoutDurationOrSentenceCuts() async throws {
        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        let engine = MockSTTClient()
        await engine.configure(
            result: stt([
                word("Before.", 0, 1_000), word("Still speaking.", 20_000, 21_000), word("After.", 30_000, 31_000),
            ]))
        let service = TranscriptionService(
            audioProcessor: MockAudioProcessor(), sttTranscriber: engine, transcriptionRepo: repository,
            speechActivityDetector: FixtureSpeechActivity(ranges: [ReadingTurnTimeRange(startMs: 24_000, endMs: 28_000)]
            )
        )
        let completed = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/fixture.wav"))
        var saved = try XCTUnwrap(repository.fetch(id: completed.id))
        XCTAssertEqual(saved.readingDocument?.turns.count, 2)
        XCTAssertEqual(saved.readingDocument?.turns[0].wordReferences, [0, 1])
        saved.filePath = nil
        try repository.save(saved)
        let reloaded = try XCTUnwrap(repository.fetch(id: saved.id))
        try assertConsumers(reloaded, expected: ["Before.\n\nStill speaking.", "After."])
        XCTAssertEqual(reloaded.readingDocument?.activityGaps?.count, 1)
    }

    func testNestedAndCrossingChainsPreserveExactNoncontiguousReferences() throws {
        let cases: [([WordTimestamp], [String])] = [
            (
                [
                    word("A0", 0, 1_000, "A"), word("B0", 20_000, 21_000, "B"),
                    word("C", 30_000, 35_000, "C"), word("A1", 32_000, 33_000, "A"),
                    word("B1", 59_000, 60_000, "B"), word("A2", 99_000, 100_000, "A"),
                ],
                ["A0", "B0", "C", "B1", "A1 A2"]
            ),
            (
                [
                    word("A0", 0, 1_000, "A"), word("B0", 20_000, 21_000, "B"),
                    word("C0", 35_000, 36_000, "C"), word("B1", 39_000, 40_000, "B"),
                    word("D0", 50_000, 51_000, "D"), word("C1", 54_000, 55_000, "C"),
                    word("D1", 69_000, 70_000, "D"), word("A1", 119_000, 120_000, "A"),
                ],
                ["A0", "B0 B1", "C0 C1", "D0 D1", "A1"]
            ),
        ]
        for (words, expected) in cases {
            // Continuous positive activity prevents word gaps alone from
            // becoming silence. This tests supplied evidence, not the detector.
            let speakers = Array(Set(words.compactMap(\.speakerId))).sorted()
            let regions = speakers.map { speaker in
                let lane = words.filter { $0.speakerId == speaker }
                return DiarizationSegmentRecord(
                    speakerId: speaker, startMs: lane.first!.startMs, endMs: lane.last!.endMs)
            }
            let document = FinalTranscriptAssembler.build(
                transcriptText: words.map(\.word).joined(separator: " "), words: words,
                speakers: speakers.map { SpeakerInfo(id: $0, label: $0) },
                diarizationSegments: regions, cleanup: .verbatim
            )
            let database = try DatabaseManager()
            let repository = TranscriptionRepository(dbQueue: database.dbQueue)
            let record = Transcription(
                fileName: "policy", cleanTranscript: document.turns.map(\.text).joined(separator: "\n\n"),
                wordTimestamps: words, readingDocument: document, status: .completed
            )
            try repository.save(record)
            let saved = try XCTUnwrap(repository.fetch(id: record.id))
            // Paragraph pauses are layout only; flatten them for block assertions.
            XCTAssertEqual(
                saved.readingDocument?.turns.map { $0.text.replacingOccurrences(of: "\n\n", with: " ") }, expected)
            let references = try XCTUnwrap(saved.readingDocument?.turns.flatMap(\.wordReferences))
            if words.count == 6 {
                let savedTurns = try XCTUnwrap(saved.readingDocument?.turns)
                let identified = identifiedReadingTurns(savedTurns)
                let index = ReadingTurnPlaybackIndex(turns: savedTurns, words: words)
                // At 59s B is speaking. A's resumed block contains earlier and
                // later words, but its enclosing range must not steal focus.
                XCTAssertEqual(index.turnID(at: 59_000)?.speakerId, "B")
                XCTAssertEqual(index.turnID(at: 34_000)?.speakerId, "C")
                XCTAssertEqual(index.turnID(at: 99_000)?.speakerId, "A")
                XCTAssertEqual(
                    readingTurnScrollTarget(for: 59_000, in: identified, playbackIndex: index),
                    identified.first { $0.turn.wordReferences.contains(4) }?.scrollID
                )
            }
            XCTAssertEqual(references.sorted(), Array(words.indices))
            for speaker in speakers {
                XCTAssertEqual(
                    references.filter { words[$0].speakerId == speaker },
                    words.indices.filter { words[$0].speakerId == speaker })
            }
        }
    }

    func testTimedImportAppliesVocabularyOnceAndOnlyExtractsTheActualTerminalAction() async throws {
        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        let vocabulary = CustomWordRepository(dbQueue: database.dbQueue)
        let snippets = TextSnippetRepository(dbQueue: database.dbQueue)
        try vocabulary.save(CustomWord(word: "acme", replacement: "ACME Corporation"))
        try snippets.save(TextSnippet(trigger: "press return", expansion: "", action: .returnKey))
        let engine = MockSTTClient()
        let evidence = [
            word("acme", 0, 500), word("please", 600, 800),
            word("press", 900, 1_100), word("return", 1_200, 1_400),
            word("Then", 5_000, 5_500), word("continue", 5_600, 6_000),
            word("press", 6_100, 6_300), word("return", 6_400, 6_700),
        ]
        await engine.configure(result: stt(evidence))
        let service = TranscriptionService(
            audioProcessor: MockAudioProcessor(), sttTranscriber: engine, transcriptionRepo: repository,
            customWordRepo: vocabulary, snippetRepo: snippets, processingMode: { .clean },
            speechActivityDetector: FixtureSpeechActivity(ranges: [])
        )
        let completed = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/fixture.wav"))
        let saved = try XCTUnwrap(repository.fetch(id: completed.id))
        try assertConsumers(saved, expected: ["ACME Corporation please press return\n\nThen continue"])
        XCTAssertEqual(saved.wordTimestamps, evidence)
    }

    func testLegacyEditedAndUntimedResultsDoNotInventStructure() async throws {
        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        let legacy = Transcription(
            fileName: "legacy", rawTranscript: "Unchanged", status: .completed, sourceType: .meeting)
        try repository.save(legacy)
        _ = CompletedMeetingReadingDocument.build(from: legacy)
        XCTAssertNil(try repository.fetch(id: legacy.id)?.readingDocument)

        let engine = MockSTTClient()
        await engine.configure(result: STTResult(text: "Untimed result"))
        let service = TranscriptionService(
            audioProcessor: MockAudioProcessor(), sttTranscriber: engine,
            transcriptionRepo: repository,
            speechActivityDetector: FixtureSpeechActivity(ranges: []))
        let untimed = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/untimed.wav"))
        XCTAssertEqual(untimed.rawTranscript, "Untimed result")
        XCTAssertNil(untimed.readingDocument)
        XCTAssertNil(untimed.transcriptSegments)

        await engine.configure(result: stt([word("Original", 0, 500)]))
        let timed = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/timed.wav"))
        let edited = try XCTUnwrap(
            repository.updateTranscriptText(id: timed.id, cleanTranscript: "My edit", isTranscriptEdited: true))
        XCTAssertNil(CompletedMeetingReadingDocument.build(from: edited))
        XCTAssertEqual(ExportService().formatForClipboard(transcription: edited), "My edit")
        XCTAssertEqual(TranscriptAIContextFormatter.format(transcription: edited), "My edit")
        XCTAssertEqual(KnowledgeSegmenter.deriveSegments(for: edited).map(\.text), ["My edit"])
    }

    func testActivityFailureFallsBackButCancellationDoesNotPublishACompletedDocument() async throws {
        for cancelled in [false, true] {
            let database = try DatabaseManager()
            let repository = TranscriptionRepository(dbQueue: database.dbQueue)
            let engine = MockSTTClient()
            await engine.configure(result: stt([word("Keep", 0, 500), word("everything", 1_000, 1_500)]))
            let failure: any Error = cancelled ? CancellationError() : CocoaError(.fileReadCorruptFile)
            let service = TranscriptionService(
                audioProcessor: MockAudioProcessor(), sttTranscriber: engine, transcriptionRepo: repository,
                speechActivityDetector: FixtureSpeechActivity(ranges: [], error: failure)
            )
            do {
                let completed = try await service.transcribe(fileURL: URL(fileURLWithPath: "/tmp/fixture.wav"))
                XCTAssertFalse(cancelled)
                let saved = try XCTUnwrap(repository.fetch(id: completed.id))
                try assertConsumers(saved, expected: ["Keep everything"])
            } catch is CancellationError {
                XCTAssertTrue(cancelled)
                let records = try repository.fetchAll()
                XCTAssertEqual(records.count, 1)
                XCTAssertEqual(records.first?.status, .cancelled)
                XCTAssertNil(records.first?.readingDocument)
            }
        }
    }

    func testCachedDetectorFindsSilenceBetweenSyntheticSpeech() async throws {
        guard ProcessInfo.processInfo.environment["MACPARAKEET_TEST_CACHED_ACTIVITY"] == "1" else {
            throw XCTSkip("Opt-in cached-model acoustic smoke test; no downloads or private recordings")
        }
        guard MeetingVADService.isModelCached() else { throw XCTSkip("VAD model is not installed") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("synthetic.aiff")
        let synthesis = Process()
        synthesis.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        synthesis.arguments = [
            "-o", audio.path,
            "This is a local test of speech activity. [[slnc 2500]] The second contribution follows a clear silence.",
        ]
        try synthesis.run()
        synthesis.waitUntilExit()
        XCTAssertEqual(synthesis.terminationStatus, 0)
        let file = try AVAudioFile(forReading: audio)
        let durationMs = Int(Double(file.length) * 1_000 / file.processingFormat.sampleRate)
        let gaps = try await OfflineSpeechActivityDetector().quietRanges(audioURL: audio)
        XCTAssertTrue(
            gaps.contains {
                $0.endMs - $0.startMs >= 1_000 && $0.startMs > 0 && $0.endMs < durationMs - 500
            }, "The cached detector must find the inserted silence, not label the entire speech file as quiet")
    }

    func testAcousticFramesDoNotForceSpeechDurationCutsOrRetainUncertainSilence() {
        let probabilities: [Float] = [0.9, 0.05, 0.05, 0.4, 0.9, .nan, 0.05]
        XCTAssertEqual(
            OfflineSpeechActivityDetector.quietRanges(probabilities: probabilities),
            [
                ReadingTurnTimeRange(startMs: 256, endMs: 768),
                ReadingTurnTimeRange(startMs: 1_536, endMs: 1_792),
            ])
        XCTAssertTrue(
            OfflineSpeechActivityDetector.quietRanges(probabilities: Array(repeating: 0.9, count: 1_000)).isEmpty)
        XCTAssertTrue(DiarizationService.offlineConfig(speakerConstraint: nil).exclusiveSegments)
        let config = DiarizationService.offlineConfig(speakerConstraint: nil, preserveActivity: true)
        XCTAssertFalse(config.exclusiveSegments)
        XCTAssertEqual(config.minGapDuration, 0)
    }
}

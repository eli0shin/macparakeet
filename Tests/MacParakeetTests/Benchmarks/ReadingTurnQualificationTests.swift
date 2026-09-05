import Foundation
import XCTest
@testable import MacParakeet
@testable import MacParakeetCore
@testable import MacParakeetViewModels

/// Env-gated qualification for private, consented meeting artifacts.
///
/// The report contains aggregate structure and timing values only. It never
/// writes transcript text, words, participant names, paths, or meeting IDs.
///
///   MACPARAKEET_READING_TURN_QUALIFICATION=1 \
///   MACPARAKEET_READING_TURN_HEADSET_SESSION=/path/to/headset/session \
///   MACPARAKEET_READING_TURN_SPEAKER_SESSION=/path/to/speaker/session \
///   MACPARAKEET_READING_TURN_RESULTS_FILE=/tmp/reading-turn-results.json \
///   swift test --filter ReadingTurnQualificationTests
final class ReadingTurnQualificationTests: XCTestCase {
    private static let enabledKey = "MACPARAKEET_READING_TURN_QUALIFICATION"
    private static let headsetKey = "MACPARAKEET_READING_TURN_HEADSET_SESSION"
    private static let speakerKey = "MACPARAKEET_READING_TURN_SPEAKER_SESSION"
    private static let resultsKey = "MACPARAKEET_READING_TURN_RESULTS_FILE"

    @MainActor
    func testConsentedDualTrackMeetings() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment[Self.enabledKey] == "1",
            "Set \(Self.enabledKey)=1 and supply both consented session paths."
        )

        let fixtures = try await [
            evaluate(mode: "headset", path: requiredPath(Self.headsetKey, environment: environment)),
            evaluate(mode: "speaker", path: requiredPath(Self.speakerKey, environment: environment)),
        ]

        for fixture in fixtures {
            XCTAssertGreaterThan(fixture.durationSeconds, 0)
            XCTAssertGreaterThan(fixture.wordCount, 0)
            XCTAssertTrue(fixture.hasMicrophoneTrack)
            XCTAssertTrue(fixture.hasSystemTrack)
            XCTAssertGreaterThanOrEqual(fixture.remoteSpeakerCount, 2)
        }

        let report = QualificationReport(
            schemaVersion: 1,
            fixtures: fixtures,
            speakerCountRerun: try await exerciseSpeakerCountRerun(
                path: requiredPath(Self.speakerKey, environment: environment),
                expectedRemoteSpeakers: 2
            ),
            oneHour: try measureOneHourProjection(
                from: requiredPath(Self.headsetKey, environment: environment)
            )
        )
        let data = try JSONEncoder.qualification.encode(report)
        if let outputPath = environment[Self.resultsKey], !outputPath.isEmpty {
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
        print("Reading Turn qualification complete: aggregate report generated for \(fixtures.count) fixtures.")
    }

    private func requiredPath(_ key: String, environment: [String: String]) throws -> String {
        guard let path = environment[key], !path.isEmpty else {
            throw QualificationError.missingEnvironment(key)
        }
        return path
    }

    @MainActor
    private func evaluate(mode: String, path: String) async throws -> FixtureReport {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let artifact = try decodeArtifact(in: folder)
        let words = artifact.wordTimestamps ?? []
        let current = currentDocument(
            segments: artifact.transcriptSegments ?? [],
            words: words,
            speakers: artifact.speakers ?? []
        )
        let reading = MeetingTranscriptPresentationBuilder.build(
            transcriptText: artifact.transcript,
            words: words,
            speakers: artifact.speakers,
            diarizationSegments: artifact.diarizationSegments
        )
        let duplicatePhraseCount = duplicateSimultaneousPhrases(in: words)
        try await exerciseConsumers(document: reading, artifact: artifact)

        return FixtureReport(
            mode: mode,
            durationSeconds: Double(artifact.durationMs ?? 0) / 1_000,
            wordCount: words.count,
            remoteSpeakerCount: Set(
                words.compactMap(\.speakerId).filter { $0.hasPrefix("system:S") }
            ).count,
            hasMicrophoneTrack: FileManager.default.fileExists(
                atPath: folder.appendingPathComponent("microphone-raw.m4a").path
            ),
            hasSystemTrack: FileManager.default.fileExists(
                atPath: folder.appendingPathComponent("system-raw.m4a").path
            ),
            current: metrics(
                for: current,
                duplicateSimultaneousPhraseCount: duplicatePhraseCount
            ),
            reading: metrics(
                for: reading,
                duplicateSimultaneousPhraseCount: duplicatePhraseCount
            )
        )
    }

    private func decodeArtifact(in folder: URL) throws -> ArtifactTranscript {
        let url = folder.appendingPathComponent("transcript.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder.qualification.decode(ArtifactTranscript.self, from: data)
    }

    private func currentDocument(
        segments: [TranscriptSegmentRecord],
        words: [WordTimestamp],
        speakers: [SpeakerInfo]
    ) -> MeetingTranscriptPresentationDocument {
        let labels = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.label) })
        let turns = segments.map { segment in
            let start = max(0, min(segment.wordRange.startIndex, words.count))
            let end = max(start, min(segment.wordRange.endIndexExclusive, words.count))
            let references = Array(start..<end)
            let speakerID = segment.speakerId ?? "unknown"
            return ReadingTurn(
                id: ReadingTurnIdentity(
                    source: source(for: speakerID),
                    speakerId: speakerID,
                    firstWordIndex: references.first
                ),
                speakerId: speakerID,
                speakerLabel: labels[speakerID] ?? segment.speakerLabel,
                source: source(for: speakerID),
                timeRange: ReadingTurnTimeRange(startMs: segment.startMs, endMs: segment.endMs),
                paragraphs: [ReadingTurnParagraph(text: segment.text, wordReferences: references)],
                wordReferences: references
            )
        }
        return MeetingTranscriptPresentationDocument(turns: turns)
    }

    private func source(for speakerID: String) -> ReadingTurnSource {
        if speakerID == AudioSource.microphone.rawValue { return .microphone }
        if speakerID == AudioSource.system.rawValue || speakerID.hasPrefix("system:") { return .system }
        return .unknown
    }

    private func metrics(
        for document: MeetingTranscriptPresentationDocument,
        duplicateSimultaneousPhraseCount duplicateCount: Int
    ) -> PresentationMetrics {
        let readability = ReadingTurnReadabilityMetrics.measure(document)
        let durationMinutes = max(1.0 / 60, documentDurationMs(document) / 60_000)
        return PresentationMetrics(
            turnCount: document.turns.count,
            turnsPerMinute: readability.turnsPerMinute,
            blocksShorterThanThreeWords: readability.blocksShorterThanThreeWords,
            isolatedSpeakerFlips: readability.isolatedSpeakerFlips,
            fallbackSpeakerTransitions: readability.fallbackSpeakerTransitions,
            duplicateSimultaneousPhraseCount: duplicateCount,
            duplicateSimultaneousPhrasesPerMinute: Double(duplicateCount) / durationMinutes,
            medianWordsPerTurn: readability.medianWordsPerTurn,
            paragraphsOver120Words: document.turns
                .flatMap(\.paragraphs)
                .count { wordCount($0.text) > 120 }
        )
    }

    /// Counts source-level matching runs of two or more words within 1.5 seconds.
    /// It observes duplicate evidence before presentation, so arbitrary merging
    /// cannot make the Reading Turn score look better.
    private func duplicateSimultaneousPhrases(in words: [WordTimestamp]) -> Int {
        let microphone = indexedWords(words, matching: { $0 == AudioSource.microphone.rawValue })
        let system = indexedWords(
            words,
            matching: {
                $0 == AudioSource.system.rawValue || $0.hasPrefix("system:")
            })
        var count = 0
        for micIndex in microphone.indices {
            for systemIndex in system.indices {
                guard microphone[micIndex].token == system[systemIndex].token,
                    abs(microphone[micIndex].startMs - system[systemIndex].startMs) <= 1_500
                else { continue }
                let hasPrecedingMatch =
                    micIndex > 0 && systemIndex > 0
                    && microphone[micIndex - 1].token == system[systemIndex - 1].token
                    && abs(microphone[micIndex - 1].startMs - system[systemIndex - 1].startMs) <= 1_500
                guard !hasPrecedingMatch else { continue }

                var runLength = 0
                while micIndex + runLength < microphone.count,
                    systemIndex + runLength < system.count,
                    microphone[micIndex + runLength].token == system[systemIndex + runLength].token,
                    abs(microphone[micIndex + runLength].startMs - system[systemIndex + runLength].startMs) <= 1_500
                {
                    runLength += 1
                }
                if runLength >= 2 { count += 1 }
            }
        }
        return count
    }

    private func indexedWords(
        _ words: [WordTimestamp],
        matching: (String) -> Bool
    ) -> [(token: String, startMs: Int)] {
        words.compactMap { word in
            guard let speakerID = word.speakerId, matching(speakerID) else { return nil }
            let token = word.word.lowercased().filter(\.isLetter)
            return token.isEmpty ? nil : (token, word.startMs)
        }
    }

    @MainActor
    private func exerciseConsumers(
        document: MeetingTranscriptPresentationDocument,
        artifact: ArtifactTranscript
    ) async throws {
        guard let firstTurn = document.turns.first,
            let firstReference = firstTurn.wordReferences.first,
            let firstTime = firstTurn.timeRange?.startMs,
            let searchToken = firstTurn.paragraphs.first?.text
                .split(whereSeparator: \.isWhitespace).first
        else { throw QualificationError.emptyFixture }

        XCTAssertNotNil(document.navigationTarget(containingWordReference: firstReference))
        XCTAssertNotNil(document.navigationTarget(containingTimeMs: firstTime))
        XCTAssertTrue(
            document.turns.flatMap(\.paragraphs).contains {
                $0.text.localizedCaseInsensitiveContains(String(searchToken))
            }
        )
        let transcription = makeTranscription(from: artifact)
        let completedDocument = try XCTUnwrap(
            CompletedMeetingReadingDocument.build(
                from: transcription,
                configuration: CompletedMeetingReadingConfiguration()
            )
        )
        XCTAssertEqual(completedDocument, document)

        let blocks = completedDocument.turns.map { turn in
            turn.paragraphs.map(\.text).joined(separator: "\n\n")
        }
        let findModel = TranscriptFindModel()
        findModel.setBlocks(blocks)
        findModel.setQuery(String(searchToken))
        XCTAssertTrue(findModel.hasMatches)

        let exportService = ExportService()
        XCTAssertFalse(exportService.formatForClipboard(transcription: transcription).isEmpty)
        let exportFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("reading-turn-exports-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportFolder) }
        let textURL = exportFolder.appendingPathComponent("meeting.txt")
        let markdownURL = exportFolder.appendingPathComponent("meeting.md")
        try exportService.exportToTxt(transcription: transcription, url: textURL)
        try exportService.exportToMarkdown(transcription: transcription, url: markdownURL)
        XCTAssertGreaterThan(try Data(contentsOf: textURL).count, 0)
        XCTAssertGreaterThan(try Data(contentsOf: markdownURL).count, 0)

        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        try repository.save(transcription)
        if let remoteID = transcription.speakers?.first(where: { $0.id.hasPrefix("system:S") })?.id {
            let renamed = try XCTUnwrap(
                repository.updateSpeakerLabel(
                    id: transcription.id,
                    speakerID: remoteID,
                    label: "Qualified remote speaker"
                )
            )
            let renamedDocument = try XCTUnwrap(
                CompletedMeetingReadingDocument.build(from: renamed)
            )
            XCTAssertTrue(
                renamedDocument.turns.contains { $0.speakerLabel == "Qualified remote speaker" }
            )
        } else {
            XCTFail("A real qualification fixture must contain a remote speaker.")
        }

        let formatting = await Self.exerciseFormatting(completedDocument)
        XCTAssertFalse(formatting.wasCancelled)
        XCTAssertEqual(formatting.formatting.count, document.turns.count)
    }

    nonisolated private static func exerciseFormatting(
        _ document: MeetingTranscriptPresentationDocument
    ) async -> MeetingReadingTurnFormattingResult {
        await MeetingReadingTurnFormatter().format(document) { $0 }
    }

    private func makeTranscription(
        from artifact: ArtifactTranscript,
        meetingArtifactFolderPath: String? = nil
    ) -> Transcription {
        Transcription(
            fileName: "Private qualification meeting",
            meetingArtifactFolderPath: meetingArtifactFolderPath,
            durationMs: artifact.durationMs,
            rawTranscript: artifact.transcript,
            cleanTranscript: artifact.transcript,
            wordTimestamps: artifact.wordTimestamps,
            language: "en",
            speakerCount: artifact.speakers?.count,
            speakers: artifact.speakers,
            diarizationSegments: artifact.diarizationSegments,
            transcriptSegments: artifact.transcriptSegments,
            status: .completed,
            sourceType: .meeting
        )
    }

    private func documentDurationMs(_ document: MeetingTranscriptPresentationDocument) -> Double {
        let starts = document.turns.compactMap { $0.timeRange?.startMs }
        let ends = document.turns.compactMap { $0.timeRange?.endMs }
        return Double(max(1, (ends.max() ?? 0) - (starts.min() ?? 0)))
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    @MainActor
    private func exerciseSpeakerCountRerun(
        path: String,
        expectedRemoteSpeakers: Int
    ) async throws -> SpeakerCountRerunReport {
        let sourceFolder = URL(fileURLWithPath: path, isDirectory: true)
        let artifact = try decodeArtifact(in: sourceFolder)
        let privateWorkFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("reading-turn-rerun-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: sourceFolder, to: privateWorkFolder)
        defer { try? FileManager.default.removeItem(at: privateWorkFolder) }

        let transcription = makeTranscription(
            from: artifact,
            meetingArtifactFolderPath: privateWorkFolder.path
        )
        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        let segmentRepository = SegmentRepository(dbQueue: database.dbQueue)
        try repository.save(transcription)
        let recording = try MeetingRecordingOutput.loadArchived(
            displayName: "Private qualification meeting",
            mixedAudioURL: privateWorkFolder.appendingPathComponent("meeting-playback.m4a"),
            durationSeconds: Double(artifact.durationMs ?? 0) / 1_000
        )
        let service = TranscriptionService(
            audioProcessor: AudioProcessor(),
            sttTranscriber: QualificationSTT(),
            transcriptionRepo: repository,
            segmentRepo: segmentRepository,
            diarizationService: DiarizationService(),
            meetingArtifactStore: nil,
            meetingAutomationHookRunner: nil
        )
        let originalLexicalEvidence = lexicalEvidence(artifact.wordTimestamps ?? [])

        let start = ContinuousClock().now
        let corrected = try await service.correctMeetingSpeakerAttribution(
            existing: transcription,
            recording: recording,
            selection: .exact(totalPeople: expectedRemoteSpeakers + 1)
        )
        let elapsed = milliseconds(start.duration(to: ContinuousClock().now))
        let persisted = try XCTUnwrap(repository.fetch(id: transcription.id))
        let detectedRemoteSpeakers = Set(
            (persisted.wordTimestamps ?? []).compactMap(\.speakerId)
                .filter { $0.hasPrefix("system:S") }
        ).count
        XCTAssertEqual(corrected.id, persisted.id)
        XCTAssertEqual(detectedRemoteSpeakers, expectedRemoteSpeakers)
        XCTAssertEqual(lexicalEvidence(persisted.wordTimestamps ?? []), originalLexicalEvidence)
        XCTAssertNotNil(CompletedMeetingReadingDocument.build(from: persisted))

        return SpeakerCountRerunReport(
            requestedRemoteSpeakers: expectedRemoteSpeakers,
            detectedRemoteSpeakers: detectedRemoteSpeakers,
            elapsedMilliseconds: elapsed
        )
    }

    private func lexicalEvidence(_ words: [WordTimestamp]) -> [LexicalWordEvidence] {
        words.map {
            LexicalWordEvidence(
                word: $0.word,
                startMs: $0.startMs,
                endMs: $0.endMs,
                confidence: $0.confidence
            )
        }
    }

    private func measureOneHourProjection(from path: String) throws -> OneHourReport {
        let artifact = try decodeArtifact(in: URL(fileURLWithPath: path, isDirectory: true))
        let sourceWords = artifact.wordTimestamps ?? []
        guard let sourceEndMs = sourceWords.map(\.endMs).max(), sourceEndMs > 0 else {
            throw QualificationError.emptyFixture
        }

        var projected: [WordTimestamp] = []
        var offset = 0
        while offset < 3_600_000 {
            projected.append(
                contentsOf: sourceWords.map {
                    WordTimestamp(
                        word: $0.word,
                        startMs: $0.startMs + offset,
                        endMs: $0.endMs + offset,
                        confidence: $0.confidence,
                        speakerId: $0.speakerId
                    )
                })
            offset += sourceEndMs + 1
        }
        projected.removeAll { $0.startMs >= 3_600_000 }

        let clock = ContinuousClock()
        let buildStart = clock.now
        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: projected,
            speakers: artifact.speakers,
            diarizationSegments: nil
        )
        let buildMs = milliseconds(buildStart.duration(to: clock.now))

        let interactionStart = clock.now
        _ = MeetingTranscriptDocumentRenderer.plainText(document)
        let identifiedTurns = identifiedReadingTurns(document.turns)
        for turn in document.turns.prefix(200) {
            if let reference = turn.wordReferences.first {
                _ = document.navigationTarget(containingWordReference: reference)
            }
            if let startMs = turn.timeRange?.startMs {
                _ = readingTurnScrollTarget(for: startMs, in: identifiedTurns)
            }
        }
        let paragraphs = document.turns.flatMap(\.paragraphs)
        let searchableText = paragraphs.map(\.text).joined(separator: " ")
        if let searchToken = paragraphs.first?.text.split(whereSeparator: \.isWhitespace).first {
            XCTAssertTrue(searchableText.localizedCaseInsensitiveContains(String(searchToken)))
        }
        let interactionMs = milliseconds(interactionStart.duration(to: clock.now))
        XCTAssertLessThan(buildMs, 1_000)
        XCTAssertLessThan(interactionMs, 1_000)

        return OneHourReport(
            projectedWordCount: projected.count,
            readingTurnCount: document.turns.count,
            scrollAndSelectionUnitCount: identifiedTurns.count,
            buildMilliseconds: buildMs,
            copySearchAndPlaybackTrackingMilliseconds: interactionMs
        )
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

private enum QualificationError: Error {
    case missingEnvironment(String)
    case emptyFixture
    case unexpectedSTTRequest
}

private struct QualificationSTT: STTTranscribing {
    func transcribe(
        audioPath: String,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> STTResult {
        throw QualificationError.unexpectedSTTRequest
    }
}

private struct LexicalWordEvidence: Equatable {
    let word: String
    let startMs: Int
    let endMs: Int
    let confidence: Double
}

private struct ArtifactTranscript: Decodable {
    let durationMs: Int?
    let transcript: String
    let wordTimestamps: [WordTimestamp]?
    let speakers: [SpeakerInfo]?
    let diarizationSegments: [DiarizationSegmentRecord]?
    let transcriptSegments: [TranscriptSegmentRecord]?
}

private struct QualificationReport: Codable {
    let schemaVersion: Int
    let fixtures: [FixtureReport]
    let speakerCountRerun: SpeakerCountRerunReport
    let oneHour: OneHourReport
}

private struct FixtureReport: Codable {
    let mode: String
    let durationSeconds: Double
    let wordCount: Int
    let remoteSpeakerCount: Int
    let hasMicrophoneTrack: Bool
    let hasSystemTrack: Bool
    let current: PresentationMetrics
    let reading: PresentationMetrics
}

private struct PresentationMetrics: Codable {
    let turnCount: Int
    let turnsPerMinute: Double
    let blocksShorterThanThreeWords: Int
    let isolatedSpeakerFlips: Int
    let fallbackSpeakerTransitions: Int
    let duplicateSimultaneousPhraseCount: Int
    let duplicateSimultaneousPhrasesPerMinute: Double
    let medianWordsPerTurn: Double
    let paragraphsOver120Words: Int
}

private struct SpeakerCountRerunReport: Codable {
    let requestedRemoteSpeakers: Int
    let detectedRemoteSpeakers: Int
    let elapsedMilliseconds: Double
}

private struct OneHourReport: Codable {
    let projectedWordCount: Int
    let readingTurnCount: Int
    let scrollAndSelectionUnitCount: Int
    let buildMilliseconds: Double
    let copySearchAndPlaybackTrackingMilliseconds: Double
}

private extension JSONDecoder {
    static var qualification: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var qualification: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

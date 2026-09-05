import XCTest
@testable import MacParakeetCore

final class MeetingSpeakerCountCorrectionTests: XCTestCase {
    func testSelectionsConvertTotalPeopleToRemoteConstraintsAndRejectInvalidInputs() throws {
        XCTAssertNil(try MeetingSpeakerCountSelection.auto.remoteDiarizationConstraint(hasSystemAudio: true))
        XCTAssertEqual(
            try MeetingSpeakerCountSelection.exact(totalPeople: 4)
                .remoteDiarizationConstraint(hasSystemAudio: true),
            .exact(3)
        )
        XCTAssertEqual(
            try MeetingSpeakerCountSelection.bounded(minTotalPeople: 3, maxTotalPeople: 6)
                .remoteDiarizationConstraint(hasSystemAudio: true),
            .range(min: 2, max: 5)
        )
        XCTAssertThrowsError(
            try MeetingSpeakerCountSelection.exact(totalPeople: 1)
                .remoteDiarizationConstraint(hasSystemAudio: true)
        )
        XCTAssertThrowsError(
            try MeetingSpeakerCountSelection.bounded(minTotalPeople: 5, maxTotalPeople: 3)
                .remoteDiarizationConstraint(hasSystemAudio: true)
        )
        XCTAssertThrowsError(
            try MeetingSpeakerCountSelection.auto.remoteDiarizationConstraint(hasSystemAudio: false)
        )
    }

    func testDualSourceExactCorrectionRebuildsSpeakerPresentationWithoutChangingWords() async throws {
        let fixture = try await makeFixture(includeMicrophone: true)
        defer { fixture.cleanup() }

        let originalWords = try XCTUnwrap(fixture.original.wordTimestamps)
        let result = try await fixture.service.correctMeetingSpeakerAttribution(
            existing: fixture.original,
            recording: fixture.recording,
            selection: .exact(totalPeople: 3)
        )

        let constraint = await fixture.diarization.lastSpeakerConstraint
        XCTAssertEqual(constraint, .exact(2))
        XCTAssertEqual(result.rawTranscript, fixture.original.rawTranscript)
        XCTAssertEqual(result.cleanTranscript, fixture.original.cleanTranscript)
        XCTAssertEqual(result.wordTimestamps?.map(\.word), originalWords.map(\.word))
        XCTAssertEqual(result.wordTimestamps?.map(\.startMs), originalWords.map(\.startMs))
        XCTAssertEqual(result.wordTimestamps?.map(\.confidence), originalWords.map(\.confidence))
        XCTAssertEqual(result.wordTimestamps?.map(\.speakerId), ["microphone", "system:S1", "system:S2"])
        XCTAssertEqual(result.speakers?.map(\.label), ["Me", "Others 1", "Others 2"])

        let readingTurns = MeetingTranscriptPresentationBuilder.build(
            transcriptText: result.rawTranscript ?? "",
            words: result.wordTimestamps,
            speakers: result.speakers,
            diarizationSegments: result.diarizationSegments
        )
        XCTAssertEqual(readingTurns.turns.map(\.speakerLabel), ["Me", "Others 1", "Others 2"])
    }

    func testSystemOnlyBoundedCorrectionUsesRemoteBoundsAndCountsMeInUIValue() async throws {
        let fixture = try await makeFixture(includeMicrophone: false)
        defer { fixture.cleanup() }

        let result = try await fixture.service.correctMeetingSpeakerAttribution(
            existing: fixture.original,
            recording: fixture.recording,
            selection: .bounded(minTotalPeople: 2, maxTotalPeople: 4)
        )

        let constraint = await fixture.diarization.lastSpeakerConstraint
        XCTAssertEqual(constraint, .range(min: 1, max: 3))
        XCTAssertEqual(MeetingSpeakerCountSelection.detectedTotalPeople(in: result), 3)
        XCTAssertEqual(result.wordTimestamps?.map(\.speakerId), ["system:S1", "system:S2"])
    }

    func testAutoCorrectionUsesUnconstrainedDiarizationThroughMeetingBoundary() async throws {
        let fixture = try await makeFixture(includeMicrophone: true)
        defer { fixture.cleanup() }

        _ = try await fixture.service.correctMeetingSpeakerAttribution(
            existing: fixture.original,
            recording: fixture.recording,
            selection: .auto
        )

        let constraint = await fixture.diarization.lastSpeakerConstraint
        let convertCallCount = await fixture.audio.convertCallCount
        XCTAssertNil(constraint)
        XCTAssertEqual(convertCallCount, 1)
    }

    func testFailureKeepsLastSuccessfulTranscriptPersisted() async throws {
        let fixture = try await makeFixture(includeMicrophone: true)
        defer { fixture.cleanup() }
        await fixture.diarization.configure(error: STTError.transcriptionFailed("speaker retry failed"))

        do {
            _ = try await fixture.service.correctMeetingSpeakerAttribution(
                existing: fixture.original,
                recording: fixture.recording,
                selection: .auto
            )
            XCTFail("Expected diarization failure")
        } catch {
            let persisted = try XCTUnwrap(fixture.repository.fetch(id: fixture.original.id))
            XCTAssertEqual(persisted.rawTranscript, fixture.original.rawTranscript)
            XCTAssertEqual(persisted.wordTimestamps, fixture.original.wordTimestamps)
            XCTAssertEqual(persisted.speakers, fixture.original.speakers)
        }
    }

    func testCancellationKeepsLastSuccessfulTranscriptPersisted() async throws {
        let fixture = try await makeFixture(includeMicrophone: true)
        defer { fixture.cleanup() }
        await fixture.diarization.configureDiarizeDelay(.seconds(2))

        let task = Task {
            try await fixture.service.correctMeetingSpeakerAttribution(
                existing: fixture.original,
                recording: fixture.recording,
                selection: .auto
            )
        }
        while !(await fixture.diarization.diarizeCalled) {
            await Task.yield()
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            let persisted = try XCTUnwrap(fixture.repository.fetch(id: fixture.original.id))
            XCTAssertEqual(persisted.rawTranscript, fixture.original.rawTranscript)
            XCTAssertEqual(persisted.wordTimestamps, fixture.original.wordTimestamps)
            XCTAssertEqual(persisted.speakers, fixture.original.speakers)
        }
    }

    func testMicrophoneOnlyMeetingIsRejectedBeforeAudioProcessing() async throws {
        let fixture = try await makeFixture(includeMicrophone: true, includeSystem: false)
        defer { fixture.cleanup() }

        do {
            _ = try await fixture.service.correctMeetingSpeakerAttribution(
                existing: fixture.original,
                recording: fixture.recording,
                selection: .auto
            )
            XCTFail("Expected microphone-only correction to fail")
        } catch let error as MeetingSpeakerCountCorrectionError {
            XCTAssertEqual(error, .systemAudioUnavailable)
        }

        let convertCallCount = await fixture.audio.convertCallCount
        let diarizeCalled = await fixture.diarization.diarizeCalled
        XCTAssertEqual(convertCallCount, 0)
        XCTAssertFalse(diarizeCalled)
    }

    private func makeFixture(
        includeMicrophone: Bool,
        includeSystem: Bool = true
    ) async throws -> Fixture {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let mixedURL = folder.appendingPathComponent("meeting-playback.m4a")
        let microphoneURL = folder.appendingPathComponent("microphone-raw.m4a")
        let systemURL = folder.appendingPathComponent("system-raw.m4a")
        FileManager.default.createFile(atPath: mixedURL.path, contents: Data("mixed".utf8))
        FileManager.default.createFile(atPath: microphoneURL.path, contents: Data("mic".utf8))
        FileManager.default.createFile(atPath: systemURL.path, contents: Data("system".utf8))

        let microphoneTrack: MeetingSourceAlignment.Track? =
            includeMicrophone
            ? .init(
                firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0, writtenFrameCount: 48_000, sampleRate: 48_000)
            : nil
        let systemTrack: MeetingSourceAlignment.Track? =
            includeSystem
            ? .init(
                firstHostTime: nil, lastHostTime: nil, startOffsetMs: includeMicrophone ? 1_000 : 0,
                writtenFrameCount: 48_000, sampleRate: 48_000)
            : nil
        let recording = MeetingRecordingOutput(
            sessionID: UUID(),
            displayName: "Speaker correction",
            folderURL: folder,
            mixedAudioURL: mixedURL,
            microphoneAudioURL: microphoneURL,
            systemAudioURL: systemURL,
            durationSeconds: 3,
            sourceAlignment: MeetingSourceAlignment(
                meetingOriginHostTime: nil,
                microphone: microphoneTrack,
                system: systemTrack
            )
        )

        var words: [WordTimestamp] = []
        if includeMicrophone {
            words.append(
                WordTimestamp(word: "Hello", startMs: 0, endMs: 300, confidence: 0.91, speakerId: "microphone"))
        }
        if includeSystem {
            let offset = includeMicrophone ? 1_000 : 0
            words.append(
                WordTimestamp(
                    word: "Remote.", startMs: offset, endMs: offset + 300, confidence: 0.82, speakerId: "system:S9"))
            words.append(
                WordTimestamp(
                    word: "Reply.", startMs: offset + 500, endMs: offset + 800, confidence: 0.83, speakerId: "system:S9"
                ))
        }
        let original = Transcription(
            fileName: "Speaker correction",
            filePath: mixedURL.path,
            rawTranscript: words.map(\.word).joined(separator: " "),
            cleanTranscript: "Displayed text stays unchanged.",
            wordTimestamps: words,
            speakerCount: includeMicrophone ? 2 : 1,
            speakers: includeMicrophone
                ? [SpeakerInfo(id: "microphone", label: "Me"), SpeakerInfo(id: "system:S9", label: "Others 1")]
                : [SpeakerInfo(id: "system:S9", label: "Others 1")],
            status: .completed,
            sourceType: .meeting
        )

        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        let segmentRepository = SegmentRepository(dbQueue: database.dbQueue)
        try repository.save(original)
        let audio = MockAudioProcessor()
        let diarization = MockDiarizationService()
        await diarization.configure(
            result: MacParakeetDiarizationResult(
                segments: [
                    SpeakerSegment(speakerId: "S1", startMs: 0, endMs: 350),
                    SpeakerSegment(speakerId: "S2", startMs: 450, endMs: 900),
                ],
                speakerCount: 2,
                speakers: [
                    SpeakerInfo(id: "S1", label: "Speaker 1"),
                    SpeakerInfo(id: "S2", label: "Speaker 2"),
                ]
            ))
        let service = TranscriptionService(
            audioProcessor: audio,
            sttTranscriber: MockSTTClient(),
            transcriptionRepo: repository,
            segmentRepo: segmentRepository,
            diarizationService: diarization
        )
        return Fixture(
            folder: folder,
            database: database,
            audio: audio,
            diarization: diarization,
            repository: repository,
            service: service,
            recording: recording,
            original: original
        )
    }

}

private struct Fixture {
    let folder: URL
    // Keep the in-memory database alive for the service and repositories.
    let database: DatabaseManager
    let audio: MockAudioProcessor
    let diarization: MockDiarizationService
    let repository: TranscriptionRepository
    let service: TranscriptionService
    let recording: MeetingRecordingOutput
    let original: Transcription

    func cleanup() {
        try? FileManager.default.removeItem(at: folder)
    }
}

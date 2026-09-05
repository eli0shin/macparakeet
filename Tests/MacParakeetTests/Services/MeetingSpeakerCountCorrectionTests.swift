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

    func testCorrectionPreservesUserEditsMadeWhileDiarizationRuns() async throws {
        let fixture = try await makeFixture(includeMicrophone: true)
        defer { fixture.cleanup() }
        await fixture.diarization.configureDiarizeDelay(.seconds(1))

        let task = Task {
            try await fixture.service.correctMeetingSpeakerAttribution(
                existing: fixture.original,
                recording: fixture.recording,
                selection: .exact(totalPeople: 3)
            )
        }
        while !(await fixture.diarization.diarizeCalled) {
            await Task.yield()
        }

        var userEdited = try XCTUnwrap(fixture.repository.fetch(id: fixture.original.id))
        userEdited.fileName = "Renamed during correction"
        userEdited.cleanTranscript = "Transcript edited during correction."
        userEdited.isTranscriptEdited = true
        userEdited.userNotes = "Notes added during correction."
        userEdited.isFavorite = true
        try fixture.repository.save(userEdited)

        let result = try await task.value
        let persisted = try XCTUnwrap(fixture.repository.fetch(id: fixture.original.id))
        for corrected in [result, persisted] {
            XCTAssertEqual(corrected.fileName, "Renamed during correction")
            XCTAssertEqual(corrected.cleanTranscript, "Transcript edited during correction.")
            XCTAssertTrue(corrected.isTranscriptEdited)
            XCTAssertEqual(corrected.userNotes, "Notes added during correction.")
            XCTAssertTrue(corrected.isFavorite)
            XCTAssertEqual(corrected.wordTimestamps?.map(\.speakerId), ["microphone", "system:S1", "system:S2"])
        }
    }

    func testCorrectionRejectsCommitWhenRetranscriptionReplacesCanonicalWords() async throws {
        let fixture = try await makeFixture(includeMicrophone: true)
        defer { fixture.cleanup() }
        await fixture.diarization.configureDiarizeDelay(.seconds(1))

        let correction = Task {
            try await fixture.service.correctMeetingSpeakerAttribution(
                existing: fixture.original,
                recording: fixture.recording,
                selection: .exact(totalPeople: 3)
            )
        }
        while !(await fixture.diarization.diarizeCalled) {
            await Task.yield()
        }

        var retranscribed = try XCTUnwrap(fixture.repository.fetch(id: fixture.original.id))
        retranscribed.rawTranscript = "Replacement words."
        retranscribed.cleanTranscript = nil
        retranscribed.wordTimestamps = [
            WordTimestamp(
                word: "Replacement", startMs: 0, endMs: 400, confidence: 0.97,
                speakerId: AudioSource.microphone.rawValue
            ),
            WordTimestamp(
                word: "words.", startMs: 450, endMs: 800, confidence: 0.96,
                speakerId: AudioSource.microphone.rawValue
            ),
        ]
        retranscribed.speakers = [SpeakerInfo(id: AudioSource.microphone.rawValue, label: "Me")]
        retranscribed.speakerCount = 1
        retranscribed.diarizationSegments = nil
        retranscribed.transcriptSegments = nil
        try fixture.repository.save(retranscribed)

        do {
            _ = try await correction.value
            XCTFail("Expected stale correction to be rejected")
        } catch let error as MeetingSpeakerCountCorrectionError {
            XCTAssertEqual(error, .canonicalWordsChanged)
        }

        let persisted = try XCTUnwrap(fixture.repository.fetch(id: fixture.original.id))
        XCTAssertEqual(persisted.rawTranscript, retranscribed.rawTranscript)
        XCTAssertEqual(persisted.wordTimestamps, retranscribed.wordTimestamps)
        XCTAssertEqual(persisted.speakers, retranscribed.speakers)
        XCTAssertEqual(persisted.speakerCount, retranscribed.speakerCount)
    }

    func testCorrectionPreservesConcurrentSpeakerRenameWhenIdentityRemains() async throws {
        let fixture = try await makeFixture(includeMicrophone: true)
        defer { fixture.cleanup() }
        await fixture.diarization.configure(
            result: MacParakeetDiarizationResult(
                segments: [SpeakerSegment(speakerId: "S9", startMs: 0, endMs: 900)],
                speakerCount: 1,
                speakers: [SpeakerInfo(id: "S9", label: "Speaker 1")]
            )
        )
        await fixture.diarization.configureDiarizeDelay(.seconds(1))

        let task = Task {
            try await fixture.service.correctMeetingSpeakerAttribution(
                existing: fixture.original,
                recording: fixture.recording,
                selection: .exact(totalPeople: 2)
            )
        }
        while !(await fixture.diarization.diarizeCalled) {
            await Task.yield()
        }
        _ = try fixture.repository.updateSpeakerLabel(
            id: fixture.original.id,
            speakerID: "system:S9",
            label: "Client"
        )

        let result = try await task.value
        XCTAssertEqual(result.speakers?.first(where: { $0.id == "system:S9" })?.label, "Client")
        XCTAssertEqual(result.wordTimestamps?.map(\.speakerId), ["microphone", "system:S9", "system:S9"])
    }

    func testLateTranscriptEditCannotRestoreOldAttribution() async throws {
        let fixture = try await makeFixture(includeMicrophone: true)
        defer { fixture.cleanup() }
        let corrected = try await fixture.service.correctMeetingSpeakerAttribution(
            existing: fixture.original,
            recording: fixture.recording,
            selection: .exact(totalPeople: 3)
        )

        let afterEdit = try XCTUnwrap(
            fixture.repository.updateTranscriptText(
                id: fixture.original.id,
                cleanTranscript: "Edited after correction.",
                isTranscriptEdited: true
            )
        )

        XCTAssertEqual(afterEdit.cleanTranscript, "Edited after correction.")
        XCTAssertTrue(afterEdit.isTranscriptEdited)
        XCTAssertEqual(afterEdit.speakers, corrected.speakers)
        XCTAssertEqual(afterEdit.wordTimestamps, corrected.wordTimestamps)
    }

    func testLateRenameForReplacedIdentityCannotRestoreOldRoster() async throws {
        let fixture = try await makeFixture(includeMicrophone: true)
        defer { fixture.cleanup() }
        let corrected = try await fixture.service.correctMeetingSpeakerAttribution(
            existing: fixture.original,
            recording: fixture.recording,
            selection: .exact(totalPeople: 3)
        )

        let afterStaleRename = try XCTUnwrap(
            fixture.repository.updateSpeakerLabel(
                id: fixture.original.id,
                speakerID: "system:S9",
                label: "Stale rename"
            )
        )

        XCTAssertEqual(afterStaleRename.speakers, corrected.speakers)
        XCTAssertEqual(afterStaleRename.wordTimestamps, corrected.wordTimestamps)
    }

    func testPostCommitSearchRefreshFailureReturnsCorrectionAndRemovesStaleSegments() async throws {
        let fixture = try await makeFixture(
            includeMicrophone: true,
            knowledgeLayerMutator: ThrowingKnowledgeLayerMutator()
        )
        defer { fixture.cleanup() }
        try fixture.segmentRepository.replaceSegments(for: fixture.original)
        XCTAssertFalse(try fixture.segmentRepository.fetch(transcriptionId: fixture.original.id).isEmpty)

        let result = try await fixture.service.correctMeetingSpeakerAttribution(
            existing: fixture.original,
            recording: fixture.recording,
            selection: .exact(totalPeople: 3)
        )

        XCTAssertEqual(result.wordTimestamps?.map(\.speakerId), ["microphone", "system:S1", "system:S2"])
        let persisted = try XCTUnwrap(fixture.repository.fetch(id: fixture.original.id))
        XCTAssertEqual(persisted.wordTimestamps, result.wordTimestamps)
        XCTAssertTrue(try fixture.segmentRepository.fetch(transcriptionId: fixture.original.id).isEmpty)
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
        includeSystem: Bool = true,
        knowledgeLayerMutator: KnowledgeLayerMutating? = nil
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
            knowledgeLayerMutator: knowledgeLayerMutator,
            diarizationService: diarization
        )
        return Fixture(
            folder: folder,
            database: database,
            audio: audio,
            diarization: diarization,
            repository: repository,
            segmentRepository: segmentRepository,
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
    let segmentRepository: SegmentRepository
    let service: TranscriptionService
    let recording: MeetingRecordingOutput
    let original: Transcription

    func cleanup() {
        try? FileManager.default.removeItem(at: folder)
    }
}

private struct ThrowingKnowledgeLayerMutator: KnowledgeLayerMutating {
    func replaceSegmentsAndInvalidateCard(for transcription: Transcription) throws {
        throw TestError.refreshFailed
    }

    private enum TestError: Error {
        case refreshFailed
    }
}

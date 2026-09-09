import XCTest
@testable import MacParakeetCore

final class MicrophoneSpeakerDetectionTests: XCTestCase {
    func testMicrophoneOnlyFinalizationPersistsTwoLocalSpeakersAndReadingTurns() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        let result = try await fixture.service.transcribeMeeting(recording: fixture.recording)
        XCTAssertEqual(result.wordTimestamps?.map(\.speakerId), ["microphone:S1", "microphone:S2"])
        XCTAssertEqual(result.wordTimestamps?.map(\.startMs), [300, 3300])
        XCTAssertEqual(result.speakers?.map(\.label), ["Local Speaker 1", "Local Speaker 2"])
        XCTAssertEqual(result.diarizationSegments?.map(\.startMs), [300, 3300])
        XCTAssertEqual(result.speakerCount, 2)
        let saved = try XCTUnwrap(fixture.repository.fetch(id: result.id))
        XCTAssertEqual(saved.wordTimestamps, result.wordTimestamps)
        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: saved.rawTranscript ?? "", words: saved.wordTimestamps,
            speakers: saved.speakers, diarizationSegments: saved.diarizationSegments
        )
        XCTAssertEqual(document.turns.map(\.source), [.microphone, .microphone])
        XCTAssertEqual(document.turns.map(\.speakerLabel), ["Local Speaker 1", "Local Speaker 2"])
        XCTAssertEqual(MeetingSpeakerCountSelection.detectedTotalPeople(in: saved), 2)
    }

    func testCombinedCaptureKeepsLocalAndRemoteSpeakerNamespacesSeparate() async throws {
        let fixture = try await makeFixture(system: true)
        defer { fixture.cleanup() }
        let result = try await fixture.service.transcribeMeeting(recording: fixture.recording)
        XCTAssertEqual(
            Set(result.speakers?.map(\.id) ?? []), ["microphone:S1", "microphone:S2", "system:S1", "system:S2"])
        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: result.rawTranscript ?? "", words: result.wordTimestamps,
            speakers: result.speakers, diarizationSegments: result.diarizationSegments
        )
        XCTAssertEqual(
            Set(document.turns.filter { $0.source == .microphone }.map(\.speakerLabel)),
            ["Local Speaker 1", "Local Speaker 2"])
        XCTAssertEqual(
            Set(document.turns.filter { $0.source == .system }.map(\.speakerLabel)), ["Others 1", "Others 2"])
    }

    func testDisabledSettingKeepsMeAndDoesNotDiarizeMicrophone() async throws {
        let fixture = try await makeFixture(enabled: false)
        defer { fixture.cleanup() }
        let result = try await fixture.service.transcribeMeeting(recording: fixture.recording)
        let called = await fixture.diarization.diarizeCalled
        XCTAssertFalse(called)
        XCTAssertEqual(result.speakers?.map(\.label), ["Me"])
        XCTAssertEqual(result.wordTimestamps?.map(\.speakerId), ["microphone", "microphone"])
    }

    func testCapturedSystemChoiceOverridesChangedGlobalDefaultDuringFinalization() async throws {
        let fixture = try await makeFixture(system: true)
        defer { fixture.cleanup() }
        let recording = fixture.recording.withSpeakerDetection(
            systemAudio: false,
            microphone: true
        )

        let result = try await fixture.service.transcribeMeeting(recording: recording)

        XCTAssertEqual(
            Set(result.speakers?.map(\.id) ?? []),
            ["microphone:S1", "microphone:S2", "system"]
        )
        XCTAssertFalse(result.speakers?.contains { $0.id.hasPrefix("system:") } ?? true)
    }

    func testDetectionFailureKeepsTranscriptWithNeutralLocalFallback() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        await fixture.diarization.configure(error: STTError.transcriptionFailed("test"))
        let result = try await fixture.service.transcribeMeeting(recording: fixture.recording)
        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(result.rawTranscript, "Hello. Welcome.")
        XCTAssertEqual(result.speakers?.map(\.label), ["Local Speakers"])
    }

    func testEmptyDetectionKeepsNeutralFallback() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        await fixture.diarization.configure(
            result: MacParakeetDiarizationResult(segments: [], speakerCount: 0, speakers: []))
        let result = try await fixture.service.transcribeMeeting(recording: fixture.recording)
        XCTAssertEqual(result.speakers?.map(\.label), ["Local Speakers"])
    }

    func testUntimedMicrophoneTranscriptSkipsDiarization() async throws {
        let fixture = try await makeFixture(timed: false)
        defer { fixture.cleanup() }
        let result = try await fixture.service.transcribeMeeting(recording: fixture.recording)
        let called = await fixture.diarization.diarizeCalled
        XCTAssertFalse(called)
        XCTAssertEqual(result.rawTranscript, "Hello. Welcome.")
        XCTAssertTrue(result.speakers?.isEmpty ?? true)
    }

    func testCancellationDuringMicrophoneDiarizationDoesNotCompleteTranscript() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        await fixture.diarization.configureDiarizeDelay(.seconds(30))
        let task = Task { try await fixture.service.transcribeMeeting(recording: fixture.recording) }
        while !(await fixture.diarization.diarizeCalled) { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
    }

    func testMicrophoneCorrectionCountsOnlyLocalPeopleAndPreservesRemoteEvidence() async throws {
        let fixture = try await makeFixture(system: true)
        defer { fixture.cleanup() }
        let original = try await fixture.service.transcribeMeeting(recording: fixture.recording)
        let result = try await fixture.service.correctMeetingSpeakerAttribution(
            existing: original, recording: fixture.recording, selection: .microphone(.exact(totalPeople: 2))
        )
        let constraint = await fixture.diarization.lastSpeakerConstraint
        XCTAssertEqual(constraint, .exact(2))
        XCTAssertEqual(result.wordTimestamps, original.wordTimestamps)
        XCTAssertEqual(result.diarizationSegments, original.diarizationSegments)
        XCTAssertEqual(
            result.speakers?.filter { $0.id.hasPrefix("system:") },
            original.speakers?.filter { $0.id.hasPrefix("system:") })
        XCTAssertEqual(
            try MeetingSpeakerCountSelection.exact(totalPeople: 1).constraint(for: fixture.recording), .exact(1))
        XCTAssertThrowsError(
            try MeetingSpeakerCountSelection.microphone(.exact(totalPeople: 0)).constraint(for: fixture.recording))
    }

    func testMicrophoneOnlyCorrectionAcceptsOnePerson() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        let original = try await fixture.service.transcribeMeeting(recording: fixture.recording)
        _ = try await fixture.service.correctMeetingSpeakerAttribution(
            existing: original, recording: fixture.recording, selection: .microphone(.exact(totalPeople: 1))
        )
        let constraint = await fixture.diarization.lastSpeakerConstraint
        XCTAssertEqual(constraint, .exact(1))
    }

    func testMetadataLockAndArchivePreserveSettingAndLegacyDefaultsOff() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        let metadata = MeetingRecordingMetadata(
            sourceAlignment: fixture.recording.sourceAlignment,
            systemSpeakerDetection: false,
            microphoneSpeakerDetection: true
        )
        try MeetingRecordingMetadataStore.save(metadata, folderURL: fixture.recording.folderURL)
        let archived = try MeetingRecordingOutput.loadArchived(
            displayName: "Room", mixedAudioURL: fixture.recording.mixedAudioURL, durationSeconds: 5
        )
        XCTAssertEqual(archived.systemSpeakerDetection, false)
        XCTAssertTrue(archived.microphoneSpeakerDetection)
        let updated = metadata.withCaptureReport(nil).withEchoSuppression(.init(reasonCode: .rawMissingSystemReference))
        XCTAssertEqual(updated.systemSpeakerDetection, false)
        XCTAssertTrue(updated.microphoneSpeakerDetection)
        let lock = MeetingRecordingLockFile(sessionId: UUID(), startedAt: Date(), displayName: "Room")
            .withSpeakerDetection(systemAudio: false, microphone: true)
            .withNotes("Notes").withState(.awaitingTranscription).withFolderURL(fixture.recording.folderURL)
            .withFinalizationOwner(pid: 123, leaseID: UUID())
        let decodedLock = try JSONDecoder().decode(
            MeetingRecordingLockFile.self,
            from: JSONEncoder().encode(lock)
        )
        XCTAssertEqual(decodedLock.systemSpeakerDetection, false)
        XCTAssertTrue(decodedLock.microphoneSpeakerDetection)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any])
        json.removeValue(forKey: "systemSpeakerDetection")
        json.removeValue(forKey: "microphoneSpeakerDetection")
        let legacy = try JSONDecoder().decode(
            MeetingRecordingMetadata.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.systemSpeakerDetection)
        XCTAssertFalse(legacy.microphoneSpeakerDetection)
    }

    func testCleanedMicrophoneIsUsedWhenDetectionIsEnabled() async throws {
        let fixture = try await makeFixture(system: true, cleaned: true)
        defer { fixture.cleanup() }
        let result = try await fixture.service.transcribeMeeting(recording: fixture.recording)
        let converted = await fixture.audio.convertURLs
        XCTAssertEqual(converted.first, fixture.recording.cleanedMicrophoneAudioURL)
        XCTAssertEqual(
            Set(result.speakers?.filter { $0.id.hasPrefix("microphone:") }.map(\.label) ?? []),
            ["Local Speaker 1", "Local Speaker 2"])
    }

    func testSystemCorrectionPreservesRenamedLocalSpeakersAndTheirEvidence() async throws {
        let fixture = try await makeFixture(system: true)
        defer { fixture.cleanup() }
        var original = try await fixture.service.transcribeMeeting(recording: fixture.recording)
        original.speakers = original.speakers?.map {
            $0.id == "microphone:S1" ? SpeakerInfo(id: $0.id, label: "Alex") : $0
        }
        try fixture.repository.save(original)
        let result = try await fixture.service.correctMeetingSpeakerAttribution(
            existing: original, recording: fixture.recording, selection: .exact(totalPeople: 2)
        )
        let constraint = await fixture.diarization.lastSpeakerConstraint
        XCTAssertEqual(constraint, .exact(2))
        XCTAssertEqual(result.speakers?.first { $0.id == "microphone:S1" }?.label, "Alex")
        XCTAssertEqual(result.diarizationSegments, original.diarizationSegments)
        XCTAssertEqual(result.wordTimestamps, original.wordTimestamps)
    }

    private func makeFixture(enabled: Bool = true, system: Bool = false, timed: Bool = true, cleaned: Bool = false)
        async throws
        -> MicrophoneFixture
    {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["meeting-playback.m4a", "microphone-raw.m4a", "system-raw.m4a"] {
            try Data("fixture".utf8).write(to: folder.appendingPathComponent(name))
        }
        let cleanedURL = cleaned ? folder.appendingPathComponent("microphone-cleaned.m4a") : nil
        if let cleanedURL {
            try await MeetingCleanedMicRenderer.encodeMonoFloat(
                [Float](repeating: 0.05, count: 80_000), sampleRate: 16_000, to: cleanedURL, fileManager: .default
            )
        }
        let track = MeetingSourceAlignment.Track(
            firstHostTime: nil, lastHostTime: nil, startOffsetMs: 300, writtenFrameCount: 80000, sampleRate: 16000)
        let recording = MeetingRecordingOutput(
            sessionID: UUID(), displayName: "Room", folderURL: folder,
            mixedAudioURL: folder.appendingPathComponent("meeting-playback.m4a"),
            microphoneAudioURL: folder.appendingPathComponent("microphone-raw.m4a"),
            systemAudioURL: folder.appendingPathComponent("system-raw.m4a"),
            cleanedMicrophoneAudioURL: cleanedURL, durationSeconds: 5,
            sourceAlignment: .init(meetingOriginHostTime: nil, microphone: track, system: system ? track : nil)
        ).withMicrophoneSpeakerDetection(enabled)
        let database = try DatabaseManager()
        let repository = TranscriptionRepository(dbQueue: database.dbQueue)
        let stt = MockSTTClient()
        await stt.configureSequence(results: [
            STTResult(
                text: "Hello. Welcome.",
                words: timed
                    ? [
                        TimestampedWord(word: "Hello.", startMs: 0, endMs: 1500, confidence: 0.9),
                        TimestampedWord(word: "Welcome.", startMs: 3000, endMs: 4500, confidence: 0.9),
                    ] : []),
            STTResult(
                text: "Remote. Reply.",
                words: [
                    TimestampedWord(word: "Remote.", startMs: 0, endMs: 1500, confidence: 0.9),
                    TimestampedWord(word: "Reply.", startMs: 3000, endMs: 4500, confidence: 0.9),
                ]),
        ])
        let diarization = MockDiarizationService()
        await diarization.configure(
            result: MacParakeetDiarizationResult(
                segments: [
                    SpeakerSegment(speakerId: "S1", startMs: 0, endMs: 1500),
                    SpeakerSegment(speakerId: "S2", startMs: 3000, endMs: 4500),
                ],
                speakerCount: 2, speakers: [SpeakerInfo(id: "S1", label: "One"), SpeakerInfo(id: "S2", label: "Two")]
            ))
        let audio = MockAudioProcessor()
        let service = TranscriptionService(
            audioProcessor: audio, sttTranscriber: stt, transcriptionRepo: repository,
            shouldDiarizeMeetings: { system }, diarizationService: diarization)
        return MicrophoneFixture(
            recording: recording, repository: repository, service: service, diarization: diarization, audio: audio)
    }
}

private struct MicrophoneFixture {
    let recording: MeetingRecordingOutput
    let repository: TranscriptionRepository
    let service: TranscriptionService
    let diarization: MockDiarizationService
    let audio: MockAudioProcessor
    func cleanup() { try? FileManager.default.removeItem(at: recording.folderURL) }
}

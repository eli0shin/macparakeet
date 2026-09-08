import Foundation
import XCTest
@testable import MacParakeetCore

/// Logic and lifecycle tests only. No audio files or model assets are encoded.
final class MeetingResidualEchoSuppressionTests: XCTestCase {
    func testPreferencesDefaultAndLiveChanges() throws {
        let name = "meeting-echo-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(MeetingResidualEchoSuppression.current(defaults: defaults), .standard)
        defaults.set(-55.0, forKey: MeetingResidualEchoSuppression.thresholdKey)
        defaults.set(false, forKey: MeetingResidualEchoSuppression.enabledKey)
        XCTAssertEqual(
            MeetingResidualEchoSuppression.current(defaults: defaults),
            .init(enabled: false, thresholdDBFS: -55))
    }

    func testOnlyDAFModelsOwnReferenceAlignment() {
        XCTAssertTrue(
            MeetingEchoSuppressionFactory.usesInternalReferenceAlignment(
                modelName: MeetingEchoSuppressionFactory.defaultModelName))
        XCTAssertFalse(
            MeetingEchoSuppressionFactory.usesInternalReferenceAlignment(
                modelName: MeetingEchoSuppressionFactory.legacyJointModelName))
    }

    func testThresholdIsBoundedAndRejectsNonfiniteValues() {
        XCTAssertEqual(MeetingResidualEchoSuppression(enabled: true, thresholdDBFS: .nan), .standard)
        XCTAssertEqual(MeetingResidualEchoSuppression(enabled: true, thresholdDBFS: 20).thresholdDBFS, -30)
        XCTAssertEqual(MeetingResidualEchoSuppression(enabled: true, thresholdDBFS: -100).thresholdDBFS, -65)
    }

    func testGateUsesHopRMSAndOffPreservesSamples() {
        var residual: [Float] = [0.001, -0.001, 0.001, -0.001]
        MeetingResidualEchoSuppression.standard.apply(to: &residual)
        XCTAssertEqual(residual, [0, 0, 0, 0])
        var speech: [Float] = [0.1, -0.1, 0.1, -0.1]
        MeetingResidualEchoSuppression.standard.apply(to: &speech)
        XCTAssertEqual(speech, [0.1, -0.1, 0.1, -0.1])
        var quiet: [Float] = [0.001, -0.001]
        MeetingResidualEchoSuppression(enabled: false, thresholdDBFS: -45).apply(to: &quiet)
        XCTAssertEqual(quiet, [0.001, -0.001])
    }

    func testDigitalMuteGapResetsProcessorWithoutDroppingIncomingSamples() {
        let processor = CountingProcessor()
        let conditioner = StreamingMeetingEchoSuppressor(processor: processor, handlesMicrophoneGaps: true)
        _ = conditioner.condition(microphone: Array(repeating: 0, count: 12), speaker: Array(repeating: 1, count: 12))
        XCTAssertEqual(processor.resets, 0)
        let result = conditioner.condition(microphone: [0.2, 0.3, 0.4, 0.5], speaker: [1, 1, 1, 1])
        XCTAssertEqual(processor.resets, 1)
        XCTAssertEqual(result, [0.2, 0.3, 0.4, 0.5])
        XCTAssertEqual(conditioner.diagnostics.processedFrames, 4)
    }

    func testBriefSilenceDoesNotResetAndOtherModelsKeepExistingPolicy() {
        let processor = CountingProcessor()
        let conditioner = StreamingMeetingEchoSuppressor(processor: processor, handlesMicrophoneGaps: true)
        _ = conditioner.condition(microphone: [0, 0, 0, 0, 0.1, 0.1, 0.1, 0.1], speaker: Array(repeating: 1, count: 8))
        XCTAssertEqual(processor.resets, 0)
        let legacy = StreamingMeetingEchoSuppressor(processor: processor)
        _ = legacy.condition(
            microphone: Array(repeating: 0, count: 16) + [1, 1, 1, 1], speaker: Array(repeating: 1, count: 20))
        XCTAssertEqual(processor.resets, 0)
    }

    func testPrimingIsBoundedAndDoesNotConsumeTranscriptTimeline() throws {
        let processor = CountingProcessor()
        let conditioner = StreamingMeetingEchoSuppressor(processor: processor, handlesMicrophoneGaps: true)
        try conditioner.prime(microphone: Array(repeating: 0.1, count: 120), speaker: Array(repeating: 1, count: 120))
        XCTAssertEqual(processor.processed, 16, "8 seconds at 8 Hz, in four-sample hops")
        XCTAssertEqual(conditioner.diagnostics.processedFrames, 0)
        let output = conditioner.condition(microphone: [0.1, 0.2, 0.3, 0.4], speaker: [1, 2, 3, 4])
        XCTAssertEqual(output, [0.1, 0.2, 0.3, 0.4])
        XCTAssertEqual(processor.lastReference, [1, 2, 3, 4])
        XCTAssertEqual(conditioner.diagnostics.processedFrames, 1)
    }

    func testLiveAcquisitionBuffersAndReplaysEverySampleInOrder() {
        let processor = CountingProcessor()
        let conditioner = StreamingMeetingEchoSuppressor(
            processor: processor, handlesMicrophoneGaps: true, buffersAcquisition: true)
        let first = Array(repeating: Float(0.1), count: 60)
        XCTAssertTrue(conditioner.condition(microphone: first, speaker: first).isEmpty)
        XCTAssertEqual(processor.processed, 0)
        let last: [Float] = [0.2, 0.3, 0.4, 0.5]
        let output = conditioner.condition(microphone: last, speaker: last)
        XCTAssertEqual(output, first + last)
        XCTAssertEqual(processor.processed, 32, "16 acquisition hops, then the same 16 output hops")
        XCTAssertEqual(conditioner.diagnostics.processedFrames, 16)
        XCTAssertEqual(processor.lastReference, last)
    }

    @MainActor
    func testBufferedPreviewUsesEmittedSpeechLevelInsteadOfSilence() async throws {
        let orchestrator = CaptureOrchestrator()
        let conditioner = StreamingMeetingEchoSuppressor(
            processor: CountingProcessor(sampleRate: 16_000, frameSize: 256),
            handlesMicrophoneGaps: true, buffersAcquisition: true)
        var chunks: [CaptureOrchestratorChunk] = []
        for cycle in 0..<16 {
            _ = await orchestrator.ingest(
                samples: Array(repeating: 0.1, count: 8_000), source: .microphone,
                hostTime: nil, micConditioner: conditioner)
            let output = await orchestrator.ingest(
                samples: Array(repeating: 0.5, count: 8_000), source: .system,
                hostTime: nil, micConditioner: conditioner)
            chunks += output.chunks
            if cycle < 15 {
                XCTAssertTrue(output.pairMetadata.allSatisfy { $0.processedMicrophoneRms == nil })
                XCTAssertFalse(output.chunks.contains { $0.source == .microphone })
            }
        }
        chunks += await orchestrator.flushChunkers()
        let microphoneChunks = chunks.filter { $0.source == .microphone }
        XCTAssertEqual(microphoneChunks.first?.chunk.startMs, 0)
        XCTAssertEqual(microphoneChunks.map { $0.chunk.startMs }, [0, 4_000])
        XCTAssertEqual(microphoneChunks.map { $0.chunk.endMs }, [5_000, 8_000])
        XCTAssertTrue(microphoneChunks.flatMap { $0.chunk.samples }.allSatisfy { $0 == 0.1 })
        for chunk in microphoneChunks {
            let samples = chunk.chunk.samples
            let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count))
            XCTAssertFalse(MeetingRecordingService.isSystemDominant(systemRms: 0.5, microphoneRms: rms))
        }
        // Keep the existing dominance threshold; change only which mic level it reads.
        XCTAssertTrue(MeetingRecordingService.isSystemDominant(systemRms: 0.5, microphoneRms: 0.03))
    }

    func testLiveAcquisitionFlushPreservesShortInitialSpeechAndTail() {
        let conditioner = StreamingMeetingEchoSuppressor(
            processor: CountingProcessor(), handlesMicrophoneGaps: true, buffersAcquisition: true)
        let speech: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]
        XCTAssertTrue(conditioner.condition(microphone: speech, speaker: speech).isEmpty)
        XCTAssertEqual(conditioner.flush(), speech)
        XCTAssertEqual(conditioner.diagnostics.processedFrames, 1)
        XCTAssertTrue(conditioner.flush().isEmpty)
    }

    func testLiveReacquisitionAfterDigitalMuteReplaysFirstSpeech() throws {
        let conditioner = StreamingMeetingEchoSuppressor(
            processor: CountingProcessor(), handlesMicrophoneGaps: true, buffersAcquisition: true)
        try conditioner.prime(microphone: [1, 1, 1, 1], speaker: [1, 1, 1, 1])
        let muted = Array(repeating: Float(0), count: 8)
        XCTAssertEqual(conditioner.condition(microphone: muted, speaker: muted), muted)
        let speech: [Float] = [0.1, 0.2, 0.3, 0.4]
        XCTAssertTrue(conditioner.condition(microphone: speech, speaker: speech).isEmpty)
        XCTAssertEqual(conditioner.flush(), speech)
    }

    func testRetryFailureRetainsPreviousDerivedArtifact() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("derived.dat")
        let candidate = folder.appendingPathComponent("candidate.dat")
        let original = Data("previous derived artifact".utf8)
        try original.write(to: output)
        let readiness = MeetingCleanedMicrophoneReadiness.scheduled(
            outputURL: output,
            task: Task { .fallback(.rawRenderFailed) },
            candidateOutputURL: candidate,
            preserveExistingOutput: true
        )
        let completion = try await readiness.awaitCompletion(timeoutSeconds: 1)
        XCTAssertEqual(completion, .fallback(.rawRenderFailed))
        XCTAssertEqual(try Data(contentsOf: output), original)
    }

    func testRetryTimeoutDoesNotRemovePreviousDerivedArtifact() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("derived.dat")
        let candidate = folder.appendingPathComponent("candidate.dat")
        try Data("old".utf8).write(to: output)
        try Data("partial".utf8).write(to: candidate)
        let task = Task<MeetingCleanedMicrophoneRenderCompletion, Never> {
            try? await Task.sleep(for: .seconds(60))
            return .fallback(.rawRenderFailed)
        }
        let readiness = MeetingCleanedMicrophoneReadiness.scheduled(
            outputURL: output, task: task, candidateOutputURL: candidate,
            preserveExistingOutput: true
        )
        let completion = try await readiness.awaitCompletion(timeoutSeconds: 0.001)
        XCTAssertNil(completion)
        XCTAssertEqual(try Data(contentsOf: output), Data("old".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidate.path))
        _ = await task.value
    }

    func testArchivedRetrySchedulesNewRenderInsteadOfReusingOldCleanedFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let previous = folder.appendingPathComponent(MeetingCleanedMicRenderer.cleanedMicrophoneFileName)
        try Data("old derived bytes".utf8).write(to: previous)
        let track = MeetingSourceAlignment.Track(
            firstHostTime: nil, lastHostTime: nil, startOffsetMs: 0,
            writtenFrameCount: 16_000, sampleRate: 16_000)
        let recording = MeetingRecordingOutput(
            sessionID: UUID(), displayName: "test", folderURL: folder,
            mixedAudioURL: folder.appendingPathComponent("playback"),
            microphoneAudioURL: folder.appendingPathComponent("missing-microphone"),
            systemAudioURL: folder.appendingPathComponent("missing-system"),
            cleanedMicrophoneAudioURL: previous, durationSeconds: 1,
            sourceAlignment: .init(meetingOriginHostTime: nil, microphone: track, system: track)
        )
        let prepared = recording.preparingEchoRetranscription(suppression: .standard)
        let readiness = try XCTUnwrap(prepared.cleanedMicrophoneReadiness)
        let completion = try await readiness.awaitCompletion(timeoutSeconds: 1)
        XCTAssertEqual(completion, .fallback(.rawRenderFailed))
        XCTAssertEqual(try Data(contentsOf: previous), Data("old derived bytes".utf8))
    }

    func testRetryPromotesOnlyCompletedCandidate() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("derived.dat")
        let candidate = folder.appendingPathComponent("candidate.dat")
        try Data("old".utf8).write(to: output)
        try Data("new".utf8).write(to: candidate)
        let readiness = MeetingCleanedMicrophoneReadiness.scheduled(
            outputURL: output, task: Task { .rendered(candidate) },
            candidateOutputURL: candidate, preserveExistingOutput: true
        )
        let completion = try await readiness.awaitCompletion(timeoutSeconds: 1)
        XCTAssertEqual(completion, .rendered(output))
        XCTAssertEqual(try Data(contentsOf: output), Data("new".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: candidate.path))
    }
}

private final class CountingProcessor: MeetingEchoSuppressing, @unchecked Sendable {
    let name = "counting"
    let sampleRate: Int
    let frameSize: Int
    init(sampleRate: Int = 8, frameSize: Int = 4) {
        self.sampleRate = sampleRate
        self.frameSize = frameSize
    }
    var resets = 0
    var processed = 0
    var lastReference: [Float] = []
    func reset() { resets += 1 }
    func processFrame(microphone: [Float], reference: [Float], output: inout [Float]) {
        processed += 1
        lastReference = reference
        output = microphone
    }
}

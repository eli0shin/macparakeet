import XCTest
import FluidAudio
@testable import MacParakeetCore

final class DiarizationServiceTests: XCTestCase {

    func testMockDiarizationServiceReturnsConfiguredResult() async throws {
        let mock = MockDiarizationService()
        let expected = MacParakeetDiarizationResult(
            segments: [
                SpeakerSegment(speakerId: "S1", startMs: 0, endMs: 5000),
                SpeakerSegment(speakerId: "S2", startMs: 5000, endMs: 10000),
            ],
            speakerCount: 2,
            speakers: [
                SpeakerInfo(id: "S1", label: "Speaker 1"),
                SpeakerInfo(id: "S2", label: "Speaker 2"),
            ]
        )
        await mock.configure(result: expected)

        let dummyURL = URL(fileURLWithPath: "/tmp/test.wav")
        let result = try await mock.diarize(audioURL: dummyURL)
        XCTAssertEqual(result.speakerCount, 2)
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.speakers.count, 2)
        XCTAssertEqual(result.speakers[0].id, "S1")
        XCTAssertEqual(result.speakers[1].label, "Speaker 2")

        let wasCalled = await mock.diarizeCalled
        XCTAssertTrue(wasCalled)
    }

    func testMockDiarizationServiceThrowsConfiguredError() async {
        let mock = MockDiarizationService()
        await mock.configure(error: STTError.transcriptionFailed("mock error"))

        let dummyURL = URL(fileURLWithPath: "/tmp/test.wav")
        do {
            _ = try await mock.diarize(audioURL: dummyURL)
            XCTFail("Expected error")
        } catch {
            // Expected
        }
    }

    func testMockDiarizationServiceDefaultsToEmpty() async throws {
        let mock = MockDiarizationService()
        let dummyURL = URL(fileURLWithPath: "/tmp/test.wav")
        let result = try await mock.diarize(audioURL: dummyURL)
        XCTAssertEqual(result.speakerCount, 0)
        XCTAssertTrue(result.segments.isEmpty)
        XCTAssertTrue(result.speakers.isEmpty)
    }

    func testMockPrepareModels() async throws {
        let mock = MockDiarizationService()
        try await mock.prepareModels()
        let wasCalled = await mock.prepareModelsCalled
        XCTAssertTrue(wasCalled)
        let ready = await mock.isReady()
        XCTAssertTrue(ready)
        let cached = await mock.hasCachedModels()
        XCTAssertTrue(cached)
    }

    func testIsReady() async {
        let mock = MockDiarizationService()
        let ready = await mock.isReady()
        XCTAssertFalse(ready)
    }

    func testClearModelCacheRemovesCachedSpeakerModels() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repoDirectory = DiarizationService.modelCacheDirectory(directory: tempDirectory)
        try FileManager.default.createDirectory(at: repoDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        for modelName in DiarizationService.requiredModelNames() {
            let modelURL = repoDirectory.appendingPathComponent(modelName, isDirectory: false)
            FileManager.default.createFile(atPath: modelURL.path, contents: Data())
        }

        XCTAssertTrue(DiarizationService.isModelCached(directory: tempDirectory))

        DiarizationService.clearModelCache(directory: tempDirectory)

        XCTAssertFalse(DiarizationService.isModelCached(directory: tempDirectory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoDirectory.path))
    }

    func testFinalConfigEnablesForkRepairWithoutChangingClustering() {
        let config = DiarizationService.offlineConfig(speakerConstraint: nil, finalTranscript: true)
        let defaults = OfflineDiarizerConfig.default

        XCTAssertTrue(config.zeroVoteReembed.enabled)
        XCTAssertEqual(config.zeroVoteReembed.minDurationSeconds, 0.4)
        XCTAssertEqual(config.segmentationStepRatio, 0.1)
        XCTAssertEqual(config.minSegmentDuration, 0)
        XCTAssertTrue(config.exclusiveSegments)
        XCTAssertEqual(config.clusteringThreshold, defaults.clusteringThreshold)
        XCTAssertEqual(config.Fa, defaults.Fa)
        XCTAssertEqual(config.Fb, defaults.Fb)
        XCTAssertNil(config.clustering.numSpeakers)
        XCTAssertFalse(DiarizationService.offlineConfig(speakerConstraint: nil).zeroVoteReembed.enabled)
    }

    func testFinalConfigKeepsRepairWithSpeakerConstraint() {
        let config = DiarizationService.offlineConfig(speakerConstraint: .exact(4), finalTranscript: true)
        XCTAssertTrue(config.zeroVoteReembed.enabled)
        XCTAssertEqual(config.clustering.numSpeakers, 4)
    }

    func testOfflineConfigAppliesExactSpeakerConstraint() {
        let config = DiarizationService.offlineConfig(speakerConstraint: .exact(2))

        XCTAssertEqual(config.clustering.numSpeakers, 2)
        XCTAssertNil(config.clustering.minSpeakers)
        XCTAssertNil(config.clustering.maxSpeakers)
    }

    func testOfflineConfigAppliesSpeakerRangeConstraint() {
        let config = DiarizationService.offlineConfig(speakerConstraint: .range(min: 2, max: 4))

        XCTAssertNil(config.clustering.numSpeakers)
        XCTAssertEqual(config.clustering.minSpeakers, 2)
        XCTAssertEqual(config.clustering.maxSpeakers, 4)
    }

    func testOfflineConfigAppliesMinimumSpeakerRangeConstraint() {
        let config = DiarizationService.offlineConfig(speakerConstraint: .range(min: 2, max: nil))

        XCTAssertNil(config.clustering.numSpeakers)
        XCTAssertEqual(config.clustering.minSpeakers, 2)
        XCTAssertNil(config.clustering.maxSpeakers)
    }

    func testOfflineConfigAppliesMaximumSpeakerRangeConstraint() {
        let config = DiarizationService.offlineConfig(speakerConstraint: .range(min: nil, max: 4))

        XCTAssertNil(config.clustering.numSpeakers)
        XCTAssertNil(config.clustering.minSpeakers)
        XCTAssertEqual(config.clustering.maxSpeakers, 4)
    }

    func testFinalTranscriptWithoutConstraintUsesFinalManagerThroughProtocol() async throws {
        let regular = RecordingOfflineDiarizerManager(result: DiarizationResult(segments: []))
        let final = RecordingOfflineDiarizerManager(result: DiarizationResult(segments: []))
        let service: any DiarizationServiceProtocol = DiarizationService(
            manager: regular,
            modelsDirectory: URL(fileURLWithPath: "/tmp/unused-diarization-models"),
            finalManagerFactory: { _ in final }
        )
        let audioURL = URL(fileURLWithPath: "/tmp/unused-diarization.wav")

        _ = try await service.diarizeFinalTranscript(audioURL: audioURL)
        _ = try await service.diarizeFinalTranscript(audioURL: audioURL, speakerConstraint: nil)

        let regularCalls = await regular.processedAudioURLs
        let finalCalls = await final.processedAudioURLs
        XCTAssertEqual(regularCalls, [])
        XCTAssertEqual(finalCalls, [audioURL, audioURL])
    }

    func testFinalTranscriptForwardsSpeakerConstraintThroughProtocol() async throws {
        let regular = RecordingOfflineDiarizerManager(result: DiarizationResult(segments: []))
        let final = RecordingOfflineDiarizerManager(result: DiarizationResult(segments: []))
        let service: any DiarizationServiceProtocol = DiarizationService(
            manager: regular,
            modelsDirectory: URL(fileURLWithPath: "/tmp/unused-diarization-models"),
            finalManagerFactory: { constraint in
                XCTAssertEqual(constraint, .exact(2))
                return final
            }
        )
        let audioURL = URL(fileURLWithPath: "/tmp/unused-diarization.wav")

        _ = try await service.diarizeFinalTranscript(audioURL: audioURL, speakerConstraint: .exact(2))

        let regularCalls = await regular.processedAudioURLs
        let finalCalls = await final.processedAudioURLs
        XCTAssertEqual(regularCalls, [])
        XCTAssertEqual(finalCalls, [audioURL])
    }

    func testFinalTranscriptDefaultStillSupportsBasicDiarizers() async throws {
        let mock = MockDiarizationService()
        let service: any DiarizationServiceProtocol = mock

        _ = try await service.diarizeFinalTranscript(audioURL: URL(fileURLWithPath: "/tmp/unused.wav"))

        let called = await mock.diarizeCalled
        XCTAssertTrue(called)
    }

    func testDiarizePreparesModelsUsingCustomDirectoryBeforeColdStartInference() async throws {
        let customDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .standardizedFileURL
        let manager = RecordingOfflineDiarizerManager(result: DiarizationResult(segments: [
            TimedSpeakerSegment(
                speakerId: "speaker_0",
                embedding: [],
                startTimeSeconds: 0,
                endTimeSeconds: 1.2,
                qualityScore: 0.9
            ),
        ]))
        let service = DiarizationService(manager: manager, modelsDirectory: customDirectory)
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        let result = try await service.diarize(audioURL: audioURL)
        let preparedDirectories = await manager.preparedDirectories
        let processedAudioURLs = await manager.processedAudioURLs
        let ready = await service.isReady()

        XCTAssertEqual(preparedDirectories, [customDirectory])
        XCTAssertEqual(processedAudioURLs, [audioURL])
        XCTAssertEqual(result.speakerCount, 1)
        XCTAssertEqual(result.speakers.map { $0.id }, ["S1"])
        XCTAssertEqual(result.segments.map { $0.speakerId }, ["S1"])
        XCTAssertTrue(ready)
    }
}

private actor RecordingOfflineDiarizerManager: OfflineDiarizerManaging {
    let result: DiarizationResult
    var preparedDirectories: [URL] = []
    var processedAudioURLs: [URL] = []

    init(result: DiarizationResult) {
        self.result = result
    }

    func prepareModels(at directory: URL) async throws {
        preparedDirectories.append(directory)
    }

    func process(audioURL: URL) async throws -> DiarizationResult {
        processedAudioURLs.append(audioURL)
        return result
    }
}

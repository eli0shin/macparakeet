import FluidAudio
import Foundation

public struct MacParakeetDiarizationResult: Sendable {
    public let segments: [SpeakerSegment]
    public let speakerCount: Int
    public let speakers: [SpeakerInfo]

    public init(segments: [SpeakerSegment], speakerCount: Int, speakers: [SpeakerInfo]) {
        self.segments = segments
        self.speakerCount = speakerCount
        self.speakers = speakers
    }
}

public struct SpeakerSegment: Sendable {
    public let speakerId: String
    public let startMs: Int
    public let endMs: Int

    public init(speakerId: String, startMs: Int, endMs: Int) {
        self.speakerId = speakerId
        self.startMs = startMs
        self.endMs = endMs
    }
}

public enum SpeakerDiarizationConstraint: Equatable, Sendable {
    case exact(Int)
    case range(min: Int?, max: Int?)
}

public protocol DiarizationServiceProtocol: Sendable {
    func diarize(audioURL: URL) async throws -> MacParakeetDiarizationResult
    func diarize(audioURL: URL, speakerConstraint: SpeakerDiarizationConstraint?) async throws -> MacParakeetDiarizationResult
    func diarizeFinalTranscript(audioURL: URL, speakerConstraint: SpeakerDiarizationConstraint?) async throws -> MacParakeetDiarizationResult
    func prepareModels(onProgress: (@Sendable (String) -> Void)?) async throws
    func isReady() async -> Bool
    func hasCachedModels() async -> Bool
}

extension DiarizationServiceProtocol {
    public func diarizeFinalTranscript(audioURL: URL) async throws -> MacParakeetDiarizationResult {
        // Forward explicitly through the protocol requirement. A default argument
        // on the fallback below selects that fallback for unconstrained calls.
        try await diarizeFinalTranscript(audioURL: audioURL, speakerConstraint: nil)
    }

    public func diarizeFinalTranscript(audioURL: URL, speakerConstraint: SpeakerDiarizationConstraint?) async throws -> MacParakeetDiarizationResult {
        try await diarize(audioURL: audioURL, speakerConstraint: speakerConstraint)
    }

    public func diarize(audioURL: URL, speakerConstraint: SpeakerDiarizationConstraint?) async throws -> MacParakeetDiarizationResult {
        try await diarize(audioURL: audioURL)
    }

    public func prepareModels() async throws {
        try await prepareModels(onProgress: nil)
    }

    public func hasCachedModels() async -> Bool {
        false
    }
}

protocol OfflineDiarizerManaging: AnyObject, Sendable {
    func prepareModels(at directory: URL) async throws
    func process(audioURL: URL) async throws -> DiarizationResult
}

extension OfflineDiarizerManager: OfflineDiarizerManaging {
    func prepareModels(at directory: URL) async throws {
        try await prepareModels(directory: directory)
    }

    func process(audioURL: URL) async throws -> DiarizationResult {
        try await process(audioURL)
    }
}

// @unchecked Sendable: all access is serialized through DiarizationService actor isolation.
extension OfflineDiarizerManager: @retroactive @unchecked Sendable {}

private struct NoopMeetingLiveDiarizer: MeetingLiveDiarizing {
    func liveModelsAreReady() async -> Bool { true }
    func hasCachedLiveModels() async -> Bool { true }
}

public actor DiarizationService: DiarizationServiceProtocol, MeetingLiveDiarizing {
    private let manager: any OfflineDiarizerManaging
    private let constrainedManagerFactory: (@Sendable (SpeakerDiarizationConstraint) -> any OfflineDiarizerManaging)?
    private let finalManagerFactory: (@Sendable (SpeakerDiarizationConstraint?) -> any OfflineDiarizerManaging)?
    private let modelsDirectory: URL
    private nonisolated let liveDiarizer: any MeetingLiveDiarizing
    private var modelsReady = false

    public init(
        config: OfflineDiarizerConfig = .default,
        modelsDirectory: URL? = nil
    ) {
        self.init(
            manager: OfflineDiarizerManager(config: config),
            constrainedManagerFactory: { constraint in
                OfflineDiarizerManager(config: Self.offlineConfig(speakerConstraint: constraint))
            },
            modelsDirectory: modelsDirectory ?? AppPaths.fluidAudioModelsDirURL,
            finalManagerFactory: { constraint in
                OfflineDiarizerManager(config: Self.offlineConfig(
                    speakerConstraint: constraint, finalTranscript: true, baseConfig: config
                ))
            },
            liveDiarizer: MeetingLiveDiarizer(
                modelsDirectory: modelsDirectory ?? AppPaths.fluidAudioModelsDirURL
            )
        )
    }

    public init(
        speakerConstraint: SpeakerDiarizationConstraint,
        modelsDirectory: URL? = nil
    ) {
        self.init(
            config: Self.offlineConfig(speakerConstraint: speakerConstraint),
            modelsDirectory: modelsDirectory
        )
    }

    init(
        manager: any OfflineDiarizerManaging,
        constrainedManagerFactory: (@Sendable (SpeakerDiarizationConstraint) -> any OfflineDiarizerManaging)? = nil,
        modelsDirectory: URL,
        finalManagerFactory: (@Sendable (SpeakerDiarizationConstraint?) -> any OfflineDiarizerManaging)? = nil,
        liveDiarizer: any MeetingLiveDiarizing = NoopMeetingLiveDiarizer()
    ) {
        self.finalManagerFactory = finalManagerFactory
        self.manager = manager
        self.constrainedManagerFactory = constrainedManagerFactory
        self.modelsDirectory = modelsDirectory.standardizedFileURL
        self.liveDiarizer = liveDiarizer
    }

    public func diarize(audioURL: URL) async throws -> MacParakeetDiarizationResult {
        try await diarize(audioURL: audioURL, speakerConstraint: nil)
    }

    public func diarize(audioURL: URL, speakerConstraint: SpeakerDiarizationConstraint?) async throws -> MacParakeetDiarizationResult {
        let selectedManager: any OfflineDiarizerManaging
        if let speakerConstraint, let constrainedManagerFactory {
            selectedManager = constrainedManagerFactory(speakerConstraint)
            try await selectedManager.prepareModels(at: modelsDirectory)
        } else {
            try await ensureModelsPrepared()
            selectedManager = manager
        }

        return try await process(audioURL: audioURL, manager: selectedManager)
    }

    public func diarizeFinalTranscript(audioURL: URL, speakerConstraint: SpeakerDiarizationConstraint? = nil) async throws -> MacParakeetDiarizationResult {
        guard let finalManagerFactory else {
            return try await diarize(audioURL: audioURL, speakerConstraint: speakerConstraint)
        }
        let manager = finalManagerFactory(speakerConstraint)
        try await manager.prepareModels(at: modelsDirectory)
        try Task.checkCancellation()
        return try await process(audioURL: audioURL, manager: manager)
    }

    private func process(audioURL: URL, manager: any OfflineDiarizerManaging) async throws -> MacParakeetDiarizationResult {
        let fluidResult: DiarizationResult
        do {
            // Serialize Neural Engine inference on macOS 14 (no-op on macOS 15+):
            // offline diarization runs its own CoreML models outside the STT
            // scheduler, so it must not overlap an in-flight ASR inference, which
            // intermittently SIGBUSes the shared Neural Engine queue on macOS 14.
            // See `ANEInferenceGate`.
            fluidResult = try await ANEInferenceGate.shared.withExclusiveAccess {
                try await manager.process(audioURL: audioURL)
            }
        } catch let error as OfflineDiarizationError where error.isNoSpeechDetected {
            return MacParakeetDiarizationResult(segments: [], speakerCount: 0, speakers: [])
        }

        // Sort by start time before assigning stable IDs so "S1" is the
        // first speaker to *talk* (chronologically), not the first speaker
        // to appear in whatever order FluidAudio's offline pipeline happens
        // to return segments. FluidAudio doesn't formally document the
        // ordering of its `segments` array, so we don't rely on it.
        let chronologicalSegments = fluidResult.segments.sorted { lhs, rhs in
            lhs.startTimeSeconds < rhs.startTimeSeconds
        }

        // Collect unique speaker IDs from FluidAudio (e.g. "speaker_0", "speaker_1")
        // and normalize to stable IDs ("S1", "S2") in chronological encounter order.
        var idMapping: [String: String] = [:]
        var nextIndex = 1
        for segment in chronologicalSegments {
            if idMapping[segment.speakerId] == nil {
                idMapping[segment.speakerId] = "S\(nextIndex)"
                nextIndex += 1
            }
        }

        let segments: [SpeakerSegment] = chronologicalSegments.map { seg in
            let mappedId = idMapping[seg.speakerId] ?? seg.speakerId
            let startMs = max(0, Int((seg.startTimeSeconds * 1000).rounded()))
            let endMs = max(0, Int((seg.endTimeSeconds * 1000).rounded()))
            return SpeakerSegment(speakerId: mappedId, startMs: startMs, endMs: endMs)
        }

        let speakers: [SpeakerInfo] = idMapping
            .sorted { Int($0.value.dropFirst()) ?? 0 < Int($1.value.dropFirst()) ?? 0 }
            .map { _, stableId in
                let number = String(stableId.dropFirst())
                return SpeakerInfo(id: stableId, label: "Speaker \(number)")
            }

        return MacParakeetDiarizationResult(
            segments: segments,
            speakerCount: speakers.count,
            speakers: speakers
        )
    }

    public func prepareModels(onProgress: (@Sendable (String) -> Void)? = nil) async throws {
        onProgress?("Downloading speaker models...")
        try await ensureModelsPrepared()
        try await prepareLiveModels(onProgress: onProgress)
        onProgress?("Speaker models ready")
    }

    private func ensureModelsPrepared() async throws {
        guard !modelsReady else { return }
        try await manager.prepareModels(at: modelsDirectory)
        modelsReady = true
    }

    public func isReady() async -> Bool {
        guard modelsReady else { return false }
        return await liveModelsAreReady()
    }

    public func hasCachedModels() async -> Bool {
        guard Self.isModelCached(directory: modelsDirectory) else { return false }
        return await hasCachedLiveModels()
    }

    public func prepareLiveModels(onProgress: (@Sendable (String) -> Void)?) async throws {
        try await liveDiarizer.prepareLiveModels(onProgress: onProgress)
    }

    public func liveModelsAreReady() async -> Bool {
        await liveDiarizer.liveModelsAreReady()
    }

    public func hasCachedLiveModels() async -> Bool {
        await liveDiarizer.hasCachedLiveModels()
    }

    public func startLiveSession(
        id: UUID,
        enabledSources: Set<AudioSource>,
        onEvent: @escaping @Sendable (MeetingLiveDiarizationEvent) async -> Void
    ) async throws {
        try await liveDiarizer.startLiveSession(
            id: id,
            enabledSources: enabledSources,
            onEvent: onEvent
        )
    }

    public func setLiveSpeakerDetection(_ enabled: Bool, for source: AudioSource, sessionID: UUID) async throws {
        try await liveDiarizer.setLiveSpeakerDetection(enabled, for: source, sessionID: sessionID)
    }

    public nonisolated func enqueueLiveAudio(samples: [Float], source: AudioSource, sessionID: UUID) {
        liveDiarizer.enqueueLiveAudio(samples: samples, source: source, sessionID: sessionID)
    }

    public func finishLiveSession(id: UUID) async {
        await liveDiarizer.finishLiveSession(id: id)
    }

    public nonisolated static func isModelCached(directory: URL? = nil) -> Bool {
        let repoDirectory = modelCacheDirectory(directory: directory)
        return requiredModelNames().allSatisfy { modelName in
            FileManager.default.fileExists(
                atPath: repoDirectory.appendingPathComponent(modelName, isDirectory: false).path
            )
        }
    }

    public nonisolated static func clearModelCache(directory: URL? = nil) {
        let rootDirectory = directory ?? AppPaths.fluidAudioModelsDirURL
        try? FileManager.default.removeItem(at: modelCacheDirectory(directory: rootDirectory))
        MeetingLiveDiarizer.clearModelCache(directory: rootDirectory)
    }

    nonisolated static func modelCacheDirectory(directory: URL? = nil) -> URL {
        let baseDirectory = (directory ?? AppPaths.fluidAudioModelsDirURL).standardizedFileURL
        return baseDirectory.appendingPathComponent(Repo.diarizer.folderName, isDirectory: true)
    }

    nonisolated static func requiredModelNames() -> [String] {
        Array(ModelNames.OfflineDiarizer.requiredModels)
    }

    nonisolated static func offlineConfig(
        speakerConstraint: SpeakerDiarizationConstraint?,
        finalTranscript: Bool = false,
        baseConfig: OfflineDiarizerConfig = .default
    ) -> OfflineDiarizerConfig {
        var config = baseConfig
        if finalTranscript {
            // FluidAudio's documented offline accuracy configuration. Keep
            // embedding/clustering defaults and use its exclusive output.
            config.segmentationStepRatio = 0.1
            config.minSegmentDuration = 0
            config.exclusiveSegments = true
        }
        guard let speakerConstraint else { return config }

        switch speakerConstraint {
        case .exact(let count):
            return config.withSpeakers(exactly: count)
        case .range(let min, let max):
            return config.withSpeakers(min: min, max: max)
        }
    }
}

extension OfflineDiarizationError {
    var isNoSpeechDetected: Bool {
        if case .noSpeechDetected = self { return true }
        return false
    }
}

public actor MockDiarizationService: DiarizationServiceProtocol, MeetingLiveDiarizing {
    public var diarizeResult: MacParakeetDiarizationResult?
    public var diarizeError: Error?
    public var diarizeCalled = false
    public var diarizeDelay: Duration?
    public var lastSpeakerConstraint: SpeakerDiarizationConstraint?
    public var prepareModelsCalled = false
    public var prepareModelsError: Error?
    public var ready = false
    public var cachedModels = false

    public init() {}

    public func configure(result: MacParakeetDiarizationResult) {
        self.diarizeResult = result
        self.diarizeError = nil
    }

    public func configure(error: Error) {
        self.diarizeError = error
        self.diarizeResult = nil
    }

    public func configureDiarizeDelay(_ delay: Duration?) {
        diarizeDelay = delay
    }

    public func configurePrepareModels(error: Error?) {
        self.prepareModelsError = error
    }

    public func configureReady(_ ready: Bool) {
        self.ready = ready
    }

    public func configureCachedModels(_ cachedModels: Bool) {
        self.cachedModels = cachedModels
    }

    public func diarize(audioURL: URL) async throws -> MacParakeetDiarizationResult {
        try await diarize(audioURL: audioURL, speakerConstraint: nil)
    }

    public func diarize(audioURL: URL, speakerConstraint: SpeakerDiarizationConstraint?) async throws -> MacParakeetDiarizationResult {
        diarizeCalled = true
        lastSpeakerConstraint = speakerConstraint
        if let diarizeDelay { try await Task.sleep(for: diarizeDelay) }
        if let error = diarizeError { throw error }
        return diarizeResult ?? MacParakeetDiarizationResult(segments: [], speakerCount: 0, speakers: [])
    }

    public func prepareModels(onProgress: (@Sendable (String) -> Void)?) async throws {
        prepareModelsCalled = true
        if let error = prepareModelsError { throw error }
        ready = true
        cachedModels = true
    }

    public func isReady() async -> Bool {
        ready
    }

    public func hasCachedModels() async -> Bool {
        cachedModels
    }
}

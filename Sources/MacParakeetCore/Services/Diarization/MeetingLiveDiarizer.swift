import FluidAudio
import Foundation
import OSLog

public enum MeetingLiveDiarizationEvent: Sendable {
    case timeline(source: AudioSource, snapshot: MeetingLiveDiarizationSnapshot)
    case unavailable(source: AudioSource, reason: String)
}

public protocol MeetingLiveDiarizing: Sendable {
    func prepareLiveModels(onProgress: (@Sendable (String) -> Void)?) async throws
    func liveModelsAreReady() async -> Bool
    func hasCachedLiveModels() async -> Bool
    func startLiveSession(
        id: UUID,
        enabledSources: Set<AudioSource>,
        onEvent: @escaping @Sendable (MeetingLiveDiarizationEvent) async -> Void
    ) async throws
    func setLiveSpeakerDetection(_ enabled: Bool, for source: AudioSource, sessionID: UUID) async throws
    func enqueueLiveAudio(samples: [Float], source: AudioSource, sessionID: UUID)
    func finishLiveSession(id: UUID) async
}

extension MeetingLiveDiarizing {
    public func prepareLiveModels(onProgress: (@Sendable (String) -> Void)?) async throws {}
    public func liveModelsAreReady() async -> Bool { false }
    public func hasCachedLiveModels() async -> Bool { false }
    public func startLiveSession(
        id: UUID,
        enabledSources: Set<AudioSource>,
        onEvent: @escaping @Sendable (MeetingLiveDiarizationEvent) async -> Void
    ) async throws {}
    public func setLiveSpeakerDetection(_ enabled: Bool, for source: AudioSource, sessionID: UUID) async throws {}
    public func enqueueLiveAudio(samples: [Float], source: AudioSource, sessionID: UUID) {}
    public func finishLiveSession(id: UUID) async {}
}

/// A meeting-local snapshot from a stateful streaming diarizer. Speaker IDs and
/// segment times already belong to the meeting timeline; callers must not
/// renumber or offset them.
public struct MeetingLiveDiarizationSnapshot: Sendable {
    public let segments: [SpeakerSegment]
    public let speakers: [SpeakerInfo]
    public let committedThroughMs: Int

    public init(segments: [SpeakerSegment], speakers: [SpeakerInfo], committedThroughMs: Int) {
        self.segments = segments
        self.speakers = speakers
        self.committedThroughMs = committedThroughMs
    }
}

private final class MeetingLiveAudioQueue: @unchecked Sendable {
    private static let maximumPendingSamplesPerSource = 30 * 16_000

    struct Block: Sendable {
        let sessionID: UUID
        let source: AudioSource
        let samples: [Float]
        let skippedSampleCount: Int

        init(sessionID: UUID, source: AudioSource, samples: [Float], skippedSampleCount: Int = 0) {
            self.sessionID = sessionID
            self.source = source
            self.samples = samples
            self.skippedSampleCount = skippedSampleCount
        }
    }

    private struct Overflow: Sendable {
        let sessionID: UUID
        var sampleCount: Int
    }

    private struct State {
        var blocks: [Block] = []
        var nextBlockIndex = 0
        var pendingSamples: [AudioSource: Int] = [:]
        var overflowBySource: [AudioSource: Overflow] = [:]
        var drainScheduled = false
    }

    private let lock = NSLock()
    private var state = State()

    func enqueue(_ block: Block) -> Bool {
        lock.withLock {
            let pending = state.pendingSamples[block.source, default: 0]
            if var overflow = state.overflowBySource[block.source] {
                overflow.sampleCount += block.samples.count
                state.overflowBySource[block.source] = overflow
            } else if pending + block.samples.count > Self.maximumPendingSamplesPerSource {
                state.overflowBySource[block.source] = Overflow(
                    sessionID: block.sessionID,
                    sampleCount: block.samples.count
                )
            } else {
                state.blocks.append(block)
                state.pendingSamples[block.source] = pending + block.samples.count
            }
            guard !state.drainScheduled else { return false }
            state.drainScheduled = true
            return true
        }
    }

    func takeNext() -> Block? {
        lock.withLock {
            if state.nextBlockIndex < state.blocks.count {
                let block = state.blocks[state.nextBlockIndex]
                state.nextBlockIndex += 1
                state.pendingSamples[block.source, default: 0] -= block.samples.count
                if state.nextBlockIndex >= 256, state.nextBlockIndex * 2 >= state.blocks.count {
                    state.blocks.removeFirst(state.nextBlockIndex)
                    state.nextBlockIndex = 0
                }
                return block
            }
            if let source = state.overflowBySource.keys.sorted(by: { $0.rawValue < $1.rawValue }).first,
                let overflow = state.overflowBySource.removeValue(forKey: source)
            {
                return Block(
                    sessionID: overflow.sessionID,
                    source: source,
                    samples: [],
                    skippedSampleCount: overflow.sampleCount
                )
            }
            state = State()
            return nil
        }
    }

    func reset() {
        lock.withLock { state = State() }
    }
}

/// Owns one persistent LS-EEND stream per captured source. Audio enters through
/// a lock-backed queue so Core ML inference never blocks the capture event loop.
actor MeetingLiveDiarizer: MeetingLiveDiarizing {
    private struct SourceSession {
        let diarizer: LSEENDDiarizer
        let startSample: Int
    }

    private let logger = Logger(subsystem: "com.macparakeet.core", category: "MeetingLiveDiarizer")
    private let modelsDirectory: URL
    private nonisolated let queue = MeetingLiveAudioQueue()

    private var model: LSEENDModel?
    private var sessionID: UUID?
    private var eventHandler: (@Sendable (MeetingLiveDiarizationEvent) async -> Void)?
    private var sourceSessions: [AudioSource: SourceSession] = [:]
    private var enabledSources = Set<AudioSource>()
    private var receivedSamples: [AudioSource: Int] = [:]
    private var publishedThroughMs: [AudioSource: Int] = [:]

    private static let variant: LSEENDVariant = .dihard3
    private static let stepSize: LSEENDStepSize = .step500ms
    private static let sampleRate = 16_000

    init(modelsDirectory: URL = AppPaths.fluidAudioModelsDirURL) {
        self.modelsDirectory = modelsDirectory.standardizedFileURL
    }

    nonisolated static func clearModelCache(directory: URL) {
        let repoDirectory = directory.standardizedFileURL
            .appendingPathComponent(Self.variant.repo.folderName, isDirectory: true)
        try? FileManager.default.removeItem(at: repoDirectory)
    }

    func prepareLiveModels(onProgress: (@Sendable (String) -> Void)? = nil) async throws {
        guard model == nil else { return }
        onProgress?("Downloading live speaker model...")
        model = try await LSEENDModel.loadFromHuggingFace(
            variant: Self.variant,
            stepSize: Self.stepSize,
            cacheDirectory: modelsDirectory,
            computeUnits: .cpuOnly
        )
        onProgress?("Live speaker model ready")
    }

    func liveModelsAreReady() -> Bool { model != nil }

    nonisolated func hasCachedLiveModels() async -> Bool {
        let variant = Self.variant
        let repo = variant.repo
        let relativePath = variant.fileName(forStep: Self.stepSize)
        let fullRelativePath = repo.subPath.map { "\($0)/\(relativePath)" } ?? relativePath
        let modelURL = modelsDirectory
            .appendingPathComponent(repo.folderName, isDirectory: true)
            .appendingPathComponent(fullRelativePath, isDirectory: true)
        return FileManager.default.fileExists(atPath: modelURL.path)
    }

    func startLiveSession(
        id: UUID,
        enabledSources: Set<AudioSource>,
        onEvent: @escaping @Sendable (MeetingLiveDiarizationEvent) async -> Void
    ) async throws {
        queue.reset()
        sessionID = id
        eventHandler = onEvent
        sourceSessions = [:]
        self.enabledSources = enabledSources
        receivedSamples = [:]
        publishedThroughMs = [:]
        if !enabledSources.isEmpty {
            do {
                guard model != nil else { throw LSEENDError.notInitialized }
            } catch {
                self.enabledSources = []
                throw error
            }
        }
    }

    func setLiveSpeakerDetection(_ enabled: Bool, for source: AudioSource, sessionID: UUID) async throws {
        guard self.sessionID == sessionID else { return }
        if enabled {
            guard model != nil else { throw LSEENDError.notInitialized }
            enabledSources.insert(source)
        } else {
            enabledSources.remove(source)
        }
    }

    nonisolated func enqueueLiveAudio(samples: [Float], source: AudioSource, sessionID: UUID) {
        guard !samples.isEmpty else { return }
        let shouldStartDrain = queue.enqueue(.init(sessionID: sessionID, source: source, samples: samples))
        if shouldStartDrain {
            Task { await self.drainQueue() }
        }
    }

    private func snapshot(for source: AudioSource) -> MeetingLiveDiarizationSnapshot? {
        guard enabledSources.contains(source), let sourceSession = sourceSessions[source] else { return nil }

        let offsetSeconds = Float(sourceSession.startSample) / Float(Self.sampleRate)
        let diarizerSpeakers = sourceSession.diarizer.timeline.speakers
        let active = diarizerSpeakers
            .filter { !$0.value.finalizedSegments.isEmpty }
            .sorted { $0.key < $1.key }
        let labels = Dictionary(uniqueKeysWithValues: active.map { slot, _ in
            let number = slot + 1
            let id = "\(source.rawValue):S\(number)"
            let label = source == .microphone ? "Local Speaker \(number)" : "Others \(number)"
            return (slot, SpeakerInfo(id: id, label: label))
        })
        let segments = active.flatMap { slot, speaker in
            speaker.finalizedSegments.compactMap { segment -> SpeakerSegment? in
                guard let info = labels[slot] else { return nil }
                return SpeakerSegment(
                    speakerId: info.id,
                    startMs: Int(((segment.startTime + offsetSeconds) * 1_000).rounded()),
                    endMs: Int(((segment.endTime + offsetSeconds) * 1_000).rounded())
                )
            }
        }.sorted { lhs, rhs in
            if lhs.startMs == rhs.startMs { return lhs.speakerId < rhs.speakerId }
            return lhs.startMs < rhs.startMs
        }
        let committedThroughMs = Int(
            ((sourceSession.diarizer.timeline.finalizedDuration + offsetSeconds) * 1_000).rounded()
        )
        return MeetingLiveDiarizationSnapshot(
            segments: segments,
            speakers: labels.values.sorted { $0.id < $1.id },
            committedThroughMs: committedThroughMs
        )
    }

    func finishLiveSession(id: UUID) async {
        guard sessionID == id else { return }
        await drainQueue()
        for (source, sourceSession) in sourceSessions {
            _ = try? sourceSession.diarizer.finalizeSession()
            if enabledSources.contains(source), let snapshot = snapshot(for: source), let eventHandler {
                await eventHandler(.timeline(source: source, snapshot: snapshot))
            }
            sourceSession.diarizer.cleanup()
        }
        queue.reset()
        sessionID = nil
        eventHandler = nil
        sourceSessions = [:]
        enabledSources = []
        receivedSamples = [:]
        publishedThroughMs = [:]
    }

    private func drainQueue() async {
        while let block = queue.takeNext() {
            if let event = process(block), let eventHandler {
                await eventHandler(event)
            }
            // Capture never waits for model work. Yield between model calls so
            // lifecycle and setting changes can enter actor isolation.
            await Task.yield()
        }
    }

    private func process(_ block: MeetingLiveAudioQueue.Block) -> MeetingLiveDiarizationEvent? {
        guard block.sessionID == sessionID else { return nil }
        let blockStart = receivedSamples[block.source, default: 0]
        receivedSamples[block.source, default: 0] += block.samples.count + block.skippedSampleCount
        if block.skippedSampleCount > 0 {
            sourceSessions[block.source]?.diarizer.cleanup()
            sourceSessions[block.source] = nil
            enabledSources.remove(block.source)
            let reason = "Live diarization could not keep up with capture."
            logger.error(
                "meeting_live_diarization_disabled reason=audio_backlog source=\(block.source.rawValue, privacy: .public) skipped_samples=\(block.skippedSampleCount, privacy: .public)"
            )
            return .unavailable(source: block.source, reason: reason)
        }
        guard let model else { return nil }

        do {
            let sourceSession: SourceSession
            if let existing = sourceSessions[block.source] {
                sourceSession = existing
            } else {
                guard enabledSources.contains(block.source) else { return nil }
                sourceSession = SourceSession(
                    diarizer: try LSEENDDiarizer(model: model),
                    startSample: blockStart
                )
                sourceSessions[block.source] = sourceSession
            }
            let samples = enabledSources.contains(block.source)
                ? block.samples
                : [Float](repeating: 0, count: block.samples.count)
            _ = try sourceSession.diarizer.process(
                samples: samples,
                sourceSampleRate: Double(Self.sampleRate)
            )
            guard let snapshot = snapshot(for: block.source),
                snapshot.committedThroughMs > publishedThroughMs[block.source, default: 0]
            else { return nil }
            publishedThroughMs[block.source] = snapshot.committedThroughMs
            return .timeline(source: block.source, snapshot: snapshot)
        } catch {
            logger.error(
                "meeting_live_diarization_failed source=\(block.source.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            enabledSources.remove(block.source)
            sourceSessions[block.source] = nil
            return .unavailable(source: block.source, reason: error.localizedDescription)
        }
    }
}

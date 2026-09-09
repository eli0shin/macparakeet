import AVFAudio
import Foundation
import OSLog

actor LiveChunkTranscriber {
    struct SessionContext: Sendable {
        let id: UUID
        let chunkFolderURL: URL
        let speechEngine: SpeechEngineSelection
        let systemSpeakerDetection: Bool
        let microphoneSpeakerDetection: Bool
    }

    struct OrderedResult: Sendable {
        let source: AudioSource
        let chunk: AudioChunker.AudioChunk
        let result: STTResult
        let diarization: MacParakeetDiarizationResult?
        let speakerDetectionGeneration: Int
    }

    enum Event: Sendable {
        case orderedResults([OrderedResult])
        case backpressureDrop
        case transcriptionFailed(String)
    }

    typealias EventHandler = @Sendable (Event) async -> Void

    private struct PendingChunkTask: Sendable {
        let id: UUID
        let task: Task<Void, Never>
    }

    private struct PendingAttributionResult: Sendable {
        let sessionID: UUID
        let source: AudioSource
        let chunk: AudioChunker.AudioChunk
        let result: STTResult
    }

    private let logger = Logger(subsystem: "com.macparakeet.core", category: "LiveChunkTranscriber")
    private let sttTranscriber: STTTranscribing
    private let diarizationService: (any DiarizationServiceProtocol)?

    private var sessionContext: SessionContext?
    private var speakerDetection: [AudioSource: Bool] = [:]
    private var speakerDetectionGeneration: [AudioSource: Int] = [:]
    private var eventHandler: EventHandler?
    private var pendingChunkTasks: [PendingChunkTask] = []
    private var pendingAttributionResults: [PendingAttributionResult] = []
    private var attributionDrainTask: Task<Void, Never>?
    private var attributionDrainID: UUID?
    private var nextChunkSequence: [AudioSource: Int] = [:]
    private var chunkResultBuffer = MeetingChunkResultBuffer()

    private static let maximumPendingAttributionResults = 12

    init(
        sttTranscriber: STTTranscribing,
        diarizationService: (any DiarizationServiceProtocol)? = nil
    ) {
        self.sttTranscriber = sttTranscriber
        self.diarizationService = diarizationService
    }

    func startSession(
        _ context: SessionContext,
        onEvent: @escaping EventHandler
    ) async {
        await cancelPendingTasks(waitForCancellation: true)
        await cancelAttributionDrain(waitForCancellation: true)
        self.sessionContext = context
        self.eventHandler = onEvent
        self.pendingChunkTasks = []
        self.pendingAttributionResults = []
        self.nextChunkSequence = [:]
        self.speakerDetection = [
            .system: context.systemSpeakerDetection,
            .microphone: context.microphoneSpeakerDetection,
        ]
        self.speakerDetectionGeneration = [.system: 0, .microphone: 0]
        self.chunkResultBuffer.reset()
    }

    func setSpeakerDetection(_ enabled: Bool, for source: AudioSource) {
        speakerDetection[source] = enabled
        speakerDetectionGeneration[source, default: 0] += 1
    }

    func finishSession() async {
        await cancelPendingTasks(waitForCancellation: false)
        await cancelAttributionDrain(waitForCancellation: false)
        self.sessionContext = nil
        self.eventHandler = nil
        self.pendingChunkTasks = []
        self.pendingAttributionResults = []
        self.nextChunkSequence = [:]
        self.speakerDetection = [:]
        self.speakerDetectionGeneration = [:]
        self.chunkResultBuffer.reset()
    }

    func enqueue(chunk: AudioChunker.AudioChunk, source: AudioSource) {
        guard let context = sessionContext else { return }
        let sequence = nextChunkSequence[source] ?? 0
        nextChunkSequence[source] = sequence + 1

        let taskID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.transcribeChunk(
                    chunk,
                    source: source,
                    context: context
                )
                await self.handleSuccess(
                    result,
                    chunk: chunk,
                    source: source,
                    sequence: sequence,
                    sessionID: context.id
                )
            } catch is CancellationError {
                // Expected during stop/cancel.
            } catch {
                await self.handleFailure(
                    error,
                    source: source,
                    sequence: sequence,
                    sessionID: context.id
                )
            }

            await self.removePendingChunkTask(id: taskID)
        }

        pendingChunkTasks.append(PendingChunkTask(id: taskID, task: task))
    }

    func waitForPendingTasksToDrain(timeout: Duration) async -> Bool {
        let startedAt = ContinuousClock.now
        while !pendingChunkTasks.isEmpty || attributionDrainTask != nil {
            if startedAt.duration(to: .now) > timeout {
                return false
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    func cancelPendingTasks(waitForCancellation: Bool) async {
        let tasks = pendingChunkTasks.map(\.task)
        pendingChunkTasks = []

        for task in tasks {
            task.cancel()
        }

        guard waitForCancellation else { return }
        for task in tasks {
            await task.value
        }
    }

    private func transcribeChunk(
        _ chunk: AudioChunker.AudioChunk,
        source: AudioSource,
        context: SessionContext
    ) async throws -> STTResult {
        let chunkURL = context.chunkFolderURL
            .appendingPathComponent("\(source.rawValue)-\(chunk.startMs)-\(chunk.endMs).wav")
        try writeChunkAudio(samples: chunk.samples, to: chunkURL)
        defer { try? FileManager.default.removeItem(at: chunkURL) }
        if let routedTranscriber = sttTranscriber as? any SpeechEngineRoutedTranscribing {
            return try await routedTranscriber.transcribe(
                audioPath: chunkURL.path,
                job: .meetingLiveChunk,
                speechEngine: context.speechEngine,
                onProgress: nil
            )
        }

        guard context.speechEngine == SpeechEngineSelection(engine: .parakeet) else {
            throw STTError.engineStartFailed(
                "Pinned \(context.speechEngine.engine.rawValue) speech engine cannot be honored by this transcriber."
            )
        }

        return try await sttTranscriber.transcribe(
            audioPath: chunkURL.path,
            job: .meetingLiveChunk,
            onProgress: nil
        )
    }

    private func writeChunkAudio(samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw MeetingAudioError.storageFailed("invalid chunk format")
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw MeetingAudioError.storageFailed("failed to allocate chunk buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { pointer in
                channelData[0].update(from: pointer.baseAddress!, count: samples.count)
            }
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }

    private func diarizeChunkIfEnabled(
        _ chunk: AudioChunker.AudioChunk,
        source: AudioSource
    ) async -> MacParakeetDiarizationResult? {
        guard speakerDetection[source] == true,
            let context = sessionContext,
            let diarizationService
        else { return nil }

        let audioURL = context.chunkFolderURL
            .appendingPathComponent("diarization-\(source.rawValue)-\(UUID().uuidString).wav")
        do {
            try writeChunkAudio(samples: chunk.samples, to: audioURL)
            defer { try? FileManager.default.removeItem(at: audioURL) }
            let result = try await diarizationService.diarize(audioURL: audioURL)
            return speakerDetection[source] == true ? result : nil
        } catch is CancellationError {
            return nil
        } catch {
            logger.error(
                "meeting_live_diarization_failed source=\(source.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func handleSuccess(
        _ result: STTResult,
        chunk: AudioChunker.AudioChunk,
        source: AudioSource,
        sequence: Int,
        sessionID: UUID
    ) async {
        guard sessionContext?.id == sessionID else { return }
        let transcriptWordCount = result.words.isEmpty
            ? Observability.wordCount(result.text)
            : result.words.count
        logger.info(
            "meeting_live_chunk_transcribed source=\(source.rawValue, privacy: .public) seq=\(sequence) words=\(transcriptWordCount) range=\(chunk.startMs)-\(chunk.endMs)"
        )

        let readyResults = chunkResultBuffer.receiveSuccess(
            sequence: sequence,
            source: source,
            chunk: chunk,
            result: result
        )
        guard !readyResults.isEmpty else { return }
        if enqueueForAttribution(readyResults, source: source, sessionID: sessionID) {
            await emit(.backpressureDrop)
        }
    }

    private func handleFailure(
        _ error: Error,
        source: AudioSource,
        sequence: Int,
        sessionID: UUID
    ) async {
        guard sessionContext?.id == sessionID else { return }

        let droppedByBackpressure =
            if case STTSchedulerError.droppedDueToBackpressure(job: .meetingLiveChunk) = error {
                true
            } else {
                false
            }

        if droppedByBackpressure {
            logger.notice(
                "meeting_live_chunk_backpressure_drop source=\(source.rawValue, privacy: .public) seq=\(sequence)"
            )
            await emit(.backpressureDrop)
        } else {
            logger.error(
                "meeting_live_chunk_failed source=\(source.rawValue, privacy: .public) seq=\(sequence) error=\(error.localizedDescription, privacy: .public)"
            )
            await emit(.transcriptionFailed(error.localizedDescription))
        }

        let readyResults = chunkResultBuffer.receiveFailure(sequence: sequence, source: source)
        guard !readyResults.isEmpty else { return }
        if enqueueForAttribution(readyResults, source: source, sessionID: sessionID) {
            await emit(.backpressureDrop)
        }
    }

    /// Returns true when one or more newest results were dropped. Keeping the
    /// older prefix preserves per-source transcript continuity while bounding
    /// live diarization independently from the STT scheduler's queue.
    private func enqueueForAttribution(
        _ readyResults: [MeetingChunkResultBuffer.ChunkResult],
        source: AudioSource,
        sessionID: UUID
    ) -> Bool {
        var dropped = false
        for ready in readyResults {
            guard pendingAttributionResults.count < Self.maximumPendingAttributionResults else {
                dropped = true
                continue
            }
            pendingAttributionResults.append(
                PendingAttributionResult(
                    sessionID: sessionID,
                    source: source,
                    chunk: ready.chunk,
                    result: ready.result
                ))
        }
        startAttributionDrainIfNeeded()
        return dropped
    }

    private func startAttributionDrainIfNeeded() {
        guard attributionDrainTask == nil, !pendingAttributionResults.isEmpty else { return }
        let drainID = UUID()
        attributionDrainID = drainID
        attributionDrainTask = Task { [weak self] in
            await self?.drainAttributionResults(drainID: drainID)
        }
    }

    private func drainAttributionResults(drainID: UUID) async {
        while !Task.isCancelled, !pendingAttributionResults.isEmpty {
            let pending = pendingAttributionResults.removeFirst()
            let diarization = await diarizeChunkIfEnabled(pending.chunk, source: pending.source)
            guard !Task.isCancelled, sessionContext?.id == pending.sessionID else { continue }
            let result = OrderedResult(
                source: pending.source,
                chunk: pending.chunk,
                result: pending.result,
                diarization: diarization,
                speakerDetectionGeneration: speakerDetectionGeneration[pending.source, default: 0]
            )
            await emit(.orderedResults([result]))
        }
        guard attributionDrainID == drainID else { return }
        attributionDrainTask = nil
        attributionDrainID = nil
        startAttributionDrainIfNeeded()
    }

    private func cancelAttributionDrain(waitForCancellation: Bool) async {
        let task = attributionDrainTask
        attributionDrainTask = nil
        attributionDrainID = nil
        pendingAttributionResults = []
        task?.cancel()
        if waitForCancellation {
            await task?.value
        }
    }

    private func emit(_ event: Event) async {
        guard let eventHandler else { return }
        await eventHandler(event)
    }

    private func removePendingChunkTask(id: UUID) {
        pendingChunkTasks.removeAll { $0.id == id }
    }
}

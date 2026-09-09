import CoreML
import FluidAudio
import Foundation

/// One workflow seam for real acoustic evidence and deterministic test evidence.
public protocol OfflineSpeechActivityDetecting: Sendable {
    func quietRanges(audioURL: URL) async throws -> [ReadingTurnTimeRange]
}

/// Reads only the already installed VAD model. No ModelHub/network fallback.
/// Missing model/audio is handled by the workflow's conservative evidence path.
public actor OfflineSpeechActivityDetector: OfflineSpeechActivityDetecting {
    public init() {}

    public func quietRanges(audioURL: URL) async throws -> [ReadingTurnTimeRange] {
        try Task.checkCancellation()
        let path = AppPaths.fluidAudioModelDirectory(for: .vad)
            .appendingPathComponent(ModelNames.VAD.sileroVadFile)
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: path, configuration: configuration)
        let manager = VadManager(config: VadConfig(computeUnits: .cpuOnly), vadModel: model)
        let samples = try AudioConverter().resampleAudioFile(audioURL)
        var state = await manager.makeStreamState()
        var probabilities: [Float] = []
        // Use frame inference, not streaming start/end events. Checking between
        // frames keeps cancellation bounded and avoids retaining every model
        // state and a second complete array of audio chunks.
        for start in stride(from: 0, to: samples.count, by: VadManager.chunkSize) {
            try Task.checkCancellation()
            let end = min(samples.count, start + VadManager.chunkSize)
            let result = try await manager.processStreamingChunk(Array(samples[start..<end]), state: state)
            state = result.state
            probabilities.append(result.probability)
        }
        try Task.checkCancellation()
        return Self.quietRanges(probabilities: probabilities)
    }

    /// Only low-posterior frames establish silence. Intermediate probabilities
    /// remain uncertain. No padding, maximum-duration cuts, or minimum-speech
    /// filtering is applied. The assembler only uses a whole quiet interval
    /// between recognized words, never a low probability inside a word.
    static func quietRanges(probabilities: [Float]) -> [ReadingTurnTimeRange] {
        let frameMs = VadManager.chunkSize * 1_000 / VadManager.sampleRate
        var ranges: [ReadingTurnTimeRange] = []
        var start: Int?
        for (index, probability) in probabilities.enumerated() {
            if probability.isFinite && probability <= 0.1 {
                if start == nil { start = index * frameMs }
            } else if let value = start {
                ranges.append(ReadingTurnTimeRange(startMs: value, endMs: index * frameMs))
                start = nil
            }
        }
        if let start {
            ranges.append(ReadingTurnTimeRange(startMs: start, endMs: probabilities.count * frameMs))
        }
        return ranges
    }
}

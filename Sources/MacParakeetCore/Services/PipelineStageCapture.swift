#if DEBUG
import FluidAudio
import Foundation

/// Opt-in snapshots at the real file-transcription boundaries. No inference or
/// attribution changes. Audio, text and embeddings stay outside the repository.
struct PipelineStageCapture: Sendable {
    @TaskLocal static var current: PipelineStageCapture?

    struct CaptureError: Error {
        let underlying: Error
    }

    let directory: URL

    static func start(transcriptionID: UUID) throws -> Self? {
        guard let root = ProcessInfo.processInfo.environment["MACPARAKEET_DEBUG_PIPELINE_OUTPUT"],
              !root.isEmpty else { return nil }
        let directory = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("\(transcriptionID.uuidString)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return Self(directory: directory)
    }

    func write<T: Encodable>(_ value: T, to name: String) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.nonConformingFloatEncodingStrategy = .convertToString(
                positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
            )
            let url = directory.appendingPathComponent(name)
            try encoder.encode(value).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw CaptureError(underlying: error)
        }
    }

    func copyAudio(from url: URL) throws {
        let destination = directory.appendingPathComponent("01-prepared-audio.wav")
        try FileManager.default.copyItem(at: url, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    func writeSTT(_ result: STTResult) throws {
        struct Snapshot: Encodable {
            let text: String
            let words: [WordTimestamp]
            let language: String?
            let engine: String
            let engineVariant: String?
        }
        try write(Snapshot(
            text: result.text,
            words: result.words.map {
                WordTimestamp(word: $0.word, startMs: $0.startMs, endMs: $0.endMs, confidence: $0.confidence)
            },
            language: result.language, engine: result.engine.rawValue, engineVariant: result.engineVariant
        ), to: "02-stt.json")
    }

    /// Exact SDK return order, IDs, float seconds, scores and available embeddings.
    /// This is the SDK's final output, not its internal segmentation tensors.
    func writeFluidAudio(_ result: DiarizationResult) throws {
        struct Segment: Encodable {
            let id: UUID
            let speakerId: String
            let startTimeSeconds: Float
            let endTimeSeconds: Float
            let qualityScore: Float
            let embedding: [Float]
        }
        struct Snapshot: Encodable {
            let segments: [Segment]
            let speakerDatabase: [String: [Float]]?
            let chunkEmbeddings: [ChunkEmbedding]?
            let timings: PipelineTimings?
        }
        try write(Snapshot(
            segments: result.segments.map {
                Segment(id: $0.id, speakerId: $0.speakerId,
                        startTimeSeconds: $0.startTimeSeconds, endTimeSeconds: $0.endTimeSeconds,
                        qualityScore: $0.qualityScore, embedding: $0.embedding)
            },
            speakerDatabase: result.speakerDatabase,
            chunkEmbeddings: result.chunkEmbeddings, timings: result.timings
        ), to: "03-fluidaudio-result.json")
    }
}
#endif

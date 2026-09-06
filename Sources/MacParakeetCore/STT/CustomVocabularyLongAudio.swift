import AVFoundation
import FluidAudio
import Foundation

public struct CustomVocabularyEdit: Sendable {
    public let utf8Range: Range<Int>
    public let text: String
    public let startTime: Double

    public init(utf8Range: Range<Int>, text: String, startTime: Double) {
        self.utf8Range = utf8Range
        self.text = text
        self.startTime = startTime
    }

    /// Apply source-relative edits without rebuilding unrelated transcript text.
    static func applying(_ edits: [Self], to transcript: String) throws -> String {
        let source = Array(transcript.utf8)
        var output: [UInt8] = []
        var cursor = 0
        for edit in edits.sorted(by: { $0.utf8Range.lowerBound < $1.utf8Range.lowerBound }) {
            let range = edit.utf8Range
            guard range.lowerBound >= cursor, range.upperBound <= source.count, !range.isEmpty,
                let original = String(bytes: source[range], encoding: .utf8),
                String(bytes: source[cursor..<range.lowerBound], encoding: .utf8) != nil
            else { throw CustomVocabularyBoostingError.invalidCandidateRange }
            output.append(contentsOf: source[cursor..<range.lowerBound])
            let prefix = String(original.unicodeScalars.prefix { CharacterSet.punctuationCharacters.contains($0) })
            let suffix = String(
                String.UnicodeScalarView(
                    original.unicodeScalars.reversed().prefix {
                        CharacterSet.punctuationCharacters.contains($0)
                    }.reversed()))
            let replacement =
                (edit.text.hasPrefix(prefix) ? "" : prefix) + edit.text
                + (edit.text.hasSuffix(suffix) ? "" : suffix)
            output.append(contentsOf: replacement.utf8)
            cursor = range.upperBound
        }
        output.append(contentsOf: source[cursor...])
        guard let result = String(bytes: output, encoding: .utf8) else {
            throw CustomVocabularyBoostingError.invalidCandidateRange
        }
        return result
    }
}

/// Bounded overlapping windows. Candidate ownership uses the original start time,
/// so a term across a core boundary is applied once, with context on both sides.
/// All windows refer to the unchanged base transcript; failures discard all edits.
struct CustomVocabularyLongAudio {
    static let coreSeconds: Double = 120
    static let contextSeconds: Double = 15

    struct Window: Sendable {
        let audioStart: Double
        let audioEnd: Double
        let core: Range<Double>
        let utf8Offset: Int
        let text: String
        let timings: [TokenTiming]
    }

    static func windows(for result: ASRResult) throws -> [Window] {
        let timings = STTWordTimingBuilder.words(from: result.tokenTimings)
        let parts = result.text.split(whereSeparator: \.isWhitespace)
        guard !timings.isEmpty, parts.count == timings.count else {
            throw CustomVocabularyBoostingError.unavailableAudioOrTimings
        }
        guard zip(parts, timings).allSatisfy({ String($0.0) == $0.1.word }),
            timings.allSatisfy({ $0.startMs >= 0 && $0.endMs >= $0.startMs }),
            zip(timings, timings.dropFirst()).allSatisfy({ $0.startMs <= $1.startMs })
        else { throw CustomVocabularyBoostingError.unavailableAudioOrTimings }

        let buckets = Set(timings.map { Int((Double($0.startMs) / 1_000) / coreSeconds) }).sorted()
        return buckets.compactMap { bucket in
            let start = Double(bucket) * coreSeconds
            let audioStart = max(0, start - contextSeconds)
            let audioEnd = start + coreSeconds + contextSeconds
            guard let first = timings.firstIndex(where: { Double($0.startMs) / 1_000 >= audioStart }),
                let last = timings.lastIndex(where: { Double($0.endMs) / 1_000 <= audioEnd }), first <= last
            else { return nil }
            let range = parts[first].startIndex..<parts[last].endIndex
            let local = (first...last).map { index in
                TokenTiming(
                    token: "▁\(parts[index])", tokenId: -1 - index,
                    startTime: Double(timings[index].startMs) / 1_000 - audioStart,
                    endTime: Double(timings[index].endMs) / 1_000 - audioStart,
                    confidence: Float(timings[index].confidence)
                )
            }
            return Window(
                audioStart: audioStart, audioEnd: audioEnd, core: start..<(start + coreSeconds),
                utf8Offset: result.text.utf8.distance(from: result.text.utf8.startIndex, to: range.lowerBound),
                text: String(result.text[range]), timings: local
            )
        }
    }

    static func rescore(
        result: ASRResult,
        vocabulary: CustomVocabularyBoostingVocabulary,
        rescorer: any CustomVocabularyRescoring,
        inferenceGate: ANEInferenceGate,
        loadSamples: (Double, Double) throws -> [Float]
    ) async throws -> CustomVocabularyRescoringResult {
        let windows = try windows(for: result)
        guard !windows.isEmpty else { throw CustomVocabularyBoostingError.unavailableAudioOrTimings }
        var edits: [CustomVocabularyEdit] = []
        for window in windows {
            try Task.checkCancellation()
            let samples = try loadSamples(window.audioStart, window.audioEnd)
            guard !samples.isEmpty else { throw CustomVocabularyBoostingError.unavailableAudioOrTimings }
            let rescored = try await inferenceGate.withExclusiveAccess {
                try await rescorer.rescore(
                    CustomVocabularyRescoringRequest(
                        transcript: window.text, tokenTimings: window.timings,
                        audioSamples: samples, vocabulary: vocabulary
                    ))
            }
            try Task.checkCancellation()
            for edit in rescored.edits where window.core.contains(edit.startTime + window.audioStart) {
                guard edit.utf8Range.lowerBound >= 0, edit.utf8Range.upperBound <= window.text.utf8.count else {
                    throw CustomVocabularyBoostingError.invalidCandidateRange
                }
                let range =
                    (edit.utf8Range.lowerBound + window.utf8Offset)..<(edit.utf8Range.upperBound + window.utf8Offset)
                guard !edits.contains(where: { $0.utf8Range.overlaps(range) }) else { continue }
                edits.append(
                    CustomVocabularyEdit(
                        utf8Range: range, text: edit.text, startTime: edit.startTime + window.audioStart))
            }
        }
        return CustomVocabularyRescoringResult(
            text: try CustomVocabularyEdit.applying(edits, to: result.text),
            detectedTerms: [], appliedTerms: edits.map(\.text), replacementCount: edits.count, edits: edits
        )
    }

    /// Read a bounded source-rate buffer and convert it with the existing audio path.
    static func samples(file: AVAudioFile, from start: Double, to end: Double) throws -> [Float] {
        try Task.checkCancellation()
        let rate = file.processingFormat.sampleRate
        guard rate.isFinite, rate > 0, start >= 0, end > start,
            end - start <= CustomVocabularyBoostingConfiguration.maxSidecarAudioSeconds,
            start * rate < Double(file.length)
        else { throw CustomVocabularyBoostingError.unavailableAudioOrTimings }
        let first = AVAudioFramePosition(start * rate)
        let available = min(Double(file.length - first), ((end - start) * rate).rounded(.up))
        guard let count = AVAudioFrameCount(exactly: available), count > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: min(count, 65_536))
        else { throw CustomVocabularyBoostingError.unavailableAudioOrTimings }
        file.framePosition = first
        var mono: [Float] = []
        mono.reserveCapacity(Int(count))
        while mono.count < Int(count) {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: min(buffer.frameCapacity, count - AVAudioFrameCount(mono.count)))
            guard buffer.frameLength > 0 else { break }
            guard let samples = AudioChunker.extractSamples(from: buffer) else {
                throw CustomVocabularyBoostingError.unavailableAudioOrTimings
            }
            mono.append(contentsOf: samples)
        }
        try Task.checkCancellation()
        return AudioChunker.resample(samples: mono, fromRate: Int(rate))
    }
}

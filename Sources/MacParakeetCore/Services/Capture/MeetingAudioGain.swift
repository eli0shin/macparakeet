import AVFAudio
import Foundation

/// Non-destructive gain used only by meeting speech processing. Raw meeting
/// tracks and the playback artifact stay unchanged so a later retranscription
/// can use different values.
public struct MeetingAudioGain: Sendable, Equatable, Codable {
    public static let microphoneKey = "meetingMicrophoneAudioGainDB"
    public static let systemKey = "meetingSystemAudioGainDB"
    public static let decibelRange: ClosedRange<Double> = -24...24
    public static let standard = Self(microphoneDB: 0, systemDB: 0)

    public let microphoneDB: Double
    public let systemDB: Double

    public init(microphoneDB: Double, systemDB: Double) {
        self.microphoneDB = Self.clamp(microphoneDB)
        self.systemDB = Self.clamp(systemDB)
    }

    public static func current(defaults: UserDefaults = .standard) -> Self {
        Self(
            microphoneDB: defaults.object(forKey: microphoneKey) as? Double ?? 0,
            systemDB: defaults.object(forKey: systemKey) as? Double ?? 0
        )
    }

    public func decibels(for source: AudioSource) -> Double {
        switch source {
        case .microphone: microphoneDB
        case .system: systemDB
        }
    }

    public func applying(to samples: [Float], source: AudioSource) -> [Float] {
        Self.apply(decibels: decibels(for: source), to: samples)
    }

    static func apply(decibels: Double, to samples: [Float]) -> [Float] {
        guard decibels != 0, !samples.isEmpty else { return samples }
        let multiplier = Float(pow(10, decibels / 20))
        return samples.map { min(1, max(-1, $0 * multiplier)) }
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(decibelRange.upperBound, max(decibelRange.lowerBound, value))
    }
}

/// Applies meeting gain to the converted 16 kHz Float32 WAV used by STT and
/// diarization. The caller owns and removes the returned file.
struct MeetingAudioGainFileProcessor: Sendable {
    func process(wavURL: URL, decibels: Double) async throws -> URL {
        guard decibels != 0 else { return wavURL }
        return try await Task.detached(priority: .utility) {
            let input = try AVAudioFile(forReading: wavURL)
            let format = input.processingFormat
            guard format.commonFormat == .pcmFormatFloat32 else {
                throw AudioProcessorError.conversionFailed("Meeting gain requires Float32 WAV audio.")
            }

            let outputURL = wavURL.deletingLastPathComponent()
                .appendingPathComponent("\(UUID().uuidString)-meeting-gain.wav")
            var succeeded = false
            defer {
                if !succeeded {
                    try? FileManager.default.removeItem(at: outputURL)
                }
            }

            let output = try AVAudioFile(
                forWriting: outputURL,
                settings: input.fileFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: format.isInterleaved
            )
            let multiplier = Float(pow(10, decibels / 20))
            let capacity = AVAudioFrameCount(16_384)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                throw AudioProcessorError.conversionFailed("Could not allocate a meeting gain buffer.")
            }

            while input.framePosition < input.length {
                try input.read(into: buffer, frameCount: capacity)
                guard buffer.frameLength > 0 else { break }
                guard let channels = buffer.floatChannelData else {
                    throw AudioProcessorError.conversionFailed("Could not read Float32 meeting audio.")
                }
                let frameCount = Int(buffer.frameLength)
                for channelIndex in 0..<Int(format.channelCount) {
                    let channel = channels[channelIndex]
                    for frameIndex in 0..<frameCount {
                        channel[frameIndex] = min(1, max(-1, channel[frameIndex] * multiplier))
                    }
                }
                try output.write(from: buffer)
            }

            succeeded = true
            return outputURL
        }.value
    }
}

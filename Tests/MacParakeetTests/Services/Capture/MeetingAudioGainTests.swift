import AVFAudio
import Foundation
import XCTest
@testable import MacParakeetCore

final class MeetingAudioGainTests: XCTestCase {
    func testPreferencesDefaultClampAndLiveChanges() throws {
        let name = "meeting-gain-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertEqual(MeetingAudioGain.current(defaults: defaults), .standard)
        defaults.set(12.0, forKey: MeetingAudioGain.microphoneKey)
        defaults.set(-6.0, forKey: MeetingAudioGain.systemKey)
        XCTAssertEqual(
            MeetingAudioGain.current(defaults: defaults),
            MeetingAudioGain(microphoneDB: 12, systemDB: -6)
        )
        XCTAssertEqual(MeetingAudioGain(microphoneDB: 100, systemDB: -.infinity).microphoneDB, 24)
        XCTAssertEqual(MeetingAudioGain(microphoneDB: 100, systemDB: -.infinity).systemDB, 0)
    }

    func testSampleGainUsesDecibelsAndClips() {
        let gain = MeetingAudioGain(microphoneDB: 6, systemDB: -6)
        let boosted = gain.applying(to: [0.25, -0.75], source: .microphone)
        XCTAssertEqual(boosted[0], 0.4988, accuracy: 0.001)
        XCTAssertEqual(boosted[1], -1, accuracy: 0.001)

        let reduced = gain.applying(to: [1, -1], source: .system)
        XCTAssertEqual(reduced[0], 0.5012, accuracy: 0.001)
        XCTAssertEqual(reduced[1], -0.5012, accuracy: 0.001)
    }

    @MainActor
    func testLiveOrchestratorAppliesPerSourceGainAfterMicConditioning() async {
        let orchestrator = CaptureOrchestrator()
        let conditioner = PassthroughMicConditioner()
        let gain = MeetingAudioGain(microphoneDB: 6, systemDB: -6)
        var chunks: [CaptureOrchestratorChunk] = []
        for _ in 0..<10 {
            let microphoneOutput = await orchestrator.ingest(
                samples: Array(repeating: 0.25, count: 8_000),
                source: .microphone,
                hostTime: nil,
                micConditioner: conditioner,
                audioGain: gain
            )
            chunks += microphoneOutput.chunks
            let systemOutput = await orchestrator.ingest(
                samples: Array(repeating: 1, count: 8_000),
                source: .system,
                hostTime: nil,
                micConditioner: conditioner,
                audioGain: gain
            )
            chunks += systemOutput.chunks
        }

        let microphone = try? XCTUnwrap(chunks.first { $0.source == .microphone })
        let system = try? XCTUnwrap(chunks.first { $0.source == .system })
        XCTAssertEqual(microphone?.chunk.samples.first ?? 0, 0.4988, accuracy: 0.001)
        XCTAssertEqual(system?.chunk.samples.first ?? 0, 0.5012, accuracy: 0.001)
    }

    func testFileProcessorCreatesAdjustedCopyAndKeepsInput() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-gain-file-test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let inputURL = folder.appendingPathComponent("input.wav")
        let format = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
        )
        var input: AVAudioFile? = try AVAudioFile(
            forWriting: inputURL,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4),
            "Expected an input PCM buffer"
        )
        buffer.frameLength = 4
        let channel = try XCTUnwrap(buffer.floatChannelData?[0], "Expected Float32 input samples")
        channel[0] = 0.25
        channel[1] = -0.25
        channel[2] = 0.75
        channel[3] = -0.75
        try input?.write(from: buffer)
        input = nil

        let outputURL = try await MeetingAudioGainFileProcessor().process(wavURL: inputURL, decibels: 6)
        XCTAssertNotEqual(outputURL, inputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inputURL.path))

        let output = try AVAudioFile(forReading: outputURL)
        let result = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: 4),
            "Expected an output PCM buffer"
        )
        try output.read(into: result)
        let samples = try XCTUnwrap(result.floatChannelData?[0], "Expected Float32 output samples")
        XCTAssertEqual(samples[0], 0.4988, accuracy: 0.001)
        XCTAssertEqual(samples[1], -0.4988, accuracy: 0.001)
        XCTAssertEqual(samples[2], 1, accuracy: 0.001)
        XCTAssertEqual(samples[3], -1, accuracy: 0.001)
    }
}

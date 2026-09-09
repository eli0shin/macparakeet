import Foundation
import XCTest

@testable import MacParakeetCore

final class LiveChunkTranscriberTests: XCTestCase {
    func testLiveDiarizationBacklogDropsNewestResultsAtBound() async throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-chunk-transcriber-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let events = LiveChunkEventRecorder()
        let transcriber = LiveChunkTranscriber(
            sttTranscriber: ImmediateLiveChunkSTTTranscriber(),
            diarizationService: SlowLiveChunkDiarizationService()
        )
        await transcriber.startSession(
            LiveChunkTranscriber.SessionContext(
                id: UUID(),
                chunkFolderURL: folderURL,
                speechEngine: SpeechEngineSelection(engine: .parakeet),
                systemSpeakerDetection: true,
                microphoneSpeakerDetection: false
            )
        ) { event in
            await events.record(event)
        }

        for sequence in 0..<30 {
            await transcriber.enqueue(
                chunk: AudioChunker.AudioChunk(
                    samples: [0.1],
                    startMs: sequence * 1_000,
                    endMs: (sequence + 1) * 1_000
                ),
                source: .system
            )
        }

        for _ in 0..<200 where await events.backpressureDropCount == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }

        let backpressureDropCount = await events.backpressureDropCount
        XCTAssertGreaterThan(backpressureDropCount, 0)
        await transcriber.finishSession()
    }
}

private actor LiveChunkEventRecorder {
    private(set) var backpressureDropCount = 0

    func record(_ event: LiveChunkTranscriber.Event) {
        if case .backpressureDrop = event {
            backpressureDropCount += 1
        }
    }
}

private struct ImmediateLiveChunkSTTTranscriber: STTTranscribing {
    func transcribe(
        audioPath: String,
        job: STTJobKind,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> STTResult {
        STTResult(
            text: "word",
            words: [TimestampedWord(word: "word", startMs: 0, endMs: 500, confidence: 0.9)]
        )
    }
}

private actor SlowLiveChunkDiarizationService: DiarizationServiceProtocol {
    func diarize(audioURL: URL) async throws -> MacParakeetDiarizationResult {
        try await Task.sleep(for: .seconds(2))
        return MacParakeetDiarizationResult(segments: [], speakerCount: 0, speakers: [])
    }

    func prepareModels(onProgress: (@Sendable (String) -> Void)?) async throws {}

    func isReady() async -> Bool { true }
}

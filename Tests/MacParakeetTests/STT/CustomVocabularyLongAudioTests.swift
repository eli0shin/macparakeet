import AVFoundation
import FluidAudio
@testable import MacParakeetCore
import XCTest

final class CustomVocabularyLongAudioTests: XCTestCase {
    func testEditsPreserveUnicodePunctuationAndUnchangedWhitespace() throws {
        let text = "Élio said:  MAC Parakeet!\nNext line."
        let range = try XCTUnwrap(text.range(of: "MAC Parakeet!"))
        let bytes =
            text.utf8.distance(
                from: text.startIndex, to: range.lowerBound)..<text.utf8.distance(
                from: text.startIndex, to: range.upperBound)
        let output = try CustomVocabularyEdit.applying(
            [
                CustomVocabularyEdit(utf8Range: bytes, text: "MacParakeet", startTime: 0)
            ], to: text)
        XCTAssertEqual(output, "Élio said:  MacParakeet!\nNext line.")
    }

    func testInvalidAndOverlappingEditsFailRatherThanDropSourceText() {
        XCTAssertThrowsError(
            try CustomVocabularyEdit.applying(
                [
                    CustomVocabularyEdit(utf8Range: 1..<2, text: "x", startTime: 0)
                ], to: "Élio"))
        XCTAssertThrowsError(
            try CustomVocabularyEdit.applying(
                [
                    CustomVocabularyEdit(utf8Range: 0..<3, text: "one", startTime: 0),
                    CustomVocabularyEdit(utf8Range: 2..<4, text: "two", startTime: 0),
                ], to: "word"))
    }

    func testLongAudioWindowsUseContextAcrossBoundariesAndApplyPhraseOnce() async throws {
        let base = Self.result([
            ("Hello", 0, 1), ("MAC", 119, 120), ("Parakeet", 120, 121),
            ("again", 240, 241), ("goodbye.", 350, 351),
        ])
        let windows = try CustomVocabularyLongAudio.windows(for: base)
        XCTAssertEqual(windows.count, 3)
        XCTAssertTrue(windows[0].text.contains("MAC Parakeet"))
        XCTAssertTrue(windows[1].text.contains("MAC Parakeet"))
        XCTAssertTrue(windows.allSatisfy { $0.audioEnd - $0.audioStart <= 150 })
        let output = try await CustomVocabularyLongAudio.rescore(
            result: base, vocabulary: .init(terms: ["MacParakeet"]),
            rescorer: PhraseRescorer(), inferenceGate: ANEInferenceGate(serializationRequired: false),
            loadSamples: { _, _ in [0.1] }
        )
        XCTAssertEqual(output.text, "Hello MacParakeet again goodbye.")
        XCTAssertEqual(output.replacementCount, 1)
        XCTAssertEqual(output.edits.first?.startTime, 119)
    }

    func testLateWindowFailureDoesNotReturnPartialCorrections() async {
        let base = Self.result([("MAC", 1, 2), ("Parakeet", 2, 3), ("later", 350, 351)])
        do {
            _ = try await CustomVocabularyLongAudio.rescore(
                result: base, vocabulary: .init(terms: ["MacParakeet"]),
                rescorer: PhraseRescorer(), inferenceGate: ANEInferenceGate(serializationRequired: false),
                loadSamples: { start, _ in
                    if start > 100 { throw CustomVocabularyBoostingError.unavailableAudioOrTimings }
                    return [0.1]
                }
            )
            XCTFail("Expected failure; runtime must retain the complete base result")
        } catch {}
        XCTAssertEqual(base.text, "MAC Parakeet later")
    }

    func testCorrectionDoesNotMatchSameWordMinutesLaterForTiming() throws {
        let base = Self.result([
            ("MAC", 1, 2), ("Parakeet", 2, 3), ("is", 3, 4),
            ("useful", 4, 5), ("MacParakeet", 350, 351),
        ])
        let edits = [CustomVocabularyEdit(utf8Range: 0..<12, text: "MacParakeet", startTime: 1)]
        let timings = try CustomVocabularyTiming.applying(
            edits, to: base.text, tokenTimings: try XCTUnwrap(base.tokenTimings))
        let words = STTWordTimingBuilder.words(from: timings)
        XCTAssertEqual(words.map(\.word), ["MacParakeet", "is", "useful", "MacParakeet"])
        XCTAssertEqual(words.map(\.startMs), [1_000, 3_000, 4_000, 350_000])
        XCTAssertEqual(words.map(\.endMs), [3_000, 4_000, 5_000, 351_000])
    }

    func testMismatchedTimingsFailRatherThanReconstructDifferentText() {
        let base = ASRResult(
            text: "One different transcript", confidence: 1, duration: 1, processingTime: 0,
            tokenTimings: [TokenTiming(token: "▁One", tokenId: 0, startTime: 0, endTime: 1, confidence: 1)])
        XCTAssertThrowsError(try CustomVocabularyLongAudio.windows(for: base))
    }

    func testBoundedAudioReaderSeeksAndClampsAtEnd() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vocab-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000))
            buffer.frameLength = 32_000
            let channel = try XCTUnwrap(buffer.floatChannelData?[0])
            for index in 0..<32_000 { channel[index] = index < 16_000 ? 0.1 : 0.2 }
            try file.write(from: buffer)
        }
        let file = try AVAudioFile(forReading: url)
        let samples = try CustomVocabularyLongAudio.samples(file: file, from: 1, to: 3)
        XCTAssertEqual(samples.count, 16_000)
        XCTAssertEqual(samples[0], 0.2, accuracy: 0.001)
        XCTAssertThrowsError(try CustomVocabularyLongAudio.samples(file: file, from: 0, to: 301))
    }

    private static func result(_ words: [(String, Double, Double)]) -> ASRResult {
        ASRResult(
            text: words.map { $0.0 }.joined(separator: " "), confidence: 1,
            duration: words.last?.2 ?? 0, processingTime: 0,
            tokenTimings: words.enumerated().map { index, word in
                TokenTiming(token: "▁\(word.0)", tokenId: index, startTime: word.1, endTime: word.2, confidence: 1)
            })
    }
}

private struct PhraseRescorer: CustomVocabularyRescoring {
    func rescore(_ request: CustomVocabularyRescoringRequest) async throws -> CustomVocabularyRescoringResult {
        guard let range = request.transcript.range(of: "MAC Parakeet"),
            let timing = request.tokenTimings?.first(where: { $0.token == "▁MAC" })
        else {
            return .init(text: request.transcript, detectedTerms: [], appliedTerms: [], replacementCount: 0)
        }
        let bytes =
            request.transcript.utf8.distance(
                from: request.transcript.startIndex, to: range.lowerBound)..<request.transcript.utf8.distance(
                from: request.transcript.startIndex, to: range.upperBound)
        let edit = CustomVocabularyEdit(utf8Range: bytes, text: "MacParakeet", startTime: timing.startTime)
        return .init(
            text: try CustomVocabularyEdit.applying([edit], to: request.transcript),
            detectedTerms: ["MacParakeet"], appliedTerms: ["MacParakeet"], replacementCount: 1, edits: [edit])
    }
}

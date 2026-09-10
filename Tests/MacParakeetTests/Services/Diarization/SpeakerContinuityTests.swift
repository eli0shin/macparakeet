import XCTest
@testable import MacParakeetCore

final class SpeakerContinuityTests: XCTestCase {
    private func word(_ start: Int, _ end: Int) -> WordTimestamp {
        WordTimestamp(word: "word", startMs: start, endMs: end, confidence: 0.9)
    }

    func testGapsLeadingAndTrailingWordsAndBoundaryOwnership() {
        let words = [word(0, 100), word(250, 300), word(500, 600), word(790, 800),
                     word(790, 801), word(800, 800), word(1_500, 1_600)]
        let regions = [SpeakerSegment(speakerId: "A", startMs: 100, endMs: 200),
                       SpeakerSegment(speakerId: "A", startMs: 350, endMs: 400),
                       SpeakerSegment(speakerId: "B", startMs: 800, endMs: 900)]
        let result = SpeakerMerger.alignWordsToSpeakerTurns(words: words, segments: regions)
        XCTAssertEqual(result.map(\.speakerId), ["A", "A", "A", "A", "B", "B", "B"])
        for (original, attributed) in zip(words, result) {
            XCTAssertEqual(original.word, attributed.word)
            XCTAssertEqual(original.startMs, attributed.startMs)
            XCTAssertEqual(original.endMs, attributed.endMs)
            XCTAssertEqual(original.confidence, attributed.confidence)
        }
        XCTAssertEqual(regions[0].endMs, 200)
    }

    func testLatestStartWinsWithoutReturningToStillActiveRegion() {
        let regions = [SpeakerSegment(speakerId: "A", startMs: 0, endMs: 2_000),
                       SpeakerSegment(speakerId: "B", startMs: 500, endMs: 600),
                       SpeakerSegment(speakerId: "A", startMs: 3_000, endMs: 3_100)]
        let result = SpeakerMerger.alignWordsToSpeakerTurns(
            words: [word(100, 200), word(490, 501), word(700, 800), word(2_900, 3_001)],
            segments: regions)
        XCTAssertEqual(result.map(\.speakerId), ["A", "B", "B", "A"])
    }

    func testNoValidRegionsDoesNotInventSpeaker() {
        let words = [word(0, 100)]
        XCTAssertEqual(SpeakerMerger.alignWordsToSpeakerTurns(words: words, segments: []), words)
        XCTAssertEqual(SpeakerMerger.alignWordsToSpeakerTurns(words: words, segments: [
            SpeakerSegment(speakerId: "A", startMs: 100, endMs: 100)
        ]), words)
    }
}

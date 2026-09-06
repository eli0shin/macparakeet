import XCTest
@testable import MacParakeetCore

final class MeetingTranscriptCleanerTests: XCTestCase {
    func testUsesSharedSafeCleanupWithoutChangingMeaningSensitiveFillers() {
        let raw = "uh   um uhm kubernetes ,  ist um klar."

        let cleaned = MeetingTranscriptCleaner.clean(
            rawTranscript: raw,
            customWords: [CustomWord(word: "kubernetes", replacement: "Kubernetes")]
        )

        XCTAssertEqual(cleaned, "Um uhm Kubernetes, ist um klar.")
        XCTAssertEqual(
            DeterministicFillerPolicy.removeFillers(from: raw),
            TextProcessingPipeline().removeFillers(from: raw)
        )
    }

    func testPreservesOrderedCustomWordReplacementSemantics() {
        let cleaned = MeetingTranscriptCleaner.clean(
            rawTranscript: "foo",
            customWords: [
                CustomWord(word: "foo", replacement: "bar"),
                CustomWord(word: "bar", replacement: "baz"),
            ]
        )

        XCTAssertEqual(cleaned, "Baz")
    }

    func testFillerOnlyTranscriptHasAuthoritativeEmptyCleanText() {
        XCTAssertEqual(
            MeetingTranscriptCleaner.clean(rawTranscript: "uh umm uhh", customWords: []),
            ""
        )
    }

    func testKeepsSnippetAndActionPhrasesAsTranscriptText() {
        let cleaned = MeetingTranscriptCleaner.clean(
            rawTranscript: "my signature press return",
            customWords: []
        )

        XCTAssertEqual(cleaned, "My signature press return")
    }
}

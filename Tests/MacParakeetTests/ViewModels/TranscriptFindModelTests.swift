import AppKit
import XCTest
@testable import MacParakeet
@testable import MacParakeetViewModels

@MainActor
final class TranscriptFindModelTests: XCTestCase {

    private func model(_ blocks: [String], query: String) async -> TranscriptFindModel {
        let model = TranscriptFindModel(debounce: .zero)
        model.setBlocks(blocks)
        model.setQuery(query)
        await settle(model)
        return model
    }

    private func settle(
        _ model: TranscriptFindModel,
        timeout: Duration = .seconds(2),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while model.isSearching, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertFalse(model.isSearching, "Search did not settle", file: file, line: line)
    }

    // MARK: - Empty / no-op queries

    func testEmptyQueryHasNoMatches() async {
        let model = await model(["the quick brown fox"], query: "")
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertNil(model.currentMatchIndex)
        XCTAssertNil(model.current)
        XCTAssertNil(model.displayPosition)
        XCTAssertFalse(model.hasMatches)
        XCTAssertFalse(model.isSearching)
    }

    func testWhitespaceOnlyQueryClearsPromptly() async {
        let model = await model(["the quick brown fox"], query: "fox")
        model.setQuery("   \n\t")
        XCTAssertEqual(model.query, "   \n\t")
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertNil(model.currentMatchIndex)
        XCTAssertFalse(model.isSearching)
    }

    func testQueryWithEdgeSpacesMatchesLiterally() async {
        let model = await model(["the cat sat", "there it is"], query: "the ")
        XCTAssertEqual(model.matches, [.init(blockIndex: 0, range: NSRange(location: 0, length: 4))])
    }

    func testQueryWithNoMatchesSettlesWithoutMatches() async {
        let model = await model(["the quick brown fox"], query: "zebra")
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertEqual(model.query, "zebra")
        XCTAssertNil(model.displayPosition)
        XCTAssertFalse(model.isSearching)
    }

    // MARK: - Basic matching

    func testSingleMatchRangeAndPosition() async {
        let model = await model(["the quick brown fox"], query: "quick")
        XCTAssertEqual(model.matches, [.init(blockIndex: 0, range: NSRange(location: 4, length: 5))])
        XCTAssertEqual(model.currentMatchIndex, 0)
        XCTAssertEqual(model.displayPosition?.current, 1)
        XCTAssertEqual(model.displayPosition?.total, 1)
    }

    func testMultipleMatchesWithinOneBlockAreOrdered() async {
        let model = await model(["hello Hello HELLO"], query: "hello")
        XCTAssertEqual(
            model.matches.map(\.range),
            [
                NSRange(location: 0, length: 5),
                NSRange(location: 6, length: 5),
                NSRange(location: 12, length: 5),
            ])
        XCTAssertTrue(model.matches.allSatisfy { $0.blockIndex == 0 })
        XCTAssertEqual(model.matchCount, 3)
    }

    func testMatchesAcrossBlocksAreGloballyOrdered() async {
        let model = await model(["alpha match", "no hit here", "match beta match"], query: "match")
        XCTAssertEqual(
            model.matches,
            [
                .init(blockIndex: 0, range: NSRange(location: 6, length: 5)),
                .init(blockIndex: 2, range: NSRange(location: 0, length: 5)),
                .init(blockIndex: 2, range: NSRange(location: 11, length: 5)),
            ])
    }

    func testMatchesAcrossCancellationChunkBoundary() async {
        let prefix = String(repeating: "x", count: 4_094)
        let model = await model([prefix + "engine engine"], query: "engine")
        XCTAssertEqual(
            model.matches.map(\.range),
            [
                NSRange(location: 4_094, length: 6),
                NSRange(location: 4_101, length: 6),
            ])
    }

    func testExpandingUnicodeMatchAcrossCancellationChunkBoundary() async {
        let prefix = String(repeating: "x", count: 4_095)
        let model = await model([prefix + "ffi"], query: "ﬃ")
        XCTAssertEqual(model.matches.map(\.range), [
            NSRange(location: 4_095, length: 3)
        ])
    }

    func testOverlappingCandidatesDoNotDoubleCount() async {
        let model = await model(["aaaa"], query: "aa")
        XCTAssertEqual(
            model.matches.map(\.range),
            [
                NSRange(location: 0, length: 2),
                NSRange(location: 2, length: 2),
            ])
    }

    // MARK: - Insensitivity

    func testCaseInsensitive() async {
        let lower = await model(["Title TITLE title"], query: "title")
        let upper = await model(["Title TITLE title"], query: "TITLE")
        XCTAssertEqual(lower.matches, upper.matches)
        XCTAssertEqual(lower.matchCount, 3)
    }

    func testDiacriticInsensitiveAndUTF16Ranges() async {
        let model = await model(["😀 café cafe Café"], query: "cafe")
        XCTAssertEqual(model.matchCount, 3)
        XCTAssertEqual(model.matches.first?.range, NSRange(location: 3, length: 4))
    }

    // MARK: - Navigation

    func testNextWrapsAround() async {
        let model = await model(["a a a"], query: "a")
        XCTAssertEqual(model.currentMatchIndex, 0)
        model.next(); XCTAssertEqual(model.currentMatchIndex, 1)
        model.next(); XCTAssertEqual(model.currentMatchIndex, 2)
        model.next(); XCTAssertEqual(model.currentMatchIndex, 0)
    }

    func testPrevWrapsAround() async {
        let model = await model(["a a a"], query: "a")
        XCTAssertEqual(model.currentMatchIndex, 0)
        model.prev(); XCTAssertEqual(model.currentMatchIndex, 2)
        model.prev(); XCTAssertEqual(model.currentMatchIndex, 1)
    }

    /// Matching time is intentionally outside this measurement. Once a very
    /// common query has settled, publishing the current result into the reading
    /// surface must fit within one 16 ms frame and must style only that result.
    func testCommonQueryDistantNavigationPresentationStaysWithinOneFrame() async {
        let block = String(repeating: "a ", count: 30)
        let blocks = Array(repeating: block, count: 7_680)
        let resultCount = 230_400
        let model = await model(blocks, query: "a")
        XCTAssertEqual(model.matchCount, resultCount)

        let clock = ContinuousClock()
        let start = clock.now
        model.prev() // Wrap from the first result to the distant final result.
        let current = try! XCTUnwrap(model.current)
        _ = TranscriptFindHighlight.attributed(
            blocks[current.blockIndex],
            current: current.range,
            baseFont: .body
        )
        let elapsed = start.duration(to: clock.now)

        XCTAssertEqual(model.displayPosition?.current, resultCount)
        XCTAssertEqual(current.blockIndex, blocks.count - 1)
        XCTAssertLessThan(elapsed, .milliseconds(16), "Result presentation took \(elapsed)")
    }

    func testDistantTextNavigationTargetStaysWithinOneFrame() {
        let text = String(repeating: "A long transcript line. ", count: 50_000)
        let firstRange = NSRange(location: 0, length: 4)
        let distantRange = NSRange(location: text.utf16.count - 10, length: 4)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 600,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        let layoutManager = try! XCTUnwrap(textView.layoutManager)
        let textContainer = try! XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        var highlighted = TranscriptFindTextView.applyHighlight(
            firstRange,
            in: text,
            layoutManager: layoutManager,
            replacing: nil
        )

        let clock = ContinuousClock()
        let start = clock.now
        highlighted = TranscriptFindTextView.applyHighlight(
            distantRange,
            in: text,
            layoutManager: layoutManager,
            replacing: highlighted
        )
        let progress = TranscriptFindHighlight.textNavigationProgress(
            current: distantRange,
            in: text
        )
        let elapsed = start.duration(to: clock.now)

        XCTAssertEqual(highlighted, distantRange)
        XCTAssertGreaterThan(progress ?? 0, 0.99)
        XCTAssertLessThan(elapsed, .milliseconds(16), "Navigation presentation took \(elapsed)")
    }

    func testTextNavigationRejectsStaleUnicodeRanges() {
        let text = "😀 café"
        XCTAssertNotNil(
            TranscriptFindHighlight.textNavigationProgress(
                current: NSRange(location: 3, length: 4),
                in: text
            )
        )
        XCTAssertNil(
            TranscriptFindHighlight.textNavigationProgress(
                current: NSRange(location: 1, length: 1),
                in: text
            ),
            "A range inside the emoji's UTF-16 surrogate pair must not be used"
        )
        XCTAssertNil(
            TranscriptFindHighlight.textNavigationProgress(
                current: NSRange(location: 99, length: 1),
                in: text
            )
        )
    }

    func testNavigationNoOpWhenNoMatches() async {
        let model = await model(["nothing here"], query: "zzz")
        model.next()
        XCTAssertNil(model.currentMatchIndex)
        model.prev()
        XCTAssertNil(model.currentMatchIndex)
    }

    func testCurrentMatchTracksCursor() async {
        let model = await model(["one two", "two three"], query: "two")
        XCTAssertEqual(model.current, .init(blockIndex: 0, range: NSRange(location: 4, length: 3)))
        model.next()
        XCTAssertEqual(model.current, .init(blockIndex: 1, range: NSRange(location: 0, length: 3)))
    }

    // MARK: - Asynchronous updates

    func testRapidEditsPublishEveryDraftAndOnlyLatestResults() async {
        let model = TranscriptFindModel(debounce: .milliseconds(20))
        model.setBlocks(["engineering engine", "energy"])

        for draft in ["e", "en", "eng", "engi", "engin", "engine"] {
            model.setQuery(draft)
            XCTAssertEqual(model.query, draft)
            XCTAssertTrue(model.isSearching)
        }

        await settle(model)
        XCTAssertEqual(model.query, "engine")
        XCTAssertEqual(
            model.matches,
            [
                .init(blockIndex: 0, range: NSRange(location: 0, length: 6)),
                .init(blockIndex: 0, range: NSRange(location: 12, length: 6)),
            ])
    }

    func testReplacedScanCannotPublishStaleResults() async {
        let model = TranscriptFindModel(debounce: .zero)
        model.setBlocks(Array(repeating: String(repeating: "alpha ", count: 2_000), count: 500))
        model.setQuery("alpha")
        await Task.yield()
        model.setQuery("missing")

        await settle(model)
        XCTAssertEqual(model.query, "missing")
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertFalse(model.isSearching)
    }

    func testClearedQueryCannotReceiveStaleResults() async {
        let model = TranscriptFindModel(debounce: .zero)
        model.setBlocks([String(repeating: "match ", count: 100_000)])
        model.setQuery("match")
        await Task.yield()
        model.clear()

        XCTAssertEqual(model.query, "")
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertFalse(model.isSearching)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(model.matches.isEmpty)
    }

    /// One frame at 60 Hz is 16.67 ms. The public-safe generated fixture is
    /// intentionally larger than a normal long meeting; each draft edit must
    /// stay under a conservative 16 ms main-thread budget because it only
    /// publishes state and schedules background matching.
    func testLongMeetingDraftEditHandlerStaysWithinOneFrame() async {
        let model = TranscriptFindModel(debounce: .milliseconds(50))
        let block = String(repeating: "Speaker discusses the engine roadmap and delivery. ", count: 30)
        model.setBlocks(Array(repeating: block, count: 10_000))
        let clock = ContinuousClock()

        for draft in ["e", "en", "eng", "engi", "engin", "engine"] {
            let start = clock.now
            model.setQuery(draft)
            let elapsed = start.duration(to: clock.now)
            XCTAssertLessThan(elapsed, .milliseconds(16), "Draft \(draft) blocked the main actor for \(elapsed)")
            XCTAssertEqual(model.query, draft)
        }
        model.clear()
    }

    // MARK: - Content changes

    func testChangingQueryResetsCursorToFirst() async {
        let model = await model(["one one", "two two two"], query: "one")
        model.next()
        XCTAssertEqual(model.currentMatchIndex, 1)
        model.setQuery("two")
        await settle(model)
        XCTAssertEqual(model.currentMatchIndex, 0)
        XCTAssertEqual(model.matchCount, 3)
    }

    func testSettingBlocksReRunsQuery() async {
        let model = TranscriptFindModel(debounce: .zero)
        model.setQuery("fox")
        await settle(model)
        XCTAssertTrue(model.matches.isEmpty)
        model.setBlocks(["the fox", "another fox"])
        await settle(model)
        XCTAssertEqual(model.matchCount, 2)
        XCTAssertEqual(model.currentMatchIndex, 0)
    }

    func testSettingBlocksPreservesCurrentMatchWhenStillPresent() async {
        let model = await model(["one", "two one", "three one"], query: "one")
        model.next()
        model.setBlocks(["one changed", "two one changed", "three one"])
        await settle(model)
        XCTAssertEqual(model.currentMatchIndex, 1)
        XCTAssertEqual(model.current, .init(blockIndex: 1, range: NSRange(location: 4, length: 3)))
    }

    func testSettingBlocksKeepsCurrentOrdinalWhenExactMatchDisappears() async {
        let model = await model(["one", "one", "one"], query: "one")
        model.next()
        model.setBlocks(["one", "missing", "one"])
        await settle(model)
        XCTAssertEqual(model.matchCount, 2)
        XCTAssertEqual(model.currentMatchIndex, 1)
        XCTAssertEqual(model.current, .init(blockIndex: 2, range: NSRange(location: 0, length: 3)))
    }

    func testSettingBlocksEmptyClearsMatchesWhileKeepingQuery() async {
        let model = await model(["fox", "another fox"], query: "fox")
        model.setBlocks([])
        XCTAssertEqual(model.query, "fox")
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertTrue(model.isSearching)
        await settle(model)
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertNil(model.currentMatchIndex)
    }

    func testClearEmptiesEverything() async {
        let model = await model(["a a a"], query: "a")
        model.clear()
        XCTAssertTrue(model.matches.isEmpty)
        XCTAssertEqual(model.query, "")
        XCTAssertNil(model.currentMatchIndex)
        XCTAssertFalse(model.isSearching)
    }
}

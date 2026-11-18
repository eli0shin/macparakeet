import AppKit
import SwiftUI
import XCTest
import MacParakeetCore
@testable import MacParakeet

/// A long Reading Turn, such as an undiarized in-person recording, renders as
/// bounded passage rows instead of one unbounded native text row.
@MainActor
final class ReadingTurnPassageTests: XCTestCase {
    func testShortTurnRendersAsOneRowWithTheCompleteText() {
        let turn = makeTurn(paragraphCount: 3, wordsPerParagraph: 20)
        let rows = identifiedReadingTurns([turn], words: makeWords(count: 60))

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].text, turn.text)
        XCTAssertFalse(rows[0].isContinuation)
        XCTAssertEqual(rows[0].startMs, turn.timeRange?.startMs)
    }

    func testLongTurnSplitsAtParagraphBreaksWithoutLosingText() {
        let words = makeWords(count: 16_000)
        let turn = makeTurn(paragraphCount: 267, wordsPerParagraph: 60, words: words)
        let rows = identifiedReadingTurns([turn], words: words)

        XCTAssertGreaterThan(rows.count, 50)
        XCTAssertEqual(rows.map(\.text).joined(separator: "\n\n"), turn.text)
        XCTAssertEqual(rows.filter { !$0.isContinuation }.count, 1)
        XCTAssertEqual(Set(rows.map(\.scrollID)).count, rows.count)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        for row in rows {
            XCTAssertLessThanOrEqual(row.text.utf16.count, ReadingTurnPassageLayout.targetPassageUTF16 * 2)
        }
        // Continuations start at their first paragraph's first word.
        XCTAssertEqual(rows[1].startMs.map { $0 > 0 }, true)
        XCTAssertEqual(rows.compactMap(\.startMs), rows.compactMap(\.startMs).sorted())
    }

    func testFormattedTurnWithoutParagraphBreaksSplitsAtWordBoundaries() {
        let words = makeWords(count: 16_000)
        let base = makeTurn(paragraphCount: 267, wordsPerParagraph: 60, words: words)
        let singleParagraph = base.paragraphs.map(\.text).joined(separator: " ")
        let turn = ReadingTurn(
            id: base.id,
            speakerId: base.speakerId,
            speakerLabel: base.speakerLabel,
            source: base.source,
            timeRange: base.timeRange,
            paragraphs: base.paragraphs,
            formattedText: singleParagraph,
            wordReferences: base.wordReferences
        )
        let rows = identifiedReadingTurns([turn], words: words)

        XCTAssertGreaterThan(rows.count, 50)
        XCTAssertEqual(rows.map(\.text).joined(separator: " "), singleParagraph)
        for row in rows {
            XCTAssertLessThanOrEqual(row.text.utf16.count, ReadingTurnPassageLayout.targetPassageUTF16)
        }
        // Reflowed AI text has no word mapping for continuation passages.
        XCTAssertEqual(rows[0].startMs, turn.timeRange?.startMs)
        XCTAssertTrue(rows.dropFirst().allSatisfy { $0.startMs == nil })
    }

    func testPlaybackFollowsTheLatestStartedPassageInsideTheTurn() {
        let words = makeWords(count: 16_000)
        let turn = makeTurn(paragraphCount: 267, wordsPerParagraph: 60, words: words)
        let rows = identifiedReadingTurns([turn], words: words)
        let index = ReadingTurnPlaybackIndex(turns: [turn], words: words)
        let target = rows[rows.count / 2]
        let targetStart = try! XCTUnwrap(target.startMs)

        XCTAssertEqual(readingTurnScrollTarget(for: targetStart + 100, in: rows, playbackIndex: index), target.scrollID)
        XCTAssertEqual(readingTurnScrollTarget(for: targetStart + 100, in: rows), target.scrollID)
        XCTAssertEqual(readingTurnScrollTarget(for: 0, in: rows, playbackIndex: index), rows[0].scrollID)
    }

    func testTableRowsStayBoundedForOneSixteenThousandWordTurn() throws {
        let words = makeWords(count: 16_000)
        let turn = makeTurn(paragraphCount: 267, wordsPerParagraph: 60, words: words)
        let rows = identifiedReadingTurns([turn], words: words)
        let target = rows[rows.count * 3 / 4]
        let view = NSHostingView(
            rootView: MeetingReadingTurnContentView(
                turns: rows,
                speakerColorMap: ["microphone": .orange],
                activeScrollID: nil,
                navigationScrollID: target.scrollID,
                navigationToken: 1,
                timestampLabel: { "\($0)" },
                isTimestampSeekable: true,
                onTimestampTap: { _ in },
                onCopyTurn: { _ in }
            ) { EmptyView() }
        )
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        let tableView = try XCTUnwrap(findTableView(view))
        XCTAssertEqual(tableView.numberOfRows, rows.count + 1)
        let tallest = (1..<tableView.numberOfRows).map { tableView.rect(ofRow: $0).height }.max() ?? 0
        XCTAssertLessThan(tallest, 600, "A passage row must fit in the viewport")
        // Find and playback navigation land on the passage, not the turn middle.
        let targetRow = rows.firstIndex { $0.scrollID == target.scrollID }! + 1
        XCTAssertTrue(tableView.rows(in: tableView.visibleRect).contains(targetRow))
    }

    private func findTableView(_ view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView { return tableView }
        return view.subviews.lazy.compactMap(findTableView).first
    }

    private func makeWords(count: Int) -> [WordTimestamp] {
        (0..<count).map {
            WordTimestamp(word: "word", startMs: $0 * 400, endMs: $0 * 400 + 350, confidence: 1, speakerId: "microphone")
        }
    }

    private func makeTurn(
        paragraphCount: Int,
        wordsPerParagraph: Int,
        words: [WordTimestamp]? = nil
    ) -> ReadingTurn {
        let vocabulary = ["public", "meeting", "decision", "context", "action", "owner"]
        let paragraphs = (0..<paragraphCount).map { paragraph in
            let references = Array((paragraph * wordsPerParagraph)..<((paragraph + 1) * wordsPerParagraph))
            let text = references.map { vocabulary[$0 % vocabulary.count] }.joined(separator: " ") + "."
            return ReadingTurnParagraph(text: text, wordReferences: references)
        }
        let wordCount = paragraphCount * wordsPerParagraph
        return ReadingTurn(
            id: ReadingTurnIdentity(source: .microphone, speakerId: "microphone", firstWordIndex: 0),
            speakerId: "microphone",
            speakerLabel: "Me",
            source: .microphone,
            timeRange: ReadingTurnTimeRange(startMs: 0, endMs: (wordCount - 1) * 400 + 350),
            paragraphs: paragraphs,
            wordReferences: Array(0..<wordCount)
        )
    }
}

import AppKit
import SwiftUI
import XCTest
import MacParakeetCore
@testable import MacParakeet

/// Exercises the completed-meeting Reading Turn view in the same adaptive
/// stack, selection, hover, and scrolling shape used by `TranscriptResultView`.
///
/// Deterministic correctness command:
/// `swift test --filter MeetingReadingTurnScrollingTests`
///
/// Agent-runnable frame-latency gate:
/// `scripts/dev/check_transcript_scrolling_performance.sh`
@MainActor
final class MeetingReadingTurnScrollingTests: XCTestCase {
    private final class CountingHostingView<Content: View>: NSHostingView<Content> {
        var layoutCount = 0

        override func layout() {
            layoutCount += 1
            super.layout()
        }
    }

    private final class HeaderState: ObservableObject {
        @Published var showsAISetupBanner = false
    }

    private struct HeaderTransitionHarness: View {
        @ObservedObject var state: HeaderState
        let turns: [IdentifiedReadingTurn]

        var body: some View {
            MeetingReadingTurnContentView(
                turns: turns,
                speakerColorMap: ["microphone": .orange],
                headerRevision: state.showsAISetupBanner ? 1 : 0,
                activeScrollID: nil,
                timestampLabel: { "\($0)" },
                isTimestampSeekable: false,
                onTimestampTap: { _ in },
                onCopyTurn: { _ in }
            ) {
                if state.showsAISetupBanner {
                    Text("Set up AI to generate summaries")
                        .frame(height: 120)
                } else {
                    EmptyView()
                }
            }
        }
    }

    func testTwelveHundredTimedRowsRealizeOnlyVisibleRowsAndScrollToExactBounds() {
        let view = host(turnCount: 1_200, compactRows: true)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 800, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let scrollView = findScrollView(view), let document = scrollView.documentView else {
            XCTFail("No NSScrollView behind the completed-meeting ScrollView")
            return
        }

        let tableView = try? XCTUnwrap(findTableView(view))
        XCTAssertEqual(tableView?.numberOfRows, 1_201)
        XCTAssertLessThan(
            tableView?.rows(in: tableView?.visibleRect ?? .zero).length ?? .max,
            30,
            "The production renderer must realize a bounded visible row set"
        )

        _ = scrollThrough(scrollView, document: document, toBottom: true)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, bottomPosition(for: scrollView))
        _ = scrollThrough(scrollView, document: document, toBottom: false)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, topPosition(for: scrollView))
        let settledCount = view.layoutCount
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        XCTAssertLessThanOrEqual(
            view.layoutCount - settledCount,
            2,
            "Reading Turn layout kept running after scrolling stopped"
        )
    }

    func testAISetupVisibilityRevisionReloadsAndRemeasuresHostedHeader() {
        let state = HeaderState()
        let turns = identifiedReadingTurns([makeTurn(index: 0, compact: true)])
        let view = CountingHostingView(
            rootView: AnyView(HeaderTransitionHarness(state: state, turns: turns))
        )
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = show(view)
        defer { window.orderOut(nil) }

        guard let tableView = preparedScrollView(in: view)?.documentView as? NSTableView else {
            XCTFail("No production Reading Turn table")
            return
        }
        let hiddenHeight = tableView.rect(ofRow: 0).height

        state.showsAISetupBanner = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertGreaterThan(tableView.rect(ofRow: 0).height, hiddenHeight + 100)
    }

    func testDistantNavigationRealizesTargetWithoutInterveningRows() {
        let view = host(turnCount: 1_200, compactRows: true, navigationIndex: 1_199)
        let window = show(view)
        defer { window.orderOut(nil) }

        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let tableView = findTableView(view) else {
            XCTFail("No production Reading Turn table")
            return
        }

        XCTAssertTrue(tableView.rows(in: tableView.visibleRect).contains(1_200))
        XCTAssertLessThan(tableView.rows(in: tableView.visibleRect).length, 30)
    }

    func testCompactRowsUseLessThanOneHundredPointsPerReadingTurn() {
        let turnCount = 12
        let view = host(turnCount: turnCount, compactRows: true)
        let window = show(view)
        defer { window.orderOut(nil) }

        guard let scrollView = preparedScrollView(in: view), let document = scrollView.documentView else {
            XCTFail("No NSScrollView behind the completed-meeting ScrollView")
            return
        }

        let transcriptHeight = document.frame.height
        XCTAssertLessThan(
            transcriptHeight / CGFloat(turnCount),
            100,
            "The borderless byline layout must remain compact while complete text stays unclipped"
        )
    }

    /// Reports a measurement for the command-level performance gate. XCTest
    /// does not assert a machine-time expectation.
    func testRepresentativeMeetingReportsMainThreadFrameCPU() {
        let start = threadCPUSeconds()
        let view = host(turnCount: 1_200)
        let window = show(view)
        defer { window.orderOut(nil) }

        guard let scrollView = preparedScrollView(in: view), let document = scrollView.documentView else {
            XCTFail("No NSScrollView behind the completed-meeting renderer")
            return
        }
        let initialMilliseconds = (threadCPUSeconds() - start) * 1_000

        var worstFrameMilliseconds = 0.0
        for _ in 0..<3 {
            worstFrameMilliseconds = max(
                worstFrameMilliseconds,
                scrollThrough(scrollView, document: document, toBottom: true)
            )
            worstFrameMilliseconds = max(
                worstFrameMilliseconds,
                scrollThrough(scrollView, document: document, toBottom: false)
            )
        }

        print(String(format: "TRANSCRIPT_INITIAL_THREAD_CPU_MS=%.6f", initialMilliseconds))
        print(String(format: "TRANSCRIPT_SCROLL_MAX_FRAME_THREAD_CPU_MS=%.6f", worstFrameMilliseconds))
    }

    private func show(_ view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 800, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.orderFront(nil)
        return window
    }

    private func preparedScrollView(in view: NSView) -> NSScrollView? {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return findScrollView(view)
    }

    private func host(
        turnCount: Int,
        compactRows: Bool = false,
        navigationIndex: Int? = nil
    ) -> CountingHostingView<AnyView> {
        let turns = identifiedReadingTurns(
            (0..<turnCount).map { makeTurn(index: $0, compact: compactRows) }
        )
        let content = MeetingReadingTurnContentView(
            turns: turns,
            speakerColorMap: ["microphone": .orange, "system:S1": .blue],
            activeScrollID: nil,
            navigationScrollID: navigationIndex.map { turns[$0].scrollID },
            navigationToken: navigationIndex ?? 0,
            timestampLabel: { "\($0 / 60_000):00" },
            isTimestampSeekable: true,
            onTimestampTap: { _ in },
            onCopyTurn: { _ in }
        ) {
            EmptyView()
        }
        let view = CountingHostingView(rootView: AnyView(content))
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        return view
    }

    private func makeTurn(index: Int, compact: Bool) -> ReadingTurn {
        let source: ReadingTurnSource = index.isMultiple(of: 3) ? .microphone : .system
        let speakerID = source == .microphone ? "microphone" : "system:S1"
        let sentence = "Public synthetic meeting text preserves selection, search, copy, and scrolling behavior."
        let repetitionCounts = compact ? [1, 2, 3, 4] : [1, 4, 10, 18]
        let repetitionCount = repetitionCounts[index % repetitionCounts.count]
        let text = Array(repeating: sentence, count: repetitionCount).joined(separator: " ")
        return ReadingTurn(
            id: ReadingTurnIdentity(source: source, speakerId: speakerID, firstWordIndex: index * 20),
            speakerId: speakerID,
            speakerLabel: source == .microphone ? "Me" : "Speaker 1",
            source: source,
            timeRange: ReadingTurnTimeRange(startMs: index * 5_000, endMs: index * 5_000 + 4_000),
            paragraphs: [ReadingTurnParagraph(text: text, wordReferences: [index * 20])],
            wordReferences: [index * 20]
        )
    }

    private func findScrollView(_ view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        return view.subviews.lazy.compactMap(findScrollView).first
    }

    private func findTableView(_ view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView { return tableView }
        return view.subviews.lazy.compactMap(findTableView).first
    }

    private func scrollThrough(
        _ scrollView: NSScrollView,
        document: NSView,
        toBottom: Bool
    ) -> Double {
        let clip = scrollView.contentView
        let maxY = max(0, document.frame.height - clip.bounds.height)
        let travel = min(maxY, 9_600)
        let positions: [CGFloat]
        let finalPosition: CGFloat
        if toBottom {
            positions = Array(stride(from: 0.0, through: travel, by: 120.0))
            finalPosition = maxY
        } else {
            positions = Array(stride(from: maxY, through: max(0, maxY - travel), by: -120.0))
            finalPosition = 0
        }
        var worstFrameMilliseconds = 0.0
        for position in positions {
            let y = document.isFlipped ? position : maxY - position
            let frameStart = threadCPUSeconds()
            clip.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(clip)
            sendMouseMoved(to: scrollView)
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            worstFrameMilliseconds = max(
                worstFrameMilliseconds,
                (threadCPUSeconds() - frameStart) * 1_000
            )
        }
        let finalY = document.isFlipped ? finalPosition : maxY - finalPosition
        clip.scroll(to: NSPoint(x: 0, y: finalY))
        scrollView.reflectScrolledClipView(clip)
        RunLoop.main.run(until: Date().addingTimeInterval(0.001))
        return worstFrameMilliseconds
    }

    private func sendMouseMoved(to scrollView: NSScrollView) {
        guard let window = scrollView.window else { return }
        let frame = scrollView.convert(scrollView.bounds, to: nil)
        let event = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: NSPoint(x: frame.midX, y: frame.midY),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )
        if let event { NSApp.sendEvent(event) }
    }

    private func threadCPUSeconds() -> Double {
        var time = timespec()
        precondition(clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
    }

    private func bottomPosition(for scrollView: NSScrollView) -> CGFloat {
        guard let document = scrollView.documentView else { return 0 }
        let maxY = max(0, document.frame.height - scrollView.contentView.bounds.height)
        return document.isFlipped ? maxY : 0
    }

    private func topPosition(for scrollView: NSScrollView) -> CGFloat {
        guard let document = scrollView.documentView else { return 0 }
        let maxY = max(0, document.frame.height - scrollView.contentView.bounds.height)
        return document.isFlipped ? 0 : maxY
    }
}

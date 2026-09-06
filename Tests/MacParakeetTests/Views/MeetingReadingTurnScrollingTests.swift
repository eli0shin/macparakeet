import AppKit
import SwiftUI
import XCTest
import MacParakeetCore
@testable import MacParakeet

/// Exercises the completed-meeting Reading Turn view in the same adaptive
/// stack, selection, hover, and scrolling shape used by `TranscriptResultView`.
///
/// Agent-runnable regression command:
/// `swift test --filter MeetingReadingTurnScrollingTests`
@MainActor
final class MeetingReadingTurnScrollingTests: XCTestCase {
    private final class CountingHostingView<Content: View>: NSHostingView<Content> {
        var layoutCount = 0

        override func layout() {
            layoutCount += 1
            super.layout()
        }
    }

    func testRepresentativeMeetingScrollDownAndBackUpSettlesWithoutMainThreadStall() {
        let view = host(turnCount: 75)
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

        for _ in 0..<3 {
            scrollThrough(scrollView, document: document, toBottom: true)
            XCTAssertEqual(scrollView.contentView.bounds.origin.y, bottomPosition(for: scrollView))
            scrollThrough(scrollView, document: document, toBottom: false)
            XCTAssertEqual(scrollView.contentView.bounds.origin.y, topPosition(for: scrollView))
        }
        let settledCount = view.layoutCount
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        XCTAssertLessThanOrEqual(
            view.layoutCount - settledCount,
            2,
            "Reading Turn layout kept running after scrolling stopped"
        )
    }

    private func host(turnCount: Int) -> CountingHostingView<AnyView> {
        let turns = identifiedReadingTurns((0..<turnCount).map(makeTurn))
        let body = MeetingReadingTurnContentView(
            turns: turns,
            speakerColorMap: ["microphone": .orange, "system:S1": .blue],
            speakerLabelContent: { _, label, color, _, _ in
                Text(label).foregroundStyle(color)
            },
            activeScrollID: nil,
            timestampLabel: { "\($0 / 60_000):00" },
            isTimestampSeekable: true,
            onTimestampTap: { _ in },
            onCopyTurn: { _ in }
        )
        let content = ScrollViewReader { _ in
            ScrollView {
                TranscriptBodyStack(rowCount: turns.count) {
                    body
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
        let view = CountingHostingView(rootView: AnyView(content))
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        return view
    }

    private func makeTurn(index: Int) -> ReadingTurn {
        let source: ReadingTurnSource = index.isMultiple(of: 3) ? .microphone : .system
        let speakerID = source == .microphone ? "microphone" : "system:S1"
        let sentence = "Public synthetic meeting text preserves selection, search, copy, and scrolling behavior."
        let repetitionCount = [1, 4, 10, 18][index % 4]
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

    private func scrollThrough(
        _ scrollView: NSScrollView,
        document: NSView,
        toBottom: Bool
    ) {
        let clip = scrollView.contentView
        let maxY = max(0, document.frame.height - clip.bounds.height)
        var positions = Array(stride(from: 0.0, to: maxY, by: 120.0))
        positions.append(maxY)
        for position in toBottom ? positions : positions.reversed() {
            let y = document.isFlipped ? position : maxY - position
            clip.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(clip)
            sendMouseMoved(to: scrollView)
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
        }
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

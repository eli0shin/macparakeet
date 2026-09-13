import AppKit
import XCTest
@testable import MacParakeet
@testable import MacParakeetViewModels

/// Qualification budgets for the Text-mode native surface. The fixture is about
/// 600,000 UTF-16 characters, which is longer than a typical multi-hour meeting.
/// Each measured main-thread presentation operation must finish within 100 ms.
@MainActor
final class LongTranscriptTextSurfaceTests: XCTestCase {
    private static let readinessBudget = Duration.milliseconds(100)
    private static let viewport = NSSize(width: 640, height: 520)
    private static let longTranscript = String(
        repeating: "Speaker explains the current decision and the next action.\n\n",
        count: 10_000
    )

    func testInitialVisibleRenderStaysWithinReadinessBudget() throws {
        let textView = makeTextView()
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)

        let elapsed = measureDuration {
            textView.textStorage?.setAttributedString(
                TranscriptFindTextView.attributedText(Self.longTranscript, fontScale: 1)
            )
            layoutManager.ensureLayout(
                forBoundingRect: NSRect(origin: .zero, size: Self.viewport),
                in: textContainer
            )
        }

        XCTAssertTrue(layoutManager.allowsNonContiguousLayout)
        XCTAssertLessThan(
            layoutManager.firstUnlaidCharacterIndex(),
            Self.longTranscript.utf16.count,
            "Initial readiness must not require complete-document shaping"
        )
        XCTAssertLessThan(elapsed, Self.readinessBudget, "Initial readiness took \(elapsed)")
    }

    func testResizeReflowsOnlyTheVisibleViewportWithinBudget() throws {
        let textView = makeTextView(text: Self.longTranscript)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(
            forBoundingRect: NSRect(origin: .zero, size: Self.viewport),
            in: textContainer
        )

        let widerViewport = NSSize(width: 900, height: Self.viewport.height)
        let elapsed = measureDuration {
            textView.frame.size.width = widerViewport.width
            textContainer.containerSize.width = widerViewport.width
            layoutManager.invalidateLayout(
                forCharacterRange: NSRange(location: 0, length: textView.string.utf16.count),
                actualCharacterRange: nil
            )
            layoutManager.ensureLayout(
                forBoundingRect: NSRect(origin: .zero, size: widerViewport),
                in: textContainer
            )
        }

        XCTAssertLessThan(layoutManager.firstUnlaidCharacterIndex(), textView.string.utf16.count)
        XCTAssertLessThan(elapsed, Self.readinessBudget, "Visible resize reflow took \(elapsed)")
    }

    func testNativeCrossParagraphSelectionAndCopyStayWithinBudget() {
        let textView = makeTextView(text: Self.longTranscript)
        let expected = "decision and the next action.\n\nSpeaker explains"
        let middle = Self.longTranscript.utf16.count / 2
        let searchRange = NSRange(location: middle, length: Self.longTranscript.utf16.count - middle)
        let range = (Self.longTranscript as NSString).range(of: expected, range: searchRange)

        var copied: String?
        let elapsed = measureDuration {
            textView.setSelectedRange(range)
            copied = textView.textStorage?.attributedSubstring(from: textView.selectedRange()).string
        }

        XCTAssertEqual(copied, expected)
        XCTAssertEqual(textView.selectedRange(), range)
        XCTAssertLessThan(elapsed, Self.readinessBudget, "Cross-paragraph selection took \(elapsed)")
    }

    func testHighMatchCountHighlightsOnlyCurrentRangeWithinBudget() async throws {
        let text = String(repeating: "match ", count: 100_000)
        let model = TranscriptFindModel(debounce: .zero)
        model.setBlocks([text])
        model.setQuery("match")
        while model.isSearching { await Task.yield() }
        XCTAssertEqual(model.matchCount, 100_000)

        let textView = makeTextView(text: text)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let finalRange = try XCTUnwrap(model.matches.last?.range)
        let elapsed = measureDuration {
            _ = TranscriptFindTextView.applyHighlight(
                finalRange,
                in: text,
                layoutManager: layoutManager,
                replacing: nil
            )
        }

        XCTAssertLessThan(elapsed, Self.readinessBudget, "Current-match highlight took \(elapsed)")
        XCTAssertNotNil(
            layoutManager.temporaryAttribute(
                .backgroundColor,
                atCharacterIndex: finalRange.location,
                effectiveRange: nil
            )
        )
    }

    func testMatchNearDocumentEndUsesRangeLayoutWithoutShapingPrefix() throws {
        let textView = makeTextView(text: Self.longTranscript)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let location = Self.longTranscript.utf16.count - 20
        let range = NSRange(location: location, length: 8)

        let elapsed = measureDuration {
            _ = TranscriptFindTextView.matchRect(
                range,
                in: Self.longTranscript,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
        }

        XCTAssertLessThan(
            layoutManager.firstUnlaidCharacterIndex(),
            location,
            "Range navigation must leave the document prefix unshaped"
        )
        XCTAssertLessThan(elapsed, Self.readinessBudget, "End-range navigation took \(elapsed)")
    }

    func testEditingCancelRestoresTextAndActualCharacterAnchor() {
        let text = String(repeating: "One line of transcript text.\n", count: 2_000)
        let textView = makeTextView(text: text)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.viewport),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView.enclosingScrollView
        TranscriptFindTextView.restoreTopVisibleCharacter(900, in: textView)
        let anchor = TranscriptFindTextView.topVisibleCharacter(in: textView)

        TranscriptFindTextView.setEditable(true, preservingViewportIn: textView)
        textView.insertText("edited ", replacementRange: textView.selectedRange())
        TranscriptFindTextView.replaceText(text, fontScale: 1, in: textView)
        let restoredAnchor = TranscriptFindTextView.preservedScrollAnchor(
            anchor,
            textUTF16Count: text.utf16.count
        )
        textView.setSelectedRange(NSRange(location: restoredAnchor, length: 0))
        TranscriptFindTextView.setEditable(false, preservingViewportIn: textView)
        TranscriptFindTextView.restoreTopVisibleCharacter(restoredAnchor, in: textView)

        XCTAssertEqual(textView.string, text)
        XCTAssertLessThanOrEqual(
            abs(TranscriptFindTextView.topVisibleCharacter(in: textView) - anchor),
            80
        )
        XCTAssertEqual(
            TranscriptFindTextView.preservedScrollAnchor(anchor, textUTF16Count: 100),
            100,
            "Save or cancel clamps the old top character when edited text is shorter"
        )
    }

    func testProgrammaticSaveOrCancelClearsTheNativeUndoSession() {
        let textView = makeTextView(text: "original")
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.viewport),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView.enclosingScrollView
        textView.isEditable = true
        window.makeFirstResponder(textView)
        textView.insertText(" edit", replacementRange: NSRange(location: 8, length: 0))
        XCTAssertTrue(textView.undoManager?.canUndo == true)

        TranscriptFindTextView.replaceText("original", fontScale: 1, in: textView)

        XCTAssertFalse(textView.undoManager?.canUndo == true)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "original")
    }

    func testFontScaleColorsLineSpacingAndAccessibilityUseTranscriptTokens() throws {
        let textView = makeTextView(text: "Styled transcript")
        let attributed = TranscriptFindTextView.attributedText("Styled transcript", fontScale: 1.2)
        let attributes = attributed.attributes(at: 0, effectiveRange: nil)
        let font = try XCTUnwrap(attributes[.font] as? NSFont)
        let paragraph = try XCTUnwrap(attributes[.paragraphStyle] as? NSParagraphStyle)

        XCTAssertEqual(font.pointSize, 18, accuracy: 0.01)
        XCTAssertEqual(attributes[.foregroundColor] as? NSColor, NSColor(DesignSystem.Colors.textPrimary))
        XCTAssertEqual(paragraph.lineSpacing, 6)
        XCTAssertEqual(textView.accessibilityLabel(), "Transcript text")
        XCTAssertTrue(textView.isSelectable)
    }

    private func makeTextView(text: String = "") -> NSTextView {
        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: Self.viewport))
        scrollView.hasVerticalScroller = true
        let textView = FinalTranscriptNSTextView(frame: NSRect(origin: .zero, size: Self.viewport))
        TranscriptFindTextView.configure(textView, for: Self.viewport)
        scrollView.documentView = textView
        if !text.isEmpty {
            textView.textStorage?.setAttributedString(
                TranscriptFindTextView.attributedText(text, fontScale: 1)
            )
        }
        return textView
    }

    private func measureDuration(_ operation: () -> Void) -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        operation()
        return start.duration(to: clock.now)
    }
}

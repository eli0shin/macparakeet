import AppKit
import SwiftUI

/// Transcript edits use a private undo stack. Save and cancel can then discard
/// stale native ranges without clearing undo operations owned by other controls.
final class FinalTranscriptNSTextView: NSTextView {
    private let transcriptUndoManager = UndoManager()

    override var undoManager: UndoManager? { transcriptUndoManager }
}

/// A native long-document transcript surface. Its TextKit layout manager permits
/// non-contiguous layout, so opening or resizing a multi-hour transcript shapes
/// the visible viewport instead of the complete document. The same text view is
/// kept when editing starts or ends. Editing starts at the top visible character,
/// and save or cancel restores that character as the viewport anchor.
struct TranscriptFindTextView: NSViewRepresentable {
    let text: String
    let currentRange: NSRange?
    let fontScale: Double
    let navigationToken: Int
    let isEditable: Bool
    let onTextChange: (String) -> Void

    init(
        text: String,
        currentRange: NSRange?,
        fontScale: Double,
        navigationToken: Int,
        isEditable: Bool = false,
        onTextChange: @escaping (String) -> Void = { _ in }
    ) {
        self.text = text
        self.currentRange = currentRange
        self.fontScale = fontScale
        self.navigationToken = navigationToken
        self.isEditable = isEditable
        self.onTextChange = onTextChange
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text = ""
        var fontScale: Double?
        var highlightedRange: NSRange?
        var navigationToken: Int?
        var isEditable = false
        var isApplyingUpdate = false
        var editabilityToken = 0
        var onTextChange: (String) -> Void = { _ in }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate,
                let textView = notification.object as? NSTextView
            else { return }
            text = textView.string
            onTextChange(textView.string)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = FinalTranscriptNSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.delegate = context.coordinator
        Self.configure(textView, for: scrollView.contentSize)
        scrollView.documentView = textView

        update(scrollView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        update(scrollView, coordinator: context.coordinator)
    }

    private func update(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.onTextChange = onTextChange

        if coordinator.text != text || coordinator.fontScale != fontScale {
            let textChanged = coordinator.text != text
            let visibleCharacter = Self.topVisibleCharacter(in: textView)
            coordinator.isApplyingUpdate = true
            Self.replaceText(text, fontScale: fontScale, in: textView)
            coordinator.isApplyingUpdate = false
            coordinator.text = text
            coordinator.fontScale = fontScale
            coordinator.highlightedRange = nil
            if textChanged {
                let anchor = Self.preservedScrollAnchor(
                    visibleCharacter,
                    textUTF16Count: text.utf16.count
                )
                textView.setSelectedRange(NSRange(location: anchor, length: 0))
            }
            Self.restoreTopVisibleCharacter(visibleCharacter, in: textView)
        }

        coordinator.highlightedRange = Self.applyHighlight(
            currentRange,
            in: text,
            layoutManager: textView.layoutManager,
            replacing: coordinator.highlightedRange
        )

        if coordinator.isEditable != isEditable {
            coordinator.isEditable = isEditable
            coordinator.editabilityToken &+= 1
            let editabilityToken = coordinator.editabilityToken
            let visibleCharacter = Self.topVisibleCharacter(in: textView)
            Self.setEditable(isEditable, preservingViewportIn: textView)
            Task { @MainActor [weak textView, weak coordinator] in
                await Task.yield()
                guard let textView, let coordinator,
                    coordinator.editabilityToken == editabilityToken
                else { return }
                if isEditable {
                    textView.window?.makeFirstResponder(textView)
                }
                Self.restoreTopVisibleCharacter(visibleCharacter, in: textView)
            }
        }

        if coordinator.navigationToken != navigationToken {
            coordinator.navigationToken = navigationToken
            scrollCurrentRangeToVisible(in: textView, coordinator: coordinator)
        }
    }

    static func configure(_ textView: NSTextView, for viewportSize: NSSize) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: viewportSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: viewportSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.layoutManager?.backgroundLayoutEnabled = false
        textView.setAccessibilityLabel("Transcript text")
    }

    /// Programmatic save/cancel replacement starts a new native undo session.
    /// Old typing ranges must not survive after the backing string changes.
    static func replaceText(_ text: String, fontScale: Double, in textView: NSTextView) {
        textView.breakUndoCoalescing()
        textView.undoManager?.removeAllActions()
        textView.textStorage?.setAttributedString(attributedText(text, fontScale: fontScale))
    }

    static func attributedText(_ text: String, fontScale: Double) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15 * fontScale),
                .foregroundColor: NSColor(DesignSystem.Colors.textPrimary),
                .paragraphStyle: paragraph,
            ]
        )
    }

    /// Resolve the current match through the TextKit layout that renders the
    /// transcript. No duplicate prefix string or SwiftUI scroll anchor exists.
    private func scrollCurrentRangeToVisible(
        in textView: NSTextView,
        coordinator: Coordinator
    ) {
        let token = navigationToken
        let range = currentRange
        let textSnapshot = text
        Task { @MainActor [weak textView, weak coordinator] in
            await Task.yield()
            guard let textView, let coordinator,
                coordinator.navigationToken == token,
                coordinator.text == textSnapshot,
                let range,
                let rect = Self.matchRect(
                    range,
                    in: textSnapshot,
                    layoutManager: textView.layoutManager,
                    textContainer: textView.textContainer
                )
            else { return }
            Self.center(rect, in: textView)
        }
    }

    static func center(_ rect: NSRect, in textView: NSTextView) {
        guard let scrollView = textView.enclosingScrollView else {
            textView.scrollToVisible(rect.insetBy(dx: 0, dy: -40))
            return
        }
        let clipView = scrollView.contentView
        let targetY = rect.midY + textView.textContainerOrigin.y - (clipView.bounds.height / 2)
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: max(0, targetY)))
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Returns the match rectangle after laying out only the range needed for
    /// navigation. With non-contiguous layout this does not shape its prefix.
    static func matchRect(
        _ currentRange: NSRange,
        in text: String,
        layoutManager: NSLayoutManager?,
        textContainer: NSTextContainer?
    ) -> NSRect? {
        guard let layoutManager, let textContainer,
            TranscriptFindHighlight.textNavigationProgress(current: currentRange, in: text) != nil
        else {
            return nil
        }
        layoutManager.ensureLayout(forCharacterRange: currentRange)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: currentRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return nil }
        return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    }

    /// Updates one temporary TextKit attribute. The transcript storage, glyph
    /// layout, native selection, and all non-current matches stay unchanged.
    @discardableResult
    static func applyHighlight(
        _ currentRange: NSRange?,
        in text: String,
        layoutManager: NSLayoutManager?,
        replacing previousRange: NSRange?
    ) -> NSRange? {
        guard currentRange != previousRange, let layoutManager else { return previousRange }
        if let previousRange {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: previousRange)
        }
        guard let currentRange,
            TranscriptFindHighlight.textNavigationProgress(current: currentRange, in: text) != nil
        else {
            return nil
        }
        layoutManager.addTemporaryAttribute(
            .backgroundColor,
            value: NSColor(DesignSystem.Colors.accent).withAlphaComponent(0.55),
            forCharacterRange: currentRange
        )
        return currentRange
    }

    /// Editing can move the native selection into view. Restore the character
    /// anchor after the mode change so entry, save, and cancel keep the reader's
    /// viewport.
    static func setEditable(_ isEditable: Bool, preservingViewportIn textView: NSTextView) {
        let visibleCharacter = topVisibleCharacter(in: textView)
        if isEditable {
            textView.setSelectedRange(NSRange(location: visibleCharacter, length: 0))
        }
        textView.isEditable = isEditable
        textView.drawsBackground = false
        restoreTopVisibleCharacter(visibleCharacter, in: textView)
    }

    /// The edit policy uses a UTF-16 character anchor: entering edit keeps the
    /// current viewport unchanged; save or cancel restores the nearest valid
    /// character at the top after replacing text.
    static func topVisibleCharacter(in textView: NSTextView) -> Int {
        guard !textView.string.isEmpty,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return 0 }
        let point = NSPoint(
            x: max(0, textView.visibleRect.minX - textView.textContainerOrigin.x),
            y: max(0, textView.visibleRect.minY - textView.textContainerOrigin.y)
        )
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    static func preservedScrollAnchor(_ location: Int, textUTF16Count: Int) -> Int {
        min(max(location, 0), textUTF16Count)
    }

    static func restoreTopVisibleCharacter(_ location: Int, in textView: NSTextView) {
        let clamped = preservedScrollAnchor(location, textUTF16Count: textView.string.utf16.count)
        guard !textView.string.isEmpty else {
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            return
        }
        guard let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer,
            let clipView = textView.enclosingScrollView?.contentView
        else {
            textView.scrollRangeToVisible(NSRange(location: clamped, length: 0))
            return
        }
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: clamped, length: 0))
        let glyph = layoutManager.glyphIndexForCharacter(
            at: min(clamped, textView.string.utf16.count - 1)
        )
        let rect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyph, length: 1),
            in: textContainer
        )
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: rect.minY + textView.textContainerOrigin.y))
        textView.enclosingScrollView?.reflectScrolledClipView(clipView)
    }
}

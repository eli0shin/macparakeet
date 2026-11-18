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
///
/// With a header, the surface fills its pane and is the only scroll view: the
/// header scrolls away above the transcript text instead of the text scrolling
/// inside a fixed-height box nested in a second scroll view.
struct TranscriptFindTextView: NSViewRepresentable {
    let text: String
    let currentRange: NSRange?
    let fontScale: Double
    let navigationToken: Int
    let isEditable: Bool
    let onTextChange: (String) -> Void
    let header: AnyView?
    let headerRevision: Int

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
        self.header = nil
        self.headerRevision = 0
    }

    init<Header: View>(
        text: String,
        currentRange: NSRange?,
        fontScale: Double,
        navigationToken: Int,
        isEditable: Bool = false,
        headerRevision: Int,
        onTextChange: @escaping (String) -> Void = { _ in },
        @ViewBuilder header: () -> Header
    ) {
        self.text = text
        self.currentRange = currentRange
        self.fontScale = fontScale
        self.navigationToken = navigationToken
        self.isEditable = isEditable
        self.onTextChange = onTextChange
        self.header = AnyView(header())
        self.headerRevision = headerRevision
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
        if let header {
            let document = TranscriptTextDocumentView(textView: textView)
            document.setHeader(header, revision: headerRevision)
            scrollView.documentView = document
        } else {
            scrollView.documentView = textView
        }

        update(scrollView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        update(scrollView, coordinator: context.coordinator)
    }

    private func update(_ scrollView: NSScrollView, coordinator: Coordinator) {
        let document = scrollView.documentView as? TranscriptTextDocumentView
        guard let textView = document?.textView ?? scrollView.documentView as? NSTextView else { return }
        coordinator.onTextChange = onTextChange
        if let document {
            if let header { document.setHeader(header, revision: headerRevision) }
            document.isEditing = isEditable
        }

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
        let midY = documentY(rect.midY + textView.textContainerOrigin.y, of: textView, in: scrollView)
        let targetY = midY - (clipView.bounds.height / 2)
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: max(0, targetY)))
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Converts a text-view y coordinate into the scroll view's document. The
    /// text view is either the document itself or sits below a hosted header.
    private static func documentY(_ y: CGFloat, of textView: NSTextView, in scrollView: NSScrollView) -> CGFloat {
        guard let documentView = scrollView.documentView, documentView !== textView else { return y }
        return textView.convert(NSPoint(x: 0, y: y), to: documentView).y
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
            let scrollView = textView.enclosingScrollView
        else {
            textView.scrollRangeToVisible(NSRange(location: clamped, length: 0))
            return
        }
        let clipView = scrollView.contentView
        // The top visible character is 0 while a header above the text is in
        // view. Keep that exact offset so editing and saving do not scroll the
        // header and its controls away.
        if clamped == 0, textView.visibleRect.minY <= 0, scrollView.documentView !== textView {
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
        let y = documentY(rect.minY + textView.textContainerOrigin.y, of: textView, in: scrollView)
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clipView)
    }
}

/// The scroll document for a Text surface with a header: the hosted SwiftUI
/// header, then a rounded backdrop containing the TextKit view. The text view
/// keeps non-contiguous layout; this view only stacks frames and follows the
/// text view's height.
@MainActor
final class TranscriptTextDocumentView: NSView {
    static let textInset = DesignSystem.Spacing.lg
    static let headerSpacing = DesignSystem.Spacing.md

    let textView: NSTextView
    private let headerHost = TranscriptTextHeaderHostingView(rootView: AnyView(EmptyView()))
    private let backdrop = TranscriptTextBackdropView()
    private var header: AnyView?
    private var headerRevision: Int?
    private var hostedWidth: CGFloat = -1
    private var headerNeedsMeasurement = true
    private var headerHeight: CGFloat = 0
    private var isTiling = false

    var isEditing = false {
        didSet {
            guard isEditing != oldValue else { return }
            backdrop.isEditing = isEditing
        }
    }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: NSRect(origin: .zero, size: textView.frame.size))
        autoresizingMask = [.width]
        autoresizesSubviews = false
        textView.autoresizingMask = []
        textView.postsFrameChangedNotifications = true
        // SwiftUI reports header content changes, such as an expanded section,
        // through intrinsic size. Measuring inside `tile` is not a new change.
        headerHost.onIntrinsicSizeInvalidated = { [weak self] in
            guard let self, !self.isTiling else { return }
            self.headerNeedsMeasurement = true
            self.needsLayout = true
        }
        addSubview(headerHost)
        addSubview(backdrop)
        addSubview(textView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textViewFrameDidChange),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    /// Rehosts the header only when its revision changes, so find and playback
    /// updates do not re-evaluate or remeasure it.
    func setHeader(_ header: AnyView, revision: Int) {
        guard revision != headerRevision else { return }
        self.header = header
        headerRevision = revision
        hostedWidth = -1
        tile()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { tile() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        tile()
    }

    override func layout() {
        super.layout()
        if headerNeedsMeasurement { tile() }
    }

    @objc private func textViewFrameDidChange() {
        tile()
    }

    private func tile() {
        guard !isTiling else { return }
        isTiling = true
        defer { isTiling = false }

        let width = max(1, enclosingScrollView?.contentSize.width ?? frame.width)
        if let header, abs(width - hostedWidth) > 0.5 {
            hostedWidth = width
            headerHost.rootView = AnyView(header.frame(width: width, alignment: .leading))
            headerNeedsMeasurement = true
        }
        if headerNeedsMeasurement {
            headerNeedsMeasurement = false
            headerHeight = header == nil ? 0 : ceil(headerHost.fittingSize.height)
        }
        let textTop = headerHeight > 0 ? headerHeight + Self.headerSpacing : 0
        headerHost.frame = NSRect(x: 0, y: 0, width: width, height: headerHeight)

        let textWidth = max(1, width - Self.textInset * 2)
        if abs(textView.frame.width - textWidth) > 0.5 {
            textView.setFrameSize(NSSize(width: textWidth, height: textView.frame.height))
        }
        let textOrigin = NSPoint(x: Self.textInset, y: textTop + Self.textInset)
        if textView.frame.origin != textOrigin { textView.setFrameOrigin(textOrigin) }
        backdrop.frame = NSRect(
            x: 0,
            y: textTop,
            width: width,
            height: textView.frame.height + Self.textInset * 2
        )

        let clipHeight = enclosingScrollView?.contentSize.height ?? 0
        let height = max(backdrop.frame.maxY, clipHeight)
        if abs(frame.width - width) > 0.5 || abs(frame.height - height) > 0.5 {
            super.setFrameSize(NSSize(width: width, height: height))
        }
    }
}

private final class TranscriptTextHeaderHostingView: NSHostingView<AnyView> {
    var onIntrinsicSizeInvalidated: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicSizeInvalidated?()
    }
}

/// A solid rounded layer behind the transcript text. It has no backing store,
/// so its height can follow a multi-hour transcript.
private final class TranscriptTextBackdropView: NSView {
    var isEditing = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = DesignSystem.Layout.rowCornerRadius
        layer.backgroundColor = NSColor(DesignSystem.Colors.surfaceElevated)
            .withAlphaComponent(isEditing ? 0.75 : 0.6)
            .cgColor
        layer.borderWidth = isEditing ? 1 : 0
        layer.borderColor = NSColor(DesignSystem.Colors.accent).withAlphaComponent(0.30).cgColor
    }
}

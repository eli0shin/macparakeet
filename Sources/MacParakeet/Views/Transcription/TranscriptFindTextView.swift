import AppKit
import SwiftUI

/// A selectable full-transcript reader that keeps its text storage stable while
/// find navigation changes. TextKit applies one temporary background attribute,
/// so moving the cursor does not rebuild an attributed copy of the transcript.
struct TranscriptFindTextView: NSViewRepresentable {
    let text: String
    let currentRange: NSRange?
    let fontScale: Double
    let navigationToken: Int

    final class Coordinator {
        var text = ""
        var fontScale: Double?
        var highlightedRange: NSRange?
        var navigationToken: Int?
        var measuredWidth: CGFloat?
        var measuredSize: CGSize?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        update(textView, coordinator: context.coordinator)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        update(textView, coordinator: context.coordinator)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textView: NSTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else { return nil }
        if context.coordinator.measuredWidth == width,
           let measuredSize = context.coordinator.measuredSize {
            return measuredSize
        }
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let measuredSize = CGSize(
            width: width,
            height: ceil(layoutManager.usedRect(for: textContainer).height)
        )
        context.coordinator.measuredWidth = width
        context.coordinator.measuredSize = measuredSize
        return measuredSize
    }

    private func update(_ textView: NSTextView, coordinator: Coordinator) {
        if coordinator.text != text || coordinator.fontScale != fontScale {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 6
            textView.textStorage?.setAttributedString(
                NSAttributedString(
                    string: text,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 15 * fontScale),
                        .foregroundColor: NSColor(DesignSystem.Colors.textPrimary),
                        .paragraphStyle: paragraph,
                    ]
                )
            )
            coordinator.text = text
            coordinator.fontScale = fontScale
            coordinator.highlightedRange = nil
            coordinator.measuredWidth = nil
            coordinator.measuredSize = nil
        }
        coordinator.highlightedRange = Self.applyHighlight(
            currentRange,
            in: text,
            layoutManager: textView.layoutManager,
            replacing: coordinator.highlightedRange
        )
        if coordinator.navigationToken != navigationToken {
            coordinator.navigationToken = navigationToken
            scrollCurrentRangeToVisible(in: textView, coordinator: coordinator)
        }
    }

    /// Resolve the current match through the same TextKit layout that renders
    /// the transcript. Waiting one main-actor turn lets SwiftUI install or move
    /// the representable before `scrollToVisible` walks to the outer clip view.
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
                  ) else { return }
            textView.scrollToVisible(rect.insetBy(dx: 0, dy: -40))
        }
    }

    /// Returns the current match rectangle from the existing TextKit layout.
    /// No second text view or prefix layout is created.
    static func matchRect(
        _ currentRange: NSRange,
        in text: String,
        layoutManager: NSLayoutManager?,
        textContainer: NSTextContainer?
    ) -> NSRect? {
        guard let layoutManager, let textContainer,
              TranscriptFindHighlight.textNavigationProgress(current: currentRange, in: text) != nil else {
            return nil
        }
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: currentRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return nil }
        layoutManager.ensureLayout(forCharacterRange: currentRange)
        return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    }

    /// Updates only a bounded TextKit temporary attribute. The transcript text
    /// storage and glyph layout stay in place, and user selection stays separate
    /// from the current-result emphasis.
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
              TranscriptFindHighlight.textNavigationProgress(current: currentRange, in: text) != nil else {
            return nil
        }
        layoutManager.addTemporaryAttribute(
            .backgroundColor,
            value: NSColor(DesignSystem.Colors.accent).withAlphaComponent(0.55),
            forCharacterRange: currentRange
        )
        return currentRange
    }
}

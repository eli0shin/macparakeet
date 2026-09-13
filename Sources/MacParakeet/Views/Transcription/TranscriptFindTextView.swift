import AppKit
import SwiftUI

/// A selectable full-transcript reader that keeps its text storage stable while
/// find navigation changes. TextKit applies one temporary background attribute,
/// so moving the cursor does not rebuild an attributed copy of the transcript.
struct TranscriptFindTextView: NSViewRepresentable {
    let text: String
    let currentRange: NSRange?
    let fontScale: Double

    final class Coordinator {
        var text = ""
        var fontScale: Double?
        var highlightedRange: NSRange?
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

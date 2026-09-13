import SwiftUI

/// Builds the highlighted `AttributedString` for the current in-transcript
/// find match. Search can return hundreds of thousands of matches, so rendering
/// deliberately styles one range instead of doing work proportional to the
/// total result count or the number of off-screen Reading Turns.
///
/// The range is a UTF-16 `NSRange` relative to `text` (as produced by
/// `TranscriptFindModel`). Coral comes only through
/// `DesignSystem.Colors.accent` tokens — never a hosting-root tint.
enum TranscriptFindHighlight {
    static func attributed(
        _ text: String,
        current: NSRange,
        baseFont: Font
    ) -> AttributedString {
        var attr = AttributedString(text)
        attr.font = baseFont
        guard let range = attributedRange(current, in: text, attr: attr) else { return attr }
        attr[range].backgroundColor = DesignSystem.Colors.accent.opacity(0.55)
        attr[range].font = baseFont.bold()
        return attr
    }

    /// Returns a proportional target inside the rendered full-text block.
    /// This uses the validated UTF-16 match range without creating or laying
    /// out an invisible transcript prefix. The target is exact for uniform
    /// wrapping and remains a close navigation target for normal prose.
    static func textNavigationProgress(current: NSRange, in text: String) -> Double? {
        let utf16 = text.utf16
        let count = utf16.count
        guard count > 0,
              current.location >= 0,
              current.length >= 0,
              current.location <= count,
              current.length <= count - current.location,
              let lowerUTF16 = utf16.index(
                  utf16.startIndex,
                  offsetBy: current.location,
                  limitedBy: utf16.endIndex
              ),
              let upperUTF16 = utf16.index(
                  lowerUTF16,
                  offsetBy: current.length,
                  limitedBy: utf16.endIndex
              ),
              lowerUTF16.samePosition(in: text.unicodeScalars) != nil,
              upperUTF16.samePosition(in: text.unicodeScalars) != nil else { return nil }
        let midpoint = Double(current.location) + (Double(current.length) / 2)
        return min(max(midpoint / Double(count), 0), 1)
    }

    /// Converts a UTF-16 `NSRange` over `string` into the matching
    /// `AttributedString` index range. Returns `nil` if the range can't be
    /// mapped (stale/clamped input), so the caller simply skips that highlight.
    private static func attributedRange(
        _ nsRange: NSRange,
        in string: String,
        attr: AttributedString
    ) -> Range<AttributedString.Index>? {
        guard let strRange = Range(nsRange, in: string),
              let lower = AttributedString.Index(strRange.lowerBound, within: attr),
              let upper = AttributedString.Index(strRange.upperBound, within: attr) else {
            return nil
        }
        return lower..<upper
    }
}

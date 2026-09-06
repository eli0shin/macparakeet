import Foundation

/// Pre-compiled, reusable custom-word replacement.
///
/// Build once from a set of `CustomWord`s, then apply to many strings. The
/// deterministic dictation pipeline only ever corrects one string per call.
/// Completed-meeting cleanup and Reading Turn projection reuse the same rules,
/// so this type keeps their replacement semantics identical.
///
/// Semantics match the original inline `TextProcessingPipeline.applyCustomWords`
/// exactly, and `CustomWordReplacerTests` pins that parity:
/// - only `isEnabled` words contribute a rule,
/// - whole-word (`\b…\b`), case-insensitive matching,
/// - rules apply in array order, so a later rule can act on an earlier rule's
///   output,
/// - `replacement == nil` or blank (a vocabulary anchor) substitutes the word
///   with itself,
/// - a word whose pattern fails to compile is skipped silently.
struct CustomWordReplacer: Sendable {
    private struct Rule: Sendable {
        let regex: NSRegularExpression
        let template: String
    }

    private let rules: [Rule]

    init(words: [CustomWord]) {
        rules = words.compactMap { word in
            guard word.isEnabled else { return nil }
            let replacement = word.replacement?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let template = if let replacement, !replacement.isEmpty {
                replacement
            } else {
                word.word
            }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word.word))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }
            return Rule(regex: regex, template: NSRegularExpression.escapedTemplate(for: template))
        }
    }

    /// True when no enabled word produced a usable rule — callers can skip work.
    var isEmpty: Bool { rules.isEmpty }

    /// Apply every rule, in order, to `text`.
    func apply(to text: String) -> String {
        guard !rules.isEmpty, !text.isEmpty else { return text }

        var result = text
        for rule in rules {
            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: rule.template
            )
        }
        return result
    }
}

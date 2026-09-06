import Foundation

/// Shared conservative filler policy for deterministic text cleanup.
enum DeterministicFillerPolicy {
    static let alwaysSafeFillers: Set<String> = ["uh", "umm", "uhh"]

    private static let regexes: [NSRegularExpression] = alwaysSafeFillers.compactMap { filler in
        try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: filler))\\b",
            options: .caseInsensitive
        )
    }

    static func removeFillers(from text: String) -> String {
        regexes.reduce(text) { result, regex in
            regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
    }

    static func contains(_ token: String) -> Bool {
        let key =
            token
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .lowercased()
        return !key.isEmpty && alwaysSafeFillers.contains(key)
    }
}

/// Derives readable meeting text without changing transcript evidence or using
/// dictation-only snippets, actions, insertion styling, or an LLM.
public enum MeetingTranscriptCleaner {
    public static func applicableCustomWords(_ customWords: [CustomWord], to rawTranscript: String) -> [CustomWord] {
        var workingText = rawTranscript
        return customWords.filter { customWord in
            let fullRange = NSRange(workingText.startIndex..., in: workingText)
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: customWord.word))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return false
            }
            let matches = regex.matches(in: workingText, range: fullRange)
            guard !matches.isEmpty else { return false }

            if let replacement = customWord.replacement?.trimmingCharacters(in: .whitespacesAndNewlines),
                !replacement.isEmpty,
                replacement.caseInsensitiveCompare(customWord.word) != .orderedSame,
                replacement.localizedCaseInsensitiveContains(customWord.word),
                let replacementRegex = try? NSRegularExpression(
                    pattern: NSRegularExpression.escapedPattern(for: replacement),
                    options: .caseInsensitive
                )
            {
                let replacementRanges = replacementRegex.matches(in: workingText, range: fullRange).map(\.range)
                guard
                    matches.contains(where: { match in
                        !replacementRanges.contains { NSLocationInRange(match.range.location, $0) }
                    })
                else {
                    return false
                }
            }

            workingText = CustomWordReplacer(words: [customWord]).apply(to: workingText)
            return true
        }
    }

    public static func preferredText(
        for transcription: Transcription,
        customWords: [CustomWord] = []
    ) -> String {
        if transcription.sourceType == .meeting {
            if let cleanTranscript = transcription.cleanTranscript {
                return cleanTranscript
            }
            return clean(
                rawTranscript: transcription.rawTranscript ?? "",
                customWords: customWords
            )
        }
        return transcription.cleanTranscript ?? transcription.rawTranscript ?? ""
    }

    public static func clean(
        rawTranscript: String,
        customWords: [CustomWord]
    ) -> String {
        MeetingTranscriptPresentationBuilder.cleanTranscriptText(
            rawTranscript,
            customWords: applicableCustomWords(customWords, to: rawTranscript)
        )
    }
}

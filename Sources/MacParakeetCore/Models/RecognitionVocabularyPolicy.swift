import Foundation

/// Shared app/CLI rules. Existing unsupported entries remain stored and can be disabled.
public enum RecognitionVocabularyPolicy {
    public static let minimumTermLength = 3
    public static let maximumEnabledTerms = 100

    public static func isVocabularyWord(_ word: CustomWord) -> Bool {
        (word.replacement ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func warning(for words: [CustomWord]) -> String? {
        let enabled = words.filter { $0.isEnabled && isVocabularyWord($0) }
        if CustomVocabularyBoostingVocabulary.mapping(from: words).terms.count > maximumEnabledTerms {
            return
                "Select at most 100 enabled vocabulary words. Hints are not applied until the list is within this limit. Stored words are kept."
        }
        if enabled.contains(where: { $0.word.trimmingCharacters(in: .whitespacesAndNewlines).count < minimumTermLength }
        ) {
            return
                "Vocabulary words shorter than three characters cannot be used as recognition hints. Their existing Clean capitalization behavior is unchanged."
        }
        return nil
    }

    public static func validateSaving(_ word: CustomWord, among words: [CustomWord]) throws {
        guard word.isEnabled, isVocabularyWord(word) else { return }
        if let old = words.first(where: { $0.id == word.id }),
            old.isEnabled, isVocabularyWord(old), old.word == word.word
        {
            return  // Do not block unrelated writes to legacy entries.
        }
        guard word.word.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumTermLength else {
            throw ValidationError("Vocabulary words need at least three characters.")
        }
        let proposed = words.filter { $0.id != word.id } + [word]
        guard CustomVocabularyBoostingVocabulary.mapping(from: proposed).terms.count <= maximumEnabledTerms else {
            throw ValidationError(
                "Select at most 100 enabled vocabulary words. Disable a word before enabling another.")
        }
    }

    public struct ValidationError: LocalizedError, Sendable {
        public let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}

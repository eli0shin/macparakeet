import Foundation
import MacParakeetCore

@MainActor
@Observable
public final class CustomWordsViewModel {
    public var words: [CustomWord] = []
    public var searchText: String = ""
    public var newWord: String = ""
    public var newReplacement: String = ""
    public var errorMessage: String?
    public var pendingDeleteWord: CustomWord?

    public var isReplacementEntry = false
    public var recognitionEnabled = false
    public var needsRecognitionConsent = false
    public var isPreparingRecognition = false
    public var recognitionStatus = RecognitionVocabularyStatus()

    private var repo: CustomWordRepositoryProtocol?
    private var defaults: UserDefaults = .standard
    private var prepareRecognition: (@Sendable () async throws -> Void)?
    private static let consentKey = UserDefaultsAppRuntimePreferences.customVocabularyRecognitionConsentKey
    private static let askedKey = UserDefaultsAppRuntimePreferences.customVocabularyRecognitionConsentAskedKey

    public init() {}

    public func configure(
        repo: CustomWordRepositoryProtocol,
        defaults: UserDefaults = .standard,
        recognitionStatus: RecognitionVocabularyStatus? = nil,
        prepareRecognition: (@Sendable () async throws -> Void)? = nil
    ) {
        self.repo = repo
        self.defaults = defaults
        self.prepareRecognition = prepareRecognition
        if let recognitionStatus { self.recognitionStatus = recognitionStatus }
        recognitionEnabled = defaults.bool(
            forKey: UserDefaultsAppRuntimePreferences.customVocabularyRecognitionBoostingEnabledKey)
        loadWords()
    }

    public var vocabularyWarning: String? { RecognitionVocabularyPolicy.warning(for: words) }

    public func requestRecognitionEnabled(_ enabled: Bool) async {
        guard !isPreparingRecognition else { return }
        if !enabled {
            recognitionEnabled = false
            defaults.set(false, forKey: UserDefaultsAppRuntimePreferences.customVocabularyRecognitionBoostingEnabledKey)
        } else if !defaults.bool(forKey: Self.consentKey) {
            needsRecognitionConsent = true
        } else {
            await enableRecognition()
        }
    }

    public func answerRecognitionConsent(_ accepted: Bool) async {
        needsRecognitionConsent = false
        defaults.set(true, forKey: Self.askedKey)
        guard accepted else { return }
        defaults.set(true, forKey: Self.consentKey)
        await enableRecognition()
    }

    private func enableRecognition() async {
        guard let prepareRecognition else {
            errorMessage = "Vocabulary preparation is unavailable."
            return
        }
        isPreparingRecognition = true
        defer { isPreparingRecognition = false }
        do {
            try await prepareRecognition()
            try Task.checkCancellation()
            defaults.set(true, forKey: UserDefaultsAppRuntimePreferences.customVocabularyRecognitionBoostingEnabledKey)
            recognitionEnabled = true
            errorMessage = nil
        } catch {
            errorMessage = "Vocabulary hints could not be prepared. Check your connection and try again."
        }
    }

    public var filteredWords: [CustomWord] {
        guard !searchText.isEmpty else { return words }
        return words.filter {
            $0.word.localizedCaseInsensitiveContains(searchText)
                || ($0.replacement?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    public func loadWords() {
        guard let repo else { return }
        if !isPreparingRecognition {
            recognitionEnabled = defaults.bool(
                forKey: UserDefaultsAppRuntimePreferences.customVocabularyRecognitionBoostingEnabledKey)
        }
        do {
            words = try repo.fetchAll()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addWord() {
        guard let repo else { return }
        let trimmedWord = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }

        // Duplicate check (case-insensitive)
        if words.contains(where: { $0.word.caseInsensitiveCompare(trimmedWord) == .orderedSame }) {
            errorMessage = "'\(trimmedWord)' already exists"
            return
        }

        let trimmedReplacement = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        let word = CustomWord(
            word: trimmedWord,
            replacement: trimmedReplacement.isEmpty ? nil : trimmedReplacement
        )

        do {
            try RecognitionVocabularyPolicy.validateSaving(word, among: try repo.fetchAll())
            try repo.save(word)
            if RecognitionVocabularyPolicy.isVocabularyWord(word),
                !recognitionEnabled, !defaults.bool(forKey: Self.askedKey)
            {
                needsRecognitionConsent = true
            }
            Telemetry.send(.customWordAdded)
            newWord = ""
            newReplacement = ""
            errorMessage = nil
            loadWords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func toggleEnabled(_ word: CustomWord) {
        guard let repo else { return }
        var updated = word
        updated.isEnabled.toggle()
        updated.updatedAt = Date()
        do {
            try RecognitionVocabularyPolicy.validateSaving(updated, among: try repo.fetchAll())
            try repo.save(updated)
            loadWords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func confirmDelete() {
        guard let word = pendingDeleteWord else { return }
        pendingDeleteWord = nil
        deleteWord(word)
    }

    public func deleteWord(_ word: CustomWord) {
        guard let repo else { return }
        do {
            _ = try repo.delete(id: word.id)
            Telemetry.send(.customWordDeleted)
            loadWords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

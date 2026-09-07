import XCTest
@testable import MacParakeetCore
@testable import MacParakeetViewModels

@MainActor
final class CustomWordsViewModelTests: XCTestCase {
    var viewModel: CustomWordsViewModel!
    var mockRepo: MockCustomWordRepository!
    var defaults: UserDefaults!
    var suiteName: String!

    override func setUp() async throws {
        mockRepo = MockCustomWordRepository()
        viewModel = CustomWordsViewModel()
        suiteName = "vocabulary-view-model-\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)!
        viewModel.configure(repo: mockRepo, defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testAddingWordDoesNotEnableOrDownloadWithoutConsent() async {
        let probe = VocabularyPreparationProbe()
        viewModel.configure(repo: mockRepo, defaults: defaults, prepareRecognition: { await probe.prepare() })
        viewModel.newWord = "MacParakeet"
        viewModel.addWord()
        XCTAssertTrue(viewModel.needsRecognitionConsent)
        XCTAssertFalse(viewModel.recognitionEnabled)
        let before = await probe.count
        XCTAssertEqual(before, 0)
        await viewModel.answerRecognitionConsent(false)
        viewModel.newWord = "FluidAudio"
        viewModel.addWord()
        XCTAssertFalse(viewModel.needsRecognitionConsent)
        let after = await probe.count
        XCTAssertEqual(after, 0)
    }

    func testConsentPreparesBeforeEnablingAndOffPreservesWords() async {
        let probe = VocabularyPreparationProbe()
        viewModel.configure(repo: mockRepo, defaults: defaults, prepareRecognition: { await probe.prepare() })
        viewModel.newWord = "MacParakeet"
        viewModel.addWord()
        await viewModel.answerRecognitionConsent(true)
        XCTAssertTrue(viewModel.recognitionEnabled)
        XCTAssertTrue(defaults.bool(forKey: UserDefaultsAppRuntimePreferences.customVocabularyRecognitionConsentKey))
        let count = await probe.count
        XCTAssertEqual(count, 1)
        await viewModel.requestRecognitionEnabled(false)
        XCTAssertFalse(viewModel.recognitionEnabled)
        XCTAssertEqual(viewModel.words.count, 1)
    }

    func testFailedPreparationDoesNotEnableHints() async {
        viewModel.configure(repo: mockRepo, defaults: defaults, prepareRecognition: { throw CancellationError() })
        await viewModel.answerRecognitionConsent(true)
        XCTAssertFalse(viewModel.recognitionEnabled)
        XCTAssertFalse(viewModel.isPreparingRecognition)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testShortVocabularyRejectedButShortReplacementAllowed() {
        viewModel.newWord = "AI"
        viewModel.addWord()
        XCTAssertTrue(viewModel.words.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
        viewModel.newReplacement = "artificial intelligence"
        viewModel.addWord()
        XCTAssertEqual(viewModel.words.count, 1)
    }

    func testLimitRejectsNewEnabledTermButPreservesLegacyListAndAllowsDisable() throws {
        for index in 0..<101 { try mockRepo.save(CustomWord(word: "Term\(index)")) }
        viewModel.loadWords()
        XCTAssertNotNil(viewModel.vocabularyWarning)
        viewModel.newWord = "MacParakeet"
        viewModel.addWord()
        XCTAssertEqual(viewModel.words.count, 101)
        XCTAssertNotNil(viewModel.errorMessage)
        viewModel.toggleEnabled(try XCTUnwrap(viewModel.words.first))
        XCTAssertNil(viewModel.vocabularyWarning)
        viewModel.newReplacement = "replacement"
        viewModel.addWord()
        XCTAssertEqual(viewModel.words.count, 102)
    }

    func testInitialState() {
        XCTAssertTrue(viewModel.words.isEmpty)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.newWord, "")
        XCTAssertEqual(viewModel.newReplacement, "")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testAddWord() {
        viewModel.newWord = "kubernetes"
        viewModel.newReplacement = "Kubernetes"
        viewModel.addWord()

        XCTAssertEqual(viewModel.words.count, 1)
        XCTAssertEqual(viewModel.words.first?.word, "kubernetes")
        XCTAssertEqual(viewModel.words.first?.replacement, "Kubernetes")
        XCTAssertEqual(viewModel.newWord, "")
        XCTAssertEqual(viewModel.newReplacement, "")
    }

    func testAddVocabularyAnchor() {
        viewModel.newWord = "MacParakeet"
        viewModel.addWord()

        XCTAssertEqual(viewModel.words.count, 1)
        XCTAssertNil(viewModel.words.first?.replacement)
    }

    func testAddEmptyWordIgnored() {
        viewModel.newWord = "  "
        viewModel.addWord()

        XCTAssertTrue(viewModel.words.isEmpty)
    }

    func testAddDuplicateShowsError() {
        viewModel.newWord = "test"
        viewModel.addWord()
        XCTAssertNil(viewModel.errorMessage)

        viewModel.newWord = "TEST"
        viewModel.addWord()
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.words.count, 1)
    }

    func testToggleEnabled() {
        viewModel.newWord = "test"
        viewModel.newReplacement = "Test"
        viewModel.addWord()
        XCTAssertTrue(viewModel.words.first?.isEnabled ?? false)

        viewModel.toggleEnabled(viewModel.words.first!)
        XCTAssertFalse(viewModel.words.first?.isEnabled ?? true)
    }

    func testDeleteWord() {
        viewModel.newWord = "test"
        viewModel.addWord()
        XCTAssertEqual(viewModel.words.count, 1)

        viewModel.deleteWord(viewModel.words.first!)
        XCTAssertTrue(viewModel.words.isEmpty)
    }

    func testFilteredWords() {
        viewModel.newWord = "kubernetes"
        viewModel.newReplacement = "Kubernetes"
        viewModel.addWord()

        viewModel.newWord = "docker"
        viewModel.newReplacement = "Docker"
        viewModel.addWord()

        viewModel.searchText = "kube"
        XCTAssertEqual(viewModel.filteredWords.count, 1)
        XCTAssertEqual(viewModel.filteredWords.first?.word, "kubernetes")
    }

    func testFilteredWordsEmptySearch() {
        viewModel.newWord = "test"
        viewModel.addWord()

        viewModel.searchText = ""
        XCTAssertEqual(viewModel.filteredWords.count, 1)
    }
}

private actor VocabularyPreparationProbe {
    var count = 0
    func prepare() { count += 1 }
}

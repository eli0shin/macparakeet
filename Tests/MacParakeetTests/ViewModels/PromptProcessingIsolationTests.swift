import XCTest
@testable import MacParakeetCore
@testable import MacParakeetViewModels

/// Integration coverage across the completion entry point, application queue,
/// SQLite persistence/observation, and transcript-scoped presentation state.
@MainActor
final class PromptProcessingIsolationTests: XCTestCase {
    @MainActor
    private struct Fixture {
        let queue = PromptGenerationQueue()
        let transcriptions: TranscriptionRepository
        let results: PromptResultRepository
        let llm = MockLLMService()
        let prompts = MockPromptRepository()
        let streams = ControlledPromptStreams()
        let first: Transcription
        let second: Transcription

        init() throws {
            let database = try DatabaseManager()
            transcriptions = TranscriptionRepository(dbQueue: database.dbQueue)
            results = PromptResultRepository(dbQueue: database.dbQueue)
            first = Transcription(
                fileName: "Meeting one", rawTranscript: "First transcript", status: .completed, sourceType: .meeting)
            second = Transcription(
                fileName: "Meeting two", rawTranscript: "Second transcript", status: .completed, sourceType: .meeting)
            try transcriptions.save(first)
            try transcriptions.save(second)
            prompts.prompts = [
                Prompt(name: "Summary", content: "Summarize", isAutoRun: true, sortOrder: 0),
                Prompt(name: "Action Items", content: "Extract actions", isAutoRun: true, sortOrder: 1),
            ]
            let streams = streams
            llm.promptResultStream = { streams.makeStream() }
            queue.configure(
                llmService: llm, promptRepo: prompts, promptResultRepo: results, transcriptionRepo: transcriptions)
        }

        func detail(_ transcription: Transcription) -> PromptResultsViewModel {
            let detail = PromptResultsViewModel(generationQueue: queue)
            detail.configure(promptRepo: prompts, promptResultRepo: results)
            detail.loadPersistedContentAsync(transcriptionId: transcription.id)
            return detail
        }

        func savedResult(_ transcription: Transcription, content: String = "Saved summary") throws -> PromptResult {
            let result = PromptResult(
                transcriptionId: transcription.id, promptName: "Summary", promptContent: "Summarize", content: content)
            try results.save(result)
            return result
        }
    }

    private func waitUntil(
        file: StaticString = #filePath, line: UInt = #line,
        _ condition: () throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while try !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for prompt processing state", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func testBackgroundMeetingCompletionCannotAddTabsOrUnreadMarkersToOpenMeeting() async throws {
        let f = try Fixture()
        let firstSummary = try f.savedResult(f.first)
        let detail = f.detail(f.first)
        try await waitUntil { !detail.isLoadingResults }
        let transcription = TranscriptionViewModel()
        transcription.configure(
            transcriptionService: MockTranscriptionService(), transcriptionRepo: f.transcriptions,
            promptGenerationQueue: f.queue)
        transcription.currentTranscription = f.first
        transcription.selectedTab = .result(id: firstSummary.id)

        transcription.presentCompletedTranscription(
            f.second, autoSave: false, runAutoPrompts: true, selectTranscription: false
        )
        XCTAssertEqual(f.queue.pendingGenerations.count, 2)
        XCTAssertTrue(detail.pendingGenerations.isEmpty)
        XCTAssertTrue(detail.canSelectModel == false)
        for index in 0..<2 {
            try await waitUntil { f.streams.count > index }
            f.streams.finish(index, content: "Meeting two result \(index)")
            try await waitUntil { try f.results.count(transcriptionId: f.second.id) == index + 1 }
            XCTAssertEqual(detail.promptResults.map(\.id), [firstSummary.id])
            XCTAssertTrue(detail.unreadPromptResultIDs.isEmpty)
        }
        XCTAssertEqual(transcription.currentTranscription?.id, f.first.id)
        XCTAssertEqual(transcription.selectedTab, .result(id: firstSummary.id))
        XCTAssertEqual(detail.reconciledTab(transcription.selectedTab), transcription.selectedTab)

        detail.loadPersistedContentAsync(transcriptionId: f.second.id)
        try await waitUntil { detail.promptResults.count == 2 }
        XCTAssertTrue(detail.promptResults.allSatisfy { $0.transcriptionId == f.second.id })
        detail.loadPersistedContentAsync(transcriptionId: f.first.id)
        try await waitUntil { detail.promptResults.map(\.id) == [firstSummary.id] }
    }

    func testNavigationAndViewReleaseDoNotCancelQueuedOrStreamingJobs() async throws {
        let f = try Fixture()
        var detail: PromptResultsViewModel? = f.detail(f.first)
        weak var releasedDetail = detail
        try await waitUntil { detail?.isLoadingResults == false }
        let jobs = f.queue.autoGeneratePromptResults(
            transcript: "First transcript", transcriptionId: f.first.id, sourceType: .meeting)
        try await waitUntil { f.streams.count == 1 }
        detail?.loadPersistedContentAsync(transcriptionId: f.second.id)
        XCTAssertTrue(detail?.pendingGenerations.isEmpty == true)
        XCTAssertEqual(f.queue.pendingGenerations.count, 2)
        detail = nil
        XCTAssertNil(releasedDetail)

        f.streams.finish(0, content: "Summary after leaving")
        try await waitUntil { f.streams.count == 2 }
        f.streams.finish(1, content: "Actions after leaving")
        try await waitUntil { try f.results.count(transcriptionId: f.first.id) == 2 }
        XCTAssertEqual(Set(try f.results.fetchAll(transcriptionId: f.first.id).map(\.id)), Set(jobs))
        let reopened = f.detail(f.first)
        try await waitUntil { reopened.promptResults.count == 2 }
        XCTAssertTrue(reopened.unreadPromptResultIDs.isEmpty)
    }

    func testTwoDetailsObserveOnlyTheirResultsIncludingWritesOutsideTheQueue() async throws {
        let f = try Fixture()
        let first = f.detail(f.first)
        let second = f.detail(f.second)
        try await waitUntil { !first.isLoadingResults && !second.isLoadingResults }
        let saved = try f.savedResult(f.second)
        try await waitUntil { second.promptResults.map(\.id) == [saved.id] }
        XCTAssertTrue(first.promptResults.isEmpty)
        XCTAssertTrue(first.unreadPromptResultIDs.isEmpty)
        XCTAssertEqual(second.unreadPromptResultIDs, [saved.id])
        XCTAssertEqual(second.reconciledTab(.result(id: saved.id)), .result(id: saved.id))
        XCTAssertTrue(second.unreadPromptResultIDs.isEmpty)

        let replacement = PromptResult(
            transcriptionId: f.second.id, promptName: "Summary", promptContent: "Summarize", content: "Replacement")
        try f.results.replace(replacement, deletingExistingID: saved.id)
        try await waitUntil { second.promptResults.map(\.id) == [replacement.id] }
        XCTAssertEqual(second.unreadPromptResultIDs, [replacement.id])
        XCTAssertEqual(second.reconciledTab(.result(id: saved.id)), .transcript)
        second.deletePromptResult(replacement)
        try await waitUntil { second.promptResults.isEmpty }
        XCTAssertTrue(second.unreadPromptResultIDs.isEmpty)
        XCTAssertTrue(first.promptResults.isEmpty)
    }

    func testMatchingCompletionUpdatesSelectedGenerationAndMarksOnlyOtherResultsUnread() async throws {
        let f = try Fixture()
        let detail = f.detail(f.first)
        try await waitUntil { !detail.isLoadingResults }
        let ids = f.queue.autoGeneratePromptResults(
            transcript: "First", transcriptionId: f.first.id, sourceType: .meeting)
        try await waitUntil { f.streams.count == 1 }
        f.streams.finish(0, content: "Summary")
        try await waitUntil { detail.promptResults.contains { $0.id == ids[0] } }
        XCTAssertEqual(detail.reconciledTab(.generation(id: ids[0])), .result(id: ids[0]))
        XCTAssertFalse(detail.hasUnreadPromptResult(ids[0]))
        try await waitUntil { f.streams.count == 2 }
        f.streams.finish(1, content: "Actions")
        try await waitUntil { detail.promptResults.count == 2 }
        XCTAssertEqual(detail.reconciledTab(.result(id: ids[0])), .result(id: ids[0]))
        XCTAssertEqual(detail.unreadPromptResultIDs, [ids[1]])
    }

    func testCompletionBeforeObservationDeliveryStillResolvesSelectedGeneration() async throws {
        let f = try Fixture()
        let detail = f.detail(f.first)
        try await waitUntil { !detail.isLoadingResults }
        // A committed result may exist before its observation is delivered to MainActor.
        let saved = try f.savedResult(f.first)
        XCTAssertTrue(detail.promptResults.isEmpty)
        XCTAssertEqual(detail.reconciledTab(.generation(id: saved.id)), .result(id: saved.id))
        XCTAssertEqual(detail.promptResults.map(\.id), [saved.id])
        XCTAssertFalse(detail.hasUnreadPromptResult(saved.id))
        // Navigation immediately after reconciliation must reject the old observation.
        detail.loadPersistedContentAsync(transcriptionId: f.second.id)
        try await waitUntil { !detail.isLoadingResults }
        XCTAssertTrue(detail.promptResults.isEmpty)
    }

    func testFailureRetryAndExplicitCancellationRemainScopedAcrossNavigation() async throws {
        let f = try Fixture()
        let detail = f.detail(f.first)
        try await waitUntil { !detail.isLoadingResults }
        let id = try XCTUnwrap(detail.generatePromptResult(transcript: "First", transcriptionId: f.first.id))
        try await waitUntil { f.streams.count == 1 }
        detail.loadPersistedContentAsync(transcriptionId: f.second.id)
        f.streams.fail(0)
        try await waitUntil { !f.queue.hasActiveGenerations }
        XCTAssertTrue(detail.pendingGenerations.isEmpty)
        XCTAssertNil(detail.errorMessage)
        XCTAssertNil(detail.retryGeneration(id: id))
        detail.loadPersistedContentAsync(transcriptionId: f.first.id)
        guard case .failed = detail.pendingGeneration(id: id)?.state else {
            return XCTFail("Failure must survive navigation")
        }
        let retry = try XCTUnwrap(detail.retryGeneration(id: id))
        try await waitUntil { f.streams.count == 2 }
        detail.cancelGeneration(id: retry)
        try await waitUntil { !f.queue.hasActiveGenerations }
        XCTAssertEqual(detail.reconciledTab(.generation(id: retry)), .transcript)
        XCTAssertEqual(try f.results.count(transcriptionId: f.first.id), 0)
    }

    func testImmediateCancellationReleasesWorkerSlotForNextJob() async throws {
        let f = try Fixture()
        let first = try XCTUnwrap(
            f.queue.generatePromptResult(
                transcript: "First", transcriptionId: f.first.id, prompt: f.prompts.prompts[0]
            ))
        // Cancel before the MainActor worker gets its first turn.
        f.queue.cancelGeneration(id: first)
        let second = try XCTUnwrap(
            f.queue.generatePromptResult(
                transcript: "Second", transcriptionId: f.second.id, prompt: f.prompts.prompts[0]
            ))
        try await waitUntil { f.streams.count == 1 }
        guard f.streams.count == 1 else { return }
        XCTAssertNil(f.queue.pendingGeneration(id: first))
        f.streams.finish(0, content: "Second summary")
        try await waitUntil { !f.queue.hasActiveGenerations }
        XCTAssertEqual(try f.results.count(transcriptionId: f.first.id), 0)
        XCTAssertEqual(try f.results.fetchAll(transcriptionId: f.second.id).map(\.id), [second])
    }

    func testCancelledOldWorkerCannotClearReplacementWorker() async throws {
        let f = try Fixture()
        _ = f.queue.autoGeneratePromptResults(transcript: "First", transcriptionId: f.first.id, sourceType: .meeting)
        try await waitUntil { f.streams.count == 1 }
        f.queue.updateLLMService(f.llm)
        let newJobs = f.queue.autoGeneratePromptResults(
            transcript: "Second", transcriptionId: f.second.id, sourceType: .meeting)
        try await waitUntil { f.streams.count == 2 }
        f.streams.finish(0, content: "Cancelled old result")
        f.streams.finish(1, content: "New summary")
        try await waitUntil { f.streams.count == 3 }
        f.streams.finish(2, content: "New actions")
        try await waitUntil { !f.queue.hasActiveGenerations }
        XCTAssertEqual(try f.results.count(transcriptionId: f.first.id), 0)
        XCTAssertEqual(Set(try f.results.fetchAll(transcriptionId: f.second.id).map(\.id)), Set(newJobs))
    }
}

private final class ControlledPromptStreams: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<String, Error>.Continuation] = []
    var count: Int { lock.withLock { continuations.count } }

    func makeStream() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock { continuations.append(continuation) }
        }
    }

    func finish(_ index: Int, content: String) {
        let continuation = lock.withLock { continuations[index] }
        continuation.yield(content)
        continuation.finish()
    }

    func fail(_ index: Int) {
        let continuation = lock.withLock { continuations[index] }
        continuation.finish(throwing: LLMError.streamingError("Test failure"))
    }
}

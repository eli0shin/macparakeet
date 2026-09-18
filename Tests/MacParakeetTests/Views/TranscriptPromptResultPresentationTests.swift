import AppKit
import SwiftUI
import XCTest
import MacParakeetCore
import MacParakeetViewModels
@testable import MacParakeet

@MainActor
final class TranscriptPromptResultPresentationTests: XCTestCase {
    func testHostedDetailPreservesSelectionForOtherMeetingsAndFollowsItsOwnGeneration() async throws {
        let database = try DatabaseManager()
        let transcriptions = TranscriptionRepository(dbQueue: database.dbQueue)
        let results = PromptResultRepository(dbQueue: database.dbQueue)
        let prompts = MockPromptRepository()
        prompts.prompts = [Prompt(name: "Summary", content: "Summarize", isAutoRun: true)]
        let first = Transcription(
            fileName: "Meeting one", rawTranscript: "First meeting", status: .completed, sourceType: .meeting)
        let second = Transcription(
            fileName: "Meeting two", rawTranscript: "Second meeting", status: .completed, sourceType: .meeting)
        try transcriptions.save(first)
        try transcriptions.save(second)
        let original = PromptResult(
            transcriptionId: first.id, promptName: "Summary", promptContent: "Summarize", content: "First summary")
        try results.save(original)
        let llm = MockLLMService()
        llm.streamTokens = ["Generated summary"]
        let queue = PromptGenerationQueue()
        queue.configure(llmService: llm, promptRepo: prompts, promptResultRepo: results)
        let detail = PromptResultsViewModel(generationQueue: queue)
        detail.configure(promptRepo: prompts, promptResultRepo: results)
        let transcription = TranscriptionViewModel()
        transcription.configure(
            transcriptionService: MockTranscriptionService(), transcriptionRepo: transcriptions,
            llmService: llm, promptResultRepo: results, promptGenerationQueue: queue
        )
        transcription.currentTranscription = first
        let root = TranscriptResultView(
            transcription: first, viewModel: transcription,
            chatViewModel: TranscriptChatViewModel(), promptResultsViewModel: detail,
            promptsViewModel: PromptsViewModel(), customWords: []
        )
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 1_000, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await waitUntil { detail.promptResults.map(\.id) == [original.id] }
        transcription.selectedTab = .result(id: original.id)

        transcription.presentCompletedTranscription(
            second, autoSave: false, runAutoPrompts: true, selectTranscription: false)
        try await waitUntil { try results.count(transcriptionId: second.id) == 1 }
        XCTAssertEqual(transcription.currentTranscription?.id, first.id)
        XCTAssertEqual(transcription.selectedTab, .result(id: original.id))
        XCTAssertEqual(detail.promptResults.map(\.id), [original.id])
        XCTAssertTrue(detail.unreadPromptResultIDs.isEmpty)

        let generation = try XCTUnwrap(
            detail.generatePromptResult(transcript: "First meeting", transcriptionId: first.id))
        transcription.selectedTab = .generation(id: generation)
        // The production view, not this test, must reconcile the selected tab.
        try await waitUntil { transcription.selectedTab == .result(id: generation) }
        XCTAssertEqual(Set(detail.promptResults.map(\.id)), [original.id, generation])
        XCTAssertFalse(detail.hasUnreadPromptResult(generation))
        XCTAssertTrue(transcription.hasPromptResultTabs)

        let generated = try XCTUnwrap(detail.promptResults.first { $0.id == generation })
        detail.deletePromptResult(generated)
        try await waitUntil { transcription.selectedTab == .transcript }
        XCTAssertEqual(detail.promptResults.map(\.id), [original.id])
    }

    private func waitUntil(
        file: StaticString = #filePath, line: UInt = #line,
        _ condition: () throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while try !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Hosted transcript did not reach the expected result state", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

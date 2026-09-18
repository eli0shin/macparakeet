import AppKit
import SwiftUI
import XCTest
import MacParakeetCore
import MacParakeetViewModels
@testable import MacParakeet

@MainActor
final class TranscriptDetailInvalidationDomainTests: XCTestCase {
    func testEachProductionPresentationModuleCanBeHostedThroughTranscriptDetail() {
        for module in TranscriptDetailPresentationModule.allCases {
            let transcription = makeTranscription()
            let transcriptionViewModel = TranscriptionViewModel()
            transcriptionViewModel.currentTranscription = transcription
            var evaluations: [TranscriptDetailPresentationModule: Int] = [:]
            var playerViewModel: MediaPlayerViewModel?
            let root = TranscriptResultView(
                transcription: transcription,
                viewModel: transcriptionViewModel,
                chatViewModel: TranscriptChatViewModel(),
                promptResultsViewModel: PromptResultsViewModel(generationQueue: PromptGenerationQueue()),
                promptsViewModel: PromptsViewModel(),
                customWords: [],
                playbackViewModelProbe: { playerViewModel = $0 },
                moduleEvaluationProbe: { evaluations[$0, default: 0] += 1 },
                hostedPresentationModule: module
            )
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
            let window = NSWindow(
                contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            window.orderFront(nil)

            let deadline = Date().addingTimeInterval(2)
            var drovePlaybackTick = false
            while evaluations[module, default: 0] == 0, Date() < deadline {
                host.layoutSubtreeIfNeeded()
                if module == .playbackFollow, let playerViewModel, !drovePlaybackTick {
                    playerViewModel.currentTimeMs = 100
                    drovePlaybackTick = true
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }

            XCTAssertGreaterThan(
                evaluations[module, default: 0],
                0,
                "The production \(module.rawValue) module did not render"
            )
            window.orderOut(nil)
        }
    }

    func testFindQueryInvalidatesOnlyFindAndTranscriptProductionModules() {
        let transcription = makeTranscription()
        let transcriptionViewModel = TranscriptionViewModel()
        transcriptionViewModel.currentTranscription = transcription
        transcriptionViewModel.updateLLMAvailability(true)
        var evaluations: [TranscriptDetailPresentationModule: Int] = [:]
        var findSessionDriver: TranscriptFindSessionDriver?
        let root = TranscriptResultView(
            transcription: transcription,
            viewModel: transcriptionViewModel,
            chatViewModel: TranscriptChatViewModel(),
            promptResultsViewModel: PromptResultsViewModel(generationQueue: PromptGenerationQueue()),
            promptsViewModel: PromptsViewModel(),
            customWords: [],
            moduleEvaluationProbe: { evaluations[$0, default: 0] += 1 },
            findSessionDriverProbe: { findSessionDriver = $0 }
        )
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let deadline = Date().addingTimeInterval(2)
        while findSessionDriver == nil, Date() < deadline {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        settle()
        let before = evaluations

        findSessionDriver?.setQuery("hello")
        settle()

        XCTAssertGreaterThan(evaluations[.findSession, default: 0], before[.findSession, default: 0])
        XCTAssertGreaterThan(
            evaluations[.transcriptDocument, default: 0],
            before[.transcriptDocument, default: 0]
        )
        for module in [
            TranscriptDetailPresentationModule.header,
            .actions,
            .playbackFollow,
            .speakerEditing,
            .aiPanes,
        ] {
            XCTAssertEqual(
                evaluations[module, default: 0],
                before[module, default: 0],
                "Find invalidated \(module.rawValue)"
            )
        }
    }

    private func makeTranscription() -> Transcription {
        let words = [
            WordTimestamp(
                word: "hello",
                startMs: 0,
                endMs: 500,
                confidence: 1,
                speakerId: "speaker-1"
            )
        ]
        let readingTurn = ReadingTurn(
            id: ReadingTurnIdentity(source: .system, speakerId: "speaker-1", firstWordIndex: 0),
            speakerId: "speaker-1",
            speakerLabel: "Ada",
            source: .system,
            timeRange: ReadingTurnTimeRange(startMs: 0, endMs: 500),
            paragraphs: [ReadingTurnParagraph(text: "hello", wordReferences: [0])],
            wordReferences: [0]
        )
        return Transcription(
            fileName: "Meeting.m4a",
            durationMs: 500,
            rawTranscript: "hello",
            wordTimestamps: words,
            speakers: [SpeakerInfo(id: "speaker-1", label: "Ada")],
            readingDocument: MeetingTranscriptPresentationDocument(turns: [readingTurn]),
            status: .completed,
            sourceType: .meeting
        )
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }
}

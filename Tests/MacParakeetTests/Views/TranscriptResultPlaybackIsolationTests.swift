import AppKit
import SwiftUI
import XCTest
import MacParakeetCore
import MacParakeetViewModels
@testable import MacParakeet

@MainActor
final class TranscriptResultPlaybackIsolationTests: XCTestCase {
    func testCompletedMeetingReadingPlaybackTicksDoNotRebuildDetailOrHeader() {
        assertPlaybackTicksDoNotRebuildDetailOrHeader(isTranscriptEdited: false)
    }

    func testCompletedMeetingTextPlaybackTicksDoNotRebuildDetailOrHeader() {
        assertPlaybackTicksDoNotRebuildDetailOrHeader(isTranscriptEdited: true)
    }

    private func assertPlaybackTicksDoNotRebuildDetailOrHeader(isTranscriptEdited: Bool) {
        let words = [
            WordTimestamp(word: "hello", startMs: 0, endMs: 4_000, confidence: 1, speakerId: "microphone"),
            WordTimestamp(word: "world", startMs: 4_001, endMs: 8_000, confidence: 1, speakerId: "system")
        ]
        let turns = [
            ReadingTurn(
                id: ReadingTurnIdentity(source: .microphone, speakerId: "microphone", firstWordIndex: 0),
                speakerId: "microphone",
                speakerLabel: "Me",
                source: .microphone,
                timeRange: ReadingTurnTimeRange(startMs: 0, endMs: 4_000),
                paragraphs: [ReadingTurnParagraph(text: "hello", wordReferences: [0])],
                wordReferences: [0]
            ),
            ReadingTurn(
                id: ReadingTurnIdentity(source: .system, speakerId: "system", firstWordIndex: 1),
                speakerId: "system",
                speakerLabel: "Speaker 1",
                source: .system,
                timeRange: ReadingTurnTimeRange(startMs: 4_001, endMs: 8_000),
                paragraphs: [ReadingTurnParagraph(text: "world", wordReferences: [1])],
                wordReferences: [1]
            )
        ]
        let transcription = Transcription(
            fileName: "Meeting.m4a",
            durationMs: 8_000,
            rawTranscript: "hello world",
            cleanTranscript: isTranscriptEdited ? "hello world edited" : nil,
            wordTimestamps: words,
            speakers: [
                SpeakerInfo(id: "microphone", label: "Me"),
                SpeakerInfo(id: "system", label: "Speaker 1")
            ],
            readingDocument: MeetingTranscriptPresentationDocument(turns: turns),
            status: .completed,
            sourceType: .meeting,
            isTranscriptEdited: isTranscriptEdited
        )
        let transcriptionViewModel = TranscriptionViewModel()
        transcriptionViewModel.currentTranscription = transcription
        var playerViewModel: MediaPlayerViewModel?
        var detailEvaluationCount = 0
        var headerEvaluationCount = 0
        let root = TranscriptResultView(
            transcription: transcription,
            viewModel: transcriptionViewModel,
            chatViewModel: TranscriptChatViewModel(),
            promptResultsViewModel: PromptResultsViewModel(),
            promptsViewModel: PromptsViewModel(),
            customWords: [],
            playbackViewModelProbe: { playerViewModel = $0 },
            detailEvaluationProbe: { detailEvaluationCount += 1 },
            headerEvaluationProbe: { headerEvaluationCount += 1 }
        )
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 1_000, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let deadline = Date().addingTimeInterval(2)
        while !isSurfaceReady(
            in: host,
            isTextMode: isTranscriptEdited,
            playerViewModel: playerViewModel,
            headerEvaluationCount: headerEvaluationCount
        ), Date() < deadline {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        guard let playerViewModel else {
            XCTFail("Completed meeting detail did not finish rendering")
            return
        }
        if isTranscriptEdited {
            XCTAssertNil(findTableView(in: host), "Edited meeting must render the Text surface")
        } else {
            XCTAssertNotNil(findTableView(in: host), "Unedited meeting must render the Reading surface")
        }
        playerViewModel.playbackMode = .audio
        playerViewModel.isPlaying = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let settledDetailCount = detailEvaluationCount
        let settledHeaderCount = headerEvaluationCount

        for timeMs in stride(from: 100, through: 1_000, by: 100) {
            playerViewModel.currentTimeMs = timeMs
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertGreaterThan(settledDetailCount, 0)
        XCTAssertGreaterThan(settledHeaderCount, 0)
        XCTAssertEqual(detailEvaluationCount, settledDetailCount)
        XCTAssertEqual(headerEvaluationCount, settledHeaderCount)
    }

    private func isSurfaceReady(
        in host: NSView,
        isTextMode: Bool,
        playerViewModel: MediaPlayerViewModel?,
        headerEvaluationCount: Int
    ) -> Bool {
        guard playerViewModel != nil, headerEvaluationCount > 0 else { return false }
        return isTextMode ? findTableView(in: host) == nil : findTableView(in: host) != nil
    }

    private func findTableView(in view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView { return tableView }
        return view.subviews.lazy.compactMap { self.findTableView(in: $0) }.first
    }
}

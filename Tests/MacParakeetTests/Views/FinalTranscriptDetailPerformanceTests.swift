import AppKit
import SwiftUI
import XCTest
import MacParakeetCore
import MacParakeetViewModels
@testable import MacParakeet

/// Release qualification for the complete production transcript-detail path.
/// The normal suite skips this machine-time test. Run the committed developer
/// gate to enable it with a public synthetic multi-hour meeting.
@MainActor
final class FinalTranscriptDetailPerformanceTests: XCTestCase {
    private static let enabledKey = "MACPARAKEET_FINAL_TRANSCRIPT_PERFORMANCE"
    private static let turnCount = 1_200
    private static let viewport = NSSize(width: 1_000, height: 800)

    private enum Mode: String, CaseIterable {
        case reading
        case text
    }

    private struct Fixture {
        let transcription: Transcription
        let wordCount: Int
        let utf16Count: Int
    }

    private struct Metrics {
        let initialTotal: Double
        let initialMaxFrame: Double
        let scrollMaxFrame: Double
        let playbackMaxTick: Double
        let findInputMax: Double
        let findSettledTotal: Double
        let findSettledMaxFrame: Double
        let matchCount: Int
    }

    func testProductionRendererReportsReleaseInteractionCPU() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment[Self.enabledKey] == "1",
            "Run scripts/dev/check_final_transcript_detail_performance.sh to enable the release gate."
        )

        for mode in Mode.allCases {
            let fixture = makeFixture(textMode: mode == .text)
            let metrics = try measure(mode: mode, fixture: fixture)
            print(
                String(
                    format:
                        "FINAL_TRANSCRIPT_PERF mode=%@ turns=%d words=%d utf16=%d initial_total_ms=%.6f initial_max_frame_ms=%.6f scroll_max_frame_ms=%.6f playback_max_tick_ms=%.6f find_input_max_ms=%.6f find_settled_total_ms=%.6f find_settled_max_frame_ms=%.6f matches=%d",
                    mode.rawValue,
                    Self.turnCount,
                    fixture.wordCount,
                    fixture.utf16Count,
                    metrics.initialTotal,
                    metrics.initialMaxFrame,
                    metrics.scrollMaxFrame,
                    metrics.playbackMaxTick,
                    metrics.findInputMax,
                    metrics.findSettledTotal,
                    metrics.findSettledMaxFrame,
                    metrics.matchCount
                )
            )
        }
    }

    private func measure(mode: Mode, fixture: Fixture) throws -> Metrics {
        let transcriptionViewModel = TranscriptionViewModel()
        transcriptionViewModel.currentTranscription = fixture.transcription
        transcriptionViewModel.updateLLMAvailability(true)
        var player: MediaPlayerViewModel?
        var findDriver: TranscriptFindSessionDriver?
        var findState = (query: "", isSearching: false, matchCount: 0)

        let initialStart = threadCPUSeconds()
        let root = TranscriptResultView(
            transcription: fixture.transcription,
            viewModel: transcriptionViewModel,
            chatViewModel: TranscriptChatViewModel(),
            promptResultsViewModel: PromptResultsViewModel(),
            promptsViewModel: PromptsViewModel(),
            customWords: [],
            playbackViewModelProbe: { player = $0 },
            findSessionDriverProbe: { findDriver = $0 },
            findSessionStateProbe: { query, isSearching, matchCount in
                findState = (query, isSearching, matchCount)
            }
        )
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: Self.viewport)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: Self.viewport.width, height: Self.viewport.height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let constructionCPU = millisecondsSince(initialStart)

        let initialPump = try pumpMainRunLoop(timeout: 12) {
            guard player != nil, findDriver != nil else { return false }
            switch mode {
            case .reading:
                return self.findTableView(in: host)?.numberOfRows == Self.turnCount + 1
            case .text:
                return self.findTextView(in: host)?.string.utf16.count == fixture.utf16Count
            }
        }
        let initialTotal = millisecondsSince(initialStart)
        let initialMaxFrame = max(constructionCPU, initialPump.maxFrameMilliseconds)

        let scrollView: NSScrollView
        switch mode {
        case .reading:
            scrollView = try XCTUnwrap(findTableView(in: host)?.enclosingScrollView)
        case .text:
            scrollView = try XCTUnwrap(findTextView(in: host)?.enclosingScrollView)
        }
        let scrollMaxFrame = scrollNormally(scrollView)

        let measuredPlayer = try XCTUnwrap(player)
        let baseTime = Int(Double(fixture.transcription.durationMs ?? 0) * 0.8)
        measuredPlayer.playbackMode = .audio
        measuredPlayer.playerState = .ready
        measuredPlayer.currentTimeMs = baseTime
        measuredPlayer.isPlaying = true
        switch mode {
        case .reading:
            let expectedTurnRow = Int(Double(Self.turnCount) * 0.8)
            _ = try pumpMainRunLoop(timeout: 3) {
                guard let tableView = self.findTableView(in: host) else { return false }
                return tableView.rows(in: tableView.visibleRect).contains(expectedTurnRow)
            }
        case .text:
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        var playbackMaxTick = 0.0
        for tick in 0..<120 {
            let start = threadCPUSeconds()
            measuredPlayer.currentTimeMs = baseTime + tick * 1_000
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            playbackMaxTick = max(playbackMaxTick, millisecondsSince(start))
        }

        let measuredFindDriver = try XCTUnwrap(findDriver)
        measuredFindDriver.setQuery("")
        _ = try pumpMainRunLoop(timeout: 2) { findState.query.isEmpty }

        var findInputMax = 0.0
        for query in ["p", "pu", "pub", "publ", "publi", "public"] {
            let start = threadCPUSeconds()
            measuredFindDriver.setQuery(query)
            findInputMax = max(findInputMax, millisecondsSince(start))
        }
        let findSettledStart = threadCPUSeconds()
        let settledPump = try pumpMainRunLoop(timeout: 12) {
            findState.query == "public" && !findState.isSearching && findState.matchCount > 0
        }

        XCTAssertGreaterThan(findState.matchCount, Self.turnCount)
        return Metrics(
            initialTotal: initialTotal,
            initialMaxFrame: initialMaxFrame,
            scrollMaxFrame: scrollMaxFrame,
            playbackMaxTick: playbackMaxTick,
            findInputMax: findInputMax,
            findSettledTotal: millisecondsSince(findSettledStart),
            findSettledMaxFrame: settledPump.maxFrameMilliseconds,
            matchCount: findState.matchCount
        )
    }

    private func makeFixture(textMode: Bool) -> Fixture {
        let vocabulary = [
            "public", "synthetic", "meeting", "decision", "context", "action", "owner", "followup",
        ]
        let speakers = [
            SpeakerInfo(id: "microphone", label: "Me"),
            SpeakerInfo(id: "system:S1", label: "Speaker 1"),
            SpeakerInfo(id: "system:S2", label: "Speaker 2"),
            SpeakerInfo(id: "system:S3", label: "Speaker 3"),
        ]
        var words: [WordTimestamp] = []
        var turns: [ReadingTurn] = []
        var paragraphs: [String] = []
        words.reserveCapacity(72_000)
        turns.reserveCapacity(Self.turnCount)
        paragraphs.reserveCapacity(Self.turnCount)

        for turnIndex in 0..<Self.turnCount {
            let speaker = speakers[turnIndex % speakers.count]
            let source: ReadingTurnSource = speaker.id == "microphone" ? .microphone : .system
            let wordsInTurn = [24, 48, 72, 96][turnIndex % 4]
            let firstWordIndex = words.count
            var turnWords: [String] = []
            turnWords.reserveCapacity(wordsInTurn)
            for wordOffset in 0..<wordsInTurn {
                let word = vocabulary[(turnIndex + wordOffset) % vocabulary.count]
                let wordIndex = words.count
                let startMs = wordIndex * 250
                words.append(
                    WordTimestamp(
                        word: word,
                        startMs: startMs,
                        endMs: startMs + 220,
                        confidence: 1,
                        speakerId: speaker.id
                    )
                )
                turnWords.append(word)
            }
            let text = turnWords.joined(separator: " ") + "."
            paragraphs.append(text)
            turns.append(
                ReadingTurn(
                    id: ReadingTurnIdentity(
                        source: source,
                        speakerId: speaker.id,
                        firstWordIndex: firstWordIndex
                    ),
                    speakerId: speaker.id,
                    speakerLabel: speaker.label,
                    source: source,
                    timeRange: ReadingTurnTimeRange(
                        startMs: firstWordIndex * 250,
                        endMs: (words.count - 1) * 250 + 220
                    ),
                    paragraphs: [
                        ReadingTurnParagraph(
                            text: text,
                            wordReferences: Array(firstWordIndex..<words.count)
                        )
                    ],
                    wordReferences: Array(firstWordIndex..<words.count)
                )
            )
        }

        let transcriptText = paragraphs.joined(separator: "\n\n")
        let durationMs = words.last?.endMs ?? 0
        let transcription = Transcription(
            fileName: "Public Synthetic Long Meeting.m4a",
            durationMs: durationMs,
            rawTranscript: transcriptText,
            cleanTranscript: textMode ? transcriptText : nil,
            wordTimestamps: words,
            speakers: speakers,
            readingDocument: MeetingTranscriptPresentationDocument(turns: turns),
            status: .completed,
            sourceType: .meeting,
            isTranscriptEdited: textMode
        )
        return Fixture(
            transcription: transcription,
            wordCount: words.count,
            utf16Count: transcriptText.utf16.count
        )
    }

    private func scrollNormally(_ scrollView: NSScrollView) -> Double {
        guard let document = scrollView.documentView else { return .infinity }
        let clipView = scrollView.contentView
        var position = max(0, clipView.bounds.minY)
        var worstFrame = 0.0
        for step in 0..<120 {
            position += step < 80 ? 120 : -120
            let maxY = max(0, document.frame.height - clipView.bounds.height)
            position = min(max(position, 0), maxY)
            let start = threadCPUSeconds()
            clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: position))
            scrollView.reflectScrolledClipView(clipView)
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            worstFrame = max(worstFrame, millisecondsSince(start))
        }
        return worstFrame
    }

    private func pumpMainRunLoop(
        timeout: TimeInterval,
        until condition: () -> Bool
    ) throws -> (maxFrameMilliseconds: Double, totalMilliseconds: Double) {
        let deadline = Date().addingTimeInterval(timeout)
        let start = threadCPUSeconds()
        var maxFrame = 0.0
        while !condition(), Date() < deadline {
            let frameStart = threadCPUSeconds()
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            maxFrame = max(maxFrame, millisecondsSince(frameStart))
        }
        guard condition() else {
            XCTFail("Production transcript renderer did not settle within \(timeout) seconds")
            throw PerformanceGateError.timeout
        }
        return (maxFrame, millisecondsSince(start))
    }

    private func findTableView(in view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView { return tableView }
        return view.subviews.lazy.compactMap { self.findTableView(in: $0) }.first
    }

    private func findTextView(in view: NSView) -> FinalTranscriptNSTextView? {
        if let textView = view as? FinalTranscriptNSTextView { return textView }
        return view.subviews.lazy.compactMap { self.findTextView(in: $0) }.first
    }

    private func millisecondsSince(_ start: Double) -> Double {
        (threadCPUSeconds() - start) * 1_000
    }

    private func threadCPUSeconds() -> Double {
        var time = timespec()
        precondition(clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
    }

    private enum PerformanceGateError: Error {
        case timeout
    }
}

import AppKit
import SwiftUI
import XCTest
import MacParakeetCore
@testable import MacParakeet

@MainActor
final class MeetingTranscriptGroupingVisualEvidenceTests: XCTestCase {
    func testRenderBeforeAndAfterEvidence() throws {
        guard
            let outputDirectory = ProcessInfo.processInfo.environment[
                "MEETING_TRANSCRIPT_GROUPING_EVIDENCE_DIR"
            ]
        else {
            throw XCTSkip(
                "Set MEETING_TRANSCRIPT_GROUPING_EVIDENCE_DIR to render grouping evidence."
            )
        }

        let canonical = MeetingTranscriptPresentationDocument(turns: evidenceTurns)
        try render(
            canonical,
            to: URL(fileURLWithPath: outputDirectory).appendingPathComponent("before.png")
        )
        try render(
            MeetingTranscriptDisplayBuilder.build(from: canonical),
            to: URL(fileURLWithPath: outputDirectory).appendingPathComponent("after.png")
        )
    }

    private func render(
        _ document: MeetingTranscriptPresentationDocument,
        to outputURL: URL
    ) throws {
        let size = NSSize(width: 700, height: 420)
        let identified = identifiedReadingTurns(document.turns)
        let root = ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Completed meeting transcript")
                    .font(DesignSystem.Typography.pageTitle)
                MeetingReadingTurnContentView(
                    turns: identified,
                    speakerColorMap: ["microphone": .orange, "system:S1": .blue],
                    speakerLabelContent: { _, label, color, _, _ in
                        Text(label)
                            .font(DesignSystem.Typography.body.weight(.semibold))
                            .foregroundStyle(color)
                    },
                    activeScrollID: identified.first?.scrollID,
                    timestampLabel: evidenceTimestamp,
                    isTimestampSeekable: true,
                    onTimestampTap: { _ in },
                    onCopyTurn: { _ in }
                )
            }
            .padding(DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: size.width, height: size.height)
        .background(DesignSystem.Colors.surface)
        .environment(\.colorScheme, .light)

        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let bitmap = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: outputURL)
    }

    private var evidenceTurns: [ReadingTurn] {
        [
            turn(
                speakerId: "microphone",
                label: "Me",
                firstWord: 0,
                startMs: 600_000,
                text: "First point."
            ),
            turn(
                speakerId: "microphone",
                label: "Me",
                firstWord: 1,
                startMs: 608_000,
                text: "Another point after a pause."
            ),
            turn(
                speakerId: "microphone",
                label: "Me",
                firstWord: 2,
                startMs: 614_000,
                text: "A final detail in the same contribution."
            ),
            turn(
                speakerId: "system:S1",
                label: "Alex",
                firstWord: 3,
                startMs: 615_000,
                text: "Response from another speaker."
            ),
        ]
    }

    private func turn(
        speakerId: String,
        label: String,
        firstWord: Int,
        startMs: Int,
        text: String
    ) -> ReadingTurn {
        let source: ReadingTurnSource = speakerId == "microphone" ? .microphone : .system
        return ReadingTurn(
            id: ReadingTurnIdentity(
                source: source,
                speakerId: speakerId,
                firstWordIndex: firstWord
            ),
            speakerId: speakerId,
            speakerLabel: label,
            source: source,
            timeRange: ReadingTurnTimeRange(startMs: startMs, endMs: startMs + 1_000),
            paragraphs: [ReadingTurnParagraph(text: text, wordReferences: [firstWord])],
            wordReferences: [firstWord]
        )
    }

    private func evidenceTimestamp(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1_000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

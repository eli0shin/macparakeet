import AppKit
import SwiftUI
import XCTest
import MacParakeetViewModels
@testable import MacParakeet

@MainActor
final class TranscribeViewVisualEvidenceTests: XCTestCase {
    func testRenderEvidence() throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["TRANSCRIBE_VIEW_EVIDENCE_DIR"] else {
            throw XCTSkip("Set TRANSCRIBE_VIEW_EVIDENCE_DIR to render Transcribe view evidence.")
        }
        let environment = ProcessInfo.processInfo.environment
        let name = environment["TRANSCRIBE_VIEW_EVIDENCE_NAME"] ?? "transcribe"
        let width = environment["TRANSCRIBE_VIEW_EVIDENCE_WIDTH"].flatMap(Double.init) ?? 760
        let size = NSSize(width: width, height: 560)
        let hostingView = NSHostingView(
            rootView: EvidenceHost()
                .frame(width: size.width, height: size.height)
                .background(DesignSystem.Colors.background)
                .environment(\.colorScheme, .light)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.backgroundColor = .windowBackgroundColor
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

private struct EvidenceHost: View {
    @State private var showingProgressDetail = false

    private let transcriptionViewModel = TranscriptionViewModel()
    private let chatViewModel = TranscriptChatViewModel()
    private let promptResultsViewModel = PromptResultsViewModel()
    private let promptsViewModel = PromptsViewModel()
    private let meetingPillViewModel = MeetingRecordingPillViewModel()

    var body: some View {
        TranscribeView(
            viewModel: transcriptionViewModel,
            chatViewModel: chatViewModel,
            promptResultsViewModel: promptResultsViewModel,
            promptsViewModel: promptsViewModel,
            meetingPillViewModel: meetingPillViewModel,
            showingProgressDetail: $showingProgressDetail,
            onRecordMeeting: {}
        )
    }
}

import AppKit
import SwiftUI
import XCTest
import MacParakeetViewModels
@testable import MacParakeet

@MainActor
final class TranscribeViewAccessibilityTests: XCTestCase {
    func testMediaURLFieldPreservesNativeValueForValidAndInvalidInput() throws {
        for input in ["https://example.com/video", "not a valid URL"] {
            let viewModel = TranscriptionViewModel()
            viewModel.urlInput = input
            let window = makeWindow(viewModel: viewModel)
            defer { window.orderOut(nil) }

            let field = try XCTUnwrap(findMediaURLField(in: window.contentView))
            XCTAssertEqual(field.accessibilityValue(), input)
        }
    }

    private func makeWindow(viewModel: TranscriptionViewModel) -> NSWindow {
        let size = NSSize(width: 760, height: 560)
        let hostingView = NSHostingView(
            rootView: TranscribeViewAccessibilityHost(viewModel: viewModel)
                .frame(width: size.width, height: size.height)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return window
    }

    private func findMediaURLField(in candidate: NSView?) -> NSTextField? {
        guard let view = candidate else { return nil }
        if let field = view as? NSTextField,
            field.placeholderString == "Paste a video or podcast link"
        {
            return field
        }
        return view.subviews.lazy.compactMap {
            self.findMediaURLField(in: $0)
        }.first
    }
}

private struct TranscribeViewAccessibilityHost: View {
    let viewModel: TranscriptionViewModel
    @State private var showingProgressDetail = false

    private let chatViewModel = TranscriptChatViewModel()
    private let promptResultsViewModel = PromptResultsViewModel()
    private let promptsViewModel = PromptsViewModel()
    private let meetingPillViewModel = MeetingRecordingPillViewModel()

    var body: some View {
        TranscribeView(
            viewModel: viewModel,
            chatViewModel: chatViewModel,
            promptResultsViewModel: promptResultsViewModel,
            promptsViewModel: promptsViewModel,
            meetingPillViewModel: meetingPillViewModel,
            showingProgressDetail: $showingProgressDetail,
            onRecordMeeting: {}
        )
    }
}

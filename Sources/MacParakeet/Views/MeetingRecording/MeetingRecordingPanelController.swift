import AppKit
import MacParakeetViewModels
import SwiftUI

@MainActor
final class MeetingRecordingPanelController {
    var onCloseRequested: (() -> Void)?

    private var window: NSWindow?
    private var windowDelegate: MeetingRecordingPanelWindowDelegate?
    private let viewModel: MeetingRecordingPanelViewModel

    init(viewModel: MeetingRecordingPanelViewModel) {
        self.viewModel = viewModel
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    var managedWindow: NSWindow? { window }

    func show() {
        if window == nil {
            createWindow()
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func close() {
        window?.delegate = nil
        window?.close()
        window = nil
        windowDelegate = nil
    }

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Meeting Recording"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.collectionBehavior = []
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 320)
        let restoredFrame = window.setFrameUsingName("MeetingRecordingPanel")
        window.setFrameAutosaveName("MeetingRecordingPanel")
        window.contentView = NSHostingView(rootView: MeetingRecordingPanelView(viewModel: viewModel))

        if !restoredFrame, let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.maxX - window.frame.width - 24
            let y = frame.minY + 96
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        let delegate = MeetingRecordingPanelWindowDelegate { [weak self] in
            self?.onCloseRequested?()
        }
        window.delegate = delegate

        self.window = window
        self.windowDelegate = delegate
    }
}

private final class MeetingRecordingPanelWindowDelegate: NSObject, NSWindowDelegate {
    private let onCloseRequested: () -> Void

    init(onCloseRequested: @escaping () -> Void) {
        self.onCloseRequested = onCloseRequested
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // User close hides only this working surface. The controller and view
        // model remain alive for the active meeting, so reopening keeps notes,
        // transcript, and Ask state.
        onCloseRequested()
        return false
    }
}

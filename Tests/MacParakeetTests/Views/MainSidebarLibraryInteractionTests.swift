import AppKit
import SwiftUI
import XCTest
import MacParakeetCore
import MacParakeetViewModels
@testable import MacParakeet

@MainActor
final class MainSidebarLibraryInteractionTests: XCTestCase {
    func testLibraryRowClickAlwaysOpensRootAndClosesDetail() {
        let state = MainWindowState()
        let libraryViewModel = TranscriptionLibraryViewModel()
        let transcriptionViewModel = TranscriptionViewModel()
        let folderID = UUID()
        let detail = Transcription(fileName: "detail.wav", status: .completed)
        let row = MainSidebarItemRow(item: .library) {
            state.navigateFromSidebar(
                to: .library,
                libraryViewModel: libraryViewModel,
                transcriptionViewModel: transcriptionViewModel
            )
        }
        let size = NSSize(width: 240, height: 40)
        let hostingView = NSHostingView(rootView: row.frame(width: size.width, height: size.height))
        let window = show(hostingView, size: size)
        defer { window.orderOut(nil) }

        libraryViewModel.selectLocation(.folder(folderID))
        transcriptionViewModel.currentTranscription = detail
        clickTrailingSpace(in: window, size: size)
        XCTAssertEqual(state.selectedItem, .library)
        XCTAssertEqual(libraryViewModel.location, .root)
        XCTAssertNil(transcriptionViewModel.currentTranscription)

        state.navigate(to: .settings)
        libraryViewModel.selectLocation(.allItems)
        clickTrailingSpace(in: window, size: size)
        XCTAssertEqual(state.selectedItem, .library)
        XCTAssertEqual(libraryViewModel.location, .root)

        libraryViewModel.selectLocation(.folder(folderID))
        transcriptionViewModel.currentTranscription = detail
        clickTrailingSpace(in: window, size: size)
        XCTAssertEqual(state.selectedItem, .library)
        XCTAssertEqual(libraryViewModel.location, .root)
        XCTAssertNil(transcriptionViewModel.currentTranscription)
    }

    func testFolderTreeClickAfterLibraryNavigationRemainsAtSelectedFolder() {
        let folder = LibraryFolder(name: "Project")
        var selectedLocation: LibraryLocation?
        let tree = LibraryFolderTreeNodeView(
            node: LibraryFolderNode(folder: folder, children: []),
            selectedLocation: .root,
            onSelect: { selectedLocation = $0 }
        )
        let size = NSSize(width: 240, height: 40)
        let hostingView = NSHostingView(rootView: tree.frame(width: size.width, height: size.height))
        let window = show(hostingView, size: size)
        defer { window.orderOut(nil) }

        sendClick(in: window, at: NSPoint(x: 50, y: size.height / 2))

        XCTAssertEqual(selectedLocation, .folder(folder.id))
    }

    private func clickTrailingSpace(in window: NSWindow, size: NSSize) {
        sendClick(in: window, at: NSPoint(x: size.width - 4, y: size.height / 2))
    }

    private func show<Content: View>(_ hostingView: NSHostingView<Content>, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return window
    }

    private func sendClick(in window: NSWindow, at location: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard
                let event = NSEvent.mouseEvent(
                    with: type,
                    location: location,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: type == .leftMouseDown ? 1 : 0
                )
            else {
                XCTFail("Could not create mouse event")
                return
            }
            window.sendEvent(event)
        }
    }
}

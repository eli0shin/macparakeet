import AppKit
import SwiftUI
import XCTest
import MacParakeetCore
import MacParakeetViewModels
@testable import MacParakeet

@MainActor
final class LibraryFolderSidebarHitAreaTests: XCTestCase {
    func testLibraryRootSelectsWhenClickingBlankTrailingRowSpace() {
        var selectedLocation: LibraryLocation?
        let row = LibrarySidebarLocationButton(
            title: "Library",
            systemImage: "tray.full",
            location: .root,
            selectedLocation: .allItems,
            onSelect: { selectedLocation = $0 }
        )

        clickTrailingSpace(in: row)

        XCTAssertEqual(selectedLocation, .root)
    }

    func testNestedFolderSelectsWhenClickingBlankTrailingRowSpace() {
        let parent = LibraryFolder(name: "Parent")
        let child = LibraryFolder(parentID: parent.id, name: "Nested folder")
        var selectedLocation: LibraryLocation?
        let tree = LibraryFolderTreeNodeView(
            node: LibraryFolderNode(
                folder: parent,
                children: [LibraryFolderNode(folder: child, children: [])]
            ),
            selectedLocation: .root,
            onSelect: { selectedLocation = $0 }
        )
        let hostingView = NSHostingView(rootView: tree.frame(width: 240))
        let size = hostingView.fittingSize
        let window = show(hostingView, size: size)
        defer { window.orderOut(nil) }

        sendClick(in: window, at: NSPoint(x: size.width - 4, y: 15))

        XCTAssertEqual(selectedLocation, .folder(child.id))
    }

    func testDisclosureControlCollapsesFolderWithoutSelectingIt() {
        let parent = LibraryFolder(name: "Parent")
        let child = LibraryFolder(parentID: parent.id, name: "Child")
        var selectedLocation: LibraryLocation?
        let tree = LibraryFolderTreeNodeView(
            node: LibraryFolderNode(
                folder: parent,
                children: [LibraryFolderNode(folder: child, children: [])]
            ),
            selectedLocation: .root,
            onSelect: { selectedLocation = $0 }
        )
        let hostingView = NSHostingView(rootView: tree.frame(width: 240))
        let initialSize = hostingView.fittingSize
        let window = show(hostingView, size: initialSize)
        defer { window.orderOut(nil) }

        sendClick(in: window, at: NSPoint(x: 5, y: initialSize.height - 15))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertNil(selectedLocation)
        XCTAssertLessThan(hostingView.fittingSize.height, initialSize.height)
    }

    private func clickTrailingSpace<Content: View>(in content: Content) {
        let size = NSSize(width: 240, height: 40)
        let hostingView = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        let window = show(hostingView, size: size)
        defer { window.orderOut(nil) }

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

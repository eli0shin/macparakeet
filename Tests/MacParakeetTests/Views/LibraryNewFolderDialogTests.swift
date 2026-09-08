import AppKit
import SwiftUI
import XCTest
@testable import MacParakeet

@MainActor
final class LibraryNewFolderDialogTests: XCTestCase {
    func testNameFieldReceivesFocusAndTypingOnRepeatedOpenings() throws {
        for opening in 1...2 {
            var name = ""
            let dialog = LibraryNewFolderDialog(
                name: Binding(get: { name }, set: { name = $0 }),
                locationMessage: opening == 1
                    ? "Create a folder at the top level of Library."
                    : "Create a folder inside Project Aurora.",
                onCancel: {},
                onCreate: {}
            )
            let presentation = show(dialog)
            defer { presentation.window.orderOut(nil) }

            let field = try XCTUnwrap(findFolderNameField(in: presentation.hostingView))
            XCTAssertGreaterThanOrEqual(field.frame.width, 300)
            XCTAssertGreaterThanOrEqual(field.frame.height, 22)
            XCTAssertTrue(
                field.currentEditor() === presentation.window.firstResponder,
                "The name field must receive initial focus on opening \(opening)."
            )

            let typedName = opening == 1 ? "Product Research" : "Sprint Planning"
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.insertText(typedName, replacementRange: NSRange(location: NSNotFound, length: 0))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            XCTAssertEqual(name, typedName)
        }
    }

    func testRenderEvidence() throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["NEW_FOLDER_DIALOG_EVIDENCE_DIR"] else {
            throw XCTSkip("Set NEW_FOLDER_DIALOG_EVIDENCE_DIR to render New Folder dialog evidence.")
        }

        var name = "Quarterly Planning Notes"
        let dialog = LibraryNewFolderDialog(
            name: Binding(get: { name }, set: { name = $0 }),
            locationMessage: "Create a folder inside Project Aurora.",
            onCancel: {},
            onCreate: {}
        )
        let presentation = show(dialog)
        defer { presentation.window.orderOut(nil) }

        let hostingView = presentation.hostingView
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("new-folder-dialog.png"))
    }

    private func show<Content: View>(_ content: Content) -> (window: NSWindow, hostingView: NSHostingView<Content>) {
        let hostingView = NSHostingView(rootView: content)
        let size = NSSize(width: 440, height: max(hostingView.fittingSize.height, 180))
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.backgroundColor = .windowBackgroundColor
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hostingView.layoutSubtreeIfNeeded()
        return (window, hostingView)
    }

    private func findFolderNameField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.placeholderString == "Folder name" {
            return field
        }
        for subview in view.subviews {
            if let field = findFolderNameField(in: subview) {
                return field
            }
        }
        return nil
    }
}

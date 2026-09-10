import AppKit
import XCTest
@testable import MacParakeet
import MacParakeetViewModels

@MainActor
final class WindowBehaviorTests: XCTestCase {
    func testDirectReturningUserLaunchOpensMainWindow() {
        XCTAssertTrue(
            AppLaunchPresentationPolicy.shouldOpenMainWindow(
                isLoginItemLaunch: false,
                onboardingCompleted: true
            )
        )
    }

    func testLoginAndOnboardingLaunchesDoNotOpenMainWindow() {
        XCTAssertFalse(
            AppLaunchPresentationPolicy.shouldOpenMainWindow(
                isLoginItemLaunch: true,
                onboardingCompleted: true
            )
        )
        XCTAssertFalse(
            AppLaunchPresentationPolicy.shouldOpenMainWindow(
                isLoginItemLaunch: false,
                onboardingCompleted: false
            )
        )
    }

    func testMainWindowPresentationReusesClosedWindowAndPreservesFrame() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 180, y: 220, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let expectedFrame = window.frame
        var activationCount = 0

        MainWindowPresentation.open(window) { activationCount += 1 }
        XCTAssertTrue(window.isVisible)
        window.close()
        XCTAssertFalse(window.isVisible)

        MainWindowPresentation.open(window) { activationCount += 1 }
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.frame, expectedFrame)
        XCTAssertEqual(activationCount, 2)
        window.close()
    }

    func testLiveMeetingUsesNormalPersistentWindowPolicy() {
        _ = NSApplication.shared
        let controller = MeetingRecordingPanelController(viewModel: MeetingRecordingPanelViewModel())
        controller.onCloseRequested = { [weak controller] in controller?.hide() }

        controller.show()
        guard let window = controller.managedWindow else {
            return XCTFail("Expected a live meeting window")
        }

        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window is NSPanel)
        XCTAssertFalse(window.hidesOnDeactivate)
        XCTAssertEqual(window.level, .normal)
        XCTAssertFalse(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))

        window.performClose(nil)
        XCTAssertFalse(controller.isVisible)
        XCTAssertTrue(controller.managedWindow === window)

        controller.show()
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(controller.managedWindow === window)
        controller.close()
    }

    func testRecordingFlowerReportsActualVisibilityAndCanReshow() {
        _ = NSApplication.shared
        let autosaveName = "MeetingRecordingPillTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(autosaveName)") }
        let controller = MeetingRecordingPillController(
            viewModel: MeetingRecordingPillViewModel(),
            frameAutosaveName: autosaveName
        )

        controller.show()
        guard let window = controller.managedWindow else {
            return XCTFail("Expected a recording flower window")
        }

        XCTAssertTrue(controller.isVisible)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertFalse(window.hidesOnDeactivate)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))

        window.orderOut(nil)
        XCTAssertFalse(controller.isVisible)
        controller.show()
        XCTAssertTrue(controller.isVisible)
        controller.hide()
    }

    func testRecordingFlowerRestoresSavedPositionInLaterController() {
        _ = NSApplication.shared
        let autosaveName = "MeetingRecordingPillTests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(autosaveName)") }
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return XCTFail("Expected a screen")
        }
        let savedOrigin = NSPoint(x: visibleFrame.midX, y: visibleFrame.midY)

        var firstController: MeetingRecordingPillController? = MeetingRecordingPillController(
            viewModel: MeetingRecordingPillViewModel(),
            frameAutosaveName: autosaveName
        )
        firstController?.show()
        firstController?.managedWindow?.setFrameOrigin(savedOrigin)
        firstController?.hide()
        firstController = nil

        let nextController = MeetingRecordingPillController(
            viewModel: MeetingRecordingPillViewModel(),
            frameAutosaveName: autosaveName
        )
        nextController.show()
        guard let restoredOrigin = nextController.managedWindow?.frame.origin else {
            return XCTFail("Expected a restored recording flower window")
        }
        XCTAssertEqual(restoredOrigin.x, savedOrigin.x, accuracy: 1)
        XCTAssertEqual(restoredOrigin.y, savedOrigin.y, accuracy: 1)
        nextController.hide()
    }

    func testRecordingFlowerRejectsUnavailableDisplayFrame() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertTrue(
            MeetingRecordingPillController.isRecoverable(
                NSRect(x: 1200, y: 400, width: 118, height: 150),
                on: [visible]
            )
        )
        XCTAssertFalse(
            MeetingRecordingPillController.isRecoverable(
                NSRect(x: 2000, y: 400, width: 118, height: 150),
                on: [visible]
            )
        )
    }
}

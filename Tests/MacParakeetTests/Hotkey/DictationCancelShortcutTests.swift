import CoreGraphics
import XCTest
@testable import MacParakeet
@testable import MacParakeetCore

final class DictationCancelShortcutTests: XCTestCase {
    private func send(
        _ manager: HotkeyManager,
        type: CGEventType = .keyDown,
        keyCode: UInt16,
        flags: CGEventFlags = []
    ) throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: type == .keyDown))
        event.flags = flags
        manager.handleEventForTesting(type: type, event: event)
    }

    func testCustomCancelWorksAcrossAllStartTriggerKinds() throws {
        let cancel = HotkeyTrigger.chord(modifiers: ["command", "shift"], keyCode: 0)
        let triggers: [HotkeyTrigger] = [
            .fn, .fromKeyCode(105), .chord(modifiers: ["control"], keyCode: 15),
            .modifierChord(modifiers: ["control", "option"]),
        ]
        for trigger in triggers {
            let manager = HotkeyManager(trigger: trigger, cancelTrigger: cancel, gestureMode: .singleTapToggle)
            manager.resumeRecording(mode: .persistent)
            var cancellations = 0
            manager.onCancelRecording = { cancellations += 1 }

            try send(manager, keyCode: 53)
            try send(manager, keyCode: 0, flags: [.maskCommand])
            XCTAssertEqual(cancellations, 0, trigger.displayName)
            try send(manager, keyCode: 0, flags: [.maskCommand, .maskShift])
            XCTAssertEqual(cancellations, 1, trigger.displayName)
            // Key repeat must not immediately dismiss the cancel countdown.
            try send(manager, keyCode: 0, flags: [.maskCommand, .maskShift])
            XCTAssertEqual(cancellations, 1)
            try send(manager, type: .keyUp, keyCode: 0)
            try send(manager, keyCode: 0, flags: [.maskCommand, .maskShift])
            XCTAssertEqual(cancellations, 2)
        }
    }

    func testCancelKeyWithHeldStartModifierCannotStartDictationOnRelease() throws {
        for cancel: HotkeyTrigger in [.defaultCancelDictation, .fromKeyCode(105)] {
            let manager = HotkeyManager(trigger: .fn, cancelTrigger: cancel, gestureMode: .singleTapToggle)
            var starts = 0
            manager.onStartRecording = { _ in starts += 1 }
            try send(manager, type: .flagsChanged, keyCode: 63, flags: [.maskSecondaryFn])
            try send(manager, keyCode: 105, flags: [.maskSecondaryFn])
            try send(manager, type: .keyUp, keyCode: 105, flags: [.maskSecondaryFn])
            try send(manager, type: .flagsChanged, keyCode: 63)
            XCTAssertEqual(starts, 0, cancel.displayName)
        }
    }

    func testCancelMatcherRecoversAfterMissedKeyRelease() throws {
        for type: CGEventType in [.tapDisabledByTimeout, .tapDisabledByUserInput] {
            let manager = HotkeyManager(trigger: .fn, cancelTrigger: .fromKeyCode(105), gestureMode: .singleTapToggle)
            manager.resumeRecording(mode: .persistent)
            var cancellations = 0
            manager.onCancelRecording = { cancellations += 1 }
            try send(manager, keyCode: 105)
            XCTAssertEqual(cancellations, 1)
            manager.resumeRecording(mode: .persistent)
            // Synthetic events do not physically press the key. Recovery must
            // notice it is released even though its keyUp was missed.
            try send(manager, type: type, keyCode: 0)
            try send(manager, keyCode: 105)
            XCTAssertEqual(cancellations, 2)
        }
    }

    func testBareKeyAndModifierCancelShortcuts() throws {
        let cases: [(HotkeyTrigger, CGEventType, UInt16, CGEventFlags)] = [
            (.fromKeyCode(105), .keyDown, 105, []),
            (.option, .flagsChanged, 58, [.maskAlternate]),
            (.modifierChord(modifiers: ["control", "option"]), .flagsChanged, 58, [.maskControl, .maskAlternate]),
        ]
        for (cancel, type, code, flags) in cases {
            let manager = HotkeyManager(trigger: .fn, cancelTrigger: cancel, gestureMode: .singleTapToggle)
            manager.resumeRecording(mode: .persistent)
            var cancellations = 0
            manager.onCancelRecording = { cancellations += 1 }
            try send(manager, type: type, keyCode: code, flags: flags)
            XCTAssertEqual(cancellations, 1, cancel.displayName)
        }
    }

    func testSharedDoubleTapAndHoldUsesCustomCancelOnlyForPersistentRecording() throws {
        for mode: FnKeyStateMachine.RecordingMode in [.persistent, .holdToTalk] {
            let manager = HotkeyManager(trigger: .fn, cancelTrigger: .fromKeyCode(105))
            manager.resumeRecording(mode: mode)
            var cancellations = 0
            manager.onCancelRecording = { cancellations += 1 }
            if mode == .persistent {
                try send(manager, keyCode: 53)
                XCTAssertEqual(cancellations, 0)
            }
            try send(manager, keyCode: mode == .persistent ? 105 : 53)
            XCTAssertEqual(cancellations, 1)
            if mode == .holdToTalk {
                try send(manager, keyCode: 53)
                XCTAssertEqual(cancellations, 2, "Escape must still dismiss the hold-to-talk cancel countdown")
            }
        }
    }

    func testDisabledCancelDoesNotCancelHandsFreeButDefaultEscapeDoes() throws {
        for cancel: HotkeyTrigger in [.disabled, .defaultCancelDictation] {
            let manager = HotkeyManager(trigger: .fn, cancelTrigger: cancel, gestureMode: .singleTapToggle)
            manager.resumeRecording(mode: .persistent)
            var cancellations = 0
            manager.onCancelRecording = { cancellations += 1 }
            try send(manager, keyCode: 53)
            XCTAssertEqual(cancellations, cancel.isDisabled ? 0 : 1)
        }
    }

    func testSuppressedPeerDoesNotCancelTwice() throws {
        let manager = HotkeyManager(trigger: .fn, cancelTrigger: .fromKeyCode(105), gestureMode: .holdOnly)
        manager.suppressUntilReset()
        var cancellations = 0
        manager.onCancelRecording = { cancellations += 1 }
        try send(manager, keyCode: 105)
        try send(manager, keyCode: 53)
        XCTAssertEqual(cancellations, 0)
    }

    @MainActor
    func testRuntimeConflictCannotShadowStartStopShortcut() {
        XCTAssertEqual(
            AppHotkeyCoordinator.cancelDictationTrigger(configured: .fn, otherTriggers: [.fn]),
            .disabled
        )
        XCTAssertEqual(
            AppHotkeyCoordinator.cancelDictationTrigger(configured: .defaultCancelDictation, otherTriggers: [.fn]),
            .defaultCancelDictation
        )
    }
}

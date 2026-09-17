@preconcurrency import AVFoundation
import os
import XCTest
@testable import MacParakeetCore

final class MicrophoneOperationDiagnosticsTests: XCTestCase {
    func testBlockedEngineStartIsReportedBeforeItReturns() async {
        let messages = OSAllocatedUnfairLock(initialState: [String]())
        let stalled = expectation(description: "independent watchdog identifies blocked engine start")
        let entered = expectation(description: "engine start entered")
        let finished = expectation(description: "engine start finished")
        let release = DispatchSemaphore(value: 0)
        let diagnostics = MicrophoneOperationDiagnostics(stallTimeout: 0.02) { message in
            messages.withLock { $0.append(message) }
            if message.contains("shared_mic_operation_stalled"), message.contains("operation=engine_start ") {
                stalled.fulfill()
            }
        }
        let platform = AVAudioEngineMicrophonePlatform(
            operationDiagnostics: diagnostics,
            engineStarter: { _, _, _, _ in
                entered.fulfill()
                _ = release.wait(timeout: .now() + 3)
                throw NSError(domain: NSOSStatusErrorDomain, code: -10868)
            }
        )
        DispatchQueue.global().async {
            defer { finished.fulfill() }
            do {
                try platform.configureAndStart(vpioEnabled: false, bufferSize: 256, tapHandler: { _, _ in })
                XCTFail("Expected engine start failure")
            } catch {
                XCTAssertEqual((error as NSError).code, -10868)
            }
        }

        await fulfillment(of: [entered, stalled], timeout: 1)
        let beforeRelease = messages.withLock { $0 }
        XCTAssertFalse(
            beforeRelease.contains { $0.contains("operation=engine_start ") && $0.contains("operation_end") })
        release.signal()
        await fulfillment(of: [finished], timeout: 2)

        let startEvents = messages.withLock { $0.filter { $0.contains("operation=engine_start ") } }
        XCTAssertEqual(startEvents.count, 3, "begin, stalled while blocked, then end after release")
        XCTAssertTrue(startEvents.last?.contains("outcome=error") == true)
        XCTAssertTrue(startEvents.last?.contains("-10868") == true)
        platform.stopEngine()
    }

    func testCompletedOperationDoesNotLaterReportAStall() async {
        let unexpectedStall = expectation(description: "completed operation must not report a stall")
        unexpectedStall.isInverted = true
        let messages = OSAllocatedUnfairLock(initialState: [String]())
        let diagnostics = MicrophoneOperationDiagnostics(stallTimeout: 0.01) { message in
            messages.withLock { $0.append(message) }
            if message.contains("operation_stalled") { unexpectedStall.fulfill() }
        }
        let span = diagnostics.begin("test")
        span.finish()
        span.finish()

        await fulfillment(of: [unexpectedStall], timeout: 0.05)
        withExtendedLifetime(span) {}
        XCTAssertEqual(messages.withLock { $0.count }, 2, "finish is idempotent")
    }

    func testLaterSubscriptionReportsQueueWaitWhileEarlierEngineStartIsBlocked() async {
        let queuedStall = expectation(description: "second subscription is waiting on stream queue")
        let engineEntered = expectation(description: "first engine call entered")
        let release = DispatchSemaphore(value: 0)
        let starts = OSAllocatedUnfairLock(initialState: 0)
        let messages = OSAllocatedUnfairLock(initialState: [String]())
        let diagnostics = MicrophoneOperationDiagnostics(stallTimeout: 0.02) { message in
            messages.withLock { $0.append(message) }
            if message.contains("operation_stalled"), message.contains("operation=stream_queue_wait ") {
                queuedStall.fulfill()
            }
        }
        let platform = AVAudioEngineMicrophonePlatform(engineStarter: { _, _, _, _ in
            let start = starts.withLock { count in
                count += 1
                return count
            }
            if start == 1 {
                engineEntered.fulfill()
                _ = release.wait(timeout: .now() + 3)
            }
            throw NSError(domain: NSOSStatusErrorDomain, code: -10868)
        })
        let stream = SharedMicrophoneStream(platform: platform, operationDiagnostics: diagnostics)
        let first = Task { try? await stream.subscribe(wantsVPIO: false) { _, _ in } }
        await fulfillment(of: [engineEntered], timeout: 1)
        let second = Task { try? await stream.subscribe(wantsVPIO: false) { _, _ in } }
        await fulfillment(of: [queuedStall], timeout: 1)

        let stalledEvents = messages.withLock { $0.filter { $0.contains("operation_stalled") } }
        XCTAssertTrue(stalledEvents.contains { $0.contains("operation=subscribe ") })
        XCTAssertTrue(
            stalledEvents.contains { $0.contains("operation=stream_queue_wait ") && $0.contains("subscription_id=") })
        XCTAssertEqual(starts.withLock { $0 }, 1, "Second subscription has not reached the platform")

        release.signal()
        _ = await first.value
        _ = await second.value
        XCTAssertEqual(stream.diagnostics.subscriberCount, 0)
        platform.stopEngine()
    }
}

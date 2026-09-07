@testable import MacParakeetCore
import XCTest

final class VocabularyPreparationWaiterTests: XCTestCase {
    func testCancellationReturnsBeforeSharedLoadFinishesAndOtherWaiterStillSucceeds() async throws {
        let gate = VocabularyLoadGate()
        let shared = Task.detached {
            await gate.wait(); return 42
        }
        // Keep the shared task's error type identical to the production loader.
        let load = Task<Int, Error> { await shared.value }
        let waiter = Task { try await VocabularyPreparationWaiter.value(of: load) }
        let other = Task { try await VocabularyPreparationWaiter.value(of: load) }
        await gate.waitUntilStarted()
        waiter.cancel()
        let returned = expectation(description: "cancelled waiter returns while model load is blocked")
        let observation = Task {
            do { _ = try await waiter.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch {
                XCTFail("Unexpected error: \(error)")
            }
            returned.fulfill()
        }
        await fulfillment(of: [returned], timeout: 1)
        let finished = await gate.finished
        XCTAssertFalse(finished)
        await gate.release()
        await observation.value
        let otherValue = try await other.value
        XCTAssertEqual(otherValue, 42)
        XCTAssertFalse(load.isCancelled)
    }
}

private actor VocabularyLoadGate {
    var finished = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startedWaiters.forEach { $0.resume() }
            startedWaiters.removeAll()
        }
        finished = true
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }
    func release() { continuation?.resume(); continuation = nil }
}

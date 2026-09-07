import Foundation
import os

/// Cancel a caller's wait without cancelling a model load shared by other jobs.
/// The completion task only transfers a result; it does not start model I/O.
final class VocabularyPreparationWaiter<Value: Sendable>: @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, Error>?
        var result: Result<Value, Error>?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    static func value(of task: Task<Value, Error>) async throws -> Value {
        let waiter = VocabularyPreparationWaiter()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                waiter.register(continuation)
                Task { waiter.resolve(await task.result) }
            }
        } onCancel: {
            waiter.resolve(.failure(CancellationError()))
        }
    }

    private func register(_ continuation: CheckedContinuation<Value, Error>) {
        let result = state.withLock { state -> Result<Value, Error>? in
            if let result = state.result { return result }
            state.continuation = continuation
            return nil
        }
        if let result { continuation.resume(with: result) }
    }

    private func resolve(_ result: Result<Value, Error>) {
        let continuation = state.withLock { state -> CheckedContinuation<Value, Error>? in
            guard state.result == nil else { return nil }
            state.result = result
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume(with: result)
    }
}

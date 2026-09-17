import Foundation
import os

/// Before/after events for synchronous microphone operations, including queue
/// waits. The watchdog never uses an engine queue or reads audio-engine state.
/// It reports a slow call; it does not cancel or reset that call.
final class MicrophoneOperationDiagnostics: Sendable {
    typealias Emit = @Sendable (String) -> Void

    private static let watchdogQueue = DispatchQueue(
        label: "com.macparakeet.microphone-operation-watchdog",
        qos: .utility
    )
    private let stallTimeout: TimeInterval
    private let emit: Emit

    init(
        stallTimeout: TimeInterval = 2,
        emit: @escaping Emit = { AudioCaptureDiagnostics.appendAsync($0) }
    ) {
        self.stallTimeout = max(0, stallTimeout)
        self.emit = emit
    }

    func begin(_ operation: String, context: String = "") -> Span {
        let span = Span(operation: operation, context: context, emit: emit)
        Self.watchdogQueue.asyncAfter(deadline: .now() + stallTimeout) { [weak span] in
            span?.reportStall()
        }
        return span
    }

    func measure<T>(_ operation: String, context: String = "", _ body: () throws -> T) rethrows -> T {
        let span = begin(operation, context: context)
        do {
            let result = try body()
            span.finish()
            return result
        } catch {
            span.finish(error: error)
            throw error
        }
    }

    final class Span: Sendable {
        private struct State {
            var finished = false
            var reportedStall = false
        }

        private let state = OSAllocatedUnfairLock(initialState: State())
        private let fields: String
        private let startedAt = DispatchTime.now().uptimeNanoseconds
        private let emit: Emit

        fileprivate init(operation: String, context: String, emit: @escaping Emit) {
            self.emit = emit
            self.fields = "operation_id=\(UUID().uuidString) operation=\(operation) \(context)"
            emit("shared_mic_operation_begin \(fields)")
        }

        func finish(error: Error? = nil) {
            let outcome =
                error.map { "outcome=error \(AudioCaptureDiagnostics.errorFields($0))" }
                ?? "outcome=returned"
            state.withLock { state in
                guard !state.finished else { return }
                state.finished = true
                emit("shared_mic_operation_end \(fields) elapsed_ms=\(elapsedMilliseconds) \(outcome)")
            }
        }

        fileprivate func reportStall() {
            state.withLock { state in
                guard !state.finished, !state.reportedStall else { return }
                state.reportedStall = true
                emit("shared_mic_operation_stalled \(fields) elapsed_ms=\(elapsedMilliseconds)")
            }
        }

        private var elapsedMilliseconds: String {
            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            return String(format: "%.3f", Double(elapsed) / 1_000_000)
        }
    }
}

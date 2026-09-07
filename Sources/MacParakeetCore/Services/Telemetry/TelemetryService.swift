import Foundation

/// Compatibility boundary for the inherited telemetry call sites.
///
/// Fork builds do not provide a network-backed implementation. Production
/// composition roots leave this boundary unconfigured, so all events are
/// discarded in process.
public protocol TelemetryServiceProtocol: Sendable {
    func send(_ event: TelemetryEventSpec)
    @discardableResult
    func sendAndFlush(_ event: TelemetryEventSpec) async -> Bool
    func clearQueue()
    func flush() async
    func flushForTermination()
}

/// Inert compatibility wrapper for inherited event instrumentation.
public enum Telemetry {
    private final class ServiceStore: @unchecked Sendable {
        private let lock = NSLock()
        private var service: TelemetryServiceProtocol?

        func set(_ service: TelemetryServiceProtocol) {
            lock.lock()
            self.service = service
            lock.unlock()
        }

        func get() -> TelemetryServiceProtocol? {
            lock.lock()
            defer { lock.unlock() }
            return service
        }
    }

    private static let serviceStore = ServiceStore()

    /// Retained for tests that inspect local event construction. Fork
    /// production code does not call this method.
    public static func configure(_ service: TelemetryServiceProtocol) {
        serviceStore.set(service)
    }

    public static func send(_ event: TelemetryEventSpec) {
        serviceStore.get()?.send(event)
    }

    public static func clearQueue() {
        serviceStore.get()?.clearQueue()
    }

    public static func flush() async {
        await serviceStore.get()?.flush()
    }

    public static func flushForTermination() {
        serviceStore.get()?.flushForTermination()
    }
}

public final class NoOpTelemetryService: TelemetryServiceProtocol {
    public init() {}
    public func send(_ event: TelemetryEventSpec) {}
    public func sendAndFlush(_ event: TelemetryEventSpec) async -> Bool { true }
    public func clearQueue() {}
    public func flush() async {}
    public func flushForTermination() {}
}

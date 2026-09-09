import Darwin
import Foundation
import OSLog

/// Writes every telemetry event to a local JSONL file.
public final class LoggerTelemetryService: TelemetryServiceProtocol, @unchecked Sendable {
    public static var defaultLogFileURL: URL {
        URL(fileURLWithPath: AppPaths.logsDir, isDirectory: true)
            .appendingPathComponent("telemetry.jsonl")
    }

    private let logger = Logger(subsystem: "com.macparakeet.core", category: "Telemetry")
    private let lock = NSLock()
    private let logFileURL: URL
    private let appVersion: String
    private let osVersion: String
    private let locale: String?
    private let chip: String
    private let sessionID = UUID().uuidString
    private let surface: String

    public init(
        logFileURL: URL = LoggerTelemetryService.defaultLogFileURL,
        surface: String = "gui",
        appVersionOverride: String? = nil
    ) {
        self.logFileURL = logFileURL
        self.surface = surface

        let systemInfo = SystemInfo.current
        appVersion = appVersionOverride ?? systemInfo.appVersion
        osVersion = systemInfo.macOSVersion
        locale = Locale.current.identifier
        chip = systemInfo.chipType
    }

    public func send(_ event: TelemetryEventSpec) {
        _ = append(event)
    }

    @discardableResult
    public func sendAndFlush(_ event: TelemetryEventSpec) async -> Bool {
        append(event)
    }

    public func clearQueue() {}
    public func flush() async {}
    public func flushForTermination() {}

    private func append(_ spec: TelemetryEventSpec) -> Bool {
        let event = TelemetryEvent(
            spec: spec,
            appVer: appVersion,
            osVer: osVersion,
            locale: locale,
            chip: chip,
            session: sessionID,
            surface: surface
        )

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            var data = try encoder.encode(event)
            data.append(0x0A)

            lock.lock()
            defer { lock.unlock() }

            try FileManager.default.createDirectory(
                at: logFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let descriptor = Darwin.open(logFileURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o666)
            guard descriptor >= 0 else { return false }
            defer { Darwin.close(descriptor) }

            let bytesWritten = data.withUnsafeBytes { bytes in
                Darwin.write(descriptor, bytes.baseAddress, bytes.count)
            }
            return bytesWritten == data.count
        } catch {
            logger.error("telemetry_log_write_failed error=\(error.localizedDescription, privacy: .private)")
            return false
        }
    }
}

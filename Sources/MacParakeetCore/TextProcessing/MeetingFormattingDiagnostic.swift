import Foundation
import OSLog

/// Full local evidence of the meeting formatter's acceptance decision.
/// Text is intentionally not redacted. No provider credentials or headers are recorded.
public struct MeetingFormattingDiagnostic: Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let outcome: String
    public let reason: String?
    public let input: String
    public let output: String?
    public let expectedTurns: Int?
    public let actualTurns: Int?
    public var reasoningContent: String? = nil
}

/// Serializes complete JSONL records off the caller's actor. Writes are awaited:
/// a rejected response must not disappear before its diagnostic is written.
actor MeetingFormattingDiagnosticLog {
    static let shared = MeetingFormattingDiagnosticLog()
    private let logger = Logger(subsystem: "com.macparakeet.core", category: "MeetingReadingTurnFormatter")
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else if Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") }) {
            self.fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "MacParakeetTests/meeting-ai-cleanup-\(ProcessInfo.processInfo.processIdentifier).jsonl")
        } else {
            self.fileURL = URL(fileURLWithPath: AppPaths.logsDir, isDirectory: true)
                .appendingPathComponent("meeting-ai-cleanup.jsonl")
        }
    }

    func append(_ event: MeetingFormattingDiagnostic) {
        if event.outcome == "rejected" {
            logger.error(
                "meeting_ai_cleanup_rejected id=\(event.id.uuidString, privacy: .public) reason=\(event.reason ?? "unknown", privacy: .public) diagnostic_path=\(self.fileURL.path, privacy: .public)"
            )
        } else {
            logger.info(
                "meeting_ai_cleanup_\(event.outcome, privacy: .public) id=\(event.id.uuidString, privacy: .public) turns=\(event.expectedTurns ?? 0) reason=\(event.reason ?? "none", privacy: .public)"
            )
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(event)
            data.append(0x0A)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                guard
                    FileManager.default.createFile(
                        atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
                else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            // Preserve complete evidence in the system log if the file cannot be written.
            logger.fault(
                "meeting_ai_cleanup_log_write_failed path=\(self.fileURL.path, privacy: .public) error=\(String(reflecting: error), privacy: .public) input=\(event.input, privacy: .public) output=\(event.output ?? "<no response>", privacy: .public) reasoning=\(event.reasoningContent ?? "", privacy: .public)"
            )
        }
    }
}

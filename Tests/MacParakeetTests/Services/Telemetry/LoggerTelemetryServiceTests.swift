import Foundation
import XCTest
@testable import MacParakeetCore

final class LoggerTelemetryServiceTests: XCTestCase {
    func testWritesOneJSONEventPerLine() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("logger-telemetry-tests-\(UUID().uuidString)", isDirectory: true)
        let logFileURL = directory.appendingPathComponent("telemetry.jsonl")
        defer { try? FileManager.default.removeItem(at: directory) }

        let service = LoggerTelemetryService(
            logFileURL: logFileURL,
            surface: "gui",
            appVersionOverride: "test-version"
        )
        service.send(.appLaunched)
        service.send(.llmPromptResultFailed(provider: "openai", errorType: "rate_limited"))

        let contents = try String(contentsOf: logFileURL, encoding: .utf8)
        let records = try contents.split(whereSeparator: { $0.isNewline }).map { line in
            try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            )
        }

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0]["event"] as? String, "app_launched")
        XCTAssertEqual(records[1]["event"] as? String, "llm_prompt_result_failed")
        XCTAssertEqual(records[1]["surface"] as? String, "gui")
        XCTAssertEqual(records[1]["app_ver"] as? String, "test-version")
        XCTAssertEqual(
            records[1]["props"] as? [String: String],
            ["error_type": "rate_limited", "provider": "openai"]
        )
    }
}

import XCTest
@testable import MacParakeet

final class TranscriptBodyLayoutTests: XCTestCase {
    func testAllProductionTranscriptSizesRenderWithoutLazyLayout() {
        XCTAssertFalse(TranscriptBodyLayout.usesLazyStack(rowCount: 0, environment: [:]))
        XCTAssertFalse(TranscriptBodyLayout.usesLazyStack(rowCount: 75, environment: [:]))
        XCTAssertFalse(TranscriptBodyLayout.usesLazyStack(rowCount: 401, environment: [:]))
        XCTAssertFalse(TranscriptBodyLayout.usesLazyStack(rowCount: 10_000, environment: [:]))
    }

    func testDebugOverrideCanReproduceFaultyLazyLayout() {
        let name = "MACPARAKEET_DEBUG_TRANSCRIPT_LAZY"
        XCTAssertTrue(
            TranscriptBodyLayout.usesLazyStack(
                rowCount: 401,
                environment: [name: "1"]
            )
        )
        XCTAssertFalse(
            TranscriptBodyLayout.usesLazyStack(
                rowCount: 401,
                environment: [name: "0"]
            )
        )
    }

    func testDebugOverrideParsing() {
        let name = "MACPARAKEET_DEBUG_TRANSCRIPT_LAZY"
        XCTAssertEqual(TranscriptBodyLayout.debugOverride(named: name, environment: [name: "1"]), true)
        XCTAssertEqual(TranscriptBodyLayout.debugOverride(named: name, environment: [name: "yes"]), true)
        XCTAssertEqual(TranscriptBodyLayout.debugOverride(named: name, environment: [name: "0"]), false)
        XCTAssertEqual(TranscriptBodyLayout.debugOverride(named: name, environment: [name: "false"]), false)
        XCTAssertNil(TranscriptBodyLayout.debugOverride(named: name, environment: [name: "invalid"]))
        XCTAssertNil(TranscriptBodyLayout.debugOverride(named: name, environment: [:]))
    }
}

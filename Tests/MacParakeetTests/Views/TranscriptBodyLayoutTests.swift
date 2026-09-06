import XCTest
@testable import MacParakeet

final class TranscriptBodyLayoutTests: XCTestCase {
    func testRepresentativeMeetingsRenderWithoutLazyLayout() {
        XCTAssertFalse(TranscriptBodyLayout.usesLazyStack(rowCount: 0, environment: [:]))
        XCTAssertFalse(TranscriptBodyLayout.usesLazyStack(rowCount: 13, environment: [:]))
        XCTAssertFalse(
            TranscriptBodyLayout.usesLazyStack(
                rowCount: TranscriptBodyLayout.nonLazyRowLimit,
                environment: [:]
            )
        )
    }

    func testVeryLargeTranscriptsKeepBoundedLazyLayout() {
        XCTAssertTrue(
            TranscriptBodyLayout.usesLazyStack(
                rowCount: TranscriptBodyLayout.nonLazyRowLimit + 1,
                environment: [:]
            )
        )
        XCTAssertTrue(TranscriptBodyLayout.usesLazyStack(rowCount: 964, environment: [:]))
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

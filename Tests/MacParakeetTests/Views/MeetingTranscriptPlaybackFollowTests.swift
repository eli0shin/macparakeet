import XCTest
@testable import MacParakeet

@MainActor
final class MeetingTranscriptPlaybackFollowTests: XCTestCase {
    func testNormalPlaybackTicksKeepFollowEnabled() {
        let controller = MeetingTranscriptPlaybackFollowController()

        controller.handlePlaybackTick(from: 1_000, to: 1_250, isPlaying: true)

        XCTAssertTrue(controller.followsPlayback)
        XCTAssertEqual(
            changedReadingTurnPresentationScrollIDs(
                previousActiveID: 12,
                activeID: 12,
                previousHighlight: nil,
                highlight: nil
            ),
            []
        )
    }

    func testLargeSeekUpdatesOnlyPreviousAndNewActiveTurns() {
        XCTAssertEqual(
            changedReadingTurnPresentationScrollIDs(
                previousActiveID: 12,
                activeID: 900,
                previousHighlight: nil,
                highlight: nil
            ),
            [12, 900]
        )
    }

    func testLargeSeekResumesFollowAfterManualScrollPause() {
        let controller = MeetingTranscriptPlaybackFollowController()
        controller.handleManualScroll(isPlaying: true)
        XCTAssertFalse(controller.followsPlayback)

        controller.handlePlaybackTick(from: 1_000, to: 10_000, isPlaying: true)

        XCTAssertTrue(controller.followsPlayback)
    }

    func testManualScrollPauseResumesAfterConfiguredDelay() async {
        let controller = MeetingTranscriptPlaybackFollowController(manualPauseDuration: .milliseconds(10))

        controller.handleManualScroll(isPlaying: true)
        XCTAssertFalse(controller.followsPlayback)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(controller.followsPlayback)
    }

    func testManualScrollTakesPauseOwnershipFromFindNavigation() {
        let controller = MeetingTranscriptPlaybackFollowController()
        controller.pauseForFindNavigation()
        controller.handleManualScroll(isPlaying: true)

        controller.releaseFindNavigationPause()

        XCTAssertFalse(controller.followsPlayback)
    }

    func testClosingFindResumesFollowWhenFindOwnsPause() {
        let controller = MeetingTranscriptPlaybackFollowController()
        controller.pauseForFindNavigation()

        controller.releaseFindNavigationPause()

        XCTAssertTrue(controller.followsPlayback)
    }
}

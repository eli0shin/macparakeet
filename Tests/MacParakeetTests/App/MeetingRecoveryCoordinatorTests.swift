import XCTest

import MacParakeetCore
@testable import MacParakeet

@MainActor
final class MeetingRecoveryCoordinatorTests: XCTestCase {

    private func makeLock(state: MeetingRecordingLockState) -> MeetingRecordingLockFile {
        MeetingRecordingLockFile(
            sessionId: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            pid: 0,
            displayName: "Meeting",
            state: state
        )
    }
}

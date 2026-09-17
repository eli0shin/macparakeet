import XCTest
@testable import MacParakeetViewModels

@MainActor
final class OfflineProcessingViewModelTests: XCTestCase {
    func testJobsKeepInsertionOrderAndExposeFocusedStack() {
        let viewModel = OfflineProcessingViewModel()
        let first = UUID()
        let second = UUID()

        viewModel.start(.init(id: first, title: "Meeting", operation: .transcribing))
        viewModel.start(.init(id: second, title: "File", operation: .waiting(detail: "Queued")))

        XCTAssertEqual(viewModel.focusedJob?.id, first)
        XCTAssertEqual(viewModel.otherJobs.map(\.id), [second])
    }

    func testUpdateClampsRealProgressAndChangesOperation() {
        let viewModel = OfflineProcessingViewModel()
        let id = UUID()
        viewModel.start(.init(id: id, title: "Meeting", operation: .preparing))

        viewModel.update(id: id, operation: .transcribing, fraction: 1.4)

        XCTAssertEqual(viewModel.focusedJob?.operation, .transcribing)
        XCTAssertEqual(viewModel.focusedJob?.fraction, 1)
    }

    func testFinishRemovesCompletedWorkImmediately() {
        let viewModel = OfflineProcessingViewModel()
        let id = UUID()
        viewModel.start(.init(id: id, title: "Meeting", operation: .finalizing))

        viewModel.finish(id: id)

        XCTAssertTrue(viewModel.jobs.isEmpty)
    }

    func testCancelUsesJobOwnedAction() {
        let viewModel = OfflineProcessingViewModel()
        let id = UUID()
        var cancelled = false
        viewModel.start(
            .init(id: id, title: "File", operation: .transcribing, canCancel: true),
            onCancel: { cancelled = true }
        )

        viewModel.cancel(id: id)

        XCTAssertTrue(cancelled)
    }

    func testIssuesAreItemOwnedAndRecoverable() {
        let viewModel = OfflineProcessingViewModel()
        let itemID = UUID()
        let otherItemID = UUID()
        let issueID = UUID()
        var recovered = false
        viewModel.reportIssue(
            .init(
                id: issueID,
                itemID: itemID,
                title: "Action Items failed",
                detail: "Provider unavailable",
                recoveryTitle: "Retry"
            ),
            onRecover: { recovered = true }
        )

        XCTAssertEqual(viewModel.issues(for: itemID).map(\.id), [issueID])
        XCTAssertTrue(viewModel.issues(for: otherItemID).isEmpty)

        viewModel.recover(issueID: issueID)
        XCTAssertTrue(recovered)

        viewModel.dismiss(issueID: issueID)
        XCTAssertTrue(viewModel.issues(for: itemID).isEmpty)
    }
}

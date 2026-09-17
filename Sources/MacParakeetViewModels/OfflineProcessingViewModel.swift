import Foundation
import MacParakeetCore

/// Process-wide source of truth for offline transcription and post-processing.
/// Live capture, live preview, and meeting-pill state do not enter this model.
@MainActor
@Observable
public final class OfflineProcessingViewModel {
    public enum Locality: Equatable, Sendable {
        case onDevice
        case ai
    }

    public enum Operation: Equatable, Sendable {
        case preparing
        case waiting(detail: String)
        case downloading
        case converting
        case preparingSpeechModel
        case transcribing
        case identifyingSpeakers
        case formatting
        case finalizing
        case adjustingSpeakers
        case generatingTitle
        case generatingResult(name: String)

        public var title: String {
            switch self {
            case .preparing: "Preparing"
            case .waiting: "Waiting to process"
            case .downloading: "Downloading audio"
            case .converting: "Preparing audio"
            case .preparingSpeechModel: "Preparing speech model"
            case .transcribing: "Transcribing"
            case .identifyingSpeakers: "Identifying speakers"
            case .formatting: "Formatting transcript"
            case .finalizing: "Finalizing transcript"
            case .adjustingSpeakers: "Adjusting speakers"
            case .generatingTitle: "Generating title"
            case .generatingResult(let name): "Writing \(name)"
            }
        }

        public var detail: String {
            switch self {
            case .waiting(let detail): detail
            case .preparing: "Preparing offline processing"
            case .downloading: "Fetching source audio"
            case .converting: "Normalizing audio"
            case .preparingSpeechModel: "Loading the selected speech model"
            case .transcribing: "Running speech recognition"
            case .identifyingSpeakers: "Analyzing speaker changes"
            case .formatting: "Building the readable transcript"
            case .finalizing: "Saving the result"
            case .adjustingSpeakers: "Rebuilding Reading Turns"
            case .generatingTitle: "Using the configured AI provider"
            case .generatingResult: "Using the configured AI provider"
            }
        }

        public var locality: Locality {
            switch self {
            case .generatingTitle, .generatingResult: .ai
            default: .onDevice
            }
        }
    }

    public struct Job: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var itemID: UUID?
        public var title: String
        public var operation: Operation
        public var fraction: Double?
        public var canCancel: Bool

        public init(
            id: UUID,
            itemID: UUID? = nil,
            title: String,
            operation: Operation,
            fraction: Double? = nil,
            canCancel: Bool = false
        ) {
            self.id = id
            self.itemID = itemID
            self.title = title
            self.operation = operation
            self.fraction = fraction.map { min(max($0, 0), 1) }
            self.canCancel = canCancel
        }
    }

    public struct Issue: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let itemID: UUID
        public var title: String
        public var detail: String
        public var recoveryTitle: String?

        public init(
            id: UUID = UUID(),
            itemID: UUID,
            title: String,
            detail: String,
            recoveryTitle: String? = nil
        ) {
            self.id = id
            self.itemID = itemID
            self.title = title
            self.detail = detail
            self.recoveryTitle = recoveryTitle
        }
    }

    public private(set) var jobs: [Job] = []
    public private(set) var issues: [Issue] = []

    @ObservationIgnored private var cancelActions: [UUID: @MainActor () -> Void] = [:]
    @ObservationIgnored private var recoveryActions: [UUID: @MainActor () -> Void] = [:]

    public init() {}

    public var focusedJob: Job? { jobs.first }
    public var otherJobs: ArraySlice<Job> { jobs.dropFirst() }

    public func start(
        _ job: Job,
        onCancel: (@MainActor () -> Void)? = nil
    ) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
        if let onCancel {
            cancelActions[job.id] = onCancel
        } else {
            cancelActions.removeValue(forKey: job.id)
        }
    }

    public func update(
        id: UUID,
        itemID: UUID? = nil,
        title: String? = nil,
        operation: Operation,
        fraction: Double?
    ) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if let itemID { jobs[index].itemID = itemID }
        if let title { jobs[index].title = title }
        jobs[index].operation = operation
        jobs[index].fraction = fraction.map { min(max($0, 0), 1) }
    }

    public func associate(id: UUID, with itemID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].itemID = itemID
    }

    public func finish(id: UUID) {
        jobs.removeAll { $0.id == id }
        cancelActions.removeValue(forKey: id)
    }

    public func cancel(id: UUID) {
        cancelActions[id]?()
    }

    public func reportIssue(
        _ issue: Issue,
        onRecover: (@MainActor () -> Void)? = nil
    ) {
        if let index = issues.firstIndex(where: { $0.id == issue.id }) {
            issues[index] = issue
        } else {
            issues.append(issue)
        }
        if let onRecover {
            recoveryActions[issue.id] = onRecover
        }
    }

    public func issues(for itemID: UUID) -> [Issue] {
        issues.filter { $0.itemID == itemID }
    }

    public func recover(issueID: UUID) {
        recoveryActions[issueID]?()
    }

    public func dismiss(issueID: UUID) {
        issues.removeAll { $0.id == issueID }
        recoveryActions.removeValue(forKey: issueID)
    }
}

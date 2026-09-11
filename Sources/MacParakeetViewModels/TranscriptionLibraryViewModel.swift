import Foundation
import MacParakeetCore
import os

public enum LibraryFilter: String, CaseIterable, Sendable {
    case all = "All"
    case youtube = "Video"
    case podcast = "Podcasts"
    case local = "Local"
    case meeting = "Meetings"
    case favorites = "Favorites"
}

public enum TranscriptionLibraryScope: Sendable {
    case all
    case meetings
}

public typealias LibrarySortOrder = TranscriptionLibrarySortOrder
public typealias LibraryLocation = TranscriptionLibraryLocation

public struct LibraryFolderNode: Identifiable, Sendable, Equatable {
    public let folder: LibraryFolder
    public let children: [LibraryFolderNode]

    public var id: UUID { folder.id }

    public init(folder: LibraryFolder, children: [LibraryFolderNode]) {
        self.folder = folder
        self.children = children
    }
}

/// Date-based bucket used to group meeting/library rows under headers like
/// "Today", "Yesterday", "Previous 7 Days". Computed against the user's
/// current calendar — never against a fixed timezone.
public enum TranscriptionDateGroup: Hashable, Sendable {
    case today
    case yesterday
    case previous7Days
    case previous30Days
    case month(year: Int, month: Int)

    /// Sort key — relative buckets first (today, yesterday, …), then month
    /// buckets in descending date order. Tuple-based so months always sort
    /// after relative buckets regardless of year value.
    public var sortKey: (Int, Int) {
        switch self {
        case .today: return (0, 0)
        case .yesterday: return (1, 0)
        case .previous7Days: return (2, 0)
        case .previous30Days: return (3, 0)
        case .month(let year, let month):
            // Negate so newer months sort smaller within the month bucket.
            return (4, -(year * 12 + month))
        }
    }

    public static func bucket(for date: Date, now: Date, calendar: Calendar) -> TranscriptionDateGroup {
        let startOfNow = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? 0

        if days <= 0 { return .today }
        if days == 1 { return .yesterday }
        if days <= 7 { return .previous7Days }
        if days <= 30 { return .previous30Days }

        let comps = calendar.dateComponents([.year, .month], from: date)
        return .month(year: comps.year ?? 0, month: comps.month ?? 0)
    }
}

public enum BulkTranscriptionOperation: Sendable {
    case deleteItems([Transcription])
    case deleteAudioOnly(targets: [Transcription], skipped: Int)

    public var targetCount: Int {
        switch self {
        case .deleteItems(let targets), .deleteAudioOnly(let targets, _):
            return targets.count
        }
    }

    public var skippedCount: Int {
        switch self {
        case .deleteItems:
            return 0
        case .deleteAudioOnly(_, let skipped):
            return skipped
        }
    }

    public var meetingCount: Int {
        switch self {
        case .deleteItems(let targets):
            return targets.filter { $0.sourceType == .meeting }.count
        case .deleteAudioOnly(let targets, _):
            return targets.count
        }
    }

    public var hasNonCompletedMeeting: Bool {
        switch self {
        case .deleteItems(let targets), .deleteAudioOnly(let targets, _):
            return targets.contains { transcription in
                transcription.sourceType == .meeting && transcription.status != .completed
            }
        }
    }

    public var isDeleteAudioOnly: Bool {
        if case .deleteAudioOnly = self { return true }
        return false
    }
}

public struct BulkOperationResult: Sendable, Equatable {
    public let succeeded: Int
    public let failed: Int
    public let skipped: Int

    public init(succeeded: Int, failed: Int, skipped: Int = 0) {
        self.succeeded = succeeded
        self.failed = failed
        self.skipped = skipped
    }
}

@MainActor @Observable
public final class TranscriptionLibraryViewModel {
    private let logger = Logger(subsystem: "com.macparakeet.viewmodels", category: "TranscriptionLibrary")
    public private(set) var transcriptions: [Transcription] = []
    public private(set) var folders: [LibraryFolder] = []
    public private(set) var location: LibraryLocation
    public var filter: LibraryFilter = .all { didSet { reloadAfterStateChange() } }
    public var searchText: String = "" { didSet { debounceSearchReload() } }
    public var sortOrder: LibrarySortOrder = .dateDescending { didSet { reloadAfterStateChange() } }
    public private(set) var filteredTranscriptions: [Transcription] = []
    public private(set) var groupedTranscriptions: [(group: TranscriptionDateGroup, items: [Transcription])] = []
    public private(set) var hasMore = false
    public private(set) var isLoading = false
    public var errorMessage: String?
    public var pageSize = 100
    public var searchDebounceInterval: Duration = .milliseconds(300)
    public private(set) var selectedTranscriptionIDs: Set<UUID> = []
    public private(set) var isBulkSelectionModeEnabled = false
    public private(set) var isBulkOperationInProgress = false
    public private(set) var pendingBulkOperation: BulkTranscriptionOperation?
    public private(set) var retryingMeetingTranscriptionIDs: Set<UUID> = []
    public private(set) var regeneratingMeetingTitleIDs: Set<UUID> = []
    public private(set) var pendingItemOperationIDs: Set<UUID> = []
    public var onRetryMeetingTranscription: ((Transcription) async throws -> Void)?
    public var onRegenerateMeetingTitle: ((Transcription) async throws -> Void)?

    /// Override for tests; production code uses `Date()`.
    public var nowProvider: @Sendable () -> Date = { Date() }
    public var calendar: Calendar = .autoupdatingCurrent

    private var transcriptionRepo: TranscriptionRepositoryProtocol?
    private var folderRepo: LibraryFolderRepositoryProtocol?
    private var loadTask: Task<Void, Never>?
    private var folderLoadTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var detailSelectionGeneration = 0
    private var hasLoadedSnapshot = false
    private var bulkSelectionGeneration = 0
    public let scope: TranscriptionLibraryScope

    public init(scope: TranscriptionLibraryScope = .all) {
        self.scope = scope
        location = scope == .all ? .root : .allItems
    }

    public func configure(
        transcriptionRepo: TranscriptionRepositoryProtocol,
        folderRepo: LibraryFolderRepositoryProtocol? = nil
    ) {
        self.transcriptionRepo = transcriptionRepo
        self.folderRepo = folderRepo
    }

    public var folderTree: [LibraryFolderNode] {
        Self.makeFolderNodes(parentID: nil, folders: folders)
    }

    public var currentFolder: LibraryFolder? {
        guard case .folder(let id) = location else { return nil }
        return folders.first { $0.id == id }
    }

    public var currentLocationTitle: String {
        switch location {
        case .allItems: return "All Items"
        case .root: return "Library"
        case .folder(let id): return folders.first(where: { $0.id == id })?.name ?? "Library"
        }
    }

    public var currentFolderPath: [LibraryFolder] {
        guard var folder = currentFolder else { return [] }
        var reversed = [folder]
        var seen: Set<UUID> = [folder.id]
        while let parentID = folder.parentID,
            let parent = folders.first(where: { $0.id == parentID }),
            seen.insert(parent.id).inserted
        {
            reversed.append(parent)
            folder = parent
        }
        return reversed.reversed()
    }

    public func selectLocation(_ newLocation: LibraryLocation) {
        guard scope == .all, location != newLocation else { return }
        finishBulkSelection()
        location = newLocation
        loadTranscriptions()
    }

    /// Reset only Library navigation state. Sort order remains a genuine user
    /// preference; selection, folder/detail location, filter, and search are
    /// destinations and must not survive an explicit sidebar click.
    public func resetNavigationToRoot() {
        guard scope == .all else { return }
        finishBulkSelection()
        let needsReload = location != .root || filter != .all || !searchText.isEmpty
        location = .root
        filter = .all
        searchText = ""
        if !needsReload {
            loadTranscriptionsIfNeeded()
        }
    }

    @discardableResult
    public func loadFolders() -> Task<Void, Never> {
        folderLoadTask?.cancel()
        guard let folderRepo else {
            folders = []
            return Task {}
        }
        let task = Task { @MainActor [weak self, folderRepo] in
            do {
                let folders = try await Task.detached(priority: .userInitiated) {
                    try folderRepo.fetchAll()
                }.value
                guard let self, !Task.isCancelled else { return }
                self.folders = folders
                if case .folder(let id) = self.location, !folders.contains(where: { $0.id == id }) {
                    self.location = .root
                    self.loadTranscriptions()
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.errorMessage = "Failed to load Library folders: \(error.localizedDescription)"
            }
        }
        folderLoadTask = task
        return task
    }

    @discardableResult
    public func createFolder(name: String) async -> LibraryFolder? {
        guard let folderRepo else { return nil }
        let parentID: UUID?
        if case .folder(let id) = location { parentID = id } else { parentID = nil }
        do {
            let folder = try await Task.detached(priority: .userInitiated) {
                try folderRepo.create(name: name, parentID: parentID)
            }.value
            await loadFolders().value
            return folder
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    public func moveTranscriptions(_ transcriptions: [Transcription], to folderID: UUID?) async -> Bool {
        guard let transcriptionRepo, !transcriptions.isEmpty else { return false }
        isBulkOperationInProgress = true
        errorMessage = nil
        do {
            try await Task.detached(priority: .userInitiated) {
                try transcriptionRepo.moveToLibraryFolder(ids: transcriptions.map(\.id), folderID: folderID)
            }.value
            isBulkOperationInProgress = false
            finishBulkSelection()
            if scope == .all {
                location = folderID.map(LibraryLocation.folder) ?? .root
            }
            await loadTranscriptions().value
            return true
        } catch {
            isBulkOperationInProgress = false
            errorMessage = "Failed to move Library items: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    public func moveSelectedTranscriptions(to folderID: UUID?) async -> Bool {
        await moveTranscriptions(selectedLoadedTranscriptions, to: folderID)
    }

    @discardableResult
    public func deleteFolder(_ folder: LibraryFolder) async -> Bool {
        guard let folderRepo else { return false }
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try folderRepo.delete(id: folder.id)
            }.value
            location = .root
            await loadFolders().value
            await loadTranscriptions().value
            return true
        } catch {
            errorMessage = "Failed to delete folder: \(error.localizedDescription)"
            return false
        }
    }

    public var selectedTranscriptionCount: Int {
        selectedTranscriptionIDs.count
    }

    public var hasSelectedTranscriptions: Bool {
        !selectedTranscriptionIDs.isEmpty
    }

    public var areAllLoadedVisibleTranscriptionsSelected: Bool {
        let ids = loadedVisibleTranscriptionIDs
        return ids.isEmpty || ids.isSubset(of: selectedTranscriptionIDs)
    }

    public var selectedMeetingAudioCount: Int {
        selectedLoadedTranscriptions.filter(Self.hasRemovableMeetingAudio).count
    }

    public var selectedLoadedTranscriptionsForExport: [Transcription] {
        selectedLoadedTranscriptions
    }

    private func groupByDate(_ items: [Transcription]) -> [(group: TranscriptionDateGroup, items: [Transcription])] {
        guard !items.isEmpty else { return [] }
        let now = nowProvider()

        // Bucket by logical group, not by adjacency. Items within each bucket
        // preserve the input order (so `titleAscending` sort produces a
        // group's items in alphabetical order). Buckets themselves sort by
        // `sortKey` so groups appear in the same order regardless of the
        // input sort.
        var bucketed: [TranscriptionDateGroup: [Transcription]] = [:]
        var encounterOrder: [TranscriptionDateGroup] = []

        for item in items {
            let group = TranscriptionDateGroup.bucket(for: item.createdAt, now: now, calendar: calendar)
            if bucketed[group] == nil {
                encounterOrder.append(group)
            }
            bucketed[group, default: []].append(item)
        }

        return
            encounterOrder
            .sorted { $0.sortKey < $1.sortKey }
            .map { group in (group: group, items: bucketed[group] ?? []) }
    }

    @discardableResult
    public func loadTranscriptions() -> Task<Void, Never> {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        return loadPage(offset: 0, append: false)
    }

    /// Keep the current page visible when SwiftUI remounts the list after a
    /// detail view. Mutations and query changes call `loadTranscriptions()`
    /// directly and therefore still refresh the snapshot.
    @discardableResult
    public func loadTranscriptionsIfNeeded() -> Task<Void, Never> {
        guard !hasLoadedSnapshot else { return Task {} }
        return loadTranscriptions()
    }

    /// Fetch the complete record only after explicit detail demand. A slower
    /// earlier click cannot publish after a newer selection.
    public func fullTranscriptionForDetail(_ item: Transcription) async -> Transcription? {
        guard let repo = transcriptionRepo else { return nil }
        detailSelectionGeneration += 1
        let generation = detailSelectionGeneration
        do {
            let full = try await Task.detached(priority: .userInitiated) {
                try repo.fetch(id: item.id)
            }.value
            guard generation == detailSelectionGeneration else { return nil }
            return full
        } catch {
            guard generation == detailSelectionGeneration else { return nil }
            errorMessage = "Failed to open transcription: \(error.localizedDescription)"
            return nil
        }
    }

    public func syncListMetadata(from full: Transcription) {
        guard let index = transcriptions.firstIndex(where: { $0.id == full.id }) else { return }
        transcriptions[index].fileName = full.fileName
        transcriptions[index].filePath = full.filePath
        transcriptions[index].meetingArtifactFolderPath = full.meetingArtifactFolderPath
        transcriptions[index].durationMs = full.durationMs
        transcriptions[index].status = full.status
        transcriptions[index].errorMessage = full.errorMessage
        transcriptions[index].isFavorite = full.isFavorite
        transcriptions[index].speakerCount = full.speakerCount
        transcriptions[index].titleOverride = full.titleOverride
        transcriptions[index].derivedTitle = full.derivedTitle
        transcriptions[index].derivedSnippet = full.derivedSnippet
        transcriptions[index].updatedAt = full.updatedAt
        publishLoadedItems(transcriptions, hasMore: hasMore)
    }

    public func fullTranscriptions(ids: [UUID]) async throws -> [Transcription] {
        guard let repo = transcriptionRepo else { return [] }
        return try await Task.detached(priority: .userInitiated) {
            try ids.compactMap { try repo.fetch(id: $0) }
        }.value
    }

    @discardableResult
    public func loadMoreTranscriptions() -> Task<Void, Never>? {
        guard hasMore, !isLoading else { return nil }
        return loadPage(offset: transcriptions.count, append: true)
    }

    public func toggleFavorite(_ transcription: Transcription) async {
        guard let repo = transcriptionRepo else { return }
        let newValue = !transcription.isFavorite
        pendingItemOperationIDs.insert(transcription.id)
            errorMessage = nil
        defer { pendingItemOperationIDs.remove(transcription.id) }
        do {
            try await Task.detached(priority: .userInitiated) {
                try repo.updateFavorite(id: transcription.id, isFavorite: newValue)
            }.value
            if let idx = transcriptions.firstIndex(where: { $0.id == transcription.id }) {
                if filter == .favorites && !newValue {
                    transcriptions.remove(at: idx)
                } else {
                    transcriptions[idx].isFavorite = newValue
                }
                publishLoadedItems(transcriptions, hasMore: hasMore)
            }
            Telemetry.send(.transcriptionFavorited(isFavorite: newValue))
        } catch {
            logger.error("Failed to update transcription favorite: \(error.localizedDescription, privacy: .private)")
            errorMessage = "Failed to update favorite: \(error.localizedDescription)"
        }
    }

    public func isRetryingMeetingTranscription(_ transcription: Transcription) -> Bool {
        retryingMeetingTranscriptionIDs.contains(transcription.id)
    }

    @discardableResult
    public func retryMeetingTranscription(_ transcription: Transcription) -> Task<Void, Never> {
        guard transcription.sourceType == .meeting,
            Self.isRetryableMeetingTranscription(transcription),
            !retryingMeetingTranscriptionIDs.contains(transcription.id)
        else {
            return Task {}
        }
        guard let retry = onRetryMeetingTranscription else {
            errorMessage = "Meeting retry is not available."
            return Task {}
        }
        guard let repo = transcriptionRepo else {
            errorMessage = "Meeting retry is not available."
            return Task {}
        }

        retryingMeetingTranscriptionIDs.insert(transcription.id)

        return Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.retryingMeetingTranscriptionIDs.remove(transcription.id)
            }
            do {
                let full = try await Task.detached(priority: .userInitiated) {
                    try repo.fetch(id: transcription.id) ?? transcription
                }.value
                try await retry(full)
                do {
                    try self.refreshLoadedTranscription(id: transcription.id)
                } catch {
                    self.logger.error(
                        "Retried meeting transcription but failed to refresh Library: \(error.localizedDescription, privacy: .private)"
                    )
                    self.errorMessage = "Retried meeting, but failed to refresh Library: \(error.localizedDescription)"
                }
            } catch {
                self.logger.error(
                    "Failed to retry meeting transcription: \(error.localizedDescription, privacy: .private)")
                self.errorMessage = "Failed to retry meeting transcription: \(error.localizedDescription)"
                try? self.refreshLoadedTranscription(id: transcription.id)
            }
        }
    }

    public func isRegeneratingMeetingTitle(_ transcription: Transcription) -> Bool {
        regeneratingMeetingTitleIDs.contains(transcription.id)
    }

    @discardableResult
    public func regenerateMeetingTitle(_ transcription: Transcription) -> Task<Void, Never> {
        guard transcription.sourceType == .meeting,
              !regeneratingMeetingTitleIDs.contains(transcription.id)
        else {
            return Task {}
        }
        guard let regenerate = onRegenerateMeetingTitle, let repo = transcriptionRepo else {
            errorMessage = "Meeting title regeneration is not available."
            return Task {}
        }

        regeneratingMeetingTitleIDs.insert(transcription.id)
        errorMessage = nil

        return Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.regeneratingMeetingTitleIDs.remove(transcription.id) }
            do {
                let full = try await Task.detached(priority: .userInitiated) {
                    try repo.fetch(id: transcription.id) ?? transcription
                }.value
                try await regenerate(full)
                try self.refreshLoadedTranscription(id: transcription.id)
            } catch {
                self.logger.error(
                    "Failed to regenerate meeting title: \(error.localizedDescription, privacy: .private)"
                )
                self.errorMessage = "Failed to regenerate meeting title: \(error.localizedDescription)"
                try? self.refreshLoadedTranscription(id: transcription.id)
            }
        }
    }

    public func isTranscriptionSelected(_ transcription: Transcription) -> Bool {
        selectedTranscriptionIDs.contains(transcription.id)
    }

    public func toggleSelection(for transcription: Transcription) {
        guard !isBulkOperationInProgress else { return }
        bulkSelectionGeneration += 1
        if selectedTranscriptionIDs.contains(transcription.id) {
            selectedTranscriptionIDs.remove(transcription.id)
        } else {
            selectedTranscriptionIDs.insert(transcription.id)
        }
    }

    public func selectLoadedVisibleTranscriptions() {
        guard !isBulkOperationInProgress else { return }
        bulkSelectionGeneration += 1
        selectedTranscriptionIDs = loadedVisibleTranscriptionIDs
    }

    public func clearSelection() {
        guard !isBulkOperationInProgress else { return }
        bulkSelectionGeneration += 1
        selectedTranscriptionIDs = []
    }

    public func beginBulkSelection(startingWith transcription: Transcription? = nil) {
        guard !isBulkOperationInProgress else { return }
        bulkSelectionGeneration += 1
        isBulkSelectionModeEnabled = true
        if let transcription {
            selectedTranscriptionIDs.insert(transcription.id)
        }
    }

    public func exitBulkSelection() {
        guard !isBulkOperationInProgress else { return }
        finishBulkSelection()
    }

    private func finishBulkSelection() {
        bulkSelectionGeneration += 1
        isBulkSelectionModeEnabled = false
        selectedTranscriptionIDs = []
        pendingBulkOperation = nil
    }

    public func cancelPendingBulkOperation() {
        guard !isBulkOperationInProgress else { return }
        pendingBulkOperation = nil
    }

    public func requestDeleteSelectedItems() {
        guard !isBulkOperationInProgress else { return }
        let targets = selectedLoadedTranscriptions
        guard !targets.isEmpty else {
            clearSelection()
            return
        }
        pendingBulkOperation = .deleteItems(targets)
    }

    public func requestDeleteSelectedMeetingAudio() {
        guard !isBulkOperationInProgress else { return }
        // Scope to meetings: "Remove Audio" only applies to meeting rows, so the
        // skipped count must be meetings-without-removable-audio, not every
        // selected non-meeting item. Counting all non-targets here mislabels
        // videos/podcasts/local files as skipped meetings in the confirmation
        // copy, which is meeting-only by design.
        let meetings = selectedLoadedTranscriptions.filter { $0.sourceType == .meeting }
        let targets = meetings.filter(Self.hasRemovableMeetingAudio)
        guard !targets.isEmpty else {
            return
        }
        pendingBulkOperation = .deleteAudioOnly(
            targets: targets,
            skipped: meetings.count - targets.count
        )
    }

    /// Snapshot the current pending operation and run it. Convenience for
    /// callers (and tests) that have just populated `pendingBulkOperation`.
    @discardableResult
    public func confirmPendingBulkOperation() async -> BulkOperationResult {
        guard let operation = pendingBulkOperation else {
            return BulkOperationResult(succeeded: 0, failed: 0)
        }
        return await confirmBulkOperation(operation)
    }

    /// Run a previously captured bulk operation.
    ///
    /// The confirm button in the bulk-delete alert MUST capture the operation
    /// synchronously and call this, rather than re-reading `pendingBulkOperation`
    /// from inside its deferred `Task`. Tapping that button also dismisses the
    /// alert, and the alert's `isPresented` setter runs
    /// `cancelPendingBulkOperation()`, which nils `pendingBulkOperation`. The
    /// dismissal fires before the Task body, so a re-read would see `nil` and
    /// silently no-op (the "delete does nothing" bug). Taking the operation by
    /// value sidesteps the race.
    @discardableResult
    public func confirmBulkOperation(_ operation: BulkTranscriptionOperation) async -> BulkOperationResult {
        guard !isBulkOperationInProgress else {
            return BulkOperationResult(succeeded: 0, failed: 0, skipped: operation.skippedCount)
        }
        pendingBulkOperation = nil
        guard let repo = transcriptionRepo else {
            errorMessage = "Unable to update Library: database is not available."
            return BulkOperationResult(succeeded: 0, failed: operation.targetCount, skipped: operation.skippedCount)
        }

        bulkSelectionGeneration += 1
        let operationGeneration = bulkSelectionGeneration
        isBulkSelectionModeEnabled = true
        isBulkOperationInProgress = true
        errorMessage = nil

        switch operation {
        case .deleteItems(let targets):
            let result = await Task.detached(priority: .userInitiated) {
                Self.deleteTargets(targets, using: repo)
            }.value
            for _ in 0..<result.succeededIDs.count {
                Telemetry.send(.transcriptionDeleted)
            }
            if !result.succeededIDs.isEmpty {
                removeLoadedTranscriptions(withIDs: Set(result.succeededIDs))
            }
            if !result.failedIDs.isEmpty {
                isBulkOperationInProgress = false
                restoreFailedSelectionIfCurrent(result.failedIDs, operationGeneration: operationGeneration)
                errorMessage = Self.bulkDeleteFailureMessage(
                    succeeded: result.succeededIDs.count, failed: result.failedIDs.count)
            } else {
                isBulkOperationInProgress = false
                finishBulkSelection()
            }
            return BulkOperationResult(
                succeeded: result.succeededIDs.count,
                failed: result.failedIDs.count
            )

        case .deleteAudioOnly(let targets, let skipped):
            let result = await Task.detached(priority: .userInitiated) {
                Self.detachMeetingAudioTargets(targets, using: repo)
            }.value
            if !result.succeededIDs.isEmpty {
                clearLoadedMeetingAudio(forIDs: Set(result.succeededIDs))
            }
            if !result.failedIDs.isEmpty {
                isBulkOperationInProgress = false
                restoreFailedSelectionIfCurrent(result.failedIDs, operationGeneration: operationGeneration)
                errorMessage = Self.bulkAudioDeleteFailureMessage(
                    succeeded: result.succeededIDs.count,
                    failed: result.failedIDs.count,
                    skipped: skipped
                )
            } else {
                isBulkOperationInProgress = false
                finishBulkSelection()
            }
            return BulkOperationResult(
                succeeded: result.succeededIDs.count,
                failed: result.failedIDs.count,
                skipped: skipped
            )
        }
    }

    public func deleteTranscription(_ transcription: Transcription) async {
        guard let repo = transcriptionRepo else { return }
        pendingItemOperationIDs.insert(transcription.id)
            errorMessage = nil
        defer { pendingItemOperationIDs.remove(transcription.id) }
        do {
            let deleted = try await Task.detached(priority: .userInitiated) {
                let full = try repo.fetch(id: transcription.id) ?? transcription
                try TranscriptionDeletionCleanup.removeOwnedAssets(for: full)
                return try repo.delete(id: transcription.id)
            }.value
            guard deleted else { return }
            transcriptions.removeAll { $0.id == transcription.id }
            selectedTranscriptionIDs.remove(transcription.id)
            publishLoadedItems(transcriptions, hasMore: hasMore)
            Telemetry.send(.transcriptionDeleted)
        } catch {
            logger.error("Failed to delete transcription: \(error.localizedDescription, privacy: .private)")
            errorMessage = "Failed to delete transcription: \(error.localizedDescription)"
        }
    }

    public func deleteMeetingAudio(_ transcription: Transcription) async {
        guard let repo = transcriptionRepo, transcription.sourceType == .meeting else { return }
        pendingItemOperationIDs.insert(transcription.id)
            errorMessage = nil
        defer { pendingItemOperationIDs.remove(transcription.id) }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let full = try repo.fetch(id: transcription.id) ?? transcription
                return try TranscriptionAssetCleanup.detachOwnedMeetingAudio(
                    for: full,
                repository: repo
            )
            }.value
            guard result.detached else {
                errorMessage = TranscriptionAssetCleanup.unmanagedMeetingAudioMessage
                return
            }
            if let idx = transcriptions.firstIndex(where: { $0.id == transcription.id }) {
                transcriptions[idx].meetingArtifactFolderPath =
                    transcriptions[idx].meetingArtifactFolderPath
                    ?? MeetingArtifactStore.sessionFolderURL(for: transcription)?.standardizedFileURL.path
                transcriptions[idx].filePath = nil
                publishLoadedItems(transcriptions, hasMore: hasMore)
            }
        } catch TranscriptionAssetCleanupError.meetingAudioFinalizationInProgress {
            errorMessage = TranscriptionAssetCleanup.meetingAudioFinalizationInProgressMessage
        } catch {
            logger.error("Failed to delete meeting audio: \(error.localizedDescription, privacy: .private)")
            errorMessage = "Failed to delete meeting audio: \(error.localizedDescription)"
        }
    }

    @discardableResult
    public func renameTranscriptionTitle(_ transcription: Transcription, to title: String) async -> Bool {
        guard transcription.sourceType == .file else { return false }
        guard let repo = transcriptionRepo else { return false }
        guard let normalizedTitle = Transcription.normalizedTitleOverride(from: title),
            normalizedTitle != transcription.effectiveDisplayTitle
        else {
            return false
        }

        let operationLoadGeneration = loadGeneration
        let wasVisible = transcriptions.contains { $0.id == transcription.id }
        errorMessage = nil
        pendingItemOperationIDs.insert(transcription.id)
        defer { pendingItemOperationIDs.remove(transcription.id) }
        do {
            try await Task.detached(priority: .userInitiated) {
            try repo.updateTitleOverride(id: transcription.id, titleOverride: normalizedTitle)
            }.value
        } catch {
            logger.error("Failed to rename transcription title: \(error.localizedDescription, privacy: .private)")
            errorMessage = "Failed to rename transcription: \(error.localizedDescription)"
            return false
        }

        // Cancel only the load that was already active when Rename started.
        // A query change made while the write was pending owns a newer
        // generation and must publish normally.
        guard wasVisible, loadGeneration == operationLoadGeneration else { return true }
        if loadTask != nil {
            cancelActiveLoad()
        }
        guard let index = transcriptions.firstIndex(where: { $0.id == transcription.id }) else { return true }
        transcriptions[index].titleOverride = normalizedTitle
        transcriptions[index].updatedAt = Date()
        if !transcriptions.isEmpty {
            if sortOrder == .titleAscending {
                transcriptions.sort {
                    let comparison = $0.effectiveDisplayTitle.localizedCaseInsensitiveCompare($1.effectiveDisplayTitle)
                    return comparison == .orderedSame ? $0.createdAt > $1.createdAt : comparison == .orderedAscending
                }
            }
            publishLoadedItems(transcriptions, hasMore: hasMore)
        }
        return true
    }

    private func reloadAfterStateChange() {
        exitBulkSelection()
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        loadTranscriptions()
    }

    private func reloadLoadedWindow() throws {
        guard let repo = transcriptionRepo else { return }
        guard var query = makeQuery(offset: 0) else {
            publishLoadedItems([], hasMore: false)
            return
        }
        query.limit = max(pageSize, transcriptions.count)
        let page = try repo.fetchLibraryListPage(query: query)
        publishLoadedItems(page.items, hasMore: page.hasMore)
    }

    private func refreshLoadedTranscription(id: UUID) throws {
        guard let repo = transcriptionRepo else { return }
        guard let index = transcriptions.firstIndex(where: { $0.id == id }) else { return }
        // An in-flight load would later publish a snapshot fetched before this
        // refresh, resurrecting the row's pre-retry status. Invalidate it; the
        // generation bump makes any late publish a no-op.
        if loadTask != nil {
            cancelActiveLoad()
        }
        guard let refreshed = try repo.fetch(id: id) else {
            removeLoadedTranscriptions(withIDs: [id])
            return
        }
        transcriptions[index] = refreshed
        publishLoadedItems(transcriptions, hasMore: hasMore)
    }

    private func cancelActiveLoad() {
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
        isLoading = false
    }

    private func debounceSearchReload() {
        exitBulkSelection()
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if self.searchDebounceInterval > .zero {
                try? await Task.sleep(for: self.searchDebounceInterval)
            }
            guard !Task.isCancelled else { return }
            self.searchDebounceTask = nil
            self.loadPage(offset: 0, append: false)
        }
    }

    @discardableResult
    private func loadPage(offset: Int, append: Bool) -> Task<Void, Never> {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration

        guard let repo = transcriptionRepo else {
            isLoading = false
            publishLoadedItems([], hasMore: false)
            return Task {}
        }
        guard let query = makeQuery(offset: offset) else {
            isLoading = false
            publishLoadedItems([], hasMore: false)
            return Task {}
        }

        isLoading = true
        errorMessage = nil

        let task = Task { @MainActor [weak self, repo, query] in
            do {
                let page = try await Task.detached(priority: .userInitiated) {
                    try repo.fetchLibraryListPage(query: query)
                }.value
                guard let self, !Task.isCancelled, self.loadGeneration == generation else { return }
                let items = append ? self.transcriptions + page.items : page.items
                self.publishLoadedItems(items, hasMore: page.hasMore)
                self.isLoading = false
            } catch {
                guard let self, !Task.isCancelled, self.loadGeneration == generation else { return }
                self.logger.error("Failed to load transcriptions: \(error.localizedDescription, privacy: .private)")
                self.publishLoadedItems([], hasMore: false)
                self.isLoading = false
                self.errorMessage = "Failed to load transcriptions: \(error.localizedDescription)"
            }
        }
        loadTask = task
        return task
    }

    private func makeQuery(offset: Int) -> TranscriptionLibraryQuery? {
        let sourceType: Transcription.SourceType?
        let favoritesOnly: Bool

        switch (scope, filter) {
        case (.all, .all):
            sourceType = nil
            favoritesOnly = false
        case (.all, .youtube):
            sourceType = .youtube
            favoritesOnly = false
        case (.all, .podcast):
            sourceType = .podcast
            favoritesOnly = false
        case (.all, .local):
            sourceType = .file
            favoritesOnly = false
        case (.all, .meeting):
            sourceType = .meeting
            favoritesOnly = false
        case (.all, .favorites):
            sourceType = nil
            favoritesOnly = true
        case (.meetings, .all), (.meetings, .meeting):
            sourceType = .meeting
            favoritesOnly = false
        case (.meetings, .favorites):
            sourceType = .meeting
            favoritesOnly = true
        case (.meetings, .youtube), (.meetings, .podcast), (.meetings, .local):
            return nil
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptionLibraryQuery(
            sourceType: sourceType,
            location: scope == .all ? location : .allItems,
            favoritesOnly: favoritesOnly,
            searchText: trimmedSearch.isEmpty ? nil : trimmedSearch,
            sortOrder: sortOrder,
            limit: pageSize,
            offset: offset,
            includeProcessing: false,
            includeProcessingMeetings: true
        )
    }

    private func publishLoadedItems(_ items: [Transcription], hasMore: Bool) {
        hasLoadedSnapshot = true
        transcriptions = items
        filteredTranscriptions = items
        groupedTranscriptions = groupByDate(items)
        self.hasMore = hasMore
        pruneSelectionToLoadedItems()
    }

    private var loadedVisibleTranscriptionIDs: Set<UUID> {
        Set(filteredTranscriptions.map(\.id))
    }

    private var selectedLoadedTranscriptions: [Transcription] {
        filteredTranscriptions.filter { selectedTranscriptionIDs.contains($0.id) }
    }

    nonisolated private static func makeFolderNodes(
        parentID: UUID?,
        folders: [LibraryFolder]
    ) -> [LibraryFolderNode] {
        folders
            .filter { $0.parentID == parentID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { folder in
                LibraryFolderNode(
                    folder: folder,
                    children: makeFolderNodes(parentID: folder.id, folders: folders)
                )
            }
    }

    nonisolated private static func hasRemovableMeetingAudio(_ transcription: Transcription) -> Bool {
        MeetingAudioFile.isRemovable(for: transcription)
    }

    private func pruneSelectionToLoadedItems() {
        selectedTranscriptionIDs = selectedTranscriptionIDs.intersection(loadedVisibleTranscriptionIDs)
    }

    private func removeLoadedTranscriptions(withIDs ids: Set<UUID>) {
        transcriptions.removeAll { ids.contains($0.id) }
        selectedTranscriptionIDs.subtract(ids)
        publishLoadedItems(transcriptions, hasMore: hasMore)
    }

    private func clearLoadedMeetingAudio(forIDs ids: Set<UUID>) {
        for index in transcriptions.indices where ids.contains(transcriptions[index].id) {
            transcriptions[index].meetingArtifactFolderPath =
                transcriptions[index].meetingArtifactFolderPath
                ?? MeetingArtifactStore.sessionFolderURL(for: transcriptions[index])?.standardizedFileURL.path
            transcriptions[index].filePath = nil
        }
        publishLoadedItems(transcriptions, hasMore: hasMore)
    }

    private func setLoadedStatus(
        id: UUID,
        status: Transcription.TranscriptionStatus,
        errorMessage: String?
    ) {
        guard let index = transcriptions.firstIndex(where: { $0.id == id }) else { return }
        transcriptions[index].status = status
        transcriptions[index].errorMessage = errorMessage
        transcriptions[index].updatedAt = Date()
        publishLoadedItems(transcriptions, hasMore: hasMore)
    }

    nonisolated private static func isRetryableMeetingTranscription(_ transcription: Transcription) -> Bool {
        transcription.status == .error || transcription.status == .cancelled
    }

    private func restoreFailedSelectionIfCurrent(_ failedIDs: [UUID], operationGeneration: Int) {
        guard bulkSelectionGeneration == operationGeneration else { return }
        let visibleFailedIDs = Set(failedIDs).intersection(loadedVisibleTranscriptionIDs)
        guard !visibleFailedIDs.isEmpty else { return }
        isBulkSelectionModeEnabled = true
        selectedTranscriptionIDs = visibleFailedIDs
    }

    nonisolated private static func deleteTargets(
        _ targets: [Transcription],
        using repo: TranscriptionRepositoryProtocol
    ) -> BatchTargetResult {
        var succeededIDs: [UUID] = []
        var failedIDs: [UUID] = []

        for target in targets {
            do {
                let full = try repo.fetch(id: target.id) ?? target
                try TranscriptionDeletionCleanup.removeOwnedAssets(for: full)
                if try repo.delete(id: target.id) {
                    succeededIDs.append(target.id)
                } else {
                    failedIDs.append(target.id)
                }
            } catch {
                failedIDs.append(target.id)
            }
        }

        return BatchTargetResult(succeededIDs: succeededIDs, failedIDs: failedIDs)
    }

    nonisolated private static func detachMeetingAudioTargets(
        _ targets: [Transcription],
        using repo: TranscriptionRepositoryProtocol
    ) -> BatchTargetResult {
        var succeededIDs: [UUID] = []
        var failedIDs: [UUID] = []

        for target in targets {
            do {
                let full = try repo.fetch(id: target.id) ?? target
                let result = try TranscriptionAssetCleanup.detachOwnedMeetingAudio(
                    for: full,
                    repository: repo
                )
                if result.detached {
                    succeededIDs.append(target.id)
                } else {
                    failedIDs.append(target.id)
                }
            } catch {
                failedIDs.append(target.id)
            }
        }

        return BatchTargetResult(succeededIDs: succeededIDs, failedIDs: failedIDs)
    }

    nonisolated private static func bulkDeleteFailureMessage(succeeded: Int, failed: Int) -> String {
        if succeeded > 0 {
            return "Deleted \(succeeded) items. \(failed) could not be deleted."
        }
        return failed == 1 ? "1 item could not be deleted." : "\(failed) items could not be deleted."
    }

    nonisolated private static func bulkAudioDeleteFailureMessage(succeeded: Int, failed: Int, skipped: Int) -> String {
        var parts: [String] = []
        if succeeded > 0 {
            parts.append("Deleted audio for \(succeeded) \(succeeded == 1 ? "meeting" : "meetings").")
        }
        if failed > 0 {
            parts.append(
                failed == 1
                    ? "1 meeting audio file could not be deleted."
                    : "\(failed) meeting audio files could not be deleted.")
        }
        if skipped > 0 {
            parts.append(skipped == 1 ? "1 selected item was skipped." : "\(skipped) selected items were skipped.")
        }
        return parts.joined(separator: " ")
    }
}

private struct BatchTargetResult: Sendable {
    let succeededIDs: [UUID]
    let failedIDs: [UUID]
}

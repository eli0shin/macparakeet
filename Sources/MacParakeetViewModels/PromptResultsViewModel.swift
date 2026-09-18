import Foundation
import MacParakeetCore
import OSLog

/// Presentation state for one open transcript. Saved results come from a scoped
/// repository observation; background processing never writes this state.
@MainActor
@Observable
public final class PromptResultsViewModel {
    public typealias PendingGeneration = PromptGenerationQueue.PendingGeneration

    public private(set) var promptResults: [PromptResult] = []
    public private(set) var currentTranscriptionID: UUID?
    public private(set) var isLoadingResults = false
    public var selectedPrompt: Prompt?
    public var extraInstructions = ""
    public var errorMessage: String?
    public var visiblePrompts: [Prompt] = []
    public var pendingDeletePromptResult: PromptResult?
    public var currentModelName = ""
    public var currentProviderID: LLMProviderID?
    public var availableModels: [String] = []
    public private(set) var unreadPromptResultIDs: Set<UUID> = []
    public var onModelChanged: (() -> Void)?

    private let generationQueue: PromptGenerationQueue
    private var promptRepo: PromptRepositoryProtocol?
    private var promptResultRepo: PromptResultRepositoryProtocol?
    private var transcriptionRepo: TranscriptionRepositoryProtocol?
    private var meetingArtifactStore: MeetingArtifactStoring?
    private var configStore: LLMConfigStoreProtocol?
    private var cliConfigStore: LocalCLIConfigStore?
    private var llmClient: LLMClientProtocol?
    @ObservationIgnored private var modelListTask: Task<Void, Never>?
    @ObservationIgnored private var persistedContentLoadTask: Task<Void, Never>?
    @ObservationIgnored private var resultsObservationTask: Task<Void, Never>?
    private var observationID = UUID()
    private let logger = Logger(subsystem: "com.macparakeet.viewmodels", category: "PromptResultsViewModel")

    public init(generationQueue: PromptGenerationQueue) {
        self.generationQueue = generationQueue
    }

    deinit {
        resultsObservationTask?.cancel()
        persistedContentLoadTask?.cancel()
        modelListTask?.cancel()
    }

    public var canGeneratePromptResult: Bool { generationQueue.canGenerate }
    public var canGenerateManualPromptResult: Bool { canGeneratePromptResult && selectedPrompt != nil }
    public var hasPromptResultGenerationCapability: Bool { canGeneratePromptResult }
    public var canSelectModel: Bool { !generationQueue.hasActiveGenerations }
    public var pendingGenerations: [PendingGeneration] {
        generationQueue.pendingGenerations.filter { $0.transcriptionId == currentTranscriptionID }
    }
    public var hasPendingGenerations: Bool { !pendingGenerations.isEmpty }
    public var hasActiveGenerations: Bool { pendingGenerations.contains { $0.state.isActive } }
    public var isStreaming: Bool { activeStreamingGeneration != nil }
    public var queuedGenerationCount: Int { pendingGenerations.filter { $0.state == .queued }.count }
    public var streamingContent: String { activeStreamingGeneration?.content ?? "" }
    public var streamingPromptResultID: UUID? { activeStreamingGeneration?.id }
    public var streamingPromptName: String { activeStreamingGeneration?.promptName ?? "" }
    private var activeStreamingGeneration: PendingGeneration? {
        pendingGenerations.first { $0.state == .streaming }
    }

    public var modelDisplayName: String {
        guard !currentModelName.isEmpty else { return "" }
        if currentProviderID == .openrouter, let slashIndex = currentModelName.firstIndex(of: "/") {
            return String(currentModelName[currentModelName.index(after: slashIndex)...])
        }
        return currentModelName
    }

    public func configure(
        promptRepo: PromptRepositoryProtocol?,
        promptResultRepo: PromptResultRepositoryProtocol?,
        transcriptionRepo: TranscriptionRepositoryProtocol? = nil,
        meetingArtifactStore: MeetingArtifactStoring? = nil,
        configStore: LLMConfigStoreProtocol? = nil,
        llmClient: LLMClientProtocol? = nil,
        cliConfigStore: LocalCLIConfigStore = LocalCLIConfigStore()
    ) {
        self.promptRepo = promptRepo
        self.promptResultRepo = promptResultRepo
        self.transcriptionRepo = transcriptionRepo
        self.meetingArtifactStore = meetingArtifactStore
        self.configStore = configStore
        self.llmClient = llmClient
        self.cliConfigStore = cliConfigStore
        loadVisiblePrompts()
        refreshModelInfo()
    }

    public func refreshModelInfo() {
        modelListTask?.cancel()
        guard let configStore, let config = try? configStore.loadConfig() else {
            currentModelName = ""
            currentProviderID = nil
            availableModels = []
            return
        }
        currentProviderID = config.id
        if config.id == .localCLI {
            let displayName =
                cliConfigStore
                .flatMap { $0.load() }
                .map { LocalCLITemplate.displayName(for: $0.commandTemplate) }
                ?? "Custom CLI"
            currentModelName = displayName
            availableModels = [displayName]
            return
        }

        currentModelName = config.modelName
        availableModels = LLMModelAvailability.pickerModels(for: config, discoveredModels: [])
        refreshAvailableModels(for: config)
    }

    public func selectModel(_ modelName: String) {
        guard let configStore, currentProviderID != .localCLI, canSelectModel else { return }
        do {
            try configStore.updateModelName(modelName)
            currentModelName = modelName
            onModelChanged?()
        } catch {
            refreshModelInfo()
        }
    }

    private func refreshAvailableModels(for config: LLMProviderConfig) {
        modelListTask = LLMModelAvailability.refreshPickerModelsTask(
            for: config,
            llmClient: llmClient,
            configStore: configStore
        ) { [weak self] models in
            self?.availableModels = models
        }
    }

    public func loadVisiblePrompts() {
        guard let promptRepo else { return }
        do {
            visiblePrompts = try promptRepo.fetchVisible(category: .result)
            if let selectedPrompt,
                let refreshed = visiblePrompts.first(where: { $0.id == selectedPrompt.id })
            {
                self.selectedPrompt = refreshed
            } else {
                self.selectedPrompt =
                    visiblePrompts.first(where: { $0.isAutoRun })
                    ?? visiblePrompts.first
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            visiblePrompts = []
            selectedPrompt = nil
        }
    }

    /// Synchronous initial read for callers that need an immediate snapshot.
    /// Subsequent changes use the same observation as the asynchronous view load.
    public func loadPromptResults(transcriptionId: UUID) {
        beginObservation(transcriptionId: transcriptionId, readInitialSnapshot: true)
    }

    public func loadPersistedContentAsync(transcriptionId: UUID) {
        beginObservation(transcriptionId: transcriptionId, readInitialSnapshot: false)
        persistedContentLoadTask?.cancel()
        let promptRepo = promptRepo
        let id = observationID
        persistedContentLoadTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                try promptRepo?.fetchVisible(category: .result) ?? []
            }.result
            guard let self, !Task.isCancelled, self.observationID == id else { return }
            switch result {
            case .success(let prompts):
                self.visiblePrompts = prompts
                if let selected = self.selectedPrompt,
                    let refreshed = prompts.first(where: { $0.id == selected.id })
                {
                    self.selectedPrompt = refreshed
                } else {
                    self.selectedPrompt = prompts.first(where: { $0.isAutoRun }) ?? prompts.first
                }
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func beginObservation(transcriptionId: UUID, readInitialSnapshot: Bool) {
        resultsObservationTask?.cancel()
        persistedContentLoadTask?.cancel()
        observationID = UUID()
        let id = observationID
        let changedTranscript = currentTranscriptionID != transcriptionId
        currentTranscriptionID = transcriptionId
        pendingDeletePromptResult = nil
        errorMessage = nil
        if changedTranscript {
            promptResults = []
            unreadPromptResultIDs = []
            extraInstructions = ""
        }
        isLoadingResults = changedTranscript
        guard let promptResultRepo else {
            isLoadingResults = false
            return
        }
        var needsBaseline = changedTranscript
        if readInitialSnapshot {
            do {
                applyResults(try promptResultRepo.fetchAll(transcriptionId: transcriptionId), baseline: needsBaseline)
                needsBaseline = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        let baseline = needsBaseline
        resultsObservationTask = Task { @MainActor [weak self] in
            var needsBaseline = baseline
            do {
                for try await results in promptResultRepo.observe(transcriptionId: transcriptionId) {
                    guard !Task.isCancelled, let self, self.observationID == id else { return }
                    self.applyResults(results, baseline: needsBaseline)
                    needsBaseline = false
                }
            } catch {
                guard !Task.isCancelled, let self, self.observationID == id else { return }
                self.isLoadingResults = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func applyResults(_ results: [PromptResult], baseline: Bool) {
        let scoped = results.filter { $0.transcriptionId == currentTranscriptionID }
        let ids = Set(scoped.map(\.id))
        if !baseline {
            unreadPromptResultIDs.formUnion(ids.subtracting(promptResults.map(\.id)))
        }
        unreadPromptResultIDs.formIntersection(ids)
        promptResults = scoped
        isLoadingResults = false
    }

    /// Reconcile presentation after a result snapshot or job state changes.
    /// The database observation can arrive after the queue drops a completed job.
    /// Read the saved snapshot in that case instead of treating completion as cancellation.
    public func reconciledTab(_ tab: TranscriptionViewModel.TranscriptTab) -> TranscriptionViewModel.TranscriptTab {
        var result = tab
        switch tab {
        case .generation(let id):
            if !promptResults.contains(where: { $0.id == id }),
                pendingGeneration(id: id) == nil, let currentTranscriptionID
            {
                // Restart observation so an older buffered snapshot cannot replace
                // the committed snapshot used to resolve this tab.
                loadPromptResults(transcriptionId: currentTranscriptionID)
                if errorMessage != nil { return tab }
            }
            if promptResults.contains(where: { $0.id == id }) {
                result = .result(id: id)
            } else if pendingGeneration(id: id) == nil {
                result = .transcript
            }
        case .result(let id):
            if !isLoadingResults && !promptResults.contains(where: { $0.id == id }) {
                result = .transcript
            }
        case .transcript, .chat:
            break
        }
        if case .result(let id) = result { markPromptResultViewed(id) }
        return result
    }

    public func markPromptResultViewed(_ id: UUID) { unreadPromptResultIDs.remove(id) }
    public func hasUnreadPromptResult(_ id: UUID) -> Bool { unreadPromptResultIDs.contains(id) }
    public func pendingGeneration(id: UUID) -> PendingGeneration? {
        pendingGenerations.first { $0.id == id }
    }
    public func pendingGenerations(for transcriptionId: UUID) -> [PendingGeneration] {
        pendingGenerations.filter { $0.transcriptionId == transcriptionId }
    }
    public func hasPendingGeneration(promptName: String, transcriptionId: UUID) -> Bool {
        pendingGenerations.contains {
            $0.transcriptionId == transcriptionId && $0.promptName == promptName && $0.state.isActive
        }
    }

    @discardableResult
    public func generatePromptResult(transcript: String, transcriptionId: UUID) -> UUID? {
        guard currentTranscriptionID == transcriptionId, let selectedPrompt else { return nil }
        let instructions = extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return generationQueue.generatePromptResult(
            transcript: transcript, transcriptionId: transcriptionId, prompt: selectedPrompt,
            extraInstructions: instructions.isEmpty ? nil : instructions
        )
    }

    @discardableResult
    public func regeneratePromptResult(_ result: PromptResult, transcript: String) -> UUID? {
        guard result.transcriptionId == currentTranscriptionID else { return nil }
        return generationQueue.regeneratePromptResult(result, transcript: transcript)
    }

    public func cancelStreaming() {
        if let id = streamingPromptResultID { cancelGeneration(id: id) }
    }

    public func cancelGeneration(id: UUID) {
        guard pendingGeneration(id: id) != nil else { return }
        generationQueue.cancelGeneration(id: id)
    }

    @discardableResult
    public func retryGeneration(id: UUID) -> UUID? {
        guard pendingGeneration(id: id) != nil else { return nil }
        return generationQueue.retryGeneration(id: id)
    }

    public func confirmDelete() {
        guard let promptResult = pendingDeletePromptResult else { return }
        pendingDeletePromptResult = nil
        deletePromptResult(promptResult)
    }

    public func deletePromptResult(_ promptResult: PromptResult) {
        guard promptResult.transcriptionId == currentTranscriptionID, let promptResultRepo else { return }
        do {
            _ = try promptResultRepo.delete(id: promptResult.id)
            let transcriptionID = promptResult.transcriptionId
            Task { [weak self] in
                await self?.refreshMeetingArtifacts(transcriptionId: transcriptionID)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Refreshes meeting artifacts; failures are logged and never surfaced or thrown, and refresh never blocks or fails the triggering user action.
    private func refreshMeetingArtifacts(transcriptionId: UUID) async {
        guard let meetingArtifactStore,
            let transcriptionRepo,
            let promptResultRepo
        else { return }

        do {
            guard let transcription = try transcriptionRepo.fetch(id: transcriptionId),
                transcription.sourceType == .meeting
            else { return }
            let promptResults = try promptResultRepo.fetchAll(transcriptionId: transcriptionId)
            _ = try await Task.detached(priority: .utility) {
                try await meetingArtifactStore.materialize(
                    transcription: transcription,
                    promptResults: promptResults
                )
            }.value
        } catch {
            logger.warning(
                "Failed to refresh meeting artifact for prompt results \(transcriptionId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

}

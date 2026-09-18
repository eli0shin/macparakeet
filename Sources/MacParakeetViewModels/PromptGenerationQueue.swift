import Foundation
import MacParakeetCore
import OSLog

/// Application-owned AI work. Jobs and saved results always carry their transcript ID.
/// This module has no selected transcript, tabs, unread state, or view lifecycle.
@MainActor
@Observable
public final class PromptGenerationQueue {
    public struct PendingGeneration: Identifiable, Equatable, Sendable {
        public enum State: Equatable, Sendable {
            case queued
            case streaming
            /// Terminal: the generation errored. The entry stays in
            /// `pendingGenerations` so its tab can show the error with
            /// Retry/Dismiss — removing it on failure made errors look
            /// like a silent revert to the Transcript tab (#478).
            case failed(message: String)

            public var isActive: Bool {
                switch self {
                case .queued, .streaming: return true
                case .failed: return false
                }
            }
        }

        public var id: UUID
        public var transcriptionId: UUID
        public var promptName: String
        public var promptContent: String
        public var extraInstructions: String?
        public var transcript: String
        /// Snapshot of `Transcription.userNotes` captured at enqueue time. Used
        /// both to substitute `{{userNotes}}` in the prompt template and to
        /// snapshot onto the resulting `PromptResult` (ADR-020 §4, §6).
        public var userNotes: String?
        public var replacingPromptResultID: UUID?
        public var state: State
        public var content: String

        public init(
            id: UUID = UUID(),
            transcriptionId: UUID,
            promptName: String,
            promptContent: String,
            extraInstructions: String?,
            transcript: String,
            userNotes: String? = nil,
            replacingPromptResultID: UUID? = nil,
            state: State = .queued,
            content: String = ""
        ) {
            self.id = id
            self.transcriptionId = transcriptionId
            self.promptName = promptName
            self.promptContent = promptContent
            self.extraInstructions = extraInstructions
            self.transcript = transcript
            self.userNotes = userNotes
            self.replacingPromptResultID = replacingPromptResultID
            self.state = state
            self.content = content
        }
    }

    public private(set) var pendingGenerations: [PendingGeneration] = []
    public var canGenerate: Bool { llmService != nil }
    public var hasActiveGenerations: Bool { pendingGenerations.contains { $0.state.isActive } }

    private var llmService: LLMServiceProtocol?
    private var cardGenerator: CardGenerating?
    private var promptRepo: PromptRepositoryProtocol?
    private var promptResultRepo: PromptResultRepositoryProtocol?
    private var transcriptionRepo: TranscriptionRepositoryProtocol?
    private var meetingArtifactStore: MeetingArtifactStoring?
    private var offlineProcessingViewModel: OfflineProcessingViewModel?
    private var streamingTask: Task<Void, Never>?
    private var activeGenerationID: UUID?
    private let logger = Logger(subsystem: "com.macparakeet.viewmodels", category: "PromptGenerationQueue")

    public init() {}

    public func configure(
        llmService: LLMServiceProtocol?,
        promptRepo: PromptRepositoryProtocol?,
        promptResultRepo: PromptResultRepositoryProtocol?,
        transcriptionRepo: TranscriptionRepositoryProtocol? = nil,
        meetingArtifactStore: MeetingArtifactStoring? = nil,
        cardGenerator: CardGenerating? = nil,
        offlineProcessingViewModel: OfflineProcessingViewModel? = nil
    ) {
        self.llmService = llmService
        self.promptRepo = promptRepo
        self.promptResultRepo = promptResultRepo
        self.transcriptionRepo = transcriptionRepo
        self.meetingArtifactStore = meetingArtifactStore
        self.cardGenerator = cardGenerator
        self.offlineProcessingViewModel = offlineProcessingViewModel
    }

    /// Changing the provider is an explicit processing action, not navigation.
    public func updateLLMService(_ service: LLMServiceProtocol?, cardGenerator: CardGenerating? = nil) {
        cancelAllGenerations()
        llmService = service
        self.cardGenerator = cardGenerator
    }

    public func pendingGeneration(id: UUID) -> PendingGeneration? {
        pendingGenerations.first { $0.id == id }
    }

    @discardableResult
    public func generatePromptResult(
        transcript: String, transcriptionId: UUID, prompt: Prompt, extraInstructions: String? = nil
    ) -> UUID? {
        enqueueGeneration(
            transcript: transcript, transcriptionId: transcriptionId, prompt: prompt,
            extraInstructions: extraInstructions, userNotes: fetchUserNotes(for: transcriptionId)
        )
    }

    @discardableResult
    public func regeneratePromptResult(_ promptResult: PromptResult, transcript: String) -> UUID? {
        let prompt = Prompt(
            name: promptResult.promptName,
            content: promptResult.promptContent,
            isBuiltIn: false,
            sortOrder: 0
        )
        // Regeneration re-snapshots from the *current* notes on the row — if
        // the user edited notes between summary generations they expect the
        // new summary to reflect the new notes. The original summary's
        // snapshot remains untouched on its row (ADR-020 §6).
        return enqueueGeneration(
            transcript: transcript,
            transcriptionId: promptResult.transcriptionId,
            prompt: prompt,
            extraInstructions: promptResult.extraInstructions,
            userNotes: fetchUserNotes(for: promptResult.transcriptionId),
            replacingPromptResultID: promptResult.id
        )
    }

    @discardableResult
    public func autoGeneratePromptResults(
        transcript: String,
        transcriptionId: UUID,
        sourceType: Transcription.SourceType
    ) -> [UUID] {
        guard transcript.contains(where: { !$0.isWhitespace }) else { return [] }

        generateKnowledgeCard(transcriptionId: transcriptionId)

        let autoPrompts: [Prompt]
        do {
            autoPrompts = try promptRepo?.fetchAutoRunPrompts(for: sourceType) ?? []
        } catch {
            logger.warning(
                "Skipping auto-run prompts because preferences could not be loaded: \(error.localizedDescription, privacy: .private)"
            )
            return []
        }
        guard !autoPrompts.isEmpty else { return [] }

        let userNotes = fetchUserNotes(for: transcriptionId)
        var queuedIDs: [UUID] = []
        for prompt in autoPrompts {
            if let id = enqueueGeneration(
                transcript: transcript,
                transcriptionId: transcriptionId,
                prompt: prompt,
                extraInstructions: nil,
                userNotes: userNotes
            ) {
                queuedIDs.append(id)
            }
        }
        return queuedIDs
    }

    public func generateKnowledgeCard(transcriptionId: UUID) {
        guard let cardGenerator else { return }
        let operationID = UUID()
        let itemTitle: String
        do {
            itemTitle =
                try transcriptionRepo?.fetch(id: transcriptionId)?.effectiveDisplayTitle
                ?? "Transcript"
        } catch {
            itemTitle = "Transcript"
        }
        offlineProcessingViewModel?.start(
            OfflineProcessingViewModel.Job(
                id: operationID,
                itemID: transcriptionId,
                title: itemTitle,
                operation: .generatingResult(name: "knowledge card")
            )
        )

        let logger = logger
        let processing = offlineProcessingViewModel
        Task(priority: .utility) {
            defer { processing?.finish(id: operationID) }
            do {
                _ = try await cardGenerator.generate(
                    transcriptionId: transcriptionId,
                    force: false
                )
            } catch {
                logger.warning(
                    "Knowledge card generation failed: \(error.localizedDescription, privacy: .private)"
                )
                processing?.reportIssue(
                    OfflineProcessingViewModel.Issue(
                        id: operationID,
                        itemID: transcriptionId,
                        title: "Knowledge card could not be generated",
                        detail: error.localizedDescription
                    )
                )
            }
        }
    }

    public func cancelGeneration(id: UUID) {
        guard let index = pendingGenerations.firstIndex(where: { $0.id == id }) else { return }
        if pendingGenerations[index].state == .streaming {
            streamingTask?.cancel()
            return
        }
        let generationID = pendingGenerations[index].id
        pendingGenerations.remove(at: index)
        offlineProcessingViewModel?.finish(id: generationID)
    }

    private func cancelAllGenerations() {
        streamingTask?.cancel()
        streamingTask = nil
        activeGenerationID = nil
        for generation in pendingGenerations {
            offlineProcessingViewModel?.finish(id: generation.id)
        }
        pendingGenerations = []
    }

    @discardableResult
    private func enqueueGeneration(
        transcript: String,
        transcriptionId: UUID,
        prompt: Prompt,
        extraInstructions: String?,
        userNotes: String? = nil,
        replacingPromptResultID: UUID? = nil
    ) -> UUID? {
        guard llmService != nil else { return nil }

        let generation = PendingGeneration(
            transcriptionId: transcriptionId,
            promptName: prompt.name,
            promptContent: prompt.content,
            extraInstructions: extraInstructions,
            transcript: transcript,
            userNotes: userNotes,
            replacingPromptResultID: replacingPromptResultID
        )
        pendingGenerations.append(generation)
        let itemTitle: String
        do {
            itemTitle =
                try transcriptionRepo?.fetch(id: transcriptionId)?.effectiveDisplayTitle
                ?? prompt.name
        } catch {
            itemTitle = prompt.name
        }
        offlineProcessingViewModel?.start(
            OfflineProcessingViewModel.Job(
                id: generation.id,
                itemID: transcriptionId,
                title: itemTitle,
                operation: .waiting(detail: "Queued behind other AI processing"),
                canCancel: true
            ),
            onCancel: { [weak self] in self?.cancelGeneration(id: generation.id) }
        )
        processNextQueuedGeneration()
        return generation.id
    }

    private func processNextQueuedGeneration() {
        guard streamingTask == nil, llmService != nil else { return }
        guard let nextIndex = pendingGenerations.firstIndex(where: { $0.state == .queued })
        else { return }

        pendingGenerations[nextIndex].state = .streaming
        let generation = pendingGenerations[nextIndex]
        offlineProcessingViewModel?.update(
            id: generation.id,
            operation: .generatingResult(name: generation.promptName),
            fraction: nil
        )
        let generationID = generation.id
        activeGenerationID = generationID
        let systemPrompt = assembledSystemPrompt(
            promptContent: generation.promptContent,
            extraInstructions: generation.extraInstructions,
            userNotes: generation.userNotes,
            transcript: generation.transcript
        )

        streamingTask = Task { @MainActor [weak self] in
            guard let self, self.activeGenerationID == generationID else { return }
            guard !Task.isCancelled, let llmService = self.llmService else {
                finishCancelledGeneration(id: generationID)
                return
            }
            do {
                let stream = llmService.generatePromptResultStream(
                    transcript: generation.transcript,
                    systemPrompt: systemPrompt
                )
                for try await token in stream {
                    appendStreamingToken(token, to: generationID)
                }
                guard !Task.isCancelled else {
                    finishCancelledGeneration(id: generationID)
                    return
                }
                try await finishGeneration(id: generationID)
            } catch is CancellationError {
                finishCancelledGeneration(id: generationID)
            } catch {
                if Task.isCancelled {
                    finishCancelledGeneration(id: generationID)
                } else {
                    finishFailedGeneration(id: generationID, error: error)
                }
            }
        }
    }

    private func appendStreamingToken(_ token: String, to generationID: UUID) {
        guard let index = pendingGenerations.firstIndex(where: { $0.id == generationID }) else { return }
        pendingGenerations[index].content += token
    }

    private func finishGeneration(id generationID: UUID) async throws {
        guard activeGenerationID == generationID,
            let index = pendingGenerations.firstIndex(where: { $0.id == generationID })
        else { return }

        let generation = pendingGenerations[index]
        guard generation.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw LLMError.streamingError("prompt result returned an empty response")
        }
        let timestamp = Date()
        let promptResult = PromptResult(
            id: generation.id,
            transcriptionId: generation.transcriptionId,
            promptName: generation.promptName,
            promptContent: generation.promptContent,
            extraInstructions: generation.extraInstructions,
            content: generation.content,
            userNotesSnapshot: generation.userNotes,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        if let replacingPromptResultID = generation.replacingPromptResultID {
            try promptResultRepo?.replace(promptResult, deletingExistingID: replacingPromptResultID)
        } else {
            try promptResultRepo?.save(promptResult)
        }

        pendingGenerations.remove(at: index)
        offlineProcessingViewModel?.finish(id: generationID)
        // Keep the worker slot until artifact materialization finishes. A new job must
        // not race an older artifact write or let its completion clear a newer task.
        await refreshMeetingArtifacts(transcriptionId: generation.transcriptionId)
        finishWorker(id: generationID)
    }

    private func finishWorker(id: UUID) {
        guard activeGenerationID == id else { return }
        activeGenerationID = nil
        streamingTask = nil
        processNextQueuedGeneration()
    }

    private func finishCancelledGeneration(id generationID: UUID) {
        guard activeGenerationID == generationID else { return }
        if let index = pendingGenerations.firstIndex(where: { $0.id == generationID }) {
            pendingGenerations.remove(at: index)
        }
        offlineProcessingViewModel?.finish(id: generationID)
        finishWorker(id: generationID)
    }

    private func finishFailedGeneration(id generationID: UUID, error: Error) {
        logger.error("Failed to generate prompt result error=\(error.localizedDescription, privacy: .public)")
        guard activeGenerationID == generationID,
            let index = pendingGenerations.firstIndex(where: { $0.id == generationID })
        else { return }
        pendingGenerations[index].state = .failed(message: error.localizedDescription)
        let generation = pendingGenerations[index]
        offlineProcessingViewModel?.finish(id: generationID)
        offlineProcessingViewModel?.reportIssue(
            OfflineProcessingViewModel.Issue(
                id: generationID,
                itemID: generation.transcriptionId,
                title: "\(generation.promptName) could not be generated",
                detail: error.localizedDescription,
                recoveryTitle: "Retry"
            ),
            onRecover: { [weak self] in
                self?.offlineProcessingViewModel?.dismiss(issueID: generationID)
                _ = self?.retryGeneration(id: generationID)
            }
        )
        finishWorker(id: generationID)
    }

    /// Re-enqueue a failed generation with the same inputs it was originally
    /// captured with (transcript, notes snapshot, replace target). Returns
    /// the new generation's ID so the caller can keep its tab selected.
    @discardableResult
    public func retryGeneration(id: UUID) -> UUID? {
        // llmService gates enqueueGeneration; checking it before removal
        // keeps the failed card (and its error) when retry can't start.
        guard llmService != nil,
            let index = pendingGenerations.firstIndex(where: { $0.id == id }),
            case .failed = pendingGenerations[index].state
        else { return nil }
        let failed = pendingGenerations.remove(at: index)
        return enqueueGeneration(
            transcript: failed.transcript,
            transcriptionId: failed.transcriptionId,
            prompt: Prompt(
                name: failed.promptName,
                content: failed.promptContent,
                isBuiltIn: false,
                sortOrder: 0
            ),
            extraInstructions: failed.extraInstructions,
            userNotes: failed.userNotes,
            replacingPromptResultID: failed.replacingPromptResultID
        )
    }

    private func assembledSystemPrompt(
        promptContent: String,
        extraInstructions: String?,
        userNotes: String? = nil,
        transcript: String? = nil
    ) -> String {
        PromptSystemPromptAssembler.assemble(
            promptContent: promptContent,
            extraInstructions: extraInstructions,
            userNotes: userNotes,
            transcript: transcript
        )
    }

    private func fetchUserNotes(for transcriptionId: UUID) -> String? {
        guard let transcriptionRepo else { return nil }
        do {
            return try transcriptionRepo.fetch(id: transcriptionId)?.userNotes
        } catch {
            logger.warning(
                "Failed to fetch userNotes for transcription \(transcriptionId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Artifact refresh is part of the worker lifetime, but a refresh failure does
    /// not fail a saved result or prevent later jobs from running.
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

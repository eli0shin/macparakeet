import AVKit
import SwiftUI
import MacParakeetCore
import MacParakeetViewModels

/// Keeps legacy segment and speaker-card playback following below the transcript
/// detail observation boundary. Completed-meeting Reading Turns use their own
/// indexed playback boundary.
private struct NonMeetingTranscriptPlaybackObserver: View {
    @Bindable var playerViewModel: MediaPlayerViewModel
    let evaluationProbe: (() -> Void)?
    let onTick: (Int, Int) -> Void

    var body: some View {
        EmptyView()
            .onChange(of: playerViewModel.currentTimeMs) { oldValue, newValue in
                evaluationProbe?()
                onTick(oldValue, newValue)
            }
    }
}

/// Data-driven model for the export confirmation popover.
/// Using a single `Identifiable` value with `.popover(item:)` ensures
/// the popover content always has the correct URL and format — no race
/// between separate presentation and data states.
private struct ExportConfirmation: Identifiable {
    let id = UUID()
    let url: URL
    /// Full heading shown in the confirmation popover, e.g.
    /// "Exported Markdown" or "Saved Audio". The popover renders this
    /// verbatim so callers control the verb-noun phrasing.
    let title: String
}

private enum TranscriptDisplayMode: String, CaseIterable, Hashable {
    case text = "Text"
    case timed = "Timed"
}

private enum SpeakerCountEditorMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case exact = "Exact"
    case bounded = "Range"
    var id: String { rawValue }
}

func shouldDefaultToMeetingReadingSurface(
    isCompletedMeeting: Bool,
    isTranscriptEdited: Bool,
    hasReadingTurns: Bool
) -> Bool {
    isCompletedMeeting && !isTranscriptEdited && hasReadingTurns
}

func performRetranscriptionSelection(
    transcription: Transcription,
    selection: SpeechEngineSelection,
    isPrimary: Bool,
    primaryReflectsTranscriptEngine: Bool,
    onRetranscribe: ((Transcription, SpeechEngineSelection?) -> Void)?
) {
    let override = isPrimary && !primaryReflectsTranscriptEngine ? nil : selection
    onRetranscribe?(transcription, override)
}

struct MeetingTimedTranscriptRecoveryBannerPresentation: Equatable {
    struct Action: Equatable {
        let title: String
        let selection: SpeechEngineSelection
    }

    let title: String
    let message: String
    let action: Action?

    static func make(
        transcriptText: String,
        hasTranscriptText: Bool? = nil,
        hasRetainedAudio: Bool,
        timestampCapableRerun: SpeechEngineSelection?
    ) -> MeetingTimedTranscriptRecoveryBannerPresentation? {
        guard hasTranscriptText ?? !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let baseMessage = "This meeting has transcript text but no word timestamps, so timed playback, segments, and speaker labels are unavailable."
        if let timestampCapableRerun {
            return MeetingTimedTranscriptRecoveryBannerPresentation(
                title: "No timed transcript",
                message: "\(baseMessage) Rerun with \(timestampCapableRerun.engine.displayName) to try adding timestamps. Speaker labels depend on the captured audio and may be approximate.",
                action: Action(
                    title: "Try timed retranscription",
                    selection: timestampCapableRerun
                )
            )
        }

        if hasRetainedAudio {
            return MeetingTimedTranscriptRecoveryBannerPresentation(
                title: "No timed transcript",
                message: "\(baseMessage) A timestamp-capable engine would be needed to try adding timestamps, but none is available right now.",
                action: nil
            )
        }

        return MeetingTimedTranscriptRecoveryBannerPresentation(
            title: "No timed transcript",
            message: "\(baseMessage) Saved audio is no longer available, so MacParakeet cannot rerun the meeting to try adding timestamps.",
            action: nil
        )
    }
}

struct MeetingTranscriptProcessingPresentation: Equatable {
    let title: String
    let message: String

    static func make(
        sourceType: Transcription.SourceType,
        status: Transcription.TranscriptionStatus
    ) -> MeetingTranscriptProcessingPresentation? {
        guard sourceType == .meeting,
            status == .processing
        else {
            return nil
        }
        return MeetingTranscriptProcessingPresentation(
            title: "Transcribing meeting",
            message:
                "Your audio is saved. Final transcription is continuing in the background. You can leave this page and return later."
        )
    }
}

enum TranscriptDetailActionAvailability {
    static func canEdit(
        status: Transcription.TranscriptionStatus
    ) -> Bool {
        status != .processing
    }

    static func canRetranscribe(
        hasRetainedAudio: Bool,
        status: Transcription.TranscriptionStatus
    ) -> Bool {
        hasRetainedAudio && status != .processing
    }
}

struct TranscriptResultView: View {
    let transcription: Transcription
    @Bindable var viewModel: TranscriptionViewModel
    var chatViewModel: TranscriptChatViewModel
    @Bindable var promptResultsViewModel: PromptResultsViewModel
    @Bindable var promptsViewModel: PromptsViewModel
    let customWords: [CustomWord]
    var onBack: (() -> Void)?
    var onStartNew: (() -> Void)?
    var onRetranscribe: ((Transcription, SpeechEngineSelection?) -> Void)?
    var onSetUpAI: (() -> Void)?
    var playbackViewModelProbe: ((MediaPlayerViewModel) -> Void)? = nil
    var detailEvaluationProbe: (() -> Void)? = nil
    var headerEvaluationProbe: (() -> Void)? = nil
    var moduleEvaluationProbe: ((TranscriptDetailPresentationModule) -> Void)? = nil
    var hostedPresentationModule: TranscriptDetailPresentationModule? = nil
    var findSessionDriverProbe: ((TranscriptFindSessionDriver) -> Void)? = nil
    var findSessionStateProbe: ((String, Bool, Int) -> Void)? = nil

    @AppStorage(UserDefaultsAppRuntimePreferences.transcriptAIContextModeKey)
    private var transcriptAIContextModeRaw = TranscriptAIContextMode.richTranscript.rawValue

    @State private var backHovered = false
    @State private var headerExpanded = false
    @State private var speakerOverviewExpanded = true
    @State private var copied = false
    @State private var copiedResultID: UUID?
    @State private var copiedButtonResultID: UUID?
    @State private var copiedMessageId: UUID?
    @State private var hoveredMessageId: UUID?
    @State private var exportConfirmation: ExportConfirmation?
    @State private var exportErrorMessage: String?
    @State private var showingExportOptions = false
    @State private var selectedExportFormat: TranscriptExportFormat = .txt
    @State private var transcriptExportOptions = TranscriptExportOptions.default
    @State private var copiedResetTask: Task<Void, Never>?
    @State private var resultCopiedResetTask: Task<Void, Never>?
    @State private var resultButtonCopiedResetTask: Task<Void, Never>?
    @State private var notesCopied = false
    @State private var notesCopiedResetTask: Task<Void, Never>?
    @State private var dismissTask: Task<Void, Never>?
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var editingTranscript = false
    @State private var transcriptDraft = ""
    @State private var transcriptEditError: String?
    @State private var transcriptDisplayMode: TranscriptDisplayMode = .text
    @State private var transcriptDisplayModeBeforeEdit: TranscriptDisplayMode?
    /// User-adjustable transcript reading size (Transcript Detail Refresh / U4).
    /// Persisted; applies to both the Text and Timed reading surfaces.
    @AppStorage(UserDefaultsAppRuntimePreferences.transcriptFontScaleKey)
    private var transcriptFontScale: Double = 1.0
    private static let transcriptFontScaleRange: ClosedRange<Double> = 0.85...1.4
    private static let transcriptFontScaleStep: Double = 0.1
    private static let textSurfaceScrollTargetID = Int.min
    // In-transcript find (Transcript Detail Refresh / U2). The matcher is the
    // testable `TranscriptFindModel`; this view owns the bar's visibility, the
    // ordered blocks fed to the model, and the scroll wiring.
    @State private var findModel = TranscriptFindModel()
    @State private var findBarVisible = false
    @State private var findBlocks: [TranscriptFindBlock] = []
    /// Bumped on every keystroke / navigation so the in-reader `onChange` can
    /// re-aim `scrollTo` at the current match (even when the cursor index is
    /// unchanged but the matched block moved).
    @State private var findScrollToken = 0
    /// True once find-navigation has taken over the auto-scroll pause, so closing
    /// the bar resumes playback-follow — without clobbering an unrelated
    /// manual-scroll pause when find never navigated.
    @State private var findPausedAutoScroll = false
    @State private var editingSpeakerId: String?
    @State private var editingSpeakerContextID: String?
    @State private var editingSpeakerLabel: String = ""
    @State private var showConversationPopover = false
    @State private var hoveredConversationId: UUID?
    @State private var playerViewModel = MediaPlayerViewModel()
    @State private var showVideoPanel = false
    @State private var lastScrolledSegmentMs: Int = -1
    // Cached transcript data — recomputed only when transcription.id changes, not on every playback tick
    @State private var cachedSegments: [TranscriptSegment] = []
    @State private var cachedIdentifiedTurnCards: [IdentifiedSpeakerTurn] = []
    /// Canonical Reading Turns remain the source for exports and AI context.
    @State private var cachedReadingDocument = MeetingTranscriptPresentationDocument(turns: [])
    /// The completed-meeting UI groups consecutive contributions by speaker.
    @State private var cachedReadingTurns: [IdentifiedReadingTurn] = []
    @State private var cachedReadingTurnPlaybackIndex: ReadingTurnPlaybackIndex?
    @State private var readingTurnContentRevision = 0
    @State private var cachedTranscriptionID: UUID?
    @State private var cachedPreferredText = ""
    @State private var cachedTextWordCount = 0
    @State private var cachedTimedWordCount = 0
    @State private var cachedHasPreferredText = false
    @State private var cachedHasCleanTranscriptText = false
    @State private var cachedHasSpeakers: Bool = false
    @State private var cachedSpeakerStatistics: [String: SpeakerStatistics] = [:]
    @State private var cachedSpeakerColorMap: [String: Color] = [:]
    @State private var cachedSpeakerLabelMap: [String: String] = [:]
    @State private var cachedReadingFindBlocks: [TranscriptFindBlock] = []
    @State private var cachedSegmentFindBlocks: [TranscriptFindBlock] = []
    @State private var cachedTextFindBlocks: [TranscriptFindBlock] = []
    @State private var cachedMandalaData = MandalaData.fallback
    @State private var detailPreparationTask: Task<Void, Never>?
    @State private var cachedSegmentStartMs: [Int] = []  // sorted, for binary search
    @State private var autoScrollPaused = false
    @State private var scrollPauseTask: Task<Void, Never>?
    @State private var scrollMonitor: Any?
    @State private var meetingPlaybackFollowController = MeetingTranscriptPlaybackFollowController()
    @State private var showPromptLibrary = false
    @State private var showGeneratePopover = false
    @State private var showingRetranscribeOptions = false
    @State private var showingSpeakerCountCorrection = false
    @State private var speakerCorrectionSource: AudioSource = .system
    @State private var microphoneSpeakerDetection = false
    @State private var speakerCorrectionSources: [AudioSource] = []
    @State private var speakerCorrectionMetadataLoading = true
    @State private var speakerCountEditorMode: SpeakerCountEditorMode = .auto
    @State private var exactTotalPeople = ""
    @State private var minimumTotalPeople = ""
    @State private var maximumTotalPeople = ""
    @State private var speakerCountEditorError: String?
    @State private var speakerCorrectionSubmitted = false
    @State private var pendingDeleteMeetingAudio = false
    @State private var showingCancelGenerationAlert: UUID?
    @FocusState private var chatInputFocused: Bool
    @FocusState private var titleFocused: Bool
    @FocusState private var speakerRenameFocused: Bool
    @FocusState private var findFieldFocused: Bool

    private let suggestedPrompts = [
        "Summarize the key points",
        "What are the main takeaways?",
        "List any action items mentioned",
    ]

    var body: some View {
        identityIsolatedAdaptiveLayout
        .onAppear {
            playbackViewModelProbe?(playerViewModel)
            findSessionDriverProbe?(
                TranscriptFindSessionDriver { query in
                    openFindBar()
                    setFindQuery(query)
                }
            )
            // Lazy migration for existing webm/opus YouTube audio files
            // saved before issue #237's playback fix shipped. The VM
            // transcodes in the background; this callback persists the new
            // .m4a path so the next open hits it directly.
            playerViewModel.onPlaybackFilePathConverted = { [viewModel] id, newPath, sourcePath in
                try viewModel.applyConvertedPlaybackPath(
                    transcriptionID: id,
                    newFilePath: newPath,
                    sourceFileToCleanup: sourcePath
                )
            }
            Task {
                if showVideoPanel {
                    await playerViewModel.load(for: transcription)
                } else {
                    await playerViewModel.prepare(for: transcription)
                }
                if let words = transcription.wordTimestamps, !words.isEmpty {
                    playerViewModel.loadSubtitleCues(from: words)
                }
            }
            rebuildSegmentCache()
            viewModel.loadPersistedContentAsync()
            syncTranscriptDisplayMode()
            promptResultsViewModel.loadPersistedContentAsync(transcriptionId: transcription.id)
            // Feed the user's typed meeting notes (if any) into chat alongside
            // the transcript. The closure is re-evaluated on every chat-send so
            // a CLI edit to userNotes in another process is visible to the next
            // chat turn without having to reload the page.
            chatViewModel.bindUserNotesProvider { [viewModel] in
                viewModel.currentTranscription?.userNotes
            }
        }
        .onChange(of: transcription.id) {
            Task {
                playerViewModel.cleanup()
                if showVideoPanel {
                    await playerViewModel.load(for: transcription)
                } else {
                    await playerViewModel.prepare(for: transcription)
                }
                if let words = transcription.wordTimestamps, !words.isEmpty {
                    playerViewModel.loadSubtitleCues(from: words)
                }
            }
            rebuildSegmentCache()
            headerExpanded = false
            speakerOverviewExpanded = true
            editingTitle = false
            titleDraft = ""
            editingTranscript = false
            transcriptDraft = ""
            transcriptEditError = nil
            transcriptDisplayModeBeforeEdit = nil
            editingSpeakerId = nil
            editingSpeakerLabel = ""
            showConversationPopover = false
            hoveredConversationId = nil
            showingSpeakerCountCorrection = false
            speakerCountEditorMode = .auto
            exactTotalPeople = ""
            minimumTotalPeople = ""
            maximumTotalPeople = ""
            speakerCountEditorError = nil
            speakerCorrectionSubmitted = false
            lastScrolledSegmentMs = -1
            autoScrollPaused = false
            scrollPauseTask?.cancel()
            meetingPlaybackFollowController.resume()
            // Reset find for the new transcript (no animation during the swap).
            findBarVisible = false
            findFieldFocused = false
            findModel.clear()
            findBlocks = []
            findPausedAutoScroll = false
            viewModel.hasConversations = false
            viewModel.selectedTab = .transcript
            viewModel.loadPersistedContentAsync()
            syncTranscriptDisplayMode()
            promptResultsViewModel.loadPersistedContentAsync(transcriptionId: transcription.id)
        }
        .onChange(of: activeTranscription.speakers) {
            rebuildSegmentCache()
            if findBarVisible { rebuildFindBlocks() }
        }
        .onChange(of: activeTranscription.wordTimestamps) {
            rebuildSegmentCache()
            if findBarVisible { rebuildFindBlocks() }
        }
        .onChange(of: activeTranscription.readingDocument) {
            rebuildSegmentCache()
            syncTranscriptDisplayMode()
            if findBarVisible { rebuildFindBlocks() }
        }
        .onChange(of: activeTranscription.diarizationSegments) {
            rebuildSegmentCache()
            if findBarVisible { rebuildFindBlocks() }
        }
        .onChange(of: activeTranscription.status) {
            rebuildSegmentCache()
            syncTranscriptDisplayMode()
            if findBarVisible { rebuildFindBlocks() }
        }
        .onChange(of: activeTranscription.updatedAt) {
            rebuildSegmentCache()
        }
        .onChange(of: viewModel.speakerAttributionCorrectionState) { _, state in
            if case .idle = state, speakerCorrectionSubmitted {
                showingSpeakerCountCorrection = false
                speakerCorrectionSubmitted = false
            }
        }
        .onChange(of: customWordsRevision) {
            rebuildSegmentCache()
            if findBarVisible { rebuildFindBlocks() }
        }
        .onChange(of: transcriptAIContextModeRaw) {
            chatViewModel.loadTranscript(currentAIContextText, transcriptionId: viewModel.currentTranscription?.id)
        }
        .onChange(of: viewModel.selectedTab) {
            if case .result(let id) = viewModel.selectedTab {
                promptResultsViewModel.markPromptResultViewed(id)
            }
        }
        .onDisappear {
            detailPreparationTask?.cancel()
            detailPreparationTask = nil
            playerViewModel.cleanup()
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
            scrollPauseTask?.cancel()
        }
        .sheet(isPresented: $showPromptLibrary, onDismiss: {
            promptsViewModel.loadPrompts()
            promptResultsViewModel.loadVisiblePrompts()
        }) {
            PromptLibraryView(viewModel: promptsViewModel)
        }
        .alert(
            "Delete Result?",
            isPresented: Binding(
                get: { promptResultsViewModel.pendingDeletePromptResult != nil },
                set: { if !$0 { promptResultsViewModel.pendingDeletePromptResult = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                promptResultsViewModel.confirmDelete()
            }
            Button("Cancel", role: .cancel) {
                promptResultsViewModel.pendingDeletePromptResult = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    /// Erase the adaptive root before AppKit hosts it. This keeps the cold
    /// AttributeGraph transaction from specializing every detail branch.
    private var identityIsolatedAdaptiveLayout: AnyView {
        guard cachedTranscriptionID == nil || cachedTranscriptionID == activeTranscription.id else {
            return AnyView(Color.clear)
        }
        if let hostedPresentationModule {
            return AnyView(focusedPresentationModule(hostedPresentationModule))
        }
        return AnyView(adaptiveLayoutWithEvaluationProbe)
    }

    /// Hosts one real production presentation module for focused correctness
    /// and performance tests without creating a second implementation path.
    @ViewBuilder
    private func focusedPresentationModule(_ module: TranscriptDetailPresentationModule) -> some View {
        switch module {
        case .header:
            headerDomain
        case .actions:
            actionsDomain
        case .transcriptDocument:
            transcriptDocumentDomain
        case .findSession:
            findSessionDomain
        case .playbackFollow:
            meetingReadingTurnView
        case .speakerEditing:
            if let speakers = activeTranscription.speakers, !speakers.isEmpty {
                speakerEditingDomain(speakers: speakers, compact: true)
            }
        case .aiPanes:
            aiPanesDomain { chatPane(viewModel: chatViewModel) }
        }
    }

    private var adaptiveLayoutWithEvaluationProbe: some View {
        let _ = detailEvaluationProbe?()
        return adaptiveLayout
    }

    @ViewBuilder
    private var adaptiveLayout: some View {
        switch playerViewModel.playbackMode {
        case .video where showVideoPanel:
            HSplitView {
                videoInfoColumn
                    .frame(
                        minWidth: DesignSystem.Layout.videoPlayerMinWidth,
                        idealWidth: 480
                    )

                videoContentColumn
            }
        case .video, .audio:
            // Audio mode OR video with panel hidden — show scrubber bar + full-width content
            VStack(spacing: 0) {
                AudioScrubberBar(viewModel: playerViewModel)
                Divider()
                fullWidthContentColumn
            }
        case .none:
            fullWidthContentColumn
        }
    }

    private func presentationDomain<Content: View>(
        _ module: TranscriptDetailPresentationModule,
        revision: TranscriptDetailPresentationRevision,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        TranscriptDetailInvalidationDomain(
            module: module,
            revision: revision,
            evaluationProbe: moduleEvaluationProbe,
            content: content
        )
        .equatable()
    }

    private func aiPanesDomain<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        presentationDomain(.aiPanes, revision: aiPanesRevision, content: content)
    }

    private var headerRevision: TranscriptDetailPresentationRevision {
        TranscriptDetailPresentationRevision([
            activeTranscription.id.uuidString,
            displayedTitle,
            String(describing: activeTranscription.durationMs),
            String(cachedTextWordCount),
            String(cachedTimedWordCount),
            String(speakerCountValue),
            String(describing: engineAttributionLabel),
            String(describing: activeTranscription.sourceURL),
            String(activeTranscription.recoveredFromCrash),
            String(describing: MeetingPartialCapturePresentation.make(for: activeTranscription)),
            sourceChipText,
            expandedSourceChipText,
            String(headerExpanded),
            String(backHovered),
            String(editingTitle),
            titleDraft,
            String(titleFocused),
            cachedMandalaData.radialPoints.map(String.init(describing:)).joined(separator: ","),
        ])
    }

    private var actionsRevision: TranscriptDetailPresentationRevision {
        TranscriptDetailPresentationRevision([
            activeTranscription.id.uuidString,
            String(describing: activeTranscription.sourceType),
            String(describing: activeTranscription.status),
            String(describing: activeTranscription.filePath),
            String(copied),
            String(showingExportOptions),
            String(describing: selectedExportFormat),
            String(describing: transcriptExportOptions),
            String(describing: exportConfirmation?.id),
            String(showingRetranscribeOptions),
            String(showingSpeakerCountCorrection),
            String(describing: speakerCorrectionSource),
            String(microphoneSpeakerDetection),
            speakerCorrectionSources.map { String(describing: $0) }.joined(separator: ","),
            String(speakerCorrectionMetadataLoading),
            String(describing: speakerCountEditorMode),
            exactTotalPeople,
            minimumTotalPeople,
            maximumTotalPeople,
            String(describing: speakerCountEditorError),
            String(describing: viewModel.speakerAttributionCorrectionState),
            String(pendingDeleteMeetingAudio),
        ])
    }

    private var findSessionRevision: TranscriptDetailPresentationRevision {
        TranscriptDetailPresentationRevision([
            String(findBarVisible),
            findModel.query,
            String(findModel.isSearching),
            String(describing: findModel.current),
            String(describing: findModel.displayPosition),
            String(findScrollToken),
            String(findFieldFocused),
            String(describing: transcriptDisplayMode),
            String(findBlocks.count),
            String(describing: findBlocks.first?.id),
            String(describing: findBlocks.last?.id),
            String(readingTurnContentRevision),
        ])
    }

    private var speakerEditingRevision: TranscriptDetailPresentationRevision {
        TranscriptDetailPresentationRevision([
            activeTranscription.speakers?.map { "\($0.id):\($0.label)" }.joined(separator: "\u{1f}") ?? "",
            String(readingTurnContentRevision),
            String(speakerOverviewExpanded),
            String(describing: editingSpeakerId),
            String(describing: editingSpeakerContextID),
            editingSpeakerLabel,
            String(speakerRenameFocused),
        ])
    }

    private var transcriptDocumentRevision: TranscriptDetailPresentationRevision {
        TranscriptDetailPresentationRevision([
            activeTranscription.id.uuidString,
            String(describing: activeTranscription.status),
            String(activeTranscription.hasWordTimestamps),
            String(activeTranscription.isTranscriptEdited),
            String(describing: activeTranscription.userNotes),
            String(describing: activeTranscription.calendarEventSnapshot),
            String(describing: activeTranscription.meetingCaptureReport),
            String(cachedTranscriptionID == activeTranscription.id),
            String(readingTurnContentRevision),
            String(cachedHasPreferredText),
            String(cachedHasCleanTranscriptText),
            String(describing: transcriptDisplayMode),
            String(editingTranscript),
            transcriptDraft,
            String(describing: transcriptEditError),
            String(notesCopied),
            String(clampedTranscriptFontScale),
            String(shouldShowTranscriptAISetupBanner),
            String(describing: playerViewModel.playerState),
        ] + findSessionRevision.values + speakerEditingRevision.values)
    }

    private var aiPanesRevision: TranscriptDetailPresentationRevision {
        TranscriptDetailPresentationRevision([
            String(describing: viewModel.selectedTab),
            String(viewModel.showTabs),
            String(describing: copiedResultID),
            String(describing: copiedButtonResultID),
            String(describing: copiedMessageId),
            String(describing: hoveredMessageId),
            String(showConversationPopover),
            String(describing: hoveredConversationId),
            String(showGeneratePopover),
            String(showPromptLibrary),
            String(describing: showingCancelGenerationAlert),
            promptResultsViewModel.promptResults.map { "\($0.id):\($0.promptName)" }.joined(separator: "\u{1f}"),
            promptResultsViewModel.pendingGenerations.map { "\($0.id):\($0.state):\($0.content.hashValue)" }.joined(separator: "\u{1f}"),
            promptResultsViewModel.visiblePrompts.map { "\($0.id):\($0.name)" }.joined(separator: "\u{1f}"),
            String(describing: promptResultsViewModel.selectedPrompt?.id),
            String(promptResultsViewModel.hasPromptResultGenerationCapability),
            String(promptResultsViewModel.canGenerateManualPromptResult),
            String(describing: promptResultsViewModel.unreadPromptResultIDs),
            promptResultsViewModel.extraInstructions,
            String(describing: promptResultsViewModel.errorMessage),
            promptResultsViewModel.currentModelName,
            promptResultsViewModel.availableModels.joined(separator: "\u{1f}"),
            chatViewModel.messages.map { "\($0.id):\($0.role):\($0.isStreaming)" }.joined(separator: "\u{1f}"),
            String(chatViewModel.messages.last?.content.hashValue ?? 0),
            chatViewModel.conversations.map { "\($0.id):\($0.title)" }.joined(separator: "\u{1f}"),
            String(describing: chatViewModel.currentConversation?.id),
            String(chatViewModel.canSendMessage),
            chatViewModel.inputText,
            String(chatViewModel.isStreaming),
            String(describing: chatViewModel.errorMessage),
            chatViewModel.currentModelName,
            chatViewModel.availableModels.joined(separator: "\u{1f}"),
            String(chatInputFocused),
        ])
    }

    // MARK: - Video Split Layout (Left Pane)

    /// Left pane in video mode: header card + video player + action bar
    private var videoInfoColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerDomain
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.top, DesignSystem.Spacing.md)

            TranscriptionVideoPanel(
                transcription: transcription,
                playerViewModel: playerViewModel
            )

            Spacer(minLength: 0)

            Divider()

            actionsDomain
        }
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "Unable to export transcript.")
        }
    }

    // MARK: - Video Split Layout (Right Pane)

    /// Right pane in video mode: tabs + content (full height, no header/action bar)
    private var videoContentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if viewModel.showTabs {
                    tabBar
                }
                Spacer(minLength: DesignSystem.Spacing.md)

                HStack {
                    Button {
                        withAnimation(DesignSystem.Animation.contentSwap) {
                            showVideoPanel = false
                        }
                    } label: {
                        Label("Hide Video", systemImage: "rectangle.lefthalf.inset.filled.arrow.left")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .layoutPriority(1)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.md)

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDisappear {
            copiedResetTask?.cancel()
            copiedResetTask = nil
            resultCopiedResetTask?.cancel()
            resultCopiedResetTask = nil
            resultButtonCopiedResetTask?.cancel()
            resultButtonCopiedResetTask = nil
            dismissTask?.cancel()
            dismissTask = nil
        }
    }

    // MARK: - Full-Width Layout (No Video, Audio, or Hidden Video)

    /// Single-column layout: header + tabs + content + action bar
    private var fullWidthContentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Keep independent detail modules opaque to the outer stack. The
            // modules retain their own identities and interactions while the
            // cold stack sizes a shallow graph.
            AnyView(
                headerDomain
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.lg)
            )

            AnyView(
                HStack {
                    if viewModel.showTabs {
                        tabBar
                    }
                    Spacer(minLength: DesignSystem.Spacing.md)

                    HStack {
                        if playerViewModel.playbackMode == .video && !showVideoPanel {
                            Button {
                                withAnimation(DesignSystem.Animation.contentSwap) {
                                    showVideoPanel = true
                                }
                                // Lazy-load: extract YouTube stream only when user wants video
                                if playerViewModel.needsVideoStreamLoad {
                                    Task {
                                        await playerViewModel.load(for: transcription)
                                    }
                                }
                            } label: {
                                Label("Show Video", systemImage: "play.rectangle")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .layoutPriority(1)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.md)
            )

            AnyView(
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )

            Divider()

            AnyView(actionsDomain)
        }
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "Unable to export transcript.")
        }
        .onDisappear {
            copiedResetTask?.cancel()
            copiedResetTask = nil
            resultCopiedResetTask?.cancel()
            resultCopiedResetTask = nil
            resultButtonCopiedResetTask?.cancel()
            resultButtonCopiedResetTask = nil
            dismissTask?.cancel()
            dismissTask = nil
        }
    }

    // MARK: - Action Bar

    private var actionsDomain: some View {
        presentationDomain(.actions, revision: actionsRevision) {
            actionBarContent
        }
    }

    private var actionBarContent: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            copyAction

            Button {
                showingExportOptions.toggle()
            } label: {
                Label("Export", systemImage: "arrow.down.doc")
            }
            .parakeetAction(.secondary)
            .popover(isPresented: $showingExportOptions, arrowEdge: .top) {
                exportOptionsPopover
            }

            if activeTranscription.sourceType == .meeting {
                let audioState = MeetingAudioFile.state(for: activeTranscription)
                let audioAvailable = audioState == .saved
                let audioRemovable = MeetingAudioFile.isRemovable(for: activeTranscription, state: audioState)
                Menu {
                    Button {
                        MeetingAudioActions.revealInFinder(activeTranscription)
                    } label: {
                        Label("Show Audio in Finder", systemImage: "waveform")
                    }
                    Button {
                        saveMeetingAudioFromActionBar()
                    } label: {
                        Label("Save Audio As…", systemImage: "square.and.arrow.down")
                    }

                    Divider()

                    Button(role: .destructive) {
                        pendingDeleteMeetingAudio = true
                    } label: {
                        Label(MeetingDeletionCopy.audioOnlyMenuTitle, systemImage: "waveform.slash")
                    }
                    .disabled(!audioRemovable)
                    .help(audioRemovable
                          ? "Remove the saved meeting audio while keeping the meeting"
                          : MeetingDeletionCopy.audioRemovalUnavailableHelp(
                              for: activeTranscription,
                              state: audioState
                          ))
                } label: {
                    Label("Audio", systemImage: "waveform")
                }
                .parakeetAction(.secondary)
                .disabled(!audioAvailable)
                .help(audioAvailable
                      ? "Reveal or save the meeting audio file"
                      : MeetingDeletionCopy.audioUnavailableHelp(for: audioState))

                let artifactAvailable = MeetingArtifactActions.folderURL(for: activeTranscription) != nil
                Menu {
                    Button {
                        MeetingArtifactActions.openFolder(for: activeTranscription)
                    } label: {
                        Label("Open Meeting Folder", systemImage: "folder")
                    }

                    Button {
                        MeetingArtifactActions.copyFolderPath(for: activeTranscription)
                    } label: {
                        Label("Copy Artifact Folder Path", systemImage: "doc.on.doc")
                    }
                } label: {
                    Label("Artifacts", systemImage: "folder")
                }
                .parakeetAction(.secondary)
                .disabled(!artifactAvailable)
                .help(artifactAvailable
                      ? "Open or copy the meeting artifact folder path"
                      : "Meeting artifact folder is not available")
            }

            if onRetranscribe != nil, let filePath = activeTranscription.filePath,
               TranscriptDetailActionAvailability.canRetranscribe(
                   hasRetainedAudio: FileManager.default.fileExists(atPath: filePath),
                   status: activeTranscription.status
               ), let engineOption = viewModel.retranscriptionEngineOption(for: activeTranscription) {
                Button {
                    showingRetranscribeOptions.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                        Text("Retranscribe")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 2)
                    }
                }
                .parakeetAction(.secondary)
                .help("Choose a speech engine for this rerun")
                .popover(isPresented: $showingRetranscribeOptions, arrowEdge: .top) {
                    retranscribeOptionsPopover(for: engineOption)
                }
            }

            if activeTranscription.sourceType == .meeting,
               activeTranscription.status == .completed {
                Button {
                    speakerCountEditorError = nil
                    viewModel.clearMeetingSpeakerAttributionCorrectionError()
                    speakerCorrectionMetadataLoading = true
                    showingSpeakerCountCorrection.toggle()
                } label: {
                    Label("Adjust Speakers", systemImage: "person.2.badge.gearshape")
                }
                .parakeetAction(.secondary)
                .help("Rerun speaker attribution without changing transcript words")
                .popover(isPresented: $showingSpeakerCountCorrection, arrowEdge: .top) {
                    speakerCountCorrectionPopover
                }
            }

            Spacer()

            if let onStartNew {
                Button {
                    onStartNew()
                } label: {
                    Label("New Transcription", systemImage: "plus")
                }
                .parakeetAction(.primary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .onChange(of: transcription.id) {
            showingRetranscribeOptions = false
        }
        .alert(MeetingDeletionCopy.audioOnlyAlertTitle, isPresented: $pendingDeleteMeetingAudio) {
            Button("Cancel", role: .cancel) {}
            Button(MeetingDeletionCopy.audioOnlyConfirmTitle, role: .destructive) {
                deleteMeetingAudioFromActionBar()
            }
        } message: {
            Text(
                MeetingDeletionCopy.singleAudioOnlyMessage(
                    surface: .library,
                    status: activeTranscription.status
                )
            )
        }
        .popover(item: $exportConfirmation, arrowEdge: .top) { confirmation in
            exportConfirmationPopover(confirmation)
        }
    }

    @ViewBuilder
    private var copyAction: some View {
        if activeTranscription.sourceType == .meeting {
            Menu {
                Button {
                    copyTranscriptToClipboard()
                } label: {
                    Label("Copy Transcript", systemImage: "doc.plaintext")
                }
            } label: {
                copyActionLabel(title: copied ? "Copied!" : "Copy Meeting")
            } primaryAction: {
                copyMeetingToClipboard()
            }
            .parakeetAction(.secondary)
            .help("Copy the meeting title, notes, and transcript. Use the menu to copy only the transcript.")
            .accessibilityLabel("Copy meeting")
            .accessibilityValue(copied ? "Copied" : "")
        } else {
            Button {
                copyTranscriptToClipboard()
            } label: {
                copyActionLabel(title: copied ? "Copied!" : "Copy")
            }
            .parakeetAction(.secondary)
        }
    }

    private func copyActionLabel(title: String) -> some View {
        Label(
            title,
            systemImage: copied ? "checkmark" : "doc.on.clipboard"
        )
        .foregroundStyle(copied ? DesignSystem.Colors.successGreen : .primary)
    }

    private func retranscribeOptionsPopover(
        for option: TranscriptionViewModel.RetranscriptionEngineOption
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Label("Retranscribe with", systemImage: "arrow.trianglehead.2.clockwise")
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer(minLength: 8)

                Button {
                    showingRetranscribeOptions = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close retranscribe options")
            }

            VStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(option.choices) { choice in
                    EngineOptionCard(
                        selection: choice.selection,
                        nemotronVariant: option.nemotronVariant,
                        parakeetVariant: option.parakeetVariant,
                        isPrimary: choice.isPrimary,
                        primaryReflectsTranscriptEngine: option.primaryReflectsTranscriptEngine,
                        advisory: choice.advisory
                    ) {
                        selectRetranscribeEngine(
                            choice,
                            reflectsTranscriptEngine: option.primaryReflectsTranscriptEngine
                        )
                    }
                }
            }

            Text("Replaces this transcript. Prompts and chats are preserved.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(width: 390)
    }

    private var detectedCorrectionSpeakerCount: Int? {
        if microphoneSpeakerDetection {
            let count = (activeTranscription.speakers ?? []).filter {
                AudioSource.forSpeakerID($0.id) == speakerCorrectionSource
            }.count
            return count > 0 ? count : nil
        }
        return MeetingSpeakerCountSelection.detectedTotalPeople(in: activeTranscription)
    }

    private var speakerCountCorrectionPopover: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Adjust speaker count").font(DesignSystem.Typography.body.weight(.semibold))
                    if let detected = detectedCorrectionSpeakerCount {
                        Text(microphoneSpeakerDetection
                             ? "Detected: \(detected) in selected audio"
                             : "Detected: \(detected) total \(detected == 1 ? "person" : "people")")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                Spacer()
                Button {
                    showingSpeakerCountCorrection = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close speaker count options")
            }
            if microphoneSpeakerDetection {
                Picker("Audio source", selection: $speakerCorrectionSource) {
                    ForEach(speakerCorrectionSources, id: \.self) { source in
                        Text(source == .microphone ? "Microphone" : "System audio").tag(source)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(
                microphoneSpeakerDetection
                    ? "Counts apply only to the selected audio source. Local and remote speakers are detected separately."
                    : "Counts are total people in the meeting, including Me. MacParakeet applies the remaining count to remote speakers in system audio."
            )
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Picker("Speaker count", selection: $speakerCountEditorMode) {
                ForEach(SpeakerCountEditorMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            switch speakerCountEditorMode {
            case .auto:
                Text("Detect the speaker count automatically.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            case .exact:
                TextField("Total people", text: $exactTotalPeople)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Exact speaker count")
            case .bounded:
                HStack {
                    TextField("Minimum total", text: $minimumTotalPeople)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Minimum speaker count")
                    TextField("Maximum total", text: $maximumTotalPeople)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Maximum speaker count")
                }
            }
            if let message = speakerCountCorrectionMessage {
                Text(message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.errorRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if case .running(let message) = viewModel.speakerAttributionCorrectionState {
                    ProgressView().controlSize(.small)
                    Text(message).font(DesignSystem.Typography.caption).foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Button("Cancel") { viewModel.cancelMeetingSpeakerAttributionCorrection() }
                        .parakeetAction(.secondary)
                } else {
                    Spacer()
                    Button("Rerun Attribution") { startSpeakerCountCorrection() }
                        .parakeetAction(.primary)
                        .disabled(speakerCorrectionMetadataLoading)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(width: 390)
        .task(id: activeTranscription.id) {
            let transcription = activeTranscription
            let recording = await Task.detached {
                guard let path = transcription.filePath else { return Optional<MeetingRecordingOutput>.none }
                return try? MeetingRecordingOutput.loadArchived(
                    displayName: "Meeting", mixedAudioURL: URL(fileURLWithPath: path),
                    durationSeconds: Double(transcription.durationMs ?? 0) / 1000
                )
            }.value
            guard !Task.isCancelled else { return }
            microphoneSpeakerDetection = recording?.microphoneSpeakerDetection ?? false
            speakerCorrectionSources = [AudioSource.microphone, .system].filter {
                recording?.sourceAlignment.track(for: $0) != nil
            }
            speakerCorrectionSource = microphoneSpeakerDetection ? (speakerCorrectionSources.first ?? .microphone) : .system
            speakerCorrectionMetadataLoading = false
        }
        .onChange(of: speakerCountEditorMode) {
            speakerCountEditorError = nil
            viewModel.clearMeetingSpeakerAttributionCorrectionError()
        }
        .onChange(of: speakerCorrectionSource) {
            speakerCountEditorError = nil
            viewModel.clearMeetingSpeakerAttributionCorrectionError()
        }
    }

    private var speakerCountCorrectionMessage: String? {
        if let speakerCountEditorError { return speakerCountEditorError }
        if case .failed(let message) = viewModel.speakerAttributionCorrectionState { return message }
        return nil
    }

    private func startSpeakerCountCorrection() {
        let selection: MeetingSpeakerCountSelection
        switch speakerCountEditorMode {
        case .auto:
            selection = .auto
        case .exact:
            guard let total = Int(exactTotalPeople.trimmingCharacters(in: .whitespaces)) else {
                speakerCountEditorError = "Enter a whole-number total speaker count."
                return
            }
            selection = .exact(totalPeople: total)
        case .bounded:
            guard let minimum = Int(minimumTotalPeople.trimmingCharacters(in: .whitespaces)),
                  let maximum = Int(maximumTotalPeople.trimmingCharacters(in: .whitespaces)) else {
                speakerCountEditorError = "Enter whole-number minimum and maximum speaker counts."
                return
            }
            selection = .bounded(minTotalPeople: minimum, maxTotalPeople: maximum)
        }
        speakerCountEditorError = nil
        speakerCorrectionSubmitted = true
        let targetedSelection: MeetingSpeakerCountSelection =
            microphoneSpeakerDetection && speakerCorrectionSource == .microphone
            ? .microphone(selection) : selection
        viewModel.correctMeetingSpeakerAttribution(activeTranscription, selection: targetedSelection)
    }

    private func selectRetranscribeEngine(
        _ choice: TranscriptionViewModel.RetranscriptionEngineOption.Choice,
        reflectsTranscriptEngine: Bool
    ) {
        // Pin the engine named on the card whenever it is a specific choice — an
        // alternative engine, or the engine that actually produced this
        // transcript. Only the legacy "Current" primary (a fall-back to the
        // user's Final Transcription default) reruns through the plain
        // current-settings path, so its variant and language follow whatever
        // the user has set now.
        showingRetranscribeOptions = false
        performRetranscriptionSelection(
            transcription: activeTranscription,
            selection: choice.selection,
            isPrimary: choice.isPrimary,
            primaryReflectsTranscriptEngine: reflectsTranscriptEngine,
            onRetranscribe: onRetranscribe
        )
    }

    private var activeTranscription: Transcription {
        guard let current = viewModel.currentTranscription, current.id == transcription.id else {
            return transcription
        }
        return current
    }

    private var transcriptText: String {
        cachedTranscriptionID == activeTranscription.id ? cachedPreferredText : ""
    }

    private var usesMeetingReadingSurface: Bool {
        (activeTranscription.sourceType == .meeting || activeTranscription.readingDocument != nil)
            && activeTranscription.status == .completed
    }

    private var currentAIContextMode: TranscriptAIContextMode {
        TranscriptAIContextMode(rawValue: transcriptAIContextModeRaw) ?? .richTranscript
    }

    private var currentAIContextText: String {
        if usesMeetingReadingSurface, !activeTranscription.isTranscriptEdited {
            guard !cachedReadingTurns.isEmpty else { return transcriptText }
            return TranscriptAIContextFormatter.format(
                document: cachedReadingDocument,
                plainTranscript: transcriptText,
                mode: currentAIContextMode
            )
        }
        return TranscriptAIContextFormatter.format(
            transcription: activeTranscription,
            mode: currentAIContextMode
        )
    }

    private func reloadAIContext() {
        chatViewModel.loadTranscript(
            currentAIContextText,
            transcriptionId: viewModel.currentTranscription?.id
        )
    }

    private var rawTranscriptText: String {
        activeTranscription.rawTranscript ?? ""
    }

    private var hasEditedTranscript: Bool {
        activeTranscription.isTranscriptEdited && hasCleanTranscriptText
    }

    private var hasCleanTranscriptText: Bool {
        cachedTranscriptionID == activeTranscription.id && cachedHasCleanTranscriptText
    }

    private var transcriptWordCount: Int {
        guard cachedTranscriptionID == activeTranscription.id else { return 0 }
        return transcriptDisplayMode == .timed && cachedTimedWordCount > 0
            ? cachedTimedWordCount : cachedTextWordCount
    }

    private var speakerCountValue: Int {
        MeetingSpeakerCountSelection.detectedTotalPeople(in: activeTranscription)
            ?? activeTranscription.speakers?.count
            ?? activeTranscription.speakerCount
            ?? 0
    }

    /// User-facing engine attribution string for the metadata chip, or `nil`
    /// for legacy rows saved before the v0.8 engine-attribution migration —
    /// in that case we omit the chip rather than mislabel.
    private var engineAttributionLabel: String? {
        guard let engineRaw = activeTranscription.engine,
              let preference = SpeechEnginePreference(rawValue: engineRaw) else {
            return nil
        }
        switch preference {
        case .parakeet:
            return "Parakeet TDT"
        case .nemotron:
            // Variant-aware: the EN build is not "Nemotron 3.5". Legacy rows
            // (nil/multilingual variant) keep the established label.
            if activeTranscription.engineVariant == NemotronModelVariant.english1120.rawValue {
                return "Nemotron EN Beta"
            }
            return "Nemotron 3.5 Beta"
        case .whisper:
            guard let variant = activeTranscription.engineVariant else {
                return "Whisper"
            }
            return "Whisper \(SpeechEnginePreference.friendlyVariantName(variant))"
        case .cohere:
            return "Cohere Transcribe"
        }
    }

    private var headerDomain: some View {
        presentationDomain(.header, revision: headerRevision) {
            resultHeaderCardContent
        }
    }

    private var resultHeaderCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Always-visible compact row: back button + title + metadata + mandala + expand toggle
            HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(backHovered ? DesignSystem.Colors.accent : DesignSystem.Colors.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(backHovered ? DesignSystem.Colors.accent.opacity(0.12) : DesignSystem.Colors.surfaceElevated)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(DesignSystem.Animation.hoverTransition) {
                            backHovered = hovering
                        }
                    }
                    .accessibilityLabel("Back")
                }

                VStack(alignment: .leading, spacing: 4) {
                    titleView

                    if !headerExpanded {
                        // Inline metadata in collapsed mode
                        HStack(spacing: 6) {
                            metadataChip(
                                icon: sourceChipIcon,
                                text: sourceChipText,
                                tint: sourceChipTint,
                                symbolText: sourceChipSymbolText
                            )

                            if let durationMs = transcription.durationMs {
                                metadataChip(icon: "clock", text: durationMs.formattedDuration, tint: DesignSystem.Colors.textSecondary)
                            }

                            if transcriptWordCount > 0 {
                                metadataChip(icon: "text.word.spacing", text: "\(transcriptWordCount.formatted()) words", tint: DesignSystem.Colors.textSecondary)
                            }

                            if speakerCountValue > 0 {
                                metadataChip(icon: "person.2.fill", text: "\(speakerCountValue) speaker\(speakerCountValue == 1 ? "" : "s")", tint: DesignSystem.Colors.textSecondary)
                            }
                        }
                    }
                }

                Spacer(minLength: DesignSystem.Spacing.sm)

                SonicMandalaView(
                    data: mandalaData,
                    size: headerExpanded ? 56 : 40,
                    style: .fullColor
                )

                // Expand/collapse chevron
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .rotationEffect(.degrees(headerExpanded ? 180 : 0))
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)

            // Expanded details section
            if headerExpanded {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        metadataChip(
                            icon: sourceChipIcon,
                            text: expandedSourceChipText,
                            tint: sourceChipTint,
                            symbolText: sourceChipSymbolText
                        )

                        if let durationMs = transcription.durationMs {
                            metadataChip(icon: "clock", text: durationMs.formattedDuration, tint: DesignSystem.Colors.textSecondary)
                        }

                        if transcriptWordCount > 0 {
                            metadataChip(icon: "text.word.spacing", text: "\(transcriptWordCount.formatted()) words", tint: DesignSystem.Colors.textSecondary)
                        }

                        if speakerCountValue > 0 {
                            metadataChip(icon: "person.2.fill", text: "\(speakerCountValue) speaker\(speakerCountValue == 1 ? "" : "s")", tint: DesignSystem.Colors.textSecondary)
                        }

                        if let engineAttributionLabel {
                            metadataChip(icon: "cpu", text: engineAttributionLabel, tint: DesignSystem.Colors.textSecondary)
                        }
                    }

                    if let sourceURL = transcription.sourceURL,
                       let url = URL(string: sourceURL) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(sourceURL)
                                    .font(DesignSystem.Typography.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(DesignSystem.Colors.surface)
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.bottom, DesignSystem.Spacing.sm)
                .padding(.leading, onBack != nil ? 36 + DesignSystem.Spacing.sm : 0)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                headerExpanded.toggle()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .fill(DesignSystem.Colors.cardBackground)
                .cardShadow(DesignSystem.Shadows.cardRest)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.75), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var titleView: some View {
        if editingTitle {
            HStack(spacing: 8) {
                TextField("Title", text: $titleDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(headerExpanded ? DesignSystem.Typography.pageTitle : DesignSystem.Typography.sectionTitle)
                    .focused($titleFocused)
                    .onSubmit(commitTitleRename)

                Button(action: commitTitleRename) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.successGreen)
                }
                .buttonStyle(.plain)

                Button(action: cancelTitleRename) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 8) {
                Text(displayedTitle)
                    .font(headerExpanded ? DesignSystem.Typography.pageTitle : DesignSystem.Typography.sectionTitle)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(headerExpanded ? 3 : 1)

                if canRenameTitle {
                    Button(action: beginTitleRename) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(transcription.sourceType == .meeting ? "Rename meeting" : "Rename transcription")
                }

                if transcription.recoveredFromCrash {
                    metadataChip(
                        icon: "wrench.and.screwdriver",
                        text: "Recovered",
                        tint: DesignSystem.Colors.warningAmber
                    )
                }

                if let partialCapture = MeetingPartialCapturePresentation.make(for: activeTranscription) {
                    metadataChip(
                        icon: "exclamationmark.triangle.fill",
                        text: partialCapture.badgeText,
                        tint: DesignSystem.Colors.warningAmber
                    )
                }
            }
        }
    }

    private var sourceDisplay: TranscriptionSourceDisplay {
        TranscriptionSourceDisplay.resolve(for: transcription)
    }

    private var sourceChipIcon: String {
        sourceDisplay.systemImage
    }

    private var sourceChipSymbolText: String? {
        sourceDisplay.symbolText
    }

    private var sourceChipText: String {
        sourceDisplay.collapsedText
    }

    private var expandedSourceChipText: String {
        sourceDisplay.expandedText
    }

    private var sourceChipTint: Color {
        sourceDisplay.tint
    }

    private var displayedTitle: String {
        (viewModel.currentTranscription ?? transcription).effectiveDisplayTitle
    }

    private var canRenameTitle: Bool {
        transcription.sourceType == .meeting || transcription.sourceType == .file
    }

    private func beginTitleRename() {
        titleDraft = displayedTitle
        editingTitle = true
        Task { @MainActor in
            titleFocused = true
        }
    }

    private func cancelTitleRename() {
        editingTitle = false
        titleDraft = ""
    }

    private func commitTitleRename() {
        if transcription.sourceType == .meeting {
            viewModel.renameCurrentTranscription(to: titleDraft)
        } else if transcription.sourceType == .file {
            viewModel.renameCurrentTranscriptionTitle(to: titleDraft)
        }
        editingTitle = false
    }

    private func metadataChip(icon: String, text: String, tint: Color, symbolText: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let symbolText {
                Text(symbolText)
                    .font(.system(size: 10, weight: .bold))
            } else {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(DesignSystem.Typography.caption.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(tint.opacity(0.10))
        )
    }

    @ViewBuilder
    private var contentArea: some View {
        Group {
            if viewModel.showTabs {
                switch viewModel.selectedTab {
                case .transcript:
                    transcriptDocumentDomain
                case .result(let id):
                    if promptResultsViewModel.promptResults.contains(where: { $0.id == id }) {
                        aiPanesDomain { promptResultContentPane(promptResultID: id) }
                    } else {
                        transcriptDocumentDomain
                            .onAppear { viewModel.selectedTab = .transcript }
                    }
                case .generation(let id):
                    if promptResultsViewModel.pendingGeneration(id: id) != nil {
                        aiPanesDomain { pendingGenerationPane(generationID: id) }
                    } else {
                        transcriptDocumentDomain
                            .onAppear { viewModel.selectedTab = .transcript }
                    }
                case .chat:
                    aiPanesDomain { chatPane(viewModel: chatViewModel) }
                }
            } else {
                transcriptDocumentDomain
            }
        }
        .padding(DesignSystem.Spacing.lg)
    }

    private var transcriptBodyRowCount: Int {
        if usesMeetingReadingSurface, !cachedReadingTurns.isEmpty {
            return cachedReadingTurns.count
        }
        if cachedHasSpeakers {
            return cachedIdentifiedTurnCards.reduce(0) { count, card in
                count + card.turn.segments.count
            }
        }
        return cachedSegments.count
    }

    private var transcriptBodySpacing: CGFloat {
        if !editingTranscript,
           transcriptDisplayMode == .timed,
           usesMeetingReadingSurface,
           !cachedReadingTurns.isEmpty {
            return MeetingReadingTurnLayout.interTurnSpacing
        }
        return DesignSystem.Spacing.md
    }

    private var transcriptDocumentDomain: some View {
        presentationDomain(.transcriptDocument, revision: transcriptDocumentRevision) {
            transcriptPaneContent
        }
    }

    private var transcriptPaneContent: some View {
        VStack(spacing: 0) {
            if findBarVisible {
                findSessionDomain
            }
            if transcriptDisplayMode == .timed,
               usesMeetingReadingSurface,
               !cachedReadingTurns.isEmpty {
                AnyView(
                    meetingReadingTurnView
                        .padding(DesignSystem.Spacing.lg)
                )
            } else {
            AnyView(ScrollViewReader { proxy in
            ScrollView {
                TranscriptBodyStack(
                    rowCount: transcriptBodyRowCount,
                    spacing: transcriptBodySpacing
                ) {
                    transcriptPaneHeader

                    if let partialCapture = MeetingPartialCapturePresentation.make(for: activeTranscription) {
                        meetingPartialCaptureBanner(partialCapture)
                    }

                    if activeTranscription.sourceType == .meeting,
                       activeTranscription.status != .processing,
                       !activeTranscription.hasWordTimestamps,
                       let banner = meetingNoWordTimestampsBannerPresentation {
                        meetingNoWordTimestampsBanner(banner)
                    }

                    if shouldShowTranscriptAISetupBanner {
                        chatConfigurationBanner
                    }

                    if activeTranscription.sourceType == .meeting,
                       let calendarSnapshot = activeTranscription.calendarEventSnapshot {
                        SavedMeetingCalendarContextSection(snapshot: calendarSnapshot)
                    }

                    if let userNotes = activeTranscription.userNotes,
                       !userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        meetingNotesSection(userNotes)
                    }

                    if let error = transcriptEditError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.errorRed)
                    }

                    if let presentation = meetingTranscriptProcessingPresentation {
                        meetingTranscriptProcessingState(presentation)
                    }

                    if transcriptDisplayMode == .text,
                       editingTranscript || cachedHasPreferredText {
                        // Keep one structural identity while edit mode changes so
                        // the native selection and viewport remain in place.
                        transcriptTextBlock
                    } else if transcriptDisplayMode == .timed,
                              usesMeetingReadingSurface,
                              !cachedReadingTurns.isEmpty {
                        if let speakers = activeTranscription.speakers, !speakers.isEmpty {
                            speakerEditingDomain(speakers: speakers, compact: true)
                        }
                        meetingReadingTurnView
                    } else if transcriptDisplayMode == .timed,
                              let timestamps = activeTranscription.wordTimestamps,
                              !timestamps.isEmpty {
                        if let speakers = activeTranscription.speakers, !speakers.isEmpty {
                            speakerEditingDomain(speakers: speakers, compact: false)
                        }
                        timestampedView(words: timestamps)
                    } else if cachedHasPreferredText {
                        transcriptTextBlock
                    } else if meetingTranscriptProcessingPresentation == nil {
                        Text("No transcript available")
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background {
                if !usesMeetingReadingSurface {
                    NonMeetingTranscriptPlaybackObserver(
                        playerViewModel: playerViewModel,
                        evaluationProbe: {
                            TranscriptDetailPresentationInstrumentation.record(
                                .playbackFollow,
                                probe: moduleEvaluationProbe
                            )
                        }
                    ) { oldValue, newValue in
                        guard playerViewModel.isPlaying else { return }
                        // Detect seek (large time jump) — re-sync transcript regardless of pause state
                        if autoScrollPaused && abs(newValue - oldValue) > 2000 {
                            autoScrollPaused = false
                            scrollPauseTask?.cancel()
                            lastScrolledSegmentMs = -1
                        }
                        guard !autoScrollPaused else { return }
                        guard !cachedSegments.isEmpty else { return }
                        if let targetId = autoScrollTarget(for: newValue),
                           targetId != lastScrolledSegmentMs {
                            lastScrolledSegmentMs = targetId
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(targetId, anchor: .center)
                            }
                        }
                    }
                }
            }
            // Find navigation: scroll the current match into view. Pausing
            // auto-scroll keeps playback-follow from yanking the view back.
            .onChange(of: findScrollToken) {
                guard findBarVisible, findModel.current != nil else { return }
                autoScrollPaused = true
                findPausedAutoScroll = true
                scrollPauseTask?.cancel()
                guard let target = findCurrentScrollTargetID else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
            })
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .fill(DesignSystem.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.75), lineWidth: 0.5)
        )
        .background { transcriptFindShortcuts }
        .onChange(of: transcriptDisplayMode) {
            if findBarVisible { rebuildFindBlocks() }
        }
        .onChange(of: findModel.isSearching) { wasSearching, isSearching in
            guard findBarVisible, wasSearching, !isSearching else { return }
            if findModel.hasMatches {
                findScrollToken &+= 1
            } else {
                releaseFindOwnedAutoScrollPause()
            }
        }
        .onChange(of: editingTranscript) {
            if editingTranscript, findBarVisible { closeFindBar() }
        }
        .onAppear {
            if let existing = scrollMonitor {
                NSEvent.removeMonitor(existing)
            }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                if self.usesMeetingReadingSurface {
                    self.meetingPlaybackFollowController.handleManualScroll(
                        isPlaying: self.playerViewModel.isPlaying
                    )
                } else if self.playerViewModel.isPlaying {
                    if self.findPausedAutoScroll {
                        // Manual scroll takes ownership and should start the
                        // normal bounded pause below, not inherit find's pause.
                        self.findPausedAutoScroll = false
                        self.autoScrollPaused = false
                        self.scrollPauseTask?.cancel()
                    }
                    if !self.autoScrollPaused {
                        self.autoScrollPaused = true
                        self.lastScrolledSegmentMs = -1
                    }
                    self.scrollPauseTask?.cancel()
                    self.scrollPauseTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(5))
                        if !Task.isCancelled {
                            self.autoScrollPaused = false
                        }
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
            scrollPauseTask?.cancel()
            autoScrollPaused = false
            meetingPlaybackFollowController.resume()
        }
    }

    // MARK: - In-transcript find (U2)

    /// Pinned find toolbar at the top of the reading pane. Stays visible while
    /// scrolling (unlike a row inside the ScrollView) and never overlaps the
    /// header controls (unlike a floating overlay).
    private var findSessionDomain: some View {
        presentationDomain(.findSession, revision: findSessionRevision) {
            transcriptFindToolbar
        }
    }

    private var transcriptFindToolbar: some View {
        let _ = findSessionStateProbe?(
            findModel.query,
            findModel.isSearching,
            findModel.matchCount
        )
        return HStack {
            Spacer()
            transcriptFindBar
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.md)
        .padding(.bottom, DesignSystem.Spacing.sm)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var transcriptFindBar: some View {
        TranscriptFindBar(
            query: Binding(
                get: { findModel.query },
                set: { setFindQuery($0) }
            ),
            isFocused: $findFieldFocused,
            position: findModel.displayPosition,
            isSearching: findModel.isSearching,
            hasQueryButNoMatches: findHasQueryNoMatches,
            onNext: { findModel.next(); findScrollToken &+= 1 },
            onPrev: { findModel.prev(); findScrollToken &+= 1 },
            onClose: closeFindBar
        )
    }

    /// Hidden buttons that register ⌘F / ⌘G / ⇧⌘G while the transcript pane is
    /// in the hierarchy. ⌘G stepping is gated on an open bar with live matches.
    private var transcriptFindShortcuts: some View {
        ZStack {
            Button("") { openFindBar() }
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityIdentifier("transcript-find-open-command")
            if findBarVisible, findModel.hasMatches {
                Button("") { findModel.next(); findScrollToken &+= 1 }
                    .keyboardShortcut("g", modifiers: .command)
                Button("") { findModel.prev(); findScrollToken &+= 1 }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// The single emphasized match, resolved to its block's scroll `id`.
    private var findCurrentHighlight: (id: Int, range: NSRange)? {
        guard findBarVisible, let current = findModel.current,
              findBlocks.indices.contains(current.blockIndex) else { return nil }
        return (id: findBlocks[current.blockIndex].id, range: current.range)
    }

    /// Text mode first centers its finite native surface in the outer scroll
    /// view, then centers the exact glyph range inside that surface. Timed mode
    /// scrolls directly to the matching block.
    private var findCurrentScrollTargetID: Int? {
        guard findBarVisible, let current = findModel.current,
              findBlocks.indices.contains(current.blockIndex) else { return nil }
        guard transcriptDisplayMode != .text else { return Self.textSurfaceScrollTargetID }
        return findBlocks[current.blockIndex].id
    }

    private var findFullTextCurrentHighlightRange: NSRange? {
        guard findBarVisible, transcriptDisplayMode == .text else { return nil }
        return findModel.current?.range
    }

    private var findHasQueryNoMatches: Bool {
        findBarVisible
            && !findModel.isSearching
            && !findModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !findModel.hasMatches
    }

    private func openFindBar() {
        // Find is a reading affordance; editing uses the raw text editor.
        guard !editingTranscript else { return }
        if !findBarVisible {
            withAnimation(DesignSystem.Animation.contentSwap) { findBarVisible = true }
            rebuildFindBlocks()
        }
        Task { @MainActor in findFieldFocused = true }
    }

    private func closeFindBar() {
        withAnimation(DesignSystem.Animation.contentSwap) { findBarVisible = false }
        findFieldFocused = false
        findModel.clear()
        findBlocks = []
        releaseFindOwnedAutoScrollPause()
    }

    /// Resume playback-follow only if find navigation owns the pause; manual
    /// scroll pauses keep their normal 5-second lifetime.
    private func releaseFindOwnedAutoScrollPause() {
        meetingPlaybackFollowController.releaseFindNavigationPause()
        if findPausedAutoScroll {
            autoScrollPaused = false
            scrollPauseTask?.cancel()
            findPausedAutoScroll = false
        }
    }

    private func setFindQuery(_ newValue: String) {
        findModel.setQuery(newValue)
        if !findModel.isSearching {
            releaseFindOwnedAutoScrollPause()
        }
    }

    /// Rebuild the ordered blocks the matcher searches for the current mode and
    /// re-run the live query. Timed mode searches cached segments. Text mode
    /// searches the full transcript string so native selection can span line and
    /// paragraph breaks.
    private func rebuildFindBlocks() {
        guard findBarVisible, !editingTranscript else {
            findBlocks = []
            findModel.setBlocks([])
            releaseFindOwnedAutoScrollPause()
            return
        }
        let blocks: [TranscriptFindBlock]
        if transcriptDisplayMode == .timed, usesMeetingReadingSurface {
            blocks = cachedReadingFindBlocks
        } else if transcriptDisplayMode == .timed, hasTimestamps {
            blocks = cachedSegmentFindBlocks
        } else {
            blocks = cachedTextFindBlocks
        }
        findBlocks = blocks
        findModel.setBlocks(blocks.map(\.text))
        if findModel.hasMatches {
            findScrollToken &+= 1
        } else {
            releaseFindOwnedAutoScrollPause()
        }
    }

    /// Persisted scale clamped to the supported range, so a stale or externally
    /// written `transcriptFontScale` never renders the body at an out-of-range
    /// size before the user touches A−/A+.
    private var clampedTranscriptFontScale: Double {
        min(
            max(transcriptFontScale, Self.transcriptFontScaleRange.lowerBound),
            Self.transcriptFontScaleRange.upperBound
        )
    }

    /// Transcript body font at the current user reading scale (U4).
    private var scaledTranscriptFont: Font {
        DesignSystem.Typography.transcriptBody(scale: clampedTranscriptFontScale)
    }

    private func adjustTranscriptFontScale(by delta: Double) {
        let next = clampedTranscriptFontScale + delta
        transcriptFontScale = min(
            max(next, Self.transcriptFontScaleRange.lowerBound),
            Self.transcriptFontScaleRange.upperBound
        )
    }

    /// Compact A−/A+ control for the transcript reading size. Lives in the pane
    /// header; hidden while editing (editing uses the raw text editor).
    private var transcriptFontSizeControl: some View {
        HStack(spacing: 2) {
            Button {
                adjustTranscriptFontScale(by: -Self.transcriptFontScaleStep)
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(clampedTranscriptFontScale <= Self.transcriptFontScaleRange.lowerBound + 0.001)
            .help("Smaller transcript text")
            .accessibilityLabel("Smaller transcript text")

            Button {
                adjustTranscriptFontScale(by: Self.transcriptFontScaleStep)
            } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(clampedTranscriptFontScale >= Self.transcriptFontScaleRange.upperBound - 0.001)
            .help("Larger transcript text")
            .accessibilityLabel("Larger transcript text")
        }
        .foregroundStyle(DesignSystem.Colors.textSecondary)
    }

    private var transcriptPaneHeader: some View {
        let _ = headerEvaluationProbe?()
        return HStack(spacing: DesignSystem.Spacing.sm) {
            Label("Transcript", systemImage: "text.alignleft")
                .font(DesignSystem.Typography.sectionTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if hasEditedTranscript {
                Label("Edited", systemImage: "checkmark.circle.fill")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.successGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(DesignSystem.Colors.successGreen.opacity(0.10))
                    )
            }

            Spacer()

            // Completed meetings expose Reading and Text. Other transcripts show
            // Timed only when word timestamps exist.
            if !editingTranscript, hasTimestamps || usesMeetingReadingSurface {
                Picker("Transcript view", selection: $transcriptDisplayMode) {
                    ForEach(TranscriptDisplayMode.allCases, id: \.self) { mode in
                        Text(mode == .timed && usesMeetingReadingSurface ? "Reading" : mode.rawValue)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }

            if !editingTranscript {
                transcriptFontSizeControl
            }

            if editingTranscript {
                if hasEditedTranscript {
                    Button {
                        revertTranscriptEdit()
                    } label: {
                        Label("Revert", systemImage: "arrow.uturn.backward")
                    }
                    .parakeetAction(.secondary)
                }

                Button {
                    cancelTranscriptEdit()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .parakeetAction(.secondary)

                Button {
                    commitTranscriptEdit()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .parakeetAction(.primaryProminent)
                .disabled(transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                // Editing operates on the plain text transcript only; the Timed
                // view is derived from word timestamps and has no editable text.
                // Disable Edit in Timed mode rather than silently dropping the
                // user into the raw text view when they click it.
                Button {
                    beginTranscriptEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .parakeetAction(.secondary)
                .disabled(
                    transcriptDisplayMode != .text
                        || !TranscriptDetailActionAvailability.canEdit(
                            status: activeTranscription.status
                        )
                )
                .help(transcriptEditHelp)
            }
        }
    }

    private var transcriptEditHelp: String {
        if transcriptDisplayMode != .text {
            return "Switch to Text to edit. Edits apply to the text transcript; timestamps are preserved."
        }
        if activeTranscription.status == .processing {
            return "Editing is available after transcription finishes."
        }
        if !cachedHasPreferredText {
            return "Add transcript text manually."
        }
        return "Edit the transcript text"
    }

    private var meetingTranscriptProcessingPresentation: MeetingTranscriptProcessingPresentation? {
        MeetingTranscriptProcessingPresentation.make(
            sourceType: activeTranscription.sourceType,
            status: activeTranscription.status
        )
    }

    private func meetingTranscriptProcessingState(
        _ presentation: MeetingTranscriptProcessingPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ParakeetSpinner(.inline, tint: DesignSystem.Colors.accent)
                Text(presentation.title)
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }

            Text(presentation.message)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.surfaceElevated)
        )
        .accessibilityElement(children: .combine)
    }

    private var shouldShowTranscriptAISetupBanner: Bool {
        !viewModel.llmAvailable
            && !viewModel.hasPromptResultTabs
            && !viewModel.hasConversations
    }

    private var transcriptTextBlock: some View {
        TranscriptFindTextView(
            text: editingTranscript ? transcriptDraft : transcriptText,
            currentRange: findFullTextCurrentHighlightRange,
            fontScale: clampedTranscriptFontScale,
            navigationToken: findScrollToken,
            isEditable: editingTranscript,
            onTextChange: { updatedText in
                guard editingTranscript else { return }
                transcriptDraft = updatedText
            }
        )
        // Text mode owns a finite native viewport. TextKit can then lay out
        // visible text only instead of reporting a complete document height to
        // the enclosing SwiftUI scroll view.
        .frame(minHeight: 320, idealHeight: 520, maxHeight: 640)
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.surfaceElevated.opacity(editingTranscript ? 0.75 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .strokeBorder(
                    editingTranscript ? DesignSystem.Colors.accent.opacity(0.30) : .clear,
                    lineWidth: 1
                )
        )
        .id(Self.textSurfaceScrollTargetID)
    }

    private func transcriptTimedTextSearchableBlocks() -> some View {
        let current = findCurrentHighlight
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ForEach(findBlocks) { block in
                paragraphText(block, current: current)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(block.id)
            }
        }
        .textSelection(.enabled)
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.surfaceElevated.opacity(0.6))
        )
    }

    private func paragraphText(
        _ block: TranscriptFindBlock,
        current: (id: Int, range: NSRange)?
    ) -> Text {
        guard current?.id == block.id, let currentRange = current?.range else {
            return Text(block.text).font(scaledTranscriptFont)
        }
        return Text(TranscriptFindHighlight.attributed(
            block.text,
            current: currentRange,
            baseFont: scaledTranscriptFont
        ))
    }

    private func meetingNotesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Label("Your notes", systemImage: "note.text")
                    .font(DesignSystem.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Spacer()

                Button {
                    TranscriptResultActions.copyText(notes)
                    notesCopied = true
                    notesCopiedResetTask?.cancel()
                    notesCopiedResetTask = Task {
                        try? await Task.sleep(for: .seconds(1))
                        if !Task.isCancelled {
                            notesCopied = false
                        }
                    }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: notesCopied ? "checkmark" : "doc.on.doc")
                        Text(notesCopied ? "Copied" : "Copy")
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(notesCopied ? DesignSystem.Colors.successGreen : .primary)
                }
                .parakeetAction(.secondary)
                .controlSize(.small)
                .accessibilityLabel(notesCopied ? "Notes copied" : "Copy your notes")
            }

            Text(notes)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.surfaceElevated.opacity(0.25))
        )
    }

    // MARK: - Tab Bar

    private var orderedTabs: [TranscriptionViewModel.TranscriptTab] {
        var tabs: [TranscriptionViewModel.TranscriptTab] = [.transcript]
        // Generated content after transcript, oldest first so new tabs appear on the right
        for promptResult in promptResultsViewModel.promptResults.reversed() {
            tabs.append(.result(id: promptResult.id))
        }
        for generation in promptResultsViewModel.pendingGenerations(for: transcription.id) {
            tabs.append(.generation(id: generation.id))
        }
        tabs.append(.chat)
        return tabs
    }

    private var tabBar: some View {
        presentationDomain(.aiPanes, revision: aiPanesRevision) {
            tabBarContent
        }
    }

    private var tabBarContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(orderedTabs, id: \.self) { tab in
                    tabCapsule(for: tab)
                }

                generateTabButton

                Spacer()
            }
        }
        .mask(
            Rectangle()
                .padding(.vertical, -20)
        )
    }

    private func tabCapsule(for tab: TranscriptionViewModel.TranscriptTab) -> some View {
        let isSelected = viewModel.selectedTab == tab

        let isStreamingTab = {
            if case .generation(let id) = tab,
               let generation = promptResultsViewModel.pendingGeneration(id: id) {
                return generation.state == .streaming
            }
            return false
        }()

        let isCopiedTab: Bool = {
            if case .result(let id) = tab { return copiedResultID == id }
            return false
        }()

        return HStack(spacing: 6) {
            Image(systemName: tabIcon(tab))
                .font(.system(size: 11, weight: .semibold))
                .symbolEffect(.pulse, options: .repeating, isActive: isStreamingTab)
            Text(tabLabel(tab))
                .font(DesignSystem.Typography.bodySmall.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)

            if case .result(let id) = tab, promptResultsViewModel.hasUnreadPromptResult(id) {
                Circle()
                    .fill(DesignSystem.Colors.accent)
                    .frame(width: 6, height: 6)
            }

            if isCopiedTab {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.successGreen)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(isSelected ? DesignSystem.Colors.accent.opacity(0.12) : .clear)
        )
        .contentShape(Capsule())
        .foregroundStyle(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
        .animation(.easeInOut(duration: 0.3), value: isCopiedTab)
        .onTapGesture {
            viewModel.selectedTab = tab
        }
        .contextMenu {
            if case .result(let id) = tab,
               let promptResult = promptResultsViewModel.promptResults.first(where: { $0.id == id }) {
                Button("Copy Result") {
                    TranscriptResultActions.copyText(promptResult.content)
                    copiedResultID = id
                    resultCopiedResetTask?.cancel()
                    resultCopiedResetTask = Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copiedResultID = nil
                    }
                }

                Menu("Export Document") {
                    Button("Markdown (.md)") { exportGenerationToDownloads(promptResult: promptResult, format: .md) }
                    Button("Plain Text (.txt)") { exportGenerationToDownloads(promptResult: promptResult, format: .txt) }
                }

                Button("Delete Result", role: .destructive) {
                    promptResultsViewModel.pendingDeletePromptResult = promptResult
                }
            }
            if case .generation(let id) = tab {
                Button("Remove", role: .destructive) {
                    promptResultsViewModel.cancelGeneration(id: id)
                }
            }
        }
        .accessibilityAddTraits(.isButton)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private var generateTabButton: some View {
        let hasAI = promptResultsViewModel.hasPromptResultGenerationCapability
        return Button {
            showGeneratePopover = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .foregroundStyle(
                    hasAI
                        ? DesignSystem.Colors.textSecondary
                        : DesignSystem.Colors.accent
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .popover(isPresented: $showGeneratePopover) {
            promptGenerationPopover
                .frame(width: 420)
                .padding(DesignSystem.Spacing.lg)
        }
        .accessibilityLabel(hasAI ? "New prompt generation" : "Set up AI for prompt generation")
        .help(hasAI ? "Generate a prompt result" : "Set up AI for summaries and action items")
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    private func tabIcon(_ tab: TranscriptionViewModel.TranscriptTab) -> String {
        switch tab {
        case .transcript:
            return "text.alignleft"
        case .result:
            return "sparkles"
        case .generation(let id):
            switch promptResultsViewModel.pendingGeneration(id: id)?.state {
            case .queued:
                return "clock"
            case .failed:
                return "exclamationmark.triangle"
            default:
                return "sparkles"
            }
        case .chat:
            return "bubble.left.and.text.bubble.right"
        }
    }

    private func tabLabel(_ tab: TranscriptionViewModel.TranscriptTab) -> String {
        switch tab {
        case .transcript:
            return "Transcript"
        case .result(let id):
            guard let promptResult = promptResultsViewModel.promptResults.first(where: { $0.id == id }) else { return "Result" }
            return label(for: promptResult.promptName, extraInstructions: promptResult.extraInstructions)
        case .generation(let id):
            guard let gen = promptResultsViewModel.pendingGeneration(id: id) else { return "Result" }
            return label(for: gen.promptName, extraInstructions: gen.extraInstructions)
        case .chat:
            return "Chat"
        }
    }

    private func label(for promptName: String, extraInstructions: String?) -> String {
        guard let extra = extraInstructions?.trimmingCharacters(in: .whitespacesAndNewlines), !extra.isEmpty else {
            return promptName
        }
        let limit = 16
        let truncated = extra.count > limit ? String(extra.prefix(limit)) + "..." : extra
        return "\(promptName) + \"\(truncated)\""
    }

    // MARK: - Result Panes

    private func promptResultContentPane(promptResultID: UUID) -> some View {
        let promptResult = promptResultsViewModel.promptResults.first(where: { $0.id == promptResultID })
        return ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                if let promptResult {
                    HStack {
                        Spacer()

                        Button {
                            if let generationID = promptResultsViewModel.regeneratePromptResult(promptResult, transcript: currentAIContextText) {
                                viewModel.selectedTab = .generation(id: generationID)
                            }
                        } label: {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: "arrow.clockwise")
                                Text("Regenerate")
                            }
                            .font(DesignSystem.Typography.caption)
                        }
                        .parakeetAction(.secondary)
                        .controlSize(.small)
                        .disabled(!promptResultsViewModel.canGeneratePromptResult || transcriptText.isEmpty)

                        let isCopied = copiedButtonResultID == promptResultID
                        Button {
                            TranscriptResultActions.copyText(promptResult.content)
                            copiedButtonResultID = promptResultID
                            resultButtonCopiedResetTask?.cancel()
                            resultButtonCopiedResetTask = Task {
                                try? await Task.sleep(for: .seconds(1))
                                copiedButtonResultID = nil
                            }
                        } label: {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                Text(isCopied ? "Copied" : "Copy")
                            }
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(isCopied ? DesignSystem.Colors.successGreen : .primary)
                        }
                        .parakeetAction(.secondary)
                        .controlSize(.small)

                        Menu {
                            Button("Markdown (.md)") { exportGenerationToDownloads(promptResult: promptResult, format: .md) }
                            Button("Plain Text (.txt)") { exportGenerationToDownloads(promptResult: promptResult, format: .txt) }
                        } label: {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: "arrow.down.doc")
                                Text("Export")
                            }
                            .font(DesignSystem.Typography.caption)
                        }
                        .menuStyle(.borderedButton)
                        .tint(DesignSystem.Colors.tintNeutral)
                        .controlSize(.small)

                        Button(role: .destructive) {
                            promptResultsViewModel.pendingDeletePromptResult = promptResult
                        } label: {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: "trash")
                                Text("Delete")
                            }
                            .font(DesignSystem.Typography.caption)
                        }
                        .parakeetAction(.destructive)
                        .controlSize(.small)
                    }

                    MarkdownContentView(promptResult.content, font: DesignSystem.Typography.bodyLarge)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .fill(DesignSystem.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.75), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func pendingGenerationPane(generationID: UUID) -> some View {
        if let generation = promptResultsViewModel.pendingGeneration(id: generationID) {
            generationPane(generation)
        }
    }

    private func generationPane(_ generation: PromptResultsViewModel.PendingGeneration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                if case .failed(let message) = generation.state {
                    failedGenerationCard(generation, message: message)

                    // Partial content streamed before the failure is still
                    // worth reading; dimmed so it reads as incomplete.
                    if !generation.content.isEmpty {
                        MarkdownContentView(generation.content, font: DesignSystem.Typography.bodyLarge)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(0.6)
                    }
                } else {
                    HStack {
                        Spacer()
                        Button {
                            showingCancelGenerationAlert = generation.id
                        } label: {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: generation.state == .queued ? "minus.circle" : "xmark")
                                Text(generation.state == .queued ? "Remove" : "Cancel")
                            }
                            .font(DesignSystem.Typography.caption)
                        }
                        .parakeetAction(.secondary)
                        .controlSize(.small)
                    }

                    if generation.state == .queued {
                        queuedGenerationCard
                    } else if generation.content.isEmpty {
                        SummarySkeletonView()
                    } else {
                        MarkdownContentView(generation.content, font: DesignSystem.Typography.bodyLarge)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .fill(DesignSystem.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.75), lineWidth: 0.5)
        )
        .alert(
            generation.state == .queued ? "Remove from queue?" : "Cancel generation?",
            isPresented: Binding(
                get: { showingCancelGenerationAlert == generation.id },
                set: { if !$0 { showingCancelGenerationAlert = nil } }
            )
        ) {
            Button("Keep", role: .cancel) { }
            Button(generation.state == .queued ? "Remove" : "Cancel", role: .destructive) {
                promptResultsViewModel.cancelGeneration(id: generation.id)
                viewModel.selectedTab = .transcript
            }
        } message: {
            Text(generation.state == .queued
                 ? "This will remove the prompt from the generation queue."
                 : "This will stop the AI from generating the result.")
        }
    }

    private func failedGenerationCard(
        _ generation: PromptResultsViewModel.PendingGeneration,
        message: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label("Generation failed", systemImage: "exclamationmark.triangle.fill")
                .font(DesignSystem.Typography.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.errorRed)

            Text(message)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DesignSystem.Spacing.sm) {
                Button {
                    if let newID = promptResultsViewModel.retryGeneration(id: generation.id) {
                        viewModel.selectedTab = .generation(id: newID)
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .parakeetAction(.primary)
                .controlSize(.regular)

                Button("Dismiss") {
                    let replacingID = generation.replacingPromptResultID
                    promptResultsViewModel.cancelGeneration(id: generation.id)
                    viewModel.selectedTab = replacingID.map { .result(id: $0) } ?? .transcript
                }
                .parakeetAction(.secondary)
                .controlSize(.regular)
            }
            .padding(.top, DesignSystem.Spacing.xs)
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.surfaceElevated.opacity(0.7))
        )
    }

    private var queuedGenerationCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Label("Queued", systemImage: "clock")
                .font(DesignSystem.Typography.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.accent)
            Text("This result will start automatically after the current generation finishes.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.surfaceElevated.opacity(0.7))
        )
    }

    @ViewBuilder
    private var promptGenerationPopover: some View {
        if promptResultsViewModel.hasPromptResultGenerationCapability {
            promptGenerationControls
        } else {
            promptGenerationSetupPopover
        }
    }

    private var promptGenerationControls: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            // Prompt chips
            promptChips

            // Model selector
            if !promptResultsViewModel.availableModels.isEmpty {
                ModelSelectorView(
                    currentModel: promptResultsViewModel.currentModelName,
                    displayName: promptResultsViewModel.modelDisplayName,
                    availableModels: promptResultsViewModel.availableModels,
                    disabled: promptResultsViewModel.hasActiveGenerations,
                    onSelect: { promptResultsViewModel.selectModel($0) }
                )
            }

            // Extra instructions
            TextField("Extra instructions (optional)", text: $promptResultsViewModel.extraInstructions)
                .textFieldStyle(.roundedBorder)
                .font(DesignSystem.Typography.body)

            if promptResultsViewModel.hasActiveGenerations {
                Text(queueStatusText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            if let errorMessage = promptResultsViewModel.errorMessage {
                Text(errorMessage)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.errorRed)
            }

            // Actions row — manage prompts on the left, generate on the right
            HStack {
                Button {
                    showGeneratePopover = false
                    showPromptLibrary = true
                } label: {
                    Label("Manage Prompts", systemImage: "slider.horizontal.3")
                }
                .parakeetAction(.secondary)
                .controlSize(.regular)

                Spacer()

                Button {
                    showGeneratePopover = false
                    if let generationID = promptResultsViewModel.generatePromptResult(
                        transcript: currentAIContextText,
                        transcriptionId: transcription.id
                    ) {
                        viewModel.selectedTab = .generation(id: generationID)
                    }
                } label: {
                    Label("Generate", systemImage: "sparkles")
                }
                .parakeetAction(.primaryProminent)
                .controlSize(.regular)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!promptResultsViewModel.canGenerateManualPromptResult || transcriptText.isEmpty)
            }
        }
    }

    private var promptGenerationSetupPopover: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Turn on AI for summaries and action items")
                        .font(DesignSystem.Typography.body.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text("MacParakeet can generate summaries, action items, and custom prompt results from this transcript. Transcription still works without AI.")
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()

                Button {
                    showGeneratePopover = false
                    onSetUpAI?()
                } label: {
                    Label("Set up AI", systemImage: "gearshape")
                }
                .parakeetAction(.primaryProminent)
                .controlSize(.regular)
            }
        }
    }

    private var promptChips: some View {
        let prompts = promptResultsViewModel.visiblePrompts
        return FlowLayout(spacing: 8) {
            ForEach(prompts) { prompt in
                let isSelected = promptResultsViewModel.selectedPrompt?.id == prompt.id
                let hasExisting = promptResultsViewModel.promptResults.contains { $0.promptName == prompt.name }
                    || promptResultsViewModel.hasPendingGeneration(
                        promptName: prompt.name,
                        transcriptionId: transcription.id
                    )

                HStack(spacing: 5) {
                    Text(prompt.name)
                        .font(DesignSystem.Typography.body.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    if hasExisting {
                        Circle()
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? DesignSystem.Colors.accent.opacity(0.15) : DesignSystem.Colors.surfaceElevated)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? DesignSystem.Colors.accent.opacity(0.4) : DesignSystem.Colors.border.opacity(0.5), lineWidth: 0.5)
                )
                .foregroundStyle(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.textPrimary)
                .contentShape(Capsule())
                .onTapGesture {
                    withAnimation(DesignSystem.Animation.selectionChange) {
                        promptResultsViewModel.selectedPrompt = prompt
                    }
                }
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
        }
    }

    private var queueStatusText: String {
        if promptResultsViewModel.isStreaming && promptResultsViewModel.queuedGenerationCount > 0 {
            return "1 generating, \(promptResultsViewModel.queuedGenerationCount) queued"
        }
        if promptResultsViewModel.isStreaming {
            return "Generating result"
        }
        return "\(promptResultsViewModel.queuedGenerationCount) queued"
    }

    // MARK: - Chat Pane

    @ViewBuilder
    private func chatPane(viewModel chatVM: TranscriptChatViewModel) -> some View {
        VStack(spacing: 0) {
            // Chat header with conversation switcher
            if !chatVM.conversations.isEmpty || !chatVM.messages.isEmpty {
                chatPaneHeader(chatVM: chatVM)
                Divider()
            }

            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if chatVM.canSendMessage && chatVM.messages.isEmpty {
                        VStack(spacing: DesignSystem.Spacing.md) {
                            chatEmptyState(chatVM: chatVM)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            if let error = chatVM.errorMessage {
                                chatErrorRow(error)
                            }
                        }
                        .padding(DesignSystem.Spacing.lg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DesignSystem.Colors.surface)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                                if !chatVM.canSendMessage {
                                    chatConfigurationBanner
                                }

                                ForEach(chatVM.messages) { message in
                                    chatBubble(message)
                                        .id(message.id)
                                }

                                if let error = chatVM.errorMessage {
                                    chatErrorRow(error)
                                }
                            }
                            .padding(DesignSystem.Spacing.lg)
                        }
                        .defaultScrollAnchor(.bottom)
                        .background(DesignSystem.Colors.surface)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        HStack(spacing: DesignSystem.Spacing.sm) {
                            TextField("Ask about this transcript...", text: Bindable(chatVM).inputText)
                                .textFieldStyle(.plain)
                                .font(DesignSystem.Typography.bodyLarge)
                                .padding(.horizontal, DesignSystem.Spacing.md)
                                .padding(.vertical, 12)
                                .focused($chatInputFocused)
                                .onSubmit {
                                    if !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chatVM.canSendMessage && !chatVM.isStreaming {
                                        chatVM.sendMessage()
                                    }
                                    chatInputFocused = true
                                }
                                .disabled(chatVM.isStreaming || !chatVM.canSendMessage)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        chatInputFocused = true
                                    }
                                }
                                .onChange(of: chatVM.isStreaming) { _, isStreaming in
                                    if !isStreaming { chatInputFocused = true }
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(DesignSystem.Colors.surfaceElevated)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(DesignSystem.Colors.border.opacity(0.5), lineWidth: 1)
                                )

                            if chatVM.isStreaming {
                                Button {
                                    chatVM.cancelStreaming()
                                } label: {
                                    Image(systemName: "stop.circle.fill")
                                        .font(.system(size: 26))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(DesignSystem.Colors.errorRed)
                                .contentShape(Circle())
                            } else {
                                let canSend = !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chatVM.canSendMessage
                                Button {
                                    chatVM.sendMessage()
                                    chatInputFocused = true
                                } label: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 26))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(canSend ? DesignSystem.Colors.accent : DesignSystem.Colors.accent.opacity(0.3))
                                .disabled(!canSend)
                                .contentShape(Circle())
                            }
                        }

                        HStack(spacing: DesignSystem.Spacing.sm) {
                            if chatVM.canSendMessage && !chatVM.availableModels.isEmpty {
                                ModelSelectorView(
                                    currentModel: chatVM.currentModelName,
                                    displayName: chatVM.modelDisplayName,
                                    availableModels: chatVM.availableModels,
                                    disabled: chatVM.isStreaming,
                                    onSelect: { chatVM.selectModel($0) }
                                )
                            }

                            if chatVM.isStreaming {
                                Text("Streaming response…")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }

                            Spacer()
                        }
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(DesignSystem.Colors.cardBackground)
                }
                .onChange(of: chatVM.messages.count) {
                    if let lastID = chatVM.messages.last?.id {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .fill(DesignSystem.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.cardCornerRadius)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.75), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func chatPaneHeader(chatVM: TranscriptChatViewModel) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Button {
                showConversationPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(chatVM.currentConversation?.title ?? "New Chat")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showConversationPopover, arrowEdge: .bottom) {
                conversationListPopover(chatVM: chatVM)
            }

            Spacer()

            Button {
                chatVM.newChat()
            } label: {
                Label("New Chat", systemImage: "plus.bubble")
                    .font(DesignSystem.Typography.caption)
            }
            .parakeetAction(.secondary)
            .controlSize(.small)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.cardBackground)
    }

    @ViewBuilder
    private func conversationListPopover(chatVM: TranscriptChatViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(chatVM.conversations) { conversation in
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text(conversation.title.isEmpty ? "Untitled" : conversation.title)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    if hoveredConversationId == conversation.id {
                        Button {
                            chatVM.deleteConversation(conversation)
                            if chatVM.conversations.isEmpty {
                                showConversationPopover = false
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(
                    chatVM.currentConversation?.id == conversation.id
                        ? DesignSystem.Colors.accent.opacity(0.1)
                        : Color.clear
                )
                .contentShape(Rectangle())
                .onHover { isHovered in
                    if isHovered {
                        hoveredConversationId = conversation.id
                    } else if hoveredConversationId == conversation.id {
                        hoveredConversationId = nil
                    }
                }
                .onTapGesture {
                    chatVM.switchConversation(conversation)
                    showConversationPopover = false
                }
            }
        }
        .frame(minWidth: 200, maxWidth: 300)
        .padding(.vertical, DesignSystem.Spacing.sm)
    }

    @ViewBuilder
    private func chatBubble(_ message: ChatDisplayMessage) -> some View {
        let isUser = message.role == .user

        HStack(alignment: .bottom, spacing: DesignSystem.Spacing.sm) {
            if isUser { Spacer(minLength: 80) }

            if !isUser {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.surfaceElevated)
                        .frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)

                    if message.isStreaming {
                        SpinnerRingView(size: 14, revolutionDuration: 2.0, tintColor: DesignSystem.Colors.accent)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.accent)
                    }
                }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if message.content.isEmpty && message.isStreaming {
                    ChatLoadingSweep()
                } else {
                    let bubbleShape = UnevenRoundedRectangle(
                        topLeadingRadius: DesignSystem.Layout.cornerRadius,
                        bottomLeadingRadius: isUser ? DesignSystem.Layout.cornerRadius : 4,
                        bottomTrailingRadius: isUser ? 4 : DesignSystem.Layout.cornerRadius,
                        topTrailingRadius: DesignSystem.Layout.cornerRadius
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        if isUser {
                            Text(message.content)
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.onAccent)
                                .textSelection(.enabled)
                        } else {
                            MarkdownContentView(message.content)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: isUser ? nil : 620, alignment: .leading)
                    .background(
                        bubbleShape.fill(isUser
                            ? DesignSystem.Colors.accent
                            : DesignSystem.Colors.surfaceElevated)
                    )
                    .overlay(
                        bubbleShape.strokeBorder(
                            isUser
                                ? Color.white.opacity(0.12)
                                : DesignSystem.Colors.border.opacity(0.4),
                            lineWidth: 0.5
                        )
                    )
                    .shadow(color: .black.opacity(isUser ? 0.12 : 0.05), radius: isUser ? 3 : 2, y: 1)
                    .overlay(alignment: .bottomTrailing) {
                        if !isUser && !message.isStreaming && !message.content.isEmpty {
                            if hoveredMessageId == message.id || copiedMessageId == message.id {
                                Button {
                                    TranscriptResultActions.copyText(message.content)
                                    copiedMessageId = message.id
                                    copiedResetTask?.cancel()
                                    copiedResetTask = Task {
                                        try? await Task.sleep(for: .seconds(2))
                                        copiedMessageId = nil
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: copiedMessageId == message.id ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 10))
                                        if copiedMessageId == message.id {
                                            Text("Copied")
                                                .font(DesignSystem.Typography.micro)
                                        }
                                    }
                                    .foregroundStyle(copiedMessageId == message.id ? DesignSystem.Colors.successGreen : DesignSystem.Colors.textTertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(DesignSystem.Colors.surfaceElevated.opacity(0.85))
                                            .overlay(Capsule().strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5))
                                    )
                                }
                                .buttonStyle(.plain)
                                .transition(.opacity)
                                .padding(4)
                            }
                        }
                    }
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredMessageId = hovering ? message.id : nil
                        }
                    }
                }
            }

            if !isUser { Spacer(minLength: 80) }
        }
    }

    private var chatConfigurationBanner: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "brain")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Turn on AI for summaries and chat")
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("MacParakeet can use a local AI app, your API key, or a command-line AI tool. Transcription still works without this.")
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button {
                onSetUpAI?()
            } label: {
                Label("Set up AI", systemImage: "gearshape")
            }
            .parakeetAction(.secondary)
            .controlSize(.small)
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.accentLight)
        )
    }

    /// Shown above a meeting transcript that has text but no word timestamps
    /// (for example, it was transcribed with Cohere). Makes the
    /// text-only trade-off visible without promising speaker-label quality.
    private var meetingNoWordTimestampsBannerPresentation: MeetingTimedTranscriptRecoveryBannerPresentation? {
        let hasRetainedAudio =
            onRetranscribe != nil
            && (activeTranscription.filePath.map { FileManager.default.fileExists(atPath: $0) } ?? false)
        // Resolve the rerun choice from the live transcription so the banner
        // stays in sync with what's actually shown.
        let timestampCapableRerun: SpeechEngineSelection? = hasRetainedAudio
            ? viewModel.retranscriptionEngineOption(for: activeTranscription)?
                .firstTimestampCapableChoice?.selection
            : nil
        return MeetingTimedTranscriptRecoveryBannerPresentation.make(
            transcriptText: transcriptText,
            hasTranscriptText: cachedHasPreferredText,
            hasRetainedAudio: hasRetainedAudio,
            timestampCapableRerun: timestampCapableRerun
        )
    }

    private func meetingNoWordTimestampsBanner(
        _ presentation: MeetingTimedTranscriptRecoveryBannerPresentation
    ) -> some View {
        return HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "clock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(presentation.message)
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            if let action = presentation.action {
                Button {
                    onRetranscribe?(activeTranscription, action.selection)
                } label: {
                    Label(
                        action.title,
                        systemImage: "arrow.trianglehead.2.clockwise"
                    )
                }
                .parakeetAction(.secondary)
                .controlSize(.small)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.accentLight)
        )
    }

    private func meetingPartialCaptureBanner(
        _ presentation: MeetingPartialCapturePresentation
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.warningAmber)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(presentation.message)
                    .font(DesignSystem.Typography.bodySmall)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.warningAmber.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func chatErrorRow(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.Colors.errorRed)
            Text(error)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.errorRed)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
    }

    private func chatEmptyState(chatVM: TranscriptChatViewModel) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: DesignSystem.Spacing.hero)

            VStack(spacing: DesignSystem.Spacing.lg) {
                MeditativeMerkabaView(
                    size: 60,
                    revolutionDuration: 6.0,
                    tintColor: DesignSystem.Colors.accent
                )

                VStack(spacing: DesignSystem.Spacing.xs) {
                    Text("Ask a question about this transcript")
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .font(DesignSystem.Typography.pageTitle)

                    Text("Start with a quick prompt, then keep drilling down.")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .font(DesignSystem.Typography.body)
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(suggestedPrompts, id: \.self) { prompt in
                        Button {
                            chatVM.inputText = prompt
                            chatVM.sendMessage()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesignSystem.Colors.accent.opacity(0.7))
                                Text(prompt)
                                    .font(DesignSystem.Typography.bodySmall)
                            }
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(DesignSystem.Colors.surfaceElevated)
                                    .overlay(
                                        Capsule()
                                            .stroke(DesignSystem.Colors.border.opacity(0.8), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                }
            }

            Spacer(minLength: DesignSystem.Spacing.hero)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.surfaceElevated.opacity(0.55))
        )
    }

    // MARK: - Mandala Data

    private var mandalaData: MandalaData {
        cachedTranscriptionID == activeTranscription.id ? cachedMandalaData : .fallback
    }

    // MARK: - Timestamped View

    @ViewBuilder
    private func timestampedView(words _: [WordTimestamp]) -> some View {
        let current = findCurrentHighlight
        TranscriptTimestampedContentView(
            hasSpeakers: cachedHasSpeakers,
            identifiedTurnCards: cachedIdentifiedTurnCards,
            segments: cachedSegments,
            speakerColorMap: cachedSpeakerColorMap,
            speakerLabelForID: { cachedSpeakerLabelMap[$0] ?? "Unknown" },
            speakerLabelContent: { speakerID, speakerLabel, speakerColor, renameContextID, isRenameButtonVisuallyRevealed in
                speakerLabelView(
                    speaker: SpeakerInfo(id: speakerID, label: speakerLabel),
                    color: speakerColor,
                    contextID: renameContextID,
                    font: DesignSystem.Typography.body.weight(.semibold),
                    renameButtonOpacity: SpeakerRenameAccessibility.renameButtonOpacity(
                        isVisuallyRevealed: isRenameButtonVisuallyRevealed
                    )
                )
            },
            isSegmentActive: isSegmentActiveBinarySearch(segmentIndex:),
            timestampLabel: { formatTimestamp(ms: $0) },
            isTimestampSeekable: playerViewModel.playerState == .ready,
            onTimestampTap: { startMs in
                playerViewModel.seek(toMs: startMs)
                if !playerViewModel.isPlaying {
                    playerViewModel.togglePlayPause()
                }
                autoScrollPaused = false
                scrollPauseTask?.cancel()
            },
            bodyFont: scaledTranscriptFont,
            currentHighlight: current
        )
    }

    private var meetingReadingTurnView: some View {
        MeetingReadingTurnPlaybackView(
            playerViewModel: playerViewModel,
            followController: meetingPlaybackFollowController,
            turns: cachedReadingTurns,
            playbackIndex: cachedReadingTurnPlaybackIndex,
            speakerColorMap: cachedSpeakerColorMap,
            contentRevision: readingTurnContentRevision,
            headerRevision: meetingReadingHeaderRevision,
            findScrollID: findBarVisible ? findCurrentScrollTargetID : nil,
            findNavigationToken: findScrollToken,
            timestampLabel: { formatTimestamp(ms: $0) },
            isTimestampSeekable: playerViewModel.playerState == .ready,
            onTimestampTap: { startMs in
                playerViewModel.seek(toMs: startMs)
                if !playerViewModel.isPlaying {
                    playerViewModel.togglePlayPause()
                }
                meetingPlaybackFollowController.resume()
            },
            onCopyTurn: { turn in
                let passage = MeetingTranscriptPresentationDocument(turns: [turn])
                TranscriptResultActions.copyText(
                    MeetingTranscriptDocumentRenderer.markdown(passage),
                    source: .meeting
                )
                showCopiedFeedback()
            },
            onRenameSpeaker: { speakerID, label in
                viewModel.renameSpeaker(id: speakerID, to: label)
                rebuildSegmentCache()
            },
            bodyPointSize: 15 * clampedTranscriptFontScale,
            currentHighlight: findCurrentHighlight,
            evaluationProbe: {
                TranscriptDetailPresentationInstrumentation.record(
                    .playbackFollow,
                    probe: moduleEvaluationProbe
                )
            }
        ) {
            meetingReadingTurnHeader
        }
    }

    @ViewBuilder
    private var meetingReadingTurnHeader: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            transcriptPaneHeader

            if let partialCapture = MeetingPartialCapturePresentation.make(for: activeTranscription) {
                meetingPartialCaptureBanner(partialCapture)
            }
            if activeTranscription.sourceType == .meeting,
               activeTranscription.status != .processing,
               !activeTranscription.hasWordTimestamps,
               let banner = meetingNoWordTimestampsBannerPresentation {
                meetingNoWordTimestampsBanner(banner)
            }
            if shouldShowTranscriptAISetupBanner { chatConfigurationBanner }
            if let snapshot = activeTranscription.calendarEventSnapshot {
                SavedMeetingCalendarContextSection(snapshot: snapshot)
            }
            if let userNotes = activeTranscription.userNotes,
               !userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                meetingNotesSection(userNotes)
            }
            if let error = transcriptEditError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.errorRed)
            }
            if let speakers = activeTranscription.speakers, !speakers.isEmpty {
                speakerEditingDomain(speakers: speakers, compact: true)
            }
        }
        .padding(.bottom, DesignSystem.Spacing.md)
    }

    private var meetingReadingHeaderRevision: Int {
        var hasher = Hasher()
        hasher.combine(activeTranscription.id)
        hasher.combine(activeTranscription.userNotes)
        hasher.combine(activeTranscription.calendarEventSnapshot != nil)
        hasher.combine(activeTranscription.hasWordTimestamps)
        hasher.combine(meetingNoWordTimestampsBannerPresentation?.message)
        hasher.combine(shouldShowTranscriptAISetupBanner)
        hasher.combine(activeTranscription.speakers?.map { "\($0.id):\($0.label)" })
        hasher.combine(speakerOverviewExpanded)
        hasher.combine(transcriptEditError)
        hasher.combine(clampedTranscriptFontScale)
        return hasher.finalize()
    }

    // MARK: - Speaker Summary Panel

    @ViewBuilder
    private func speakerEditingDomain(speakers: [SpeakerInfo], compact: Bool) -> some View {
        presentationDomain(.speakerEditing, revision: speakerEditingRevision) {
            if compact {
                compactMeetingSpeakerSummaryPanel(speakers: speakers)
            } else {
                speakerSummaryPanel(speakers: speakers)
            }
        }
    }

    @ViewBuilder
    private func compactMeetingSpeakerSummaryPanel(speakers: [SpeakerInfo]) -> some View {
        let colorMap = cachedSpeakerColorMap
        let speakerStats = cachedSpeakerStatistics

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    speakerOverviewExpanded.toggle()
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Speakers")
                        .font(DesignSystem.Typography.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    if !speakerOverviewExpanded {
                        HStack(spacing: 4) {
                            ForEach(speakers.prefix(6), id: \.id) { speaker in
                                Circle()
                                    .fill(colorMap[speaker.id] ?? DesignSystem.Colors.textTertiary)
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .rotationEffect(.degrees(speakerOverviewExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SpeakerRenameAccessibility.overviewToggleLabel(isExpanded: speakerOverviewExpanded))
            .accessibilityHint(SpeakerRenameAccessibility.overviewToggleHint)
            .accessibilityIdentifier(SpeakerRenameAccessibility.overviewToggleIdentifier)

            if speakerOverviewExpanded {
                FlowLayout(spacing: DesignSystem.Spacing.sm) {
                    ForEach(speakers, id: \.id) { speaker in
                        speakerOverviewEntry(
                            speaker: speaker,
                            color: colorMap[speaker.id] ?? DesignSystem.Colors.textTertiary,
                            stats: speakerStats[speaker.id]
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Speaker labels are approximate.")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
    }

    private func speakerOverviewEntry(
        speaker: SpeakerInfo,
        color: Color,
        stats: SpeakerStatistics?
    ) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(DesignSystem.Colors.transcriptSpeakerLabelAlpha))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            speakerLabelView(
                speaker: speaker,
                color: color,
                contextID: SpeakerRenameAccessibility.overviewRenameContextIdentifier(for: speaker.id),
                font: DesignSystem.Typography.micro.weight(.semibold)
            )

            if let stats {
                Text("\(formatSpeakingTime(ms: stats.speakingTimeMs)) · \(stats.wordCount.formatted()) words")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(DesignSystem.Colors.surfaceElevated.opacity(0.7))
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func speakerSummaryPanel(speakers: [SpeakerInfo]) -> some View {
        let colorMap = cachedSpeakerColorMap
        let speakerStats = cachedSpeakerStatistics

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    speakerOverviewExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Speaker overview")
                        .font(DesignSystem.Typography.body.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    if !speakerOverviewExpanded {
                        // Compact inline speaker dots when collapsed
                        HStack(spacing: 4) {
                            ForEach(speakers.prefix(6), id: \.id) { speaker in
                                Circle()
                                    .fill(colorMap[speaker.id] ?? DesignSystem.Colors.textTertiary)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .rotationEffect(.degrees(speakerOverviewExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SpeakerRenameAccessibility.overviewToggleLabel(isExpanded: speakerOverviewExpanded))
            .accessibilityHint(SpeakerRenameAccessibility.overviewToggleHint)
            .accessibilityIdentifier(SpeakerRenameAccessibility.overviewToggleIdentifier)

            if speakerOverviewExpanded {
                ForEach(speakers, id: \.id) { speaker in
                    let stats = speakerStats[speaker.id]
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Circle()
                            .fill(colorMap[speaker.id] ?? DesignSystem.Colors.textTertiary)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 6) {
                            speakerLabelView(
                                speaker: speaker,
                                color: colorMap[speaker.id] ?? DesignSystem.Colors.textSecondary,
                                contextID: SpeakerRenameAccessibility.overviewRenameContextIdentifier(for: speaker.id)
                            )

                            if let stats {
                                HStack(spacing: DesignSystem.Spacing.sm) {
                                    metadataChip(icon: "clock", text: formatSpeakingTime(ms: stats.speakingTimeMs), tint: DesignSystem.Colors.textSecondary)
                                    metadataChip(icon: "text.word.spacing", text: "\(stats.wordCount.formatted()) words", tint: DesignSystem.Colors.textSecondary)
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                            .fill(DesignSystem.Colors.surfaceElevated.opacity(0.45))
                    )
                }
                Text("Speaker labels are approximate.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.surfaceElevated.opacity(0.25))
        )
    }

    @ViewBuilder
    private func speakerLabelView(
        speaker: SpeakerInfo,
        color: Color,
        contextID: String,
        font: Font = DesignSystem.Typography.caption.weight(.semibold),
        renameButtonOpacity: Double = SpeakerRenameAccessibility.renameButtonOpacity(isVisuallyRevealed: true)
    ) -> some View {
        if editingSpeakerId == speaker.id, editingSpeakerContextID == contextID {
            TextField("Name", text: $editingSpeakerLabel)
                .font(font)
                .foregroundStyle(color)
                .textFieldStyle(.plain)
                .frame(minWidth: 60, maxWidth: 200)
                .focused($speakerRenameFocused)
                .task { speakerRenameFocused = true }
                .onSubmit {
                    commitSpeakerRename()
                }
                .onExitCommand {
                    cancelSpeakerRename()
                }
                .onChange(of: speakerRenameFocused) {
                    if !speakerRenameFocused {
                        commitSpeakerRename()
                    }
                }
                .accessibilityLabel(SpeakerRenameAccessibility.speakerNameFieldLabel)
                .accessibilityHint(SpeakerRenameAccessibility.speakerNameFieldHint)
                .accessibilityIdentifier(SpeakerRenameAccessibility.speakerNameFieldIdentifier(contextID: contextID))
        } else {
            HStack(spacing: 6) {
                Text(speaker.label)
                    .font(font)
                    .foregroundStyle(color)
                    .onTapGesture {
                        beginSpeakerRename(speaker, contextID: contextID)
                    }

                Button {
                    beginSpeakerRename(speaker, contextID: contextID)
                } label: {
                    Label(SpeakerRenameAccessibility.renameButtonLabel(for: speaker.label), systemImage: "pencil")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .parakeetAction(.subtle)
                .controlSize(.small)
                .help(SpeakerRenameAccessibility.renameButtonLabel(for: speaker.label))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SpeakerRenameAccessibility.renameButtonLabel(for: speaker.label))
                .accessibilityHint(SpeakerRenameAccessibility.renameButtonHint)
                .accessibilityIdentifier(SpeakerRenameAccessibility.renameButtonIdentifier(contextID: contextID))
                .opacity(renameButtonOpacity)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func beginSpeakerRename(_ speaker: SpeakerInfo, contextID: String) {
        if editingSpeakerId != nil, editingSpeakerId != speaker.id || editingSpeakerContextID != contextID {
            commitSpeakerRename()
        }
        editingSpeakerId = speaker.id
        editingSpeakerContextID = contextID
        editingSpeakerLabel = speaker.label
    }

    private func commitSpeakerRename() {
        guard let speakerId = editingSpeakerId else { return }
        let trimmed = editingSpeakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            viewModel.renameSpeaker(id: speakerId, to: trimmed)
            rebuildSegmentCache()
        }
        cancelSpeakerRename()
    }

    private func cancelSpeakerRename() {
        editingSpeakerId = nil
        editingSpeakerContextID = nil
        editingSpeakerLabel = ""
        speakerRenameFocused = false
    }


    private func formatSpeakingTime(ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    // MARK: - Segment Cache

    /// Rebuild cached segment data. Called once on appear and when transcription.id changes.
    private var customWordsRevision: [String] {
        customWords.map {
            "\($0.id.uuidString)|\($0.word)|\($0.replacement ?? "")|\($0.isEnabled)|\($0.updatedAt.timeIntervalSinceReferenceDate)"
        }
    }

    private func rebuildSegmentCache() {
        let transcription = activeTranscription
        let customWords = customWords
        let input = TranscriptDetailPreparationInput(
            transcription: transcription,
            customWords: customWords
        )
        if cachedTranscriptionID != transcription.id {
            clearDetailSnapshot()
        }

        if let cached = TranscriptDetailSnapshotCache.shared.value(for: input) {
            applyDetailSnapshot(cached)
            return
        }

        detailPreparationTask?.cancel()
        detailPreparationTask = Task { @MainActor in
            let snapshot = await Task.detached(priority: .userInitiated) {
                TranscriptDetailPreparation.make(
                    transcription: transcription,
                    customWords: customWords,
                    input: input
                )
            }.value
            let currentInput = TranscriptDetailPreparationInput(
                transcription: activeTranscription,
                customWords: self.customWords
            )
            guard !Task.isCancelled,
                viewModel.currentTranscription?.id == transcription.id,
                snapshot.input == currentInput
            else { return }
            TranscriptDetailSnapshotCache.shared.insert(snapshot)
            applyDetailSnapshot(snapshot)
            detailPreparationTask = nil
        }
    }

    private func applyDetailSnapshot(_ snapshot: TranscriptDetailPreparationSnapshot) {
        guard snapshot.input.transcriptionID == activeTranscription.id else { return }
        cachedTranscriptionID = snapshot.input.transcriptionID
        cachedPreferredText = snapshot.preferredText
        cachedTextWordCount = snapshot.textWordCount
        cachedTimedWordCount = snapshot.timedWordCount
        cachedHasPreferredText = snapshot.hasPreferredText
        cachedHasCleanTranscriptText = snapshot.hasCleanTranscriptText
        cachedReadingDocument = snapshot.readingDocument
        cachedReadingTurns = snapshot.readingTurns
        cachedReadingTurnPlaybackIndex = snapshot.playbackIndex
        readingTurnContentRevision &+= 1
        cachedSegments = snapshot.segments
        cachedIdentifiedTurnCards = snapshot.identifiedTurnCards
        cachedHasSpeakers = snapshot.hasSpeakers
        cachedSegmentStartMs = snapshot.segmentStartMs
        cachedSpeakerStatistics = snapshot.speakerStatistics
        cachedSpeakerLabelMap = snapshot.speakerLabels
        cachedSpeakerColorMap = snapshot.speakerColorIndices.mapValues {
            DesignSystem.Colors.speakerColor(for: $0)
        }
        cachedReadingFindBlocks = snapshot.readingFindBlocks
        cachedSegmentFindBlocks = snapshot.segmentFindBlocks
        cachedTextFindBlocks = snapshot.textFindBlocks
        cachedMandalaData = snapshot.mandalaData
        syncTranscriptDisplayMode()
        reloadAIContext()
        if findBarVisible { rebuildFindBlocks() }
    }

    private func clearDetailSnapshot() {
        cachedTranscriptionID = nil
        cachedPreferredText = ""
        cachedTextWordCount = 0
        cachedTimedWordCount = 0
        cachedHasPreferredText = false
        cachedHasCleanTranscriptText = false
        cachedReadingDocument = MeetingTranscriptPresentationDocument(turns: [])
        cachedReadingTurns = []
        cachedReadingTurnPlaybackIndex = nil
        cachedSegments = []
        cachedIdentifiedTurnCards = []
        cachedHasSpeakers = false
        cachedSegmentStartMs = []
        cachedSpeakerStatistics = [:]
        cachedSpeakerLabelMap = [:]
        cachedSpeakerColorMap = [:]
        cachedReadingFindBlocks = []
        cachedSegmentFindBlocks = []
        cachedTextFindBlocks = []
        cachedMandalaData = .fallback
        findBlocks = []
        findModel.setBlocks([])
    }

    // MARK: - Binary Search Helpers

    /// Find the active segment index for the current playback time using binary search. O(log n).
    private func activeSegmentIndex(for currentMs: Int) -> Int? {
        guard !cachedSegmentStartMs.isEmpty else { return nil }

        // Binary search: find the last segment whose startMs <= currentMs
        var lo = 0
        var hi = cachedSegmentStartMs.count - 1
        var result = -1

        while lo <= hi {
            let mid = (lo + hi) / 2
            if cachedSegmentStartMs[mid] <= currentMs {
                result = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        return result >= 0 ? result : nil
    }

    /// Check if a segment at the given index is active (O(1) after binary search).
    private func isSegmentActiveBinarySearch(segmentIndex: Int) -> Bool {
        guard playerViewModel.playbackMode != .none else { return false }
        let currentMs = playerViewModel.currentTimeMs
        guard currentMs > 0 else { return false }
        guard let activeIdx = activeSegmentIndex(for: currentMs) else { return false }
        return activeIdx == segmentIndex
    }

    /// Find the scroll target ID (segment startMs) for the given playback time.
    private func autoScrollTarget(for currentMs: Int) -> Int? {
        if usesMeetingReadingSurface {
            return readingTurnScrollTarget(
                for: currentMs, in: cachedReadingTurns, playbackIndex: cachedReadingTurnPlaybackIndex
            )
        }
        if cachedHasSpeakers {
            return speakerTurnCardScrollTarget(
                for: currentMs,
                in: cachedIdentifiedTurnCards
            )
        } else {
            if let idx = activeSegmentIndex(for: currentMs) {
                return cachedSegmentStartMs[idx]
            }
        }
        return nil
    }

    // MARK: - Speaker Helpers

    private func syncTranscriptDisplayMode() {
        if shouldDefaultToMeetingReadingSurface(
            isCompletedMeeting: usesMeetingReadingSurface,
            isTranscriptEdited: activeTranscription.isTranscriptEdited,
            hasReadingTurns: !cachedReadingTurns.isEmpty
        ) {
            transcriptDisplayMode = .timed
        } else {
            transcriptDisplayMode = (hasCleanTranscriptText || !hasTimestamps) ? .text : .timed
        }
    }

    private func beginTranscriptEdit() {
        transcriptDraft = transcriptText
        transcriptEditError = nil
        transcriptDisplayModeBeforeEdit = transcriptDisplayMode
        editingTranscript = true
        transcriptDisplayMode = .text
    }

    private func cancelTranscriptEdit() {
        transcriptDraft = ""
        transcriptEditError = nil
        editingTranscript = false
        transcriptDisplayMode = transcriptDisplayModeBeforeEdit ?? transcriptDisplayMode
        transcriptDisplayModeBeforeEdit = nil
    }

    private func commitTranscriptEdit() {
        let trimmed = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            transcriptEditError = "Transcript text cannot be empty."
            SoundManager.shared.play(.errorSoft)
            return
        }

        if trimmed == transcriptText {
            cancelTranscriptEdit()
            return
        }

        guard viewModel.updateCurrentTranscriptText(to: transcriptDraft) else {
            transcriptEditError = "Could not save transcript edits."
            SoundManager.shared.play(.errorSoft)
            return
        }

        chatViewModel.loadTranscript(currentAIContextText, transcriptionId: viewModel.currentTranscription?.id)
        transcriptDraft = ""
        transcriptEditError = nil
        editingTranscript = false
        transcriptDisplayMode = .text
        transcriptDisplayModeBeforeEdit = nil
        SoundManager.shared.play(.transcriptionComplete)
    }

    private func revertTranscriptEdit() {
        guard viewModel.revertCurrentTranscriptToOriginal() else { return }
        chatViewModel.loadTranscript(currentAIContextText, transcriptionId: viewModel.currentTranscription?.id)
        transcriptDraft = ""
        transcriptEditError = nil
        editingTranscript = false
        transcriptDisplayMode = hasTimestamps ? .timed : .text
        transcriptDisplayModeBeforeEdit = nil
        SoundManager.shared.play(.transcriptionComplete)
    }

    // MARK: - Actions

    private func copyMeetingToClipboard() {
        let document =
            cachedReadingDocument.turns.isEmpty
            ? nil
            : cachedReadingDocument
        let markdown = MeetingMarkdownRenderer().renderForClipboard(
            transcription: activeTranscription,
            readingDocument: document
        )
        TranscriptResultActions.copyText(markdown, source: .meeting)
        showCopiedFeedback()
    }

    private func copyTranscriptToClipboard() {
        if usesMeetingReadingSurface,
            !activeTranscription.isTranscriptEdited,
            !cachedReadingTurns.isEmpty
        {
            TranscriptResultActions.copyText(
                MeetingTranscriptDocumentRenderer.markdown(cachedReadingDocument),
                source: .meeting
            )
        } else {
            TranscriptResultActions.copyText(transcriptText)
        }
        showCopiedFeedback()
    }

    private func showCopiedFeedback() {
        copiedResetTask?.cancel()
        withAnimation(DesignSystem.Animation.hoverTransition) { copied = true }
        copiedResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(DesignSystem.Animation.hoverTransition) { copied = false }
        }
    }

    private var hasTimestamps: Bool {
        activeTranscription.hasWordTimestamps
    }

    private var hasAlignedTimestampsForExport: Bool {
        hasTimestamps && !hasEditedTranscript
    }

    private var hasSpeakerLabelsForExport: Bool {
        !hasEditedTranscript && activeTranscription.hasSpeakerLabeledWords
    }

    /// Whether "Include timestamps" applies to the current selection: the format
    /// must take transcript options *and* the transcript must have aligned
    /// timestamps to include.
    private var canIncludeTimestampsOption: Bool {
        selectedExportFormat.supportsTranscriptOptions && hasAlignedTimestampsForExport
    }

    private var canIncludeSpeakerLabelsOption: Bool {
        selectedExportFormat.supportsTranscriptOptions && hasSpeakerLabelsForExport
    }

    /// Caption shown under a disabled "Include timestamps" toggle. `nil` when the
    /// option is available, or when the format takes no options (the section is
    /// hidden in that case, so no caption is needed).
    private var timestampsUnavailableReason: String? {
        guard selectedExportFormat.supportsTranscriptOptions,
              !hasAlignedTimestampsForExport else { return nil }
        if !hasTimestamps { return "This transcript has no word timestamps." }
        return "Unavailable after editing the transcript text."
    }

    private var speakerLabelsUnavailableReason: String? {
        guard selectedExportFormat.supportsTranscriptOptions,
              !hasSpeakerLabelsForExport else { return nil }
        if activeTranscription.hasSpeakerLabeledWords {
            return "Unavailable after editing the transcript text."
        }
        return "This transcript has no speaker labels."
    }

    private var resolvedTranscriptExportOptions: TranscriptExportOptions {
        transcriptExportOptions.resolved(
            canIncludeTimestamps: hasAlignedTimestampsForExport,
            canIncludeSpeakerLabels: hasSpeakerLabelsForExport
        )
    }

    private var exportFormatOrder: [TranscriptExportFormat] {
        [.txt, .md, .srt, .vtt, .dapt, .json, .pdf, .docx]
    }

    private var exportOptionsPopover: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Label("Export Transcript", systemImage: "arrow.down.doc")
                    .font(DesignSystem.Typography.body.bold())

                Spacer()

                Button {
                    showingExportOptions = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close export options")
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Format")
                    .font(DesignSystem.Typography.caption.weight(.medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(exportFormatOrder) { format in
                        Button {
                            selectedExportFormat = format
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: format.iconName)
                                    .frame(width: 16)
                                Text(format.shortName)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: 0)
                            }
                            .font(DesignSystem.Typography.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedExportFormat == format
                                          ? DesignSystem.Colors.accent.opacity(0.14)
                                          : DesignSystem.Colors.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        selectedExportFormat == format
                                        ? DesignSystem.Colors.accent.opacity(0.7)
                                        : DesignSystem.Colors.border.opacity(0.7),
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // The Options toggles apply only to Text/Markdown. Other formats
            // have fixed mappings, so showing disabled toggles would be noise.
            if selectedExportFormat.supportsTranscriptOptions {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Options")
                        .font(DesignSystem.Typography.caption.weight(.medium))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    exportOptionToggle(
                        "Include timestamps",
                        isOn: $transcriptExportOptions.includeTimestamps,
                        isEnabled: canIncludeTimestampsOption,
                        unavailableReason: timestampsUnavailableReason
                    )

                    exportOptionToggle(
                        "Include speaker labels",
                        isOn: $transcriptExportOptions.includeSpeakerLabels,
                        isEnabled: canIncludeSpeakerLabelsOption,
                        unavailableReason: speakerLabelsUnavailableReason
                    )

                    Toggle("Include metadata", isOn: $transcriptExportOptions.includeMetadata)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    showingExportOptions = false
                    exportToDownloads(format: selectedExportFormat)
                } label: {
                    Label("Export", systemImage: "arrow.down.doc")
                }
                .parakeetAction(.primaryProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(width: 380)
    }

    /// An export option toggle that shows its *effective* state. When the option
    /// is unavailable it renders unchecked and disabled — rather than checked and
    /// greyed, which reads as "forced on" and contradicts the export, which omits
    /// the missing data. An optional caption explains why it is unavailable.
    @ViewBuilder
    private func exportOptionToggle(
        _ title: String,
        isOn: Binding<Bool>,
        isEnabled: Bool,
        unavailableReason: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: Binding(
                get: { isEnabled && isOn.wrappedValue },
                set: { isOn.wrappedValue = $0 }
            ))
            .disabled(!isEnabled)

            if let unavailableReason {
                Text(unavailableReason)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
    }

    // MARK: - Export Confirmation Popover

    @ViewBuilder
    private func exportConfirmationPopover(_ confirmation: ExportConfirmation) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.Colors.successGreen)

                VStack(alignment: .leading, spacing: 2) {
                    Text(confirmation.title)
                        .font(DesignSystem.Typography.body.bold())
                    Text(confirmation.url.lastPathComponent)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    dismissTask?.cancel()
                    dismissTask = nil
                    exportConfirmation = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close export confirmation")
                .accessibilityHint("Dismisses the export confirmation popover")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([confirmation.url])
                dismissTask?.cancel()
                dismissTask = nil
                exportConfirmation = nil
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .font(DesignSystem.Typography.caption)
            }
            .parakeetAction(.secondary)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(minWidth: 220)
    }

    private func exportGenerationToDownloads(promptResult: PromptResult, format: TranscriptExportFormat) {
        let source = activeTranscription
        do {
            let fileURL = try TranscriptResultActions.exportPromptResultToDownloads(
                promptResult: promptResult,
                source: source,
                format: format
            )
            exportErrorMessage = nil
            SoundManager.shared.play(.transcriptionComplete)
            dismissTask?.cancel()
            exportConfirmation = ExportConfirmation(
                url: fileURL,
                title: "Exported \(format.displayName)"
            )
            dismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5.0))
                guard !Task.isCancelled else { return }
                exportConfirmation = nil
            }
        } catch let cocoaError as CocoaError where cocoaError.code == .fileNoSuchFile {
            exportErrorMessage = "Your Downloads folder could not be found."
            SoundManager.shared.play(.errorSoft)
        } catch {
            exportErrorMessage = error.localizedDescription
            SoundManager.shared.play(.errorSoft)
        }
    }

    private func exportToDownloads(format: TranscriptExportFormat) {
        // Use the ViewModel's copy which reflects any in-flight renames
        let source = activeTranscription
        do {
            let readingDocument =
                usesMeetingReadingSurface && !cachedReadingDocument.turns.isEmpty
                ? cachedReadingDocument
                : nil
            let fileURL = try TranscriptResultActions.exportTranscriptToDownloads(
                transcription: source,
                format: format,
                options: format.supportsTranscriptOptions ? resolvedTranscriptExportOptions : .default,
                meetingReadingDocument: readingDocument
            )
            exportErrorMessage = nil
            SoundManager.shared.play(.transcriptionComplete)
            dismissTask?.cancel()
            exportConfirmation = ExportConfirmation(
                url: fileURL,
                title: "Exported \(format.displayName)"
            )
            dismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5.0))
                guard !Task.isCancelled else { return }
                exportConfirmation = nil
            }
        } catch let cocoaError as CocoaError where cocoaError.code == .fileNoSuchFile {
            exportErrorMessage = "Your Downloads folder could not be found."
            SoundManager.shared.play(.errorSoft)
        } catch {
            exportErrorMessage = error.localizedDescription
            SoundManager.shared.play(.errorSoft)
        }
    }

    /// Drives the "Save Audio As…" item in the meeting action bar's
    /// Audio menu. Reuses the existing exportConfirmation popover on
    /// success and the existing exportErrorMessage alert on failure.
    private func saveMeetingAudioFromActionBar() {
        let source = activeTranscription
        Task { @MainActor in
            do {
                let outcome = try await MeetingAudioActions.runSaveAudioPanel(for: source)
                switch outcome {
                case .saved(let destination):
                    SoundManager.shared.play(.transcriptionComplete)
                    dismissTask?.cancel()
                    exportConfirmation = ExportConfirmation(
                        url: destination,
                        title: "Saved Audio"
                    )
                    dismissTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(5.0))
                        guard !Task.isCancelled else { return }
                        exportConfirmation = nil
                    }
                case .cancelled:
                    break
                case .sourceUnavailable:
                    exportErrorMessage = "The meeting audio file is no longer available."
                    SoundManager.shared.play(.errorSoft)
                }
            } catch {
                exportErrorMessage = error.localizedDescription
                SoundManager.shared.play(.errorSoft)
            }
        }
    }

    private func deleteMeetingAudioFromActionBar() {
        viewModel.deleteMeetingAudio(activeTranscription)
    }

    private func formatTimestamp(ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct EngineOptionCard: View {
    let selection: SpeechEngineSelection
    let nemotronVariant: NemotronModelVariant
    let parakeetVariant: ParakeetModelVariant
    let isPrimary: Bool
    /// When this is the primary card, whether it names the engine that produced
    /// the transcript ("Original") rather than a fall-back to the user's current
    /// default ("Current"). Ignored on non-primary cards.
    let primaryReflectsTranscriptEngine: Bool
    let advisory: String?
    let onSelect: () -> Void

    @State private var hovering = false

    private var iconName: String {
        switch selection.engine {
        case .parakeet: "bolt.fill"
        case .nemotron: "sparkles"
        case .whisper: "globe"
        case .cohere: "waveform"
        }
    }

    private var subtitle: String {
        switch selection.engine {
        case .parakeet:
            switch parakeetVariant {
            case .v3: "Fast local default • word timestamps"
            case .v2: "English stability • word timestamps"
            case .unified: "Readable English • word timestamps"
            }
        case .nemotron:
            nemotronVariant.isEnglishOnly
                ? "Beta English streaming • quality still being validated"
                : "Beta multilingual streaming • quality varies by language"
        case .whisper:
            "Broad-language fallback • files and saved audio"
        case .cohere:
            "Batch plain text • no timestamps or speaker labels"
        }
    }

    private var languageDetail: String? {
        guard selection.engine == .whisper || selection.engine == .nemotron else { return nil }
        if selection.engine == .nemotron, nemotronVariant.isEnglishOnly {
            // The English-only build ignores language hints.
            return "Language: English"
        }
        let language = selection.language ?? "auto-detect"
        return "Language: \(language)"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 22, height: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(selection.engine.displayName)
                            .font(DesignSystem.Typography.body.weight(.semibold))
                            .foregroundStyle(titleColor)
                        if isPrimary {
                            EngineBadge(
                                text: primaryReflectsTranscriptEngine ? "Original" : "Current",
                                tint: DesignSystem.Colors.accent
                            )
                        }
                    }
                    .lineLimit(1)

                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let languageDetail {
                        Text(languageDetail)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }

                    if let advisory {
                        Text(advisory)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, DesignSystem.Spacing.sm + 2)
            .padding(.horizontal, DesignSystem.Spacing.sm + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(DesignSystem.Animation.hoverTransition) {
                hovering = isHovering
            }
        }
        .help(helpText)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text(accessibilityHint))
    }

    private var helpText: String {
        if let advisory {
            return "\(advisory) Rerun with \(selection.engine.displayName)."
        }
        return "Rerun with \(selection.engine.displayName)."
    }

    private var iconColor: Color {
        DesignSystem.Colors.accent
    }

    private var titleColor: Color {
        DesignSystem.Colors.textPrimary
    }

    private var backgroundFill: Color {
        return hovering ? DesignSystem.Colors.accentLight : DesignSystem.Colors.surfaceElevated
    }

    private var borderColor: Color {
        return hovering ? DesignSystem.Colors.accent.opacity(0.5) : DesignSystem.Colors.border
    }

    private var accessibilityLabel: String {
        var parts = [selection.engine.displayName]
        if isPrimary {
            parts.append(primaryReflectsTranscriptEngine ? "engine used for this transcript" : "current engine")
        }
        return parts.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        if let advisory {
            return "\(advisory) Reruns this transcription with \(selection.engine.displayName)."
        }
        return "Reruns this transcription with \(selection.engine.displayName)."
    }
}

private struct EngineBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 0.5)
            )
    }
}

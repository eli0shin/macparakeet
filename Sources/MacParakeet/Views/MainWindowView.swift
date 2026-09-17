import SwiftUI
import MacParakeetCore
import MacParakeetViewModels

enum SidebarItem: String, CaseIterable, Identifiable {
    case transcribe = "Transcribe"
    case library = "Library"
    case dictations = "Dictations"
    case meetings = "Meetings"
    case transforms = "Transforms"
    case vocabulary = "Vocabulary"
    case feedback = "Feedback"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .transcribe: return "waveform"
        case .meetings: return "person.2.wave.2"
        case .library: return "square.grid.2x2"
        case .dictations: return "clock.arrow.circlepath"
        case .transforms: return "wand.and.stars"
        case .vocabulary: return "book.fill"
        case .feedback: return "bubble.left.and.text.bubble.right"
        case .settings: return "gearshape"
        }
    }

    /// Primary features — the core things users do. Library remains the
    /// universal archive; Meetings is the workflow space for live/upcoming
    /// and saved meeting work.
    static var primaryItems: [SidebarItem] {
        var items: [SidebarItem] = [.transcribe, .library, .dictations]
        if AppFeatures.meetingRecordingEnabled {
            items.append(.meetings)
        }
        return items
    }

    /// Configuration and support items. Transforms (ADR-022) is inserted
    /// here at runtime when `AppFeatures.transformsEnabled == true`.
    static var configItems: [SidebarItem] {
        var items: [SidebarItem] = [.vocabulary, .feedback, .settings]
        if AppFeatures.transformsEnabled {
            items.insert(.transforms, at: 0)
        }
        return items
    }
}

struct MainWindowView: View {
    @Bindable var state: MainWindowState
    @State private var showingOtherProcessingJobs = false

    let transcriptionViewModel: TranscriptionViewModel
    let historyViewModel: DictationHistoryViewModel
    let settingsViewModel: SettingsViewModel
    let llmSettingsViewModel: LLMSettingsViewModel
    let chatViewModel: TranscriptChatViewModel
    let promptResultsViewModel: PromptResultsViewModel
    let promptsViewModel: PromptsViewModel
    let transformsViewModel: TransformsViewModel
    let customWordsViewModel: CustomWordsViewModel
    let textSnippetsViewModel: TextSnippetsViewModel
    let vocabularyBackupViewModel: VocabularyBackupViewModel
    let feedbackViewModel: FeedbackViewModel
    let libraryViewModel: TranscriptionLibraryViewModel
    let meetingsWorkspaceViewModel: MeetingsWorkspaceViewModel
    let meetingPillViewModel: MeetingRecordingPillViewModel
    @Bindable var offlineProcessingViewModel: OfflineProcessingViewModel
    let onRecordMeeting: () -> Void
    let onRecordMeetingFromWorkspace: () -> Void
    let onPauseToggleMeeting: (() -> Void)?
    /// Routed to `AppHotkeyCoordinator.suspend` / `resume` while a hotkey
    /// recorder is active. Passed through to `SettingsView`.
    let onHotkeyRecordingStateChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $state.selectedItem) {
                    Section {
                        ForEach(SidebarItem.primaryItems) { item in
                            MainSidebarItemRow(item: item) {
                                state.navigateFromSidebar(
                                    to: item,
                                    libraryViewModel: libraryViewModel,
                                    transcriptionViewModel: transcriptionViewModel,
                                    historyViewModel: historyViewModel
                                )
                            }
                            .tag(item)
                        }
                    }

                    Section {
                        ForEach(SidebarItem.configItems) { item in
                            MainSidebarItemRow(item: item) {
                                state.navigateFromSidebar(
                                    to: item,
                                    libraryViewModel: libraryViewModel,
                                    transcriptionViewModel: transcriptionViewModel,
                                    historyViewModel: historyViewModel
                                )
                            }
                                .tag(item)
                        }
                    }
                }
                .listStyle(.sidebar)
                .tint(DesignSystem.Colors.accent)
                .navigationSplitViewColumnWidth(min: 170, ideal: DesignSystem.Layout.sidebarMinWidth, max: 240)
            } detail: {
                Group {
                    switch state.selectedItem {
                    case .transcribe:
                        TranscribeView(
                            viewModel: transcriptionViewModel,
                            chatViewModel: chatViewModel,
                            promptResultsViewModel: promptResultsViewModel,
                            promptsViewModel: promptsViewModel,
                            meetingPillViewModel: meetingPillViewModel,
                            meetingPermissionState: meetingPermissionState,
                            showingProgressDetail: $state.showingProgressDetail,
                            onRecordMeeting: onRecordMeeting,
                            onPauseToggleMeeting: onPauseToggleMeeting,
                            onRefreshPermissions: settingsViewModel.refreshPermissions
                        )
                    case .meetings:
                        MeetingsView(
                            viewModel: meetingsWorkspaceViewModel,
                            customWords: customWordsViewModel.words,
                            onRecordMeeting: {
                                onRecordMeetingFromWorkspace()
                            },
                            onPauseToggleMeeting: onPauseToggleMeeting,
                            onOpenCalendarSettings: {
                                state.navigateToSettings(tab: .capture, anchor: "meeting")
                            },
                            onOpenAISettings: {
                                state.navigateToSettings(tab: .ai)
                            },
                            onRecoverMeetings: {
                                settingsViewModel.requestPendingMeetingRecovery()
                            },
                            onSelectMeeting: { transcription in
                                transcriptionViewModel.currentTranscription = transcription
                                state.navigateToTranscription(from: .meetings)
                            }
                        )
                    case .library:
                        if let transcription = transcriptionViewModel.currentTranscription {
                            TranscriptResultView(
                                transcription: transcription,
                                viewModel: transcriptionViewModel,
                                chatViewModel: chatViewModel,
                                promptResultsViewModel: promptResultsViewModel,
                                promptsViewModel: promptsViewModel,
                                customWords: customWordsViewModel.words,
                                onBack: {
                                    if let current = transcriptionViewModel.currentTranscription {
                                        libraryViewModel.syncListMetadata(from: current)
                                    }
                                    transcriptionViewModel.showInputPortal()
                                },
                                onStartNew: {
                                    transcriptionViewModel.showInputPortal()
                                    state.selectedItem = .transcribe
                                },
                                onRetranscribe: { original, speechEngineOverride in
                                    transcriptionViewModel.retranscribe(
                                        original, speechEngineOverride: speechEngineOverride)
                                },
                                onSetUpAI: {
                                    state.navigateToSettings(tab: .ai)
                                },
                                offlineProcessingViewModel: offlineProcessingViewModel
                            )
                        } else {
                            TranscriptionLibraryView(
                                viewModel: libraryViewModel,
                                primaryActionTitle: "New Transcription",
                                onPrimaryAction: {
                                    transcriptionViewModel.showInputPortal()
                                    state.selectedItem = .transcribe
                                },
                                customWords: customWordsViewModel.words
                            ) { transcription in
                                transcriptionViewModel.currentTranscription = transcription
                            }
                        }
                    case .dictations:
                        DictationHistoryView(viewModel: historyViewModel)
                    case .transforms:
                        TransformsView(
                            viewModel: transformsViewModel,
                            reservedHotkeys: transformReservedHotkeys,
                            llmConfiguredAction: { state.navigateToSettings(tab: .ai) },
                            onEdit: { state.editingTransform = $0 },
                            onCreate: { state.isCreatingTransform = true },
                            onBindingsChanged: {
                                NotificationCenter.default.post(name: .transformsBindingsChanged, object: nil)
                            }
                        )
                        .sheet(isPresented: $state.isCreatingTransform) {
                            TransformEditorSheetHost(
                                mode: .create,
                                existingPrompts: transformsViewModel.allPrompts,
                                reservedHotkeys: transformReservedHotkeys,
                                onShortcutRecordingStateChanged: onHotkeyRecordingStateChanged,
                                onSave: { prompt in
                                    Task {
                                        if await transformsViewModel.save(prompt) {
                                            state.isCreatingTransform = false
                                            NotificationCenter.default.post(
                                                name: .transformsBindingsChanged, object: nil)
                                        }
                                    }
                                },
                                onCancel: { state.isCreatingTransform = false },
                                onReset: nil
                            )
                        }
                        .sheet(item: $state.editingTransform) { transform in
                            TransformEditorSheetHost(
                                mode: .edit(transform),
                                existingPrompts: transformsViewModel.allPrompts,
                                reservedHotkeys: transformReservedHotkeys,
                                onShortcutRecordingStateChanged: onHotkeyRecordingStateChanged,
                                onSave: { prompt in
                                    Task {
                                        if await transformsViewModel.save(prompt) {
                                            state.editingTransform = nil
                                            NotificationCenter.default.post(
                                                name: .transformsBindingsChanged, object: nil)
                                        }
                                    }
                                },
                                onCancel: { state.editingTransform = nil },
                                onReset: transform.isBuiltIn
                                    ? {
                                        Task {
                                            if await transformsViewModel.resetBuiltIn(
                                                transform,
                                                reservedHotkeys: transformReservedHotkeys
                                            ) {
                                                state.editingTransform = nil
                                                NotificationCenter.default.post(
                                                    name: .transformsBindingsChanged, object: nil)
                                            } else {
                                                state.editingTransform = nil
                                            }
                                        }
                                    } : nil
                            )
                        }
                    case .vocabulary:
                        VocabularyView(
                            settingsViewModel: settingsViewModel,
                            customWordsViewModel: customWordsViewModel,
                            textSnippetsViewModel: textSnippetsViewModel,
                            backupViewModel: vocabularyBackupViewModel
                        )
                    case .feedback:
                        FeedbackView(viewModel: feedbackViewModel)
                    case .settings:
                        SettingsView(
                            viewModel: settingsViewModel,
                            llmSettingsViewModel: llmSettingsViewModel,
                            transformHotkeys: transformsViewModel.transforms,
                            requestedTab: state.requestedSettingsTab,
                            requestedAnchor: state.requestedSettingsAnchor,
                            requestedTabRevision: state.requestedSettingsTabRevision,
                            onRequestedTabConsumed: {
                                state.consumeRequestedSettingsTab()
                            },
                            onHotkeyRecordingStateChanged: onHotkeyRecordingStateChanged
                        )
                    }
                }
            }

            if !offlineProcessingViewModel.jobs.isEmpty {
                universalProcessingBottomBar
            }
        }
        .frame(
            minWidth: 860,
            minHeight: DesignSystem.Layout.windowMinHeight
        )
        .onChange(of: transcriptionViewModel.isTranscribing) { _, isTranscribing in
            if !isTranscribing {
                state.showingProgressDetail = false
            }
        }
        .onChange(of: transcriptionViewModel.currentTranscription?.id) { _, newID in
            if newID != nil {
                state.selectedItem = .library
            }
        }
        .onChange(of: state.selectedItem) { _, newItem in
            // Bulk-selection mode is a History-only affordance living on a
            // process-lifetime singleton, so tear it down at the navigation
            // boundary when the user leaves the Dictations section. Handled here
            // rather than via `DictationHistoryView.onDisappear`, which can fire
            // on transient macOS view-lifecycle events and reset an active
            // selection mid-browse.
            if newItem != .dictations {
                historyViewModel.exitBulkSelection()
            }
        }
    }

    private var transformReservedHotkeys: [TransformShortcutReservedHotkey] {
        var reserved: [TransformShortcutReservedHotkey] = [
            TransformShortcutReservedHotkey(
                name: "hands-free dictation",
                trigger: settingsViewModel.hotkeyTrigger,
                conflictMode: .bareModifierDictation
            ),
            TransformShortcutReservedHotkey(
                name: "push to talk",
                trigger: settingsViewModel.pushToTalkHotkeyTrigger,
                conflictMode: .bareModifierDictation
            ),
            TransformShortcutReservedHotkey(
                name: "file transcription", trigger: settingsViewModel.fileTranscriptionHotkeyTrigger),
            TransformShortcutReservedHotkey(
                name: "video URL transcription", trigger: settingsViewModel.youtubeTranscriptionHotkeyTrigger),
        ]
        if AppFeatures.meetingRecordingEnabled {
            reserved.append(
                TransformShortcutReservedHotkey(
                    name: "meeting recording", trigger: settingsViewModel.meetingHotkeyTrigger))
        }
        return reserved.filter { !$0.trigger.isDisabled }
    }

    private var meetingPermissionState: MeetingRecordingTile.PermissionState {
        MeetingRecordingTile.PermissionState(
            microphoneGranted: settingsViewModel.microphoneGranted,
            screenRecordingGranted: settingsViewModel.screenRecordingGranted,
            sourceMode: settingsViewModel.meetingAudioSourceMode
        )
    }

    private var universalProcessingBottomBar: some View {
        VStack(spacing: 0) {
            if showingOtherProcessingJobs, !offlineProcessingViewModel.otherJobs.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack {
                        Text("OTHER PROCESSING")
                        Spacer()
                        Text("\(offlineProcessingViewModel.otherJobs.count) ACTIVE")
                    }
                    .font(DesignSystem.Typography.micro.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                    ForEach(Array(offlineProcessingViewModel.otherJobs)) { job in
                        processingJobRow(job, isFocused: false)
                            .padding(.horizontal, DesignSystem.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                                    .fill(DesignSystem.Colors.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                                    .strokeBorder(DesignSystem.Colors.border.opacity(0.7), lineWidth: 0.5)
                            )
                    }
                }
                .padding(DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.contentBackground)
                .overlay(alignment: .bottom) { Divider() }
            }

            if let focusedJob = offlineProcessingViewModel.focusedJob {
                processingJobRow(focusedJob, isFocused: true)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.vertical, DesignSystem.Spacing.sm)
            }
        }
        .background(DesignSystem.Colors.cardBackground)
        .overlay(alignment: .top) { Divider() }
    }

    private func processingJobRow(
        _ job: OfflineProcessingViewModel.Job,
        isFocused: Bool
    ) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: processingIcon(for: job.operation))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(job.operation.locality == .ai ? Color.purple : DesignSystem.Colors.accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((job.operation.locality == .ai ? Color.purple : DesignSystem.Colors.accent).opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(job.title)
                        .font(DesignSystem.Typography.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(job.operation.locality == .ai ? "AI" : "On-device")
                        .font(DesignSystem.Typography.micro.weight(.bold))
                        .foregroundStyle(job.operation.locality == .ai ? Color.purple : DesignSystem.Colors.successGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                (job.operation.locality == .ai ? Color.purple : DesignSystem.Colors.successGreen)
                                    .opacity(0.1)
                            )
                        )
                }

                Text(job.operation.title)
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            Group {
                if let fraction = job.fraction {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .tint(DesignSystem.Colors.accent)
                            .frame(width: 110)
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(DesignSystem.Typography.micro.monospacedDigit().weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                } else {
                    Text(job.operation.detail)
                        .font(DesignSystem.Typography.micro)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                }
            }

            if isFocused, !offlineProcessingViewModel.otherJobs.isEmpty {
                Button(showingOtherProcessingJobs ? "Hide other jobs" : "\(offlineProcessingViewModel.otherJobs.count) more") {
                    showingOtherProcessingJobs.toggle()
                }
                .parakeetAction(.secondary)
                .controlSize(.small)
            }

            processingAction(for: job)
        }
        .frame(minHeight: isFocused ? 42 : 38)
    }

    @ViewBuilder
    private func processingAction(for job: OfflineProcessingViewModel.Job) -> some View {
        if job.canCancel {
            Button("Cancel") {
                offlineProcessingViewModel.cancel(id: job.id)
            }
            .parakeetAction(.secondary)
            .controlSize(.small)
        } else if transcriptionViewModel.currentTranscription?.id != job.itemID {
            Button("View") {
                if let itemID = job.itemID,
                   transcriptionViewModel.selectTranscription(id: itemID) {
                    state.navigateToTranscription(from: .library)
                } else {
                    state.selectedItem = .transcribe
                }
            }
            .parakeetAction(.secondary)
            .controlSize(.small)
        }
    }

    private func processingIcon(for operation: OfflineProcessingViewModel.Operation) -> String {
        switch operation {
        case .preparing, .preparingSpeechModel: "cpu"
        case .waiting: "clock"
        case .downloading: "arrow.down.circle"
        case .converting: "waveform.path.ecg"
        case .transcribing: "waveform"
        case .identifyingSpeakers, .adjustingSpeakers: "person.2"
        case .formatting, .finalizing: "doc.text"
        case .generatingTitle, .generatingResult: "sparkles"
        }
    }
}

private struct TransformEditorSheetHost: View {
    @State private var editorViewModel: TransformEditorViewModel

    let existingPrompts: [Prompt]
    let reservedHotkeys: [TransformShortcutReservedHotkey]
    let onShortcutRecordingStateChanged: (Bool) -> Void
    let onSave: (Prompt) -> Void
    let onCancel: () -> Void
    let onReset: (() -> Void)?

    init(
        mode: TransformEditorViewModel.Mode,
        existingPrompts: [Prompt],
        reservedHotkeys: [TransformShortcutReservedHotkey],
        onShortcutRecordingStateChanged: @escaping (Bool) -> Void,
        onSave: @escaping (Prompt) -> Void,
        onCancel: @escaping () -> Void,
        onReset: (() -> Void)?
    ) {
        _editorViewModel = State(initialValue: TransformEditorViewModel(mode: mode))
        self.existingPrompts = existingPrompts
        self.reservedHotkeys = reservedHotkeys
        self.onShortcutRecordingStateChanged = onShortcutRecordingStateChanged
        self.onSave = onSave
        self.onCancel = onCancel
        self.onReset = onReset
    }

    var body: some View {
        TransformEditorSheet(
            viewModel: editorViewModel,
            existingPrompts: existingPrompts,
            reservedHotkeys: reservedHotkeys,
            onShortcutRecordingStateChanged: onShortcutRecordingStateChanged,
            onSave: onSave,
            onCancel: onCancel,
            onReset: onReset
        )
    }
}

struct MainSidebarItemRow: View {
    let item: SidebarItem
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Label(item.rawValue, systemImage: item.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarItemLabel: View {
    let item: SidebarItem

    var body: some View {
        Label(item.rawValue, systemImage: item.icon)
    }
}

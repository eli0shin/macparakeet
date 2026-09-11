import AppKit
import OSLog
import SwiftUI
import MacParakeetCore
import MacParakeetViewModels

@MainActor
final class AppWindowCoordinator: NSObject, NSWindowDelegate {
    private let mainWindowState: MainWindowState
    private let transcriptionViewModel: TranscriptionViewModel
    private let historyViewModel: DictationHistoryViewModel
    private let settingsViewModel: SettingsViewModel
    private let llmSettingsViewModel: LLMSettingsViewModel
    private let chatViewModel: TranscriptChatViewModel
    private let promptResultsViewModel: PromptResultsViewModel
    private let promptsViewModel: PromptsViewModel
    private let transformsViewModel: TransformsViewModel
    private let customWordsViewModel: CustomWordsViewModel
    private let textSnippetsViewModel: TextSnippetsViewModel
    private let vocabularyBackupViewModel: VocabularyBackupViewModel
    private let feedbackViewModel: FeedbackViewModel
    private let libraryViewModel: TranscriptionLibraryViewModel
    private let meetingsWorkspaceViewModel: MeetingsWorkspaceViewModel
    private let meetingPillViewModel: MeetingRecordingPillViewModel
    private let onRecordMeeting: () -> Void
    private let onRecordMeetingFromWorkspace: () -> Void
    private let onPauseToggleMeeting: (() -> Void)?
    private let onHotkeyRecordingStateChanged: (Bool) -> Void
    private let onQuit: () -> Void
    private let logger = Logger(subsystem: "com.macparakeet.app", category: "MainWindow")

    private var mainWindow: NSWindow?

    init(
        mainWindowState: MainWindowState,
        transcriptionViewModel: TranscriptionViewModel,
        historyViewModel: DictationHistoryViewModel,
        settingsViewModel: SettingsViewModel,
        llmSettingsViewModel: LLMSettingsViewModel,
        chatViewModel: TranscriptChatViewModel,
        promptResultsViewModel: PromptResultsViewModel,
        promptsViewModel: PromptsViewModel,
        transformsViewModel: TransformsViewModel,
        customWordsViewModel: CustomWordsViewModel,
        textSnippetsViewModel: TextSnippetsViewModel,
        vocabularyBackupViewModel: VocabularyBackupViewModel,
        feedbackViewModel: FeedbackViewModel,
        libraryViewModel: TranscriptionLibraryViewModel,
        meetingsWorkspaceViewModel: MeetingsWorkspaceViewModel,
        meetingPillViewModel: MeetingRecordingPillViewModel,
        onRecordMeeting: @escaping () -> Void,
        onRecordMeetingFromWorkspace: @escaping () -> Void,
        onPauseToggleMeeting: (() -> Void)? = nil,
        onHotkeyRecordingStateChanged: @escaping (Bool) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.mainWindowState = mainWindowState
        self.transcriptionViewModel = transcriptionViewModel
        self.historyViewModel = historyViewModel
        self.settingsViewModel = settingsViewModel
        self.llmSettingsViewModel = llmSettingsViewModel
        self.chatViewModel = chatViewModel
        self.promptResultsViewModel = promptResultsViewModel
        self.promptsViewModel = promptsViewModel
        self.transformsViewModel = transformsViewModel
        self.customWordsViewModel = customWordsViewModel
        self.textSnippetsViewModel = textSnippetsViewModel
        self.vocabularyBackupViewModel = vocabularyBackupViewModel
        self.feedbackViewModel = feedbackViewModel
        self.libraryViewModel = libraryViewModel
        self.meetingsWorkspaceViewModel = meetingsWorkspaceViewModel
        self.meetingPillViewModel = meetingPillViewModel
        self.onRecordMeeting = onRecordMeeting
        self.onRecordMeetingFromWorkspace = onRecordMeetingFromWorkspace
        self.onPauseToggleMeeting = onPauseToggleMeeting
        self.onHotkeyRecordingStateChanged = onHotkeyRecordingStateChanged
        self.onQuit = onQuit
    }

    func openMainWindow() {
        guard mainWindow == nil else { return }
        createMainWindow()
        guard let mainWindow else { return }
        mainWindow.orderFront(nil)
        logWindowEvent("open", window: mainWindow)
    }

    func openMainWindowToSettings(tab: SettingsTab? = nil) {
        mainWindowState.navigateToSettings(tab: tab)
        openMainWindow()
    }

    func handleAppReopen() -> Bool {
        false
    }

    func applyActivationPolicyFromSettings() {
        let menuBarOnly = settingsViewModel.menuBarOnlyMode
        let mode: NSApplication.ActivationPolicy = menuBarOnly ? .accessory : .regular
        NSApp.setActivationPolicy(mode)
    }

    func makeDockMenu() -> NSMenu {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "Open MacParakeet",
            action: #selector(dockOpenMainWindow),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(dockOpenSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit MacParakeet",
            action: #selector(dockQuit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func dockOpenMainWindow() {
        openMainWindow()
    }

    @objc private func dockOpenSettings() {
        openMainWindowToSettings()
    }

    @objc private func dockQuit() {
        onQuit()
    }

    private func createMainWindow() {
        let contentView = MainWindowView(
            state: mainWindowState,
            transcriptionViewModel: transcriptionViewModel,
            historyViewModel: historyViewModel,
            settingsViewModel: settingsViewModel,
            llmSettingsViewModel: llmSettingsViewModel,
            chatViewModel: chatViewModel,
            promptResultsViewModel: promptResultsViewModel,
            promptsViewModel: promptsViewModel,
            transformsViewModel: transformsViewModel,
            customWordsViewModel: customWordsViewModel,
            textSnippetsViewModel: textSnippetsViewModel,
            vocabularyBackupViewModel: vocabularyBackupViewModel,
            feedbackViewModel: feedbackViewModel,
            libraryViewModel: libraryViewModel,
            meetingsWorkspaceViewModel: meetingsWorkspaceViewModel,
            meetingPillViewModel: meetingPillViewModel,
            onRecordMeeting: onRecordMeeting,
            onRecordMeetingFromWorkspace: onRecordMeetingFromWorkspace,
            onPauseToggleMeeting: onPauseToggleMeeting,
            onHotkeyRecordingStateChanged: onHotkeyRecordingStateChanged
        )

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: DesignSystem.Layout.sidebarMinWidth + DesignSystem.Layout.contentMinWidth,
                height: DesignSystem.Layout.windowMinHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacParakeet"
        if !window.setFrameUsingName("MainWindow") {
            window.center()
        }
        window.setFrameAutosaveName("MainWindow")
        window.minSize = NSSize(
            width: DesignSystem.Layout.sidebarMinWidth + DesignSystem.Layout.contentMinWidth,
            height: DesignSystem.Layout.windowMinHeight
        )
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: contentView)
        window.delegate = self
        window.isReleasedWhenClosed = false

        mainWindow = window
    }

    func windowDidBecomeMain(_ notification: Notification) {
        logMainWindowNotification("became-main", notification: notification)
    }

    func windowDidResignMain(_ notification: Notification) {
        logMainWindowNotification("resigned-main", notification: notification)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        logMainWindowNotification("became-key", notification: notification)
    }

    func windowDidResignKey(_ notification: Notification) {
        logMainWindowNotification("resigned-key", notification: notification)
    }

    func windowDidMove(_ notification: Notification) {
        logMainWindowNotification("moved", notification: notification)
    }

    func windowDidResize(_ notification: Notification) {
        logMainWindowNotification("resized", notification: notification)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        logMainWindowNotification("miniaturized", notification: notification)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        logMainWindowNotification("deminiaturized", notification: notification)
    }

    func windowWillClose(_ notification: Notification) {
        // Retain the window and its hosting view. A later Open reuses both and
        // AppKit restores the saved frame without rebuilding the SwiftUI tree.
        logMainWindowNotification("will-close", notification: notification)
    }

    private func logMainWindowNotification(_ event: String, notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        logWindowEvent(event, window: window)
    }

    private func logWindowEvent(_ event: String, window: NSWindow) {
        let frame = window.frame
        logger.debug(
            "event=\(event, privacy: .public) visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) miniaturized=\(window.isMiniaturized) policy=\(NSApp.activationPolicy().rawValue) frame=(\(frame.origin.x),\(frame.origin.y),\(frame.width),\(frame.height))"
        )
    }
}

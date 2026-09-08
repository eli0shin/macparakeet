import SwiftUI

struct BulkTranscriptionSelectionBar: View {
    let selectedCount: Int
    let selectedMeetingAudioCount: Int
    let isMeetingContext: Bool
    let areAllVisibleSelected: Bool
    let isPerformingOperation: Bool
    var operationLabel = "Deleting..."
    var isExportDisabled = false
    let onSelectVisible: () -> Void
    let onClear: () -> Void
    let onCancel: () -> Void
    var onMove: (() -> Void)? = nil
    var onExport: (() -> Void)?
    let onDeleteAudioOnly: () -> Void
    let onDeleteItems: () -> Void

    private var showsAudioAction: Bool {
        isMeetingContext || selectedMeetingAudioCount > 0
    }

    private var deleteAudioTitle: String {
        if isMeetingContext {
            return "Remove Audio Only..."
        }
        return
            "Remove Audio for \(selectedMeetingAudioCount) \(selectedMeetingAudioCount == 1 ? "Meeting" : "Meetings")..."
    }

    private var deleteItemsTitle: String {
        isMeetingContext ? "Delete Meetings..." : "Delete Items..."
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalBar
            wrappedBar
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surfaceElevated)
        .overlay(alignment: .top) {
            Divider()
                .opacity(0.35)
        }
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.55)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isPerformingOperation ? operationLabel : "\(selectedCount) selected")
        // Resolve the bar's internal layout as one unit so the enclosing
        // selection-mode animation moves it as a cohesive block. Without this,
        // the container animation interpolates the inner `Spacer` from
        // collapsed to full width, sweeping the trailing action cluster (Cancel
        // first) from center to edge — a visible "Cancel flashes mid-bar"
        // artifact — and re-runs the nested ViewThatFits/FlowLayout every frame.
        .geometryGroup()
    }

    private var horizontalBar: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            selectionSummary

            Spacer(minLength: DesignSystem.Spacing.md)

            actionCluster
        }
        .frame(minHeight: 34)
    }

    private var wrappedBar: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            selectionSummary
            actionFlow
        }
    }

    private var selectionSummary: some View {
        HStack(spacing: 8) {
            if isPerformingOperation {
                ParakeetSpinner(.inline)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.accent)
            }

            Text(isPerformingOperation ? operationLabel : "\(selectedCount) selected")
                .font(DesignSystem.Typography.bodySmall.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.accentLight)
        )
        .accessibilityHidden(true)
    }

    private var actionCluster: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                utilityActions
                destructiveActions
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                utilityActions
                destructiveActions
            }
        }
    }

    private var utilityActions: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            cancelAction
            selectVisibleAction
            clearAction
            moveAction
            exportAction
        }
    }

    private var destructiveActions: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            if showsAudioAction {
                deleteAudioAction
            }
            deleteItemsAction
        }
    }

    private var actionFlow: some View {
        FlowLayout(spacing: DesignSystem.Spacing.sm) {
            cancelAction
            selectVisibleAction
            clearAction
            moveAction
            exportAction
            if showsAudioAction {
                deleteAudioAction
            }
            deleteItemsAction
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cancelAction: some View {
        SelectionBarActionButton(
            title: "Cancel",
            systemImage: "xmark",
            tone: .subtle,
            isDisabled: isPerformingOperation,
            usesEscapeShortcut: true,
            action: onCancel
        )
    }

    // Labeled "Select All" but scoped to the loaded rows by design: selection
    // (and therefore deletion) never reaches rows that aren't loaded yet. The
    // selected-count chip and the delete confirmation always state the exact
    // number, so the scope is explicit at the moment of action.
    private var selectVisibleAction: some View {
        SelectionBarActionButton(
            title: "Select All",
            systemImage: "checkmark.circle",
            tone: .utility,
            isDisabled: areAllVisibleSelected || isPerformingOperation,
            action: onSelectVisible
        )
    }

    private var clearAction: some View {
        SelectionBarActionButton(
            title: "Clear",
            systemImage: "xmark.circle",
            tone: .utility,
            isDisabled: selectedCount == 0 || isPerformingOperation,
            action: onClear
        )
    }

    @ViewBuilder
    private var moveAction: some View {
        if let onMove {
            SelectionBarActionButton(
                title: "Move to…",
                systemImage: "folder",
                tone: .utility,
                isDisabled: selectedCount == 0 || isPerformingOperation,
                action: onMove
            )
        }
    }

    @ViewBuilder
    private var exportAction: some View {
        if let onExport {
            SelectionBarActionButton(
                title: "Export...",
                systemImage: "arrow.down.doc",
                tone: .utility,
                isDisabled: isExportDisabled,
                action: onExport
            )
        }
    }

    private var deleteAudioAction: some View {
        SelectionBarActionButton(
            title: deleteAudioTitle,
            systemImage: "waveform.slash",
            tone: .destructive,
            isDisabled: selectedMeetingAudioCount == 0 || isPerformingOperation,
            role: .destructive,
            action: onDeleteAudioOnly
        )
    }

    private var deleteItemsAction: some View {
        SelectionBarActionButton(
            title: deleteItemsTitle,
            systemImage: "trash",
            tone: .destructive,
            isDisabled: selectedCount == 0 || isPerformingOperation,
            role: .destructive,
            action: onDeleteItems
        )
    }
}

private enum SelectionBarActionTone {
    case utility
    case destructive
    case subtle

    var actionRole: ParakeetActionRole {
        switch self {
        case .utility:
            return .secondary
        case .destructive:
            return .destructive
        case .subtle:
            return .subtle
        }
    }
}

private struct SelectionBarActionButton: View {
    let title: String
    let systemImage: String
    let tone: SelectionBarActionTone
    var isDisabled: Bool = false
    var usesEscapeShortcut: Bool = false
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Group {
            if usesEscapeShortcut {
                baseButton
                    .keyboardShortcut(.escape, modifiers: [])
            } else {
                baseButton
            }
        }
    }

    private var baseButton: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
        }
        .parakeetAction(tone.actionRole)
        .disabled(isDisabled)
    }
}

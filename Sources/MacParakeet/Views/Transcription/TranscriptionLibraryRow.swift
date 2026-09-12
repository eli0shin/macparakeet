import SwiftUI
import MacParakeetCore

private enum LibraryRowLayout {
    static let selectionWidth: CGFloat = 20
    static let typeWidth: CGFloat = 100
    static let folderWidth: CGFloat = 140
    static let actionWidth: CGFloat = 60
    static let horizontalPadding: CGFloat = 12
    static let columnSpacing: CGFloat = 12
}

struct LibraryRowHeader: View {
    let showsSelectionColumn: Bool

    var body: some View {
        HStack(spacing: LibraryRowLayout.columnSpacing) {
            if showsSelectionColumn {
                Color.clear
                    .frame(width: LibraryRowLayout.selectionWidth)
            }

            Text("Title")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Type")
                .frame(width: LibraryRowLayout.typeWidth, alignment: .leading)
            Text("Folder")
                .frame(width: LibraryRowLayout.folderWidth, alignment: .leading)
            Text("Actions")
                .frame(width: LibraryRowLayout.actionWidth, alignment: .trailing)
        }
        .font(DesignSystem.Typography.micro.weight(.bold))
        .foregroundStyle(DesignSystem.Colors.textSecondary)
        .textCase(.uppercase)
        .padding(.horizontal, LibraryRowLayout.horizontalPadding)
        .frame(minHeight: 34)
        .background(DesignSystem.Colors.surfaceElevated)
        .accessibilityHidden(true)
    }
}

struct TranscriptionLibraryRow<MenuContent: View>: View {
    let transcription: Transcription
    let folderName: String
    var searchText = ""
    var isSelected = false
    var showsSelectionControls = false
    let onTap: () -> Void
    @ViewBuilder let menuContent: () -> MenuContent

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: LibraryRowLayout.columnSpacing) {
            Button(action: onTap) {
                HStack(spacing: LibraryRowLayout.columnSpacing) {
                    if showsSelectionControls {
                        selectionIndicator
                            .frame(width: LibraryRowLayout.selectionWidth)
                    }

                    titleColumn
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Label(sourceDisplay.collapsedText, systemImage: sourceDisplay.systemImage)
                        .font(DesignSystem.Typography.bodySmall)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                        .frame(width: LibraryRowLayout.typeWidth, alignment: .leading)

                    highlightedText(folderName)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                        .frame(width: LibraryRowLayout.folderWidth, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityValue(showsSelectionControls ? (isSelected ? "Selected" : "Not selected") : "")
            .accessibilityHint(showsSelectionControls ? "Toggles selection" : "Opens transcription")

            Menu {
                menuContent()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: LibraryRowLayout.actionWidth, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Transcription actions")
            .accessibilityLabel("Actions for \(transcription.effectiveDisplayTitle)")
        }
        .padding(.horizontal, LibraryRowLayout.horizontalPadding)
        .padding(.vertical, 9)
        .frame(minHeight: 54)
        .background(rowBackground)
        .onHover { isHovered = $0 }
        .animation(DesignSystem.Animation.hoverTransition, value: isHovered)
        .animation(DesignSystem.Animation.hoverTransition, value: isSelected)
    }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if transcription.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .accessibilityLabel("Favorite")
                }

                highlightedText(transcription.effectiveDisplayTitle)
                    .font(DesignSystem.Typography.bodySmall.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
            }

            highlightedText(subtitle)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            DesignSystem.Colors.accentLight
        } else if isHovered {
            DesignSystem.Colors.rowHoverBackground
        } else {
            Color.clear
        }
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .fill(isSelected ? DesignSystem.Colors.accent : Color.clear)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.textTertiary.opacity(0.7),
                            lineWidth: 1.2
                        )
                }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.onAccent)
            }
        }
        .accessibilityHidden(true)
    }

    private var sourceDisplay: TranscriptionSourceDisplay {
        TranscriptionSourceDisplay.resolve(for: transcription)
    }

    private var subtitle: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let channelName = transcription.channelName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !query.isEmpty,
            UnicodeSearch.contains(channelName, normalizedQuery: UnicodeSearch.makeKey(query))
        {
            return channelName
        }
        if let snippet = transcription.derivedSnippet?.trimmingCharacters(in: .whitespacesAndNewlines),
            !snippet.isEmpty
        {
            return snippet
        }
        if let channelName = transcription.channelName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !channelName.isEmpty
        {
            return channelName
        }

        var parts = [transcription.createdAt.libraryRelativeFormatted]
        if let durationMs = transcription.durationMs {
            parts.append(durationMs.formattedDuration)
        }
        return parts.joined(separator: " · ")
    }

    @MainActor
    private func highlightedText(_ text: String) -> Text {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Text(text) }

        var result = Text("")
        var remainder = text[...]
        while let range = remainder.range(of: query, options: .caseInsensitive) {
            let prefix = String(remainder[..<range.lowerBound])
            if !prefix.isEmpty {
                result = result + Text(prefix)
            }
            result = result + Text(String(remainder[range])).bold()
            remainder = remainder[range.upperBound...]
        }
        if !remainder.isEmpty {
            result = result + Text(String(remainder))
        }
        return result
    }
}

private extension Date {
    var libraryRelativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

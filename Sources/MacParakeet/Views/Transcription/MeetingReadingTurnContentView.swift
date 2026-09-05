import SwiftUI
import MacParakeetCore

struct IdentifiedReadingTurn: Identifiable {
    let turn: ReadingTurn
    let scrollID: Int

    var id: ReadingTurnIdentity { turn.id }
}

func identifiedReadingTurns(_ turns: [ReadingTurn]) -> [IdentifiedReadingTurn] {
    turns.enumerated().map { index, turn in
        IdentifiedReadingTurn(turn: turn, scrollID: -2_000_000_000 + index)
    }
}

struct IdentifiedReadingTurnGroup: Identifiable {
    let overlap: ReadingTurnOverlap?
    let turns: [IdentifiedReadingTurn]

    var id: Int { turns[0].scrollID }
}

func identifiedReadingTurnGroups(
    _ turns: [IdentifiedReadingTurn]
) -> [IdentifiedReadingTurnGroup] {
    let overlapMembers = Dictionary(
        grouping: turns.compactMap { turn in
            turn.turn.overlap.map { ($0, turn) }
        },
        by: { $0.0 }
    )
    var emittedOverlaps: Set<ReadingTurnOverlap> = []
    var groups: [IdentifiedReadingTurnGroup] = []

    for turn in turns {
        guard let overlap = turn.turn.overlap else {
            groups.append(IdentifiedReadingTurnGroup(overlap: nil, turns: [turn]))
            continue
        }
        guard emittedOverlaps.insert(overlap).inserted else { continue }
        groups.append(
            IdentifiedReadingTurnGroup(
                overlap: overlap,
                turns: overlapMembers[overlap, default: []].map(\.1)
            )
        )
    }
    return groups
}

func readingTurnScrollTarget(
    for currentMs: Int,
    in turns: [IdentifiedReadingTurn]
) -> Int? {
    turns.last { identified in
        guard let startMs = identified.turn.timeRange?.startMs else { return false }
        return startMs <= currentMs
    }?.scrollID
}

struct MeetingReadingTurnContentView<SpeakerLabelContent: View>: View {
    let turns: [IdentifiedReadingTurn]
    let speakerColorMap: [String: Color]
    let speakerLabelContent: (String, String, Color, String, Bool) -> SpeakerLabelContent
    let activeScrollID: Int?
    let timestampLabel: (Int) -> String
    let isTimestampSeekable: Bool
    let onTimestampTap: (Int) -> Void
    let onCopyTurn: (ReadingTurn) -> Void
    var bodyFont: Font = DesignSystem.Typography.bodyLarge
    var highlightRangesByScrollID: [Int: [NSRange]] = [:]
    var currentHighlight: (id: Int, range: NSRange)?

    var body: some View {
        ForEach(identifiedReadingTurnGroups(turns)) { group in
            if group.overlap != nil {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Label("Simultaneous speech", systemImage: "waveform.path")
                        .font(DesignSystem.Typography.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.speakerColor(for: 1))

                    ForEach(group.turns) { identified in
                        card(for: identified)
                    }
                }
                .padding(DesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                        .fill(DesignSystem.Colors.speakerColor(for: 1).opacity(0.06))
                )
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignSystem.Colors.speakerColor(for: 1).opacity(0.75))
                        .frame(width: 3)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Simultaneous speech")
            } else if let identified = group.turns.first {
                card(for: identified)
            }
        }
    }

    private func card(for identified: IdentifiedReadingTurn) -> some View {
        MeetingReadingTurnCard(
            identified: identified,
            speakerColor: speakerColorMap[identified.turn.speakerId]
                ?? sourceColor(for: identified.turn.source),
            speakerLabelContent: speakerLabelContent,
            isActive: activeScrollID == identified.scrollID,
            timestampLabel: timestampLabel,
            isTimestampSeekable: isTimestampSeekable,
            onTimestampTap: onTimestampTap,
            onCopyTurn: onCopyTurn,
            bodyFont: bodyFont,
            highlightRanges: highlightRangesByScrollID[identified.scrollID] ?? [],
            currentRange: currentHighlight?.id == identified.scrollID
                ? currentHighlight?.range
                : nil
        )
        .id(identified.scrollID)
    }

    private func sourceColor(for source: ReadingTurnSource) -> Color {
        switch source {
        case .microphone:
            return DesignSystem.Colors.accent
        case .system:
            return DesignSystem.Colors.speakerColor(for: 1)
        case .unknown:
            return DesignSystem.Colors.textTertiary
        }
    }
}

private struct MeetingReadingTurnCard<SpeakerLabelContent: View>: View {
    let identified: IdentifiedReadingTurn
    let speakerColor: Color
    let speakerLabelContent: (String, String, Color, String, Bool) -> SpeakerLabelContent
    let isActive: Bool
    let timestampLabel: (Int) -> String
    let isTimestampSeekable: Bool
    let onTimestampTap: (Int) -> Void
    let onCopyTurn: (ReadingTurn) -> Void
    let bodyFont: Font
    let highlightRanges: [NSRange]
    let currentRange: NSRange?

    @State private var isHovering = false

    private var turn: ReadingTurn { identified.turn }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Circle()
                    .fill(speakerColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)

                speakerLabelContent(
                    turn.speakerId,
                    turn.speakerLabel,
                    speakerColor,
                    renameContextID,
                    isHovering
                )

                if let startMs = turn.timeRange?.startMs {
                    timestampButton(startMs: startMs)
                }

                Spacer()
            }

            bodyText
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(
                    isActive
                        ? speakerColor.opacity(0.15)
                        : speakerColor.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .strokeBorder(
                    isActive ? speakerColor.opacity(0.55) : speakerColor.opacity(0.16),
                    lineWidth: isActive ? 1.25 : 0.75
                )
        )
        .onHover { hovering in
            withAnimation(DesignSystem.Animation.hoverTransition) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Copy Reading Turn") {
                onCopyTurn(turn)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(turn.speakerLabel) reading turn")
    }

    private var renameContextID: String {
        SpeakerRenameAccessibility.turnRenameContextIdentifier(
            speakerID: turn.speakerId,
            firstStartMs: turn.timeRange?.startMs,
            duplicateOrdinal: turn.id.firstWordIndex ?? 0
        )
    }

    private var bodyText: Text {
        guard !highlightRanges.isEmpty else {
            return Text(turn.text).font(bodyFont)
        }
        return Text(
            TranscriptFindHighlight.attributed(
                turn.text,
                ranges: highlightRanges,
                current: currentRange,
                baseFont: bodyFont
            ))
    }

    private func timestampButton(startMs: Int) -> some View {
        Button {
            onTimestampTap(startMs)
        } label: {
            Text(timestampLabel(startMs))
                .font(DesignSystem.Typography.timestamp)
                .foregroundStyle(
                    isTimestampSeekable
                        ? DesignSystem.Colors.accent
                        : DesignSystem.Colors.textSecondary
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(DesignSystem.Colors.surfaceElevated))
        }
        .buttonStyle(.plain)
        .disabled(!isTimestampSeekable)
        .help(isTimestampSeekable ? "Play from this Reading Turn" : "Audio is not ready")
        .accessibilityLabel("Start time \(timestampLabel(startMs))")
        .accessibilityHint(isTimestampSeekable ? "Play from this Reading Turn" : "")
    }
}

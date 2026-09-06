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

enum MeetingReadingTurnLayout {
    static let interTurnSpacing: CGFloat = 2
    static let horizontalPadding = DesignSystem.Spacing.sm
    static let verticalPadding: CGFloat = 7
    static let bylineSpacing: CGFloat = 6
    static let bodyIndent: CGFloat = 13
    static let speakerMarkerSize: CGFloat = 7
    static let playbackFocusWidth: CGFloat = 2
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
        ForEach(turns) { identified in
            card(for: identified)
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

    private var turn: ReadingTurn { identified.turn }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: MeetingReadingTurnLayout.bylineSpacing) {
                Circle()
                    .fill(speakerColor.opacity(DesignSystem.Colors.transcriptSpeakerLabelAlpha))
                    .frame(
                        width: MeetingReadingTurnLayout.speakerMarkerSize,
                        height: MeetingReadingTurnLayout.speakerMarkerSize
                    )
                    .accessibilityHidden(true)

                speakerLabelContent(
                    turn.speakerId,
                    turn.speakerLabel,
                    speakerColor,
                    renameContextID,
                    false
                )

                if let startMs = turn.timeRange?.startMs {
                    timestampButton(startMs: startMs)
                }

                Spacer()
            }

            bodyText
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(4)
                .padding(.leading, MeetingReadingTurnLayout.bodyIndent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MeetingReadingTurnLayout.horizontalPadding)
        .padding(.vertical, MeetingReadingTurnLayout.verticalPadding)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(speakerColor.opacity(isActive ? 0.8 : 0))
                .frame(width: MeetingReadingTurnLayout.playbackFocusWidth)
                .accessibilityHidden(true)
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
                .font(DesignSystem.Typography.duration)
                .foregroundStyle(
                    isTimestampSeekable
                        ? DesignSystem.Colors.textSecondary
                        : DesignSystem.Colors.textTertiary
                )
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
        }
        .buttonStyle(.plain)
        .disabled(!isTimestampSeekable)
        .help(isTimestampSeekable ? "Play from this Reading Turn" : "Audio is not ready")
        .accessibilityLabel("Start time \(timestampLabel(startMs))")
        .accessibilityHint(isTimestampSeekable ? "Play from this Reading Turn" : "")
    }
}

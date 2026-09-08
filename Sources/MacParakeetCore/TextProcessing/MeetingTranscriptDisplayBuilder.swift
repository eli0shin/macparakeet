import Foundation

/// Builds the completed-meeting UI document without changing the canonical
/// Reading Turns used by exports, AI context, or stored formatting overrides.
public enum MeetingTranscriptDisplayBuilder {
    public static func build(
        from document: MeetingTranscriptPresentationDocument
    ) -> MeetingTranscriptPresentationDocument {
        var displayedTurns: [ReadingTurn] = []

        for turn in document.turns {
            guard let previous = displayedTurns.last,
                previous.source == turn.source,
                previous.speakerId == turn.speakerId
            else {
                displayedTurns.append(turn)
                continue
            }

            displayedTurns[displayedTurns.count - 1] = merge(previous, with: turn)
        }

        return MeetingTranscriptPresentationDocument(turns: displayedTurns)
    }

    private static func merge(_ first: ReadingTurn, with next: ReadingTurn) -> ReadingTurn {
        let timeRange: ReadingTurnTimeRange?
        if let firstRange = first.timeRange {
            timeRange = ReadingTurnTimeRange(
                startMs: firstRange.startMs,
                endMs: max(firstRange.endMs, next.timeRange?.endMs ?? firstRange.endMs)
            )
        } else {
            timeRange = nil
        }

        let formattedText =
            first.formattedText != nil || next.formattedText != nil
            ? [first.text, next.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
            : nil

        return ReadingTurn(
            id: first.id,
            speakerId: first.speakerId,
            speakerLabel: first.speakerLabel,
            source: first.source,
            timeRange: timeRange,
            overlap: first.overlap,
            paragraphs: first.paragraphs + next.paragraphs,
            formattedText: formattedText,
            wordReferences: first.wordReferences + next.wordReferences
        )
    }
}

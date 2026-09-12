import Foundation

/// Coalesces consecutive presented contributions from the same speaker. The
/// returned document keeps the first contribution's stable identity and does
/// not change canonical word evidence.
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

        return ReadingTurn(
            id: first.id,
            speakerId: first.speakerId,
            speakerLabel: first.speakerLabel,
            source: first.source,
            timeRange: timeRange,
            overlap: first.overlap,
            paragraphs: first.paragraphs + next.paragraphs,
            formattedText: [first.text, next.text].filter { !$0.isEmpty }.joined(separator: "\n\n"),
            wordReferences: first.wordReferences + next.wordReferences
        )
    }
}

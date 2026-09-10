import Foundation

/// Builds the completed-meeting UI document without changing the canonical
/// Reading Turns used by exports, AI context, or stored formatting overrides.
public enum MeetingTranscriptDisplayBuilder {
    public static func build(
        from document: MeetingTranscriptPresentationDocument
    ) -> MeetingTranscriptPresentationDocument {
        var displayedTurns: [ReadingTurn] = []

        for turn in document.turns {
            // Cleanup can remove every word in a turn. Such a turn must not
            // display a blank row or split the surrounding speaker run.
            guard !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

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

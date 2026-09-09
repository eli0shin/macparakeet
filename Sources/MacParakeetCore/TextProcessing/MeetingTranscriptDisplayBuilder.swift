import Foundation

/// Builds the completed-meeting UI document without changing the canonical
/// Reading Turns used by exports, AI context, or stored formatting overrides.
public enum MeetingTranscriptDisplayBuilder {
    public static func build(
        from document: MeetingTranscriptPresentationDocument
    ) -> MeetingTranscriptPresentationDocument {
        var displayedTurns: [ReadingTurn] = []

        for turn in document.turns {
            let displayedTurn = displayedTurn(from: turn)
            guard let previous = displayedTurns.last,
                previous.source == displayedTurn.source,
                previous.speakerId == displayedTurn.speakerId
            else {
                displayedTurns.append(displayedTurn)
                continue
            }

            displayedTurns[displayedTurns.count - 1] = merge(previous, with: displayedTurn)
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
            formattedText: [first.text, next.text].filter { !$0.isEmpty }.joined(separator: "\n"),
            wordReferences: first.wordReferences + next.wordReferences
        )
    }

    private static func displayedTurn(from turn: ReadingTurn) -> ReadingTurn {
        ReadingTurn(
            id: turn.id,
            speakerId: turn.speakerId,
            speakerLabel: turn.speakerLabel,
            source: turn.source,
            timeRange: turn.timeRange,
            overlap: turn.overlap,
            paragraphs: turn.paragraphs,
            formattedText: compactParagraphSpacing(in: turn.text),
            wordReferences: turn.wordReferences
        )
    }

    /// SwiftUI treats each newline as a visible line advance. Canonical Reading
    /// Turns use an empty line between paragraphs, so remove empty separator
    /// lines before the completed-meeting UI renders the text.
    private static func compactParagraphSpacing(in text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }
}

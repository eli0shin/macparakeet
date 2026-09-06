import Foundation

/// A seekable destination for a search result or citation inside one Reading Turn.
public struct ReadingTurnNavigationTarget: Sendable, Equatable {
    public let turnID: ReadingTurnIdentity
    public let timeRange: ReadingTurnTimeRange?
    public let wordReferences: [Int]

    public init(
        turnID: ReadingTurnIdentity,
        timeRange: ReadingTurnTimeRange?,
        wordReferences: [Int]
    ) {
        self.turnID = turnID
        self.timeRange = timeRange
        self.wordReferences = wordReferences
    }
}

public extension MeetingTranscriptPresentationDocument {
    /// Resolve word-based citations to the complete Reading Turn that contains
    /// the evidence. The returned range is the same range used by its seek control.
    func navigationTarget(containingWordReference reference: Int) -> ReadingTurnNavigationTarget? {
        guard let turn = turns.first(where: { $0.wordReferences.contains(reference) }) else {
            return nil
        }
        return navigationTarget(for: turn)
    }

    /// Resolve a playback time only when it is inside a timed Reading Turn.
    func navigationTarget(containingTimeMs timeMs: Int) -> ReadingTurnNavigationTarget? {
        guard
            let turn = turns.first(where: { turn in
                guard let range = turn.timeRange else { return false }
                return range.startMs <= timeMs && timeMs <= range.endMs
            })
        else {
            return nil
        }
        return navigationTarget(for: turn)
    }

    func passage(containingWordReference reference: Int) -> MeetingTranscriptPresentationDocument? {
        guard let turn = turns.first(where: { $0.wordReferences.contains(reference) }) else {
            return nil
        }
        return MeetingTranscriptPresentationDocument(turns: [turn])
    }

    private func navigationTarget(for turn: ReadingTurn) -> ReadingTurnNavigationTarget {
        ReadingTurnNavigationTarget(
            turnID: turn.id,
            timeRange: turn.timeRange,
            wordReferences: turn.wordReferences
        )
    }
}

/// The active presentation policy for completed-meeting Reading Turns.
/// Completed meetings always use deterministic cleanup, independent of the
/// dictation Raw/Clean preference.
public struct CompletedMeetingReadingConfiguration: Sendable {
    public let customWords: [CustomWord]
    public let cleanup: MeetingTranscriptCleanup

    public init(
        processingMode: Dictation.ProcessingMode,
        customWords: [CustomWord]
    ) {
        _ = processingMode
        self.customWords = customWords
        cleanup = .cleaned
    }

    public init(
        customWords: [CustomWord] = [],
        cleanup: MeetingTranscriptCleanup = .cleaned
    ) {
        self.customWords = customWords
        self.cleanup = cleanup
    }
}

/// Builds the completed-meeting Reading Turn document used by copy, readable
/// exports, meeting artifacts, summaries, and chat. Edited transcripts keep the
/// existing plain-text contract because their word alignment is no longer valid.
public enum CompletedMeetingReadingDocument {
    public static func build(
        from transcription: Transcription,
        configuration: CompletedMeetingReadingConfiguration
    ) -> MeetingTranscriptPresentationDocument? {
        build(
            from: transcription,
            customWords: configuration.customWords,
            cleanup: configuration.cleanup
        )
    }

    public static func build(
        from transcription: Transcription,
        customWords: [CustomWord] = [],
        cleanup: MeetingTranscriptCleanup = .cleaned
    ) -> MeetingTranscriptPresentationDocument? {
        guard transcription.sourceType == .meeting,
            transcription.status == .completed,
            !transcription.isTranscriptEdited
        else {
            return nil
        }
        let rawTranscript = transcription.rawTranscript ?? transcription.cleanTranscript ?? ""
        return MeetingTranscriptPresentationBuilder.build(
            transcriptText: rawTranscript,
            words: transcription.wordTimestamps,
            speakers: transcription.speakers,
            diarizationSegments: transcription.diarizationSegments,
            customWords: MeetingTranscriptCleaner.applicableCustomWords(
                customWords,
                to: rawTranscript
            ),
            cleanup: cleanup,
            formatting: transcription.meetingReadingTurnFormatting ?? []
        )
    }
}

/// Deterministic text projections of a Reading Turn document. All projections
/// keep turn order, overlap membership, and paragraph boundaries.
public enum MeetingTranscriptDocumentRenderer {
    public static func plainText(
        _ document: MeetingTranscriptPresentationDocument,
        includeTimestamps: Bool = true,
        includeSpeakerLabels: Bool = true
    ) -> String {
        render(
            document,
            includeTimestamps: includeTimestamps,
            includeSpeakerLabels: includeSpeakerLabels,
            markdown: false
        )
    }

    public static func markdown(
        _ document: MeetingTranscriptPresentationDocument,
        includeTimestamps: Bool = true,
        includeSpeakerLabels: Bool = true
    ) -> String {
        render(
            document,
            includeTimestamps: includeTimestamps,
            includeSpeakerLabels: includeSpeakerLabels,
            markdown: true
        )
    }

    private static func render(
        _ document: MeetingTranscriptPresentationDocument,
        includeTimestamps: Bool,
        includeSpeakerLabels: Bool,
        markdown: Bool
    ) -> String {
        groups(in: document.turns).map { group in
            var sections: [String] = []
            if group.isOverlap {
                sections.append(markdown ? "> Simultaneous speech" : "[Simultaneous speech]")
            }
            sections.append(
                contentsOf: group.turns.map { turn in
                    render(
                        turn,
                        includeTimestamps: includeTimestamps,
                        includeSpeakerLabels: includeSpeakerLabels,
                        markdown: markdown
                    )
                })
            return sections.joined(separator: "\n\n")
        }
        .joined(separator: "\n\n")
    }

    private static func render(
        _ turn: ReadingTurn,
        includeTimestamps: Bool,
        includeSpeakerLabels: Bool,
        markdown: Bool
    ) -> String {
        var sections: [String] = []
        let hasReliableSpeaker = turn.source != .unknown
        let label = includeSpeakerLabels && hasReliableSpeaker ? normalized(turn.speakerLabel) : nil
        let timestamp =
            includeTimestamps
            ? turn.timeRange.map { "[\(readableTimestamp(ms: $0.startMs))]" }
            : nil

        let header = [label, timestamp].compactMap { $0 }.joined(separator: " · ")
        if !header.isEmpty {
            sections.append(markdown ? "**\(header)**" : "\(header):")
        }
        if !turn.text.isEmpty {
            sections.append(turn.text)
        }
        return sections.joined(separator: "\n\n")
    }

    private struct TurnGroup {
        let isOverlap: Bool
        let turns: [ReadingTurn]
    }

    private static func groups(in turns: [ReadingTurn]) -> [TurnGroup] {
        let overlapMembers = Dictionary(
            grouping: turns.compactMap { turn in turn.overlap.map { ($0, turn) } },
            by: { $0.0 }
        )
        var emitted: Set<ReadingTurnOverlap> = []
        var result: [TurnGroup] = []
        for turn in turns {
            guard let overlap = turn.overlap else {
                result.append(TurnGroup(isOverlap: false, turns: [turn]))
                continue
            }
            guard emitted.insert(overlap).inserted else { continue }
            result.append(
                TurnGroup(
                    isOverlap: true,
                    turns: overlapMembers[overlap, default: []].map(\.1)
                )
            )
        }
        return result
    }

    private static func normalized(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func readableTimestamp(ms: Int) -> String {
        let totalSeconds = max(0, ms) / 1_000
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

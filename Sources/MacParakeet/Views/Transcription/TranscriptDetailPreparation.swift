import Foundation
import MacParakeetCore

struct TranscriptFindBlock: Equatable, Identifiable, Sendable {
    let id: Int
    let text: String
}

private struct TranscriptDetailCustomWordInput: Equatable, Sendable {
    let id: UUID
    let word: String
    let replacement: String?
    let isEnabled: Bool
}

struct TranscriptDetailPreparationInput: Equatable, Sendable {
    let transcriptionID: UUID
    let fileName: String
    let durationMs: Int?
    let rawTranscript: String?
    let cleanTranscript: String?
    let wordTimestamps: [WordTimestamp]?
    let speakers: [SpeakerInfo]?
    let diarizationSegments: [DiarizationSegmentRecord]?
    let readingDocument: MeetingTranscriptPresentationDocument?
    let readingTurnFormatting: [MeetingReadingTurnFormatting]?
    let status: Transcription.TranscriptionStatus
    let sourceType: Transcription.SourceType
    let isTranscriptEdited: Bool
    private let customWords: [TranscriptDetailCustomWordInput]

    init(transcription: Transcription, customWords: [CustomWord]) {
        transcriptionID = transcription.id
        fileName = transcription.fileName
        durationMs = transcription.durationMs
        rawTranscript = transcription.rawTranscript
        cleanTranscript = transcription.cleanTranscript
        wordTimestamps = transcription.wordTimestamps
        speakers = transcription.speakers
        diarizationSegments = transcription.diarizationSegments
        readingDocument = transcription.readingDocument
        readingTurnFormatting = transcription.meetingReadingTurnFormatting
        status = transcription.status
        sourceType = transcription.sourceType
        isTranscriptEdited = transcription.isTranscriptEdited
        self.customWords = customWords.map {
            TranscriptDetailCustomWordInput(
                id: $0.id,
                word: $0.word,
                replacement: $0.replacement,
                isEnabled: $0.isEnabled
            )
        }
    }
}

struct TranscriptDetailPreparationSnapshot: Sendable {
    let input: TranscriptDetailPreparationInput
    let preferredText: String
    let textWordCount: Int
    let timedWordCount: Int
    let hasPreferredText: Bool
    let hasCleanTranscriptText: Bool
    let readingDocument: MeetingTranscriptPresentationDocument
    let readingTurns: [IdentifiedReadingTurn]
    let playbackIndex: ReadingTurnPlaybackIndex?
    let segments: [TranscriptSegment]
    let identifiedTurnCards: [IdentifiedSpeakerTurn]
    let hasSpeakers: Bool
    let segmentStartMs: [Int]
    let speakerStatistics: [String: SpeakerStatistics]
    let speakerLabels: [String: String]
    let speakerColorIndices: [String: Int]
    let readingFindBlocks: [TranscriptFindBlock]
    let segmentFindBlocks: [TranscriptFindBlock]
    let textFindBlocks: [TranscriptFindBlock]
    let mandalaData: MandalaData
}

enum TranscriptDetailPreparation {
    nonisolated static func make(
        transcription: Transcription,
        customWords: [CustomWord],
        input: TranscriptDetailPreparationInput
    ) -> TranscriptDetailPreparationSnapshot {
        let speakerLabels = Dictionary(
            uniqueKeysWithValues: (transcription.speakers ?? []).map { ($0.id, $0.label) }
        )
        let speakerColorIndices = Dictionary(
            uniqueKeysWithValues: (transcription.speakers ?? []).enumerated().map {
                ($0.element.id, $0.offset)
            }
        )
        let applicableWords = transcription.hasWordTimestamps
            ? MeetingTranscriptCleaner.applicableCustomWords(
                customWords,
                to: transcription.rawTranscript ?? ""
            )
            : []
        let readingDocument = CompletedMeetingReadingDocument.build(
            from: transcription,
            customWords: applicableWords,
            cleanup: .cleaned
        ) ?? MeetingTranscriptPresentationBuilder.build(
            transcriptText: transcription.rawTranscript ?? "",
            words: transcription.wordTimestamps,
            speakers: transcription.speakers,
            diarizationSegments: transcription.diarizationSegments,
            customWords: applicableWords,
            cleanup: .cleaned,
            formatting: transcription.meetingReadingTurnFormatting ?? []
        )
        let displayedTurns = transcription.readingDocument != nil
            ? readingDocument.turns
            : MeetingTranscriptDisplayBuilder.build(from: readingDocument).turns
        let readingTurns = identifiedReadingTurns(displayedTurns)
        let playbackIndex = transcription.wordTimestamps.map {
            ReadingTurnPlaybackIndex(turns: displayedTurns, words: $0)
        }
        let words = transcription.wordTimestamps ?? []
        let segments = TranscriptSegmenter.groupIntoSegments(words: words)
        let hasSpeakers = words.contains { $0.speakerId != nil }
        let cards: [IdentifiedSpeakerTurn]
        if hasSpeakers {
            let turns = TranscriptSegmenter.groupIntoSpeakerTurns(
                segments: segments,
                speakerLabelProvider: { speakerID in
                    guard let speakerID else { return "Unknown" }
                    return speakerLabels[speakerID] ?? "Unknown"
                }
            )
            cards = identifiedSpeakerTurnCards(turns)
        } else {
            cards = []
        }
        let preferredText = MeetingTranscriptCleaner.preferredText(
            for: transcription,
            customWords: customWords
        )

        return TranscriptDetailPreparationSnapshot(
            input: input,
            preferredText: preferredText,
            textWordCount: preferredText.split(whereSeparator: \.isWhitespace).count,
            timedWordCount: words.count,
            hasPreferredText: preferredText.contains { !$0.isWhitespace },
            hasCleanTranscriptText: transcription.cleanTranscript?.contains {
                !$0.isWhitespace
            } ?? false,
            readingDocument: readingDocument,
            readingTurns: readingTurns,
            playbackIndex: playbackIndex,
            segments: segments,
            identifiedTurnCards: cards,
            hasSpeakers: hasSpeakers,
            segmentStartMs: segments.map(\.startMs),
            speakerStatistics: TranscriptSegmenter.computeSpeakerStats(
                diarizationSegments: transcription.diarizationSegments,
                wordTimestamps: transcription.wordTimestamps
            ),
            speakerLabels: speakerLabels,
            speakerColorIndices: speakerColorIndices,
            readingFindBlocks: readingTurns.map {
                TranscriptFindBlock(id: $0.scrollID, text: $0.turn.text)
            },
            segmentFindBlocks: segments.map {
                TranscriptFindBlock(id: $0.startMs, text: $0.text)
            },
            textFindBlocks: [TranscriptFindBlock(id: 0, text: preferredText)],
            mandalaData: makeMandalaData(for: transcription)
        )
    }

    private nonisolated static func makeMandalaData(for transcription: Transcription) -> MandalaData {
        if let timestamps = transcription.wordTimestamps, !timestamps.isEmpty {
            return .from(wordTimestamps: timestamps)
        }
        return .from(
            text: transcription.cleanTranscript ?? transcription.rawTranscript ?? transcription.fileName,
            durationMs: transcription.durationMs ?? 1_000
        )
    }
}

@MainActor
final class TranscriptDetailSnapshotCache {
    static let shared = TranscriptDetailSnapshotCache()

    private var values: [UUID: TranscriptDetailPreparationSnapshot] = [:]
    private var order: [UUID] = []

    func value(for input: TranscriptDetailPreparationInput) -> TranscriptDetailPreparationSnapshot? {
        guard let snapshot = values[input.transcriptionID], snapshot.input == input else { return nil }
        return snapshot
    }

    func insert(_ value: TranscriptDetailPreparationSnapshot) {
        let id = value.input.transcriptionID
        values[id] = value
        order.removeAll { $0 == id }
        order.append(id)
        while order.count > 4, let oldest = order.first {
            order.removeFirst()
            values.removeValue(forKey: oldest)
        }
    }
}

import Foundation

/// Capture-source identity used by the completed-meeting reading surface.
public enum ReadingTurnSource: String, Sendable, Equatable, Hashable {
    case microphone
    case system
    case unknown
}

/// Stable identity derived from canonical transcript evidence. Speaker renames do
/// not change this identity. Retranscription can create a new identity because it
/// creates new word evidence.
public struct ReadingTurnIdentity: Sendable, Equatable, Hashable {
    public let source: ReadingTurnSource
    public let speakerId: String
    public let firstWordIndex: Int?

    public init(source: ReadingTurnSource, speakerId: String, firstWordIndex: Int?) {
        self.source = source
        self.speakerId = speakerId
        self.firstWordIndex = firstWordIndex
    }
}

public struct ReadingTurnTimeRange: Sendable, Equatable {
    public let startMs: Int
    public let endMs: Int

    public init(startMs: Int, endMs: Int) {
        self.startMs = startMs
        self.endMs = endMs
    }
}

/// A paragraph inside one Reading Turn. Word references are indexes into the
/// unchanged `WordTimestamp` evidence supplied to the builder.
public struct ReadingTurnParagraph: Sendable, Equatable {
    public let text: String
    public let wordReferences: [Int]

    public init(text: String, wordReferences: [Int]) {
        self.text = text
        self.wordReferences = wordReferences
    }
}

/// The human-facing unit for a completed meeting transcript.
public struct ReadingTurn: Sendable, Equatable, Identifiable {
    public let id: ReadingTurnIdentity
    public let speakerId: String
    public let speakerLabel: String
    public let source: ReadingTurnSource
    public let timeRange: ReadingTurnTimeRange?
    public let paragraphs: [ReadingTurnParagraph]
    public let wordReferences: [Int]

    public init(
        id: ReadingTurnIdentity,
        speakerId: String,
        speakerLabel: String,
        source: ReadingTurnSource,
        timeRange: ReadingTurnTimeRange?,
        paragraphs: [ReadingTurnParagraph],
        wordReferences: [Int]
    ) {
        self.id = id
        self.speakerId = speakerId
        self.speakerLabel = speakerLabel
        self.source = source
        self.timeRange = timeRange
        self.paragraphs = paragraphs
        self.wordReferences = wordReferences
    }

    public var text: String {
        paragraphs.map(\.text).joined(separator: "\n\n")
    }
}

public struct MeetingTranscriptPresentationDocument: Sendable, Equatable {
    public let turns: [ReadingTurn]

    public init(turns: [ReadingTurn]) {
        self.turns = turns
    }
}

/// Pure presentation boundary from canonical meeting transcript evidence to a
/// readable document. It never writes back to words, source IDs, or diarization.
public enum MeetingTranscriptPresentationBuilder {
    private static let utterancePauseMs = 2_500
    private static let maximumParagraphSentenceCount = 3
    private static let maximumParagraphWordCount = 80

    public static func build(
        transcriptText: String,
        words: [WordTimestamp]?,
        speakers: [SpeakerInfo]?
    ) -> MeetingTranscriptPresentationDocument {
        guard let words, !words.isEmpty else {
            return fallbackDocument(transcriptText: transcriptText)
        }

        let labels = Dictionary(
            (speakers ?? []).map { ($0.id, $0.label) },
            uniquingKeysWith: { first, _ in first }
        )
        let indexedWords = words.enumerated().map { IndexedWord(index: $0.offset, word: $0.element) }
        let sourceOrder: [ReadingTurnSource] = [.microphone, .system, .unknown]
        let assembled = sourceOrder.flatMap { source in
            makeTurns(
                from: indexedWords.filter { readingSource(for: $0.word.speakerId) == source },
                allWords: indexedWords,
                source: source,
                labels: labels
            )
        }
        .sorted { lhs, rhs in
            let lhsStart = lhs.timeRange?.startMs ?? .max
            let rhsStart = rhs.timeRange?.startMs ?? .max
            if lhsStart == rhsStart {
                return sourceRank(lhs.source) < sourceRank(rhs.source)
            }
            return lhsStart < rhsStart
        }

        return MeetingTranscriptPresentationDocument(turns: assembled)
    }

    private static func makeTurns(
        from words: [IndexedWord],
        allWords: [IndexedWord],
        source: ReadingTurnSource,
        labels: [String: String]
    ) -> [ReadingTurn] {
        guard !words.isEmpty else { return [] }

        let sortedWords = words.sorted(by: evidenceOrder)
        let otherSourceWords =
            allWords
            .filter { readingSource(for: $0.word.speakerId) != source }
            .sorted(by: evidenceOrder)
        var otherSourceCursor = 0
        var utterances: [[IndexedWord]] = []
        var current: [IndexedWord] = []

        for indexedWord in sortedWords {
            if let previous = current.last {
                let longPause = indexedWord.word.startMs - previous.word.endMs >= utterancePauseMs
                let sentenceBoundary = endsSentence(previous.word.word)
                let sentenceSpeakerChange =
                    sentenceBoundary
                    && indexedWord.word.speakerId != previous.word.speakerId
                while otherSourceCursor < otherSourceWords.count,
                    otherSourceWords[otherSourceCursor].word.endMs <= previous.word.endMs
                {
                    otherSourceCursor += 1
                }
                let sourceExchange =
                    sentenceBoundary
                    && otherSourceCursor < otherSourceWords.count
                    && otherSourceWords[otherSourceCursor].word.startMs < indexedWord.word.startMs
                if longPause || sentenceSpeakerChange || sourceExchange {
                    utterances.append(current)
                    current = []
                }
            }
            current.append(indexedWord)
        }
        if !current.isEmpty { utterances.append(current) }

        let resolved = utterances.map { utterance in
            ResolvedUtterance(
                words: utterance,
                speakerId: resolvedSpeakerId(for: utterance, source: source)
            )
        }

        return resolved.map { group in
            let speakerId = group.speakerId
            let label: String
            switch source {
            case .microphone:
                label = AudioSource.microphone.displayLabel
            case .system:
                label =
                    normalizedLabel(labels[speakerId])
                    ?? (speakerId == AudioSource.system.rawValue
                        ? AudioSource.system.displayLabel
                        : speakerId)
            case .unknown:
                label = normalizedLabel(labels[speakerId]) ?? "Unknown Speaker"
            }
            let references = group.words.map(\.index)
            return ReadingTurn(
                id: ReadingTurnIdentity(
                    source: source,
                    speakerId: speakerId,
                    firstWordIndex: references.first
                ),
                speakerId: speakerId,
                speakerLabel: label,
                source: source,
                timeRange: ReadingTurnTimeRange(startMs: group.startMs, endMs: group.endMs),
                paragraphs: makeParagraphs(from: group.words),
                wordReferences: references
            )
        }
    }

    private static func resolvedSpeakerId(
        for words: [IndexedWord],
        source: ReadingTurnSource
    ) -> String {
        if source == .microphone { return AudioSource.microphone.rawValue }

        var durationBySpeaker: [String: Int] = [:]
        for indexedWord in words {
            guard let speakerId = indexedWord.word.speakerId else { continue }
            let duration = max(1, indexedWord.word.endMs - indexedWord.word.startMs)
            durationBySpeaker[speakerId, default: 0] += duration
        }

        if source == .system {
            let refined = durationBySpeaker.filter { $0.key != AudioSource.system.rawValue }
            if let dominant = dominantSpeaker(in: refined) { return dominant }
            return AudioSource.system.rawValue
        }
        return dominantSpeaker(in: durationBySpeaker) ?? "unknown"
    }

    private static func dominantSpeaker(in durations: [String: Int]) -> String? {
        durations.max { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key > rhs.key }
            return lhs.value < rhs.value
        }?.key
    }

    private static func makeParagraphs(from words: [IndexedWord]) -> [ReadingTurnParagraph] {
        var paragraphs: [ReadingTurnParagraph] = []
        var current: [IndexedWord] = []
        var sentenceCount = 0

        func appendCurrent() {
            guard !current.isEmpty else { return }
            paragraphs.append(
                ReadingTurnParagraph(
                    text: renderedText(from: current.map { $0.word.word }),
                    wordReferences: current.map(\.index)
                ))
        }

        for indexedWord in words {
            if let previous = current.last,
                indexedWord.word.startMs - previous.word.endMs >= utterancePauseMs
            {
                appendCurrent()
                current = []
                sentenceCount = 0
            }

            current.append(indexedWord)
            if endsSentence(indexedWord.word.word) { sentenceCount += 1 }
            if sentenceCount >= maximumParagraphSentenceCount
                || current.count >= maximumParagraphWordCount
            {
                appendCurrent()
                current = []
                sentenceCount = 0
            }
        }
        appendCurrent()
        return paragraphs
    }

    private static func fallbackDocument(transcriptText: String) -> MeetingTranscriptPresentationDocument {
        let text = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return MeetingTranscriptPresentationDocument(turns: []) }
        let source = ReadingTurnSource.unknown
        let speakerId = "unknown"
        return MeetingTranscriptPresentationDocument(turns: [
            ReadingTurn(
                id: ReadingTurnIdentity(source: source, speakerId: speakerId, firstWordIndex: nil),
                speakerId: speakerId,
                speakerLabel: "Transcript",
                source: source,
                timeRange: nil,
                paragraphs: [ReadingTurnParagraph(text: text, wordReferences: [])],
                wordReferences: []
            )
        ])
    }

    private static func readingSource(for speakerId: String?) -> ReadingTurnSource {
        switch speakerId {
        case AudioSource.microphone.rawValue:
            return .microphone
        case AudioSource.system.rawValue:
            return .system
        case .some:
            // Meeting diarization currently prefixes remote IDs with `system:`.
            // Older completed meetings can contain bare IDs such as `S1`.
            // Meetings diarize only the system track, so every attributed ID
            // other than the deterministic microphone ID is remote speech.
            return .system
        case nil:
            return .unknown
        }
    }

    private static func evidenceOrder(_ lhs: IndexedWord, _ rhs: IndexedWord) -> Bool {
        if lhs.word.startMs == rhs.word.startMs { return lhs.index < rhs.index }
        return lhs.word.startMs < rhs.word.startMs
    }

    private static func sourceRank(_ source: ReadingTurnSource) -> Int {
        switch source {
        case .microphone: return 0
        case .system: return 1
        case .unknown: return 2
        }
    }

    private static func normalizedLabel(_ label: String?) -> String? {
        guard let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    private static func endsSentence(_ token: String) -> Bool {
        guard let last = token.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return ".!?".contains(last)
    }

    private static func renderedText(from tokens: [String]) -> String {
        var result = ""
        for token in tokens {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if result.isEmpty || ",.!?;:%)]}".contains(trimmed.first!) {
                result += trimmed
            } else {
                result += " \(trimmed)"
            }
        }
        return result
    }
}

private struct IndexedWord {
    let index: Int
    let word: WordTimestamp
}

private struct ResolvedUtterance {
    let words: [IndexedWord]
    let speakerId: String

    var startMs: Int { words.first?.word.startMs ?? 0 }
    var endMs: Int { words.map { $0.word.endMs }.max() ?? startMs }
}

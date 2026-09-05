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

/// Content-free measures for comparing Reading Turn fixture output. These
/// values describe presentation structure and never include transcript text.
public struct ReadingTurnReadabilityMetrics: Sendable, Equatable {
    public let turnsPerMinute: Double
    public let blocksShorterThanThreeWords: Int
    public let isolatedSpeakerFlips: Int
    public let fallbackSpeakerTransitions: Int
    public let medianWordsPerTurn: Double

    public init(
        turnsPerMinute: Double,
        blocksShorterThanThreeWords: Int,
        isolatedSpeakerFlips: Int,
        fallbackSpeakerTransitions: Int,
        medianWordsPerTurn: Double
    ) {
        self.turnsPerMinute = turnsPerMinute
        self.blocksShorterThanThreeWords = blocksShorterThanThreeWords
        self.isolatedSpeakerFlips = isolatedSpeakerFlips
        self.fallbackSpeakerTransitions = fallbackSpeakerTransitions
        self.medianWordsPerTurn = medianWordsPerTurn
    }

    public static func measure(_ document: MeetingTranscriptPresentationDocument) -> Self {
        let turns = document.turns
        guard !turns.isEmpty else {
            return Self(
                turnsPerMinute: 0,
                blocksShorterThanThreeWords: 0,
                isolatedSpeakerFlips: 0,
                fallbackSpeakerTransitions: 0,
                medianWordsPerTurn: 0
            )
        }

        let starts = turns.compactMap { $0.timeRange?.startMs }
        let ends = turns.compactMap { $0.timeRange?.endMs }
        let durationMs = max(1, (ends.max() ?? 0) - (starts.min() ?? 0))
        let wordCounts = turns.map { $0.wordReferences.count }.sorted()
        let middle = wordCounts.count / 2
        let median =
            wordCounts.count.isMultiple(of: 2)
            ? Double(wordCounts[middle - 1] + wordCounts[middle]) / 2
            : Double(wordCounts[middle])
        let flips = turns.indices.dropFirst().dropLast().reduce(into: 0) { count, index in
            if turns[index - 1].speakerId == turns[index + 1].speakerId,
                turns[index].speakerId != turns[index - 1].speakerId
            {
                count += 1
            }
        }
        let fallbackTransitions = zip(turns, turns.dropFirst()).reduce(into: 0) { count, pair in
            guard pair.0.speakerId != pair.1.speakerId else { return }
            if pair.0.speakerId == AudioSource.system.rawValue
                || pair.1.speakerId == AudioSource.system.rawValue
            {
                count += 1
            }
        }

        return Self(
            turnsPerMinute: Double(turns.count) * 60_000 / Double(durationMs),
            blocksShorterThanThreeWords: wordCounts.count { $0 < 3 },
            isolatedSpeakerFlips: flips,
            fallbackSpeakerTransitions: fallbackTransitions,
            medianWordsPerTurn: median
        )
    }
}

/// Pure presentation boundary from canonical meeting transcript evidence to a
/// readable document. It never writes back to words, source IDs, or diarization.
public enum MeetingTranscriptPresentationBuilder {
    private static let utterancePauseMs = 2_500
    /// A new remote speaker needs this much exclusive aggregate evidence when
    /// the stable speaker before and after it is the same.
    private static let minimumSpeakerChangeEvidenceMs = 1_000
    private static let maximumParagraphSentenceCount = 3
    private static let maximumParagraphWordCount = 80

    public static func build(
        transcriptText: String,
        words: [WordTimestamp]?,
        speakers: [SpeakerInfo]?,
        diarizationSegments: [DiarizationSegmentRecord]? = nil
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
                labels: labels,
                diarizationSegments: diarizationSegments ?? []
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
        labels: [String: String],
        diarizationSegments: [DiarizationSegmentRecord]
    ) -> [ReadingTurn] {
        guard !words.isEmpty else { return [] }

        let utterances = formUtterances(from: words, allWords: allWords, source: source)
        let attributed = utterances.map { utterance in
            let evidence = speakerEvidence(
                for: utterance.words,
                source: source,
                diarizationSegments: diarizationSegments
            )
            return ResolvedUtterance(
                words: utterance.words,
                speakerId: evidence.speakerId,
                speakerEvidenceMs: evidence.durationMs,
                allowsMergeWithPrevious: utterance.allowsMergeWithPrevious
            )
        }
        let resolved = mergeAdjacentUtterances(smoothWeakSpeakerRuns(attributed, source: source))

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

    private static func formUtterances(
        from words: [IndexedWord],
        allWords: [IndexedWord],
        source: ReadingTurnSource
    ) -> [SourceUtterance] {
        let sortedWords = words.sorted(by: evidenceOrder)
        let otherSourceWords =
            allWords
            .filter { readingSource(for: $0.word.speakerId) != source }
            .sorted(by: evidenceOrder)
        var otherSourceCursor = 0
        var utterances: [SourceUtterance] = []
        var current: [IndexedWord] = []
        var currentAllowsMergeWithPrevious = false

        for indexedWord in sortedWords {
            if let previous = current.last {
                let longPause = indexedWord.word.startMs - previous.word.endMs >= utterancePauseMs
                while otherSourceCursor < otherSourceWords.count,
                    otherSourceWords[otherSourceCursor].word.endMs <= previous.word.endMs
                {
                    otherSourceCursor += 1
                }
                let sourceExchange = hasCompletedSourceExchange(
                    between: previous.word.endMs,
                    and: indexedWord.word.startMs,
                    in: otherSourceWords,
                    startingAt: otherSourceCursor
                )
                let sentenceBoundary = endsSentence(previous.word.word)
                if longPause || sourceExchange || sentenceBoundary {
                    utterances.append(
                        SourceUtterance(
                            words: current,
                            allowsMergeWithPrevious: currentAllowsMergeWithPrevious
                        ))
                    current = []
                    currentAllowsMergeWithPrevious = sentenceBoundary && !longPause && !sourceExchange
                }
            }
            current.append(indexedWord)
        }
        if !current.isEmpty {
            utterances.append(
                SourceUtterance(
                    words: current,
                    allowsMergeWithPrevious: currentAllowsMergeWithPrevious
                ))
        }
        return utterances
    }

    private static func speakerEvidence(
        for words: [IndexedWord],
        source: ReadingTurnSource,
        diarizationSegments: [DiarizationSegmentRecord]
    ) -> SpeakerEvidence {
        if source == .microphone {
            return SpeakerEvidence(speakerId: AudioSource.microphone.rawValue, durationMs: 0)
        }

        var durationBySpeaker: [String: Int] = [:]
        if source == .system, let startMs = words.first?.word.startMs {
            let endMs = words.map { $0.word.endMs }.max() ?? startMs
            for segment in diarizationSegments where isRefinedSystemSpeaker(segment.speakerId) {
                let overlapMs = max(0, min(endMs, segment.endMs) - max(startMs, segment.startMs))
                if overlapMs > 0 {
                    durationBySpeaker[segment.speakerId, default: 0] += overlapMs
                }
            }
        }

        // Legacy meetings may not retain diarization regions. Keep aggregate
        // word evidence as a compatibility fallback, never as a visible split.
        if durationBySpeaker.isEmpty {
            for indexedWord in words {
                guard let speakerId = indexedWord.word.speakerId else { continue }
                if source == .system, !isRefinedSystemSpeaker(speakerId) { continue }
                let durationMs = max(1, indexedWord.word.endMs - indexedWord.word.startMs)
                durationBySpeaker[speakerId, default: 0] += durationMs
            }
        }

        let fallback = source == .system ? AudioSource.system.rawValue : "unknown"
        guard let dominant = unambiguousDominantSpeaker(in: durationBySpeaker) else {
            let utteranceSpeechMs = words.reduce(0) {
                $0 + max(1, $1.word.endMs - $1.word.startMs)
            }
            return SpeakerEvidence(speakerId: fallback, durationMs: utteranceSpeechMs)
        }
        return SpeakerEvidence(speakerId: dominant.key, durationMs: dominant.value)
    }

    private static func unambiguousDominantSpeaker(
        in durations: [String: Int]
    ) -> (key: String, value: Int)? {
        let ranked = durations.sorted {
            if $0.value == $1.value { return $0.key < $1.key }
            return $0.value > $1.value
        }
        guard let first = ranked.first else { return nil }
        guard ranked.count == 1 || first.value > ranked[1].value else { return nil }
        return first
    }

    private static func smoothWeakSpeakerRuns(
        _ utterances: [ResolvedUtterance],
        source: ReadingTurnSource
    ) -> [ResolvedUtterance] {
        guard source == .system, utterances.count >= 3 else { return utterances }
        var smoothed = utterances
        var runStart = 0

        while runStart < smoothed.count {
            var runEnd = runStart + 1
            while runEnd < smoothed.count,
                smoothed[runEnd].speakerId == smoothed[runStart].speakerId
            {
                runEnd += 1
            }

            if runStart > 0, runEnd < smoothed.count {
                let previousSpeaker = smoothed[runStart - 1].speakerId
                let nextSpeaker = smoothed[runEnd].speakerId
                let runSpeaker = smoothed[runStart].speakerId
                let evidenceMs = smoothed[runStart..<runEnd].reduce(0) {
                    $0 + $1.speakerEvidenceMs
                }
                if previousSpeaker == nextSpeaker,
                    runSpeaker != previousSpeaker,
                    evidenceMs < minimumSpeakerChangeEvidenceMs
                {
                    for index in runStart..<runEnd {
                        smoothed[index].speakerId = previousSpeaker
                    }
                }
            }
            runStart = runEnd
        }
        return smoothed
    }

    private static func mergeAdjacentUtterances(
        _ utterances: [ResolvedUtterance]
    ) -> [ResolvedUtterance] {
        var merged: [ResolvedUtterance] = []
        for utterance in utterances {
            if let previous = merged.last,
                utterance.allowsMergeWithPrevious,
                utterance.speakerId == previous.speakerId,
                utterance.startMs - previous.endMs < utterancePauseMs
            {
                merged[merged.count - 1].words.append(contentsOf: utterance.words)
                merged[merged.count - 1].speakerEvidenceMs += utterance.speakerEvidenceMs
            } else {
                merged.append(utterance)
            }
        }
        return merged
    }

    private static func isRefinedSystemSpeaker(_ speakerId: String) -> Bool {
        speakerId != AudioSource.microphone.rawValue
            && speakerId != AudioSource.system.rawValue
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

    /// A source exchange is complete only when other-source speech starts after
    /// the preceding source word and ends before the next one. Speech crossing
    /// either boundary is overlap and must not split the surrounding utterance.
    private static func hasCompletedSourceExchange(
        between startMs: Int,
        and endMs: Int,
        in otherSourceWords: [IndexedWord],
        startingAt startIndex: Int
    ) -> Bool {
        guard endMs > startMs else { return false }

        var foundCompletedSpeech = false
        var index = startIndex
        while index < otherSourceWords.count,
            otherSourceWords[index].word.startMs < endMs
        {
            let word = otherSourceWords[index].word
            if word.endMs > startMs {
                guard word.startMs >= startMs, word.endMs <= endMs else {
                    return false
                }
                foundCompletedSpeech = true
            }
            index += 1
        }
        return foundCompletedSpeech
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

private struct SourceUtterance {
    let words: [IndexedWord]
    let allowsMergeWithPrevious: Bool
}

private struct SpeakerEvidence {
    let speakerId: String
    let durationMs: Int
}

private struct ResolvedUtterance {
    var words: [IndexedWord]
    var speakerId: String
    var speakerEvidenceMs: Int
    let allowsMergeWithPrevious: Bool

    var startMs: Int { words.first?.word.startMs ?? 0 }
    var endMs: Int { words.map { $0.word.endMs }.max() ?? startMs }
}

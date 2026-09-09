import Foundation

struct MeetingTranscriptFinalizer {
    struct SourceTranscript: Sendable {
        let source: AudioSource
        let result: STTResult
        let startOffsetMs: Int
    }

    struct SourceDiarization: Sendable {
        let speakers: [SpeakerInfo]
        let segments: [SpeakerSegment]
    }

    struct FinalizedTranscript: Sendable {
        let rawTranscript: String
        let words: [WordTimestamp]
        let speakers: [SpeakerInfo]
        let diarizationSegments: [DiarizationSegmentRecord]
        let durationMs: Int?
    }

    static func finalize(
        sourceTranscripts: [SourceTranscript],
        systemDiarization: SourceDiarization? = nil,
        microphoneDiarization: SourceDiarization? = nil,
        microphoneSpeakerDetection: Bool = false
    ) -> FinalizedTranscript {
        let normalized = sourceTranscripts.sorted { lhs, rhs in
            if lhs.startOffsetMs == rhs.startOffsetMs {
                return sourceOrder(lhs.source) < sourceOrder(rhs.source)
            }
            return lhs.startOffsetMs < rhs.startOffsetMs
        }

        let shiftedWordsBySource = Dictionary(uniqueKeysWithValues: normalized.map { sourceTranscript in
            (
                sourceTranscript.source,
                shiftedWords(
                    for: sourceTranscript.result,
                    source: sourceTranscript.source,
                    offsetMs: sourceTranscript.startOffsetMs
                )
            )
        })

        let systemWords = shiftedWordsBySource[.system] ?? []
        let sourceMicrophoneWords = shiftedWordsBySource[.microphone] ?? []
        let attributedMicrophoneWords =
            microphoneDiarization.map {
                SpeakerMerger.alignWordsToSpeakerTurns(
                    words: sourceMicrophoneWords, segments: $0.segments)
            } ?? sourceMicrophoneWords
        let microphoneWords = attributedMicrophoneWords.map { word in
            guard microphoneSpeakerDetection, word.speakerId == AudioSource.microphone.rawValue else { return word }
            return WordTimestamp(
                word: word.word, startMs: word.startMs, endMs: word.endMs, confidence: word.confidence,
                speakerId: AudioSource.unidentifiedMicrophoneSpeakerID)
        }
        let finalizedSystemWords: [WordTimestamp]
        if let systemDiarization {
            finalizedSystemWords = SpeakerMerger.alignWordsToSpeakerTurns(
                words: systemWords,
                segments: systemDiarization.segments
            )
        } else {
            finalizedSystemWords = systemWords
        }

        var mergedWords = microphoneWords + finalizedSystemWords

        mergedWords.sort {
            if $0.startMs == $1.startMs {
                return sourceOrder(id: $0.speakerId) < sourceOrder(id: $1.speakerId)
            }
            return $0.startMs < $1.startMs
        }

        let speakers = activeSpeakers(
            from: mergedWords, systemDiarization: systemDiarization,
            microphoneDiarization: microphoneDiarization
        )
        let diarizationSegments = diarizationEvidence(
            mergedWords: mergedWords,
            systemDiarization: systemDiarization,
            microphoneDiarization: microphoneDiarization
        )
        let rawTranscript = finalTranscriptText(
            from: normalized,
            mergedWords: mergedWords
        )

        return FinalizedTranscript(
            rawTranscript: rawTranscript,
            words: mergedWords,
            speakers: speakers,
            diarizationSegments: diarizationSegments,
            durationMs: mergedWords.map(\.endMs).max()
        )
    }

    /// Replace one track's attribution without changing canonical words or
    /// discarding the other track's speaker names and overlap evidence.
    static func reattributeWords(
        _ words: [WordTimestamp],
        source: AudioSource,
        diarization: SourceDiarization,
        existingSpeakers: [SpeakerInfo],
        existingSegments: [DiarizationSegmentRecord],
        microphoneSpeakerDetection: Bool
    ) -> FinalizedTranscript {
        let sourceWords = words.filter { AudioSource.forSpeakerID($0.speakerId) == source }.map {
            WordTimestamp(
                word: $0.word, startMs: $0.startMs, endMs: $0.endMs, confidence: $0.confidence,
                speakerId: source.rawValue)
        }
        var attributed = SpeakerMerger.alignWordsToSpeakerTurns(
            words: sourceWords, segments: diarization.segments
        ).makeIterator()
        let merged = words.map { word in
            guard AudioSource.forSpeakerID(word.speakerId) == source else { return word }
            let updated = attributed.next() ?? word
            guard source == .microphone, microphoneSpeakerDetection, updated.speakerId == source.rawValue else {
                return updated
            }
            return WordTimestamp(
                word: updated.word,
                startMs: updated.startMs,
                endMs: updated.endMs,
                confidence: updated.confidence,
                speakerId: AudioSource.unidentifiedMicrophoneSpeakerID)
        }
        var speakers = existingSpeakers.filter { AudioSource.forSpeakerID($0.id) != source }
        speakers += diarization.speakers
        let fallbackID =
            source == .microphone && microphoneSpeakerDetection
            ? AudioSource.unidentifiedMicrophoneSpeakerID : source.rawValue
        if merged.contains(where: { $0.speakerId == fallbackID }) {
            speakers.append(
                SpeakerInfo(
                    id: fallbackID,
                    label: fallbackID == AudioSource.unidentifiedMicrophoneSpeakerID
                        ? "Local Speakers" : source.displayLabel))
        }
        let segments =
            existingSegments.filter { AudioSource.forSpeakerID($0.speakerId) != source }
            + diarization.segments.map {
                DiarizationSegmentRecord(
                    speakerId: $0.speakerId,
                    startMs: $0.startMs, endMs: $0.endMs)
            }

        return FinalizedTranscript(
            rawTranscript: transcriptText(from: merged),
            words: merged,
            speakers: speakers,
            diarizationSegments: segments.sorted {
                if $0.startMs == $1.startMs { return $0.speakerId < $1.speakerId }
                return $0.startMs < $1.startMs
            },
            durationMs: merged.map(\.endMs).max()
        )
    }

    private static func shiftedWords(
        for result: STTResult,
        source: AudioSource,
        offsetMs: Int
    ) -> [WordTimestamp] {
        result.words.map {
            WordTimestamp(
                word: $0.word,
                startMs: $0.startMs + offsetMs,
                endMs: $0.endMs + offsetMs,
                confidence: $0.confidence,
                speakerId: source.rawValue
            )
        }
    }

    private static func activeSpeakers(
        from words: [WordTimestamp],
        systemDiarization: SourceDiarization?,
        microphoneDiarization: SourceDiarization? = nil
    ) -> [SpeakerInfo] {
        let wordSpeakerIDs = Set(words.compactMap(\.speakerId))
        let regionSpeakerIDs = Set(
            (systemDiarization?.segments.map(\.speakerId) ?? [])
                + (microphoneDiarization?.segments.map(\.speakerId) ?? []))
        let activeIDs = wordSpeakerIDs.union(regionSpeakerIDs)
        var speakers: [SpeakerInfo] = []

        if activeIDs.contains(AudioSource.microphone.rawValue) {
            speakers.append(SpeakerInfo(id: AudioSource.microphone.rawValue, label: AudioSource.microphone.displayLabel))
        }

        if activeIDs.contains(AudioSource.unidentifiedMicrophoneSpeakerID) {
            speakers.append(SpeakerInfo(id: AudioSource.unidentifiedMicrophoneSpeakerID, label: "Local Speakers"))
        }

        if activeIDs.contains(AudioSource.system.rawValue) {
            speakers.append(SpeakerInfo(id: AudioSource.system.rawValue, label: AudioSource.system.displayLabel))
        }

        for diarization in [microphoneDiarization, systemDiarization].compactMap({ $0 }) {
            for speaker in diarization.speakers where activeIDs.contains(speaker.id) {
                speakers.append(speaker)
            }
        }

        return speakers
    }

    private static func diarizationEvidence(
        mergedWords: [WordTimestamp],
        systemDiarization: SourceDiarization?,
        microphoneDiarization: SourceDiarization? = nil
    ) -> [DiarizationSegmentRecord] {
        guard systemDiarization != nil || microphoneDiarization != nil else {
            return buildDiarizationSegments(from: mergedWords)
        }

        let segments = [AudioSource.microphone, .system].flatMap { source -> [DiarizationSegmentRecord] in
            let diarization = source == .microphone ? microphoneDiarization : systemDiarization
            if let diarization {
                return diarization.segments.map {
                    DiarizationSegmentRecord(
                        speakerId: $0.speakerId,
                        startMs: $0.startMs,
                        endMs: $0.endMs
                    )
                }
            }
            return buildDiarizationSegments(
                from: mergedWords.filter { AudioSource.forSpeakerID($0.speakerId) == source })
        }
        return segments.sorted {
            if $0.startMs == $1.startMs { return $0.speakerId < $1.speakerId }
            return $0.startMs < $1.startMs
        }
    }

    private static func buildDiarizationSegments(from words: [WordTimestamp]) -> [DiarizationSegmentRecord] {
        guard let firstWord = words.first, let firstSpeaker = firstWord.speakerId else {
            return []
        }

        var segments: [DiarizationSegmentRecord] = []
        var currentSpeaker = firstSpeaker
        var currentStart = firstWord.startMs
        var currentEnd = firstWord.endMs

        for word in words.dropFirst() {
            guard let speakerId = word.speakerId else { continue }

            if speakerId == currentSpeaker, word.startMs - currentEnd <= 1500 {
                currentEnd = max(currentEnd, word.endMs)
            } else {
                segments.append(DiarizationSegmentRecord(
                    speakerId: currentSpeaker,
                    startMs: currentStart,
                    endMs: currentEnd
                ))
                currentSpeaker = speakerId
                currentStart = word.startMs
                currentEnd = word.endMs
            }
        }

        segments.append(DiarizationSegmentRecord(
            speakerId: currentSpeaker,
            startMs: currentStart,
            endMs: currentEnd
        ))
        return segments
    }

    private static func finalTranscriptText(
        from sourceTranscripts: [SourceTranscript],
        mergedWords: [WordTimestamp]
    ) -> String {
        let textualSourceTranscripts = sourceTranscripts.compactMap { sourceTranscript -> (source: AudioSource, text: String, hasWords: Bool)? in
            let text = sourceTranscript.result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return (sourceTranscript.source, text, !sourceTranscript.result.words.isEmpty)
        }
        let nonEmptyTexts = textualSourceTranscripts.map(\.text)

        if nonEmptyTexts.count == 1 {
            return nonEmptyTexts[0]
        }

        if mergedWords.isEmpty {
            return nonEmptyTexts.joined(separator: "\n\n")
        }

        if let orderedSourceTexts = orderedSourceTextsIfContiguous(
            from: textualSourceTranscripts,
            mergedWords: mergedWords
        ) {
            return orderedSourceTexts.joined(separator: " ")
        }

        return transcriptText(from: mergedWords)
    }

    private static func transcriptText(from words: [WordTimestamp]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(words.count)

        for word in words {
            let token = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }

            if parts.isEmpty || shouldAttachWithoutLeadingSpace(token) {
                parts.append(token)
            } else {
                parts.append(" \(token)")
            }
        }

        return parts.joined()
    }

    private static func shouldAttachWithoutLeadingSpace(_ token: String) -> Bool {
        guard let first = token.first else { return false }
        return ",.!?;:%)]}".contains(first)
    }

    private static func sourceOrder(_ source: AudioSource) -> Int {
        switch source {
        case .microphone:
            return 0
        case .system:
            return 1
        }
    }

    private static func sourceOrder(id: String?) -> Int {
        switch id {
        case let value? where AudioSource.forSpeakerID(value) == .microphone:
            return 0
        case AudioSource.system.rawValue:
            return 1
        case let value? where value.hasPrefix("\(AudioSource.system.rawValue):"):
            return 2
        default:
            return 3
        }
    }

    private static func orderedSourceTextsIfContiguous(
        from sourceTranscripts: [(source: AudioSource, text: String, hasWords: Bool)],
        mergedWords: [WordTimestamp]
    ) -> [String]? {
        let runSources = contiguousSources(from: mergedWords)
        guard !runSources.isEmpty else { return nil }
        guard Set(runSources).count == runSources.count else { return nil }
        let timedTextSources = sourceTranscripts.filter(\.hasWords).map(\.source)
        guard runSources == timedTextSources else { return nil }

        var orderedTexts: [String] = []
        orderedTexts.reserveCapacity(sourceTranscripts.count)
        for sourceTranscript in sourceTranscripts {
            guard !sourceTranscript.text.isEmpty else { return nil }
            orderedTexts.append(sourceTranscript.text)
        }
        return orderedTexts
    }

    private static func contiguousSources(from words: [WordTimestamp]) -> [AudioSource] {
        var sources: [AudioSource] = []
        var lastSource: AudioSource?

        for word in words {
            guard let source = source(for: word.speakerId) else { continue }
            guard source != lastSource else { continue }
            sources.append(source)
            lastSource = source
        }

        return sources
    }

    private static func source(for speakerID: String?) -> AudioSource? {
        switch speakerID {
        case let value? where AudioSource.forSpeakerID(value) == .microphone:
            return .microphone
        case AudioSource.system.rawValue:
            return .system
        case let value? where value.hasPrefix("\(AudioSource.system.rawValue):"):
            return .system
        default:
            return nil
        }
    }
}

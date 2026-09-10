import Foundation

/// Merges word-level timestamps with speaker diarization segments.
/// Both inputs must be sorted by start time.
public enum SpeakerMerger {

    /// Attribute complete words using speaker-region starts. Keep the current
    /// speaker through uncovered time; a later speaker start wins, even during
    /// overlap. A word crossing a change belongs to the new speaker. Leading
    /// words belong to the first detected speaker. Evidence times are unchanged.
    /// Live callers must hold words until the timeline covers their end times.
    public static func alignWordsToSpeakerTurns(
        words: [WordTimestamp], segments: [SpeakerSegment]
    ) -> [WordTimestamp] {
        let ordered = segments.enumerated().filter { $0.element.endMs > $0.element.startMs }
            .sorted {
                if $0.element.startMs == $1.element.startMs { return $0.offset < $1.offset }
                return $0.element.startMs < $1.element.startMs
            }.map(\.element)
        var turns: [SpeakerSegment] = []
        for region in ordered {
            if let previous = turns.last, previous.speakerId == region.speakerId {
                turns[turns.count - 1] = SpeakerSegment(
                    speakerId: previous.speakerId, startMs: previous.startMs,
                    endMs: max(previous.endMs, region.endMs)
                )
            } else {
                turns.append(region)
            }
        }
        guard !turns.isEmpty else { return words }
        let boundaries = turns.dropFirst().map(\.startMs)
        return words.map { word in
            var lower = 0
            var upper = boundaries.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                // Intervals are half-open: a word ending at B's start remains A.
                if word.endMs <= boundaries[middle], word.startMs < boundaries[middle] {
                    upper = middle
                } else {
                    lower = middle + 1
                }
            }
            var attributed = word
            attributed.speakerId = turns[lower].speakerId
            return attributed
        }
    }

    /// Assign a speakerId to each word based on which diarization segment has the most time overlap.
    /// Tie-breaking: earlier segment wins. No overlap → speakerId = nil.
    public static func mergeWordTimestampsWithSpeakers(
        words: [WordTimestamp],
        segments: [SpeakerSegment]
    ) -> [WordTimestamp] {
        guard !words.isEmpty, !segments.isEmpty else { return words }

        // Defensive sort — FluidAudio returns chronological output, but
        // the algorithm requires sorted input for correctness.
        let sortedWords = words.sorted { $0.startMs < $1.startMs }
        let sortedSegments = segments.sorted { $0.startMs < $1.startMs }

        var result = sortedWords
        var segIdx = 0

        for (wordIdx, word) in sortedWords.enumerated() {
            // Advance segIdx past segments that end before this word starts.
            // Since words are sorted by startMs, segments before segIdx can never
            // overlap any future word either, making this amortized O(W+S).
            while segIdx < sortedSegments.count && sortedSegments[segIdx].endMs <= word.startMs {
                segIdx += 1
            }

            var bestSpeaker: String? = nil
            var bestOverlap = 0

            // Scan forward from segIdx to find the segment with most overlap
            var s = segIdx
            while s < sortedSegments.count {
                let seg = sortedSegments[s]
                if seg.startMs >= word.endMs {
                    break // No more segments can overlap this word
                }

                let overlapStart = max(word.startMs, seg.startMs)
                let overlapEnd = min(word.endMs, seg.endMs)
                let overlap = overlapEnd - overlapStart

                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestSpeaker = seg.speakerId
                }
                // Tie-breaking: earlier segment wins (first match with same overlap kept)

                s += 1
            }

            if bestOverlap > 0 {
                result[wordIdx].speakerId = bestSpeaker
            }
        }

        return result
    }
}

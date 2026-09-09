import Foundation

/// A time index over original evidence, separate from saved reading order.
/// Build once when the document changes; playback never reorders the document.
public struct ReadingTurnPlaybackIndex: Sendable {
    private struct Entry: Sendable {
        let startMs: Int
        let endMs: Int
        let reference: Int
        let turnID: ReadingTurnIdentity
    }

    private let entries: [Entry]
    private let prefixEndMs: [Int]

    public init(turns: [ReadingTurn], words: [WordTimestamp]) {
        entries = turns.flatMap { turn in
            turn.wordReferences.compactMap { reference -> Entry? in
                guard words.indices.contains(reference) else { return nil }
                let word = words[reference]
                return Entry(startMs: word.startMs, endMs: word.endMs, reference: reference, turnID: turn.id)
            }
        }.sorted {
            // An upper-bound lookup chooses the first evidence reference when
            // several words share a start, independent of display position.
            $0.startMs == $1.startMs ? $0.reference > $1.reference : $0.startMs < $1.startMs
        }
        var maximumEnd = Int.min
        prefixEndMs = entries.map {
            maximumEnd = max(maximumEnd, $0.endMs)
            return maximumEnd
        }
    }

    public func turnID(at timeMs: Int) -> ReadingTurnIdentity? {
        var low = 0
        var high = entries.count
        while low < high {
            let middle = low + (high - low) / 2
            if entries[middle].startMs <= timeMs { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let latest = low - 1
        var index = latest
        // Prefer a word still active at this time. A resumed surrounding turn
        // can have old words whose enclosing turn range covers an interjection.
        while index >= 0, prefixEndMs[index] >= timeMs {
            if entries[index].endMs >= timeMs { return entries[index].turnID }
            index -= 1
        }
        // In silence, retain the most recent evidence target (legacy behavior).
        return entries[latest].turnID
    }
}

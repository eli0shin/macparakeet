import Foundation

/// Confirmed source-local silence. Times use the same aligned timeline as words.
/// A gap is evidence, not an instruction to cut a word or discard short speech.
public struct SpeechActivityGap: Codable, Sendable, Equatable {
    public let source: ReadingTurnSource
    public let startMs: Int
    public let endMs: Int

    public init(source: ReadingTurnSource, startMs: Int, endMs: Int) {
        self.source = source
        self.startMs = startMs
        self.endMs = endMs
    }
}

/// Offline-only assembly. Legacy documents continue through the old builder;
/// new documents are saved and never run this ordering algorithm on read.
public enum FinalTranscriptAssembler {
    // One Silero inference frame. This is boundary uncertainty, not a pause rule.
    static let boundaryUncertaintyMs = 256

    public static func build(
        transcriptText: String,
        words: [WordTimestamp],
        speakers: [SpeakerInfo],
        diarizationSegments: [DiarizationSegmentRecord],
        activityGaps: [SpeechActivityGap] = [],
        customWords: [CustomWord] = [],
        cleanup: MeetingTranscriptCleanup = .cleaned
    ) -> MeetingTranscriptPresentationDocument {
        guard !words.isEmpty else {
            return MeetingTranscriptPresentationBuilder.build(
                transcriptText: transcriptText, words: nil, speakers: nil,
                customWords: customWords, cleanup: cleanup
            )
        }
        let lanes = Dictionary(grouping: words.indices, by: { words[$0].speakerId ?? "" })
        var blocks: [Block] = []
        for (speaker, references) in lanes {
            let source = MeetingTranscriptPresentationBuilder.readingSource(for: words[references[0]].speakerId)
            // The finalizer also stores word-derived fallback regions under
            // capture-source IDs. Those are not measured activity or silence.
            let regions = diarizationSegments.filter {
                $0.speakerId == speaker && speaker != AudioSource.microphone.rawValue
                    && speaker != AudioSource.system.rawValue
                    && speaker != AudioSource.unidentifiedMicrophoneSpeakerID
            }
            .sorted { $0.startMs < $1.startMs }
            var gaps = activityGaps.filter { $0.source == source || $0.source == .unknown }
                .map { ($0.startMs, $0.endMs) }
            // Use positive speaker regions before exclusive overlap trimming.
            // A later same-speaker region establishes a gap only after the union
            // of preceding regions ends.
            var regionEnd: Int?
            for region in regions {
                if let end = regionEnd, region.startMs > end {
                    gaps.append((end, region.startMs))
                }
                regionEnd = max(regionEnd ?? region.endMs, region.endMs)
            }
            // Preserve evidence order within each speaker, including imperfect
            // timestamps. Ordering contributions must not reorder their words.
            let ordered = references
            let otherLanes = lanes.filter { $0.key != speaker }.values.map { lane in
                (lane.map { words[$0].startMs }.min()!, lane.map { words[$0].endMs }.max()!)
            }
            var current: [Int] = []
            for reference in ordered {
                if let previous = current.last {
                    let end = words[previous].endMs
                    let start = words[reference].startMs
                    let confirmedGap = gaps.contains { max($0.0, end) < min($0.1, start) }
                    // Without activity evidence, preserve a complete handoff
                    // visible between words. Do not infer silence from time alone.
                    let completedExchange =
                        regions.isEmpty && gaps.isEmpty
                        && otherLanes.contains { $0.0 >= end && $0.1 <= start }
                    if confirmedGap || completedExchange {
                        blocks.append(Block(references: current, words: words))
                        current = []
                    }
                }
                current.append(reference)
            }
            if !current.isEmpty { blocks.append(Block(references: current, words: words)) }
        }
        blocks.sort {
            $0.start == $1.start ? $0.references[0] < $1.references[0] : $0.start < $1.start
        }

        // Assign each block to its nearest clear container. A crossing block
        // remains a sibling; no permanent microphone/system priority exists.
        var children = Array(repeating: [Int](), count: blocks.count)
        var roots: [Int] = []
        for index in blocks.indices {
            let child = blocks[index]
            let parent = (0..<index).reversed().first { candidate in
                let outer = blocks[candidate]
                return child.start - outer.start > boundaryUncertaintyMs
                    && outer.end - child.end > boundaryUncertaintyMs
            }
            if let parent { children[parent].append(index) } else { roots.append(index) }
        }
        var runs: [[Int]] = []
        func emit(_ index: Int) {
            let block = blocks[index]
            var cursor = 0
            var childCursor = 0
            while childCursor < children[index].count {
                let first = children[index][childCursor]
                let anchor = blocks[first].start
                var split = cursor
                // Starts inside a word insert after it. Starts in a gap insert
                // between its neighbors, never at a distant sentence boundary.
                while split < block.references.count, words[block.references[split]].startMs < anchor {
                    split += 1
                }
                if split > cursor { runs.append(Array(block.references[cursor..<split])) }
                cursor = split
                var chainEnd = blocks[first].end
                emit(first)
                childCursor += 1
                while childCursor < children[index].count {
                    let next = children[index][childCursor]
                    guard blocks[next].start < chainEnd else { break }
                    chainEnd = max(chainEnd, blocks[next].end)
                    emit(next)
                    childCursor += 1
                }
            }
            if cursor < block.references.count { runs.append(Array(block.references[cursor...])) }
        }
        for root in roots { emit(root) }
        return MeetingTranscriptPresentationDocument(
            turns: runs.map {
                MeetingTranscriptPresentationBuilder.makeFinalTurn(
                    references: $0, words: words, speakers: speakers,
                    customWords: customWords, cleanup: cleanup
                )
            },
            activityGaps: activityGaps
        )
    }

    private struct Block {
        let references: [Int]
        let start: Int
        let end: Int

        init(references: [Int], words: [WordTimestamp]) {
            self.references = references
            start = references.map { words[$0].startMs }.min()!
            end = references.map { words[$0].endMs }.max()!
        }
    }
}

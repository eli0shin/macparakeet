import FluidAudio
import Foundation

/// Source-relative candidate spans are authoritative. Never search corrected
/// text for a matching word later in the recording to infer its timestamp.
enum CustomVocabularyTiming {
    static func applying(
        _ edits: [CustomVocabularyEdit],
        to transcript: String,
        tokenTimings: [TokenTiming]
    ) throws -> [TokenTiming] {
        let parts = transcript.split(whereSeparator: \.isWhitespace)
        let words = STTWordTimingBuilder.words(from: tokenTimings)
        guard !edits.isEmpty, parts.count == words.count,
            zip(parts, words).allSatisfy({ String($0.0) == $0.1.word })
        else { throw CustomVocabularyBoostingError.unavailableAudioOrTimings }
        let ranges = parts.map { part in
            transcript.utf8.distance(
                from: transcript.startIndex, to: part.startIndex)..<transcript.utf8.distance(
                    from: transcript.startIndex, to: part.endIndex)
        }
        var output: [TokenTiming] = []
        var cursor = 0
        func append(_ word: String, start: Double, end: Double, confidence: Float) {
            output.append(
                TokenTiming(
                    token: "▁\(word)", tokenId: -1 - output.count,
                    startTime: start, endTime: end, confidence: confidence))
        }
        func preserve(_ range: Range<Int>) {
            for index in range {
                append(
                    words[index].word, start: Double(words[index].startMs) / 1_000,
                    end: Double(words[index].endMs) / 1_000, confidence: Float(words[index].confidence))
            }
        }
        for edit in edits.sorted(by: { $0.utf8Range.lowerBound < $1.utf8Range.lowerBound }) {
            guard let first = ranges.firstIndex(where: { $0.overlaps(edit.utf8Range) }),
                let last = ranges.lastIndex(where: { $0.overlaps(edit.utf8Range) }), first >= cursor,
                edit.utf8Range.lowerBound >= ranges[first].lowerBound,
                edit.utf8Range.upperBound <= ranges[last].upperBound
            else { throw CustomVocabularyBoostingError.invalidCandidateRange }
            preserve(cursor..<first)
            let original = String(transcript[parts[first].startIndex..<parts[last].endIndex])
            let offset = ranges[first].lowerBound
            let localEdit = CustomVocabularyEdit(
                utf8Range: (edit.utf8Range.lowerBound - offset)..<(edit.utf8Range.upperBound - offset),
                text: edit.text, startTime: edit.startTime
            )
            let replacement = try CustomVocabularyEdit.applying([localEdit], to: original)
                .split(whereSeparator: \.isWhitespace)
            guard !replacement.isEmpty else { throw CustomVocabularyBoostingError.invalidCandidateRange }
            let start = Double(words[first].startMs) / 1_000
            let end = max(start, Double(words[last].endMs) / 1_000)
            let step = (end - start) / Double(replacement.count)
            for (index, word) in replacement.enumerated() {
                append(
                    String(word), start: start + step * Double(index),
                    end: index == replacement.count - 1 ? end : start + step * Double(index + 1), confidence: 0)
            }
            cursor = last + 1
        }
        preserve(cursor..<words.count)
        return output
    }
}

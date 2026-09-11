import Foundation

/// Persists consecutive contributions in the finalized evidence order.
/// Speaker attribution belongs to diarization alignment, not reading layout.
public enum FinalTranscriptAssembler {
    public static func build(
        transcriptText: String,
        words: [WordTimestamp],
        speakers: [SpeakerInfo],
        customWords: [CustomWord] = [],
        cleanup: MeetingTranscriptCleanup = .cleaned
    ) -> MeetingTranscriptPresentationDocument {
        guard !words.isEmpty else {
            return MeetingTranscriptPresentationBuilder.build(
                transcriptText: transcriptText, words: nil, speakers: nil,
                customWords: customWords, cleanup: cleanup
            )
        }

        var runs: [[Int]] = []
        for reference in words.indices {
            if let previous = runs.last?.last,
                words[previous].speakerId == words[reference].speakerId
            {
                runs[runs.count - 1].append(reference)
            } else {
                runs.append([reference])
            }
        }
        return MeetingTranscriptPresentationDocument(
            turns: runs.map {
                MeetingTranscriptPresentationBuilder.makeFinalTurn(
                    references: $0, words: words, speakers: speakers,
                    customWords: customWords, cleanup: cleanup
                )
            }
        ).droppingEmptyTurns()
    }
}

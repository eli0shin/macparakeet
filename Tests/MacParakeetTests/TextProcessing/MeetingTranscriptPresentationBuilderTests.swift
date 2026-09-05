import XCTest
@testable import MacParakeetCore

final class MeetingTranscriptPresentationBuilderTests: XCTestCase {
    func testBuildsCompleteSourceAwareReadingTurnDocumentWithoutChangingEvidence() {
        let words = [
            word("I", 0, 100, "microphone"),
            word("will", 150, 300, "microphone"),
            word("ship.", 350, 600, "microphone"),
            word("Yes,", 100, 250, "system:S1"),
            word("that", 300, 450, "system"),
            word("works.", 500, 750, "system:S1"),
        ]
        let originalWords = words

        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "I will ship. Yes, that works.",
            words: words,
            speakers: [
                SpeakerInfo(id: "microphone", label: "Incorrect remote label"),
                SpeakerInfo(id: "system:S1", label: "Avery"),
            ]
        )

        XCTAssertEqual(
            document,
            MeetingTranscriptPresentationDocument(turns: [
                ReadingTurn(
                    id: ReadingTurnIdentity(
                        source: .microphone,
                        speakerId: "microphone",
                        firstWordIndex: 0
                    ),
                    speakerId: "microphone",
                    speakerLabel: "Me",
                    source: .microphone,
                    timeRange: ReadingTurnTimeRange(startMs: 0, endMs: 600),
                    paragraphs: [
                        ReadingTurnParagraph(
                            text: "I will ship.",
                            wordReferences: [0, 1, 2]
                        )
                    ],
                    wordReferences: [0, 1, 2]
                ),
                ReadingTurn(
                    id: ReadingTurnIdentity(
                        source: .system,
                        speakerId: "system:S1",
                        firstWordIndex: 3
                    ),
                    speakerId: "system:S1",
                    speakerLabel: "Avery",
                    source: .system,
                    timeRange: ReadingTurnTimeRange(startMs: 100, endMs: 750),
                    paragraphs: [
                        ReadingTurnParagraph(
                            text: "Yes, that works.",
                            wordReferences: [3, 4, 5]
                        )
                    ],
                    wordReferences: [3, 4, 5]
                ),
            ])
        )
        XCTAssertEqual(words, originalWords, "Presentation must not rewrite raw evidence")
    }

    func testUnpunctuatedSourceExchangePreservesChronologicalConversationTurns() {
        let words = [
            word("Question", 0, 200, "microphone"),
            word("Answer", 300, 500, "system"),
            word("Thanks", 600, 800, "microphone"),
        ]

        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "Question Answer Thanks",
            words: words,
            speakers: nil
        )

        XCTAssertEqual(
            document,
            MeetingTranscriptPresentationDocument(turns: [
                readingTurn(
                    source: .microphone,
                    speakerId: "microphone",
                    speakerLabel: "Me",
                    wordIndex: 0,
                    text: "Question",
                    startMs: 0,
                    endMs: 200
                ),
                readingTurn(
                    source: .system,
                    speakerId: "system",
                    speakerLabel: "Others",
                    wordIndex: 1,
                    text: "Answer",
                    startMs: 300,
                    endMs: 500
                ),
                readingTurn(
                    source: .microphone,
                    speakerId: "microphone",
                    speakerLabel: "Me",
                    wordIndex: 2,
                    text: "Thanks",
                    startMs: 600,
                    endMs: 800
                ),
            ])
        )
    }

    func testOverlappingSourceSpeechDoesNotCreateACompletedExchangeBoundary() {
        let words = [
            word("Question", 0, 400, "microphone"),
            word("Answer", 200, 700, "system"),
            word("Thanks", 600, 900, "microphone"),
        ]

        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "Question Answer Thanks",
            words: words,
            speakers: nil
        )

        XCTAssertEqual(document.turns.map(\.speakerLabel), ["Me", "Others"])
        XCTAssertEqual(document.turns.map(\.text), ["Question Thanks", "Answer"])
        XCTAssertEqual(document.turns.map(\.wordReferences), [[0, 2], [1]])
    }

    func testLegacyBareRemoteSpeakerIDsRemainSystemSourceWithFallbackWords() {
        let words = [
            word("That", 0, 200, "S1"),
            word("still", 250, 450, "system"),
            word("works.", 500, 800, "S1"),
        ]

        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "That still works.",
            words: words,
            speakers: [SpeakerInfo(id: "S1", label: "Avery")]
        )

        XCTAssertEqual(document.turns.count, 1)
        XCTAssertEqual(document.turns[0].source, .system)
        XCTAssertEqual(document.turns[0].speakerLabel, "Avery")
        XCTAssertEqual(document.turns[0].text, "That still works.")
    }

    func testLongTurnUsesParagraphsWithoutRepeatingTheSpeakerTurn() {
        let words = (0..<10).map { index in
            word("Sentence\(index).", index * 200, index * 200 + 100, "microphone")
        }

        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: words,
            speakers: nil
        )

        XCTAssertEqual(document.turns.count, 1)
        XCTAssertEqual(document.turns[0].speakerLabel, "Me")
        XCTAssertEqual(document.turns[0].paragraphs.count, 4)
        XCTAssertEqual(
            document.turns[0].paragraphs.map { $0.wordReferences.count },
            [3, 3, 3, 1]
        )
    }

    func testFallsBackToUntimedTextWithoutClaimingSourceOrTimePrecision() {
        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "  A useful legacy transcript.  ",
            words: nil,
            speakers: [SpeakerInfo(id: "S1", label: "Speaker 1")]
        )

        XCTAssertEqual(document.turns.count, 1)
        XCTAssertEqual(document.turns[0].speakerLabel, "Transcript")
        XCTAssertEqual(document.turns[0].source, .unknown)
        XCTAssertNil(document.turns[0].timeRange)
        XCTAssertEqual(document.turns[0].text, "A useful legacy transcript.")
        XCTAssertTrue(document.turns[0].wordReferences.isEmpty)
    }

    func testStableIdentityDoesNotDependOnDisplayLabel() {
        let words = [word("Hello.", 0, 300, "system:S1")]

        let beforeRename = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "Hello.",
            words: words,
            speakers: [SpeakerInfo(id: "system:S1", label: "Speaker 1")]
        )
        let afterRename = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "Hello.",
            words: words,
            speakers: [SpeakerInfo(id: "system:S1", label: "Morgan")]
        )

        XCTAssertEqual(beforeRename.turns.map(\.id), afterRename.turns.map(\.id))
        XCTAssertEqual(afterRename.turns.map(\.speakerLabel), ["Morgan"])
    }

    func testOneHourDocumentRemainsTurnBoundedInsteadOfWordBounded() {
        let wordsPerMinute = 120
        let words = (0..<(60 * wordsPerMinute)).map { index in
            let minute = index / wordsPerMinute
            let token = index % 20 == 19 ? "word." : "word"
            return word(
                token,
                index * 500,
                index * 500 + 300,
                minute.isMultiple(of: 2) ? "microphone" : "system:S1"
            )
        }

        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: words,
            speakers: [SpeakerInfo(id: "system:S1", label: "Remote")]
        )

        XCTAssertEqual(document.turns.count, 60)
        XCTAssertLessThan(document.turns.count, words.count / 100)
        XCTAssertEqual(document.turns.flatMap(\.wordReferences).count, words.count)
    }

    private func readingTurn(
        source: ReadingTurnSource,
        speakerId: String,
        speakerLabel: String,
        wordIndex: Int,
        text: String,
        startMs: Int,
        endMs: Int
    ) -> ReadingTurn {
        ReadingTurn(
            id: ReadingTurnIdentity(
                source: source,
                speakerId: speakerId,
                firstWordIndex: wordIndex
            ),
            speakerId: speakerId,
            speakerLabel: speakerLabel,
            source: source,
            timeRange: ReadingTurnTimeRange(startMs: startMs, endMs: endMs),
            paragraphs: [
                ReadingTurnParagraph(text: text, wordReferences: [wordIndex])
            ],
            wordReferences: [wordIndex]
        )
    }

    private func word(_ text: String, _ startMs: Int, _ endMs: Int, _ speakerId: String?) -> WordTimestamp {
        WordTimestamp(
            word: text,
            startMs: startMs,
            endMs: endMs,
            confidence: 0.9,
            speakerId: speakerId
        )
    }
}

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

    func testSourceExchangeCreatesConversationTurnsWithoutWordLevelInterleaving() {
        let words = [
            word("My", 0, 200, "microphone"),
            word("question.", 250, 500, "microphone"),
            word("The", 600, 800, "system"),
            word("answer.", 850, 1_100, "system"),
            word("Thanks.", 1_200, 1_500, "microphone"),
        ]

        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "My question. The answer. Thanks.",
            words: words,
            speakers: nil
        )

        XCTAssertEqual(document.turns.map(\.speakerLabel), ["Me", "Others", "Me"])
        XCTAssertEqual(document.turns.map(\.text), ["My question.", "The answer.", "Thanks."])
        XCTAssertEqual(document.turns.map(\.wordReferences), [[0, 1], [2, 3], [4]])
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

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

    func testIsolatedShortRemoteSpeakerFlipIsAbsorbedByStableNeighbors() {
        let words = [
            word("We", 0, 180, "system:S1"),
            word("should", 200, 380, "system:S1"),
            word("proceed.", 400, 700, "system:S1"),
            word("Actually.", 800, 1_100, "system:S2"),
            word("The", 1_200, 1_380, "system:S1"),
            word("plan", 1_400, 1_580, "system:S1"),
            word("is", 1_600, 1_720, "system:S1"),
            word("ready.", 1_740, 2_000, "system:S1"),
        ]

        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: words,
            speakers: remoteSpeakers,
            diarizationSegments: [
                segment("system:S1", 0, 700),
                segment("system:S2", 800, 1_100),
                segment("system:S1", 1_200, 2_000),
            ]
        )

        XCTAssertEqual(document.turns.map(\.speakerId), ["system:S1"])
        XCTAssertEqual(document.turns.map(\.text), ["We should proceed. Actually. The plan is ready."])
        XCTAssertEqual(document.turns[0].wordReferences, Array(words.indices))
    }

    func testSustainedRemoteExchangeRetainsThreeSpeakerTurns() {
        let words = [
            word("Opening.", 0, 600, "system:S1"),
            word("This", 800, 1_200, "system:S2"),
            word("is", 1_220, 1_500, "system:S2"),
            word("substantial.", 1_520, 2_100, "system:S2"),
            word("Closing.", 2_300, 2_900, "system:S1"),
        ]

        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: words,
            speakers: remoteSpeakers,
            diarizationSegments: [
                segment("system:S1", 0, 600),
                segment("system:S2", 800, 2_100),
                segment("system:S1", 2_300, 2_900),
            ]
        )

        XCTAssertEqual(document.turns.map(\.speakerId), ["system:S1", "system:S2", "system:S1"])
        XCTAssertEqual(document.turns.map(\.text), ["Opening.", "This is substantial.", "Closing."])
    }

    func testFinalizedRawOverlapKeepsSubthresholdFlipFromBecomingReadingTurn() {
        let finalized = MeetingTranscriptFinalizer.finalize(
            sourceTranscripts: [
                .init(
                    source: .system,
                    result: STTResult(
                        text: "Opening. Wait. Closing.",
                        words: [
                            TimestampedWord(word: "Opening.", startMs: 0, endMs: 500, confidence: 0.9),
                            TimestampedWord(word: "Wait.", startMs: 500, endMs: 1_500, confidence: 0.9),
                            TimestampedWord(word: "Closing.", startMs: 1_600, endMs: 2_100, confidence: 0.9),
                        ]
                    ),
                    startOffsetMs: 0
                )
            ],
            systemDiarization: .init(
                speakers: remoteSpeakers,
                segments: [
                    SpeakerSegment(speakerId: "system:S1", startMs: 0, endMs: 500),
                    SpeakerSegment(speakerId: "system:S2", startMs: 700, endMs: 1_300),
                    SpeakerSegment(speakerId: "system:S1", startMs: 1_600, endMs: 2_100),
                ]
            )
        )
        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: finalized.rawTranscript,
            words: finalized.words,
            speakers: finalized.speakers,
            diarizationSegments: finalized.diarizationSegments
        )

        XCTAssertEqual(finalized.words.map(\.speakerId), ["system:S1", "system:S2", "system:S1"])
        XCTAssertEqual(finalized.diarizationSegments[1], segment("system:S2", 700, 1_300))
        XCTAssertEqual(document.turns.map(\.speakerId), ["system:S1"])
        XCTAssertEqual(document.turns.map(\.text), ["Opening. Wait. Closing."])
    }

    func testAggregateSpeakerKeepsRosterLabelWhenNoWordReceivedThatSpeaker() {
        let finalized = MeetingTranscriptFinalizer.finalize(
            sourceTranscripts: [
                .init(
                    source: .system,
                    result: STTResult(
                        text: "Hello there.",
                        words: [
                            TimestampedWord(word: "Hello", startMs: 0, endMs: 300, confidence: 0.9),
                            TimestampedWord(word: "there.", startMs: 700, endMs: 1_000, confidence: 0.9),
                        ]
                    ),
                    startOffsetMs: 0
                )
            ],
            systemDiarization: .init(
                speakers: remoteSpeakers,
                segments: [
                    SpeakerSegment(speakerId: "system:S1", startMs: 0, endMs: 200),
                    SpeakerSegment(speakerId: "system:S2", startMs: 250, endMs: 750),
                    SpeakerSegment(speakerId: "system:S1", startMs: 800, endMs: 1_000),
                ]
            )
        )
        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: finalized.rawTranscript,
            words: finalized.words,
            speakers: finalized.speakers,
            diarizationSegments: finalized.diarizationSegments
        )

        XCTAssertEqual(finalized.words.map(\.speakerId), ["system:S1", "system:S1"])
        XCTAssertEqual(finalized.speakers, remoteSpeakers)
        XCTAssertEqual(document.turns.map(\.speakerId), ["system:S2"])
        XCTAssertEqual(document.turns.map(\.speakerLabel), ["Blake"])
    }

    func testAggregateDiarizationOverlapAssignsFallbackWordsToRefinedSpeaker() {
        let words = [
            word("That", 0, 250, "system:S2"),
            word("still", 270, 520, "system"),
            word("works.", 540, 800, "system:S2"),
        ]
        let originalWords = words

        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: words,
            speakers: remoteSpeakers,
            diarizationSegments: [segment("system:S1", 0, 800)]
        )

        XCTAssertEqual(document.turns.map(\.speakerId), ["system:S1"])
        XCTAssertEqual(document.turns.map(\.speakerLabel), ["Avery"])
        XCTAssertEqual(document.turns.map(\.text), ["That still works."])
        XCTAssertEqual(words, originalWords, "Presentation smoothing must not rewrite word labels")
    }

    func testSameSpeakerUtterancesMergeAcrossShortPauseButNotClearBreak() {
        let words = [
            word("First.", 0, 500, "system:S1"),
            word("Second.", 1_000, 1_500, "system:S1"),
            word("Later.", 4_000, 4_500, "system:S1"),
        ]

        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: words,
            speakers: remoteSpeakers,
            diarizationSegments: [
                segment("system:S1", 0, 500),
                segment("system:S1", 1_000, 1_500),
                segment("system:S1", 4_000, 4_500),
            ]
        )

        XCTAssertEqual(document.turns.map(\.text), ["First. Second.", "Later."])
        XCTAssertEqual(document.turns.map { $0.timeRange?.startMs }, [0, 4_000])
    }

    func testMicrophoneIdentityIgnoresRemoteDiarizationEvidence() {
        let words = [word("Mine.", 0, 500, "microphone")]

        let document = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: words,
            speakers: remoteSpeakers,
            diarizationSegments: [segment("system:S2", 0, 500)]
        )

        XCTAssertEqual(document.turns.map(\.speakerId), ["microphone"])
        XCTAssertEqual(document.turns.map(\.speakerLabel), ["Me"])
    }

    func testNoisyFixtureReportsReadabilityMetricsBeforeAndAfterStabilization() {
        let words = [
            word("We", 0, 180, "system:S1"),
            word("can", 200, 380, "system:S1"),
            word("start.", 400, 700, "system:S1"),
            word("Wait.", 800, 1_100, "system:S2"),
            word("The", 1_200, 1_380, "system:S1"),
            word("plan", 1_400, 1_580, "system:S1"),
            word("works.", 1_600, 1_800, "system:S1"),
            word("Well.", 1_900, 2_200, "system"),
            word("Let", 2_300, 2_480, "system:S1"),
            word("us", 2_500, 2_680, "system:S1"),
            word("continue.", 2_700, 2_900, "system:S1"),
        ]
        let rawWordLabelDocument = MeetingTranscriptPresentationDocument(turns: [
            metricTurn("system:S1", 0..<3, 0, 700),
            metricTurn("system:S2", 3..<4, 800, 1_100),
            metricTurn("system:S1", 4..<7, 1_200, 1_800),
            metricTurn("system", 7..<8, 1_900, 2_200),
            metricTurn("system:S1", 8..<11, 2_300, 2_900),
        ])
        let stabilizedDocument = MeetingTranscriptPresentationBuilder.build(
            transcriptText: "",
            words: words,
            speakers: remoteSpeakers,
            diarizationSegments: [
                segment("system:S1", 0, 700),
                segment("system:S2", 800, 1_100),
                segment("system:S1", 1_200, 1_800),
                segment("system:S1", 2_300, 2_900),
            ]
        )

        let before = ReadingTurnReadabilityMetrics.measure(rawWordLabelDocument)
        let after = ReadingTurnReadabilityMetrics.measure(stabilizedDocument)

        XCTAssertEqual(before.turnsPerMinute, 103.448, accuracy: 0.001)
        XCTAssertEqual(after.turnsPerMinute, 20.690, accuracy: 0.001)
        XCTAssertEqual(before.blocksShorterThanThreeWords, 2)
        XCTAssertEqual(after.blocksShorterThanThreeWords, 0)
        XCTAssertEqual(before.isolatedSpeakerFlips, 2)
        XCTAssertEqual(after.isolatedSpeakerFlips, 0)
        XCTAssertEqual(before.fallbackSpeakerTransitions, 2)
        XCTAssertEqual(after.fallbackSpeakerTransitions, 0)
        XCTAssertEqual(before.medianWordsPerTurn, 3)
        XCTAssertEqual(after.medianWordsPerTurn, 11)
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

    private func metricTurn(
        _ speakerId: String,
        _ wordRange: Range<Int>,
        _ startMs: Int,
        _ endMs: Int
    ) -> ReadingTurn {
        let references = Array(wordRange)
        return ReadingTurn(
            id: ReadingTurnIdentity(
                source: .system,
                speakerId: speakerId,
                firstWordIndex: references.first
            ),
            speakerId: speakerId,
            speakerLabel: speakerId,
            source: .system,
            timeRange: ReadingTurnTimeRange(startMs: startMs, endMs: endMs),
            paragraphs: [ReadingTurnParagraph(text: "fixture", wordReferences: references)],
            wordReferences: references
        )
    }

    private var remoteSpeakers: [SpeakerInfo] {
        [
            SpeakerInfo(id: "system:S1", label: "Avery"),
            SpeakerInfo(id: "system:S2", label: "Blake"),
        ]
    }

    private func segment(_ speakerId: String, _ startMs: Int, _ endMs: Int) -> DiarizationSegmentRecord {
        DiarizationSegmentRecord(speakerId: speakerId, startMs: startMs, endMs: endMs)
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

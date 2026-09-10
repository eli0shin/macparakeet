import XCTest
@testable import MacParakeetCore

final class MeetingLiveSpeakerContinuityTests: XCTestCase {
    private func snapshot(_ regions: [SpeakerSegment], through: Int) -> MeetingLiveDiarizationSnapshot {
        MeetingLiveDiarizationSnapshot(
            segments: regions,
            speakers: Array(Set(regions.map(\.speakerId))).sorted().map { SpeakerInfo(id: $0, label: $0) },
            committedThroughMs: through)
    }

    private func apply(
        _ assembler: inout MeetingTranscriptAssembler, start: Int, end: Int,
        source: AudioSource = .system, state: MeetingLiveDiarizationState
    ) -> MeetingTranscriptUpdate {
        assembler.apply(
            result: STTResult(text: "word\(start)", words: [
                TimestampedWord(word: "word\(start)", startMs: 0, endMs: end - start, confidence: 0.9)
            ]),
            chunk: AudioChunker.AudioChunk(samples: [0], startMs: start, endMs: end),
            source: source, liveDiarization: state)
    }

    func testLeadingWordsWaitThenBackfillAndGapsStayWithPreviousSpeakerAcrossChunks() {
        var assembler = MeetingTranscriptAssembler()
        XCTAssertTrue(apply(&assembler, start: 0, end: 100, state: .awaitingTimeline).words.isEmpty)
        XCTAssertNil(assembler.advanceLiveDiarization(snapshot([], through: 200), source: .system))
        XCTAssertTrue(apply(&assembler, start: 200, end: 300,
                            state: .timeline(snapshot([], through: 400))).words.isEmpty)
        let a = SpeakerSegment(speakerId: "system:A", startMs: 400, endMs: 500)
        let first = snapshot([a], through: 600)
        XCTAssertEqual(assembler.advanceLiveDiarization(first, source: .system)?.words.map(\.speakerId),
                       ["system:A", "system:A"])
        XCTAssertEqual(apply(&assembler, start: 550, end: 590, state: .timeline(first)).words.last?.speakerId,
                       "system:A")
        // Words beyond the committed timeline remain hidden, even with a known speaker.
        XCTAssertEqual(apply(&assembler, start: 790, end: 810, state: .timeline(first)).words.count, 3)
        let b = SpeakerSegment(speakerId: "system:B", startMs: 800, endMs: 900)
        let second = snapshot([a, b], through: 1_000)
        let update = assembler.advanceLiveDiarization(second, source: .system)
        XCTAssertEqual(update?.words.map(\.speakerId), ["system:A", "system:A", "system:A", "system:B"])
        XCTAssertEqual(apply(&assembler, start: 950, end: 990, state: .timeline(second)).words.last?.speakerId,
                       "system:B")
    }

    func testApplyUsesSameBoundaryRuleAsTimelineArrivalAndKeepsSourcesSeparate() {
        var assembler = MeetingTranscriptAssembler()
        let timeline = snapshot([
            SpeakerSegment(speakerId: "system:A", startMs: 0, endMs: 100),
            SpeakerSegment(speakerId: "system:B", startMs: 800, endMs: 900)
        ], through: 1_000)
        let update = apply(&assembler, start: 790, end: 801, state: .timeline(timeline))
        XCTAssertEqual(update.words.last?.speakerId, "system:B")
        _ = apply(&assembler, start: 0, end: 100, source: .microphone, state: .awaitingTimeline)
        XCTAssertEqual(assembler.currentUpdate.words.count, 1)
        let mic = snapshot([SpeakerSegment(speakerId: "microphone:A", startMs: 200, endMs: 300)], through: 400)
        let combined = assembler.advanceLiveDiarization(mic, source: .microphone)
        XCTAssertEqual(combined?.words.map(\.speakerId), ["microphone:A", "system:B"])
    }

    func testStopWithoutDetectionReleasesTextWithoutInventingSpeaker() {
        var assembler = MeetingTranscriptAssembler()
        _ = apply(&assembler, start: 0, end: 100, state: .awaitingTimeline)
        let update = assembler.stopLiveDiarization(for: .system)
        XCTAssertEqual(update?.words.map(\.word), ["word0"])
        // The source ID is provenance, not a detected voice.
        XCTAssertEqual(update?.words.map(\.speakerId), ["system"])
        XCTAssertEqual(update?.speakers.map(\.label), ["System audio"])
        XCTAssertNil(assembler.stopLiveDiarization(for: .system))
    }

    func testFailurePreservesAttributedWordsAndReleasesPendingWithoutCarryingSpeaker() {
        var assembler = MeetingTranscriptAssembler()
        let timeline = snapshot([SpeakerSegment(speakerId: "system:A", startMs: 0, endMs: 100)], through: 200)
        _ = apply(&assembler, start: 0, end: 100, state: .timeline(timeline))
        _ = apply(&assembler, start: 300, end: 400, state: .timeline(timeline))
        XCTAssertEqual(assembler.stopLiveDiarization(for: .system)?.words.map(\.speakerId), ["system:A", "system"])
        XCTAssertEqual(apply(&assembler, start: 500, end: 600, state: .disabled).words.last?.speakerId, "system")
    }
}

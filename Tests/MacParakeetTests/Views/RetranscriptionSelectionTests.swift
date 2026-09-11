import XCTest
@testable import MacParakeet
@testable import MacParakeetCore

final class RetranscriptionSelectionTests: XCTestCase {
    func testSelectingEngineImmediatelyRequestsRetranscription() {
        let transcription = Transcription(
            fileName: "Meeting.m4a",
            rawTranscript: "Original transcript",
            status: .completed,
            sourceType: .meeting
        )
        let selection = SpeechEngineSelection(engine: .whisper, language: "en")
        var request: (Transcription, SpeechEngineSelection?)?

        performRetranscriptionSelection(
            transcription: transcription,
            selection: selection,
            isPrimary: false,
            primaryReflectsTranscriptEngine: true
        ) {
            request = ($0, $1)
        }

        XCTAssertEqual(request?.0.id, transcription.id)
        XCTAssertEqual(request?.1, selection)
    }

    func testSelectingCurrentPrimaryEngineUsesCurrentSettingsRoute() {
        let transcription = Transcription(
            fileName: "Recording.m4a",
            rawTranscript: "Original transcript",
            status: .completed,
            sourceType: .file
        )
        var request: (Transcription, SpeechEngineSelection?)?

        performRetranscriptionSelection(
            transcription: transcription,
            selection: SpeechEngineSelection(engine: .parakeet),
            isPrimary: true,
            primaryReflectsTranscriptEngine: false
        ) {
            request = ($0, $1)
        }

        XCTAssertEqual(request?.0.id, transcription.id)
        XCTAssertNil(request?.1)
    }
}

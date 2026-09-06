import SwiftUI
import XCTest
import MacParakeetCore
@testable import MacParakeet

final class MeetingRowCardTests: XCTestCase {
    func testLegacyMeetingSnippetCleansRawTextBeforeUsingOldDerivedSnippet() {
        let transcription = Transcription(
            fileName: "meeting.m4a",
            rawTranscript: "uh ship foo today",
            status: .completed,
            sourceType: .meeting,
            derivedSnippet: "uh ship foo today"
        )
        let customWords = [CustomWord(word: "foo", replacement: "Acme")]

        XCTAssertEqual(
            MeetingRowCard<EmptyView>.snippetText(
                for: transcription,
                customWords: customWords
            ),
            "Ship Acme today"
        )
    }

    func testFillerOnlyLegacyMeetingDoesNotRestoreRawDerivedSnippet() {
        let transcription = Transcription(
            fileName: "meeting.m4a",
            rawTranscript: "uh uhh umm",
            status: .completed,
            sourceType: .meeting,
            derivedSnippet: "uh uhh umm"
        )

        XCTAssertNil(
            MeetingRowCard<EmptyView>.snippetText(
                for: transcription,
                customWords: []
            )
        )
    }

    func testPersistedMeetingAndNonMeetingSnippetsKeepDerivedPreference() {
        let meeting = Transcription(
            fileName: "meeting.m4a",
            rawTranscript: "raw meeting",
            cleanTranscript: "Clean meeting.",
            status: .completed,
            sourceType: .meeting,
            derivedSnippet: "Stored meeting snippet"
        )
        let file = Transcription(
            fileName: "file.m4a",
            rawTranscript: "raw file",
            status: .completed,
            sourceType: .file,
            derivedSnippet: "Stored file snippet"
        )

        XCTAssertEqual(
            MeetingRowCard<EmptyView>.snippetText(for: meeting, customWords: []),
            "Stored meeting snippet"
        )
        XCTAssertEqual(
            MeetingRowCard<EmptyView>.snippetText(for: file, customWords: []),
            "Stored file snippet"
        )
    }
}

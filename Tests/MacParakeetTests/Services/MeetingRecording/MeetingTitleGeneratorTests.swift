import XCTest
@testable import MacParakeetCore

final class MeetingTitleGeneratorTests: XCTestCase {
    func testGenerateTitleSendsCompleteTranscriptBeyondFormerCap() async throws {
        let llm = MockLLMService()
        llm.summarizeResult = "Complete Context Review"
        let generator = MeetingTitleGenerator(
            llmService: llm,
            shouldGenerate: { true },
            logger: .init(subsystem: "com.macparakeet.tests", category: "MeetingTitleGeneratorTests")
        )
        let transcript =
            "BEGIN_SENTINEL "
            + String(repeating: "meeting context ", count: 1_000)
            + "MIDDLE_SENTINEL "
            + String(repeating: "meeting context ", count: 1_000)
            + "END_SENTINEL"

        let title = try await generator.generateTitle(transcript: transcript, currentTitle: "Meeting")

        XCTAssertEqual(title, "Complete Context Review")
        XCTAssertEqual(llm.lastSummaryTranscript, transcript)
        XCTAssertEqual(llm.summarizeCallCount, 1)
    }

    func testGenerateTitleReturnsClearContextLimitError() async {
        let llm = MockLLMService()
        llm.errorToThrow = LLMError.contextTooLong
        let generator = MeetingTitleGenerator(
            llmService: llm,
            shouldGenerate: { true },
            logger: .init(subsystem: "com.macparakeet.tests", category: "MeetingTitleGeneratorTests")
        )

        do {
            _ = try await generator.generateTitle(
                transcript: String(repeating: "enough context ", count: 20),
                currentTitle: "Meeting"
            )
            XCTFail("Expected contextTooLong")
        } catch let error as LLMError {
            guard case .contextTooLong = error else {
                return XCTFail("Expected contextTooLong, got \(error)")
            }
            XCTAssertTrue(error.localizedDescription.contains("complete text"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShouldReplaceTimestampFallbackMeetingTitles() {
        XCTAssertTrue(MeetingTitleGenerator.shouldReplaceFallbackMeetingTitle("Meeting"))
        XCTAssertTrue(MeetingTitleGenerator.shouldReplaceFallbackMeetingTitle("Meeting Jun 17, 2026 at 09:59"))
        XCTAssertTrue(MeetingTitleGenerator.shouldReplaceFallbackMeetingTitle("Meeting June 17, 2026 at 9:59 AM"))
        XCTAssertTrue(MeetingTitleGenerator.shouldReplaceFallbackMeetingTitle("Meeting 6/17/2026"))
    }

    func testShouldPreserveCustomOrCalendarMeetingTitles() {
        XCTAssertFalse(MeetingTitleGenerator.shouldReplaceFallbackMeetingTitle("Customer Expansion Review"))
        XCTAssertFalse(MeetingTitleGenerator.shouldReplaceFallbackMeetingTitle("Weekly Product Sync"))
        XCTAssertFalse(MeetingTitleGenerator.shouldReplaceFallbackMeetingTitle("Meeting Notes for Acme"))
        XCTAssertFalse(MeetingTitleGenerator.shouldReplaceFallbackMeetingTitle("Meeting Product Review"))
        // A deliberate calendar/custom title that merely contains a year must not
        // be mistaken for the timestamp fallback and overwritten.
        XCTAssertFalse(MeetingTitleGenerator.shouldReplaceFallbackMeetingTitle("Meeting 2026 Budget Planning"))
        XCTAssertFalse(MeetingTitleGenerator.shouldReplaceFallbackMeetingTitle("Meeting Q1 2026 Kickoff"))
    }

    func testValidatedTitleNormalizesSimpleProviderResponses() {
        XCTAssertEqual(
            MeetingTitleGenerator.validatedTitle(from: #"  "Product Roadmap Review."  "#),
            "Product Roadmap Review"
        )
        XCTAssertEqual(
            MeetingTitleGenerator.validatedTitle(from: "- Customer Onboarding Risks"),
            "Customer Onboarding Risks"
        )
        XCTAssertEqual(
            MeetingTitleGenerator.validatedTitle(from: "1. Mobile Beta Launch"),
            "Mobile Beta Launch"
        )
    }

    func testValidatedTitleRejectsLowConfidenceResponses() {
        XCTAssertNil(MeetingTitleGenerator.validatedTitle(from: "Meeting"))
        XCTAssertNil(MeetingTitleGenerator.validatedTitle(from: "Discussion"))
        XCTAssertNil(MeetingTitleGenerator.validatedTitle(from: "NO_TITLE"))
        XCTAssertNil(MeetingTitleGenerator.validatedTitle(from: "Meeting Jun 17, 2026"))
        XCTAssertNil(MeetingTitleGenerator.validatedTitle(from: "Product Review\nCustomer Followup"))
        XCTAssertNil(MeetingTitleGenerator.validatedTitle(from: "One"))
        XCTAssertNil(
            MeetingTitleGenerator.validatedTitle(from: "This title has far too many words to be a usable meeting title")
        )
    }
}

import AppKit
import SwiftUI
import XCTest
import MacParakeetCore
@testable import MacParakeet

@MainActor
final class SavedMeetingCalendarVisualEvidenceTests: XCTestCase {
    func testRenderConfirmedProbablePartialAndAbsentCalendarContext() throws {
        guard let outputDirectory = ProcessInfo.processInfo.environment["SAVED_CALENDAR_EVIDENCE_DIR"] else {
            throw XCTSkip("Set SAVED_CALENDAR_EVIDENCE_DIR to render saved calendar context evidence.")
        }

        let start = Date(timeIntervalSince1970: 1_767_616_200)
        let confirmed = MeetingCalendarSnapshot(
            confidence: .confirmed,
            eventIdentifier: "confirmed",
            title: "Weekly Product Review",
            scheduledStartAt: start,
            scheduledEndAt: start.addingTimeInterval(3_600),
            attendees: [
                MeetingCalendarPerson(name: "Alice Example", email: "alice@example.com"),
                MeetingCalendarPerson(name: "Bob Example"),
            ],
            organizer: MeetingCalendarPerson(name: "Omar Organizer", email: "omar@example.com"),
            meetingURL: "https://zoom.us/j/123456789",
            meetingService: "Zoom"
        )
        var probable = confirmed
        probable.confidence = .probable
        probable.eventIdentifier = "probable"
        var partial = confirmed
        partial.eventIdentifier = "partial"
        partial.attendees = []
        partial.organizer = nil
        partial.meetingURL = nil
        partial.meetingService = nil

        let view = ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                evidenceCase(title: "Confirmed", snapshot: confirmed)
                evidenceCase(title: "Probable", snapshot: probable)
                evidenceCase(title: "Partial", snapshot: partial)
                evidenceCase(title: "Absent", snapshot: nil)
            }
            .padding(24)
        }
        .frame(width: 820, height: 980)
        .background(DesignSystem.Colors.background)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 820, height: 980)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return XCTFail("Could not allocate screenshot bitmap")
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            return XCTFail("Could not encode screenshot")
        }
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("saved-calendar-context.png"))
    }

    private func evidenceCase(
        title: String,
        snapshot: MeetingCalendarSnapshot?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(DesignSystem.Typography.sectionTitle)
                if let confidence = snapshot?.confidence {
                    SavedMeetingCalendarConnectionBadge(confidence: confidence)
                }
            }
            if let snapshot {
                SavedMeetingCalendarContextSection(snapshot: snapshot)
            }
            Text("Transcript starts here without an empty calendar section.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }
}

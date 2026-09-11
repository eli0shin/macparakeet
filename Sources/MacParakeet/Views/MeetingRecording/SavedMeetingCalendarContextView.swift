import MacParakeetCore
import SwiftUI

enum SavedMeetingCalendarPresentation {
    static func connectionTitle(for confidence: MeetingCalendarSnapshot.Confidence) -> String {
        switch confidence {
        case .confirmed:
            return "Calendar"
        case .probable:
            return "Possible match"
        }
    }

    static func connectionHelp(for confidence: MeetingCalendarSnapshot.Confidence) -> String {
        switch confidence {
        case .confirmed:
            return "Started from a calendar event"
        case .probable:
            return "Possible calendar match based on overlapping time"
        }
    }

    static func confidenceTitle(for confidence: MeetingCalendarSnapshot.Confidence) -> String {
        switch confidence {
        case .confirmed:
            return "Confirmed calendar event"
        case .probable:
            return "Possible calendar match"
        }
    }

    static func confidenceDetail(for confidence: MeetingCalendarSnapshot.Confidence) -> String {
        switch confidence {
        case .confirmed:
            return "This recording was started from this calendar event."
        case .probable:
            return "This recording overlapped this event. Verify the match before relying on its details."
        }
    }

    static func personText(_ person: MeetingCalendarPerson) -> String? {
        let name = normalized(person.name)
        let email = normalized(person.email)
        switch (name, email) {
        case let (.some(name), .some(email)):
            return "\(name) (\(email))"
        case let (.some(name), .none):
            return name
        case let (.none, .some(email)):
            return email
        case (.none, .none):
            return nil
        }
    }

    static func attendeeText(_ attendees: [MeetingCalendarPerson]) -> String? {
        let people = attendees.compactMap(personText)
        return people.isEmpty ? nil : people.joined(separator: ", ")
    }

    static func actionableMeetingURL(_ value: String?) -> URL? {
        guard let value = normalized(value),
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            url.host != nil
        else {
            return nil
        }
        return url
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

struct SavedMeetingCalendarConnectionBadge: View {
    let confidence: MeetingCalendarSnapshot.Confidence

    var body: some View {
        Label(SavedMeetingCalendarPresentation.connectionTitle(for: confidence), systemImage: "calendar")
            .font(DesignSystem.Typography.micro.weight(.semibold))
            .foregroundStyle(
                confidence == .confirmed
                    ? DesignSystem.Colors.accent
                    : DesignSystem.Colors.warningAmber
            )
            .lineLimit(1)
            .fixedSize()
            .help(SavedMeetingCalendarPresentation.connectionHelp(for: confidence))
            .accessibilityHint(SavedMeetingCalendarPresentation.connectionHelp(for: confidence))
    }
}

struct SavedMeetingCalendarContextSection: View {
    let snapshot: MeetingCalendarSnapshot

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
                Label("Calendar", systemImage: "calendar")
                    .font(DesignSystem.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Text(SavedMeetingCalendarPresentation.confidenceTitle(for: snapshot.confidence))
                    .font(DesignSystem.Typography.micro.weight(.semibold))
                    .foregroundStyle(confidenceColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(confidenceColor.opacity(0.10)))

                Spacer()

                if let meetingURL = SavedMeetingCalendarPresentation.actionableMeetingURL(snapshot.meetingURL) {
                    Button {
                        openURL(meetingURL)
                    } label: {
                        Label("Open meeting link", systemImage: "arrow.up.right.square")
                    }
                    .parakeetAction(.secondary)
                    .controlSize(.small)
                }
            }

            Text(SavedMeetingCalendarPresentation.confidenceDetail(for: snapshot.confidence))
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            calendarDetail(label: "Scheduled", value: scheduleText)

            if let service = normalized(snapshot.meetingService) {
                calendarDetail(label: "Service", value: service)
            }
            if let organizer = snapshot.organizer.flatMap(SavedMeetingCalendarPresentation.personText) {
                calendarDetail(label: "Organizer", value: organizer)
            }
            if let attendees = SavedMeetingCalendarPresentation.attendeeText(snapshot.attendees) {
                calendarDetail(label: "Participants", value: attendees)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.rowCornerRadius)
                .fill(DesignSystem.Colors.surfaceElevated.opacity(0.25))
        )
    }

    private var confidenceColor: Color {
        snapshot.confidence == .confirmed
            ? DesignSystem.Colors.accent
            : DesignSystem.Colors.warningAmber
    }

    private var scheduleText: String {
        let start = snapshot.scheduledStartAt.formatted(date: .abbreviated, time: .shortened)
        if Calendar.autoupdatingCurrent.isDate(snapshot.scheduledStartAt, inSameDayAs: snapshot.scheduledEndAt) {
            let end = snapshot.scheduledEndAt.formatted(date: .omitted, time: .shortened)
            return "\(start) – \(end)"
        }
        let end = snapshot.scheduledEndAt.formatted(date: .abbreviated, time: .shortened)
        return "\(start) – \(end)"
    }

    private func calendarDetail(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
            Text(label)
                .font(DesignSystem.Typography.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .frame(width: 76, alignment: .leading)

            Text(value)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

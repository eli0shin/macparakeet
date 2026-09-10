import Foundation

/// A calendar event fetched from EventKit at poll time.
///
/// MacParakeet does not persist the polling cache, but a meeting recording may
/// snapshot the triggering event onto its local transcript row and artifacts.
/// See ADR-017 §6 for the current persistence boundary.
public struct CalendarEvent: Codable, Sendable, Identifiable {
    /// EventKit's `EKEvent.eventIdentifier`. Stable across syncs but can
    /// change for recurring events when the user edits a single occurrence.
    /// Use `externalId` if you need a stronger identity.
    public var id: String

    public var title: String
    public var startTime: Date
    public var endTime: Date
    public var location: String?

    /// Extracted Zoom / Meet / Teams / Webex / Around URL.
    public var meetUrl: String?

    /// Other attendees — current user is filtered out at conversion time
    /// (their participation status is captured separately in `userStatus`).
    public var participants: [EventParticipant]

    /// EventKit's organizer, when supplied by the backing calendar.
    public var organizer: EventParticipant?

    public var isAllDay: Bool

    /// e.g. "Work", "Personal" — display label for UI surfaces. **Don't key
    /// the per-calendar exclude list on this** — multiple accounts can have
    /// the same human-readable title (two "Calendar"s, two "Work"s). Use
    /// `calendarIdentifier` for filtering.
    public var calendarName: String?

    /// Stable `EKCalendar.calendarIdentifier`. Used to key the per-calendar
    /// exclude list — survives renames and disambiguates same-titled
    /// calendars across accounts.
    public var calendarIdentifier: String?

    /// Current user's participation status, lifted off `EKAttendee` before
    /// the participant list is filtered. Used to suppress declined events.
    public var userStatus: EventParticipant.ParticipantStatus?

    /// `EKEvent.calendarItemExternalIdentifier` — more stable than `id` for
    /// recurring events whose occurrences get reorganized server-side.
    public var externalId: String?

    public var syncedAt: Date

    public init(
        id: String,
        title: String,
        startTime: Date,
        endTime: Date,
        location: String? = nil,
        meetUrl: String? = nil,
        participants: [EventParticipant] = [],
        organizer: EventParticipant? = nil,
        isAllDay: Bool = false,
        calendarName: String? = nil,
        calendarIdentifier: String? = nil,
        userStatus: EventParticipant.ParticipantStatus? = nil,
        externalId: String? = nil,
        syncedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.meetUrl = meetUrl
        self.organizer = organizer?.normalized
        self.participants = Self.uniqueParticipants(participants.map(\.normalized))
        self.isAllDay = isAllDay
        self.calendarName = calendarName
        self.calendarIdentifier = calendarIdentifier
        self.userStatus = userStatus
        self.externalId = externalId
        self.syncedAt = syncedAt
    }
}

public struct EventParticipant: Codable, Sendable, Hashable {
    public var email: String?
    public var name: String?
    public var status: ParticipantStatus

    /// EventKit's supported participant URL, retained only in memory for
    /// identity checks. It is intentionally omitted from Codable output so an
    /// opaque calendar-provider principal does not become exported user data.
    var sourceIdentifier: String? = nil

    private enum CodingKeys: String, CodingKey {
        case email
        case name
        case status
    }

    public init(email: String? = nil, name: String? = nil, status: ParticipantStatus = .unknown) {
        self.email = email
        self.name = name
        self.status = status
        self.sourceIdentifier = nil
    }

    public enum ParticipantStatus: String, Codable, Sendable {
        case accepted
        case declined
        case tentative
        case pending
        case unknown
    }

    /// Best available local label. EventKit providers do not always supply
    /// both a name and an email address.
    public var displayName: String {
        name ?? email ?? "Participant"
    }

    static func emailAddress(from url: URL) -> String? {
        guard url.scheme?.caseInsensitiveCompare("mailto") == .orderedSame,
              let separator = url.absoluteString.firstIndex(of: ":") else {
            return nil
        }
        let resource = url.absoluteString[url.absoluteString.index(after: separator)...]
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let address = (String(resource).removingPercentEncoding ?? String(resource))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? nil : address
    }

    fileprivate var normalized: EventParticipant {
        var participant = EventParticipant(
            email: Self.nonempty(email)?.lowercased(),
            name: Self.nonempty(name),
            status: status
        )
        participant.sourceIdentifier = Self.nonempty(sourceIdentifier)
        return participant
    }

    func representsSamePerson(as other: EventParticipant) -> Bool {
        let lhs = normalized
        let rhs = other.normalized
        if let lhsIdentifier = lhs.sourceIdentifier, let rhsIdentifier = rhs.sourceIdentifier {
            return lhsIdentifier == rhsIdentifier
        }
        if let lhsEmail = lhs.email, let rhsEmail = rhs.email {
            return lhsEmail == rhsEmail
        }
        return false
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public extension CalendarEvent {
    var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }

    var isNow: Bool {
        let now = Date()
        return startTime <= now && endTime >= now
    }

    func startsWithin(minutes: Int) -> Bool {
        let now = Date()
        let threshold = now.addingTimeInterval(TimeInterval(minutes * 60))
        return startTime > now && startTime <= threshold
    }

    var timeUntilStart: TimeInterval {
        startTime.timeIntervalSinceNow
    }

    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }

    var attendeeCount: Int {
        participants.count
    }

    var participantDisplayNames: [String] {
        participants
            .filter { participant in
                organizer?.representsSamePerson(as: participant) != true
            }
            .map(\.displayName)
    }

    var organizerDisplayName: String? {
        guard let organizer else { return nil }
        return organizer.name ?? organizer.email ?? "Organizer"
    }

    /// Stable key for the coordinator's per-occurrence suppression sets
    /// (reminded / countdown-shown / dismissed). Combines `id` with the start
    /// time so rescheduling an event to a different time is treated as a fresh
    /// occurrence that can re-fire — keying on `id` alone permanently
    /// suppressed a same-day reschedule. Whole-second granularity is plenty;
    /// meetings don't move by sub-second amounts.
    var dedupeKey: String {
        "\(id)|\(Int(startTime.timeIntervalSinceReferenceDate))"
    }

    var isMeeting: Bool {
        !participants.isEmpty || meetUrl != nil
    }

    var userDeclined: Bool {
        userStatus == .declined
    }

    private static func uniqueParticipants(_ participants: [EventParticipant]) -> [EventParticipant] {
        var unique: [EventParticipant] = []
        for participant in participants {
            if unique.contains(where: { $0.representsSamePerson(as: participant) }) { continue }
            // People whose provider exposes no supported identity value stay
            // in the list because equal names do not prove equal identities.
            unique.append(participant)
        }
        return unique
    }
}

// Identity is `id` only (EventKit's `eventIdentifier`). This is deliberate:
// `==`/`hash` answer "same calendar event," not "same occurrence." A
// rescheduled occurrence keeps its `id`, so two occurrences of one recurring
// series can compare equal — meaning a `Set<CalendarEvent>` would silently
// collapse them. The coordinator never does that: occurrence-level identity
// (suppression sets, reschedule re-fire) is keyed on `dedupeKey` (id + start
// time), and the only `contains` over a `[CalendarEvent]` (owned-event merge)
// matches on `id` on purpose. If a future caller needs per-occurrence set
// semantics, key on `dedupeKey`, not the event itself.
extension CalendarEvent: Hashable {
    public static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Lightweight info for the per-calendar include list in Settings — we don't
/// need the full `EKCalendar` surface here.
public struct CalendarInfo: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var sourceTitle: String?

    public init(id: String, title: String, sourceTitle: String? = nil) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
    }
}

import MacParakeetCore

public struct MeetingRecordingPreviewLine: Identifiable, Equatable, Sendable {
    public let id: String
    public let timestamp: String
    public let speakerLabel: String
    public let text: String
    public let source: AudioSource?
    public let speakerID: String?

    /// Preserve the local “Me” heading, but do not present an undetected
    /// system source as an “Others” speaker.
    public var showsSpeakerHeading: Bool {
        guard let identity = speakerIdentity else { return false }
        return identity != AudioSource.system.rawValue
            && identity != AudioSource.unidentifiedMicrophoneSpeakerID
    }

    public var speakerIdentity: String? {
        speakerID ?? source?.rawValue
    }

    public init(
        id: String,
        timestamp: String,
        speakerLabel: String,
        text: String,
        source: AudioSource?,
        speakerID: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.speakerLabel = speakerLabel
        self.text = text
        self.source = source
        self.speakerID = speakerID
    }
}

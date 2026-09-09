import MacParakeetCore

public struct MeetingRecordingPreviewLine: Identifiable, Equatable, Sendable {
    public let id: String
    public let timestamp: String
    public let speakerLabel: String
    public let text: String
    public let source: AudioSource?
    public let speakerID: String?

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

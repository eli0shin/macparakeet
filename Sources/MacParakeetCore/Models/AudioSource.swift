import Foundation

/// Audio source for speaker attribution from the dual-stream meeting capture pipeline.
public enum AudioSource: String, Codable, Sendable {
    case microphone
    case system

    public static let unidentifiedMicrophoneSpeakerID = "microphone:unknown"

    /// Bare legacy speaker IDs belong to system audio. New detected IDs retain
    /// their capture source, independently of the user-visible speaker name.
    public static func forSpeakerID(_ id: String?) -> AudioSource? {
        guard let id else { return nil }
        if id == microphone.rawValue || id.hasPrefix("microphone:") { return .microphone }
        return .system
    }

    public var displayLabel: String {
        switch self {
        case .microphone:
            return "Me"
        case .system:
            return "Others"
        }
    }
}

import Foundation

/// The speaker-count hint for a completed meeting. User-entered values always
/// describe total people in the meeting, including Me. Only the remote count is
/// passed to system-audio diarization.
public enum MeetingSpeakerCountSelection: Equatable, Sendable {
    case auto
    case exact(totalPeople: Int)
    case bounded(minTotalPeople: Int, maxTotalPeople: Int)

    public func remoteDiarizationConstraint(
        hasSystemAudio: Bool
    ) throws -> SpeakerDiarizationConstraint? {
        guard hasSystemAudio else {
            throw MeetingSpeakerCountCorrectionError.systemAudioUnavailable
        }

        switch self {
        case .auto:
            return nil
        case .exact(let totalPeople):
            guard totalPeople >= 2 else {
                throw MeetingSpeakerCountCorrectionError.totalMustIncludeRemoteSpeaker
            }
            return .exact(totalPeople - 1)
        case .bounded(let minTotalPeople, let maxTotalPeople):
            guard minTotalPeople >= 2, maxTotalPeople >= 2 else {
                throw MeetingSpeakerCountCorrectionError.totalMustIncludeRemoteSpeaker
            }
            guard minTotalPeople <= maxTotalPeople else {
                throw MeetingSpeakerCountCorrectionError.invalidBounds
            }
            return .range(min: minTotalPeople - 1, max: maxTotalPeople - 1)
        }
    }

    public static func detectedTotalPeople(in transcription: Transcription) -> Int? {
        guard transcription.sourceType == .meeting,
            let speakers = transcription.speakers,
            !speakers.isEmpty
        else {
            return nil
        }
        let includesMe = speakers.contains { $0.id == AudioSource.microphone.rawValue }
        return speakers.count + (includesMe ? 0 : 1)
    }
}

public struct MeetingSpeakerAttributionUpdate: Equatable, Sendable {
    public let wordTimestamps: [WordTimestamp]
    public let speakers: [SpeakerInfo]
    public let speakerCount: Int?
    public let diarizationSegments: [DiarizationSegmentRecord]
    public let transcriptSegments: [TranscriptSegmentRecord]?

    public init(
        wordTimestamps: [WordTimestamp],
        speakers: [SpeakerInfo],
        speakerCount: Int?,
        diarizationSegments: [DiarizationSegmentRecord],
        transcriptSegments: [TranscriptSegmentRecord]?
    ) {
        self.wordTimestamps = wordTimestamps
        self.speakers = speakers
        self.speakerCount = speakerCount
        self.diarizationSegments = diarizationSegments
        self.transcriptSegments = transcriptSegments
    }
}

public enum MeetingSpeakerCountCorrectionError: LocalizedError, Equatable, Sendable {
    case systemAudioUnavailable
    case totalMustIncludeRemoteSpeaker
    case invalidBounds
    case timedWordsUnavailable
    case noRemoteSpeechDetected
    case unsupportedService
    case retainedAudioUnavailable
    case transcriptionUnavailable

    public var errorDescription: String? {
        switch self {
        case .systemAudioUnavailable:
            return "Speaker attribution needs a saved system-audio track. Microphone-only meetings have only Me."
        case .totalMustIncludeRemoteSpeaker:
            return "Enter at least 2 people: Me and at least one remote speaker."
        case .invalidBounds:
            return "The minimum speaker count must not be greater than the maximum."
        case .timedWordsUnavailable:
            return "Speaker attribution needs a timed transcript. The current transcript has no word timestamps."
        case .noRemoteSpeechDetected:
            return "No remote speech was detected. The existing transcript was not changed."
        case .unsupportedService:
            return "Speaker attribution correction is not available."
        case .retainedAudioUnavailable:
            return "Saved meeting audio is not available, so speaker attribution cannot be rerun."
        case .transcriptionUnavailable:
            return "The meeting is no longer available. The speaker correction was not saved."
        }
    }
}

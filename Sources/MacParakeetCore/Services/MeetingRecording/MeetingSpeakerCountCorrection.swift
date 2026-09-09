import Foundation

/// Counts for a completed meeting. Legacy recordings use totals including Me.
/// Recordings with microphone detection use counts for the selected track.
public enum MeetingSpeakerCountSelection: Equatable, Sendable {
    case auto
    case exact(totalPeople: Int)
    case bounded(minTotalPeople: Int, maxTotalPeople: Int)

    /// Counts only people captured by the microphone, not remote participants.
    indirect case microphone(MeetingSpeakerCountSelection)

    public var source: AudioSource {
        if case .microphone = self { return .microphone }
        return .system
    }

    public func constraint(for recording: MeetingRecordingOutput) throws -> SpeakerDiarizationConstraint? {
        if case .microphone(let selection) = self {
            guard recording.microphoneSpeakerDetection, recording.sourceAlignment.microphone != nil else {
                throw MeetingSpeakerCountCorrectionError.microphoneDetectionUnavailable
            }
            return try selection.localConstraint()
        }
        // Legacy meetings retain total-including-Me semantics. With microphone
        // detection enabled, system counts refer only to that independent track.
        if recording.microphoneSpeakerDetection {
            guard recording.sourceAlignment.system != nil else {
                throw MeetingSpeakerCountCorrectionError.systemAudioUnavailable
            }
            return try localConstraint()
        }
        return try remoteDiarizationConstraint(hasSystemAudio: recording.sourceAlignment.system != nil)
    }

    private func localConstraint() throws -> SpeakerDiarizationConstraint? {
        switch self {
        case .auto: return nil
        case .exact(let count):
            guard count >= 1 else { throw MeetingSpeakerCountCorrectionError.invalidLocalCount }
            return .exact(count)
        case .bounded(let minimum, let maximum):
            guard minimum >= 1, maximum >= minimum else { throw MeetingSpeakerCountCorrectionError.invalidLocalCount }
            return .range(min: minimum, max: maximum)
        case .microphone(let selection):
            return try selection.localConstraint()
        }
    }

    public func remoteDiarizationConstraint(
        hasSystemAudio: Bool
    ) throws -> SpeakerDiarizationConstraint? {
        guard hasSystemAudio else {
            throw MeetingSpeakerCountCorrectionError.systemAudioUnavailable
        }

        switch self {
        case .microphone(let selection):
            return try selection.localConstraint()
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
        if speakers.contains(where: { $0.id.hasPrefix("microphone:") }) {
            return speakers.count
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
    public let readingDocument: MeetingTranscriptPresentationDocument?

    public init(
        wordTimestamps: [WordTimestamp],
        speakers: [SpeakerInfo],
        speakerCount: Int?,
        diarizationSegments: [DiarizationSegmentRecord],
        transcriptSegments: [TranscriptSegmentRecord]?,
        readingDocument: MeetingTranscriptPresentationDocument? = nil
    ) {
        self.wordTimestamps = wordTimestamps
        self.speakers = speakers
        self.speakerCount = speakerCount
        self.diarizationSegments = diarizationSegments
        self.transcriptSegments = transcriptSegments
        self.readingDocument = readingDocument
    }
}

public enum MeetingSpeakerCountCorrectionError: LocalizedError, Equatable, Sendable {
    case systemAudioUnavailable
    case microphoneDetectionUnavailable
    case invalidLocalCount
    case totalMustIncludeRemoteSpeaker
    case invalidBounds
    case timedWordsUnavailable
    case noRemoteSpeechDetected
    case unsupportedService
    case retainedAudioUnavailable
    case transcriptionUnavailable
    case canonicalWordsChanged

    public var errorDescription: String? {
        switch self {
        case .microphoneDetectionUnavailable:
            return
                "Microphone speaker detection must have been enabled for this recording, and saved microphone audio is required."
        case .invalidLocalCount:
            return "Enter at least 1 speaker, with the minimum no greater than the maximum."
        case .systemAudioUnavailable:
            return
                "Speaker attribution needs a saved system-audio track. Select Microphone for an in-person recording with microphone speaker detection enabled."
        case .totalMustIncludeRemoteSpeaker:
            return "Enter at least 2 people: Me and at least one remote speaker."
        case .invalidBounds:
            return "The minimum speaker count must not be greater than the maximum."
        case .timedWordsUnavailable:
            return "Speaker attribution needs a timed transcript. The current transcript has no word timestamps."
        case .noRemoteSpeechDetected:
            return "No speakers were detected in the selected audio. The existing transcript was not changed."
        case .unsupportedService:
            return "Speaker attribution correction is not available."
        case .retainedAudioUnavailable:
            return "Saved meeting audio is not available, so speaker attribution cannot be rerun."
        case .transcriptionUnavailable:
            return "The meeting is no longer available. The speaker correction was not saved."
        case .canonicalWordsChanged:
            return "The transcript changed while speaker attribution was running. Run Adjust Speakers again."
        }
    }
}

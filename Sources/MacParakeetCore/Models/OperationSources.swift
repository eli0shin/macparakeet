import Foundation

public enum TranscriptionSource: String, Sendable, Equatable {
    case file
    case youtube
    case podcast
    case meeting
    case dragDrop = "drag_drop"
}

public enum FormatterSource: String, Sendable, Equatable {
    case dictation
    case transcription
}

public enum MeetingRecordingTrigger: String, Sendable, Equatable {
    case manual
    case hotkey
    case calendarAutoStart = "calendar_auto_start"
}

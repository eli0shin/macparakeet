import Foundation
import Testing
@testable import MacParakeetCore

@Suite("DiagnosticErrorClassifier")
struct DiagnosticErrorClassifierTests {

    @Test("classifies AudioProcessorError cases with case name")
    func audioProcessorErrorCases() {
        #expect(
            DiagnosticErrorClassifier.classify(AudioProcessorError.insufficientSamples)
                == "AudioProcessorError.insufficientSamples")
        #expect(
            DiagnosticErrorClassifier.classify(AudioProcessorError.microphoneNotAvailable)
                == "AudioProcessorError.microphoneNotAvailable")
        #expect(
            DiagnosticErrorClassifier.classify(AudioProcessorError.microphonePermissionDenied)
                == "AudioProcessorError.microphonePermissionDenied")
        #expect(
            DiagnosticErrorClassifier.classify(AudioProcessorError.recordingFailed("test"))
                == "AudioProcessorError.recordingFailed")
        #expect(
            DiagnosticErrorClassifier.classify(AudioProcessorError.conversionFailed("test"))
                == "AudioProcessorError.conversionFailed")
        #expect(
            DiagnosticErrorClassifier.classify(AudioProcessorError.inputUnavailable(.noInputBuffers))
                == "AudioProcessorError.inputUnavailable")
    }

    @Test("classifies STTError cases with case name")
    func sttErrorCases() {
        #expect(
            DiagnosticErrorClassifier.classify(STTError.engineStartFailed("test"))
                == "STTError.engineStartFailed")
    }

    @Test("classifies DictationServiceError cases with case name")
    func dictationServiceErrorCases() {
        #expect(
            DiagnosticErrorClassifier.classify(DictationServiceError.emptyTranscript)
                == "DictationServiceError.emptyTranscript")
        #expect(
            DiagnosticErrorClassifier.classify(DictationServiceError.notRecording)
                == "DictationServiceError.notRecording")
    }

    @Test("classifies URLError with code name")
    func urlErrorCodes() {
        #expect(
            DiagnosticErrorClassifier.classify(URLError(.notConnectedToInternet))
                == "URLError.notConnectedToInternet")
        #expect(
            DiagnosticErrorClassifier.classify(URLError(.timedOut))
                == "URLError.timedOut")
    }

    @Test("classifies CancellationError")
    func cancellationError() {
        #expect(
            DiagnosticErrorClassifier.classify(CancellationError())
                == "CancellationError")
    }

    @Test("classifies NSError with domain and code")
    func nsError() {
        let error = NSError(domain: "TestDomain", code: 42)
        #expect(
            DiagnosticErrorClassifier.classify(error)
                == "TestDomain.42")
    }

    // MARK: - errorDetail

    @Test("errorDetail returns localizedDescription")
    func errorDetailBasic() {
        let error = STTError.engineStartFailed("Neural Engine unavailable")
        let detail = DiagnosticErrorClassifier.errorDetail(error)
        #expect(detail.contains("Neural Engine unavailable"))
    }

    @Test("errorDetail replaces user home paths with <path>")
    func errorDetailStripsHomePath() {
        let error = NSError(
            domain: "Test", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Failed to load model at /Users/john/Library/Application Support/MacParakeet/models/stt"
            ])
        let detail = DiagnosticErrorClassifier.errorDetail(error)
        #expect(!detail.contains("/Users/john"))
        #expect(!detail.contains("Library/Application Support"))
        #expect(detail.contains("<path>"))
    }

    @Test("errorDetail replaces temp paths with <path>")
    func errorDetailStripsTempPath() {
        let error = NSError(
            domain: "Test", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Cannot write to /var/folders/xx/yyy/T/macparakeet/audio.wav"
            ])
        let detail = DiagnosticErrorClassifier.errorDetail(error)
        #expect(!detail.contains("/var/folders"))
        #expect(detail.contains("<path>"))

        // /private/var/folders/...
        let error2 = NSError(
            domain: "Test", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Error at /private/var/folders/ab/cd/T/tmp.wav"
            ])
        let detail2 = DiagnosticErrorClassifier.errorDetail(error2)
        #expect(!detail2.contains("/private/var"))
        #expect(detail2.contains("<path>"))

        // /tmp/...
        let error3 = NSError(
            domain: "Test", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Missing file /tmp/macparakeet/recording.wav"
            ])
        let detail3 = DiagnosticErrorClassifier.errorDetail(error3)
        #expect(!detail3.contains("/tmp/macparakeet"))
        #expect(detail3.contains("<path>"))
    }

    @Test("errorDetail replaces file:// URLs with <path>")
    func errorDetailStripsFileURL() {
        let error = NSError(
            domain: "Test", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Cannot open file://localhost/Users/alice/Documents/meeting.m4v"
            ])
        let detail = DiagnosticErrorClassifier.errorDetail(error)
        #expect(!detail.contains("file://"))
        #expect(!detail.contains("alice"))
        #expect(detail.contains("<path>"))
    }

    @Test("errorDetail replaces http(s) URLs with <url>")
    func errorDetailStripsHTTPURL() {
        let error = NSError(
            domain: "Test", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Download failed: https://youtube.com/watch?v=dQw4w9WgXcQ returned 403"
            ])
        let detail = DiagnosticErrorClassifier.errorDetail(error)
        #expect(!detail.contains("youtube.com"))
        #expect(!detail.contains("dQw4w9WgXcQ"))
        #expect(detail.contains("<url>"))
    }

    @Test("errorDetail handles multiple paths in one message")
    func errorDetailMultiplePaths() {
        let error = NSError(
            domain: "Test", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Cannot move /Users/alice/a.wav to /Users/alice/b.wav"
            ])
        let detail = DiagnosticErrorClassifier.errorDetail(error)
        #expect(!detail.contains("/Users/alice"))
        // Both paths should be replaced
        #expect(!detail.contains("a.wav"))
    }

    @Test("errorDetail truncates to 512 characters")
    func errorDetailTruncates() {
        let longMessage = String(repeating: "x", count: 600)
        let error = NSError(
            domain: "Test", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: longMessage
            ])
        let detail = DiagnosticErrorClassifier.errorDetail(error)
        #expect(detail.count == 512)
    }
}

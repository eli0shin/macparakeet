import Foundation

public enum Observability {
    public static func operationID() -> String {
        UUID().uuidString
    }

    public static func durationSeconds(since startedAt: Date) -> Double {
        max(0, Date().timeIntervalSince(startedAt))
    }

    public static func errorType(for error: Error) -> String {
        DiagnosticErrorClassifier.classify(error)
    }

    public static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for character in text {
            if character.isWhitespace {
                inWord = false
            } else if !inWord {
                count += 1
                inWord = true
            }
        }
        return count
    }
}

import Foundation

/// A content-free notice shared by vocabulary settings and the main window.
@MainActor
@Observable
public final class RecognitionVocabularyStatus {
    public var message: String?
    public init() {}
    public func report(_ message: String) { self.message = message }
}

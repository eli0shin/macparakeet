import Foundation

/// Planning limits for meeting AI cleanup. Complete turns are never split;
/// boundary repair may add one carried turn beyond these limits.
public struct MeetingCleanupBatchLimits: Sendable, Equatable {
    public static let defaultMaximumTurns = 10
    public static let defaultMaximumCharacters = 500

    public let maximumTurns: Int
    public let maximumCharacters: Int

    public init(
        maximumTurns: Int = defaultMaximumTurns,
        maximumCharacters: Int = defaultMaximumCharacters
    ) {
        self.maximumTurns = maximumTurns > 0 ? maximumTurns : Self.defaultMaximumTurns
        self.maximumCharacters = maximumCharacters > 0 ? maximumCharacters : Self.defaultMaximumCharacters
    }
}

import Foundation

/// Residual gating is separate from acoustic echo cancellation. Off disables
/// only the gate; it never disables the reference-based canceller.
public struct MeetingResidualEchoSuppression: Sendable, Equatable, Codable {
    public static let enabledKey = "meetingResidualEchoSuppressionEnabled"
    public static let thresholdKey = "meetingResidualEchoSuppressionThresholdDBFS"
    public static let thresholdRange: ClosedRange<Double> = -65 ... -30
    public static let standard = Self(enabled: true, thresholdDBFS: -45)

    public let enabled: Bool
    public let thresholdDBFS: Double

    public init(enabled: Bool, thresholdDBFS: Double) {
        self.enabled = enabled
        self.thresholdDBFS =
            thresholdDBFS.isFinite
            ? min(Self.thresholdRange.upperBound, max(Self.thresholdRange.lowerBound, thresholdDBFS))
            : -45
    }

    public static func current(defaults: UserDefaults = .standard) -> Self {
        Self(
            enabled: defaults.object(forKey: enabledKey) as? Bool ?? true,
            thresholdDBFS: defaults.object(forKey: thresholdKey) as? Double ?? -45
        )
    }

    /// Compatibility fallback for custom runtimes without LocalVQE's gate API.
    /// This uses the same per-hop RMS rule as localvqe_set_noise_gate.
    func apply(to samples: inout [Float]) {
        guard enabled, !samples.isEmpty else { return }
        let power = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)
        if power <= pow(10, thresholdDBFS / 10) {
            samples = Array(repeating: 0, count: samples.count)
        }
    }
}

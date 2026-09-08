import MacParakeetCore
import SwiftUI

/// Shared by meeting Settings and the live recording panel. The processor reads
/// these preferences on incoming hops; UI changes never rewrite raw audio.
struct MeetingEchoSuppressionControls: View {
    var isLive = false
    @AppStorage(MeetingResidualEchoSuppression.enabledKey) private var enabled = true
    @AppStorage(MeetingResidualEchoSuppression.thresholdKey) private var threshold = -45.0

    private var selected: MeetingResidualEchoSuppression {
        .init(enabled: enabled, thresholdDBFS: threshold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Toggle("Residual echo suppression", isOn: $enabled)
            HStack {
                Text(
                    enabled
                        ? "\(selected == .standard ? "Standard" : "Custom") · \(Int(selected.thresholdDBFS)) dBFS"
                        : "Off"
                )
                .monospacedDigit()
                Spacer()
                Button("Reset to Standard") {
                    threshold = MeetingResidualEchoSuppression.standard.thresholdDBFS
                    enabled = true
                }
                .parakeetAction(.secondary)
            }
            Slider(
                value: Binding(
                    get: { selected.thresholdDBFS },
                    set: {
                        threshold = MeetingResidualEchoSuppression(enabled: enabled, thresholdDBFS: $0).thresholdDBFS
                    }
                ),
                in: MeetingResidualEchoSuppression.thresholdRange,
                step: 1
            )
            .disabled(!enabled)
            .accessibilityLabel("Residual echo suppression threshold")
            .accessibilityValue("\(Int(selected.thresholdDBFS)) decibels full scale")
            HStack {
                Text("Preserve quieter speech")
                Spacer()
                Text("Suppress more echo")
            }
            .font(DesignSystem.Typography.caption)
            Text(
                "Stronger suppression removes more residual echo but can cut quiet speech. Off disables only this gate, not echo cancellation."
            )
            .font(DesignSystem.Typography.caption)
            Text(
                isLive
                    ? "Applies to incoming preview audio. Existing preview text stays unchanged. The final transcript uses the setting selected when cleanup starts. Preview can pause briefly after unmute."
                    : "Applies to incoming meeting preview audio and final cleanup. Retranscribe a saved meeting to regenerate cleaned audio with this setting."
            )
            .font(DesignSystem.Typography.caption)
        }
        .foregroundStyle(DesignSystem.Colors.textSecondary)
    }
}

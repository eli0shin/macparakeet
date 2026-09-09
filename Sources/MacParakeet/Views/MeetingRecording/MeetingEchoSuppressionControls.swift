import MacParakeetCore
import MacParakeetViewModels
import SwiftUI

struct MeetingInProgressAudioControls: View {
    @Bindable var viewModel: MeetingRecordingPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Speaker detection")
                    .font(DesignSystem.Typography.bodySmall.weight(.semibold))

                speakerToggle(
                    title: "System audio",
                    detail: viewModel.speakerDetectionState.canDetectSystemAudio
                        ? "Detect remote speakers in live and final transcripts."
                        : "System audio is not recorded in this meeting.",
                    source: .system,
                    isOn: viewModel.speakerDetectionState.systemAudioEnabled,
                    isAvailable: viewModel.speakerDetectionState.canDetectSystemAudio
                )
                speakerToggle(
                    title: "Microphone",
                    detail: viewModel.speakerDetectionState.canDetectMicrophone
                        ? "Detect local room speakers instead of labeling everyone Me."
                        : "The microphone is not recorded in this meeting.",
                    source: .microphone,
                    isOn: viewModel.speakerDetectionState.microphoneEnabled,
                    isAvailable: viewModel.speakerDetectionState.canDetectMicrophone
                )

                Text(
                    "Changes apply to new live transcript text and this meeting's final transcript. Existing live text stays unchanged. They also become the defaults for new meetings."
                )
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            if viewModel.speakerDetectionState.canDetectSystemAudio
                && viewModel.speakerDetectionState.canDetectMicrophone
            {
                Divider()
                MeetingEchoSuppressionControls(isLive: true)
            }
        }
        .foregroundStyle(DesignSystem.Colors.textSecondary)
    }

    private func speakerToggle(
        title: String,
        detail: String,
        source: AudioSource,
        isOn: Bool,
        isAvailable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(
                title,
                isOn: Binding(
                    get: { isOn },
                    set: { viewModel.requestSpeakerDetection($0, for: source) }
                )
            )
            .disabled(!isAvailable)
            Text(detail)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }
}

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

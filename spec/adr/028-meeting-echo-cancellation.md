# ADR-028: Offline Meeting Echo Cancellation via Derived Cleaned-Mic Artifact

> Status: **Accepted**
> Date: 2026-07-03

## Context

Meeting recording captures two sources: the microphone and system audio
(remote participants). When the user plays remote audio through speakers,
the microphone also captures it — delayed and room-colored. This bleed
degrades transcription accuracy on the user's own speech and misattributes
remote speech to the "Me" track. Users expect high-accuracy meeting
transcripts; echo bleed is the largest accuracy defect in the
speakers-playback case.

Constraints that shaped the decision:

- Local-first: all processing on-device.
- The shared mic engine (ADR-015) deliberately avoids Apple's
  voice-processing I/O; dictation and meetings share one plain
  AVAudioEngine capture path, and raw audio must remain available.
- The consumer of echo cancellation is transcription, not live playback —
  there is no real-time requirement.
- Meeting artifacts are durable user data; processing must be reversible
  and debuggable.

## Decision

Perform echo cancellation OFFLINE, after recording stops, producing a
derived artifact — `microphone-cleaned.m4a` — while preserving the raw
microphone recording untouched.

Pipeline (see `MeetingCleanedMicRenderer`, `MicConditioner`,
`MeetingEchoDelayEstimator`, `MeetingEchoSuppressionConfiguration`, and
`MeetingEchoSuppressionFactory`):

1. The recorded system-audio track is the echo reference. It is captured
   anyway for the meeting, giving a perfect reference most AEC systems
   lack.
2. Alignment: retain the recorded host-time offset. The selected v1.4
   echo-only DAF model owns adaptive reference alignment; do not also shift
   its reference with the outer delay estimator. Legacy models retain the
   outer estimator. Cross-correlation remains available for the echo probe.
3. Suppression: use the LocalVQE echo-only model, without general denoising
   or a linear DSP pre-stage. Apply its optional residual noise gate at
   −45 dBFS by default. Load `localvqe_set_noise_gate` when available; older
   runtimes use an equivalent per-hop RMS gate after model output. Stronger
   gating can cut quiet speech; this is a reversible user choice, not proof
   of correct speaker attribution.
4. Final meeting transcription prefers the cleaned mic for the "Me" track.

Coordination (readiness gate, PR #671):

- Stop schedules the render when the duration guard predicts it can finish
  inside the bounded deadline; otherwise it skips upfront with
  `predictedRenderTimeout`. Stop latency is never proportional to meeting
  length.
- Final transcription awaits render readiness (a Task handle, not file
  polling) with a bounded, duration-scaled deadline before choosing the
  microphone source.
- GUI and CLI retranscription schedule a fresh cleaned-mic render from the
  raw tracks with the current suppression setting. They do not silently
  reuse a cleaned file made with unknown or older settings. Keep the prior
  derived file until a candidate completes; failure or cancellation leaves
  that file intact but uses raw audio for this attempt. Raw sources and
  playback audio are never replaced by cleanup.
- Fallback to raw is intentional and observable via a structured reason
  taxonomy: `cleanedUsed`, `rawTimeout`, `rawInvalidArtifact`,
  `rawRenderFailed`, `rawMissingSystemReference`, `rawNoAECAssets`, `rawNotPrepared`,
  `skippedNoEchoPath`, `predictedRenderTimeout`. Silent raw fallback is a
  defect.

Live control and microphone gaps:

- Meeting Settings and the live recording panel share a residual suppression
  control: Off, Standard (−45 dBFS), or a custom threshold from −65 to −30 dBFS,
  with Reset to Standard and a quiet-speech warning. Off disables the gate,
  not echo cancellation. Preferences are local (`meetingResidualEchoSuppressionEnabled`
  and `meetingResidualEchoSuppressionThresholdDBFS`).
- Changes apply to incoming preview hops, not previous preview text. Each
  final/recovery render fixes the setting when cleanup starts. Retranscription
  fixes it when requested and processes the whole archived meeting again.
- Reset cancellation state for synthetic microphone silence. For the DAF
  model, also reset when microphone input returns after at least one second
  of digital silence. Offline cleanup primes acquisition with up to eight
  seconds of aligned buffered audio at startup and after these gaps, then
  processes the same samples for output. No initial speech is dropped and
  no output timestamps are shifted. Live capture holds up to eight seconds
  of incoming audio for the same acquisition pass, then emits those samples
  in order. This can briefly delay the preview after unmute. Stop or another
  gap drains a shorter buffer rather than losing speech. Real-meeting checks
  are still required for both live and final unmute quality.
- Logic checks cover settings, sample counts, reset boundaries, and artifact
  replacement. They do not establish echo quality. Use real meetings to
  check residual echo and preservation of quiet local speech; do not add
  recorded-audio fixtures as a substitute for that acceptance check.

Render skip (echo probe, PR #676):

- Before running the model, the delay estimator doubles as a cheap probe
  over reference-energy windows. No correlation → no echo path (headphones
  of any kind, or remote inaudible) → skip the render with
  `skippedNoEchoPath`. Echo detection is measured from the artifacts, not
  inferred from output-route metadata, so Bluetooth speakers and route
  changes need no special cases and the recovery path behaves identically.
- Each render/skip emits a per-session diagnostics summary (model version,
  render duration and realtime factor, delay estimate, probe score, final
  reason) so accuracy complaints are debuggable from one line.
- The same render/skip summary is persisted into the session's
  `meeting-recording-metadata.json` sidecar as additive optional
  `echoSuppression` fields (`reasonCode` plus optional `modelVersion`,
  `renderDurationMs`, `delayEstimateMs`, `probeBestCorrelation`), per
  `spec/contracts/meeting-artifacts-v1.md`, so shared artifact folders
  self-describe cleaned-vs-raw routing without app logs.

The cleaned mic is exposed in the artifact manifest
(`cleanedMicrophoneAudioPath`, `spec/contracts/meeting-artifacts-v1.md`).

## Alternatives considered

- **Live system AEC (Apple VPIO)** — rejected. Reverses ADR-015: forks the
  shared capture path, destroys raw audio, and its far-end suppression
  audibly ducks the user during double-talk (observed directly in earlier
  testing; see also `../../docs/research/vpio-process-tap-conflict.md`). VPIO
  optimizes live-call comfort; we optimize post-hoc transcript accuracy.
- **Transcript-level echo removal** (delete mic-transcript segments that
  duplicate the system transcript) — rejected. Bleed corrupts the user's
  own words before ASR sees them; deleting duplicates cannot restore
  accuracy and fails on overlapping speech.
- **Linear DSP AEC only** (adaptive filter, WebRTC-AEC3 style) — rejected
  as the sole mechanism. Leaves nonlinear residual (speaker distortion,
  reverb, clock drift). May later be added as a pre-stage if measurement
  justifies it.

## Consequences

Positive:

- Raw audio preserved; cleaned is derived — past meetings can be
  re-rendered when better models ship.
- Offline processing with a known reference is strictly easier than live
  AEC: precise alignment, lookahead, unconstrained compute.
- Every raw-vs-cleaned decision is observable; no silent quality
  degradation.

Negative / accepted risks:

- Double-talk over-suppression is the primary quality risk; it is tracked
  by a dedicated harness metric (PR #669) rather than assumed away.
- The bundled LocalVQE dylib + model are a permanent
  signing/notarization/asset-gate liability
  (`REQUIRE_MEETING_ECHO_ASSETS=1` build gate). Dev launch also requires these
  assets by default and uses the same packaging function as release builds.
  After signing, dev launch verifies model initialization and frame processing
  in a hardened test process with matching signing identity and entitlements.
  An explicit `BUNDLE_MEETING_ECHO_ASSETS=0` development opt-out warns that
  microphone echo can be labeled “Me”; it is not a meeting-quality test mode.
- Render costs compute after each speakers-playback meeting; bounded by
  the deadline policy and eliminated for no-echo meetings by the probe or
  very long meetings by the duration guard.

## References

- Tracking issue #605 (U1–U5 PRs #638/#650/#651/#654/#656).
- Readiness gate: PR #671. Echo probe + skip: PR #676. Long-meeting
  duration guard: PR #705.
- Double-talk metric: PR #669.
- Prior art survey: `../../docs/research/2026-06-meeting-aec-open-issues-prior-art.md`.
- Related ADRs: 014 (meeting recording), 015 (concurrent dictation/meeting,
  shared engine), 019 (crash-resilient recording).

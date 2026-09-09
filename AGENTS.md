# AGENTS.md -- MacParakeet

## Project Shape

MacParakeet is a fast, private, local-first voice app for Apple Silicon Macs.
It ships three primary capture modes -- system-wide dictation, file/media URL
transcription, and meeting recording -- plus Transforms for selected-text
rewrites. Speech recognition runs locally by default through Parakeet via
FluidAudio CoreML/ANE, with optional Nemotron, WhisperKit, and Cohere Transcribe
engines.

The repo contains two products:

- `MacParakeet.app`: SwiftUI macOS app.
- `macparakeet-cli`: public automation surface in `Sources/CLI/`; compatibility
  notes live in `Sources/CLI/CHANGELOG.md`.

## Commands

```bash
swift build
swift test
swift test --filter TextProcessingPipelineTests
scripts/dev/check.sh [TestFilter]
scripts/dev/format.sh
scripts/dev/ci_local.sh
scripts/dev/greptile_review.sh [BaseBranch]
scripts/dev/run_app.sh
no-mistakes doctor
no-mistakes init
no-mistakes axi
swift run macparakeet-cli --help
swift run macparakeet-cli health
```

Iterate on focused tests ONLY (`swift test --filter <AreaTests>` for the
areas the diff touches). Run the full `swift test` suite AT MOST ONCE per
task, as the final gate before declaring code-change work complete — never
per iteration. The suite is 4,300+ tests including CPU-heavy AEC/DSP
simulations; full-suite-per-iteration turns a 10-minute review into an
hour. Exception only when the user explicitly scopes verification
differently.

## Product Rules

- Preserve the local-first posture. Audio/transcripts stay on-device for core
  dictation, transcription, and meeting recording. Cloud LLMs, media downloads,
  model/update flows, and telemetry are explicit product surfaces.
- Treat the user database and meeting artifacts as user data. Do not delete them
  outside explicit product recovery/discard flows.


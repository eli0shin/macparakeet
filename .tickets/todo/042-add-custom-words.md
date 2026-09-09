---
Assigned-To: pi
Tags: []
Parent:
Blocked-By: []
---

# Add custom words as recognition vocabulary hints

## Problem

Users need to save names, technical terms, acronyms, and short phrases that
occur in their speech. They should not have to predict the incorrect
transcription and create a replacement pair first.

MacParakeet already stores blank-replacement vocabulary anchors and has
Parakeet TDT vocabulary boosting code. However, recognition boosting defaults
to off, the UI presents entries as rules, and the existing sidecar skips audio
over five minutes. This ticket makes the existing capability clear and usable,
and extends it to long recordings. It does not create another vocabulary store.

## Agreed scope

The user confirmed these decisions over three grilling rounds:

- English vocabulary hints for Parakeet TDT v2/v3.
- Apply hints to final dictation and saved file/meeting transcripts, including
  long recordings. Live preview and Whisper support are follow-up work.
- Provide distinct entry forms: **Vocabulary words** takes one word-or-phrase
  field; **Replacements** takes source and replacement fields. Preserve all
  existing entries in the same store.
- When the first vocabulary word is added, ask once before enabling hints and
  downloading the additional local model. Explain the download, show preparation
  progress, and provide an off switch. Do not enable or download without consent.
- Use one shared vocabulary list. Changes affect new jobs, not jobs already
  running or previously saved transcripts.
- Hints affect recognition in both Raw and Clean modes. Raw still skips
  replacement rules and other deterministic cleanup.
- Keep words when the selected engine does not support hints. Show
  **Vocabulary hints unavailable for this engine.** Do not switch engines
  automatically. Explicit replacement rules retain their existing behavior.
- If hint processing fails or is unavailable during a supported job, complete
  transcription without hints and show a visible notice. Do not lose the
  transcript or silently imply that hints were applied.
- Favor conservative matching over maximum term recall. Saved vocabulary is
  a recognition preference, not a guarantee or an unconditional replacement.
- Review newer FluidAudio releases and compatible recognition/CTC models for
  relevant vocabulary improvements and fixes. Upgrade dependency pins and
  required integration code when upstream evidence supports the change and
  focused checks pass. A full local benchmark comparison is not required.
  Do not claim measured accuracy improvements from version numbers alone.
- Initially require at least three characters per recognition term. Clearly
  warn about shorter entries; never silently claim that they participate.
  Two-character acronyms such as `AI` are not required in this release.
- Support up to 100 enabled recognition terms. Test the limit as application
  behavior; a recognition benchmark at multiple list sizes is not required.
  Preserve larger existing lists. Require explicit user selection to reach
  the supported enabled count; do not silently choose or drop terms. This
  recognition-term limit must not impose a new limit on replacement rules.

## Acceptance criteria

### Vocabulary management

- [ ] A user can add, find, enable, disable, and delete a word or phrase without
  providing a replacement. The UI clearly distinguishes hints from replacements.
- [ ] Existing vocabulary entries and replacement rules survive the change;
  no duplicate store or destructive migration is introduced.
- [ ] First-use consent, local model preparation progress, and an off switch
  are available. Existing saved words do not imply consent to enable recognition.
- [ ] Short entries and lists above the supported enabled count have clear,
  actionable feedback, with no silent truncation or loss of stored entries.
- [ ] App and CLI use the same saved vocabulary. Applicable CLI behavior and
  contracts remain consistent with the agreed recognition policy.

### Transcription behavior

- [ ] Enabled hints are used by Parakeet TDT v2/v3 for final dictation and
  saved file/meeting transcription, including recordings longer than five minutes.
- [ ] Each job uses a stable vocabulary selection; edits during a job affect
  subsequent jobs only. Existing saved transcripts are not rewritten.
- [ ] Raw mode receives recognition hints but no replacement-rule cleanup.
  Clean mode retains the existing deterministic cleanup behavior.
- [ ] Unsupported engines retain vocabulary and show the unsupported state,
  without an automatic engine switch.
- [ ] Preparation or rescoring failures preserve the base transcript and expose
  that hints were not applied. Cold first-use behavior must not falsely report
  successful boosting.
- [ ] Long-audio processing stays bounded in memory. Preserve cancellation,
  word timing alignment, meeting recovery, the shared STT scheduler and ANE
  inference gate, and dictation trailing-silence handling.
- [ ] Vocabulary and audio remain local. No vocabulary content is added to
  telemetry. Model downloads use the explicit consent flow.

### Practical verification

The user replaced the earlier quantitative evaluation requirements with focused
checks. Full LibriSpeech runs, numeric WER gates, recall studies, latency/memory
reports, and a dependency/model benchmark matrix are not acceptance requirements
for this ticket. Existing research remains context, not a required rerun.

- [ ] Review upstream release notes or source for relevant vocabulary fixes;
  record the reason for any dependency/model upgrade and the selected versions.
  Check build compatibility and affected model download/cache behavior.
- [ ] Try a few real English recordings with saved names or technical terms,
  with hints on and off. Include ordinary speech without those terms. Check
  for useful matches, obvious false corrections, and empty output; note what
  was actually observed without making statistical accuracy claims.
- [ ] Smoke-test final dictation and a file/meeting recording longer than five
  minutes, including first-use preparation and a later prepared run. Check
  that transcription completes and fallback notices are honest.
- [ ] Add focused tests for persistence, entry validation and the 100-term
  limit, stable job vocabulary, Raw/Clean behavior, unsupported engines,
  failure fallback, long-audio boundaries, and affected CLI contracts.
- [ ] Update user documentation and relevant boundary contracts. Do not claim
  measured accuracy or performance improvements without supporting results.

## Out of scope

- Whisper vocabulary prompting, Parakeet Unified boosting, Nemotron, or Cohere
  recognition-hint support.
- Vocabulary hints in live preview.
- Non-English or mixed-language qualification.
- Two-character recognition terms, more than 100 enabled recognition terms,
  and per-project or per-meeting vocabulary lists.
- Automatic vocabulary learning, model retraining, cloud speech recognition,
  and LLM-based transcript correction.
- Automatic rewriting of historical transcripts.

## Research and governing decisions

- [Research: vocabulary hints for Parakeet and Whisper](../../../docs/research/2026-09-06-vocabulary-hints-parakeet-whisper.md)
  — live checkout findings, pinned upstream sources, and Whisper prompt risks.
- [Existing Parakeet vocabulary plan](../../../plans/active/2026-07-03-parakeet-custom-vocabulary.md)
  — reuse the existing store and qualify recognition improvements.
- [Previous Phase 0 experiment](../../../docs/research/2026-07-04-custom-vocab-phase0.md)
  — useful mechanism evidence; synthetic speech results are not human-speech
  qualification for this ticket.
- [ADR-004](../../../spec/adr/004-deterministic-pipeline.md),
  [ADR-007](../../../spec/adr/007-fluidaudio-coreml-migration.md),
  [ADR-021](../../../spec/adr/021-whisperkit-multilingual-stt.md), and
  [ADR-026](../../../spec/adr/026-asr-engine-strategy.md).
- Relevant code: `CustomWord`, `CustomWordsView`, `CustomWordsViewModel`,
  `CustomVocabularyBoosting`, `AppRuntimePreferences`, `STTRuntime`,
  `SpeechEngineCapabilityRegistry`, and CLI `vocab words`.

## Handoff

Implementation is present in the worktree; changes are not committed. English
Parakeet TDT v2/v3 remains the recognition-hint scope. FluidAudio is pinned to
0.15.6, with ModelHub migration, short-term safety controls, source-relative
candidate edits, and bounded overlapping long-audio rescoring. The integration
also preserves Unified cache/download correctness under the newer SDK; it does
not enable Unified vocabulary hints.

Verification on 2026-09-06:
- 226 focused tests passed after the final fixes, including vocabulary, consent,
  cancellation, boundary timing, scheduler snapshots, CLI config, and model cache.
- Swift 6 language-mode build passed with `MACPARAKEET_SKIP_WHISPERKIT=1`, as in
  CI. Normal builds/tests included WhisperKit.
- Full suite ran once: 5,214 tests, 21 skipped, four failed assertions in two
  Unified cache tests. The SDK had removed the streaming encoder from its shared
  required-file set and replaced the preprocessor with native mel. Cache/download
  integration and expectations were corrected; the affected tests then passed
  in the focused rerun. The full suite was not repeated, per repo policy.
- Independent code review approved the final changes. Earlier timing-alignment
  and preparation-cancellation findings were fixed and regression-tested.
- `git diff --check` and `tickets lint` passed. Swift-format lint exited zero;
  it reports pre-existing formatting warnings outside the changed assertions
  in `ModelDeletionTests.swift`.
- `no-mistakes` is unavailable in this environment.

User-verified on 2026-09-06 with MacParakeet Dev: vocabulary hints work with
Parakeet. This is a practical smoke result, not a measured accuracy claim.
Changes remain uncommitted. The ticket can close after any remaining checks the
user wants (long recording, first-use download/GUI) and after commit/PR.


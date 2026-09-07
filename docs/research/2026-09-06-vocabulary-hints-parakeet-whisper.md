# Vocabulary hints for Parakeet and Whisper

Date: 2026-09-06
Scope: research for branch `028-add-custom-words`.
Result: [ticket 028](../../.tickets/todo/028-add-custom-words.md), created after
three grilling rounds and user confirmation.
Research baseline: `6bda8d75`. No model benchmarks or app smoke tests run.

Implementation update: ticket 028 now upgrades FluidAudio to 0.15.6. The pinned
0.15.4 descriptions below record the research baseline, not the modified worktree.
The implementation uses the optional short-term safety controls from upstream
[PR #722](https://github.com/FluidInference/FluidAudio/pull/722) and source-relative
candidate evidence from PR #805. Focused tests and builds passed; live model
downloads and real-audio behavior remain unverified. See the ticket handoff for
full-suite results and the SDK's Unified cache compatibility fix.

## User goal

Save a word or phrase such as `MacParakeet` as expected vocabulary. The user
must not need to know or enter the incorrect transcription first. This is a
recognition hint, not an unconditional `incorrect text → correct text` rule.

## Main findings

- This checkout already stores words without replacements and has Parakeet
  vocabulary boosting code. However, recognition boosting defaults to **off**.
- Parakeet TDT uses an additional local CTC model to check candidate terms
  against the audio, then rescores the transcript. This is not model training
  and not a user-authored replacement rule.
- Whisper can receive a spelling glossary as decoder context. Its open-source
  WhisperKit API is `DecodingOptions.promptTokens`. This is a preference, not
  a guarantee and not an instruction-following LLM prompt.
- Our pinned WhisperKit decoder still contains the early-stop conditions
  associated with upstream reports of empty prompted transcripts. Whisper
  support needs qualification, not just a field wired into decoding options.

Sources and limits follow below.

## What exists in this checkout

| Area | Verified behavior | Source |
|---|---|---|
| Storage | `CustomWord.replacement` is optional; no replacement is required. | [CustomWord](../../Sources/MacParakeetCore/Models/CustomWord.swift) |
| Entry UI | Replacement is optional, but the UI says “Word Rules”, “Add Rule”, and “Enforces exact spelling”. | [CustomWordsView](../../Sources/MacParakeet/Views/Vocabulary/CustomWordsView.swift) |
| Text cleanup | A blank-replacement “vocabulary anchor” matches the same whole word case-insensitively and restores its saved casing. It does not detect arbitrary misheard forms. | [CustomWordReplacer](../../Sources/MacParakeetCore/TextProcessing/CustomWordReplacer.swift) |
| Recognition vocabulary | Enabled blank-replacement entries of at least three characters become terms; explicit replacement rules are excluded. Terms are trimmed and deduplicated. | [CustomVocabularyBoostingVocabulary.mapping](../../Sources/MacParakeetCore/STT/CustomVocabularyBoosting.swift) |
| Default state | `customVocabularyRecognitionBoostingEnabled` reads a defaults value and falls back to `false`. Searches found readers, but no product setter for this preference in `Sources`. This does not establish the value on the user's installed app. | [AppRuntimePreferences](../../Sources/MacParakeetCore/AppRuntimePreferences.swift), [AppEnvironment](../../Sources/MacParakeet/App/AppEnvironment.swift) |
| Engine support | Capability registry supports Parakeet TDT v2/v3; not Unified, Whisper, Nemotron, or Cohere. | [SpeechEngineCapabilities](../../Sources/MacParakeetCore/STT/SpeechEngineCapabilities.swift) |
| Audio limits | Sidecar audio is capped at five minutes. Longer URL-backed work skips boosting. Cold short-dictation preparation runs in the background and returns the original result; later dictations can use prepared resources. | [configuration](../../Sources/MacParakeetCore/STT/CustomVocabularyBoosting.swift), [STTRuntime](../../Sources/MacParakeetCore/STT/STTRuntime.swift) |
| Whisper | Decoding options set language/detection and word timestamps, but do not pass vocabulary prompt tokens. | [WhisperEngine.makeDecodingOptions](../../Sources/MacParakeetCore/STT/WhisperEngine.swift) |

Thus the likely work is to make vocabulary hints clear, usable, and reliable,
then extend the required recognition paths—not add a duplicate word store.
This is a recommendation pending the user's scope decisions.

## Parakeet: audio-based context biasing

FluidAudio's [documentation at our pinned revision][fluid-pinned] describes
Parakeet TDT 0.6B v2/v3 plus a separate CTC encoder:

1. TDT produces the base transcript and timings.
2. The CTC model processes the same audio and scores the saved terms.
3. Keyword spotting finds candidate terms and time ranges.
4. The rescorer compares candidates with the original transcript and applies
   corrections subject to acoustic scores and matching thresholds.

The [NVIDIA-authored CTC word-spotter paper][ctc-paper] describes the underlying
method. Its candidates replace greedy recognition output at matching frame
intervals. Although the algorithm changes transcript spans internally, the
user supplies **only the desired vocabulary**, not a source-to-target rule.
Neither mechanism requires retraining the base model.

The repo already has [a Phase 0 experiment][phase0]. It reports synthetic
50-term recall of 22% without boosting versus 74% with the stricter similarity
threshold. Full LibriSpeech clean WER rose from 2.312% to 2.414%, and throughput
fell from 103.1× to 31.4× real time. These are previous experiment results, not
new measurements. Synthetic speech is not proof of performance on human
names, accents, noisy microphones, or meetings. Even the stricter run made
false corrections. More aggressive boosting is not unconditionally better.

### Version and engine limits matter

[Package.swift](../../Package.swift) pins FluidAudio 0.15.4 and explicitly
blocks an automatic upgrade across its model-download API change.
Current online docs and later source must not be treated as this checkout's API.

For example, [upstream source at `6428e291`][fluid-session] defines a shared
`VocabularyBoostingSession` whose documented inputs permit Unified as well
as TDT: aligned audio, transcript, and token timings. That is evidence of an
upstream extension path, not evidence that this app already supports Unified
boosting. The older Phase 0 statement about missing Unified hooks is scoped
to the dependency/API tested then, not a permanent model limitation.

## Whisper: decoder-context prompting

OpenAI's [Whisper prompting guide][whisper-guide] demonstrates passing a glossary
such as `Aimee, Shawn, BBQ` to influence spelling. Whisper treats it like prior
transcript context. A command such as “always use these words” is not the right
mental model. OpenAI explicitly says the technique is not especially reliable.

WhisperKit maintainers [recommend `promptTokens`][whisper-issue] for this use.
A word list can be joined as text and encoded with the selected model's tokenizer.
The [pinned configuration][whisper-config] exposes both `promptTokens` and
`prefixTokens`; the former is the conditioning-context API, not the latter.

The [pinned decoder][whisper-decoder] prepends the prompt under
`startOfPreviousToken`. It retains only a suffix of length
`(Constants.maxTokenContext / 2) - 1` and filters special tokens. OpenAI's API
guide describes a 224-token limit; use the actual WhisperKit implementation
when defining this app's budget. Tokens are not words. An unlimited saved
list therefore needs an explicit selection/overflow policy for Whisper.

### Pinned dependency risk

WhisperKit is pinned to 0.18.0, revision
`e2adabbe7d98dc4d0ab9a5b75424ecc42a9cdbef`.
In that decoder, `isFirstToken` uses `prefilledIndex`, and
`sampleResult.completed` can terminate decoding without an `isPrefill` guard.
[Upstream PR #497][whisper-fix] describes these conditions causing empty output
while prompt tokens are being forced through the decoder, including with the
large-v3 Turbo model used here. Source inspection confirms the conditions;
this research did not reproduce the failure locally or qualify an upgrade.

Any Whisper trial must test real audio with and without prompts, silence,
short clips, long-audio windows, language detection, timestamps, empty output,
and latency. Do not remove speech/confidence safety checks as a shortcut.

### Do not confuse WhisperKit with WhisperKitPro

[Argmax Pro custom vocabulary documentation][argmax-pro] describes a separate
auxiliary keyword model and a simple word-list API. This is not the open-source
`promptTokens` feature and is not our installed dependency. The fetched page
also says that its auxiliary vocabulary feature is disabled with Whisper
models pending qualification. Its advertised keyword limits must not be
attributed to open-source Whisper prompting.

## Existing decisions to preserve

- [ADR-004](../../spec/adr/004-deterministic-pipeline.md): deterministic Clean
  processing remains separate from recognition and opt-in LLM features.
- [ADR-007](../../spec/adr/007-fluidaudio-coreml-migration.md): retain native
  FluidAudio/CoreML; no Python runtime for this feature.
- [ADR-021](../../spec/adr/021-whisperkit-multilingual-stt.md): Whisper remains
  local and uses the shared scheduler; preserve language and meeting routing.
- [ADR-026 §3](../../spec/adr/026-asr-engine-strategy.md): extend capability
  declarations and qualify accuracy with the ASR harness. Long-audio boosting
  is already identified as future work.
- [Existing vocabulary plan](../../plans/active/2026-07-03-parakeet-custom-vocabulary.md):
  reuse the same vocabulary store; do not transmit vocabulary content.

## Decisions for the grilling session

1. Required workflows: final dictation, final file/meeting transcription,
   and/or live preview. The five-minute cap makes this a material distinction.
2. Required engines: Parakeet TDT first, or Whisper as a release requirement.
3. Expected vocabulary languages and kinds: names, product terms, acronyms,
   and phrases; English alone or multilingual speech.
4. Then decide entry/discovery UX, activation and download consent, list-size
   policy, failure reporting, and measurable quality/latency acceptance.

The user confirmed the scope after three grilling rounds. Ticket 028 records
all decisions: English Parakeet TDT final dictation and file/meeting transcripts,
including long recordings; distinct word/replacement forms in the same store;
explicit activation/download consent; one shared list with per-job snapshots;
visible fallback and unsupported states; hints in Raw and Clean recognition;
a three-character minimum; and qualification up to 100 enabled terms.
Whisper, live preview, and multilingual qualification remain follow-up work.
The ticket, rather than this pre-decision research section, owns the agreed
acceptance criteria.

[fluid-pinned]: https://github.com/FluidInference/FluidAudio/blob/b9d43724cbdb5a980e441fd54180964e94d470f7/Documentation/ASR/CustomVocabulary.md
[ctc-paper]: https://arxiv.org/abs/2406.07096
[phase0]: 2026-07-04-custom-vocab-phase0.md
[fluid-session]: https://github.com/FluidInference/FluidAudio/blob/6428e291/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/CustomVocabulary/VocabularyBoostingSession.swift
[whisper-guide]: https://cookbook.openai.com/examples/whisper_prompting_guide
[whisper-issue]: https://github.com/argmaxinc/WhisperKit/issues/127
[whisper-config]: https://github.com/argmaxinc/argmax-oss-swift/blob/e2adabbe7d98dc4d0ab9a5b75424ecc42a9cdbef/Sources/WhisperKit/Core/Configurations.swift
[whisper-decoder]: https://github.com/argmaxinc/argmax-oss-swift/blob/e2adabbe7d98dc4d0ab9a5b75424ecc42a9cdbef/Sources/WhisperKit/Core/TextDecoder.swift
[whisper-fix]: https://github.com/argmaxinc/argmax-oss-swift/pull/497
[argmax-pro]: https://app.argmaxinc.com/docs/examples/custom-vocabulary

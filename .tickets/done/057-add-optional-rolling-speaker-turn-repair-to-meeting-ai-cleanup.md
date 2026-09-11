---
Assigned-To: pi
Tags: []
Parent:
Blocked-By: []
---

# Add optional rolling speaker-turn repair to meeting AI cleanup

## Problem

FluidAudio diarization can place a speaker transition one to three words late or
early relative to the transcript. This leaves obvious sentence fragments in the
wrong Reading Turn, for example:

```text
Speaker A: Oh yeah, I
Speaker B: think we should do it a different way.
```

Meeting AI cleanup already sends consecutive Reading Turns in serial batches, so
it can see and repair boundaries inside a batch. The current prompt explicitly
forbids moving text between entries, and the first turn of a later batch does not
include the preceding turn. As a result, AI cleanup cannot repair either kind of
boundary.

## Product decision

Add an optional meeting AI cleanup setting that lets the selected formatter model
repair clear text attribution errors between adjacent Reading Turns. This is a
post-processing feature for cleaned meeting presentation. It does not correct
ASR timestamps or diarization evidence.

The setting lets us ship the behavior, enable it when wanted, and explicitly
retranscribe saved meetings after release to see whether it improves real output.
Do not require model fine-tuning, an accuracy harness, or a pre-release diarization
benchmark.

## Settings placement

Place this control in **Settings → AI → AI Formatter**. It belongs to the AI
Formatter because it changes the formatter's meeting cleanup requests; it does
not configure speaker detection or the FluidAudio diarizer.

Add a separate settings row immediately below the existing **Use for transcripts**
and **Use for dictation** routing controls and any provider-unavailable message.
Place it before **Smart defaults**, **Formatter instructions**, and custom profiles.
Use this copy:

- Label: **Fix misplaced words between speakers**
- Detail: **During meeting AI cleanup, move clearly misplaced words between neighboring speaker turns. Applies to new and re-transcribed meetings.**

Keep the row visible for discoverability. Disable its switch when no AI Formatter
provider is available or **Use for transcripts** is off, and explain that dependency
in help or disabled-state text. Preserve its saved value while inactive so turning
transcript formatting off and back on does not discard the user's choice. Use a
trailing switch consistent with the other AI Formatter rows and provide the same
label and enabled/disabled value to accessibility.

Do not place this control in general meeting recording, speaker detection, or
diarization settings. Those locations would incorrectly imply that it changes
acoustic speaker detection or raw transcript evidence.

## Required behavior

- Add a persisted setting under **AI Formatter** for repairing speaker-turn
  boundaries in completed meetings. It is separately controllable and is applied
  only when meeting AI cleanup runs.
- Keep the setting off by default. Changing it does not silently rewrite saved
  meetings. New meeting cleanup and explicit meeting retranscription use its
  current value.
- When disabled, preserve the existing batch plan, prompt contract, requests,
  fallback, progress, and cancellation behavior. Meeting cleanup makes one
  request attempt per planned batch in both modes.
- When enabled, tell the formatter that text at an adjacent Reading Turn boundary
  may belong to the preceding or following speaker. It may move clear hanging
  words between those turns while performing the normal cleanup. If the correct
  boundary is not clear from the text, it must preserve the existing boundary.
- Preserve the selected AI provider, model, and formatter prompt. Do not add a
  new model, provider, or implicit network path.

## Rolling batch contract

Process the existing planned batches serially with one complete returned Reading
Turn carried between requests:

```text
Request 1: turns 1 2 3 4 5
Commit:    turns 1 2 3 4
Carry:                     cleaned turn 5

Request 2:                cleaned turn 5 + turn 6
Commit:                    revised turn 5
Carry:                                      cleaned turn 6

Request 3:                                 cleaned turn 6 + turns 7 8
Commit:                                     revised turns 6 7
Carry:                                                       cleaned turn 8
```

- Hold the final returned Reading Turn until the next request rather than
  committing it and later applying a patch.
- Prepend that complete cleaned turn to the next planned batch. The formatter may
  return a revised version after seeing the following turn.
- Commit all returned turns except the final one. Flush the final held turn after
  the last request.
- The carried Reading Turn is additional context. It must remain complete and
  must not be truncated, split, summarized, or replaced with a suffix excerpt.
- A failed request must not discard a previously accepted version of the carried
  turn. Use deterministic text for the failed new turns, carry the final
  deterministic new turn into the next request, and allow later batches to
  continue. Do not add retries.

## Full-turn request and response contract

The formatter MUST return complete Reading Turns. Do not ask for or accept diffs,
patches, moved-word lists, word IDs, split positions, edit operations, or partial
turns.

Requests and responses continue to use full JSON entries:

```json
{
  "entries": [
    {"id": "turn-5", "text": "Oh yeah, I think we should do it a different way."},
    {"id": "turn-6", "text": "That makes sense."}
  ]
}
```

- Return every input turn ID exactly once.
- Return the complete cleaned text for every input turn, including the carried
  turn.
- Treat the returned entries as the complete replacement for those cleaned
  Reading Turns, not as changes to apply to earlier output.
- Preserve entry order after mapping by ID. Keep the existing partial ID-mapping
  behavior: valid entries can be accepted when another entry is missing,
  duplicated, or unknown.
- Validate only the full JSON-entry shape and turn IDs. Do not apply lexical
  similarity, protected-value, output-length, non-empty, or other content
  preservation heuristics in either mode. An empty full-turn replacement is
  valid and the existing cleaned-presentation path drops that empty turn.
- Keep speaker labels outside the model output. An entry retains the speaker of
  its Reading Turn; moving text into that full entry changes its presented
  attribution.

## Evidence and failure contract

- Keep raw transcript text, `WordTimestamp` values, source attribution,
  diarization regions, Reading Turn timing, and word references unchanged as
  recoverable evidence.
- Store only structurally parsed, ID-mapped full-turn AI presentation overrides
  through the existing cleanup path.
- Do not claim that this feature repairs acoustic timestamps or the FluidAudio
  diarization model. It repairs obvious Reading Turn text attribution in the
  cleaned presentation.
- Continue writing complete request, response, rejection, cancellation, and
  fallback details to the existing meeting AI cleanup diagnostics.

## Acceptance criteria

- [x] **Fix misplaced words between speakers** appears in **Settings → AI → AI
  Formatter**, directly below the formatter routing controls and before prompt/profile
  controls. It is persisted, defaults off, remains visible, and is disabled with
  explanatory help when the formatter is unavailable or **Use for transcripts** is off.
- [x] With the setting off, the existing batch plan, prompt, requests, fallback,
  progress, and cancellation behavior are unchanged. Content-preservation
  heuristics are removed in both modes.
- [x] With batches containing 5, 1, and 2 turns, requests contain 5, 2, and 3
  complete turns respectively because the final returned turn is carried into
  the next request.
- [x] A carried turn is sent in full and the next successful response replaces
  its earlier cleaned version in full.
- [x] The enabled prompt permits clear text movement only between adjacent
  Reading Turns and requires complete JSON entries in response.
- [x] Responses use full turns only. No diff, patch, word-ID, split-position, or
  edit-operation interface is introduced.
- [x] Returned IDs still map correctly when the provider changes entry order.
- [x] Responses are checked only for JSON structure and turn-ID mapping. Empty
  replacements are accepted; lexical, protected-value, output-length, and
  non-empty content checks do not run in either mode.
- [x] A failed or malformed later request does not erase the last accepted
  carried turn or block cleanup of all subsequent batches.
- [x] Cancellation does not commit a partial response or lose the held turn.
- [x] New meeting finalization and explicit meeting retranscription use the
  current setting; changing the setting alone does not rewrite old meetings.
- [x] Canonical transcript, speaker, timing, diarization, source, and word-reference
  evidence remain unchanged.
- [x] Focused tests use formatter doubles to verify the request/response and
  failure contracts. They do not attempt to measure semantic accuracy.
- [x] Active Text Processing and product documentation describe the optional
  rolling cleanup behavior and its presentation-only scope. This ticket is the
  detailed specification; do not restore the retired `spec/` documentation tree.

## Out of scope

- Model fine-tuning or training.
- A synthetic, corpus, or audio accuracy harness and quantitative quality gates.
- Diff-based, patch-based, word-ID, or split-position model output.
- Forced alignment or changes to ASR, FluidAudio diarization, timestamps, or
  `SpeakerMerger`.
- Automatic rewriting of saved meetings without explicit retranscription.
- Claiming improved diarization accuracy before observing the optional feature in
  released use.

## Starting points

- `Sources/MacParakeetCore/TextProcessing/MeetingReadingTurnFormatter.swift`
- `Sources/MacParakeetCore/TextProcessing/MeetingTranscriptPresentationBuilder.swift`
- `Sources/MacParakeetCore/AppRuntimePreferences.swift`
- `Sources/MacParakeetViewModels/LLMSettingsViewModel.swift`
- `Sources/MacParakeet/Views/Settings/LLMSettingsView.swift`
- `Sources/MacParakeetCore/Services/TranscriptionService.swift`
- `Tests/MacParakeetTests/TextProcessing/MeetingReadingTurnFormatterTests.swift`
- `Sources/MacParakeetCore/TextProcessing/README.md`
- `README.md`

Completed ticket `048-batch-meeting-ai-cleanup-across-turns-with-a-20000-character-text-budget`
is relevant history. This ticket changes the later batching contract where the
current implementation again caps batches by turn count and text size.

## Resolution

Added the persisted AI Formatter control and meeting-only runtime route. Enabled
cleanup now carries complete full-turn output across planned requests, preserves
accepted carry on request, response, and cancellation failures, and continues
with deterministic fallback for new turns. JSON structure and turn IDs remain
the only response checks; empty presentation overrides are valid. Updated active
documentation and focused tests. The full `swift test` suite passed with 5,220
tests, 26 skipped, and no failures.

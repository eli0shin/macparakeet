# Text Processing

> Deterministic post-processing for raw STT output. No LLM in the
> default path; the AI formatter is opt-in and lives behind a separate
> entry point.

## Entry point

`TextProcessingPipeline` — pure value type, `process(text:customWords:snippets:)`
returns a `TextProcessingResult`. Same input always produces the same
output. This is the function called for every dictation in "clean"
mode.

## What's here

- `TextProcessingPipeline.swift` — the deterministic pipeline. Five
  steps in fixed order; details below.
- `CustomWordReplacer.swift` — pre-compiled, reusable custom-word
  replacement (the step-2 rule). `TextProcessingPipeline.applyCustomWords`
  and deterministic meeting cleanup delegate to it.
- `TextProcessingResult.swift` — value type returned by the pipeline.
  Carries the cleaned text, the set of expanded-snippet IDs, and an
  optional `postPasteAction` for trailing-action snippets.
- `TextRefinementService.swift` — small coordinator for Raw vs Clean
  text refinement. Raw mode skips full cleanup but still extracts
  trailing action snippets; Clean mode runs `TextProcessingPipeline`.
- `AIFormatter.swift` — supporting prompt/rendering types for the
  opt-in provider-based AI formatter used after deterministic cleanup
  in dictation and file/URL transcription flows.
- `TranscriptDerivers.swift` — derives display-side fields
  (search-friendly text, summaries' rendering helpers, etc.) from
  stored transcripts. Read-only; doesn't mutate the canonical text.
- `TranscriptParagraphBuilder.swift` — groups timestamped words into
  deterministic reading paragraphs for TXT/Markdown exports and the meeting
  live preview. It does not replace subtitle cues or persisted transcript
  segments.
- `MeetingTranscriptPresentationBuilder.swift` — pure completed-meeting boundary
  that forms source utterances, assigns remote speakers from aggregate diarization
  overlap, smooths weak isolated changes, and derives Reading Turns, readability
  metrics, bounded paragraphs, cleaned readable text, time ranges, and raw-word
  references without changing canonical transcript evidence. Normal completed-
  meeting surfaces always select `.cleaned`, independent of the dictation
  Raw/Clean preference. `.verbatim` remains available for evidence-focused use.
- `MeetingReadingTurnFormatter.swift` — optional AI formatting module for completed
  meetings and timestamped file transcripts. It sends finalized Reading Turns in
  sequential JSON batches and maps structurally valid output back by stable turn
  ID. Meeting cleanup can optionally carry one complete returned turn into the
  next request so the formatter can repair clear presentation-text attribution
  errors at adjacent speaker boundaries. Failed batches use deterministic text
  without blocking later batches. Cancellation is reported to the transcription
  workflow.
- `MeetingTranscriptDocumentRenderer.swift` — shared completed-meeting boundary
  and plain-text/Markdown projections for copy, readable exports, meeting
  artifacts, rich AI context, and containing-turn navigation. It does not
  replace subtitle cues or evidence-focused exports.

## Cross-references

- ADR-004 — deterministic pipeline over LLM-based refinement. Captures
  the *principle* that default cleanup must be deterministic and
  fast. (The ADR's step table predates the trailing-action step; the
  code below is authoritative on step count.)
- `spec/07-text-processing.md` — narrative spec.
- ADR-011 — the LLM provider model that the separate AI formatter
  rides on.

## What to know before editing

**The five pipeline steps run in this fixed order:**

1. **Filler removal.** Strip conservative hesitation spellings (`uh`,
   `umm`, `uhh`) only. Word-boundary regex, case-insensitive,
   pre-compiled at type level. The list is intentionally short —
   anything longer ("like", "you know", "kind of") changes meaning
   too often to delete by default.
2. **Custom word replacement.** User-defined `CustomWord` entries.
   Replaces matches whole-word, case-insensitive, in the order
   provided. Disabled entries skip silently.
3. **Trailing action extraction.** If the user's text ends with an
   action-snippet trigger (snippet whose `action != nil`), strip the
   trigger from the text and surface the action through
   `postPasteAction` on the result. Done **before** snippet
   expansion so the trigger phrase isn't mangled by step 4.
4. **Text snippet expansion.** Plain text snippets (where
   `action == nil`) replace their trigger phrases with their bodies.
5. **Whitespace cleanup and insertion styling.** Collapse repeated
   spaces, fix punctuation spacing, normalize, then apply the selected
   dictation insertion style. Sentence style preserves the historic
   first-letter capitalization behavior. Inline style removes terminal
   sentence punctuation and lowercases ordinary sentence-initial words
   while preserving acronyms, camelCase, custom vocabulary, and expanded
   snippet casing.

**The order is load-bearing.** Action extraction before snippet
expansion prevents a plain-text snippet from consuming the action
trigger. Don't reorder without writing a test that exercises every
adjacent-step interaction.

**The pipeline is a pure function.** No I/O, no side effects, no
state. This makes it trivial to test exhaustively (see
`Tests/MacParakeetTests/`) and means you should not introduce
file/network/logging into the steps. If you need observability, do
it at the call site, not inside the pipeline.

**Filler removal is intentionally narrow.** Any expansion of the
`alwaysSafeFillers` list needs a thoughtful test case demonstrating
it doesn't change meaning in every supported language. Portuguese and
German use `um` semantically, so it is preserved even though English
speakers may use the same spelling as a hesitation.

**The AI formatter is a different code path.** `TextRefinementService`
does not call an LLM. It returns deterministic cleanup (plus any
post-paste action) first; dictation and transcription services may
then invoke the opt-in AI formatter through `LLMService`. Don't
conflate those two stages — the deterministic pipeline must remain
LLM-free per ADR-004.

**Reading Turn speaker attribution is presentation-only.** The builder forms
utterances per capture source before it reads remote-speaker evidence. Microphone
utterances remain `Me` when microphone speaker detection is off. When enabled,
local speakers receive the same source-isolated evidence treatment as remote
speakers, with a neutral `Local Speakers` fallback. System utterances use aggregate overlap with retained
diarization regions, with aggregate word labels only as a legacy fallback. An
isolated remote-speaker run shorter than one second is absorbed when the same
stable speaker surrounds it, unless at least 200 ms of concurrent diarization
supports a genuine interjection. A supported interjection remains a separate,
seekable contribution. After attribution, words are ordered by start time with
original evidence order as the tie-breaker. Intervening contributions split the
surrounding speaker's turn; questions never move behind that speaker's later
words. Reading Turns have no simultaneous-speech grouping or markers.
Same-speaker sentence utterances merge across gaps shorter than 2.5 seconds;
long pauses and completed source exchanges stay as boundaries. Live preview
paragraphs also order words by start time before grouping. This local policy
does not rewrite words or diarization regions.

**AI formatting changes presentation text, not transcript evidence.** The
formatter never sends speaker labels, timestamps, overlap state, or word
references. A Reading Turn of 500 or more characters is one uncapped request and
is never split or truncated. Consecutive shorter turns share a request while
their combined source text stays at or below 500 characters and the planned
request contains at most 10 turns. Every request and response uses the same JSON
`entries` contract with transport IDs, including requests that contain one turn.
Responses are checked for JSON structure and mapped by ID; lexical similarity,
protected-value, length, and non-empty content heuristics do not run. Valid
entries commit independently, and an empty override removes that turn only from
the cleaned presentation.

The off-by-default **Fix misplaced words between speakers** AI Formatter setting
applies only to meeting cleanup. When enabled, the formatter can move clearly
misplaced words between adjacent Reading Turns. The final complete returned turn
is held and prepended to the next planned batch so boundaries across requests can
also be repaired. The carried turn is additional, uncapped context. A failed
request keeps the last accepted carried version, uses deterministic text for new
turns, and continues with that final deterministic turn as the next carry. A
cancelled operation is not persisted. Durable overrides include the turn identity
and deterministic source text; stale overrides fail closed. Canonical raw text,
word timestamps, speaker evidence, timing, sources, and word references never
change. The selected formatter provider, model, and prompt are reused, so this
setting adds no implicit network path.

Each meeting AI cleanup batch writes an awaited local diagnostic to
`~/Library/Logs/MacParakeet/meeting-ai-cleanup.jsonl`. It includes the complete
input and output JSON, acceptance/rejection/cancellation outcome, turn counts,
and exact rejection reason with the failed turn and validation values. Text is
not redacted. A `provider_response` record with the same diagnostic ID stores
the full rendered prompt, original response content, reasoning content, provider,
model, and stop reason before parsing or validation. This preserves truncated
and empty responses too. Provider errors retain their error detail; credentials
and request headers are not collected. System logs also record the outcome and diagnostic
path. `llm_formatter_used` records provider completion, not validation acceptance;
use the cleanup diagnostic to determine whether the result was accepted.

**Meetings have a separate deterministic cleanup boundary.** New finalized
meetings and explicit meeting retranscriptions keep STT text, timed words,
source attribution, and diarization as raw evidence. `MeetingTranscriptCleaner`
derives and persists `cleanTranscript` with the shared conservative filler
policy, `CustomWordReplacer`, whitespace and punctuation normalization, and
sentence capitalization. It deliberately does **not** expand snippets, extract
trailing actions, execute paste actions, apply dictation insertion styling, or
call an LLM. Normal meeting UI, copy, search, readable exports, artifacts, and
AI context use cleaned text or the equivalent deterministic Reading Turn
projection. Legacy rows with no `cleanTranscript` use that projection without a
storage write. JSON, SRT, VTT, and other evidence-focused paths continue to use
raw words and timing.

## How to verify a change

- `swift test --filter TextProcessing` — covers the pipeline at the
  step level and end-to-end. Add a focused test for any new behaviour
  before changing the pipeline body.
- `swift test` — full suite (~100 s). Pipeline regressions ripple
  into transcription tests because every dictation runs through it.
- Manual: dictate something with each kind of trigger (filler word,
  custom word, text snippet, action snippet) and confirm the result
  is unsurprising. Edge cases worth checking: empty input, input
  that's only fillers, snippet that expands into another snippet's
  trigger (we do not recurse on purpose).

# Completed-Meeting Reading Turn Consumers

## Local speakers

Reading Turns recognize `microphone:<id>` as microphone speech, not remote
speech. Detected local speakers use their saved names; `microphone:unknown`
is the neutral `Local Speakers` fallback. Legacy `microphone` stays `Me`.
Speaker evidence is evaluated within each capture source. Concurrent evidence
can support speaker attribution, but does not create simultaneous-speech groups.
All completed-meeting consumers retain this attribution without changing
canonical word text, timing, confidence, or source.

> Status: ACTIVE - stable readable transcript consumer contract.

## Purpose

A completed, unedited meeting has one canonical derived Reading Turn document.
Copy, export, artifact, summary, and chat consumers use that document unchanged.
The completed-meeting UI has a separate derived display document that collapses
consecutive same-speaker runs. This display-only grouping does not change AI
request grouping, readable exports, or stored formatting mappings.

## Producers

- `MeetingTranscriptPresentationBuilder` derives canonical Reading Turns from
  transcript words, speaker metadata, and retained diarization evidence.
- `MeetingTranscriptDisplayBuilder` groups canonical turns for the completed-
  meeting UI by capture source and resolved speaker ID.
- `CompletedMeetingReadingDocument` applies the completed-meeting and edited-text
  compatibility guards.
- `MeetingTranscriptDocumentRenderer` produces Markdown and plain-text
  projections without regrouping transcript evidence.

## Consumers

- Completed-meeting displayed-turn blocks and their context copy actions. The
  visible reading surface omits overlap decoration and internal contribution
  targets. Canonical turns do not receive overlap identities.
- Full meeting and transcript clipboard actions.
- TXT and Markdown exports.
- `meeting.md` artifact rendering.
- Rich summary, prompt, and chat context, including all `prompts run` output modes.
- Search and citation navigation that needs a containing seek target.

## Stable Semantics

- All normal reconstructed documents use deterministic cleaned meeting text and
  the current enabled vocabulary. The global dictation Raw/Clean preference does
  not change completed meetings. Raw timed words remain unchanged evidence.
- Canonical readable-output blocks follow Reading Turn order and use the current
  speaker label.
- The completed-meeting UI collapses every adjacent run with the same capture
  source and resolved speaker ID. Labels do not define identity. Only a different
  speaker ends a run; pauses, paragraph and AI-formatting boundaries, and overlap
  metadata do not.
- A displayed turn retains the first canonical turn identity and start time, all
  paragraphs and word references in order, and no internal UI or accessibility
  target. Playback focus, transcript find, and containing citation navigation use
  that one displayed turn.
- Canonical rendered turns have at most one start time. Word timestamps are not
  emitted in readable output.
- Paragraphs remain separate inside their canonical or displayed turn. The UI
  renders exactly one empty text row between displayed paragraphs. The display
  builder preserves existing paragraph breaks and joins grouped contributions
  with `\n\n`, not a single newline. Line spacing is not a blank-line substitute.
  Validate visible spacing in the running app, not isolated test-host images. Optional AI
  cleanup sends all deterministic Reading Turn text in one request, separated by
  stable boundaries that map validated output back into source order without
  giving the model control of Reading Turn structure.
- Contributions follow word start time, with original evidence order breaking
  ties. An intervening contribution splits the surrounding speaker's turn,
  including during concurrent speech. No simultaneous-speech group or marker is
  emitted by UI, copy, readable export, artifact, or rich AI-context consumers.
  Live preview also orders words by start time before paragraph grouping.
- Word-based citations resolve to the containing Reading Turn and return that
  turn's seekable time range. Time-based containment does not guess across gaps.
- Untimed fallback text has no fabricated timestamp or speaker attribution.
- Edited transcripts use the existing plain edited text because word alignment
  is no longer valid.
- Meeting AI cleanup publishes formatting only when the complete response maps
  to every requested Reading Turn and passes content-preservation checks. A
  failed or malformed request leaves all turns deterministic. It is not retried
  with chunked or reduced context. The prompt explicitly requires preservation
  of all boundary markers and short contributions. Every acceptance, rejection,
  cancellation, or empty-document skip writes a local JSONL diagnostic in
  `~/Library/Logs/MacParakeet/meeting-ai-cleanup.jsonl`. Diagnostics retain full
  input/output text, turn counts, and exact rejection reasons (failed turn,
  observed values, and validation limits), without redaction. Provider failure
  details are retained when available. A correlated `provider_response` record
  preserves the full prompt and original content/reasoning before parsing,
  normalization, or truncated/empty-response rejection. Provider completion is not evidence that
  the meeting cleanup passed validation.
- Plain AI-context mode remains the preferred stored `cleanTranscript`, with raw
  text only as a legacy fallback. Legacy meeting card snippets and rebuildable
  search segments derive deterministic cleanup in memory; segment index version
  3 replaces older raw-derived rows without backfilling `cleanTranscript`.
- SRT and VTT remain cue projections of canonical raw word timings. When an
  unedited meeting has no word timings, their single-cue fallback and DAPT's
  untimed event use `rawTranscript`, not deterministic cleaned text. A manual
  transcript edit remains authoritative and drops stale timing. JSON keeps its
  existing evidence-focused contract.

## Versioning And Compatibility

This is a semantic contract, not a serialized schema. UI display grouping is
computed in memory for existing and new meetings and needs no migration.
Formatting marks can change when all canonical readable consumers and tests
change together. A change to canonical turn formation, overlap order, paragraph
boundaries, attribution, or navigation must update the builder, every projection,
this contract, and the shared consumer fixture in one change.

## Tests That Enforce This

- `MeetingReadingTurnConsumerTests`
- `MeetingTranscriptPresentationBuilderTests`
- `MeetingTranscriptDisplayBuilderTests`
- `TranscriptAIContextFormatterTests`
- `MeetingMarkdownRendererClipboardTests`
- `ExportServiceTests`
- `PromptsCommandTests`

The shared consumer fixture compares readable exports, clipboard output,
meeting Markdown, and AI context with one derived Reading Turn document. Its
dictation-Raw fixture proves that meeting cleanup and vocabulary replacement
stay active across direct artifact, background AI, and CLI-readable export
reconstruction. It also pins rename
propagation, chronological rendering, paragraph preservation, containing navigation,
untimed fallback, verbatim availability, and SRT/VTT cue retention.

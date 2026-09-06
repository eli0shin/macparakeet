# Completed-Meeting Reading Turn Consumers

> Status: ACTIVE - stable readable transcript consumer contract.

## Purpose

A completed, unedited meeting has one derived Reading Turn document. The app
uses projections of that document when a user reads, copies, exports,
summarizes, or chats about the meeting. Consumer-specific decoration can differ,
but speaker order, overlap membership, paragraph boundaries, and turn start
ranges must not drift.

## Producers

- `MeetingTranscriptPresentationBuilder` derives Reading Turns from canonical
  transcript words, speaker metadata, and retained diarization evidence.
- `CompletedMeetingReadingDocument` applies the completed-meeting and edited-text
  compatibility guards.
- `MeetingTranscriptDocumentRenderer` produces Markdown and plain-text
  projections without regrouping transcript evidence.

## Consumers

- Completed-meeting transcript cards and per-turn copy actions.
- Full meeting and transcript clipboard actions.
- TXT and Markdown exports.
- `meeting.md` artifact rendering.
- Rich summary, prompt, and chat context, including all `prompts run` output modes.
- Search and citation navigation that needs a containing seek target.

## Stable Semantics

- All normal reconstructed documents use deterministic cleaned meeting text and
  the current enabled vocabulary. The global dictation Raw/Clean preference does
  not change completed meetings. Raw timed words remain unchanged evidence.
- Each rendered block follows Reading Turn order and uses the current speaker
  label.
- A rendered turn has at most one start time. Word timestamps are not emitted in
  readable output.
- Paragraphs remain separate inside their Reading Turn.
- Simultaneous contributions retain one explicit overlap marker and deterministic
  contribution order.
- Word-based citations resolve to the containing Reading Turn and return that
  turn's seekable time range. Time-based containment does not guess across gaps.
- Untimed fallback text has no fabricated timestamp or speaker attribution.
- Edited transcripts use the existing plain edited text because word alignment
  is no longer valid.
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

This is a semantic contract, not a serialized schema. Formatting marks can
change when all readable consumers and tests change together. A change to turn
formation, overlap order, paragraph boundaries, attribution, or navigation must
update the builder, every projection, this contract, and the shared consumer
fixture in one change.

## Tests That Enforce This

- `MeetingReadingTurnConsumerTests`
- `MeetingTranscriptPresentationBuilderTests`
- `TranscriptAIContextFormatterTests`
- `MeetingMarkdownRendererClipboardTests`
- `ExportServiceTests`
- `PromptsCommandTests`

The shared consumer fixture compares readable exports, clipboard output,
meeting Markdown, and AI context with one derived Reading Turn document. Its
dictation-Raw fixture proves that meeting cleanup and vocabulary replacement
stay active across direct artifact, background AI, and CLI-readable export
reconstruction. It also pins rename
propagation, overlap rendering, paragraph preservation, containing navigation,
untimed fallback, verbatim availability, and SRT/VTT cue retention.

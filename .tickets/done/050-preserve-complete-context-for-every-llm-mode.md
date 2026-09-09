---
Assigned-To: macparakeet@050-preserve-complete-context-for-every-llm-mode
Tags:
  - llm
  - ai-safety
Parent:
Blocked-By: []
---

# Preserve complete context for every LLM mode

## Problem

MacParakeet currently applies provider-specific character budgets while it
assembles LLM requests. It can truncate source input from the middle, truncate
meeting notes, and remove old chat turns. LM Studio has a particularly small
hard-coded budget of 8,000 characters even when the loaded model supports a
much larger context.

This makes LLM output untrustworthy. A model can claim that information is not
in a transcript because MacParakeet silently removed that information before
sending the request.

## Required invariant

Every LLM operation must send its complete relevant source input through one
context-preservation policy. This rule applies to every current and future LLM
mode, including:

- Meeting Ask
- saved-transcript chat
- summaries and prompt results
- transcript and dictation formatting
- Transforms
- knowledge-card generation and other shared LLM operations

No individual mode or provider adapter may weaken this invariant.

## Requirements

- Send the complete transcript or other source input on every request.
- Send complete meeting notes when they apply.
- Send the complete chat history, including every old user and assistant turn,
  on every chat request.
- Never truncate source input, notes, questions, prompt overrides, or chat
  history. Middle truncation is explicitly prohibited.
- Never compact, summarize, retrieve, rank, select, or drop context as a
  substitute for sending the complete input.
- Never use chunking, RAG, semantic search, full-text search, context shifting,
  or a reduced-context retry as a fallback.
- Do not classify prompts or route them through different context strategies.
  Every prompt follows the same complete-context path.
- Do not require the user to count tokens or manage an application-side
  character budget. Assume the configured provider/model context is sufficient.
- If the provider rejects the complete request because it exceeds the
  provider's context window, surface a clear error and stop. Do not retry with
  less context.
- Preserve useful timestamps and available speaker labels in Rich transcript
  context. Do not add synthetic turn numbers. An explicit Plain transcript
  selection may omit presentation metadata, but it must still preserve all
  source text.
- Operation-specific instructions and transport-specific request formats may
  wrap the source input, but they must not remove or rewrite any source content.

## Acceptance criteria

- [x] `LLMService` has no provider-specific source-input truncation behavior,
  including the 500,000-character cloud budget, 80,000-character local budget,
  and 8,000-character LM Studio budget.
- [x] Inputs larger than each former budget are delivered completely to the
  selected LLM client.
- [x] Meeting Ask and saved-transcript chat deliver the complete transcript,
  complete applicable notes, complete prompt override, and complete chat
  history, including the oldest turns.
- [x] Summary/prompt-result, formatter, Transform, knowledge-card, and every
  other shared LLM operation deliver their complete relevant source input.
- [x] No assembled request contains a MacParakeet-generated truncation marker
  or silently omitted source range.
- [x] No LLM mode performs a second reduced-context request after a provider
  context-limit error.
- [x] A provider context-limit error is shown clearly to the caller or user.
- [x] Rich transcript context retains timestamps and available speaker labels
  without synthetic turn identifiers. Plain context remains complete.
- [x] Focused tests use distinct beginning, middle, and ending sentinels plus
  old-history sentinels to prove that all content reaches the client unchanged.
- [x] Governing LLM specifications and privacy/user documentation state the
  complete-context and no-fallback behavior.

## Must not change

- Speech recognition remains local, and LLM providers receive text rather than
  meeting audio.
- Existing provider routing, authentication storage, streaming presentation,
  chat persistence, and live-to-saved conversation handoff remain intact except
  where needed to enforce complete context.
- Provider failures must not interrupt meeting recording or damage saved user
  data.

## Relevant code and decisions

- `Sources/MacParakeetCore/Services/LLM/LLMService.swift`
- `Sources/MacParakeetViewModels/TranscriptChatViewModel.swift`
- `Sources/MacParakeetViewModels/MeetingRecordingPanelViewModel.swift`
- `Sources/MacParakeetCore/TextProcessing/TranscriptAIContextFormatter.swift`
- `spec/11-llm-integration.md`
- `spec/adr/011-llm-cloud-and-local-providers.md`
- `spec/adr/018-live-meeting-insights-and-ask.md`

## Resolution

PR #56 merged into main as `d0fe50b807a1f30392114b7d4062c1ca1bd842ef` from reviewed head `755db756b3a52329870f9325c2a373d52f18c6dd`. CI run `34297876444` passed, including the formerly failing settings test. Independent review found no actionable issues or remaining contract violations. Generated CLI specification inspected and valid; release/DMG jobs skipped. This complete-context policy replaces bounded meeting cleanup requests with one complete request, as required by this ticket. Merge compatibility passed. Live-model output quality was not verified.

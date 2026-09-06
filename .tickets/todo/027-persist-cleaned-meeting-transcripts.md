---
Assigned-To:
Tags:
  - ready-for-agent
Parent: 023-simplify-meeting-transcript-experience
Blocked-By: []
---

## What to build

For newly finalized and explicitly re-transcribed meetings, persist both the untouched raw transcript and a separate deterministic cleaned transcript. Normal meeting surfaces must use the cleaned transcript even when the global dictation processing preference is Raw.

Use the existing `rawTranscript` and `cleanTranscript` domain fields rather than adding duplicate concepts. Raw transcript text, timestamped words, source attribution, diarization regions, and Reading Turn references remain canonical evidence. Derive and store cleaned meeting text without rewriting that evidence.

Meeting cleanup reuses only text-safe deterministic behavior: conservative filler removal, custom-word replacement, whitespace normalization, punctuation spacing, and sentence capitalization. Do not expand text snippets, execute trailing action snippets, apply paste actions, use dictation insertion styling, or add a network/LLM dependency. Keep optional AI formatting and manually edited clean text authoritative when present.

Do not automatically backfill existing saved meetings. They gain the new persisted cleaned form only through explicit re-transcription.

## Consumer contract

Use cleaned meeting text for normal transcript UI, copy, search/indexing, readable TXT/Markdown/PDF/DOCX exports, meeting artifacts' readable projection, summaries, prompts, and AI/chat context. Evidence-focused JSON and timed subtitle/cue exports preserve raw words and timing. A missing cleaned transcript on an older meeting falls back safely to the current deterministic Reading Turn presentation without mutating storage.

## Acceptance criteria

- [ ] New finalized meetings store unchanged raw transcript evidence and a separate deterministic cleaned transcript.
- [ ] Explicit meeting re-transcription derives and stores cleaned text while preserving the newly produced raw evidence.
- [ ] Existing meetings are not mutated or backfilled merely by launch, browse, search, copy, export, or migration.
- [ ] Global dictation Raw/Clean mode no longer makes normal completed-meeting UI verbatim; normal meeting UI uses cleaned text in both modes.
- [ ] Safe filler removal includes the spellings supported by the governing deterministic policy, including `uh`; any addition such as `uhm` is made once in shared policy with multilingual safety tests.
- [ ] Custom-word replacement, spacing, punctuation, and sentence capitalization match the shared deterministic cleanup contract.
- [ ] Snippet expansion, trailing actions, paste actions, insertion styling, and LLM calls never run in this deterministic meeting path.
- [ ] Existing optional AI-formatted or manually edited `cleanTranscript` content is not silently overwritten outside explicit re-transcription.
- [ ] Normal UI, copy, search, readable exports, artifacts, summaries, prompts, and chat consume cleaned meeting text with a safe fallback for legacy rows.
- [ ] JSON/subtitle evidence paths retain canonical raw text, word timing, speaker/source evidence, and cue alignment.
- [ ] Reading Turn word references, seeking, speaker attribution, overlap evidence, and transcript correction remain valid after cleanup.
- [ ] Database, finalization, re-transcription, consumer, legacy-row, and no-backfill tests cover the contract.
- [ ] The Text Processing README and affected feature/contract documentation describe the new persisted raw-versus-cleaned boundary.
- [ ] Applicable focused tests and CI checks pass.

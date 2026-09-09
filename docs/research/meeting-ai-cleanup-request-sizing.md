# Meeting AI cleanup: request size and cost

Source snapshot: `2ee7b5e1`. This is a source-code investigation, not a performance measurement of the work Mac. Its app version, transcript, LM Studio settings, and model timings were not available. No model requests or benchmarks were run. Existing tests were read, not executed. No application behavior was changed.

## Main finding

Completed meetings use **Reading Turns as request boundaries**, not a target batch size. Paragraphs can share a request only within the same turn. A short acknowledgement can therefore cost one complete model invocation. Hundreds of eligible turns normally mean hundreds of serial requests. The model receives text only, not the speaker/timing structure used to form those turns. [1][2]

```text
Raw speech evidence: transcript + timed words + speakers
  → deterministic Reading Turns
      Turn A: paragraph 1 + paragraph 2 → request 1
      Turn B: “Yes.”                   → request 2
      Turn A: next contribution        → request 3
  → send each request and wait for its complete response
  → validate response against the original request
  → save a text override only when all requests for that turn pass
```

This is distinct from file/URL transcription: that path sends one whole cleaned transcript if it is at most 20,000 characters; otherwise it skips AI formatting. A meeting without timed words has one fallback Reading Turn, rather than speaker-based turns. [1][3][4]

## How boundaries are chosen

| Layer | Actual rule |
|---|---|
| Source utterances | Work independently within microphone/system/unknown sources. Split at sentence endings, pauses of at least 2.5 seconds, or completed exchanges with another source. |
| Reading Turns | Resolve speakers from evidence, smooth weak isolated speaker changes, and merge eligible same-speaker utterances. Sentence endings alone do not necessarily create separate requests. |
| Speaker smoothing | An isolated run below one second of reliable evidence can be absorbed between the same stable speaker. At least 200 ms of supported concurrent speech can preserve an interjection. |
| Paragraphs | Split at 2.5-second pauses; pack complete sentences up to three sentences / 80 words. A single long sentence can exceed 80 words. |
| Request packing | Greedily join complete paragraphs with blank lines, up to 20,000 Swift characters, **inside one Reading Turn only**. |
| Oversized paragraph | If any paragraph exceeds 20,000 characters, skip AI for the whole turn. Do not split that paragraph. |
| Small turns | No minimum size, quality gate, or short-acknowledgement bypass. |
| Scheduling | Serial, with no cross-turn batching, explicit pacing delay, or meeting-wide request/time budget in this loop. |

Sources: presentation rules [4][5], request planning and scheduling [2]. These are character and structural rules, not tokenizer-aware packing, topic detection, fixed audio windows, or hardware-aware sizing.

## What LM Studio receives

Each call is a fresh non-streaming `POST /chat/completions`, with this request shape (instructions shortened here): [6][7][8]

```json
{
  "model": "<selected model>",
  "messages": [
    {"role": "system", "content": "You are a transcription formatting assistant. ..."},
    {"role": "user", "content": "<cleanup instructions>\n\nRaw transcript:\n<text from one turn>"}
  ],
  "stream": false,
  "temperature": 0.2,
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "formatter_output",
      "schema": {
        "type": "object",
        "properties": {"cleaned_text": {"type": "string"}},
        "required": ["cleaned_text"],
        "additionalProperties": false
      }
    }
  }
}
```

The default user instructions request punctuation, sentence and paragraph breaks, obvious STT corrections, and removal of unnecessary repetitions/fillers. They prohibit summarization, shortening, added content, and explanations. A custom formatter prompt replaces those user instructions. [9]

Not included by the formatter: audio, speaker labels/IDs, turn IDs, timestamps, word confidence, diarization evidence, overlap state, meeting title/notes, adjacent turns, or prior requests/responses. Such words can of course appear in the transcript itself or a custom prompt. Vocabulary is already applied through deterministic cleanup; the formatter does not attach a separate vocabulary list. [1][2][6]

LM Studio-specific controls:

- JSON output containing `cleaned_text`; `temperature: 0.2`. [6]
- `max_tokens` is omitted: the options default to `nil`. Server/model defaults determine the output limit. This does **not** prove that generation is unlimited. [7][8]
- The adapter sets a 300-second non-streaming local request timeout, not a meeting-wide deadline. [7]
- No explicit Gemma thinking/reasoning control is sent in this request shape. Actual reasoning behavior must be checked in LM Studio. [7]
- No app-level retry loop exists on this HTTP completion path; a failed turn falls back and later turns continue. [2][7][10]

## Two different size limits

```text
Meeting planner:      ≤20,000 characters of turn text
                              ↓
LM Studio service:    8,000 characters for system + rendered prompt
                     − about 1,082 characters of default instructions
                     = about 6,918 characters of transcript
                              ↓
Too long?            Replace the middle with a truncation marker
                     Keep beginning and end; do not make more requests
```

The 8,000-character LM Studio budget is a hard-coded provider rule. It is not derived from the loaded model's context window, tokenization, available RAM, or GPU. The planner does not know about this lower budget. Custom prompts change the remaining allowance. The budget calculation does not account for the response schema, chat token framing, or generated output. [6][11]

The approximate 1,082-character instruction count comes from the shipped default template with an empty transcript plus the system prompt. It excludes JSON/schema overhead. Character counts are not token counts. [9][12]

This mismatch means some planned requests are sent with missing middle text, then validated against the **full original request**. They can fail preservation validation after using model time. Validation is not a strict completeness proof: it allows bounded lexical changes, so smaller omissions could pass. The meeting path does not explicitly reject the `inputTruncated` flag. [1][2][3][6]

## Validation and progress

Each response must be non-empty, retain protected values (tokens containing digits, `@`, or `://`), have lexical insertion/deletion count divided by the larger token count at most 0.35, and have output length no greater than `max(1.5 × input length, input length + 200)`. Casing and punctuation do not count as lexical changes. This is not simply a “35% of words replaced” rule: a replacement can count as a deletion plus insertion. [2]

If one request fails, discard all AI output for that turn, skip its remaining requests, and continue with later turns. There is no automatic retry for rejected wording. Raw words, speakers, and timing remain unchanged. Workflow cancellation aborts completion without publishing partial overrides. [1][2][5]

`Formatting meeting... completed/total` reports planned requests, not subtitle segments or a literal count of successful HTTP calls. Skipped remaining requests after a turn failure also advance completed progress. [2][13]

## Cost example — illustrative, not the reported meeting

Assume 300 turns with 200 characters each, all below the provider budget:

- Transcript text: 60,000 characters.
- Requests: 300, sent serially.
- Repeated default instructions: about 324,600 characters, excluding JSON/schema.
- Total message content: about 384,600 characters before responses.
- At an assumed average of 2 seconds per complete request: 10 minutes. At 5 seconds: 25 minutes.

This is transmitted content, **not measured GPU work**. LM Studio may reuse cached prompt prefixes. The app does not send the entire meeting for every turn or build a growing chat history. It nevertheless starts a separate generation for every eligible request, and asks the model to reproduce almost all transcript text. [2][6][9][12]

Serial requests limit concurrency, but do not guarantee low instantaneous CPU/GPU load or provide idle time between calls. The actual load could also depend on model generation speed, reasoning, context configuration, quantization, and cache behavior; none was measured here.

## Optimization candidates

These are proposals, not implemented behavior or measured speedups.

1. **Unify planning with the provider budget.** Plan complete paragraphs against a model-aware input/output budget; do not silently truncate cleanup input. This addresses both wasted work and missing-text risk. Test long turns and custom prompts. [2][6][11]
2. **Batch multiple short turns while preserving separate output identities.** Pack a modest amount of text with stable IDs, and request one result per ID. Validate and apply each result independently; retain speaker/timing ownership outside the model. This changes the current no-cross-turn contract and needs focused correctness tests. Do not merge the displayed turns just to optimize transport. [2][5]
3. **Conservatively bypass trivial turns.** For example, already-clean short acknowledgements. A length-only gate can miss short STT errors or override custom-prompt intent. Measure coverage and quality first. [2][9]
4. **Set a suitable output budget and check reasoning behavior.** Use observed output ratios with headroom. Avoid blindly lowering limits: truncated output must fall back safely. Verify Gemma/LM Studio support before adding a reasoning control. [6][7][8]
5. **Bound repeated failures and total work.** Stop attempting hundreds of later turns after repeated provider failures; expose a time/request budget and preserve deterministic fallback. [2]

Do not start by increasing parallelism: it can raise peak load on the same local model. Larger batches also do not remove the need to generate the cleaned transcript, so fewer requests alone are not a speedup guarantee.

For a benchmark, first confirm the work Mac's app revision. Then capture request count; input-size distribution; prompt/completion tokens; per-call latency; cache/prefill and generation timings if available; reasoning settings; and accepted/rejected/fallback turn counts. Existing formatter run records contain some input/output size, usage, and latency data, but meeting preservation rejection occurs after the LLM service reports success, so service success alone is insufficient. Use synthetic or redacted text; work transcript contents are not required for initial measurement. [1][2][3][6]

## Sources

Paths and line references apply to source snapshot `2ee7b5e1`.

1. [TranscriptionService.swift:1994–2138](../../Sources/MacParakeetCore/Services/TranscriptionService.swift#L1994) — meeting completion and request wiring.
2. [MeetingReadingTurnFormatter.swift:47–253](../../Sources/MacParakeetCore/TextProcessing/MeetingReadingTurnFormatter.swift#L47) — planning, serial calls, validation, progress.
3. [TranscriptFormatter.swift:17–126](../../Sources/MacParakeetCore/TextProcessing/TranscriptFormatter.swift#L17) — whole-input cap, request forwarding, fallback.
4. [MeetingTranscriptPresentationBuilder.swift:190–389](../../Sources/MacParakeetCore/TextProcessing/MeetingTranscriptPresentationBuilder.swift#L190) and [paragraph/fallback construction:849–991](../../Sources/MacParakeetCore/TextProcessing/MeetingTranscriptPresentationBuilder.swift#L849).
5. [Text processing spec:49](../../spec/07-text-processing.md#L49) and [LLM integration contract:426–441](../../spec/11-llm-integration.md#L426).
6. [LLMService.swift:626–729](../../Sources/MacParakeetCore/Services/LLM/LLMService.swift#L626) — prompt assembly, input truncation, LM Studio options and run metadata.
7. [OpenAICompatibleLLMHTTPAdapter.swift:12–48](../../Sources/MacParakeetCore/Services/LLM/OpenAICompatibleLLMHTTPAdapter.swift#L12) and [request builder:178–244](../../Sources/MacParakeetCore/Services/LLM/OpenAICompatibleLLMHTTPAdapter.swift#L178).
8. [LLMTypes.swift:132–148](../../Sources/MacParakeetCore/Models/LLMTypes.swift#L132) — options defaults.
9. [AIFormatter.swift:5–85](../../Sources/MacParakeetCore/TextProcessing/AIFormatter.swift#L5) — 20,000-character cap and default/user prompt rendering.
10. [RoutingLLMClient.swift](../../Sources/MacParakeetCore/Services/LLM/RoutingLLMClient.swift), [LLMClient.swift](../../Sources/MacParakeetCore/Services/LLM/LLMClient.swift), [LLMHTTPTransport.swift:33–47](../../Sources/MacParakeetCore/Services/LLM/LLMHTTPTransport.swift#L33) — HTTP dispatch without app-level retries.
11. [LLMService.swift:157–159](../../Sources/MacParakeetCore/Services/LLM/LLMService.swift#L157), [budget selector:1129](../../Sources/MacParakeetCore/Services/LLM/LLMService.swift#L1129), [middle truncation:1400](../../Sources/MacParakeetCore/Services/LLM/LLMService.swift#L1400).
12. [LLMService.swift:1460–1463](../../Sources/MacParakeetCore/Services/LLM/LLMService.swift#L1460) — system formatter prompt.
13. [TranscriptionViewModel.swift:1509–1510](../../Sources/MacParakeetViewModels/TranscriptionViewModel.swift#L1509) — UI progress label.
14. [MeetingReadingTurnFormatterTests.swift](../../Tests/MacParakeetTests/TextProcessing/MeetingReadingTurnFormatterTests.swift) — existing tests for independent turns, paragraph boundaries, unsafe oversize input, validation, fallback and cancellation. Read, not run.

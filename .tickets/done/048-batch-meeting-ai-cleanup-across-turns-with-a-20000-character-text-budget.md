---
Assigned-To: macparakeet@048-batch-meeting-ai-cleanup-across-turns-with-a-20000-character-text-budget
Tags: []
Parent:
Blocked-By: []
---

# Batch meeting AI cleanup across turns with a 20,000-character text budget

## User request

Meeting AI cleanup sends hundreds of small requests and takes too long. Batch consecutive turns into larger requests. Remove the special 8,000-character LM Studio cap. Never truncate input. Keep paragraphs whole except when a single paragraph exceeds 20,000 characters; split that paragraph at sentence endings. Retry failures twice, then use raw text for the affected batch—not deterministic cleanup.

## Required behavior

- Batch consecutive turns across speaker changes, with a hard limit of 20,000 characters of transcript text per request for every provider. Instructions, IDs, and JSON structure do not count toward that text budget.
- Pack complete paragraphs in order, with a hard maximum of 20,000 characters of transcript text per request. Stop at the last paragraph that does not push the batch over the limit; start the next batch with the next paragraph.
- Only when a single paragraph exceeds 20,000 characters, split that paragraph at sentence endings. Do not exceed the request limit or discard any text.
- Send all transcript text. Do not truncate, shorten, or omit input in the planner, prompt renderer, service, or provider adapter.
- Remove the LM Studio-specific 8,000-character cleanup limit. Do not replace it with guessed model-context limits or automatically reduce batches based on provider assumptions.
- Change the default cleanup instruction from “Remove repeated words and filler sounds when unnecessary.” to “Remove repeated words and filler sounds.”
- Update the cleanup prompt to tell the model to clean each batch entry independently and preserve its ID.
- Tell the model not to combine entries or move text between them.
- Parse returned IDs to map cleaned text back to the correct turns and assemble turn parts in source order. Keep speaker labels and timing outside the model's control.
- Use the selected provider, model, and formatter prompt. Support the existing provider paths, not just LM Studio. Adapt the default and custom prompt rendering for the batch format.
- Retry a failed batch twice after the initial attempt: three attempts total. If all three fail, use raw text for the affected batch, not deterministic cleanup. This applies to request failures and responses that cannot be parsed or mapped by ID.
- Do not reject output solely because the provider reports a generation length limit. Remove content-change, protected-value, and output-size rejection checks from the batch cleanup path. Do not replace them with semantic-completeness or paragraph-coverage heuristics. Parse response structure and IDs to map the output, not to judge whether the model preserved meaning.
- Keep batch requests serial and preserve cancellation. Progress reports batch work, not one request per original turn.

## Acceptance tests

- 300 turns of 200 characters each pack into approximately three text-budget batches, not 300 requests. Speaker changes do not force a new request.
- All input text reaches model requests in order. Paragraphs remain whole except for the oversized-paragraph sentence-boundary rule. Tests compare assembled request text with source text through the service/adapter boundary, not only the planner.
- A batch stops at the last complete paragraph that fits within 20,000 characters. The next paragraph starts the next batch.
- A single paragraph over 20,000 characters splits at sentence endings, with all text retained and requests within the limit. Paragraphs that fit are not split.
- Default and custom instructions do not subtract from the 20,000-character text allowance. LM Studio and other provider paths do not truncate cleanup input.
- Returned IDs map correctly even if response entries arrive in a different order. Turn parts reassemble in source order.
- Request failures and malformed/missing/duplicate response IDs trigger up to two retries. A successful retry supplies the cleaned batch text; after three failed attempts total, the affected batch uses raw text, not deterministic cleanup.
- Content changes, protected-value changes, and output size do not trigger rejection or retries. A generation length stop reason alone does not reject returned output.
- Cancellation stops further batch requests. Disabled AI cleanup makes no model requests.

## Scope and documentation

- Keep raw transcript evidence, speaker identity, and timing intact. This ticket changes AI request batching, not displayed speaker grouping.
- Ticket `047-group-consecutive-same-speaker-meeting-transcript-blocks` owns the separate UI change. Neither ticket blocks the other.
- Keep unrelated summary/chat budgets and dictation behavior outside this change.
- Update the Text Processing README and `spec/11-llm-integration.md` to replace the old one-turn-per-request and fallback contracts. Update applicable boundary contracts and focused tests in the same change.
- Compare request counts and repeated instruction volume on the same fixture before and after the change.

## Starting points

- `Sources/MacParakeetCore/TextProcessing/MeetingReadingTurnFormatter.swift`
- `Sources/MacParakeetCore/TextProcessing/TranscriptFormatter.swift`
- `Sources/MacParakeetCore/TextProcessing/AIFormatter.swift`
- `Sources/MacParakeetCore/Services/TranscriptionService.swift`
- `Sources/MacParakeetCore/Services/LLM/LLMService.swift`
- `Sources/MacParakeetCore/Services/LLM/OpenAICompatibleLLMHTTPAdapter.swift`
- `Tests/MacParakeetTests/TextProcessing/MeetingReadingTurnFormatterTests.swift`
- `Tests/MacParakeetTests/Services/LLM/LLMServiceTests.swift`
- `Tests/MacParakeetTests/Services/LLM/LLMHTTPAdapterTests.swift`

The investigation in `docs/research/meeting-ai-cleanup-request-sizing.md` describes the old implementation at `2ee7b5e1`. Its optimization proposals and old fallback behavior are not requirements for this ticket. The requirements above supersede the conflicting behavior in completed ticket `007-format-long-meetings-with-bounded-ai-requests`.

## Resolution

PR #55 merged into main as `4b0eafc6a84f4954fc998ac6d4675f5d15aea63f` from reviewed head `be04782e08c1d3637561ed416b87f301ce6cce21`. CI run `34296503688` passed. Independent follow-up review confirmed all three findings resolved: non-batch length-stop behavior preserved, batch JSON bypasses plain-text normalization, and valid empty overrides survive persistence/presentation. No remaining ticket violations found. CI generated logs only; real-provider cleanup output was not verified. Merge compatibility passed with landed display grouping preserved.

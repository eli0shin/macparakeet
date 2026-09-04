# State of the art: readable speaker-aware meeting transcripts

> Scope: research into current transcript structure, diarization reconciliation, readable formatting, and meeting-product presentation. Primary sources are official provider documentation, model cards, open-source repositories, and the MacParakeet and Meetily source trees. This is a design study, not an implementation decision.

## Executive conclusion

The user's proposed direction matches the dominant architecture:

```text
word evidence
  -> source-aware utterances
  -> speaker-attributed turns
  -> reading paragraphs / speech blocks
  -> UI
```

Current systems keep timestamps, but they do not normally use every timestamp as a visible document boundary. Word timestamps are evidence for playback, search, export, and diarization reconciliation. The primary human unit is an **utterance**, **speaker turn**, **segment**, or **paragraph**.

MacParakeet currently collapses two separate concerns:

- **timing evidence:** fine-grained words and diarization regions;
- **reading structure:** the blocks a person should read.

That coupling explains both failure extremes:

- speaker/timestamp jitter creates too many tiny cards;
- the plain text fallback creates one large paragraph.

The best near-term target is not a new diarization model. It is a conservative **Reading Turn** layer that prefers a few large, stable blocks over many fragile splits. Meetily is a useful minimum target. Deepgram, AssemblyAI, OpenAI's diarization API, pyannote community-1, and WhisperX all provide additional patterns that support this design.

## Canonical term

Use **Reading Turn** for the human-facing unit:

> A Reading Turn is a contiguous, readable block attributed to one speaker, with a start and end time retained as metadata. It can contain multiple sentences and can be split into paragraphs when one person speaks for a long time.

This is different from:

- a **word timestamp**, which is alignment evidence;
- a **diarization region**, which is acoustic evidence about who is active;
- an **ASR segment**, which is an engine/chunking artifact;
- a **subtitle cue**, which is constrained by playback timing and screen space;
- a **paragraph**, which is prose structure inside or across a long Reading Turn.

The UI should show Reading Turns. It should not expose ASR chunks or individual diarization transitions as if they were editorial decisions.

## What current systems do

### Deepgram: words are nested evidence; utterances and paragraphs are products

Deepgram exposes separate features for:

- word timestamps;
- `utterances[]`, each with start, end, transcript, words, channel, and optional speaker;
- paragraphs and sentences;
- smart formatting.

Its official Utterances documentation describes conversational speech as spontaneous and reformulated, then returns a coherent utterance object that contains its words. Its diarization example prints one line per utterance, not one line per word.

Its Paragraphs documentation states that paragraph boundaries use punctuation and are influenced by speaker changes and channel changes. A paragraph contains sentences, a word count, start time, and end time. This is the hierarchy MacParakeet lacks in its detail UI.

Smart Format applies punctuation and paragraphs at minimum for supported whitespace-delimited languages. Deepgram also documents a configurable utterance-split silence threshold, with 0.8 seconds as the default. The important product lesson is not that 0.8 seconds is universally correct; it is that silence boundaries are one input to utterance formation, not a command to show a timestamp row.

Sources:

- [Deepgram: Utterances](https://developers.deepgram.com/docs/utterances)
- [Deepgram: Paragraphs](https://developers.deepgram.com/docs/paragraphs)
- [Deepgram: Smart Formatting](https://developers.deepgram.com/docs/smart-format)
- [Deepgram: Speaker Diarization](https://developers.deepgram.com/docs/diarization)
- [Deepgram: Utterance Split](https://developers.deepgram.com/docs/utterance-split)

### AssemblyAI: the diarized response is a turn-by-turn utterance list

AssemblyAI defines each diarized utterance as an uninterrupted segment of speech from one speaker. The utterance has speaker, text, start, end, confidence, and nested words.

It supports exact, minimum, and maximum speaker counts. Its guidance is conservative:

- use an exact count only when certain;
- use a range when uncertain;
- avoid a maximum that is much too high because that can over-split speakers;
- short phrases and limited speech provide weak speaker embeddings;
- echo, crosstalk, and noise reduce accuracy.

Its streaming documentation adds two useful robustness patterns:

1. turns shorter than about one second can remain `PENDING` instead of creating an unreliable speaker identity;
2. an end-of-session refinement can revise speaker labels while leaving text and timestamps unchanged.

This separates stable transcript content from revisable attribution. MacParakeet's final meeting pass is already offline, so it can apply the same principle before persistence: uncertain short fragments should inherit stable turn context or remain unknown, not create new visible turns.

AssemblyAI also removes a conservative set of filler words by default unless verbatim disfluencies are requested, and exposes sentence and paragraph results separately from the full text.

Sources:

- [AssemblyAI: Speaker Diarization](https://www.assemblyai.com/docs/pre-recorded-audio/label-speakers)
- [AssemblyAI: Streaming Diarization and Multichannel](https://www.assemblyai.com/docs/streaming/label-speakers-and-separate-channels)
- [AssemblyAI: Pre-recorded speech recognition](https://www.assemblyai.com/docs/pre-recorded-audio)

### OpenAI: diarized output is segment-first

OpenAI's `gpt-4o-transcribe-diarize` returns `diarized_json` as speaker-labelled segments with start, end, and text. For inputs longer than 30 seconds, chunking with automatic or configurable VAD is required. It can map up to four speakers from 2–10 second reference clips.

The API does not expose the diarized result as a word-row document. Its diarized model returns speaker segments, while word timestamp granularities are not available for that model. This is another segment-first design: the speaker-aware product unit is a completed segment.

Sources:

- [OpenAI: Speech-to-text and speaker diarization](https://developers.openai.com/api/docs/guides/speech-to-text)
- [OpenAI: GPT-4o Transcribe Diarize](https://developers.openai.com/api/docs/models/gpt-4o-transcribe-diarize)
- [OpenAI API: Create transcription](https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create)

### pyannote community-1: exclusive diarization exists to simplify reconciliation

The pyannote community-1 model card reports improved speaker assignment and counting over 3.1 and explicitly provides `exclusive_speaker_diarization`. Its stated purpose is to simplify reconciliation between fine-grained diarization timestamps and transcription timestamps that can be less precise.

It also accepts exact, minimum, and maximum speaker counts. This supports three principles:

- reconciliation is a separate algorithmic stage;
- speaker-count information is useful when trustworthy;
- an application should not expose every overlapping acoustic region directly as prose structure.

MacParakeet already uses FluidAudio's CoreML port of community-1 with WeSpeaker and VBx. Before replacing it, verify whether the FluidAudio result used by MacParakeet has equivalent exclusive/reconciled semantics and whether the app discards useful confidence or overlap information.

Source:

- [pyannote speaker-diarization-community-1 model card](https://huggingface.co/pyannote/speaker-diarization-community-1)

### WhisperX: sentence segmentation improves both subtitles and diarization

WhisperX combines VAD batching, forced word alignment, and pyannote diarization. Its project documentation says v3 moved to one transcript segment per sentence for better subtitling and better diarization.

That is directly relevant to MacParakeet: even when word timestamps exist, sentence or utterance units are better reconciliation and presentation boundaries.

Source:

- [WhisperX repository](https://github.com/m-bain/whisperX)

### NVIDIA Sortformer: useful for live diarization, not the first fix here

NVIDIA's streaming Sortformer keeps an arrival-order speaker cache and emits frame-level activity for up to four speakers in the reviewed model. This is useful for low-latency live attribution, but it does not solve MacParakeet's human-facing block assembly. A better frame model can still create an unreadable UI if every transition becomes a row.

Source:

- [NVIDIA Streaming Sortformer 4-speaker v2 model card](https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2)

### Product-level pattern

Public product documentation does not usually reveal reconciliation algorithms, so product claims must be treated more cautiously than API schemas or source code. The visible pattern is still useful:

- Meetily renders source/speaker turns as conversation bubbles and hides fine timestamp boundaries.
- MacWhisper advertises compact mode that hides timestamps, automatic filler removal, editable segments, and automatic speaker recognition.
- Descript presents the transcript as the primary editing surface and supports removing filler words from that document.

These products treat timestamps as controls or metadata. They do not make timestamp granularity the main reading hierarchy.

Sources:

- [`Meetily-ActuallyFree/frontend/src/components/VirtualizedTranscriptView.tsx`](../../../Meetily-ActuallyFree/frontend/src/components/VirtualizedTranscriptView.tsx)
- [MacWhisper official product page](https://goodsnooze.gumroad.com/l/macwhisper)
- [Descript Help Center](https://help.descript.com/)

## State-of-the-art architecture

A strong post-call pipeline has five distinct layers.

### Layer 1: preserve source and alignment evidence

Keep:

- microphone and system tracks;
- source alignment offsets;
- word timings;
- ASR confidence when meaningful;
- raw diarization regions;
- overlap regions;
- optional voice embeddings or known-speaker references.

Do not render this raw evidence directly.

When a platform can provide one participant per channel, channel identity is stronger than diarization. MacParakeet has only microphone versus aggregate system audio, so it can deterministically identify `Me`, but it must still diarize remote participants within the system track.

### Layer 2: form source-specific utterances

Build utterances independently inside microphone and system sources. Use a combination of:

- punctuation or sentence boundaries;
- silence gaps;
- maximum duration or word count;
- VAD boundaries;
- engine segment boundaries as weak hints.

Bias toward larger utterances. Do not split because a single word has a different tentative speaker label.

### Layer 3: reconcile speakers at utterance or sentence level

For each system utterance:

1. aggregate overlap duration for each diarization speaker;
2. choose a dominant speaker only when evidence is sufficient;
3. use neighboring utterances and continuity as a prior;
4. suppress isolated short speaker flips;
5. retain `Unknown` when evidence is weak rather than inventing a new identity;
6. represent real overlap separately;
7. apply exact/range speaker-count constraints when available.

Microphone identity remains `Me`. Acoustic echo is handled before or alongside this stage, not by remote-speaker clustering.

### Layer 4: assemble Reading Turns and paragraphs

Merge adjacent utterances when:

- speaker identity is the same;
- the gap is below a configurable reading threshold;
- no strong speaker change is present.

Within a long same-speaker turn, create paragraphs from:

- sentence count;
- word count;
- topic transition when an optional formatter can identify one safely;
- a long pause.

A paragraph split does not create a new speaker turn. A timestamp remains attached to the first word of each paragraph but is not required to be visible at all times.

### Layer 5: render a reading document

Default meeting UI:

```text
Speaker name                                      12:04
First paragraph of the speaker's turn. It contains complete
sentences and enough context to read naturally.

Second paragraph from the same long turn. It does not repeat
the speaker header unless needed for navigation.
```

Recommended presentation rules:

- one speaker header per Reading Turn;
- one quiet timestamp on the header or first paragraph;
- no timestamp chip per sentence;
- local-user alignment can differ, but left/right chat bubbles should be optional because they are less dense for hour-long meetings;
- show playback controls and timestamps on hover or focus;
- keep paragraph text continuously selectable;
- use compact overlap markers instead of alternating word rows.

## A conservative grouping policy for MacParakeet

The user's preference is to under-split rather than over-split. Encode that as product policy, not only tuning constants.

### Strong boundaries

Start a new Reading Turn only for:

- deterministic source change between microphone and system, unless both are active in a true overlap interval;
- remote speaker change supported by enough aggregate diarization evidence;
- an explicit manual correction.

### Weak boundaries

These can influence paragraphing but should not create a new speaker turn alone:

- punctuation;
- ASR segment boundary;
- short silence;
- one-word speaker change;
- diarization gap;
- low-confidence speaker assignment.

### Smoothing rules to prototype

Initial values are hypotheses and require fixture testing:

- Aggregate attribution over a sentence or source utterance, never one word.
- Do not let less than about 1 second of exclusive speech define a new remote speaker. AssemblyAI uses a similar `PENDING` rule for short streaming turns; Meetily requires 1.5 seconds before a fragment can define a cluster.
- If an isolated candidate speaker change is shorter than 3 words or 1 second and the stable speaker before and after is the same, absorb it into that stable speaker unless overlap evidence is strong.
- Let unattributed system words inherit the dominant speaker of their containing utterance. Do not surface `Others` as a separate identity between `Others 1` words.
- Merge adjacent same-speaker utterances across gaps up to roughly 2.5 seconds for reading. Meetily uses 2.5 seconds in its renderer.
- Split a long Reading Turn into a new paragraph after 2–4 complete sentences or about 60–100 words. Do not repeat the speaker header for a paragraph-only split.
- Keep short genuine backchannels as compact interjections, but do not let them divide the surrounding speaker's text into unrelated visual cards.

## Transcript cleanup and formatting in MacParakeet

The user's observation is substantially correct, with one implementation nuance.

### What currently happens

MacParakeet's deterministic dictation pipeline removes a narrow filler set, applies custom words/snippets, and cleans whitespace. The Text Processing subsystem explicitly says meetings reuse only custom-word correction for their timestamped evidence; it avoids applying dictation paste semantics to the meeting word model.

However, `TranscriptionService.completeTranscription` does route meetings through the general transcription refinement and optional AI formatter. The AI formatter prompt asks for punctuation, natural sentences, 1–3 sentence paragraphs, repeated-word cleanup, and filler cleanup.

There are two reasons this does not solve the reported meeting problem:

1. `AIFormatter.maxTranscriptionInputChars` is 20,000 characters. Long meetings skip the LLM formatter, specifically because hour-long meetings hit provider timeouts.
2. The cleaned text is a separate `cleanTranscript` string. The Timed speaker view continues to derive its structure from raw timestamped words. Formatting the full string does not repair word-level speaker turns or give cleaned paragraphs stable timing/speaker identity.

MacParakeet already has `TranscriptParagraphBuilder`, with 3 sentences, 80 words, and a 2.5-second pause as deterministic boundaries. It is used for meeting live preview and TXT/Markdown exports, but not as the primary transcript-detail reading model. It also currently splits on every non-nil word-level speaker change, so it must run **after** speaker smoothing, not before it.

Sources:

- [`Sources/MacParakeetCore/TextProcessing/README.md`](../../Sources/MacParakeetCore/TextProcessing/README.md)
- [`Sources/MacParakeetCore/TextProcessing/AIFormatter.swift`](../../Sources/MacParakeetCore/TextProcessing/AIFormatter.swift)
- [`Sources/MacParakeetCore/TextProcessing/TranscriptParagraphBuilder.swift`](../../Sources/MacParakeetCore/TextProcessing/TranscriptParagraphBuilder.swift)
- [`Sources/MacParakeetCore/Services/TranscriptionService.swift`](../../Sources/MacParakeetCore/Services/TranscriptionService.swift)
- [`Sources/MacParakeet/Views/Transcription/TranscriptResultView.swift`](../../Sources/MacParakeet/Views/Transcription/TranscriptResultView.swift)

### Recommended cleanup design

Preserve two products:

1. **Verbatim evidence** — original words, source, timings, confidence, and speaker evidence.
2. **Readable transcript** — derived Reading Turns and paragraphs.

Apply deterministic cleanup per Reading Turn:

- conservative filler removal;
- repeated adjacent word removal;
- whitespace and punctuation normalization;
- custom vocabulary correction;
- capitalization repair.

Make stronger rewriting optional. If an LLM formatter is enabled:

- format one stable Reading Turn or bounded group at a time;
- preserve the turn ID and speaker ID;
- require no summarization, omission, attribution changes, or invented content;
- retain the original turn text for revert and audit;
- validate entity, number, and content preservation;
- do not ask the LLM to decide speaker identity.

Chunking by Reading Turn removes the current 20,000-character whole-transcript limit without losing speaker structure. It also permits progressive formatting and bounded retries.

## What MacParakeet should copy from Meetily immediately

1. Source-specific utterance formation before speaker assignment.
2. Aggregate speaker overlap per utterance.
3. Exact speaker-count option, with Auto or range when uncertain.
4. Minimum reliable speech duration before a fragment defines a speaker.
5. Meaningful overlap labels instead of forced alternation.
6. Adjacent same-speaker turn merging.
7. A conversation/turn reading surface where timestamps are secondary.

These changes are sufficient to target Meetily-level usability without changing the diarization model.

## Extra improvements beyond Meetily

1. **Reading paragraphs inside long turns.** Meetily's bubbles can still become dense. MacParakeet can use its existing paragraph builder after stable turn assembly.
2. **Conservative uncertainty.** Use `Unknown` or contextual inheritance for weak short fragments instead of creating a speaker.
3. **Non-blocking speaker-count correction.** Show “Found 4 speakers · Correct…” after finalization rather than forcing a modal after every meeting.
4. **Block-aware cleanup.** Format bounded Reading Turns, not the entire transcript string.
5. **Optional known-speaker matching.** MacParakeet's planned local voiceprints can map stable remote clusters after diarization, while requiring confirmation.
6. **Separate overlap presentation.** Keep both speakers' words but render overlap as a compact nested interruption or paired block.
7. **Quality metrics aimed at readability.** DER alone is insufficient. Track visible fragmentation.

## Evaluation metrics

Use standard acoustic metrics where possible:

- diarization error rate;
- speaker confusion time;
- missed and false-alarm speech;
- speaker-count error.

Add product metrics that match the complaint:

- Reading Turns per minute;
- median words per Reading Turn;
- turns shorter than 3 words;
- isolated A/B/A speaker flips;
- fallback/unknown transitions;
- duplicate simultaneous mic/system phrase rate;
- paragraphs over 120 words;
- paragraphs under one complete sentence;
- manual corrections required per 10 minutes;
- time for a reviewer to find and understand a specific discussion.

Pre-commit to a readability bias:

> When acoustic evidence is ambiguous, preserve a larger existing Reading Turn. Do not create a new visible speaker block from one weak timestamp transition.

This policy should reduce fragmentation without falsifying the underlying evidence, because the raw word and diarization records remain available.

## Recommended plan

### Phase 0: fixtures and characterization

Create synthetic and consented real fixtures for:

- clean headset meeting;
- speaker-mode acoustic bleed;
- two remote speakers;
- three or more remote speakers;
- long monologue;
- rapid dialogue;
- short backchannels;
- true overlap;
- diarization gaps;
- isolated wrong word labels.

Capture current Reading Turns per minute and A/B/A flip counts.

### Phase 1: pure Reading Turn assembler

Add a pure, tested module that consumes source-aware words plus diarization regions and returns stable Reading Turns. Do not change persistence or UI first.

### Phase 2: transcript UI prototype

Compare three variants on identical noisy data:

- conversation bubbles;
- dense reading transcript;
- hybrid reading transcript with explicit overlap blocks.

The likely default is the dense reading transcript. It scales better to one-hour meetings while retaining Meetily's turn stability.

### Phase 3: use Reading Turns in production presentation

Use Reading Turns for:

- meeting transcript detail;
- plain-text reading paragraphs;
- speaker-aware Markdown/TXT;
- AI context formatting;
- search citations.

Keep subtitle exports on their own cue model.

### Phase 4: block-aware cleanup

Apply deterministic cleanup to every Reading Turn. Add optional bounded LLM formatting per turn with preservation validation and original-text fallback.

### Phase 5: attribution controls

Add non-blocking speaker-count correction and later confirmed voiceprint/name matching.

### Phase 6: acoustic bleed hardening

Evaluate MacParakeet's existing microphone/system duplicate reconciler separately. Improve delay search and fuzzy matching, or add real reference-based AEC, only with speaker-mode fixtures. Do not mix this work with headset-only turn assembly tests.

## Decision summary

- Keep fine timestamps as hidden evidence and playback metadata.
- Stop using fine timestamps as the reading structure.
- Keep FluidAudio community-1 for the first implementation.
- Introduce Reading Turns as the central meeting transcript abstraction.
- Prefer stable clumps over speculative splits.
- Split long same-speaker turns into readable paragraphs without inventing speaker changes.
- Preserve a verbatim layer and derive a readable layer.
- Format by stable block, not by one unbounded meeting string.

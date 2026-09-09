# Overlapping speech and Reading Turns

## Status and scope

Research and decisions from a user-led design session. The product decisions below are agreed; implementation has not been authorized. Final meeting transcripts and imported recordings are in scope as one deliverable; live preview is deferred. No private audio or transcripts were read or sent to external services. No tests were run: this is source research, not a reproduced recording-level diagnosis.

## Consolidated design agreement

This section is authoritative over earlier proposals and the chronological discussion below.

1. Identify clearly bounded Speech Blocks using source/speaker-local audio activity and speaker evidence. Do not require perfect linguistic segmentation, semantic completion detection, or general noisy-room speech separation. Do not use paragraph word counts, sentence counts, or a universal pause duration as the definition of a contribution.
2. Preserve all recognized words and their speaker-local order. Genuine short replies, including consecutive one-word exchanges, are valid. The prohibited behavior is mutual fragmentation of coherent contributions into alternating tiny turns.
3. Insert a clearly contained block whole near its start, splitting the surrounding block once. If that start falls inside a surrounding word, insert after that word; otherwise use the nearest inter-word boundary. Resume the surrounding block from that split, including words spoken during the insertion.
4. Place crossing blocks sequentially by start time, without splitting them against each other. Apply containment recursively and preserve crossing chains sequentially inside a surrounding block. Do not silently add a postponement cap that changes the agreed chain behavior.
5. Nearly shared boundaries and uncertain containment use sequential start order rather than forced insertion or word-by-word interleaving. Acoustic boundary uncertainty and source synchronization error remain distinct; do not infer clock correction from overlap alone.
6. Use one-column reading order. No parallel layout or simultaneous-speech grouping UI.
7. Establish and save authoritative ordered Reading Turns upstream. All readable consumers must use the saved structure rather than independently reconstructing it. Preserve original timed evidence and exact word references separately for playback and evidence-focused outputs.
8. Apply the policy to new transcriptions and explicit reprocessing. Do not silently rewrite old saved transcripts or overwrite user edits. An additional rebuild UI is not separately approved.
9. When required word timing is unavailable, preserve the plain-text result without inventing timing or speaker structure. This is an evidence-dependent fallback within the complete scope, not a separate deliverable. No additional alignment step is required by the agreement.
10. Reuse existing local activity detection where sufficient. An additional small local model is permitted if a need is established, but is not a prerequisite. Do not inherit recognition-window padding, forced maximum-duration splits, or short-speech filtering as conversational rules.

Engineering work still needs to specify acoustic evidence extraction and calibration, exact persistence/schema and consumer changes, deterministic ordering details, and failure handling. The user rejected selecting universal timing constants through a hand-written transcript-example exercise. Research findings do not establish measured quality on actual recordings.

## User requirements

- Do not interleave overlapping contributions word by word into tiny turns.
- Keep short questions and replies near the speech they interrupt, not after minutes of later speech.
- Preserve genuine short replies, including a single word.
- Consider near-boundary timing errors, interjections, simultaneous starts, and sustained simultaneous speech separately.
- Start with microphone versus system audio, but investigate the limits of same-track speech and imported recordings.

The statement that consecutive one-word turns are never acceptable needs qualification: genuine exchanges such as “Ready?” / “Yes.” / “Go.” must not be mistaken for fragmentation.

## Current implementation: verified source facts

Paths below are relative to the repository root, inspected at HEAD `68aeb042`.

1. `Sources/MacParakeetCore/Services/MeetingRecording/MeetingTranscriptFinalizer.swift`, `finalize`: shifts each source's words by `startOffsetMs`, performs source reconciliation, applies source-specific speaker attribution, then sorts the combined words by start time. The pipeline already has source-offset handling; a residual synchronization defect is not established by this inspection.
2. `Sources/MacParakeetCore/Services/MeetingRecording/MeetingRecordingMetadata.swift`, `MeetingSourceAlignment.startOffsetMs`: calculates offsets from source and meeting timeline origins. This does not establish how accurately a particular recording or ASR output is aligned.
3. `Sources/MacParakeetCore/TextProcessing/MeetingTranscriptPresentationBuilder.swift`, `build` and `makeTurns`: forms source-local utterances, uses aggregate speaker evidence, smooths weak isolated speaker changes, and merges adjacent utterances. Sentence endings and 2.5-second pauses are among the boundary signals. Sentence utterances can merge again.
4. The same file's `chronologicalTurns` then sorts all words by start time and starts a new Reading Turn whenever the originating assembled turn changes. Thus alternating starts from two otherwise coherent source turns directly produce alternating reading fragments. This is a source-level mechanism, not proof that track offset caused a user's recording to reach it.
5. `Sources/MacParakeetCore/TextProcessing/MeetingTranscriptDisplayBuilder.swift` only merges consecutive turns with the same source and speaker. It cannot repair alternating-source fragmentation.
6. `Sources/MacParakeetCore/Services/Diarization/SpeakerMerger.swift` assigns a word to the diarization segment with the greatest intersection. `Services/Diarization/DiarizationService.swift` uses FluidAudio's offline diarizer. Speaker assignment and readable ordering are separate concerns.
7. `Sources/MacParakeetCore/Services/TranscriptionService.swift`, the file transcription path around `diarizationRequested`: recognizes the file, then attributes the recognized words using diarization segments. This path does not recover a second transcript merely by identifying a second simultaneous speaker.
8. `Sources/MacParakeetCore/TextProcessing/README.md`: readable meeting output and evidence-focused JSON/subtitles have distinct contracts. AI formatting does not own turn structure. A policy change must account for all consumers, not just visual grouping.

## Removed behavior

Commit `4946bca254fd70c7969f938b19776bf8f6380060`, “Remove simultaneous-speech grouping from meeting transcripts (#57)”, names the rejected feature and describes displaced questions.

Its parent implementation sorted assembled source turns by their start time and marked overlap groups. A long source turn therefore appeared before a short contribution inside it. A separate `mergeAroundOverlappingInterjections` function joined the surrounding speaker's words and appended interjections afterward. `markOverlaps` used connected groups of overlapping turns; connected overlap alone is not a safe bound on conversational grouping.

The replacement introduced global word ordering. The old policy preserves too much speaker continuity; the current policy gives individual word starts too much authority over reading boundaries.

`Tests/MacParakeetTests/TextProcessing/MeetingChronologicalSpeechTests.swift` protects interjection placement, five-minute continuations, ties, and stale formatting. Its smallest saved-meeting example explicitly expects three one-word turns. Future acceptance tests must distinguish meaningful short contributions from fragments; a blanket word-count rule conflicts with this distinction.

## External primary sources

### Separate channels keep simultaneous evidence

[Amazon Transcribe: multi-channel audio](https://docs.aws.amazon.com/transcribe/latest/dg/channel-id.html) documents independent channel transcripts and explicitly overlapping timestamps when speakers overlap. This supports keeping parallel source evidence rather than forcing a false exclusive timeline. It does not specify the readable insertion policy we need. This is a reference, not a recommendation to send audio to AWS.

### Exclusive diarization solves a different problem

[pyannote Community-1 announcement](https://www.pyannote.ai/blog/community-1) explains exclusive diarization: one active speaker, chosen as most likely to be transcribed, to simplify reconciliation with imprecise ASR timestamps. The [model card](https://huggingface.co/pyannote-community/speaker-diarization-community-1) says regular and exclusive diarization are both returned.

Implication: useful for attributing a single recognized text stream, but not a policy for preserving both independently recognized microphone and system contributions. It cannot recover missing words from mixed audio.

### Maximum-overlap attribution is not readable turn assembly

[WhisperX source, `assign_word_speakers`](https://raw.githubusercontent.com/m-bain/whisperX/main/whisperx/diarize.py) sums intersections by speaker for segments and words and assigns the largest. It can optionally use the nearest segment. The inspected function supplies attribution, not a solution to bounded interruption placement. The URL tracks upstream main and can change.

### Mixed audio can require speech separation

[Microsoft Research: low-latency continuous speech separation](https://www.microsoft.com/en-us/research/publication/low-latency-speaker-independent-continuous-speech-separation/) describes converting mixed speech into separate overlap-free signals while keeping each utterance on one output channel. Recognition follows separation.

Their [meeting transcription paper](https://www.microsoft.com/en-us/research/wp-content/uploads/2019/12/ASRU2019-camera-ready.pdf) describes separate–recognize–diarize, then merging speaker-attributed outputs. This establishes an upstream technique for mixed-speaker recognition, not an off-the-shelf local Mac solution or a proven reading-order rule. Runtime, models, licensing, and Mac feasibility remain unexamined.

### A single column is not the only faithful representation

[ELAN: time-aligned interlinear text](https://www.mpi.nl/tools/elan/docs/manual/Sec_Exporting_time_aligned_interlinear_text.html) aligns annotations across tiers and can export overlapping annotations relative to a reference tier. It demonstrates a representation of parallel speech without pretending every word has a single conversational order. Its exact fixed-width export is not recommended for MacParakeet; the manual warns that the layout can cut annotation text.

## Candidate direction — proposal, not a sourced algorithm

Separate the evidence timeline from the reading order. Preserve coherent speaker contributions within a bounded local region. Insert a short contribution once near its onset, splitting the surrounding speaker locally instead of alternating words or delaying the contribution to the end of a long speech.

This is incomplete until we decide:

- Which boundaries are preferred: pause, clause, sentence, or nearby word boundary?
- How much local displacement is acceptable, and what happens when no good boundary exists?
- How do two long simultaneous contributions appear without recreating minutes-long postponement?
- Should simultaneous content be marked or use parallel display?
- What evidence distinguishes a genuine short reply from a fragmentation artifact?
- Which consumers share reading order, and how does playback behave when consecutive reading turns have overlapping time ranges?

Do not infer a track correction merely because two people appear to overlap. Capture alignment, ASR word alignment, diarization boundaries, echo leakage, and genuine overlap require different evidence.

## Agreed behavior — round 1

- Reading order may differ locally from word timestamp order. Prefer anchoring to the start of a block; the precise anchor still needs definition.
- Preserve genuine consecutive one-word exchanges. Prevent artificial fragmentation of coherent speech instead of imposing a minimum word count.
- Break at blocks and blank space, not into tiny alternating fragments. What establishes a block or blank space is still open.
- Always use one column. Two legitimate 20-second overlapping contributions appear as two intact, sequential chunks, not a parallel layout.
- Do not split the work into separate deliverables for cross-track and same-track speech. Both remain in the design scope, along with imported recordings. Their different evidence and recognition limits still need investigation.

These decisions supersede the proposed parallel-display option and staged acceptance target above. No implementation is approved.

## Agreed behavior — round 2

- Audible pauses and paragraph boundaries establish speech blocks. Boundary detection details remain open.
- Blocks are not universally indivisible. For a contained shorter block, split the surrounding longer block once at the insertion point and keep the shorter block whole.
- Example: A 30–80 seconds, B 45–50 seconds → A prefix to around 45, all of B, A remainder. A need not have a natural boundary near 45.
- Example: A 30–60 seconds, B 55–80 seconds → all of A, then all of B. Crossing overlaps are sequential, not mutually fragmented.
- The prohibited behavior is splitting both overlapping blocks into alternating fragments, not splitting any block at all.
- Primary and secondary roles describe the surrounding and inserted contributions in the contained case; whether these roles have any broader meaning is not yet settled.

This refines round 1's intact-block language. A blanket rule that an interjection cannot split a block is rejected. The user describes the policy as inserting a smaller block into a bigger block, or placing crossing blocks sequentially. Equal boundaries, timing tolerance, multiple overlaps, and paragraph-boundary detection remain open.

## Agreed behavior — round 3

- After inserting B at approximately its start, resume A from the same split point. Preserve A's words spoken during B; do not skip to B's end.
- Treat nearly shared starts or ends as boundary overlaps and show the blocks sequentially by start time. Insert only when containment is clear. Timing tolerance remains to be established from examples and audio.
- For A 30–100, B 45–60, C 55–70: render A prefix near 45, all B, all C, then A remainder. B and C cross each other and remain intact inside the surrounding A block.

## Agreed behavior — round 4

- Establish source/speaker-local speech blocks before ordering contributions across speakers. Screen wrapping and paragraphs generated after interleaving must not define blocks. Compare candidate pause/paragraph rules on examples before retaining current thresholds.
- Apply containment recursively: A 0–100, B 20–60, C 30–35 → A prefix, B prefix, all C, B remainder, A remainder.
- Extend sequential ordering through crossing chains: A 0–120, B 20–40, C 35–55, D 50–70 → A prefix, all B, all C, all D, A remainder. The user agreed to this order, including postponement of A's concurrent words. No extra maximum-postponement limit was selected; the earlier proposed hard bound must not silently override this rule.

## Agreed behavior — round 5

- If B starts during A's word, keep that word intact and insert B immediately afterward. Otherwise split between A's words nearest B's start. Do not move the insertion to a distant sentence boundary.
- Establish and save reading order upstream so all transcript consumers use it. The UI must not enforce or repair this order. The existing presentation-only architecture is not the approved location for the new policy.
- The user rejected a hand-written before/after transcript-example exercise for selecting pause and paragraph thresholds. Research natural speech variability and boundary detection instead. No fixed duration or count rule is approved.

## Agreed behavior — final product questions

- Uncertain containment falls back to sequential block ordering by start time, never alternating words.
- No automatic restructuring of existing saved transcripts. Use new transcription or explicit reprocessing; preserve user edits.
- Untimed engine output retains its plain-text result. Do not invent word alignment or speaker structure. No additional alignment step was selected.

## Scope clarification — after boundary research

- An additional small on-device model is acceptable if needed; adopting one is not required or approved.
- Perfect linguistic or paragraph segmentation is not required. The user emphasizes that an interjecting block or a crossing block usually has real empty space on both sides in its own source/speaker activity.
- Use these clear activity boundaries and the agreed contained/crossing rules as the main approach. Do not make general semantic completion or paragraph detection a prerequisite.
- Robust separation of many simultaneous voices in a noisy room is not the requested problem. This limits the acoustic difficulty we must solve; it does not split the work into separate deliverables or remove imported recordings from scope.
- Next investigation should focus on how the existing audio activity and speaker evidence can identify these bounded contributions, including which gaps survive current processing. Only add a model if that investigation establishes a need.

This clarification narrows the recommended direction below. The literature remains background evidence, not a mandate to build a general linguistic-boundary detector.

## Follow-up: existing activity evidence and upstream storage

Source inspection after the scope clarification found:

- FluidAudio `VAD/VadManager.swift` exposes speech probabilities in 4096-sample frames at 16 kHz (256 ms). This supplies actual audio activity but not sample-accurate speech boundaries. Word alignment can help locate text around a boundary; probability confidence alone does not correct source clocks.
- `Services/MeetingRecording/MeetingVADService.swift` currently exposes live start/end events, not probabilities; its speech-start event discards the position. It applies a 0.5-second silence confirmation and 0.15-second padding. Reusing those live events as final Speech Blocks would inherit information loss and live-specific policy.
- FluidAudio `VAD/VadManager+SpeechSegmentation.swift` accepts precomputed probabilities, but its default config (`VadTypes.swift`) has minimum silence 0.75 seconds, maximum speech 14 seconds, minimum speech 0.15 seconds, and padding. The helper can force duration-based splits and discard short activity. These defaults are ASR segmentation settings, not approved Speech Block rules. Padding is for retaining audio around recognition windows and must not establish conversational overlap.
- FluidAudio `Diarizer/Offline/Utils/OfflineReconstruction.swift` merges adjacent same-speaker segments within the configured gap, filters by minimum duration, then optionally trims overlaps. Thus the current returned regions are post-processed activity evidence, not untouched speaker activity.
- `Services/TranscriptionService.swift`, `transcribeMeetingSources`, already retains the converted per-source WAV URLs through finalization, using the selected cleaned/raw microphone source consistently with recognition. An offline activity pass can use these same files and source offsets without replaying live capture. No new analysis pass has been implemented or benchmarked.
- The same service already persists meeting `transcriptSegments`, but `CompletedMeetingReadingDocument.build` in `TextProcessing/MeetingTranscriptDocumentRenderer.swift` rebuilds Reading Turns from words and diarization on read. Merely saving different segments will not make that structure authoritative for these consumers.
- Persisted `TranscriptSegmentRecord.wordRange` is one contiguous interval. `materializeMeetingSegments` takes minimum/maximum word references. Under block ordering, a block may refer to noncontiguous entries of the timestamp-ordered evidence array; the interval would include the other speaker's intervening words. The storage design therefore needs exact references (or an equivalent explicit mapping), not a naive reuse of enclosing index ranges. This is a requirement of the proposed change, not a claim of a newly reproduced bug.

Proposed implementation direction, awaiting remaining product decisions: use existing local audio activity and speaker evidence to establish clear blocks; apply the agreed contained/crossing ordering; save authoritative ordered turns with exact word references while preserving the original timed evidence. Do not require an additional completion model, inherit VAD maximum-duration cuts, or solve arbitrary noisy-room separation.

Open product decisions include uncertain block boundaries, existing saved/edited transcripts, and missing timing/audio. Numerical acoustic detection/calibration choices remain engineering research, not questions asking the user to select a universal pause duration.

## Boundary-detection research

### Research question

How can we find coherent Speech Blocks across different speaking styles, languages, and input sources without treating a fixed silence duration or paragraph word count as conversational truth?

This is distinct from the now-agreed contained/crossing ordering policy. It is also distinct from voice activity detection (speech present), speaker attribution (who spoke), and endpointing (when an agent should respond).

### Primary-source findings

**1. Pause-only segmentation misses useful evidence, even in real meetings.**

[Kolar, Shriberg, Liu: speaker-specific prosodic models for dialog-act segmentation](https://www.isca-archive.org/interspeech_2006/kolar06_interspeech.pdf) studied the ICSI Meeting Corpus. A richer prosodic feature set significantly improved boundary detection for 19 of 20 speakers compared with pause-only features. Features included normalized word/phone durations, pauses, pitch changes, and energy. Speaker-specific adaptation helped some speakers, not all.

Limits: this study used forced alignment of human transcripts and close-talking microphones, not noisy ASR output on a mixed system track. It supports combining evidence, not a universal accuracy guarantee or training a separate model for every attendee.

**2. Pauses can signal hesitation, not a finished unit.**

[Nielsen, Steedman, Goldwater: prosodic segmentation for parsing spoken dialogue](https://aclanthology.org/anthology-files/anthology-files/pdf/acl/2021.acl-long.79v1.pdf) describes confusion between sentence-unit boundaries and disfluency interruption points in pause-only models. Their [2023 follow-up](https://www.isca-archive.org/interspeech_2023/nielsen23_interspeech.pdf) combines text with pause duration, normalized word duration, pitch, and intensity, reporting improved sentence-unit segmentation on Switchboard.

Limits: sentence-like units are not automatically our Speech Blocks or paragraphs. These studies use annotated transcripts/timing; ASR errors and mixed-speaker acoustics remain transfer risks. Offline processing can use speech after a candidate boundary as well as before it; this is an opportunity, not a tested MacParakeet result.

**3. Speaking-rate changes offer a lighter, partly adaptive method, but not a threshold-free one.**

[Biron et al.: automatic prosodic-boundary detection in spontaneous speech](https://doi.org/10.1371/journal.pone.0250969) detects final lengthening followed by acceleration, plus silence. It uses relative within-turn rate changes and forced-aligned phone durations. The paper also uses fixed heuristics, including a 300 ms pause rule; replacing our 2.5 seconds with that value would miss the point.

Important mismatch: its intonation units are often only a few words, and single-unit turns were excluded from its boundary-detection procedure. Using every detected intonation boundary as a Speech Block could recreate excessive fragmentation. Our current word timestamps do not supply the phone durations used by this method.

**4. Speaker-normalized pause evidence has precedent across languages.**

[Akita et al.: spontaneous Japanese sentence-boundary detection](https://www.isca-archive.org/interspeech_2006/akita06_interspeech.pdf) combines lexical and pause information and normalizes pause durations by the average in a talk, explicitly noting speaking-rate and speaker variation. [The ICSI+ multilingual system](https://www.isca-archive.org/interspeech_2006/zimmerman06_interspeech.pdf) combines lexical, prosodic, speaker-change, and syntactic features for English and Mandarin broadcast news.

Limits: neither is a ready multilingual meeting-block model. Normalization reduces one source of variation; it does not make a pause unambiguous or prove one rule works across all languages.

**5. Small local learned completion models are practical candidates, not direct solutions.**

[Smart Turn v3.2 source README](https://raw.githubusercontent.com/pipecat-ai/smart-turn/main/README.md) documents 23 languages, 16 kHz mono input, up to eight seconds of preceding audio, and an 8 MB quantized ONNX model. The [model card](https://huggingface.co/pipecat-ai/smart-turn-v3/raw/main/README.md) lists an approximately 8M-parameter Whisper Tiny encoder plus classifier and BSD-2-Clause licensing. Its intended task is deciding whether a voice agent should respond. It normally runs after VAD finds silence and warns against very short inputs.

Implication: it can supply evidence that a pause is hesitation rather than completion. It does not directly find paragraphs, identify internal boundaries in uninterrupted speech, assign overlapping speakers, or implement our ordering rules. CPU speed figures are publisher claims on other setups, not measurements on this Mac. Swift/CoreML or ONNX integration has not been verified.

[LiveKit's official turn-detector documentation](https://docs.livekit.io/agents/logic/turns/turn-detector/) also combines acoustic/semantic completion detection with VAD. It documents local and hosted models and language-specific confidence thresholds, and a text-model endpointing mode that adapts delays to session pause statistics. This illustrates adaptive, multi-signal decisions; copying endpointing delays into offline paragraph formation would be a task mismatch. No hosted service is proposed for MacParakeet.

These upstream pages track changing releases; facts above refer to the retrieved versions.

### Signals actually available in this checkout

The resolved FluidAudio revision is `4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b` (`Package.resolved`, confirmed against `.build/checkouts/FluidAudio`).

- `Sources/MacParakeetCore/STT/STTResult.swift`: carries text, word times/confidence, language, and engine metadata. There are no structured paragraph boundaries, speech-activity probabilities, pitch contours, phone alignments, or boundary-confidence fields in this shared result.
- `STT/STTWordTimingBuilder.swift`: joins token pieces into words and retains word starts/ends and averaged token confidence. Whitespace is trimmed; structured paragraph information is not exposed here. ASR token confidence is not boundary confidence.
- `STT/WhisperEngine.swift`, `makeResult`: keeps merged text and `allWords`, not the engine's structured segment list. Engine segments would still need validation before treating them as conversational blocks.
- `STT/CohereTranscribeEngine.swift`: returns an empty word list. An audio boundary detector alone cannot place those untimed words into overlapping speaker blocks. This is a missing-evidence constraint within the same deliverable, not a proposed separate target.
- `Models/Transcription.swift`: persisted words and diarization regions contain timings and speaker IDs, but not the acoustic or learned boundary evidence described above.
- FluidAudio `VAD/VadTypes.swift`: exposes speech probability through `VadResult`. Its ready-made `VadSegmentationConfig` also includes minimum silence/speech durations. Calling `segmentSpeech` unchanged would replace one fixed silence policy with another, not solve semantic segmentation.
- FluidAudio `Diarizer/Offline/Core/OfflineDiarizerTypes.swift`: the default post-processing has `exclusiveSegments = true` and a 0.1-second minimum gap. `OfflineReconstruction.swift`, `sanitize`/`excludeOverlaps`, trims later overlapping segments and can drop fully covered ones. MacParakeet's `DiarizationService` uses the defaults, including when applying speaker-count constraints; no application override of `exclusiveSegments` was found. Thus current same-track diarization output must not be assumed to retain all overlap evidence. This is a verified configuration fact, not a diagnosis of a particular recording, and does not explain independent microphone/system overlap by itself.

### Assessment of candidate approaches

| Approach | Useful evidence | Main limitation |
|---|---|---|
| Fixed pause or word-count rules | Cheap, deterministic | Confuses pace/hesitation with completed contributions; count limits are layout choices |
| Adaptive pause statistics | Accounts for some speaker/rate variation | Still cannot distinguish hesitation from completion by duration alone; unstable with little speech |
| Text/punctuation-only boundaries | Linguistic completion and topic structure | ASR punctuation is inferred; loses audible intent and can reflect recognition chunks |
| Prosodic features plus text | Direct research support for complementary signals | Needs reliable alignment/audio features, calibration, language coverage, and a suitable target unit |
| Small audio completion model plus VAD | Existing local models distinguish some incomplete pauses | Endpoint completion differs from paragraph/block detection; mixed speech and short replies need care |
| General LLM paragraph generation | Potential text-level coherence | Can rewrite/drop text; default cloud/opt-in constraints; no acoustic evidence in text-only input |

No source establishes an off-the-shelf detector for exactly our Speech Block definition. A classifier still has learned or calibrated decision boundaries; the goal is not zero thresholds, but avoiding one fixed silence duration as the sole meaning of a boundary.

### Recommended direction for further design, not an approved algorithm

Use source/speaker-local audio activity to propose possible boundaries. Combine pause evidence relative to local pace, reliable speaker changes, acoustic completion cues, and text continuity to decide which boundaries should form Speech Blocks. Keep phrase-level and paragraph-level evidence distinct; neither every breath nor every ASR period should automatically create a block. Offline analysis can inspect both sides of a pause.

Save the resulting ordered transcript upstream, applying the agreed contained/crossing policy. Preserve timed source evidence separately. The data contract and treatment of existing saved transcripts remain undecided; do not simply sort the canonical word array into reading order and assume timing-based consumers will still work.

Prefer researching an existing small local boundary/completion model and its target mismatch before inventing a collection of hand-tuned timing rules. Retained audio is available during new finalization; old transcripts without audio cannot supply missing prosody. No models have been downloaded or benchmarked, no private recording has been opened, and no transcript-example exercise is planned.

Open research: local model integration, whether a suitable model can distinguish block completion from phrase breaks, handling same-track mixtures without assigning mixed pitch to one speaker, supported-language coverage, boundary uncertainty versus clock/alignment error, and fallback behavior when word timing or audio is absent. The user must approve trade-offs; research must not turn implementation guesses into product rules.

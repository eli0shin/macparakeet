# Upstream diarization evaluation for the fork

Date: 2026-09-08

## Question

Did upstream MacParakeet find a diarization improvement that the fork should adopt?

## Verdict

**Partly, but it is not a proven unlock yet.** The largest upstream fix was the move from FluidAudio 0.15.4 to 0.15.6. The fork already pins the exact same 0.15.6 revision (`4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b`), so it already receives FluidAudio's corrected clustering threshold semantics, deterministic K-Means fallback, corrected constraint count, and constrained co-chunk assignment.

The fork does not have upstream's application-level configuration and model-loading changes:

1. `segmentation.stepRatio = 0.1` instead of 0.2.
2. `embedding.minSegmentDurationSeconds = 0` instead of 1.0.
3. `zeroVoteReembed.enabled = true` instead of false.
4. One shared immutable model load for constrained and unconstrained runs, with cancellation-responsive waiters, retry after failed preparation, and narrow PLDA metadata repair.
5. A calendar-attendee-derived cap for the meeting system track.

The first three can improve missed/incorrect short turns, but upstream's own evidence also shows more false alarm, more segments, and over-splitting. The fork's Reading Turn layer can absorb some short label jitter, but it cannot make a false global speaker cluster disappear. The correct next step is an isolated A/B on fork behavior, not a direct cherry-pick of PR #974.

## What the fork already gets from FluidAudio 0.15.6

FluidAudio 0.15.6 contains the important library-level corrections from PR #802 and related releases:

- The AHC threshold is now used as a Euclidean cut distance directly. FluidAudio 0.15.4 incorrectly treated it as cosine similarity and converted 0.6 to approximately 0.894.
- Speaker constraints are compared with clusters that actually receive assignments, not the AHC warm-start count.
- Co-chunk local speakers use constrained assignment by default, which prevents two simultaneous local speaker slots from independently collapsing onto the same global cluster.
- Count-forced K-Means uses ten deterministic initializations with base seed zero instead of one random initialization.
- Zero-vote span re-embedding exists as an opt-in configuration.

These behaviors live inside the dependency. Because `Package.swift` and `Package.resolved` already select 0.15.6 at the exact revision above, no upstream MacParakeet code is needed to obtain the first four fixes.

Sources:

- Fork [`Package.swift`](../../Package.swift)
- FluidAudio [v0.15.6 release](https://github.com/FluidInference/FluidAudio/releases/tag/v0.15.6)
- FluidAudio [PR #802](https://github.com/FluidInference/FluidAudio/pull/802)
- FluidAudio [`OfflineDiarizerTypes.swift` at v0.15.6](https://github.com/FluidInference/FluidAudio/blob/v0.15.6/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerTypes.swift)
- FluidAudio [`VBxClustering.swift` at v0.15.6](https://github.com/FluidInference/FluidAudio/blob/v0.15.6/Sources/FluidAudio/Diarizer/Offline/Clustering/VBxClustering.swift)

## The real quality delta

The fork currently creates `OfflineDiarizerManager` from `OfflineDiarizerConfig.default` and applies only an optional exact/range speaker constraint. FluidAudio 0.15.6 defaults remain optimized for speed:

| Setting | Fork/default | Upstream MacParakeet |
|---|---:|---:|
| Segmentation step ratio | 0.2, 2-second hop over a 10-second window | 0.1, 1-second hop |
| Minimum embedding segment | 1.0 seconds | 0 seconds |
| Zero-vote re-embed | Disabled | Enabled, 0.4-second minimum |
| Constrained assignment | Enabled by FluidAudio 0.15.6 | Enabled by FluidAudio 0.15.6 |
| Clustering threshold | 0.6 distance | Same 0.6 distance |

Fork source: [`DiarizationService.swift`](../../Sources/MacParakeetCore/Services/Diarization/DiarizationService.swift).

Upstream source: [`DiarizationService.swift` at `a82ae130`](https://github.com/moona3k/macparakeet/blob/a82ae130a20636dc318cecd5c36ba8402190cb2f/Sources/MacParakeetCore/Services/Diarization/DiarizationService.swift).

### Published FluidAudio comparison

FluidAudio reports this full VoxConverse comparison, with collar 0.25 seconds and overlap ignored:

| Configuration | Average DER | Median DER | Average JER | Throughput |
|---|---:|---:|---:|---:|
| Step 0.2, minimum 1.0 | 15.07% | 10.70% | 39.40% | 122.06x |
| Step 0.1, minimum 0 | 13.89% | 10.49% | 42.84% | 64.75x |

This is a **1.18-point average DER improvement**, but average JER becomes **3.44 points worse** and throughput is about halved. The benchmark predates or does not clearly isolate every 0.15.6 correction, and it does not isolate step ratio from minimum duration.

Source: FluidAudio [`Documentation/Benchmarks.md` at v0.15.6](https://github.com/FluidInference/FluidAudio/blob/v0.15.6/Documentation/Benchmarks.md#offline-diarization-pipeline).

### Upstream MacParakeet comparison

[Upstream PR #974](https://github.com/moona3k/macparakeet/pull/974) compared old 0.15.4/default against new 0.15.6/high-accuracy. It therefore cannot separate the dependency upgrade from configuration changes. On one 21-minute AMI training-set meeting with four reference speakers:

- DER improved from 17.18% to 16.50%: 0.68 points.
- Speaker confusion improved from 2.65% to 1.19%.
- Miss improved from 2.98% to 1.74%.
- False alarm worsened from 11.54% to 13.58%.
- Detected speakers changed from 3 to 5 when truth was 4.
- Raw segments increased from 119 to 300.
- Words labeled increased from 93.4% to 96.1%, but ASR word counts differed between arms.
- Runtime was variable, and the high-accuracy path could take approximately twice as long.

On one retained upstream meeting without ground truth, speakers increased from 3 to 5 and segments from 15 to 179. That result proves the new settings preserve much more short-turn evidence; it does not prove those extra turns or clusters are correct.

Upstream's strongest measured gain from the dependency upgrade was determinism under a count constraint: the old 0.15.4 constrained path produced materially different results between runs, while 0.15.6 was stable. The fork already gets that behavior from its 0.15.6 dependency.

## Interaction with fork-specific diarization

The fork is not the baseline evaluated by upstream research. Since divergence it added:

- Reading Turns with utterance-level aggregate speaker evidence.
- Absorption of unsupported sub-second speaker runs when the same speaker surrounds them.
- Preservation of supported overlapping interjections.
- Non-blocking Auto/exact/bounded speaker-count correction against retained audio.
- Independent optional microphone-track diarization with `microphone:<id>` identities.
- Speaker rename persistence and derived-artifact refresh.

Sources:

- [`MeetingTranscriptPresentationBuilder.swift`](../../Sources/MacParakeetCore/TextProcessing/MeetingTranscriptPresentationBuilder.swift)
- [`TextProcessing/README.md`](../../Sources/MacParakeetCore/TextProcessing/README.md)
- [`MeetingSpeakerCountCorrection.swift`](../../Sources/MacParakeetCore/Services/MeetingRecording/MeetingSpeakerCountCorrection.swift)
- [`ADR-010`](../../spec/adr/010-speaker-diarization.md)

These features change the expected outcome:

- More short, correct diarization regions can improve Reading Turn assignment and preserve real interjections.
- More short, incorrect regions can be absorbed by the fork's utterance policy, reducing visible jitter.
- Extra false global clusters remain harmful. Reading Turn grouping does not merge two different speaker identities globally.
- The risk applies to both system and microphone tracks because the fork can diarize each independently.
- A count-correction rerun currently constructs and prepares another constrained manager. Upstream's shared-model factory is especially relevant to the fork because repeated Adjust Speakers operations should not repeat model preparation or prewarming.

## Component assessment

### 1. FluidAudio 0.15.6 clustering fixes — already adopted

**Decision:** No work. Preserve the exact pin and add a regression check only if current tests do not prove deterministic constrained runs.

### 2. High-accuracy configuration — benchmark before adoption

**Decision:** Promising but not ready to enable globally.

Do not evaluate it as one opaque preset. Use separate arms:

1. Current 0.15.6 defaults.
2. Step ratio 0.1 only.
3. Step ratio 0.1 plus zero-vote re-embed.
4. Step ratio 0.1 plus minimum segment 0.
5. Full upstream preset: step ratio 0.1, minimum 0, zero-vote re-embed.

This isolates which setting improves attribution and which causes fragmentation/false alarms. The upstream preset bundles three mechanisms with different risk profiles.

### 3. Zero-vote re-embedding — strongest isolated quality candidate

**Decision:** Test early.

Without this pass, a speech-active span that has no cluster votes is assigned through a cluster-zero tie-break. Re-embedding the exact span and selecting the nearest existing centroid is mechanically better than arbitrary cluster zero. It does not create a new global cluster, so its over-splitting risk is lower than dropping the minimum segment duration. FluidAudio leaves it disabled by default, and no isolated corpus result was found, so it still needs measurement.

### 4. Shared immutable model loading — adopt independently of quality settings

**Decision:** Worth porting, with adaptation.

The fork's constrained path creates an `OfflineDiarizerManager` and calls `prepareModels` for each constrained run. Upstream loads `OfflineDiarizerModels` once, then creates cheap per-request managers initialized from shared immutable models. It also:

- does not hold the macOS 14 inference gate during download/load;
- avoids eager inference prewarming;
- lets a cancelled waiter stop waiting without cancelling a shared load;
- retries after failed preparation;
- keeps separate request constraints;
- repairs only malformed PLDA metadata and preserves the remaining cache.

This improves Adjust Speakers and microphone/system reruns even if the fork retains default quality settings. Port the design into the fork's current per-track correction API; do not copy upstream's older system-only meeting finalizer.

### 5. Calendar attendee cap — low confidence for the fork

**Decision:** Defer until measured.

Upstream maps 1–8 countable remote attendees to a loose `min = 1, max = n + 1` bound. It excludes known declined/resource/group entries and leaves large or missing counts unconstrained. This can cap over-splitting but calendar attendance is not actual attendance. The fork already gives users Auto, exact, and bounded reruns and now supports in-person microphone-track diarization. An automatic calendar cap could be useful as an initial hint, but it is not the quality unlock and should not precede the configuration benchmark.

### 6. Upstream word assignment — do not replace fork behavior

**Decision:** Keep the fork's Reading Turn attribution.

Upstream PR #974 did not implement the larger post-processing recommendations from its own research: nearest-turn fallback, one-word flip smoothing, embedding consolidation, stable IDs across reruns, and confidence-based review. The fork already implements a stronger presentation-level stabilization layer than the upstream baseline. Pulling the upstream `TranscriptionService` or finalizer would remove fork-specific microphone diarization, cleaned-mic routing, Reading Turns, and vocabulary/AI cleanup behavior.

## Recommended experiment

Use 10–20 test-owned, hand-labeled recordings representing the fork's actual paths:

- remote meeting system tracks;
- in-person microphone tracks;
- rapid backchannels and interruptions;
- two similar voices;
- three to six speakers;
- noisy and echo-cleaned microphone audio;
- at least one long meeting.

For each configuration arm, record:

- DER with a fixed collar and overlap policy;
- JER;
- detected speaker-count error;
- word-level attribution error after `SpeakerMerger`;
- visible Reading Turn correction count after the fork's presentation builder;
- false speaker clusters;
- missed short interjections;
- wall time and peak memory;
- run-to-run determinism, including exact and bounded corrections.

Primary acceptance should be **fewer user-visible attribution corrections**, not DER alone. The fork presents Reading Turns, not raw FluidAudio regions.

A practical first slice is:

1. Add a test-only injectable diarizer configuration seam.
2. Add the five configuration arms above to a corpus harness.
3. Keep production behavior unchanged.
4. Run the public FluidAudio fixture or test-owned corpus.
5. If evidence is positive, port shared model loading separately and enable the winning configuration behind one rollback flag.

## Recommendation

There is enough evidence to investigate, but not enough to switch production to upstream's full preset immediately.

- **Already won:** 0.15.6 clustering correctness and determinism.
- **Port now as engineering work:** shared model loading/cancellation/retry design, after adapting it to the fork's two-track and Adjust Speakers paths.
- **A/B first:** step ratio 0.1 and zero-vote re-embed.
- **Treat cautiously:** minimum segment duration 0; it appears to drive much of the segment explosion and false-alarm increase.
- **Defer:** calendar attendee cap.
- **Do not cherry-pick:** upstream's broad transcription/finalizer integration.

The likely unlock is not a new model. It is a combination of the 0.15.6 clustering fixes already in the fork, a carefully selected higher-evidence configuration, and the fork's stronger Reading Turn post-processing. The available evidence suggests a modest acoustic improvement, not a step-function quality gain.

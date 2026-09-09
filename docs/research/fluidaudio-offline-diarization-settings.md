# FluidAudio offline diarization: settings and implementation research

Researched 2026-09-09. This document reports source evidence, not a new product specification or an implemented fix. No audio was uploaded or reprocessed. No models were downloaded and no application settings were changed.

## Implementation follow-up

The user selected FluidAudio exclusive output, step ratio 0.1, minimum segment duration zero, and unchanged embedding defaults, model choice, and identity naming. The correction removes the added silence scan, recursive Reading Turn reordering, and text-level microphone echo deletion. It aligns words to consecutive model speaker contributions and persists combined same-speaker contributions; original word times and model regions remain separate evidence.

A local run on the affected 129-second system track used the cached model with these settings and reused its 347 saved STT words. Through finalization, temporary persistence, reload and export, the result had two speakers and five Reading Turns instead of three labels and 31 turns. All word text and timestamps were unchanged; references remained in original order. However, the model still assigned the second speaker to 26.55–28.81 seconds inside the opening the user identified as one speaker. The acoustic attribution issue is unresolved. This run is not a fresh ASR evaluation or proof that the complete transcript is correct. Audio, transcript output, and the local probe remain outside the repository.

## Scope and exact versions

- MacParakeet release code: `b10be066adca5d44a91f3dbd1280ed67d6b8d995`.
- FluidAudio pin in `Package.resolved`, confirmed against the checkout: `4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b` (2026-08-19).
- Official pyannote source examined: `b749285c5cdd4636b2edc7f766f1352c8dde9369` (main when retrieved).
- FluidAudio web documentation was retrieved separately; claims about executable behavior below are checked against our pinned source, not assumed from current web documentation.
- Scope is **final/offline diarization**. `DiarizerConfig` for the older online pipeline, LS-EEND timeline settings, and Sortformer streaming settings are different interfaces. Advice for those configurations cannot be transferred by matching parameter names.

## Main finding: there is an explicit upstream accuracy recommendation

FluidAudio's official [Offline Pipeline documentation][1] says:

> Use step ratio 0.1 for critical accuracy.

Its table distinguishes two configurations:

| Configuration | Step ratio | Minimum duration | Reported DER | Reported JER | Speed |
| --- | ---: | ---: | ---: | ---: | ---: |
| Default | 0.2 | 1.0 s | 15.1% | 39.4% | 122× real time |
| Labeled “max accuracy” by FluidAudio | 0.1 | 0 s | 13.9% | 42.8% | 65× real time |

These are vendor-reported results on 232 VoxConverse clips. The pinned benchmark notes specify a 0.25-second collar and ignored overlap for this comparison. DER improves while JER worsens; “max accuracy” is the vendor's label, not evidence of universal superiority. The comparison changes two parameters together and cannot establish their separate contributions. It does not establish results on the user's recording. [1][2]

**Our app uses the default 0.2 step ratio and 1.0-second minimum, not that documented accuracy configuration.** `AppEnvironment` constructs `DiarizationService()` without a custom base config. Its final manager preserves those values while overriding the output settings listed below. [3][4]

The evidence therefore does not support my earlier suggestion that simply restoring every FluidAudio default is necessarily the correct accuracy choice. It also does not support inventing additional values without measurement.

## Actual configuration in the shipped final path

| Parameter | Pinned FluidAudio default | MacParakeet final path | Source-established meaning |
| --- | --- | --- | --- |
| `windowDuration` | 10 s | unchanged | Segmentation window; must match exported model geometry |
| `sampleRate` | 16000 | unchanged | Mono audio/model input rate |
| `segmentationStepRatio` | 0.2 | unchanged | 2-second hop over 10-second windows; 0.1 is a 1-second hop |
| `minSegmentDuration` | 1.0 s | unchanged | Used for embedding mask selection **and output segment filtering** |
| `embeddingExcludeOverlap` | true | unchanged | Masks concurrent-speaker frames during embedding extraction |
| `embeddingSkipStrategy` | none | unchanged | No optional reuse of similar-window embeddings |
| `embeddingBatchSize` | 32 | unchanged | Embedding/PLDA batching |
| `clusteringThreshold` | 0.6 | unchanged | Euclidean AHC cut distance, not a speech probability |
| `Fa` / `Fb` | 0.07 / 0.8 | unchanged | VBx priors |
| `clustering.constrainedAssignment` | true | unchanged | Distinct assignments for speakers in the same window, except after forced-count reclustering |
| Speaker count | automatic | automatic for ordinary GUI reprocessing | Explicit Adjust Speakers and CLI constraints are separate paths |
| VBx iterations / tolerance | 20 / 1e-4 | unchanged | Refinement stopping limits |
| `exclusiveSegments` | true | **false** | Controls final chronological overlap trimming |
| `minGapDuration` | 0.1 s | **0** | Final same-speaker region stitching threshold |
| `segmentationMinDurationOff` | 0 | explicitly 0 | Already zero; our assignment is not an effective change |
| `segmentationMinDurationOn` | 0 | unchanged | Output filtering also considers this, but the 1-second minimum dominates |
| `speechOnsetThreshold` / `speechOffsetThreshold` | 0.5 / 0.5 | unchanged | Config documentation says ignored for Community-1 powerset models |
| `zeroVoteReembed.enabled` | false | unchanged | Optional repair of speech-active frames with no cluster votes |
| `exposeChunkEmbeddings` | false | unchanged | Diagnostic output, not a classification setting |

Sources: pinned type definitions and actual wrapper construction. [3][4]

## Important behavior hidden behind those settings

### 1. The one-second minimum deletes model-output regions

`OfflineReconstruction.sanitize` calculates:

```swift
let minimumDuration = max(config.minSegmentDuration, config.segmentationMinDurationOn)
```

It filters out regions shorter than that duration. With our config, that is one second. If exclusivity is enabled, overlap trimming can shorten a region and then reject it against the same minimum again. [5]

Thus setting `segmentationMinDurationOn = 0` does **not** remove the one-second filter. The apparently embedding-related `minSegmentDuration` controls both stages. The official pyannote source converts reconstructed activity to regions with `min_duration_on=0.0`, rather than this shared one-second output cutoff. [5][6]

This proves that short detected regions can be removed in our current pipeline. It does not prove which missing or misattributed parts of the affected recording were caused by the filter: the pre-filter timeline was not saved.

### 2. There is a separate hard-coded embedding gate

Before extracting each local speaker embedding, pinned `OfflineEmbeddingExtractor.processChunk` does:

```swift
let cleanSum = sum(cleanMask)
let minActiveRatio: Float = 0.2
if cleanSum < Float(frameCount) * minActiveRatio {
    continue
}
```

For a 10-second window, this is approximately two seconds' worth of clean speaker-activity weight. It is a weighted-mask condition, not a precise two-second wall-clock rule. With overlap exclusion enabled, simultaneous-speech frames have already been removed from that mask. [7]

The gate occurs **before** the configurable minimum-frame choice and before fallback from the clean mask to the full mask. Therefore reducing `minSegmentDuration` to zero does not remove this gate. This is an implementation issue, not another exposed parameter to tune. Official pyannote's corresponding code falls back to the full speaker mask when its clean mask is too short for the embedding model; it has no equivalent fixed 20%-of-window early skip at that point. [6][7]

### 3. Missing embeddings can become wrong identities rather than missing speech

Pinned reconstruction predicts how many speakers are active from segmentation, then ranks cluster vote sums to select their identities. Its own code documents a failure when a speech-active frame has **zero votes for every cluster**: the selection can fall to cluster 0 despite no identity evidence. [5][8]

FluidAudio added an optional `zeroVoteReembed` pass in [PR #751][8] to re-embed these spans. It is included in our pin but disabled by default. The PR reports recovery of actual turns on its fixture. That is not sufficient evidence to enable it globally: another upstream report explicitly says enabling it did nothing on a different wrong-partition recording. It is a specific conditional repair, not a generic accuracy switch. [8][9]

### 4. Two different “exclude overlap” controls must not be confused

`embeddingExcludeOverlap=true` concerns the acoustic input used to estimate voice embeddings. Pinned Getting Started documentation explicitly recommends keeping it enabled for Community-1 powerset outputs. [10]

`exclusiveSegments=true` is a different post-pass. In our pinned FluidAudio version it sorts intervals, advances a later interval's start to the previous retained interval's end, and drops intervals that become empty or too short. It does not reconsider frame-level speaker confidence. [5]

Official pyannote's exclusive output is **not implemented this way**. It caps the frame-level speaker count at one and reconstructs the timeline again from segmentation and cluster assignments. It provides both regular and exclusive outputs. Treating FluidAudio's boolean as equivalent to pyannote's exclusive timeline is incorrect. [6][11]

Consequently, “restore exclusivity” is not a researched general solution to wrong attribution. Nor is turning it off a guarantee of improved attribution. It changes representation after clustering, with possible region loss when enabled.

### 5. The two effective overrides act after clustering

The pinned manager performs embedding extraction, AHC/VBx, centroid assignment and construction of per-window cluster assignments before invoking `OfflineReconstruction`. `minGapDuration` and `exclusiveSegments` are consumed in that reconstruction/output stage. They do not directly change embedding vectors or the VBx partition. [5][12]

Setting the gap threshold from 0.1 to zero prevents stitching some adjacent same-speaker regions. Because duration filtering follows stitching, it can also cause short regions that would otherwise survive together to disappear individually. Turning exclusivity off preserves regions the chronological trim might otherwise remove. These are real output changes, but they cannot alone be assumed to explain a particular acoustic speaker classification.

## Threshold guidance changed upstream

[Issue #801][9] reported the same detected speaker count but materially different partitions under automatic versus forced-count processing. [PR #802][13] fixed three porting differences:

1. The threshold had been interpreted as cosine similarity instead of a direct Euclidean AHC cut.
2. Speaker-count constraints were compared against the warm-start AHC count instead of the surviving VBx cluster count.
3. Per-window constrained speaker assignment was missing.

**Our pin already includes that fix** (`df1417ce86225af50150b11eb04fa01c0aba9148` is an ancestor). It is not a newly discovered update we can install to claim a fix.

At our pin, larger threshold values mean more aggressive merging and generally fewer warm-start clusters. Older advice has different semantics. The benchmark notes map old `0.7` to approximately `0.775` under the new interpretation; the old default `0.6` maps to approximately `0.894`. Blindly copying an older “best threshold 0.7” recipe is not valid. [2][3][13]

The official pyannote source currently exposes default parameters `threshold=0.6`, `Fa=0.07`, `Fb=0.8`, and segmentation minimum-duration-off zero. This is source-level support for these defaults. Its gated model `config.yaml` returned HTTP 401 during this research, so the exact downloaded checkpoint configuration was not independently read. Constructor defaults, default_parameters, and gated pretrained pipeline parameters must not be conflated. [6]

Forcing a speaker count can invoke K-Means when the automatically retained count violates the request; it is not merely changing a label or display count. The pinned config describes it as a target, not a guarantee, because downstream assignments can leave clusters unused. [3][12]

## Chunking and precision

The final app path supplies a complete selected source WAV to one offline manager call. **FluidAudio still uses internal overlapping windows**: 10-second segmentation windows with a 2-second hop under our config. This is expected model/pipeline processing, not independent STT-chunk diarization with reset identities. The documented accuracy option changes the hop to one second without changing the model's 10-second input window. [3][10]

The Core ML model card documents converted PyTorch models and FP16 on ANE versus FP32 on CPU/GPU. The pinned benchmark notes also acknowledge a precision-related quality gap from Python. Calling this “Community-1” establishes model lineage, not exact prediction parity with the official Python implementation. No hardware-precision comparison was run here. [2][14]

The official offline quick start takes audio directly through its segmentation pipeline. It does not require our added external Silero scan. Nothing in the examined guidance recommends that scan to construct conversational Reading Turns or to repair diarization. [1][10]

## Follow-up: overlapping turn starts/stops and upstream discussion

### Users explicitly reported word-attribution ambiguity at overlapping boundaries

In a first-hand [discussion comment][15], an integrator requested exclusive diarization because overlapping speaker segments made ASR word attribution ambiguous. The integrator also reported that excluding overlap from embedding input made embeddings too sparse and caused clustering failures on their audio. They wanted overlap-inclusive embeddings **and** exclusive output. This is a user report on a particular setup, not a universal recommendation to disable embedding overlap masking.

[Issue #343][16] and PR #342 separated these previously coupled controls. At our pin:

- `embeddingExcludeOverlap` controls embedding masks.
- `exclusiveSegments=false` lets overlapping reconstructed regions survive the exclusivity stage; other filters can still remove regions.
- `exclusiveSegments=true` trims later regions chronologically. A later region fully contained in an earlier retained one is dropped. A crossing region loses the shared prefix; minimum-duration filtering may then drop its remainder.

That describes interval manipulation, not a model-backed choice of which simultaneous speaker's words were transcribed. Official pyannote's separately reconstructed exclusive output remains a different mechanism. [5][6][16]

### Maintainers place temporal speaker boundaries in segmentation, not VBx tuning

A more recent [issue #879][17] reports rapid-turn errors and asks for a speaker-transition prior. The maintainer explains that the absence of that prior is intentional: this VBx implementation clusters per-window speaker embeddings, including several simultaneous speakers from one window. Treating that flattened embedding sequence as consecutive turns would mistake overlap for rapid switching. It follows pyannote's GMM-style update, which is visible in the upstream source. [17][18]

The maintainer points to denser segmentation windows and minimum-duration settings, not Fa/Fb, for short-turn sensitivity. Fa/Fb affect clustering evidence rather than imposing a temporal switching rate. The new documentation was merged after our pin, but describes the algorithm already present; it is not a new model fix. The reporter's measurements also show that improved aggregate DER does not necessarily improve recovery of rapid turn changes, so the comment is not proof of one universally best configuration. [17][18]

### What this does not supply

The examined FluidAudio sources discuss acoustic overlap, region boundaries and word-attribution ambiguity. They do not supply a single-column Reading Turn ordering policy for contained versus crossing contributions. I found no recommendation in these sources to create whole-recording speaker spans and recursively postpone contributions inside them. That behavior came from our assembler, not FluidAudio.

## Research conclusions, not automatic changes

- There is a documented accuracy-oriented starting configuration: **step ratio 0.1 and minimum duration 0**, retaining the supported 10-second / 16 kHz input geometry. We did not use it. It is supported as an evaluation candidate by explicit vendor guidance, not proven for this recording. [1]
- The unchanged one-second output filter and hard-coded 20% embedding gate are more consequential than my previous explanation acknowledged. Changing exposed settings alone does not remove both.
- Keep embedding overlap handling conceptually separate from output exclusivity. Published guidance supports the former; the latter is not equivalent to official pyannote's confidence-based exclusive reconstruction.
- There is no evidence-backed universal clustering-threshold replacement in this research. The current 0.6/Fa/Fb defaults have upstream source support; older recipes require semantic conversion.
- The zero-vote option should be investigated only if the affected audio exhibits its actual trigger. Similar symptoms alone are insufficient.
- I cannot establish the correct output for this recording by reading source or citing vendor scores. Neither “stock defaults fix it” nor “these three overrides caused the entire regression” follows from this evidence.

## Evidence available for a direct investigation

The pipeline can expose per-chunk embeddings and cluster assignments (`exposeChunkEmbeddings`), export embeddings, and report per-stage timings. Those outputs can help distinguish missing embeddings, clustering errors and region filtering without feeding the result through our Reading Turn assembler. The zero-vote trigger and the pre-sanitize timeline would need targeted diagnostics because the app's current saved segment list is already post-processed. This describes available evidence, not a new shipping requirement. [3][5][12]

## Sources

[1]: https://docs.fluidinference.com/diarization/offline-pipeline
[2]: https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Documentation/Benchmarks.md#diarization
[3]: https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerTypes.swift
[4]: https://github.com/eli0shin/macparakeet/blob/b10be066adca5d44a91f3dbd1280ed67d6b8d995/Sources/MacParakeetCore/Services/Diarization/DiarizationService.swift
[5]: https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Sources/FluidAudio/Diarizer/Offline/Utils/OfflineReconstruction.swift
[6]: https://github.com/pyannote/pyannote-audio/blob/b749285c5cdd4636b2edc7f766f1352c8dde9369/src/pyannote/audio/pipelines/speaker_diarization.py
[7]: https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Sources/FluidAudio/Diarizer/Offline/Extraction/OfflineEmbeddingExtractor.swift
[8]: https://github.com/FluidInference/FluidAudio/pull/751
[9]: https://github.com/FluidInference/FluidAudio/issues/801
[10]: https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Documentation/Diarization/GettingStarted.md
[11]: https://huggingface.co/pyannote/speaker-diarization-community-1
[12]: https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift
[13]: https://github.com/FluidInference/FluidAudio/pull/802
[14]: https://huggingface.co/FluidInference/speaker-diarization-coreml
[15]: https://github.com/FluidInference/FluidAudio/issues/49#issuecomment-3955671725
[16]: https://github.com/FluidInference/FluidAudio/issues/343
[17]: https://github.com/FluidInference/FluidAudio/issues/879
[18]: https://github.com/FluidInference/FluidAudio/pull/894

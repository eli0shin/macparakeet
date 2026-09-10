# Current diarization options for MacParakeet

Primary-source review on 2026-09-09. No recordings were uploaded, models downloaded, or application behavior changed.

## Conclusion

There is no established universal winner across offline accuracy, streaming latency, languages, speaker counts, licensing, and Apple Silicon deployment. The strongest documented shortlist from this review is pyannoteAI Precision-2 for commercial offline accuracy, pyannote Community-1 for a practical open-weight offline pipeline, DiariZen for a strong research alternative, and NVIDIA Streaming Sortformer for streaming. This is not an exhaustive ranking of all 2026 research.

**MacParakeet already uses a FluidAudio implementation of Community-1 for final diarization.** A recommendation to simply switch to Community-1 would miss that fact. FluidAudio's checked-out README describes powerset segmentation, WeSpeaker embeddings, and VBx clustering. Its OfflineDiarizerTypes.swift describes Community-1-derived defaults. This establishes lineage, not numerical parity with the upstream Python pipeline.

## Candidates

### pyannoteAI Precision-2

The Community-1 model card publishes a consistent comparison with no forgiveness collar and overlapping speech included:

| Dataset | Community-1 DER (%) | Precision-2 DER (%) |
| --- | ---: | ---: |
| AMI, single distant microphone | 19.9 | 15.6 |
| DIHARD 3, full | 20.2 | 14.7 |
| CALLHOME, part 2 | 26.7 | 16.6 |

Lower diarization error rate (DER) is better. DER measures missed speech, false speech, and speaker confusion over reference speaker time; it is not word accuracy or the fraction of transcripts that are correct. These are vendor-published results, not measurements of MacParakeet or the affected recording. [1]

A separate ETH Zurich study of 196.6 hours reports Precision-2 at 11.2% aggregate DER and DiariZen at 13.3%. Its open pyannote comparator is 3.1, **not Community-1**, and its Sortformer versions are not the latest 2.1 model card. Do not extend its ranking to models it did not evaluate. [2]

Precision models are commercial. pyannoteAI documents an Argmax partnership for on-device Precision deployment, so they are not necessarily cloud-only. Argmax's current SpeakerKitPro documentation exposes Pyannote and Sortformer engines on Apple platforms. Exact Precision-2 availability in an SDK configuration, license terms, and redistribution terms require confirmation before adoption. [3][4]

### pyannote Community-1

Open-weight pipeline, CC-BY-4.0, gated initial download, and fully local inference after download. Official implementation is in pyannote.audio. It provides both ordinary overlap-aware diarization and a separate exclusive output for reconciling diarization with transcription timestamps. The model card explicitly notes that STT and diarization timestamps can differ. [1]

For MacParakeet, the official implementation is a useful way to isolate model capability from the FluidAudio conversion and our surrounding processing. That is an implementation comparison, not an entirely different model. Native Apple performance and parity are not established by the published Python results.

### DiariZen

The BUT-FIT WavLM-based EEND/hybrid system is a serious alternative to the pyannote model family. Its model card reports substantially lower DER than pyannote 3.1 on several datasets. The cited pruned checkpoint reduces WavLM Large from 316.6M to 63.3M parameters; this is the WavLM component, not necessarily the complete pipeline. [5]

Important restriction: code is MIT, but the examined checkpoint's weights are **CC-BY-NC-4.0**. It is a research comparison candidate, not an automatically redistributable commercial replacement. Its card also links an updated model for higher simultaneous-speaker overlap. No native Mac deployment measurement was made here. [5]

### NVIDIA Streaming Sortformer 4spk v2.1

End-to-end streaming diarization with an Arrival-Order Speaker Cache to retain speaker information across chunks. The published checkpoint has four speaker outputs. The model card documents a latency/accuracy configuration trade-off, including approximately 1.04-second and 30.4-second latency configurations. Model processing chunks with explicit cross-chunk identity state are not the same as independently diarizing STT chunks. [6]

This is a strong streaming candidate, not evidence that it beats Precision-2 for completed meetings. Argmax documents an on-device Sortformer engine; equivalence to this exact v2.1 checkpoint is not established here. [4][6]

## Implications

1. Compare native model timelines before our word assignment and Reading Turn assembly. Replacing the model cannot repair known defects in our persisted assembly by itself.
2. For a genuinely different offline accuracy candidate, investigate Precision-2, including local Argmax delivery. For open research comparison, consider DiariZen subject to its weights license.
3. Do not claim any published DER guarantees continuous, correctly labeled contributions in the affected recording. The complete persisted transcript remains the product output.
4. No model choice or download was authorized or performed as part of this source review.

## Sources

1. Official Community-1 model card, benchmark, license and offline/exclusive-output documentation: https://huggingface.co/pyannote/speaker-diarization-community-1
2. Lanzendörfer et al., *Benchmarking Diarization Models*, primary research: https://arxiv.org/html/2509.26177v1
3. pyannoteAI, *pyannoteAI on Argmax SDK*: https://www.pyannote.ai/blog/pyannoteai-on-argmax-sdk
4. Argmax SpeakerKitPro examples and platform requirements: https://app.argmaxinc.com/docs/examples/speaker-diarization
5. BUT-FIT DiariZen model card and weights license: https://huggingface.co/BUT-FIT/diarizen-wavlm-large-s80-md
6. NVIDIA Streaming Sortformer v2.1 model card: https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2.1
7. Local pinned FluidAudio source: `.build/checkouts/FluidAudio/README.md`, offline diarization section; `Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerTypes.swift` in that checkout.

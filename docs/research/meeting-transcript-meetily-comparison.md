# Meeting transcript comparison: MacParakeet and Meetily Actually Free

> Scope: source-code comparison of final meeting transcription, speaker attribution, and transcript presentation. No shared recording was available, so this note separates verified implementation facts from likely failure mechanisms.

## Conclusion

Meetily does not appear to win because it has a better diarization model. MacParakeet uses the stronger batch diarization architecture on paper: FluidAudio's pyannote community-1 segmentation, WeSpeaker embeddings, and VBx clustering. Meetily uses a custom pyannote segmentation-3.0, WeSpeaker, and agglomerative-clustering pipeline.

Meetily wins mainly because it protects **utterance structure** from capture through presentation:

1. It transcribes separate microphone and system tracks.
2. VAD creates coherent utterance-sized transcript rows before diarization.
3. The microphone row is deterministically `You`; only the system side needs remote-speaker refinement.
4. Diarization assigns a label to a whole transcript row by aggregate time overlap.
5. The UI merges adjacent rows from the same speaker and renders one chat bubble per turn.

MacParakeet also transcribes separate microphone and system tracks and diarizes only the system track. The likely failure is later: it merges both source transcripts at **word granularity**, assigns remote speaker IDs at **word granularity**, and starts a new displayed turn whenever the next chronological word has a different speaker ID. Overlap, timestamp jitter, residual microphone echo, or small gaps in diarization can therefore cause rapid `Me` / remote / fallback switching. The Timed view faithfully renders that unstable word sequence, which makes the transcript look like failed diarization even when source separation worked.

The plain Text view has the opposite problem. It renders one stored transcript string. Meeting finalization normally constructs that string by joining chronological words with spaces, with no paragraph model. A long meeting therefore becomes one large paragraph.

## Verified pipeline comparison

| Stage | MacParakeet | Meetily Actually Free | User-visible effect |
|---|---|---|---|
| Capture | Separate microphone and system M4A tracks; mixed file is playback only | Separate `mic.mp4` and `system.mp4`; mixed `audio.mp4` is playback only | Both apps have the correct source-separation foundation. |
| Final STT | Runs STT once per retained source file and returns word timestamps | Runs source-specific VAD, then STT per VAD utterance | Meetily has coherent utterance boundaries before speaker assignment. |
| Local-user identity | Every microphone word gets source ID `microphone` / label `Me` | Every microphone utterance gets hint `You` | Both avoid clustering the local user in the normal dual-track path. |
| Remote diarization | FluidAudio offline diarizer on system track only | Custom offline diarizer on system track only | Neither current dual-track path should confuse mic and system inside the diarizer itself. |
| Speaker assignment | Maximum overlap for each system **word** | Aggregate overlap for each transcript **utterance**; meaningful simultaneous speakers can produce a combined label | Meetily damps boundary noise and preserves overlap semantics. |
| Speaker count | Core service supports exact/range constraints, but normal meeting UI does not ask | Post-call UI asks for total speakers and recommends an exact count; Auto-detect remains available | Meetily gives clustering a strong prior when the user knows the count. |
| Display grouping | Punctuation, 1.5-second gaps, 40 words, and every speaker-ID change create segments; consecutive equal IDs create cards | Adjacent equal-speaker utterances within 2.5 seconds merge into one bubble | MacParakeet exposes attribution jitter; Meetily hides harmless fragmentation. |
| Full text | One selectable stored string | Main transcript surface is always an utterance/turn list | MacParakeet's Text mode loses meeting structure. |

## Primary-source evidence

### MacParakeet

- The meeting architecture says final STT reads `microphone-raw.m4a` and `system-raw.m4a` independently and applies diarization only to the isolated system track: [`docs/research/meeting-dual-stream-transcription-pipeline.md`](./meeting-dual-stream-transcription-pipeline.md).
- `TranscriptionService.transcribeMeetingSources` transcribes each active source separately. `diarizeMeetingSystemIfNeeded` diarizes only the system WAV and namespaces remote IDs as `system:S1`, `system:S2`, and so on: [`Sources/MacParakeetCore/Services/TranscriptionService.swift`](../../Sources/MacParakeetCore/Services/TranscriptionService.swift).
- `MeetingTranscriptFinalizer.shiftedWords` assigns every word its capture-source ID. `finalize` then concatenates microphone and system words and sorts them by word start time: [`Sources/MacParakeetCore/Services/MeetingRecording/MeetingTranscriptFinalizer.swift`](../../Sources/MacParakeetCore/Services/MeetingRecording/MeetingTranscriptFinalizer.swift).
- `SpeakerMerger.mergeWordTimestampsWithSpeakers` chooses the diarization segment with the greatest overlap independently for each word. A system word with no diarization overlap keeps its existing `system` fallback ID: [`Sources/MacParakeetCore/Services/Diarization/SpeakerMerger.swift`](../../Sources/MacParakeetCore/Services/Diarization/SpeakerMerger.swift).
- `TranscriptSegmenter` flushes a segment on every non-nil speaker change. It then groups only consecutive equal-speaker segments into turns: [`Sources/MacParakeetCore/Utilities/TranscriptSegmenter.swift`](../../Sources/MacParakeetCore/Utilities/TranscriptSegmenter.swift).
- The Timed UI renders those turns as cards and renders a timestamped row for each segment: [`Sources/MacParakeet/Views/Transcription/TranscriptTimestampedContentView.swift`](../../Sources/MacParakeet/Views/Transcription/TranscriptTimestampedContentView.swift).
- The Text UI passes the complete stored transcript to one SwiftUI `Text`. `MeetingTranscriptFinalizer.transcriptText` joins words with spaces and does not create paragraphs: [`Sources/MacParakeet/Views/Transcription/TranscriptResultView.swift`](../../Sources/MacParakeet/Views/Transcription/TranscriptResultView.swift), [`Sources/MacParakeetCore/Services/MeetingRecording/MeetingTranscriptFinalizer.swift`](../../Sources/MacParakeetCore/Services/MeetingRecording/MeetingTranscriptFinalizer.swift).
- MacParakeet's diarizer wraps FluidAudio's `OfflineDiarizerManager`: [`Sources/MacParakeetCore/Services/Diarization/DiarizationService.swift`](../../Sources/MacParakeetCore/Services/Diarization/DiarizationService.swift). The accepted architecture records pyannote community-1 + WeSpeaker + VBx: [`spec/adr/010-speaker-diarization.md`](../../spec/adr/010-speaker-diarization.md).

### Meetily Actually Free

- The architecture explicitly keeps mic and system VAD/STT separate and says only system audio is clustered for normal new recordings: [`../Meetily-ActuallyFree/ARCHITECTURE.md`](../../../Meetily-ActuallyFree/ARCHITECTURE.md).
- Retranscription discovers `mic.mp4` and `system.mp4`, applies source-specific VAD thresholds, gives completed mic/system utterances the `You`/`Guest` hints, and saves one database row per VAD/STT result: [`frontend/src-tauri/src/audio/retranscription.rs`](../../../Meetily-ActuallyFree/frontend/src-tauri/src/audio/retranscription.rs).
- Offline diarization handles the mic as one known local speaker and clusters only the system track into remote speakers. It then labels each transcript row from aggregate overlap and preserves combined labels for meaningful overlap: [`frontend/src-tauri/src/diarization/mod.rs`](../../../Meetily-ActuallyFree/frontend/src-tauri/src/diarization/mod.rs).
- The post-call dialog asks for an exact total speaker count and explains that it is more accurate than Auto-detect: [`frontend/src/components/MeetingDetails/PostCallProcessingDialog.tsx`](../../../Meetily-ActuallyFree/frontend/src/components/MeetingDetails/PostCallProcessingDialog.tsx).
- `VirtualizedTranscriptView` merges adjacent same-speaker rows within 2.5 seconds and renders local speech on the right and remote speech on the left: [`frontend/src/components/VirtualizedTranscriptView.tsx`](../../../Meetily-ActuallyFree/frontend/src/components/VirtualizedTranscriptView.tsx).

## Acoustic bleed is a separate defect

A speaker-mode call can put the far-end voice onto both retained tracks:

- the system track contains the direct loopback signal;
- the microphone track contains the same voice after room playback, delay, coloration, and attenuation.

Source separation alone cannot identify the second copy as echo. MacParakeet correctly treats microphone speech as `Me`, so any far-end copy that survives microphone cleanup and `MeetingTranscriptSourceReconciler` becomes a false local utterance. System-side diarization then labels the direct copy as a remote speaker. This produces the same sentence under two identities.

Meetily does **not** contain a general acoustic echo canceller in the reviewed path. It high-pass filters, optionally applies RNNoise, normalizes/limits microphone loudness, uses source-specific VAD, and avoids amplifying microphone bleed without bounds. Those steps can reduce whether a quiet room copy becomes a completed microphone utterance, but RNNoise is noise suppression, not reference-based echo cancellation. Meetily can therefore still duplicate far-end speech in speaker mode.

The reported headset failure is important because it proves acoustic bleed is not the complete explanation. With physical bleed removed, MacParakeet's word-level merge, word-level remote assignment, fallback speaker ID, and turn rendering can still fragment a correct pair of source transcripts.

## Likely MacParakeet failure mechanisms

These are source-based hypotheses. A shared audio fixture is required to rank them.

### 1. Word-level cross-source interleaving

For simultaneous speech, the finalizer sorts mic and system words onto one linear timeline. If starts alternate, the presentation model sees repeated speaker changes even when each source transcript is internally correct.

Example:

```text
mic:    [I  10.00] [think 10.30] [we 10.60]
system: [yes 10.10] [but 10.40] [wait 10.70]
merged: I / yes / think / but / we / wait
turns:  Me / Others / Me / Others / Me / Others
```

Meetily keeps these as two utterances and can show overlap as `You + Speaker 1`. It does not force alternating words into alternating bubbles.

### 2. Word-level remote label jitter

Diarization boundaries and ASR word boundaries come from different models. Assigning each word independently makes a boundary error visible as a one-word speaker flip. Meetily aggregates overlap across an utterance, so one noisy boundary usually cannot relabel the whole row.

### 3. Fallback `Others` becomes an extra apparent speaker

When a system word does not overlap a diarization segment, `SpeakerMerger` retains `speakerId = system`. The speaker roster can therefore include both `Others` and refined `Others 1`, `Others 2`, and so on. The UI treats these as different speaker IDs and splits turns between them.

### 4. Residual far-end audio on the microphone track

MacParakeet has an echo reconciler, but any duplicated far-end words that survive it remain deterministic `Me` words. The diarizer cannot repair them because the microphone side intentionally bypasses diarization. This can look like mic/system confusion, but it is source contamination before attribution, not a clustering error.

### 5. Auto-detected remote count

MacParakeet's service can constrain speaker count, but the standard meeting workflow does not collect it. Meetily's own calibration notes say one threshold cannot fit every recording and that an exact count fixed its measured speaker-count cases. This can explain remote over-splitting or merging, but not the plain-text paragraph problem or mic/system alternation.

## Recommended direction

### P0: Prove the failure shape before changing models

Acquire one consented 10–20 minute meeting fixture with:

- separate mic and system tracks;
- at least two remote speakers;
- some overlap;
- some speaker-output bleed into the mic;
- a small hand-annotated set of expected turns.

Log or export these intermediate forms:

1. source-specific STT words;
2. source reconciliation removals;
3. raw system diarization segments;
4. current word-level assignments;
5. proposed utterance-level assignments;
6. rendered turns.

Measure both model quality and readability:

- speaker-count error;
- diarization error rate or a smaller turn-attribution score;
- one-word speaker flips;
- displayed turns per minute;
- median words per displayed turn;
- duplicate simultaneous mic/system text retained.

Do not replace FluidAudio based only on current UI output. The source comparison does not support that conclusion.

### P1: Add a meeting-turn assembly layer

Create one derived presentation model between persisted words and all human-facing meeting transcript surfaces. A useful shape is:

```swift
MeetingTurn {
    id
    startMs
    endMs
    speakerIDs
    speakerLabel
    text
    source
    isOverlap
    confidence
}
```

Rules:

1. Build coherent utterances inside each source first, using punctuation and silence gaps.
2. Attribute a system utterance by aggregate diarization overlap, not one word at a time.
3. Require evidence before changing a turn's speaker; smooth isolated one-word flips.
4. Keep microphone identity deterministic.
5. Represent real cross-source overlap explicitly instead of alternating the two word streams.
6. Preserve the original word array for playback, exports, search citations, and correction. The turn model is derived presentation structure, not a replacement for evidence.

This is the highest-value technical change because it improves the Timed UI even if the underlying diarization model stays unchanged.

### P1: Make Text mode structurally readable

Do not modify the user's stored or edited transcript only to add display formatting. Derive display paragraphs:

- Prefer `MeetingTurn` paragraphs for meetings with timestamps.
- For unlabelled transcripts, use durable transcript segments and merge them into paragraphs with a target of roughly 2–5 sentences or 60–120 words.
- Use a blank line between paragraphs.
- Keep selection across the whole document.
- Keep Copy/Edit semantics explicit: copy the displayed structured text or the original plain text, rather than silently changing persisted content.

### P2: Prototype three transcript presentations

Prototype these as throwaway UI variants against the same synthetic meeting data:

1. **Conversation** — Meetily-like left/right bubbles, one bubble per turn, first timestamp only.
2. **Reading transcript** — full-width speaker paragraphs with a colored rail, speaker label, and first timestamp. This is likely the best default for 30–60 minute meetings because it is denser than chat.
3. **Hybrid** — reading paragraphs by default; compact overlap blocks or paired bubbles only when two sources genuinely overlap.

Evaluate with a 60-minute synthetic transcript and intentionally noisy attribution. The winning UI must remain readable when some labels are wrong; good presentation must not depend on perfect diarization.

### P2: Expose speaker-count correction without blocking every meeting

Do not copy Meetily's mandatory post-call interruption unchanged. MacParakeet queues finalization in the background and should keep that flow. Better options:

- an optional expected-speaker count on the recording tile;
- a non-blocking “Found N speakers · Re-run…” action after completion;
- exact count in retranscription controls.

The count should mean **total people including Me** in the UI, then convert to remote count for system-only diarization.

## Proposed implementation sequence

1. Add characterization tests that reproduce alternating mic/system words, one-word remote flips, uncovered system words, and true overlap.
2. Implement pure `MeetingTurnAssembler` logic and compare old/new turn metrics on fixtures.
3. Make both Text and Timed meeting views consume the same derived turns.
4. Run the UI prototype and select Conversation, Reading, or Hybrid.
5. Add optional speaker-count correction.
6. Only then tune or replace diarization models if annotated audio still shows a model-level defect.

## Prototype ticket draft

**Title:** Prototype readable meeting transcript layouts with noisy speaker attribution

**Question:** Which transcript layout stays readable for a 30–60 minute meeting when speaker labels include realistic mistakes and overlap?

**Variants:** Conversation, Reading transcript, Hybrid.

**Fixture:** One deterministic synthetic meeting with 3 speakers, 60 minutes of generated turns, short acknowledgements, long monologues, overlap, one-word label flips, and unlabeled gaps.

**Acceptance criteria:**

- One command launches all variants.
- A URL search parameter switches variants.
- The current variant shows the complete derived `MeetingTurn` state.
- Local-user, remote-speaker, unknown, and overlap cases are visible.
- The reviewer records a verdict and rejected alternatives.
- Prototype code is throwaway and does not merge to `main`; the selected behavior is implemented separately.

A local Tickets workspace was not configured in this checkout, so this draft is captured here instead of creating a tracker item.

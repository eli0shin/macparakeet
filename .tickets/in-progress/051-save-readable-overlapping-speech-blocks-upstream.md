---
Assigned-To: macparakeet@051-save-readable-overlapping-speech-blocks-upstream
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## Problem Statement

Work meetings routinely contain short replies, interruptions, simultaneous starts, and overlapping speech. Microphone and system audio can also have small timing differences that make a normal handoff appear to overlap.

MacParakeet currently orders attributed words globally by their start timestamps and splits Reading Turns whenever the originating contribution changes. Two coherent contributions can become alternating one-word or few-word turns. The result is unreadable.

The removed simultaneous-speech feature failed in the opposite direction: it kept a speaker's long contribution together and placed intervening questions or replies after that speaker's later speech, sometimes minutes later. Restoring that feature is not acceptable.

Users need a readable, single-column final transcript that preserves each contribution and the local conversation order. The saved transcript must contain that order; the UI must not repair or independently reconstruct it.

## Solution

Identify Speech Blocks from clear source/speaker-local activity boundaries, then order those blocks rather than interleaving their words. A clear pause before and after a contribution is useful even while another speaker continues talking. Perfect paragraph understanding and noisy-room speech separation are not required.

Apply these rules:

- **Contained overlap:** insert the contained block whole near its start, splitting the surrounding block once. Resume the surrounding speaker from that split, preserving words spoken during the insertion.
- **Crossing overlap:** show complete blocks sequentially in start order. Do not split both blocks into alternating fragments.
- **Nested containment:** apply the insertion rule recursively.
- **Crossing chains inside a larger block:** keep the chain sequential and intact, then resume the surrounding block.
- **Nearly shared boundaries or uncertain containment:** prefer sequential block order. Never fall back to word-by-word alternation.

Preserve genuine short replies, including consecutive one-word exchanges. The prohibition is artificial fragmentation, not short speech.

Save ordered, speaker-labeled Reading Turns, their text, and their exact relationship to the original timed words. All readable outputs consume that saved structure. Keep original timing evidence for playback and evidence-focused exports.

This is one feature covering final meeting transcripts and imported recordings where the necessary timing and speaker evidence exists. Apply it to new transcription and explicit reprocessing. Preserve existing saved transcripts and user edits; retain plain text when timing is unavailable.

## User Stories

1. As a meeting participant, I want overlapping contributions to remain readable blocks, so that I can follow what each person said.
2. As a meeting participant, I want a short interjection inserted near its start, so that it stays close to the speech it interrupts.
3. As a meeting participant, I want the surrounding speaker to resume after the interjection, so that I can follow the interrupted contribution.
4. As a meeting participant, I want words spoken during an interjection preserved, so that concurrent speech is not silently deleted.
5. As a meeting participant, I want a crossing overlap shown as complete sequential contributions, so that neither person's speech becomes alternating fragments.
6. As a meeting participant, I want simultaneous starts handled without word-by-word alternation, so that a brief competition to speak does not damage the transcript.
7. As a meeting participant, I want small timing differences at a handoff tolerated, so that separate microphone and system capture do not create false interruptions.
8. As a meeting participant, I want a genuine one-word reply preserved, so that agreement or disagreement is not lost.
9. As a meeting participant, I want genuine consecutive one-word exchanges preserved, so that readability rules do not rewrite the conversation.
10. As a meeting participant, I want replies to a question kept before the speaker's later continuation when the block relationships establish that order, so that the transcript does not suggest people answered minutes later.
11. As a meeting participant, I want nested interruptions handled consistently, so that a third speaker can interrupt an already inserted contribution.
12. As a meeting participant, I want crossing interjections kept sequential inside a longer contribution, so that multiple speakers do not produce fragments.
13. As a meeting participant, I want legitimate sustained overlap shown as sequential blocks in one column, so that I do not have to read parallel text.
14. As a speaker, I want my speech boundaries based on actual activity evidence rather than one universal pause duration, so that my speaking pace does not determine whether the transcript is readable.
15. As a speaker, I want breaths and recognition-window boundaries not automatically treated as new contributions, so that processing details do not become conversation structure.
16. As a user, I want no word split at an insertion point, so that the saved text remains intact.
17. As a user, I want each speaker's original word order preserved, so that rearranging contributions does not rearrange what that speaker said.
18. As a user, I want uncertain overlaps handled conservatively, so that the app does not claim a precise interruption that the evidence cannot establish.
19. As a user, I want the readable order saved during finalization, so that reopening the transcript does not produce a different conversation.
20. As a user, I want the displayed transcript and copied text to use the same saved order, so that sharing a passage does not change it.
21. As a user, I want readable exports and meeting artifacts to use that same order, so that saved documents match the app.
22. As a user, I want summaries and chat to receive the saved readable conversation, so that AI does not work from interleaved word fragments.
23. As a user, I want navigation and citations to retain exact source-word references, so that I can find the speech behind a contribution.
24. As a user, I want playback and timed exports to preserve the original timestamps, so that readable ordering does not fabricate a different audio timeline.
25. As a user, I want genuine speaker identities and attribution uncertainty preserved, so that improved grouping does not invent who said something.
26. As a user importing a recording, I want the same block-ordering policy when timing and speaker evidence support it, so that readable transcripts are not limited to app-recorded meetings.
27. As a user of microphone speaker detection, I want local speakers treated by the same evidence-based rules as remote speakers, so that the microphone is not permanently favored as the primary speaker.
28. As a user with speaker detection disabled, I want the existing source labels respected, so that this feature does not silently enable speaker identification.
29. As a user of an engine without word timestamps, I want my plain-text transcript preserved, so that missing timing does not cause fabricated alignment or loss of text.
30. As a user with existing saved transcripts, I want installation and ordinary reading to leave them unchanged, so that an update does not silently restructure my records.
31. As a user who explicitly reprocesses a recording, I want the new saved result to use the new policy, so that I can correct an older unreadable transcript.
32. As a user who edited a transcript, I want my edits protected, so that automatic structure changes do not overwrite my work.
33. As a privacy-conscious user, I want block detection and ordering to run locally, so that improving the transcript does not send audio to a service.
34. As a user of optional AI cleanup, I want cleanup to preserve saved speaker blocks and order, so that rewriting text cannot undo the conversation structure.
35. As a user, I want the saved order to remain usable after source audio expires under my retention settings, so that reading does not require rerunning audio analysis.
36. As a CLI user, I want readable transcript operations to consume the same saved structure as the app, so that automation does not expose a different conversation.

## Implementation Decisions

### One upstream owner

- Move ownership of final readable structure from presentation-time reconstruction to the transcription/finalization workflow. This is not a UI-only patch or a restoration of simultaneous-speech grouping.
- Reuse the existing transcription service, meeting finalizer, persistence layer, and shared document consumers where practical. Meeting and imported-file completion currently take different segmentation paths; both must honor the same feature contract without creating separate deliverables.
- Establish the ordered Reading Turns before readable text is supplied to downstream formatting, persistence, exports, artifacts, and AI context. Keep optional formatting separate from block detection and ordering.
- Rendering may lay out paragraphs and apply current speaker labels, but it must not re-sort words, infer new turns, or merge across an inserted contribution. Existing UI grouping must not replace saved conversation structure.

### Speech-block evidence

- Use clear speech activity and speaker evidence in each source/speaker's own timeline. Silence in one source can bound a contribution while another source remains active.
- Prefer the existing local VAD and diarizer over adding a semantic completion model. An additional small local model is permitted only if an actual need is established; no new model is required by this spec.
- Reuse the selected cleaned or raw microphone audio and the system audio already used for final recognition. Apply the existing source alignment consistently to all evidence used for ordering.
- Preserve gaps and overlap evidence needed to identify blocks. The current diarizer's default exclusive post-processing trims overlaps; assess and adjust evidence acquisition rather than assuming those returned regions contain all concurrent speaker activity. Do not assume disabling exclusivity alone solves word attribution.
- The existing live VAD adapter exposes reduced start/end events and uses live-specific silence and padding settings. Do not treat those events as the authoritative final block representation. The underlying VAD exposes probabilities suitable for an offline analysis path.
- Do not adopt VAD segmentation defaults as conversation rules: padding can create artificial overlap, maximum speech duration can force unwanted splits, and minimum speech duration can remove genuine short replies.
- No universal pause duration, paragraph word count, or sentence count is approved as the definition of a Speech Block. Acoustic detection still needs engineering choices for stability, resolution, and uncertainty; research and justify those choices without asking the user to select a fixed duration.
- Do not make exact linguistic paragraph segmentation a prerequisite. Paragraph layout must not determine which speaker's words belong together.
- Word recognition confidence is not boundary confidence. A word-timestamp gap is not proof of silence. Apparent overlap is not proof of a clock offset.
- Within a mixed track, use available speaker evidence without inventing parallel transcripts. Recognized words missing from mixed speech cannot be recovered by rearrangement alone.

### Ordering contract

- Primary and secondary roles are local to a containment relationship, not permanent source or speaker priorities.
- For containment, split the surrounding block near the contained block's start. If that start falls during a word, insert after that word; otherwise use the nearest inter-word boundary. Do not wait for a distant sentence ending.
- Keep the inserted block whole relative to its surrounding block. Nested containment may split that inserted block around another contained contribution under the same rule.
- After insertion, resume at the original split point, not the inserted block's end time. Preserve all concurrent words.
- For crossing overlaps, emit intact blocks by start time. Nearly shared starts/ends and uncertain containment use this conservative sequential policy.
- Apply containment recursively. Preserve crossing chains sequentially before resuming their surrounding block, including when the chain postpones concurrent words from that surrounding speaker. Do not introduce a hidden maximum-delay cap that contradicts this behavior.
- Ordering must be deterministic, including exact timestamp ties. Preserve stable source/evidence order as the existing tie-break precedent where no stronger relationship is established.
- Do not impose a minimum word count on Reading Turns. Preserve genuine short responses and maintain every recognized evidence word exactly once in the structural mapping. Existing conservative text cleanup remains a separate transformation; block ordering must not drop words to improve readability.

### Durable representation and consumer contract

- Persist ordered, speaker-labeled Reading Turns, their readable text/paragraphs, timing information, and exact source-word references or an equivalent lossless mapping. The saved ordering is authoritative after reload.
- Preserve original timed evidence separately. Do not simply rearrange a timestamp-ordered word array and assume all timing-based consumers remain correct.
- Existing durable segments use one contiguous word-index range. A Reading Turn can reference noncontiguous entries in globally timestamp-ordered evidence, so an enclosing minimum/maximum range is insufficient. Extend persistence to represent exact references without accidentally including another speaker's words. The precise schema is an engineering choice, not fixed by this spec.
- Existing shared meeting readers reconstruct turns from words even when segments are saved. Update consumers to prefer the authoritative saved structure, rather than merely writing different segments and leaving read-time reconstruction intact.
- Cover displayed transcript text, copy and passage copy, readable exports, meeting artifacts, readable CLI surfaces, indexed readable content, and transcript text supplied to AI. Formatting wrappers may differ; contribution content and order must not.
- Keep subtitles and evidence-focused exports tied to original timing. Sequential readable blocks can overlap in their time ranges; do not falsify times to make them monotonic in reading order.
- Keep speaker renaming and citation/playback mappings valid without recomputing block order. Preserve existing unknown/source-only attribution when identity is unavailable.
- Optional AI cleanup must not own block structure or change ordering. Stale formatting tied to old turn text or identity must not restore old structure.

### Compatibility and lifecycle

- Apply the policy to new transcription and explicit reprocessing. Do not silently backfill or rewrite old saved transcripts during migration, app launch, or reading.
- Provide backward-compatible reading of records without the new saved structure. Do not require retained audio simply to read an existing transcript.
- Preserve user-edited transcripts under the existing edit contract. Do not add an automatic rebuild UI or a new destructive reprocessing flow.
- When word timing is unavailable, preserve the plain-text result without invented times or speaker structure. No new forced-alignment step or engine switch is required.
- Preserve current speaker-detection preferences, local-first behavior, cancellation/recovery behavior, and audio-retention controls. Do not delete user artifacts or expose partial new structure as a completed transcript if processing fails.
- Version and migrate persistence as needed, and preserve existing public evidence contracts. Any necessary public CLI contract change must be explicit and documented, not a silent reinterpretation of word indices.

## Testing Decisions

### Primary test boundary

Use the existing transcription-service workflow as the main test boundary: finalize or import, save through the real test repository, reload, and consume the result through the shared readable outputs. This is the highest useful existing boundary for proving that structure is computed upstream, survives persistence, and is not repaired only by a view.

Reuse existing injected speech-engine, audio-processing, and diarization test dependencies. If activity evidence needs a new injectable interface, add it at that workflow boundary rather than introducing separate test-only interfaces for each ordering helper. Do not mock the saved order or the algorithm under test.

This test-boundary choice follows the agreed upstream-save requirement and current test infrastructure.

### What good tests establish

- Assert externally visible contribution text/order, preservation of original evidence, exact word ownership, reload stability, and agreement between readable consumers. Do not assert private helper calls, arbitrary internal chunk sizes, or one chosen algorithm's data structures.
- Exercise the agreed contained, crossing, nested, and crossing-chain relationships through the primary boundary. Preserve the distinctions already agreed in the design session; do not require a new user transcript-example exercise to invent pause constants.
- Verify genuine short replies, genuine consecutive one-word exchanges, handoffs with near-shared boundaries, stable ties, and uncertain-containment fallback.
- Verify that insertion preserves the surrounding speaker's concurrent words, keeps individual words intact, and does not split both crossing contributions into alternating fragments.
- Verify no loss or duplication in the evidence mapping and preservation of speaker-local order. Check exact references where a block's words are noncontiguous in timestamp order.
- Verify persistence round-trip and readable consumer parity. A test that only constructs a presentation document in memory cannot establish acceptance.
- Verify readable order survives without audio at read time and without running block detection in the UI or shared readers.
- Verify that timing-focused outputs keep original timestamps even when readable order differs. Validate passage/citation ownership and playback targets against original evidence.
- Verify optional cleanup cannot reorder contributions and stale formatting cannot restore superseded grouping.
- Verify both new meeting finalization and imported-file completion, plus explicit reprocessing, legacy records, user-edited transcripts, disabled speaker detection, and untimed engine output.
- Verify failures/cancellation do not publish inconsistent completed records or delete user data. Preserve established recovery and retention behavior.

### Prior art and acoustic verification

- Extend the existing TranscriptionServiceTests patterns for separate-source alignment, cleaned-microphone selection, durable transcript segments, finalization persistence, and cancellation.
- Reuse MeetingReadingTurnConsumerTests patterns for shared copy/export/AI output, speaker renaming, navigation, untimed fallback, and subtitle timing. Feed these checks from reloaded workflow results rather than maintaining unrelated ordering expectations in every consumer.
- Use MeetingChronologicalSpeechTests as regression history for misplaced questions and long continuations. Preserve the product intent, not a blanket requirement that every word be globally chronological.
- Existing finalizer and presentation-builder tests can support focused diagnosis, but they are not substitutes for the save/reload acceptance boundary.
- The primary workflow tests can inject deterministic acoustic evidence; they do not establish that the VAD adapter detects real speech correctly. Verify the adapter against local/public speech material as needed. Use private recordings only with permission, and do not transmit them externally. Do not treat a few hand-written transcripts or word-error/diarization-error metrics alone as evidence of general block-boundary quality.
- Run focused tests for the touched areas during implementation. Follow the repository rule allowing the full suite at most once as the final gate. This specification task does not run or change tests.

## Out of Scope

- Live preview ordering or live diarization changes.
- Parallel columns, overlap badges, or restoration of the removed simultaneous-speech grouping feature.
- General separation of many simultaneous voices in a noisy room.
- Perfect linguistic paragraph segmentation, a new semantic parser, or mandatory completion-model inference.
- A universal pause threshold or a hand-written transcript-example exercise for selecting one.
- Automatic rewriting of existing saved transcripts or overwriting user edits.
- A new rebuild UI, automatic engine switching, or forced alignment for untimed engine output.
- Recovering speech recognition never produced by rearranging existing words.
- Guessing source clock corrections from overlap alone.
- Cloud audio processing, hidden model/network activity, or changed privacy/retention policy.
- Splitting cross-track and same-track behavior into separate deliverables.
- Unrelated text cleanup, capture, diarization, or UI refactoring.

## Implementation and verification

- Implemented on branch `051-save-readable-speech-blocks` in its own worktree. Final meetings, imported recordings, and explicit speaker correction save authoritative Reading Turns with exact evidence membership; legacy rows are not backfilled.
- Cached local VAD supplies quiet intervals. Final diarization preserves overlapping activity without changing live processing. Word-derived source fallback regions are not treated as acoustic silence.
- Shared readable consumers and the UI use saved structure. Playback uses a separate original-evidence index. Original word times and timed subtitle behavior remain unchanged.
- 125 focused checks passed after resolving the in-scope review findings. An additional opt-in cached-model run passed all nine feature tests, including detection of a deliberate silence in locally generated speech. No private audio or new model download was used.
- The remaining review finding about terminal action extraction across paragraph boundaries is explicitly excluded by the user. Do not expand this ticket to address it.
- Broad final gate passed: 5,155 XCTest cases, 22 runtime skips, zero failures; 14 Swift Testing cases also passed. Eight desktop-window-opening test classes were excluded because a previous full-suite run froze the desktop. This gate ran once.
- Implementation is complete; keep this ticket in progress while the PR is under review.

## Further Notes

- This spec is the single deliverable for the agreed feature and supersedes the earlier simultaneous-speech presentation approach. The older completed overlap ticket is historical context, not the implementation to restore.
- The rejected feature was removed in commit `4946bca254fd70c7969f938b19776bf8f6380060` because interjections could appear after the surrounding speaker's later speech. Its replacement introduced the global word-ordering behavior addressed here.
- The user approved the product rules through the design session and confirmed that saving authoritative Reading Turns means saving the readable conversation once, before UI/export/AI consumption.
- The main research conclusion is modest: clear activity boundaries plus the agreed interval relationships are sufficient to target the reported problem. An additional local model is permitted, not presumed necessary.
- Detailed source findings, primary-source citations, alternatives, and chronological decisions are retained in the [overlapping-speech Reading Turn research note](../../docs/research/overlapping-speech-reading-turns.md). Its consolidated agreement overrides earlier exploratory proposals.
- At specification time no prototype or implementation had been produced. Implementation status is recorded above. No private audio has been inspected, and no measured quality improvement on the affected real recordings is claimed.

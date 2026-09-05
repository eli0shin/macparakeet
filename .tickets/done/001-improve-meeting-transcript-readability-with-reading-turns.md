---
Assigned-To:
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## Problem Statement

MacParakeet meeting transcripts are difficult to read after a long meeting.

The Timed view exposes fine-grained word timestamps, diarization boundaries, and capture-source transitions as visible transcript boundaries. Small timing differences, uncertain speaker assignments, overlap, and residual microphone/system duplication can therefore create many short speaker cards. This can happen even with a headset, where acoustic bleed is absent.

The Text view has the opposite failure. It can render the meeting as one large paragraph. MacParakeet has deterministic paragraph-building and optional AI formatting capabilities, but the main meeting reading surface does not preserve one coherent structure across speaker attribution, paragraphing, and playback. Long meetings can also exceed the current whole-transcript AI formatting limit.

The user prefers conservative grouping: when attribution is uncertain, MacParakeet should preserve a larger readable block instead of creating several small blocks. Fine timestamps must remain available for playback and evidence, but they must not define the primary reading structure.

## Solution

Present completed meetings as a sequence of **Reading Turns**.

A Reading Turn is a contiguous, readable block attributed to one speaker. It retains start and end times as metadata and can contain multiple paragraphs when one person speaks for a long time.

MacParakeet will derive Reading Turns from the existing source-aware words and diarization evidence. It will form utterances inside each capture source before it reconciles remote-speaker identity. It will assign remote speakers from aggregate evidence across an utterance, smooth weak short-lived speaker changes, preserve deterministic microphone identity, and represent genuine overlap without alternating individual words between speakers.

The completed-meeting transcript will use Reading Turns as its default human-facing structure. Each turn will show one speaker header and one quiet timestamp. Long turns will split into readable paragraphs without repeating the speaker header. Fine timestamps will remain available for seeking, search, exports that require timing, and accessibility actions, but they will not create a visible row for every small segment.

MacParakeet will preserve the original transcript evidence. Readability cleanup will create a derived presentation and will not overwrite raw words, source identity, timings, or diarization regions.

## User Stories

1. As a meeting participant, I want the transcript grouped into stable speaker blocks, so that I can read a long meeting as a conversation.
2. As a meeting participant, I want MacParakeet to prefer larger blocks when speaker evidence is uncertain, so that minor diarization mistakes do not fragment the transcript.
3. As a meeting participant, I want one speaker heading per Reading Turn, so that the speaker identity is clear without repeated labels.
4. As a meeting participant, I want a long statement from one speaker split into readable paragraphs, so that it does not become one dense wall of text.
5. As a meeting participant, I want paragraph boundaries to preserve the current speaker, so that paragraph formatting does not invent speaker changes.
6. As a meeting participant, I want timestamps to be visually secondary, so that the transcript reads as prose instead of a list of technical events.
7. As a meeting participant, I want the start time of a Reading Turn available, so that I can navigate to the matching audio when needed.
8. As a meeting participant, I want to select text across paragraphs in a Reading Turn, so that I can copy a coherent passage.
9. As a meeting participant, I want playback to follow the active Reading Turn, so that transcript navigation remains synchronized with the recording.
10. As a meeting participant, I want clicking a Reading Turn timestamp to seek to its start, so that existing playback navigation remains useful.
11. As a meeting participant, I want fine timestamps available through hover, focus, or explicit timed actions, so that detail is available without dominating the page.
12. As a meeting participant, I want microphone speech consistently identified as Me, so that remote-speaker diarization cannot relabel my clean microphone track.
13. As a meeting participant using a headset, I want simultaneous mic and system words represented as overlap rather than rapid speaker alternation, so that clean source isolation still produces readable output.
14. As a meeting participant using speakers, I want duplicated far-end speech to be treated as a separate acoustic-bleed problem, so that transcript grouping does not hide or misdiagnose source contamination.
15. As a meeting participant, I want system-audio words assigned to a remote speaker from the evidence across a complete utterance, so that one noisy word boundary cannot create a new turn.
16. As a meeting participant, I want unattributed system words to inherit the stable speaker of their utterance when possible, so that the fallback Others identity does not appear as an extra participant.
17. As a meeting participant, I want a short uncertain speaker fragment to remain Unknown or inherit stable context, so that MacParakeet does not invent a confident identity.
18. As a meeting participant, I want a genuine short interjection retained, so that conservative grouping does not delete another speaker's contribution.
19. As a meeting participant, I want the surrounding speaker's long statement to remain visually continuous around a short interjection, so that a backchannel does not make the page look fragmented.
20. As a meeting participant, I want genuine overlapping speech represented explicitly, so that both contributions remain visible without being interleaved word by word.
21. As a meeting participant, I want adjacent utterances from the same speaker merged across short pauses, so that normal hesitation does not create another block.
22. As a meeting participant, I want a long pause to influence paragraph or turn boundaries, so that clear conversational breaks remain visible.
23. As a meeting participant, I want sentence punctuation to influence paragraph boundaries, so that paragraphs end at natural reading points.
24. As a meeting participant, I want maximum sentence and word limits for paragraphs, so that a long monologue remains scannable.
25. As a meeting participant, I want conservative filler-word cleanup in the readable transcript, so that repeated ums and uhs do not make long passages harder to read.
26. As a meeting participant, I want repeated adjacent speech artifacts cleaned from the readable transcript, so that STT repetition does not distract from the conversation.
27. As a meeting participant, I want custom vocabulary corrections preserved in Reading Turns, so that names and project terms remain correct.
28. As a meeting participant, I want raw transcript evidence retained behind readable cleanup, so that I can recover or inspect the original transcription.
29. As a meeting participant, I want transcript editing to remain possible, so that I can correct wording after transcription.
30. As a meeting participant, I want speaker renaming to update every Reading Turn for that speaker, so that the transcript stays consistent.
31. As a meeting participant, I want a non-blocking way to correct the expected number of speakers, so that I can improve remote-speaker grouping without interrupting every completed meeting.
32. As a meeting participant, I want Auto speaker count when I do not know the participant count, so that the feature remains simple by default.
33. As a meeting participant, I want an exact or bounded speaker count used only when I provide it, so that an incorrect assumption does not silently damage attribution.
34. As a meeting participant, I want the same Reading Turn structure in the meeting detail view and readable text exports, so that copied and exported transcripts match what I read.
35. As a meeting participant, I want subtitle exports to keep subtitle-specific cue timing, so that readability changes do not damage caption formats.
36. As a meeting participant, I want summaries and chat to receive speaker-aware readable blocks, so that AI features retain who said what.
37. As a meeting participant, I want one-hour meetings to remain responsive while scrolling, selecting, and seeking, so that improved readability does not cause a performance regression.
38. As a meeting participant, I want meetings without word timestamps to retain a useful plain-text fallback, so that text-only engines still produce readable output.
39. As a meeting participant, I want meetings without diarization to group at least by microphone and system source, so that the transcript remains useful when speaker detection is unavailable.
40. As a meeting participant, I want microphone-only meetings to produce readable paragraphs without unnecessary speaker chrome, so that single-source meetings remain simple.
41. As a meeting participant, I want system-only meetings to use remote Reading Turns when diarization is available, so that remote discussions remain structured.
42. As a meeting participant, I want manually edited transcript text clearly distinguished from regenerated timed structure, so that MacParakeet does not imply that an edit changed the audio evidence.
43. As a keyboard user, I want Reading Turn timestamps, speaker rename controls, and copy actions to remain accessible, so that the new layout is fully operable without a pointer.
44. As a VoiceOver user, I want each Reading Turn announced with speaker, start time, and text in a sensible order, so that the transcript has a coherent accessibility structure.
45. As a user who searches within a transcript, I want matches to scroll to the containing Reading Turn and paragraph, so that find navigation still works after grouping changes.
46. As a user who copies a Reading Turn, I want an option to include its speaker and start time, so that the copied passage keeps useful context.
47. As a user who disables cleanup, I want the same Reading Turn structure with verbatim text, so that readability structure is independent of wording changes.
48. As a privacy-conscious user, I want deterministic Reading Turn assembly to run locally, so that basic transcript readability never requires a cloud model.
49. As a privacy-conscious user, I want optional AI formatting to follow my configured provider choice, so that no new network behavior is introduced implicitly.
50. As a maintainer, I want raw evidence and readable presentation modeled separately, so that diarization tuning does not directly control UI fragmentation.
51. As a maintainer, I want one shared Reading Turn result consumed by all completed-meeting reading surfaces, so that Text and Timed views cannot drift into contradictory structures.
52. As a maintainer, I want readability metrics for short turns and isolated speaker flips, so that improvements are measured against the reported problem instead of diarization error rate alone.
53. As a maintainer, I want headset and speaker-mode fixtures evaluated separately, so that acoustic bleed and transcript assembly defects are not conflated.
54. As a maintainer, I want current raw words and diarization records preserved, so that this feature can be reversed or retuned without data loss.
55. As a maintainer, I want a throwaway UI prototype evaluated before the final presentation is selected, so that Conversation, Reading, and Hybrid layouts can be compared on identical noisy data.

## Implementation Decisions

- Introduce Reading Turn as the canonical human-facing meeting transcript unit.
- A Reading Turn owns a stable identity, speaker identity, capture source, start time, end time, readable text, paragraph structure, underlying word references, and overlap state.
- Preserve raw word timestamps, source IDs, confidence values, diarization regions, and retained audio as canonical evidence.
- Do not use ASR chunks, individual word timestamps, or individual diarization transitions as direct visible block boundaries.
- Form utterances independently within the microphone and system sources before the sources are merged for presentation.
- Keep microphone identity deterministic as Me in dual-source meetings.
- Apply remote-speaker reconciliation only to system-source utterances.
- Assign a remote speaker from aggregate diarization overlap across an utterance or sentence-sized unit.
- Treat continuity with the preceding and following stable speaker as evidence when an isolated assignment is short or weak.
- Prefer an existing stable speaker over a new visible split when evidence is ambiguous.
- Do not let a fragment with less than approximately one second of reliable exclusive speech define a new remote speaker by itself. The final threshold must be calibrated with fixtures.
- Let unattributed system words inherit the dominant speaker of their containing utterance when one exists.
- Do not expose the generic system fallback and a refined system speaker as separate participants within one otherwise stable utterance.
- Preserve a genuine short interjection as content, but allow the surrounding longer Reading Turn to remain visually continuous.
- Represent genuine cross-source overlap explicitly. Do not linearize overlapping microphone and system words into alternating Reading Turns.
- Merge adjacent same-speaker utterances across a short gap. Start evaluation with the existing 2.5-second reading threshold and tune from fixture results.
- Split long same-speaker content into paragraphs without creating a new Reading Turn or repeating the speaker header.
- Start paragraph calibration from the existing deterministic policy of three sentences, 80 words, or a 2.5-second pause.
- Use one quiet timestamp at the Reading Turn header or first paragraph. Preserve detailed timestamps for playback and explicit timed actions.
- Make the dense Reading layout the expected production default unless the prototype shows a clear advantage for Conversation or Hybrid.
- Prototype Conversation, Reading, and Hybrid presentations against the same deterministic noisy transcript data before selecting final visual details.
- Keep the prototype throwaway and separate from production implementation.
- Apply conservative deterministic cleanup to derived Reading Turn text. Cleanup can remove the existing always-safe filler set, normalize whitespace and punctuation, remove obvious adjacent repetition, and apply custom vocabulary.
- Do not apply dictation-only snippet expansion, trailing paste actions, or insertion styling to meetings.
- Keep cleanup independent from Reading Turn grouping. Disabling cleanup must not change speaker or paragraph boundaries.
- Do not overwrite the verbatim word model when cleanup changes displayed wording.
- Optional AI formatting must operate on bounded stable Reading Turns or bounded groups, not one unbounded meeting string.
- Optional AI formatting must preserve Reading Turn and speaker identity and must not decide diarization.
- Optional AI formatting must retain original text and fall back to it when output is empty, excessively changed, or fails preservation validation.
- The current whole-transcript AI formatter remains compatible during migration, but the new meeting reading path must not depend on it.
- The first production slice will derive Reading Turns from existing persisted evidence and will not require a database migration.
- The existing durable evidence remains the recovery source if Reading Turn rules change in a later release.
- Text-only meetings will use deterministic prose paragraphing without claiming speaker or timing precision that is unavailable.
- Subtitle formats retain their current cue-oriented model. Reading Turns are for document and meeting-reading surfaces.
- Readable TXT and Markdown meeting output should use the same Reading Turn grouping as the UI when speaker/timing evidence is available.
- Speaker-count correction must be non-blocking. The default completion flow must continue in the background without a mandatory post-call modal.
- Speaker-count correction will accept exact, bounded, or Auto behavior and reuse the existing diarization constraint support.
- The UI meaning of speaker count is total people including Me. The meeting pipeline converts this to the remote count for system-only diarization.
- Acoustic echo cancellation and microphone/system duplicate suppression remain a separate processing concern. This feature can expose duplicate evidence in fixtures but must not hide duplicated text by arbitrary block merging.
- The primary implementation seam is one pure meeting transcript presentation builder. It consumes a completed meeting's existing transcript evidence and returns the full ordered Reading Turn document. Grouping, smoothing, overlap representation, cleanup boundaries, and paragraphing are tested through this seam.
- Existing lower-level diarization and word-alignment modules remain evidence producers. Avoid adding separate public seams for each internal heuristic.
- The presentation builder output becomes the shared input for completed-meeting UI, readable copy/export, and AI-context rendering where practical.
- Update the governing meeting, data-model, text-processing, and UI specifications when final behavior is implemented.
- Update affected meeting artifact or export contracts if externally visible serialized output changes.

## Testing Decisions

- Test externally observable Reading Turn documents, not private helper methods or individual heuristic branches.
- Use the pure meeting transcript presentation builder as the primary test seam. Each test supplies source-aware transcript evidence and asserts the ordered Reading Turns, speakers, text, paragraphs, timing range, and overlap state.
- Prefer one high-level expectation per scenario that shows the complete document shape. Avoid tests that only pin an internal threshold without proving user-visible behavior.
- Add characterization coverage for the current reported failures before changing behavior.
- Test clean headset dialogue with no acoustic bleed.
- Test speaker-mode duplicate content as a separate fixture and confirm Reading Turn grouping does not misclassify duplicate suppression as diarization.
- Test word-level microphone/system timestamp interleaving and assert that it does not produce alternating one-word Reading Turns.
- Test an isolated A/B/A remote-speaker flip and assert conservative smoothing.
- Test a genuine sustained A/B/A exchange and assert that the real speaker change remains.
- Test unattributed system words between words from the same remote speaker and assert contextual inheritance.
- Test a generic system fallback between refined remote-speaker words and assert that it does not create an extra visible participant.
- Test a short genuine backchannel and assert that its content remains present without unnecessarily fragmenting the surrounding long turn.
- Test simultaneous mic/system speech and assert explicit overlap representation.
- Test simultaneous remote speakers when diarization provides overlap evidence.
- Test long same-speaker monologues and assert paragraph boundaries without repeated speaker turns.
- Test paragraph boundaries at punctuation, maximum sentence count, maximum word count, and long pauses through complete Reading Turn output.
- Test that short pauses do not create extra Reading Turns.
- Test that cleanup removes only the approved conservative fillers and preserves meaning-sensitive words.
- Test that cleanup does not mutate raw word evidence.
- Test that cleanup disabled and enabled produce identical Reading Turn identity, speaker attribution, and timing.
- Test custom vocabulary corrections in displayed Reading Turn text.
- Test microphone-only, system-only, dual-source, no-diarization, no-word-timestamp, and empty-transcript cases.
- Test exact, bounded, and Auto speaker-count behavior through the existing transcription-service orchestration seam with a mock diarization service.
- Test speaker rename through the existing view-model/repository behavior and assert that all derived Reading Turns resolve the new label.
- Test find navigation against Reading Turn and paragraph anchors through the existing transcript find model seam.
- Test copy output as pure formatting behavior, including speaker and timestamp options.
- Test accessibility labels and stable identities using the existing transcript speaker-turn accessibility test patterns.
- Add a performance test with a synthetic one-hour transcript. Building the Reading Turn document and scrolling the resulting view must remain bounded and must not create one view per word.
- Use prior art from existing transcript segmenter tests, meeting transcript finalizer tests, diarization merger tests, paragraph builder tests, transcription-service tests, transcript find tests, and speaker-turn identity/accessibility tests.
- Evaluate the UI prototype manually with identical synthetic data in Conversation, Reading, and Hybrid modes. Record the selected variant and rejection reasons before production visual implementation.
- Evaluate real consented headset and speaker-mode recordings before declaring the feature complete.
- Track readability metrics in fixture evaluation: Reading Turns per minute, median words per turn, turns shorter than three words, isolated A/B/A flips, fallback-speaker transitions, duplicate simultaneous phrase rate, and paragraphs over 120 words.
- Retain standard diarization quality checks where labelled audio permits them, but do not use diarization error rate as the only acceptance measure.

## Out of Scope

- Replacing FluidAudio's offline diarization model.
- Adding a cloud diarization provider as the default path.
- Implementing streaming/live speaker diarization.
- Building persistent cross-meeting speaker recognition or automatic voiceprint enrollment.
- Implementing general acoustic echo cancellation in this ticket.
- Rewriting the existing microphone/system duplicate reconciler without speaker-mode fixture evidence.
- Changing capture permissions, audio routing, retained-audio policy, or recording lifecycle.
- Changing raw transcript words, timing evidence, or diarization regions to match presentation output.
- Turning MacParakeet into a Descript-style media editor.
- Word-level karaoke highlighting.
- Changing SRT or VTT cue semantics to use Reading Turns.
- Mandatory post-call speaker-count dialogs.
- Automatic deletion of short interjections or uncertain speech.
- Using an LLM to decide who spoke.
- Requiring an external AI provider for baseline transcript readability.
- Summarization, action-item extraction, or meeting-title changes except where they consume the new readable speaker structure.
- Final acoustic-quality tuning without a consented real recording corpus.

## Further Notes

The governing product rule is conservative grouping:

> When acoustic speaker evidence is ambiguous, preserve a larger existing Reading Turn. Do not create a new visible speaker block from one weak timestamp transition.

Timestamps remain important. They become metadata for playback and evidence instead of the visible document hierarchy.

The current codebase already contains several foundations that should be reused: separate meeting source tracks, source-aware word timestamps, system-only remote diarization, diarization speaker-count constraints, deterministic paragraph construction, transcript find, speaker rename, readable meeting exports, and optional transcript formatting.

Meetily establishes the minimum acceptable behavior with source-specific VAD utterances, utterance-level overlap assignment, exact speaker-count support, adjacent same-speaker merging, and conversation blocks. The desired MacParakeet result adds denser long-form reading paragraphs and conservative uncertainty handling.

Research context is available in the repository's meeting transcript comparison and state-of-the-art research notes.

## Resolution

Completed the Reading Turn program through tickets 002–010. The delivered system includes the selected Conversation layout, pure presentation boundary, utterance-level remote attribution, explicit overlap and interjections, conservative cleanup and paragraphing, bounded optional AI formatting, shared copy/export/AI consumers, non-blocking speaker-count correction, and private real-meeting qualification. Authorized headset and speaker-mode results support keeping Conversation-style Reading Turns as the default. Final qualification merged in PR #10 at commit `9c762aa6a0666ea2dee4b92f5bf9382a1b846cf8`.

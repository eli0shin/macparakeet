---
Assigned-To: macparakeet@047-group-consecutive-same-speaker-meeting-transcript-blocks
Tags: []
Parent:
Blocked-By: []
---

# Group consecutive same-speaker meeting transcript blocks

## User request

Never display multiple consecutive turns from the same speaker. Collapse each consecutive same-speaker run into one displayed turn, not separate turns with hidden headers. The collapsed turn has exactly one speaker header, one timestamp, and one seek target at its start. No per-segment seek targets in the UI.

This explicit user decision supersedes the earlier requirement to preserve individual contribution seek targets.

## Scope and behavior

- Collapse every consecutive run from the same resolved speaker into one displayed turn in the completed-meeting UI. Compare speaker identity, not the displayed name: two different speakers renamed to the same label remain distinct.
- Show exactly one compact speaker byline and one timestamp at the collapsed turn's start. That timestamp is its sole seek target. Do not retain individual contribution timestamps, seek controls, hidden per-segment UI targets, or separate same-speaker rows.
- Keep all text in order, with paragraph breaks inside the single turn. User visual feedback on PR #54: there must be only ONE blank line between points/paragraphs, not two. Ensure combined paragraph separators and view spacing do not produce a double blank gap; regenerate visual evidence after correcting it. Pauses of any length, existing segment boundaries, AI formatting boundaries, and overlap metadata must not create consecutive displayed turns for the same speaker.
- Only an intervening contribution from a different speaker ends a consecutive same-speaker run. Preserve that speaker's contribution and transcript order. Overlap is not an exception to the no-consecutive-same-speaker-turns rule.
- Preserve raw words, timing, speaker attribution, and overlap evidence internally. Internal evidence and AI override mappings are not independent UI turns or seek targets.
- Playback focus and transcript navigation operate on the collapsed displayed turn. Search/citation navigation must resolve to that containing turn rather than restore internal segment targets. Keep text selection, copying, and keyboard/accessibility behavior usable at the collapsed-turn level.
- Follow the existing compact, borderless transcript design. Do not add cards, bubbles, or a new overlap container.
- Apply to existing and new saved meetings without retranscription or a storage migration. Keep file/URL transcript presentation, live preview, exports, and AI-context contracts unchanged in this UI ticket.

## Example

```text
Before                         After
Me · 10:00                     Me · 10:00
First point.                   First point.

Me · 10:08                     Another point after a pause.
Another point after a pause.

Alex · 10:15                   Alex · 10:15
Response.                     Response.
```

The collapsed Me turn has only the 10:00 timestamp and seek target. There is no 10:08 target in the UI.

## Acceptance and verification

- A → A → A becomes exactly one displayed turn with all text, paragraph breaks, one speaker header, one start timestamp, and one start seek target. This remains true across long pauses and internal segment/formatting boundaries.
- No two adjacent displayed turns have the same resolved speaker. Assert this invariant across overlap/interjection cases, renamed speakers, AI-formatted and deterministic text, and legacy meetings.
- A → B → A remains three displayed turns. Different speaker identities with equal display names remain distinct.
- No individual contribution timestamp, seek control, hidden UI seek target, separate playback-focus row, or accessibility turn survives inside a collapsed turn.
- Seeking uses the collapsed turn's start. Playback highlighting and search/citation navigation use the collapsed turn. Selection, copy, and keyboard/accessibility behavior work with this single-turn model.
- Add focused grouping and interaction tests. Keep the existing 401-row scrolling/performance regression passing; do not restore incorrect scroll targets or lazy-layout stalls.
- Provide rendered before/after evidence and request user visual approval before merge.
- Update applicable UI documentation and any changed presentation contract in the same change.

## Starting points and related work

- `Sources/MacParakeet/Views/Transcription/TranscriptResultView.swift`
- `Sources/MacParakeetCore/TextProcessing/MeetingTranscriptPresentationBuilder.swift`
- `spec/04-ui-patterns.md`
- `spec/contracts/meeting-reading-turn-consumers.md`
- Completed ticket `026-implement-compact-borderless-meeting-transcript` records the current Compact byline design. Its per-Reading-Turn timestamp/navigation behavior is deliberately superseded here for consecutive same-speaker runs.
- `docs/research/meeting-ai-cleanup-request-sizing.md` and `docs/research/show-me-meeting-ai-cleanup.html` record the investigation that led to this request.
- Related ticket `048-batch-meeting-ai-cleanup-across-turns-with-a-20000-character-text-budget` changes model request grouping separately. Neither ticket blocks the other. Display grouping must not determine AI batch size.

## Resolution

PR #54 merged into main as `a1b8857a4fc957d377cc47d9f4277e9b6904d148` from reviewed head `f914cc883ba627092b57866b6d081ab470c7c9a1`. CI run `34295216360` passed. Independent review found no actionable findings and confirmed that the approved rendering and rendering code remain unchanged after the main update. User visual approval is recorded in PR comment 5593762589. Both generated images inspected; canonical evidence, exports, and AI context remain unchanged. Merge compatibility passed.


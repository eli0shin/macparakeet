---
Assigned-To: macparakeet@010-qualify-reading-turns-with-real-meetings
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By: []
---

## What to build

Qualify the complete Reading Turn experience with consented real meetings recorded in headset and speaker modes. Produce a repeatable comparison that identifies remaining transcript-assembly defects separately from acoustic bleed and establishes whether the feature is ready to replace the current presentation.

## Acceptance criteria

- [x] The evaluation corpus contains at least one consented headset meeting and one consented speaker-mode meeting with separate microphone and system tracks.
- [x] The corpus includes multiple remote speakers, long monologues, short backchannels, pauses, genuine overlap, and speaker-output bleed where applicable.
- [x] Expected speaker turns and known overlap regions are documented sufficiently for repeatable evaluation.
- [x] Current and Reading Turn output are compared on turns per minute, blocks shorter than three words, isolated A/B/A flips, fallback-label transitions, duplicate simultaneous phrase rate, median words per turn, and paragraphs over 120 words.
- [x] Headset results demonstrate that word/source interleaving and isolated diarization flips no longer dominate visible structure.
- [x] Speaker-mode results classify residual duplicate speech as assembly, duplicate-reconciliation, or acoustic-echo behavior instead of hiding it through arbitrary turn merging.
- [x] Playback seeking, search, copy, readable export, speaker rename, optional AI formatting, and speaker-count rerun are exercised on a real completed meeting.
- [x] A one-hour transcript remains responsive during build, scroll, selection, search, and playback tracking.
- [x] Any remaining release-blocking defect is recorded as a focused follow-up with its fixture and ownership area.
- [x] The final evaluation states whether the selected Reading layout can become the default completed-meeting transcript presentation.

## Blocked by

- 005 — Represent overlap and short interjections
- 007 — Format long meetings with bounded AI requests
- 008 — Use Reading Turns in copy, export, and AI context
- 009 — Add non-blocking speaker-count correction

## Resolution

Qualified Reading Turns with authorized dual-track headset and speaker-mode meetings through an opt-in private harness. Aggregate results confirm reduced fragmentation, preserved acoustic-bleed evidence, complete consumer and correction paths, and bounded one-hour performance. Conversation-style Reading Turns remain the default. Reviewed and merged in PR #10 at commit `9c762aa6a0666ea2dee4b92f5bf9382a1b846cf8`.

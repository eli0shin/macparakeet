---
Assigned-To:
Tags:
  - ready-for-agent
Parent: 001-improve-meeting-transcript-readability-with-reading-turns
Blocked-By:
  - 008-use-reading-turns-in-copy-export-and-ai-context
---

## What to build

Qualify the complete Reading Turn experience with consented real meetings recorded in headset and speaker modes. Produce a repeatable comparison that identifies remaining transcript-assembly defects separately from acoustic bleed and establishes whether the feature is ready to replace the current presentation.

## Acceptance criteria

- [ ] The evaluation corpus contains at least one consented headset meeting and one consented speaker-mode meeting with separate microphone and system tracks.
- [ ] The corpus includes multiple remote speakers, long monologues, short backchannels, pauses, genuine overlap, and speaker-output bleed where applicable.
- [ ] Expected speaker turns and known overlap regions are documented sufficiently for repeatable evaluation.
- [ ] Current and Reading Turn output are compared on turns per minute, blocks shorter than three words, isolated A/B/A flips, fallback-label transitions, duplicate simultaneous phrase rate, median words per turn, and paragraphs over 120 words.
- [ ] Headset results demonstrate that word/source interleaving and isolated diarization flips no longer dominate visible structure.
- [ ] Speaker-mode results classify residual duplicate speech as assembly, duplicate-reconciliation, or acoustic-echo behavior instead of hiding it through arbitrary turn merging.
- [ ] Playback seeking, search, copy, readable export, speaker rename, optional AI formatting, and speaker-count rerun are exercised on a real completed meeting.
- [ ] A one-hour transcript remains responsive during build, scroll, selection, search, and playback tracking.
- [ ] Any remaining release-blocking defect is recorded as a focused follow-up with its fixture and ownership area.
- [ ] The final evaluation states whether the selected Reading layout can become the default completed-meeting transcript presentation.

## Blocked by

- 005 — Represent overlap and short interjections
- 007 — Format long meetings with bounded AI requests
- 008 — Use Reading Turns in copy, export, and AI context
- 009 — Add non-blocking speaker-count correction

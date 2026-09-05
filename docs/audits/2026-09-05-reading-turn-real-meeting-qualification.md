# Reading Turn Real-Meeting Qualification — 2026-09-05

> Status: qualified with two private, consented, dual-track meeting sessions on
> commit `945dbd4a`. The recordings, transcripts, meeting IDs, paths, and derived
> text remain outside git. This document contains only safe aggregate evidence
> and content-free timing annotations.

## Decision

**Keep the Conversation-style Reading Turn layout as the default completed-meeting transcript presentation.**

The headset fixture improved from 75 current timed blocks to 13 Reading Turns.
The speaker fixture improved from 39 blocks to 11 Reading Turns. Reading Turns
removed the visible word/source interleaving and weak label fragmentation that
motivated the project. The retained speaker-mode duplicate stayed measurable;
the presentation did not hide it by merging text.

No release-blocking transcript-assembly defect was found. Speaker-mode acoustic
bleed remains an audio/source-reconciliation concern, not a Reading Turn release
blocker. Auto diarization also found one more remote cluster than expected in the
speaker fixture. The existing non-blocking exact-count rerun constrained the same
real system track to the expected two remote speakers.

## Corpus and consent

The fixture owner explicitly authorized these sessions for ticket 010. Both are
completed MacParakeet meetings with separate raw microphone and system tracks.
The private corpus is not committed.

| Alias | Mode | Duration | Words | Expected remote speakers | Coverage |
|---|---|---:|---:|---:|---|
| H1 | Headset | 235.008 s | 541 | 2 | Long local and remote statements, two remote speakers, short backchannel, pauses, deliberate cross-source overlap |
| S1 | Speakers | 143.603 s | 390 | 2 | Long local and remote statements, multiple remote voices, pauses, source handoff overlap, audible speaker-output bleed |

### Content-free annotations

Times are relative to meeting start. They let a future evaluator inspect the
same behavior without putting transcript content in git.

| Fixture | Region | Expected evidence |
|---|---|---|
| H1 | 3.5–53.3 s | Long local-speaker statement |
| H1 | 55.5–104.9 s | Long first-remote-speaker statement |
| H1 | 79.5–85.0 s | Deliberate local speech over the first remote speaker |
| H1 | 117.9–119.5 s | Short local backchannel during remote speech |
| H1 | 128.9–130.7 s | Short deliberate local/remote overlap |
| H1 | 143.4–174.9 s | Long second-remote-speaker statement |
| H1 | 104.9–109.8 s and 174.9–180.8 s | Clear pauses |
| S1 | 2.6–37.9 s | Long local-speaker statement |
| S1 | 37.7–37.9 s | Source handoff with a small genuine overlap |
| S1 | 43.5–70.8 s | Long first-remote-speaker statement |
| S1 | 67.8–68.6 s | Matching microphone/system phrase caused by speaker-output bleed |
| S1 | 76.5–79.2 s | Short remote exchange between two voices |
| S1 | 87.8–108.2 s | Long remote monologue |
| S1 | 116.5–130.6 s | Second remote voice after a seek/pause |
| S1 | 130.9–133.5 s | Residual remote speech on the microphone source |

## Repeatable method

`ReadingTurnQualificationTests` is opt-in because it consumes private data and
runs the local diarization model. It validates dual-track inputs, derives the
current timed-segment presentation and Reading Turn presentation from the same
canonical evidence, exercises shared completed-meeting consumers, runs an exact
speaker-count correction at the diarization boundary, projects the real headset
evidence to one hour, and writes aggregate JSON only.

```bash
MACPARAKEET_READING_TURN_QUALIFICATION=1 \
MACPARAKEET_READING_TURN_HEADSET_SESSION=/private/headset/session \
MACPARAKEET_READING_TURN_SPEAKER_SESSION=/private/speaker/session \
MACPARAKEET_READING_TURN_RESULTS_FILE=/tmp/reading-turn-results.json \
swift test --filter ReadingTurnQualificationTests
```

Definitions:

- **Current**: one block per persisted `TranscriptSegmentRecord`, matching the
  prior timed-segment presentation boundary.
- **Reading**: output from `MeetingTranscriptPresentationBuilder` using the same
  words, speaker roster, and retained diarization regions.
- **Turns/minute**: displayed blocks divided by the timed presentation span.
- **Short block**: fewer than three referenced words.
- **A/B/A candidate**: a different speaker ID between equal adjacent speaker IDs.
  The aggregate counter intentionally includes genuine overlap and source
  exchanges; the classification below separates these from diarization defects.
- **Fallback transition**: a speaker boundary to or from generic `system`.
- **Duplicate simultaneous phrase**: a matching run of at least two microphone
  and system words, with corresponding word starts no more than 1.5 seconds
  apart. It is measured from source evidence before presentation, so grouping
  cannot reduce the score.
- **Long paragraph**: more than 120 whitespace-separated words.

## Results

| Fixture | Presentation | Turns/min | Blocks <3 words | A/B/A candidates | Fallback transitions | Duplicate phrases (per min) | Median words/turn | Paragraphs >120 words |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| H1 | Current | 19.737 | 35 | 33 | 12 | 0 (0.000) | 4 | 0 |
| H1 | Reading | 3.421 | 1 | 7 | 2 | 0 (0.000) | 19 | 0 |
| S1 | Current | 17.095 | 7 | 4 | 6 | 1 (0.438) | 7 | 0 |
| S1 | Reading | 4.822 | 2 | 4 | 0 | 1 (0.438) | 16 | 0 |

### Headset classification

Reading Turns reduced visible blocks by 82.7%, short blocks by 97.1%, raw A/B/A
candidates by 78.8%, and fallback transitions by 83.3%. Review of the seven
remaining A/B/A candidates found deliberate local/remote overlap, a sustained
remote exchange, and one short generic-system contribution. No isolated weak
remote diarization flip remained. Word/source interleaving and isolated flips no
longer dominate the visible structure.

### Speaker-mode classification

The source-level duplicate count stayed at one before and after Reading Turn
assembly. Its matching microphone/system timing and the headset fixture's zero
count classify it as **acoustic echo/speaker-output bleed**, not an assembly
defect. The separate residual remote phrase on the microphone source is also
source contamination. Reading Turn assembly kept this evidence visible.

No case was classified as a Reading Turn assembly duplicate. No evidence showed
that arbitrary turn merging concealed a duplicate-reconciliation failure.

## Completed-meeting behavior exercised

The harness exercised the real derived document through:

- word-reference and playback-time seeking;
- case-insensitive paragraph search;
- passage text selection inputs and complete-document copy rendering;
- readable plain-text and Markdown export rendering;
- remote-speaker rename and Reading Turn rebuild;
- bounded optional AI formatting with a local identity request, including
  content-preservation validation;
- exact speaker-count conversion and real constrained diarization.

The speaker fixture's exact rerun requested two remote speakers, returned two,
and completed in 1,385.0 ms with warm models on an M1 Pro. The harness called
the production correction service with a private temporary session copy and an
in-memory database. It verified persisted reattribution, rebuilt Reading Turns,
and unchanged lexical word evidence without modifying the original or user database.

## One-hour responsiveness

The harness repeated the authorized headset evidence in memory to a 60-minute
projection. It did not write the projected transcript.

| Measure | Result |
|---|---:|
| Projected words | 8,434 |
| Reading Turns | 201 |
| Lazy scroll/selection units | 201 |
| Document build | 75.2 ms |
| Copy + search + 200 seek/scroll-target resolutions | 56.0 ms |

The production UI uses one selectable card per Reading Turn in a `LazyVStack`,
not one view per word. The measured projection keeps build, copy, search, and
playback tracking well below interactive latency, with only 201 scroll/selection
units for one hour. No responsiveness blocker was observed.

## Follow-up ownership

No release-blocking Reading Turn follow-up is required.

Two non-blocking quality observations stay in their existing ownership areas:

1. Speaker-output bleed belongs to audio capture/AEC and source duplicate
   reconciliation. S1 at 67.8–68.6 s is the retained private fixture region.
2. Auto speaker over-clustering belongs to offline diarization. S1 produced
   three remote clusters for two expected voices; the shipped exact-count rerun
   corrected the clustering boundary without changing transcript words.

These observations do not block the selected Reading layout from remaining the
default completed-meeting presentation.

# Reading Turn layout prototype

> **Throwaway prototype:** This folder is isolated from the Swift app. It has no production model, persistence, or migration.

## Question

Which completed-meeting presentation best supports long-form reading while it keeps uncertain attribution, overlap, timestamps, text selection, and playback visible?

Open the prototype:

```bash
open prototypes/reading-turn-layouts/index.html
```

Use the bottom switcher or the Left and Right Arrow keys. The shareable variants are:

- `?variant=conversation` — discrete conversation cards
- `?variant=reading` — continuous editorial document
- `?variant=hybrid` — topic-grouped scan view

Select a timestamp to move the playback-focus state. Transcript paragraphs use normal browser text selection.

## Fixed fixture

All variants render the same frozen set of 12 Reading Turns from an 05:51 synthetic meeting. The fixture includes:

- clean microphone and system turns;
- a 235-word monologue split into three paragraphs;
- interleaved microphone and system speech;
- an uncertain one-word A/B/A speaker flip;
- unattributed system words inherited by a stable utterance;
- a one-word backchannel during a continuing long turn;
- genuine cross-source overlap;
- duplicated speaker-mode speech retained on both sources.

Evidence notes make each stress case visible. They are prototype annotations, not proposed transcript chrome.

## Fixture evaluation

These values are computed from the frozen fixture and shown unchanged in each variant:

| Measure | Result |
|---|---:|
| Reading Turns per minute | 2.1 |
| Tiny blocks under 3 words | 2 |
| Median words per turn | 27.0 |
| Paragraphs over 120 words | 0 |

The long monologue is 235 words in one Reading Turn. Its three paragraphs are 84, 79, and 72 words, so paragraphing removes the wall of text without inventing speaker changes.

## Decision

**Select Reading (`?variant=reading`) as the production direction.**

Reading makes the transcript a continuous document. The speaker rail gives identity and one quiet start timestamp without making each timing boundary dominant. Paragraphs carry the visual hierarchy for long speech. The contained overlap treatment preserves both complete contributions. Playback focus remains clear without changing the document structure.

Reject **Conversation** as the default because repeated card edges give short and uncertain turns too much weight. It works well for rapid chat but fragments a long meeting and makes the 235-word turn feel like a message bubble.

Reject **Hybrid** as the default because topic rails add an editorial grouping that the available transcript evidence does not reliably provide. It scans well and its side-by-side overlap treatment is useful, but the extra hierarchy competes with speaker continuity.

For production, use Reading as the base and retain Hybrid's explicit overlap boundary. Do not carry the prototype evidence notes or synthetic topic labels into production.

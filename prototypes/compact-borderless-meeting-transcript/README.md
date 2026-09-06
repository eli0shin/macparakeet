# Compact borderless meeting transcript prototype

> **Throwaway prototype:** This folder is isolated from the Swift app. It uses only frozen synthetic data. It has no persistence, analytics, network requests, or production behavior.

## Question

Which compact, borderless completed-meeting transcript layout reduces vertical waste while speaker identity, renaming, timing, seeking, text selection, overlap evidence, and long-turn readability stay clear?

## Review

Open the published [compact-borderless-meeting-transcript artifact](https://artifacts.home.arpa/compact-borderless-meeting-transcript/) directly in a browser. No checkout, Xcode, server, or build tool is required.

CI also uploads `MacParakeet-compact-borderless-transcript-prototype` from the PR's [workflow run](https://github.com/moona3k/macparakeet/actions/workflows/ci.yml). Download it, unzip it, and open `index.html` to review the exact committed file.

For a local checkout, open:

```bash
open prototypes/compact-borderless-meeting-transcript/index.html
```

Use the bottom switcher or the Left and Right Arrow keys. Arrow keys do not change variants while the speaker rename field has focus.

- `?variant=byline` — compact speaker byline above each turn;
- `?variant=rail` — stable speaker-and-time rail beside the prose;
- `?variant=running` — timestamp gutter with the speaker name starting the prose.

During review:

1. Compare the measured height and full-turn count with the current-card representation.
2. Rename Nadia in the compact speaker overview and confirm the name updates in the transcript.
3. Select transcript text, including a long turn.
4. Select timestamps to move playback focus.
5. Inspect the adjacent turns marked `↗ overlap`; the frozen fixture retains their shared `overlapId` and exact time ranges without a visual wrapper.
6. Resize the window and confirm that the eight-speaker overview adds compact wrapped lines only when needed.

Record the selected variant, or a precise combination, on ticket `025`. Record the selection and reasons for rejecting the alternatives for implementation ticket `026` before completing this prototype ticket.

## Fixed fixture

All variants render the same 24 Reading Turns and eight speakers from one synthetic launch-readiness meeting. It includes:

- several long, multi-paragraph Reading Turns;
- short interjections;
- three genuine overlap groups, including a backchannel and a closing contribution;
- an active rename field in a wrapping speaker overview;
- per-speaker turn and word statistics;
- seekable timestamps and an initial playback-focused turn;
- enough content to compare scroll density.

The fixture and rename state stay in browser memory. Reloading restores the frozen fixture.

## Structural alternatives

- **A — Compact byline** keeps the familiar speaker-before-text sequence. It is the easiest transition from cards, but repeated headers still interrupt long reading.
- **B — Speaker rail** aligns identity and timing in a stable gutter. It supports scanning speaker changes, but gives less width to prose.
- **C — Running names** puts time in a narrow gutter and starts each block with the speaker. It is the densest document treatment, but identity has less visual separation from the transcript.

All three remove Reading Turn borders, bubble backgrounds, padded overlap wrappers, large internal padding, and large inter-turn gaps. The density strip compares the rendered active variant against an offscreen representation of the current card layout with the same fixture, width, and body type size.

## Decision

**Select A — Compact byline** for ticket `026`.

Use one speaker dot beside the name. Playback focus uses the left border only, without a gradient background. Keep A's familiar speaker-before-text sequence and compact borderless spacing.

Reject B because the fixed speaker rail takes width from long-form prose. Reject C because running names give speaker changes less separation than A. Both remain useful density references, but neither is the production base.

# Upstream changes since the fork diverged

Date: 2026-09-08

## Scope

This summary uses the requested three-dot comparison between `eli0shin/main` and `moona3k/main`. The branches share merge base [`02677ba7`](https://github.com/moona3k/macparakeet/commit/02677ba701608e2cd217ce60ea983368995e382b) from 2026-09-02. At inspection time, the fork head was `d0fe50b8`, the upstream head was [`a82ae130`](https://github.com/moona3k/macparakeet/commit/a82ae130a20636dc318cecd5c36ba8402190cb2f), and the comparison contained 291 upstream-only commits. The fork also had 105 commits that were not in upstream, so this is a summary of upstream work, not a claim that the branches can be fast-forwarded or that every upstream change is absent from equivalent fork code.

Primary comparison: [GitHub compare view](https://github.com/eli0shin/macparakeet/compare/main...moona3k%3Amacparakeet%3Amain)

## Feature summary

### Prompts and AI generation

- The prompt library became a versioned prompt manager. Built-in and custom prompts can be edited, soft-deleted, restored as a new version, organized into collections, and routed by meeting labels. Prompt history is immutable.
- Result prompts gained per-prompt inference settings: temperature, top-p, top-k, maximum output tokens, thinking mode, and reasoning effort where the selected provider supports them. Results retain the effective settings and provider/model receipt used for the request.
- Saved meetings gained an editable Notes tab with debounced autosave. Each result prompt can opt into meeting notes as context. Chat continues to use current committed notes.
- AI result, transcript chat, and live Ask output now use a shared rich Markdown renderer for headings, lists, code, tables, links, and math.
- AI provider setup is safer: failed draft tests or saves do not erase a working setup, corrupt metadata can be cleared, HTTP can be explicitly allowed for local endpoints, and provider redirect/output handling is stricter.

Sources: [development feature table](https://github.com/moona3k/macparakeet/blob/a82ae130a20636dc318cecd5c36ba8402190cb2f/spec/02-features.md#development-additions-after-073), [CLI 4.0 changelog](https://github.com/moona3k/macparakeet/blob/a82ae130a20636dc318cecd5c36ba8402190cb2f/Sources/CLI/CHANGELOG.md), [PR #959](https://github.com/moona3k/macparakeet/pull/959), [PR #961](https://github.com/moona3k/macparakeet/pull/961), [PR #957](https://github.com/moona3k/macparakeet/pull/957), [PR #968](https://github.com/moona3k/macparakeet/pull/968).

### Speaker attribution and transcription output

- Users can correct transcript-local speaker attribution with rename, assign, split, merge, remove, reset, Undo, and Redo operations. Effective corrections flow into display, retrieval, AI context, meeting artifacts, and exports without rewriting recognized words.
- Diarization moved to FluidAudio 0.15.6, uses its high-accuracy configuration, has safer cache/load handling, and can use a meeting attendee count as a cap-only speaker prior.
- TXT and Markdown timing output is grouped into readable paragraphs. Whole-meeting copy can include notes, generated results, and transcript content as one coherent unit.
- DAPT 1.0 export was added as an eighth export format, with timed speaker-attributed output when alignment exists and untimed fallback otherwise.
- Local files with multiple embedded audio tracks can expose and persist a selected track for transcription and retranscription.

Sources: [PR #960](https://github.com/moona3k/macparakeet/pull/960), [PR #974](https://github.com/moona3k/macparakeet/pull/974), [0.8.0 release inventory](https://github.com/moona3k/macparakeet/blob/a82ae130a20636dc318cecd5c36ba8402190cb2f/docs/qa/2026-09-07-0.8.0/release-inventory.md), [DAPT contract](https://github.com/moona3k/macparakeet/blob/a82ae130a20636dc318cecd5c36ba8402190cb2f/spec/contracts/dapt-export-v1.md).

### Library and vocabulary UI

- The Library gained persistent grid/list layouts across its main filters, contextual source labels, clearer audio/favorite actions, improved label-picker behavior, and new deterministic recording cover art.
- Long timestamped transcripts now load and scroll with less main-actor work, including fixes for the down-then-up scrolling freeze and stale content during navigation.
- Custom Words gained confirmed bulk deletion for selected rows or all current search matches. Deletion is atomic, and failed deletion keeps the selection for retry.

Sources: [PR #966](https://github.com/moona3k/macparakeet/pull/966), [PR #973](https://github.com/moona3k/macparakeet/pull/973), [PR #978](https://github.com/moona3k/macparakeet/pull/978), [PR #987](https://github.com/moona3k/macparakeet/pull/987), [PR #988](https://github.com/moona3k/macparakeet/pull/988), [PR #946](https://github.com/moona3k/macparakeet/pull/946).

### Meeting capture and completion

- Meeting startup now distinguishes “starting” from active recording. Stop/cancel remains available during startup, and late callbacks cannot revive a stopped or superseded session.
- Stop/finalization, back-to-back recording, writer timeout, lock ownership, recovery, retained audio, and capture-report logic were hardened. Capture quality uses retained frames, preserves healthy tracks, and distinguishes a digitally silent selected source without incorrectly marking a complete one-sided recording as partial.
- Users can turn off “Open app when meeting ends” and separately control the ready notification. Quiet completion still saves, refreshes the Library, and runs background auto-prompts without stealing focus.
- Routine recording feedback became quieter, while actionable capture failures remain visible.

Sources: [release-readiness integration #953](https://github.com/moona3k/macparakeet/pull/953), [quiet feedback #963](https://github.com/moona3k/macparakeet/pull/963), [0.8.0 release inventory](https://github.com/moona3k/macparakeet/blob/a82ae130a20636dc318cecd5c36ba8402190cb2f/docs/qa/2026-09-07-0.8.0/release-inventory.md), [meeting artifact contract](https://github.com/moona3k/macparakeet/blob/a82ae130a20636dc318cecd5c36ba8402190cb2f/spec/contracts/meeting-artifacts-v1.md).

### App controls, onboarding, privacy, and reliability

- Startup settings can hide the menu-bar icon while keeping a Dock/window access path. The app repairs settings that would hide both access surfaces.
- Discover now has a separate preference that hides it and stops/cancels feed network work. It is not a global no-network switch.
- Bare-Fn observation became passive and more defensive about other held or transitioning keys. Shortcuts can recover after Accessibility permission is granted without restarting the app.
- Microphone preparation, device-route change recovery, system-audio diagnostics, first-run model failure recovery, and long-transcript responsiveness received substantial fixes.
- Telemetry consent, retry pacing, termination behavior, and bounded local diagnostic evidence were hardened.

Sources: [feature specification](https://github.com/moona3k/macparakeet/blob/a82ae130a20636dc318cecd5c36ba8402190cb2f/spec/02-features.md), [PR #937](https://github.com/moona3k/macparakeet/pull/937), [PR #950](https://github.com/moona3k/macparakeet/pull/950), [PR #951](https://github.com/moona3k/macparakeet/pull/951), [PR #962](https://github.com/moona3k/macparakeet/pull/962), [PR #980](https://github.com/moona3k/macparakeet/pull/980), [PR #983](https://github.com/moona3k/macparakeet/pull/983), [PR #984](https://github.com/moona3k/macparakeet/pull/984).

### CLI changes

- The bundled CLI moved from the fork-point 3.x line to 4.0.0.
- Prompt commands now cover versions, diffs, restore, soft deletion, label availability, meeting classification, and collection management.
- Meeting/export JSON includes speaker-correction metadata and uses effective speaker corrections. Prompt runs use timestamped, speaker-aware input when available.
- `health` is read-only by default and does not create directories or migrate databases unless repair is explicit. Local CLI output and errors receive stronger terminal-control sanitization.
- **Breaking change:** `export --stdout --format txt`, including default `export <id> --stdout`, now matches TXT file export and includes its metadata/timestamps/speaker labels. Automation that needs transcript-only text must use JSON fields.

Source: [CLI changelog at upstream head](https://github.com/moona3k/macparakeet/blob/a82ae130a20636dc318cecd5c36ba8402190cb2f/Sources/CLI/CHANGELOG.md).

## Release status

These changes are on upstream development source, not the published stable channel. Upstream still identifies the stable DMG as 0.7.3. A signed and notarized 0.8.0 candidate was verified and merged, but its QA report explicitly says that publication was a later step. Additional prompt, speaker-editor, hotkey, telemetry, Library, and cover-art work landed after that tested candidate.

Sources: [upstream README at inspected head](https://github.com/moona3k/macparakeet/blob/a82ae130a20636dc318cecd5c36ba8402190cb2f/README.md#release-status), [0.8.0 QA report](https://github.com/moona3k/macparakeet/blob/a82ae130a20636dc318cecd5c36ba8402190cb2f/docs/qa/2026-09-07-0.8.0/README.md).

## Integration note

This is a large divergent comparison: 688 files changed, with much of the raw insertion count coming from QA evidence and documentation. Review or port by workflow, not by total diff size. The highest-value user-facing slices are prompt management, speaker corrections, saved notes, rich Markdown, Library layouts, bulk vocabulary deletion, DAPT/multi-track support, and meeting capture hardening. The CLI 4.0 stdout change needs an explicit compatibility decision before integration.

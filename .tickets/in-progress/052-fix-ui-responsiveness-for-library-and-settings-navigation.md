---
Assigned-To: macparakeet@052-fix-ui-responsiveness-for-library-and-settings-navigation
Tags: []
Parent:
Blocked-By: []
---

# Fix UI responsiveness for Library and Settings navigation

## What to build

Make ordinary navigation respond promptly without loading transcript bodies to
show titles or accessing credentials to draw Settings controls. Explicit sidebar
clicks must open the section's main page, not restore its last nested route.

This ticket is an interaction-level work inventory, not permission for a general
UI refactor. Implement and verify each listed interaction through its view,
state, data access, and tests. Record additional measured slow interactions
before expanding scope.

## Evidence and priorities

The user reports severe delays during ordinary Library entry, Settings tab
switches, and Capture workflow switches. Search and active recording are not
required. The source audit confirmed the work described below, but did not
measure the duration of the reported stalls.

Primary priorities are ordinary Library loading, internal Settings navigation,
and root-on-sidebar navigation. Do not make search optimization or adding
spinners a substitute for those changes.

## Required page and interaction inventory

### 1. Library: enter from the sidebar, return from detail, and load another page

Current work: paged queries select and decode complete transcription records,
including full text, word timestamps, Reading Turn documents, segments, and chat
history. Paging runs off-main, but a page can represent 8–40 hours of recordings.
Returning to the list also requests another load without a freshness gate.

Required change:
- Use small list records containing only fields needed by cards, rows, filters,
  and available actions. Load a full transcription on explicit detail/action
  demand, not as a prerequisite for displaying its title.
- Reuse a current list snapshot on return. Refresh when underlying items or the
  query change; preserve cancellation and stale-result protection.
- Adapt selection, favorites, folders, and bulk actions so they do not depend on
  all transcript bodies already being resident. Fetch operation data on demand.

Acceptance:
- [ ] First page and subsequent pages decode no full transcript text, word
  timestamps, Reading Turn documents, transcript segments, or chat history.
- [ ] Verify list entry using synthetic pages representing 8, 10, 20, and 40 hours
  of recordings; report load time, main-thread work, and decoded payload size.
- [ ] Returning from detail displays the existing list promptly, and edits or
  newly completed transcriptions still become visible without stale results.
- [ ] Opening a card loads the correct full transcription. Folder moves,
  selection, favorite state, and bulk operations retain their behavior.

### 2. Library Meetings filter and Meetings saved rows: enter, hover, select

Current work: a row obtains and cleans the complete transcript, replaces
newlines, and trims it before taking a 140-character preview. This fallback work
runs even when a derived snippet exists. Hover can cause reevaluation.

Required change: prepare a bounded, cached preview outside rendering. Respect
legacy meetings without clean text and invalidate previews when relevant text
or custom-word settings change.

Acceptance:
- [ ] Rendering, hovering, and selecting a meeting row do not clean or scan the
  complete transcript. A stored usable preview avoids fallback processing.
- [ ] Legacy and newly saved meetings show correct previews without delaying
  row interaction. Cover text/custom-word invalidation in tests.

### 3. Settings: switch Capture / Engine / AI / System

Current work: the common header computes its AI badge through a configuration
getter that synchronously reads the Keychain. This runs outside the AI tab too
when a saved provider configuration exists. The AI form repeats configuration
reads for status, changed-state checks, and formatter availability.

Required change: display an in-memory saved-configuration/status snapshot.
Refresh that snapshot at explicit configuration-change boundaries, not from
view-body getters. Keep credential retrieval out of drawing and navigation.

Acceptance:
- [ ] Repeated top-level tab switches perform zero Keychain requests and zero
  saved-configuration storage loads from render-time getters.
- [ ] Verify System ↔ AI specifically with a saved cloud provider, saved local
  CLI provider, and no saved provider, with no search or recording running.
- [ ] AI Ready status, unsaved-change indicators, formatter availability, and
  save/clear/test-connection behavior remain correct after configuration changes.
- [ ] Record click-to-first-response and click-to-content-ready before/after;
  if delay remains, trace that exact interaction rather than attributing it to
  unrelated Library work.

### 4. Settings Capture: switch Dictation / Transcription / Meetings

Current work: changing the workflow rebuilds the selected form and reevaluates
its parent/header. The common header can reach the same synchronous Keychain
path. Meetings also has calendar/notification and auto-save-folder refresh hooks.

Required change: keep switching free of synchronous storage/service work; reuse
current display state. Inspect those appearance hooks at the actual call sites
and move or deduplicate work only where needed. Do not assume async hooks block.

Acceptance:
- [ ] All three switches perform zero render-time Keychain/configuration reads.
- [ ] Verify each direction with calendar/auto-save controls both enabled and
  disabled where available; switches remain responsive while status refreshes.
- [ ] No model load, device rescan, or database/file operation is synchronously
  required just to select a workflow. Record any remaining expensive layout work.

### 5. Settings: enter from another section and receive background status updates

Current work: root appearance refreshes launch status, permissions, stats,
licensing, model status, and recoveries. Stats synchronously queries the database;
its dictation stats call opens a write transaction and reads historical dates.
Permission polling also synchronously enumerates microphones every two seconds.
Storage-size scans and model disk checks already run off-main.

Required change: show current cached status immediately, refresh only needed or
stale data asynchronously, and prevent polling from interrupting navigation.
Measure device enumeration; do not rewrite already-detached scans without cause.

Acceptance:
- [ ] Entering Settings does not wait synchronously for database availability.
  A controlled database-lock test leaves navigation and dragging usable.
- [ ] Counts and permission/device status still update correctly. Expensive
  refreshes are not duplicated by rapid leave/re-entry.
- [ ] Verify navigation over several polling intervals and report any remaining
  main-thread device/service calls and their measured duration.

### 6. Sidebar: section root instead of restored nested destination

Current work: Settings saves both the selected tab and Capture workflow across
launches. Configuration sidebar labels have no explicit root-reset action.
Dictations retains History/Stats in its long-lived view model. Library resets
folder/detail but retains search/filter state.

Required change: make every explicit sidebar click a section-root action,
including repeated clicks on the already-selected section. Keep explicit deep
links distinct. Reset navigation, not actual settings or unsaved user content.

Acceptance:
- [ ] Settings → Library → Settings lands on Capture → Dictation, not the
  previous Settings tab/workflow. Clicking Settings while already selected does
  the same. Last-route persistence does not override explicit sidebar intent.
- [ ] Dictations sidebar clicks land on History, not retained Stats.
- [ ] Library sidebar clicks show its root list, not a recording or a retained
  search/filter destination. Preserve genuine preferences such as sort choice.
- [ ] Inventory Transcribe, Meetings, Transforms, Vocabulary, and Feedback
  sidebar behavior too; list the nested state reset for each, or explicitly
  record that it has no nested destination. Do not claim all are already broken.
- [ ] Deliberate AI/calendar/detail deep links still reach their target. Actual
  settings, drafts, meeting notes, and active recordings are not discarded.

### 7. Transcript detail: open a recording and return to it

Current work: appearance synchronously constructs Reading Turns, playback
indexes, segments, and speaker turns, then fetches persisted content and prompt
results. Returning can repeat this preparation.

Required change: fetch and prepare a versioned detail snapshot asynchronously,
reuse it while valid, and publish only the currently selected recording's result.

Acceptance:
- [ ] A long recording can load without blocking sidebar clicks or window drag.
- [ ] Rapidly opening different recordings cannot publish stale detail content.
- [ ] Reading Turns, playback alignment, prompts, and text/custom-word edits stay
  correct; unchanged detail does not repeat full preparation on every return.

### 8. Dictations: History search and Stats selection

Current work: history search debounces but then synchronously fetches/groups
records. Selecting Stats runs several synchronous aggregate queries.

Required change: perform these specific queries/preparation off-main and retain
current visible state while refreshing.

Acceptance:
- [ ] Typing in History and selecting Stats cannot synchronously wait for the
  database on the UI thread. Late search results cannot replace a newer query.
- [ ] Counts, streaks, heatmap, top apps, and selection behavior remain correct.

### 9. Library item actions: favorite, rename, delete item, remove meeting audio

Current work: these single-item handlers perform synchronous database/asset
work. Rename also synchronously reloads the loaded window. Bulk deletion already
uses detached work.

Required change: make these actions asynchronous with explicit pending/error
state, retaining existing confirmation and user-data protection rules.

Acceptance:
- [ ] Each named action leaves navigation usable during a controlled slow
  repository/asset operation and reports failures without false success.
- [ ] Rename updates the visible title without a synchronous full-window reload.
- [ ] Destructive actions preserve all existing ownership, recovery, confirmation,
  and active-finalization safeguards. Do not delete assets merely to test speed.

## Completion and verification

- [ ] Attach a completed interaction inventory: each row above has the change
  made, focused regression coverage, and observed before/after behavior.
- [ ] Use a release build for practical timings. Measure first visual response
  separately from content readiness; do not invent timing results.
- [ ] Loading feedback is used only for actual asynchronous work; it is not the
  fix for main-thread waits. Clicks and window movement stay available.
- [ ] Use synthetic/test data, never reset the user's database or recordings.
- [ ] Run focused tests per iteration and the full suite at most once as the
  final gate, in accordance with project instructions.

## Out of scope

- Library search indexing, broad database-engine replacement, or unrelated UI
  redesign. Search remains a secondary follow-up unless evidence shows it blocks
  an in-scope ordinary interaction.
- Window activation, placement, and visibility policy; covered by ticket 053.
- Blanket claims that native controls or all async work are slow.

## Blocked by

None — can start immediately. Ticket 053 can proceed independently.

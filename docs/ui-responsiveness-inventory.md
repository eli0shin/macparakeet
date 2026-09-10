# UI responsiveness interaction inventory

Ticket: `052-fix-ui-responsiveness-for-library-and-settings-navigation`

## Verification environment

The automated measurements used synthetic data in a temporary test database. They did not read, change, or delete user recordings.

An optimized test run was attempted with:

```text
swift test -c release -Xswiftc -DDEBUG --filter TranscriptionRepositoryTests/testOrdinaryLibraryPagesExcludeTranscriptPayloadsForLongRecordings
```

The package spent more than five minutes compiling the complete optimized `MacParakeetTests` target and the harness stopped it before execution. The measured numbers below are therefore debug-build evidence, not release-build numbers. They must not be presented as release timings.

For one synthetic page containing 8-, 10-, 20-, and 40-hour recordings:

| Query | Elapsed | Decoded transcript text |
|---|---:|---:|
| Previous `SELECT *` equivalent (`fetchAll`) | 68.0 ms | 59,280,000 bytes |
| List projection | 5.7 ms | 0 bytes |

The application runs the list query off the main actor. Main-thread database and transcript-decoding work for this path is therefore zero; the main actor only publishes four list records. These timings do not measure SwiftUI layout or click-to-first-response.

## Interaction inventory

| Interaction | Change | Focused coverage | Observed boundary |
|---|---|---|---|
| Library entry and paging | Ordinary pages select display/action metadata only. Full transcript text, word timestamps, Reading Turn documents, transcript segments, and chat history stay in SQLite. | Long-recording projection and paging repository tests. | The synthetic four-record page changed from 59.28 MB / 68.0 ms to 0 transcript bytes / 5.7 ms in a debug build. |
| Return from Library detail | The current list snapshot remains visible when the list remounts. Detail metadata is merged into its row. Completion and recovery boundaries continue to request explicit reloads. | Snapshot reuse, explicit refresh, and metadata tests. | No synchronous page reload occurs on return. |
| Open another Library item | Card selection fetches the full row on a detached task. A selection generation rejects an older result after a newer click. | On-demand full-record test and existing stale-generation tests. | Content readiness still depends on database and detail preparation; navigation does not wait for either operation. |
| Library folder, selection, favorite, export, and bulk actions | Rows retain IDs and action metadata. Export and destructive bulk operations fetch full records on demand. Favorite, rename, delete, and meeting-audio removal run off-main and expose pending/error state. Rename updates and re-sorts the visible row without a window reload. | Library view-model action, failure, ownership, stale-load, and bulk-operation tests. | The action handlers yield while repository or asset work runs. |
| Meetings list render, hover, and select | List loading prepares one bounded legacy preview outside rendering, applies current custom words, then removes the bounded source text. Rows render the prepared snippet. New rows use their derived snippet. | Legacy custom-word preview, bounded payload, and row snippet tests. | Hover and selection do not clean or scan a transcript body. Legacy preparation reads at most 2,048 characters. |
| Settings Capture / Engine / AI / System | `LLMSettingsViewModel` keeps an in-memory saved-configuration snapshot. Status, unsaved-change, formatter, and badge getters read that snapshot. Save, clear, and configuration load update it. | Saved cloud-provider getter test plus existing save, clear, local CLI, status, unsaved-change, formatter, and connection tests. | Twenty repeated getter passes caused zero additional configuration or credential loads. Direct click timings were not captured. |
| Capture Dictation / Transcription / Meetings | Workflow selection now has no render-time configuration or Keychain read through the shared header. Existing calendar/notification refreshes remain asynchronous. | Settings status and LLM snapshot suites. | No synchronous model load, device enumeration, database query, or file operation was added to selection. Layout cost was not instrumented. |
| Enter Settings and status polling | Cached values draw first. Dictation/custom-word/snippet counts refresh on a deduplicated detached task. Microphone enumeration runs on a detached task with cancellation and stale-result protection. | Settings view-model suite and existing polling tests. | Database and device work no longer executes on the main actor from Settings appearance/polling. Device-service duration was not captured. |
| Sidebar roots | Every sidebar label has an explicit button action, including repeated clicks. Settings requests Capture → Dictation; Dictations selects History; Library clears detail, folder, filter, search, and selection but preserves sort. | State and sidebar hit-area tests. | Explicit deep links still use `navigateToSettings` and preserve AI/calendar targets. |
| Transcribe sidebar | Clears progress detail and returns to the input portal. | Main-window state coverage. | No separate nested route remains. |
| Meetings sidebar | No retained nested destination is owned by the main window. Active recording and notes remain intact. | Sidebar selection inventory. | No reset is required. |
| Transforms sidebar | The section has no retained navigation route owned by the main window. Open editor draft state is not discarded. | Sidebar selection inventory. | No reset is required. |
| Vocabulary sidebar | The section has no retained navigation route owned by the main window. User settings are not reset. | Sidebar selection inventory. | No reset is required. |
| Feedback sidebar | The section has no retained navigation route owned by the main window. | Sidebar selection inventory. | No reset is required. |
| Transcript detail | Full-row fetch, Reading Turn construction, playback index construction, transcript segmentation, and speaker-turn preparation run off-main. A version key rejects stale results; a four-entry cache reuses unchanged snapshots. Persisted row and prompt-result reads also run off-main and check the selected recording before publication. | Full-record demand test plus existing Reading Turn, playback, prompt, edit, and stale-result suites. | Sidebar clicks and window interaction do not wait for detail preparation. Practical long-recording click timing was not captured. |
| Dictation History search and Stats | Debounced search fetch/group work runs off-main with a generation check. Stats-tab aggregate queries run off-main and keep visible values while refreshing. | Dictation history search, clear, stats, and repository aggregate tests. | Search and Stats selection no longer wait synchronously for database queries. |
| Single Library item actions | Favorite, rename, delete, and meeting-audio removal are asynchronous. Full ownership data is fetched before destructive cleanup. | Existing success/failure and asset-safeguard tests, updated for async completion. | Navigation remains available while work is pending; failures do not publish success. |

## Remaining measurement limits

No automated macOS window-drag timing seam exists in this package. This change does not claim measured click-to-first-response, click-to-content-ready, calendar-service duration, device-enumeration duration, or expensive SwiftUI layout duration. Those values need an instrumented release app session. The optimized package test attempt did not finish compilation within the five-minute harness limit.

# Window behavior and UI responsiveness audit

Source baseline: `7e36e971`. Scope: main window, floating capture windows, Library, Settings, and related main-thread work.

## Summary

There are real window-policy problems and main-thread blocking paths in this source. These do not require low memory or inadequate hardware.

1. **The main window has custom lifecycle and visibility handling.** App code changes activation policy when it becomes main and closes, branches on visibility for reopen, explicitly re-shows it after a policy change, and destroys/recreates its hosting hierarchy on close/open. Its base class being `NSWindow` does not make that custom behavior disappear.
2. Floating meeting windows inherit `NSPanel`'s hide-on-deactivate default. The live meeting panel also explicitly moves to the active Space.
3. **Ordinary Library entry loads complete transcript records rather than small list records.** A page covering many hours of recordings decodes their detailed transcript data just to display cards. Search is a secondary issue, not a prerequisite for this problem.
4. **Settings rendering synchronously accesses the Keychain.** The shared header's AI badge does this even on other tabs. The AI form does it through several more computed display properties. This is a direct blocking path for ordinary internal Settings navigation without Library search or recording.
5. Settings deliberately persists both its tab and Capture subpanel to `UserDefaults`, restoring unwanted nested navigation while still rebuilding the view. Route persistence is not content caching.
6. Settings and other UI paths also synchronously access the shared database queue. Meeting rows process complete transcript text for a short preview, and transcript detail builds several full-document representations synchronously on appearance.

**Evidence boundary:** This is a source audit, not a runtime hang diagnosis. No app was launched, no user database or meeting artifacts were inspected, and no Instruments trace or hang sample was captured. Confirmed below means confirmed in source or Apple documentation. It does not mean that the duration or exact reported symptom was reproduced. Runtime reproduction, timing, and fix verification remain next steps. No product code changed; no tests were run for this documentation-only audit.

The diagnostic reproduction/fix phases are deferred because this request is to research and report before choosing changes. Do not treat the ranked risks as a measured root cause.

## 1. Window behavior catalog

### Main window

Source: [AppWindowCoordinator.swift](../../Sources/MacParakeet/App/AppWindowCoordinator.swift), especially lines 81–119 and 163–240.

| Trigger | Current behavior | Assessment |
| --- | --- | --- |
| Explicit Open | Creates the window if needed, calls `makeKeyAndOrderFront`, then activates the app ignoring other apps. | Expected for an explicit Open command. |
| Dock/app reopen | If a main or onboarding window reports `isVisible`, only activates the app. Otherwise opens the main window. The delegate ignores AppKit's supplied `hasVisibleWindows` argument. | Uses visibility as a substitute for deciding which window the user requested. It does not explicitly bring the main window forward in the visible-window branch. Test minimized, obscured, and other-Space cases. |
| First creation | Centers, registers `MainWindow` frame autosave, uses titled/closable/minimizable/resizable style. | Autosave and standard window styles are appropriate. Centering is creation-time, not a continuous placement loop. |
| Close | Clears the hosting view, releases the coordinator's window reference, then schedules a Dock-policy check. | Reopening reconstructs the window and SwiftUI hierarchy. Not inherently incorrect, but creates repeated appearance work and policy transitions. |
| Main window becomes main, menu-bar-only mode enabled | Changes app activation policy to `.regular`. | Dock policy changes because a window gained main status. No check for an already-regular policy. |
| Main window closes, menu-bar-only mode enabled | Changes policy to `.accessory` if no primary window is visible. | App-wide policy change; floating meeting windows are not included in the primary-window check. |
| Menu-bar-only setting changes | Sets `.accessory` or `.regular`. When entering accessory mode with the main window visible, explicitly re-shows and activates it. | The code comment itself records that the policy change hides windows. This path repairs only the main window. Its main-window callback can then promote the app back to regular mode. |
| Normal cold launch after onboarding | Launch configures services, menus, and activation policy. Setup ends by checking onboarding, not by opening the main window. | No explicit ordinary-launch main-window presentation in this path. Distinguish user launch from login/background launch rather than relying on a later reopen event. |

Cold-launch sources: [MacParakeetApp.swift:31–36](../../Sources/MacParakeet/MacParakeetApp.swift#L31), [AppDelegate.swift:317–344, 397–410, 510–520](../../Sources/MacParakeet/AppDelegate.swift#L317), [OnboardingCoordinator.swift:39–51](../../Sources/MacParakeet/App/OnboardingCoordinator.swift#L39).

**Scope of the remaining uncertainty:** The main window's custom handling above is confirmed. The narrower search found no explicit active-Space notification handler or custom main-window drag implementation, and the main window does not set `canJoinAllSpaces` or `moveToActiveSpace`. This does **not** mean there is no custom main-window behavior. App-wide activation-policy changes can affect windows without a Space-switch handler. The specific callback sequence behind the wallpaper-then-window symptom remains unmeasured.

### Floating meeting flower / recording pill

Source: [MeetingRecordingPillController.swift:5–8, 80–158](../../Sources/MacParakeet/Views/MeetingRecording/MeetingRecordingPillController.swift#L80).

- Borderless, nonactivating `NSPanel`; cannot become key or main.
- Floating level; joins all Spaces and full-screen Spaces as an auxiliary window.
- Does not set `hidesOnDeactivate`.
- Initially placed at the right edge of `NSScreen.main`, vertically centered. Background dragging is enabled.
- `hide()` orders it out and releases the panel. Normal hide also clears the saved frame. Position is preserved only for callers that request it, such as the floating-controls preference and quit flow. Position is not persisted across ordinary recording sessions or app restarts.
- `isVisible` tests whether the panel exists, not `panel.isVisible`. Thus it is an ownership test, not a reliable onscreen-visibility test.
- `show()` on an existing panel orders it forward and refreshes state.

Explicit hide sources: [MeetingRecordingFlowCoordinator.swift:394–423](../../Sources/MacParakeet/App/MeetingRecordingFlowCoordinator.swift#L394), saved-completion handling around 1070–1200 in the same file. The preference hides the pill while preserving the next frame; inactive recording state and normal teardown hide it; saved completion has a timed dismissal. These are separate from AppKit's implicit hide behavior.

### Live meeting Notes / Transcript / Ask panel

Source: [MeetingRecordingPanelController.swift](../../Sources/MacParakeet/Views/MeetingRecording/MeetingRecordingPanelController.swift).

- Uses `NSPanel`, despite allowing both key and main window status.
- Floating level; explicitly sets `[.moveToActiveSpace, .fullScreenAuxiliary]`.
- Does not set `hidesOnDeactivate`.
- Opening calls `makeKeyAndOrderFront` and activates the app.
- Has frame autosave and background dragging, but no minimization style.
- Closing is intercepted: the delegate returns false and routes the request to `orderOut`. The controller retains the panel until session teardown.
- Initial fallback position is near the lower-right of the main screen.
- The flow hides it on stop/teardown as well as on the user's close action. It is not an independently persistent transcript window.

Flow sources: [MeetingRecordingFlowCoordinator.swift:636–701, 859, 1067, 1199–1200, 1572–1603](../../Sources/MacParakeet/App/MeetingRecordingFlowCoordinator.swift#L636).

One additional mismatch: during active recording, the pill's context-menu command named “Open MacParakeet” invokes `showMeetingPanel`, not the main window. See the `onOpenApp` binding at lines 678–681. That gives an explicit Open command a different destination from the Dock/menu-bar Open commands.

### Why the floating windows disappear

Apple documents that [`hidesOnDeactivate`](https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate) defaults to **false for `NSWindow` and true for `NSPanel`**. Neither meeting controller overrides it. This is a direct policy-level explanation for why the live meeting panel does not behave like a normal window when switching apps. Test the nonactivating pill separately because its activation path differs from the keyable meeting panel.

“All Spaces” and “floating” do not constitute an explicit keep-visible-on-deactivation policy. The app needs to specify that policy instead of accepting panel defaults.

### Other floating surfaces

| Surface | Custom behavior | Source |
| --- | --- | --- |
| Dictation overlay and live dictation preview | Nonactivating, keyable floating panel on all Spaces; recreated at bottom-center; hide destroys it; has an animated width/position method; resigns key before simulated paste. No hide-on-deactivate override. | [DictationOverlayController.swift:41–180](../../Sources/MacParakeet/Views/Dictation/DictationOverlayController.swift#L41) |
| Idle dictation pill | Nonactivating floating panel on all Spaces; recreated at bottom-center; explicit show/hide. No hide-on-deactivate override. | [IdlePillController.swift:96–168](../../Sources/MacParakeet/Views/Dictation/IdlePillController.swift#L96) |
| Media URL input | Floating panel on all Spaces; show takes focus; resign-key observer hides it; Escape orders it out. | [YouTubeInputPanelController.swift:57–130](../../Sources/MacParakeet/Views/Transcription/YouTubeInputPanelController.swift#L57) |
| Transform progress | Floating panel on all Spaces, ordered forward regardless; custom animated positioning and delayed teardown. | [TransformSpikeProgressPanelController.swift:60–196](../../Sources/MacParakeet/Views/Transforms/TransformSpikeProgressPanelController.swift#L60) |
| Meeting countdown toast | Nonactivating floating panel on all Spaces; custom screen selection and placement; ordered forward regardless; lifecycle dismissal. | [MeetingCountdownToastController.swift:115–204](../../Sources/MacParakeet/Views/MeetingRecording/MeetingCountdownToastController.swift#L115) |
| Onboarding | Separate centered window; can reopen after an incomplete dismissal when the app becomes active. | [OnboardingWindowController.swift:29–74](../../Sources/MacParakeet/Onboarding/OnboardingWindowController.swift#L29), [OnboardingCoordinator.swift:64–108](../../Sources/MacParakeet/App/OnboardingCoordinator.swift#L64) |

Do not remove all transient behavior indiscriminately. A countdown toast should expire. Dictation must not steal focus from the paste target. A user-opened live transcript window has different requirements.

## 2. Responsiveness findings

### R0. Ordinary Settings rendering makes synchronous Keychain calls — first priority for internal tab switching

The follow-up audit traced the user's exact distinction: System ↔ AI and Capture's Dictation ↔ Transcription ↔ Meetings, not just leaving and re-entering Settings.

```text
Change activeTab or activeCaptureWorkflow
  -> SettingsView body evaluates the header and selected content
  -> settingsHeaderShell asks for tabBadges
  -> tabBadges evaluates aiProviderCardStatus, regardless of active tab
  -> LLMSettingsViewModel.isConfigured
  -> LLMConfigStore.loadConfig()
  -> KeychainKeyValueStore.getString()
  -> SecItemCopyMatching() synchronously, on the UI path
```

Sources: [SettingsView.swift:134–170, 207–213, 244–283, 839–842, 1716–1724](../../Sources/MacParakeet/Views/Settings/SettingsView.swift#L244), [LLMSettingsViewModel.swift:245–247](../../Sources/MacParakeetViewModels/LLMSettingsViewModel.swift#L245), [LLMConfigStore.swift:38–49](../../Sources/MacParakeetCore/Services/LLM/LLMConfigStore.swift#L38), [KeychainKeyValueStore.swift:11–28](../../Sources/MacParakeetCore/Licensing/KeychainKeyValueStore.swift#L11).

This path reaches the Keychain when saved provider configuration exists and decodes successfully. It is skipped when no provider configuration exists. It is also skipped by the badge's early return for a connection-test error. `loadConfig()` performs the key lookup for every saved provider, including local CLI, even though local CLI does not need an API key.

The AI pane adds more reads:

| Display property | Storage work performed |
| --- | --- |
| `setupStatus` | `isConfigured`, then `savedAIOptionDisplayName`; normally two configuration/Keychain reads for a saved setup. |
| `isConfigured` | Loads configuration and key each time; used by clear/reset and configuration controls as well as the header. |
| `hasUnsavedChanges` | Builds the saved snapshot by loading configuration and key. |
| `isAIFormatterAvailable` | Loads configuration/key to obtain only the saved provider ID. |
| `aiFormatterUnavailableReason` | Can load configuration/key once for configured status and again for provider identity. |

Sources: [LLMSettingsViewModel.swift:249–263, 474–475, 533–560, 1293–1302](../../Sources/MacParakeetViewModels/LLMSettingsViewModel.swift#L249); UI uses at [LLMSettingsView.swift:225–226, 729–781, 1026, 1913–1932](../../Sources/MacParakeet/Views/Settings/LLMSettingsView.swift#L225).

The exact number of reads per click depends on visible branches and SwiftUI evaluation. The confirmed defect is the I/O in display getters; no timing or fixed calls-per-click count is claimed. This is more directly relevant to the reported internal tab delay than the earlier Library-search contention example.

**It is not merely a missing loading state.** These calls are made while evaluating UI content, not through an asynchronous loading operation that leaves the main thread free. A spinner cannot repair a blocked UI thread. Display properties should read an in-memory configuration/status snapshot; key access belongs at explicit asynchronous configuration and execution boundaries.

The tab body uses an ordinary `VStack` inside a `ScrollView`, so the selected form is eagerly constructed. Top-level Settings tab swaps are not deliberately delayed by a tab animation. Capture workflow swaps use a 0.2-second content animation. The 50 ms scroll delay runs only for a pending deep-link/search scroll target. These facts do not explain a multi-second stall. Sources: [SettingsView.swift:143–169, 376–396, 664–683](../../Sources/MacParakeet/Views/Settings/SettingsView.swift#L664), [DesignSystem.swift:211](../../Sources/MacParakeet/Views/Components/DesignSystem.swift#L211).

### R1. Synchronous UI database access can wait behind background work — additional blocking path

The app uses a shared GRDB `DatabaseQueue`. Repositories expose synchronous reads and writes. The configuration also allows a five-second SQLite busy wait for database lock contention. Sources: [DatabaseManager.swift:6–32, 76–80](../../Sources/MacParakeetCore/Database/DatabaseManager.swift#L6), [database documentation](../../Sources/MacParakeetCore/Database/README.md).

Settings calls `refreshStats()` directly from `.onAppear`. The main-actor method synchronously calls dictation stats and fetches all custom words and snippets to count them. Sources: [SettingsView.swift:175–183](../../Sources/MacParakeet/Views/Settings/SettingsView.swift#L175), [SettingsViewModel.swift:1390–1403](../../Sources/MacParakeetViewModels/SettingsViewModel.swift#L1390).

`DictationRepository.stats()` is not just a cached count read. It opens a **write transaction**, reads lifetime counters, counts visible rows, then fetches all completed dictation dates and computes weekly stats. The transaction is used to permit repair of a missing lifetime counter row. Source: [DictationRepository.swift:304–348](../../Sources/MacParakeetCore/Database/DictationRepository.swift#L304).

A concrete blocking chain is therefore:

```text
Background Library search holds the shared database queue
  -> user opens Settings
  -> onAppear calls refreshStats synchronously on MainActor
  -> stats waits for the database queue
  -> main thread cannot finish the interaction
```

External SQLite write contention can add a busy wait to the stats write transaction. The five-second timeout does not bound time spent waiting for another operation on the in-process queue.

This is a confirmed possible wait path, not a measurement that it caused the user's latest beachball.

### R2. Library paging loads too much per row, and search has unbounded scan work

Sources: [TranscriptionLibraryViewModel.swift:125–145, 354–361, 737–787](../../Sources/MacParakeetViewModels/TranscriptionLibraryViewModel.swift#L125), [TranscriptionRepository.swift:220–331](../../Sources/MacParakeetCore/Database/TranscriptionRepository.swift#L220), [Transcription.swift:361–440](../../Sources/MacParakeetCore/Models/Transcription.swift#L361).

- Normal Library loading is detached from the main actor and paged, normally 100 results plus a look-ahead row. It does **not** fetch the entire library on every ordinary page load.
- But the SQL uses `SELECT *`. Every returned record decodes full transcript text, word timestamps, diarization segments, transcript segments, Reading Turn documents, formatting, chat messages, and metadata. Most of this is not needed for a card or list row.
- Search uses a cursor without SQL `LIMIT`, decodes records, and performs Unicode text matching in Swift until enough matches are found. A no-match search can inspect the entire selected scope.
- Meeting search calls `MeetingTranscriptCleaner.preferredText`; older/unformatted meetings may require full text cleanup. All of this runs inside `dbQueue.read`.
- Parent task cancellation and generation checks prevent stale UI publication. They do not cancel the already-running detached synchronous query. Rapid queries or re-entry can leave obsolete work using the database queue.

The issue is not simply lack of a loading indicator. The data contract is too large for list browsing, and cancellation does not stop the expensive work.

### R3. Meeting list rendering processes full transcript text to show 140 characters

[MeetingRowCard.swift:308–337](../../Sources/MacParakeet/Views/MeetingRecording/MeetingRowCard.swift#L308) calls `MeetingTranscriptCleaner.preferredText`, replaces newlines across the full result, trims it, and only then takes a 140-character prefix. It computes this fallback even when a stored `derivedSnippet` is available.

For a meeting without `cleanTranscript`, `preferredText` runs cleanup and custom-word handling over the raw transcript. Source: [MeetingTranscriptCleaner.swift:71–96](../../Sources/MacParakeetCore/TextProcessing/MeetingTranscriptCleaner.swift#L71).

This is a computed property used by the SwiftUI row. Hover changes row state, so subsequent body evaluation can repeat the work. It is not a cached, bounded preview operation. The Library's meeting list is lazy, which limits simultaneous row construction but does not make an individual row cheap. Source: [TranscriptionLibraryView.swift:437–476](../../Sources/MacParakeet/Views/Transcription/TranscriptionLibraryView.swift#L437).

This finding applies to meeting rows, not every thumbnail in the ordinary Library grid.

### R4. Navigation remounts views and repeats preparation

[MainWindowView.swift:122–295](../../Sources/MacParakeet/Views/MainWindowView.swift#L122) switches the detail subtree by selected section. Shared view models survive, but view-local state and appearance work can be recreated.

- Library `.onAppear` always calls `loadFolders()` and `loadTranscriptions()`: [TranscriptionLibraryView.swift:139–142](../../Sources/MacParakeet/Views/Transcription/TranscriptionLibraryView.swift#L139). There is no freshness gate here.
- Every explicit Library sidebar click also clears transcript detail and selects the root folder: [MainWindowState.swift:27–38](../../Sources/MacParakeet/Views/MainWindowState.swift#L27). Returning from another folder can request a load there and another on list appearance.
- Settings appearance refreshes permissions, stats, entitlements, model status, switch availability, and pending recovery count even if the user only wants one capture setting.
- Settings permission polling defaults to two seconds. Each refresh synchronously enumerates microphones before starting the asynchronous permission work: [SettingsViewModel.swift:735, 1209–1254, 1370–1384](../../Sources/MacParakeetViewModels/SettingsViewModel.swift#L1209). Measure Core Audio cost; frequency alone does not prove a long stall.

Changing between Settings' internal tabs does not by itself prove that the root `.onAppear` runs again. Separate root re-entry from internal tab switching in the runtime test.

### R5. Transcript detail does substantial synchronous preparation

[TranscriptResultView.swift:293–321](../../Sources/MacParakeet/Views/Transcription/TranscriptResultView.swift#L293) synchronously rebuilds transcript caches on appearance, reloads persisted content, and loads prompts/results.

`rebuildSegmentCache()` constructs a Reading Turn document and display turns, builds a playback index, and also groups timestamped words into segments and speaker turns. This work scales with the selected transcript. Source: [TranscriptResultView.swift:3751–3805](../../Sources/MacParakeet/Views/Transcription/TranscriptResultView.swift#L3751).

`loadPersistedContent()` synchronously fetches the full transcript again. Prompt loaders also synchronously query their repositories. Sources: [TranscriptionViewModel.swift:1577–1583](../../Sources/MacParakeetViewModels/TranscriptionViewModel.swift#L1577), [PromptResultsViewModel.swift:237–272](../../Sources/MacParakeetViewModels/PromptResultsViewModel.swift#L237).

This affects opening and returning to detail, not only scrolling in the transcript. It also gives more foreground callers access to the same blocking database queue.

### R6. Other foreground actions still perform synchronous work

- Dictation history load/search fetches up to 200 records, groups them, and optionally refreshes stats on the main actor. Stats-tab loading performs four synchronous aggregate queries. The search debounce does not move the query off the main actor. [DictationHistoryViewModel.swift:177–214, 306–339, 481–492](../../Sources/MacParakeetViewModels/DictationHistoryViewModel.swift#L177).
- Library favorite, title rename, single-item delete, and single-item audio removal perform synchronous repository or asset work. Rename then reloads the loaded window synchronously. Bulk deletion, by contrast, already uses detached work. [TranscriptionLibraryViewModel.swift:366–380, 611–708](../../Sources/MacParakeetViewModels/TranscriptionLibraryViewModel.swift#L366).

These deserve the same main-thread I/O rule, even if they are not the first measured hang.

### Existing improvements that should be retained

- Library normal fetch and folder fetch run off-main.
- Library grid and meeting list use lazy containers.
- Model disk-status checks run detached: [EngineSettingsViewModel.swift:419–530](../../Sources/MacParakeetViewModels/EngineSettingsViewModel.swift#L419).
- Storage-size directory scans run detached: [SettingsViewModel.swift:1637–1754](../../Sources/MacParakeetViewModels/SettingsViewModel.swift#L1637).
- Startup database creation/migration and history cleanup run detached: [AppStartupBootstrapper.swift](../../Sources/MacParakeet/App/AppStartupBootstrapper.swift).
- The meeting flower's fast audio glow updates CALayer state rather than driving the whole SwiftUI hierarchy: [MeetingRecordingPillController.swift:160–164](../../Sources/MacParakeet/Views/MeetingRecording/MeetingRecordingPillController.swift#L160).

Do not blame these operations as direct main-thread work without tracing their execution. Background work can still compete for resources or hold a shared queue, but that is a different mechanism.

## 2a. Navigation restores routes by design, not because content is cached

### Settings: both levels are explicitly persisted

[SettingsRootViewModel.swift:32–83](../../Sources/MacParakeetViewModels/SettingsRootViewModel.swift#L32) writes:

- `settings.lastViewedTab` whenever the Settings tab changes.
- `settings.capture.lastWorkflow` whenever Dictation / Transcription / Meetings changes.

Initialization restores both. These values even survive app restarts. With no saved state, the defaults are Capture → Dictation. This is explicit product behavior in the code, not an unavoidable SwiftUI convention.

[MainWindowView.swift:107–115](../../Sources/MacParakeet/Views/MainWindowView.swift#L107) renders configuration/sidebar items as selectable labels. Settings has no equivalent of the Library's explicit root-navigation action. A normal sidebar selection does not reset Settings to its root, and clicking an already-selected label does not provide a separate reset command.

By contrast, the primary Library button calls `navigateFromSidebar`, clears transcript detail, and selects the Library root. Source: [MainWindowState.swift:27–38](../../Sources/MacParakeet/Views/MainWindowState.swift#L27).

### Other retained state confirmed in this pass

- Dictations retains `selectedSubTab` in its process-lifetime view model. Leaving the section clears bulk selection but does not reset History / Stats. Sources: [DictationHistoryViewModel.swift:54–73](../../Sources/MacParakeetViewModels/DictationHistoryViewModel.swift#L54), [MainWindowView.swift:335–347](../../Sources/MacParakeet/Views/MainWindowView.swift#L335).
- Library's root-navigation action resets the folder and detail destination, but does not clear its view model's filter, search, or sort. Thus even the current Library rule is not a full section-state reset. Sources: [MainWindowState.swift:31–37](../../Sources/MacParakeet/Views/MainWindowState.swift#L31), [TranscriptionLibraryViewModel.swift:131–134, 215–220](../../Sources/MacParakeetViewModels/TranscriptionLibraryViewModel.swift#L131).

These are confirmed examples, not a claim that every disclosure in every section persists. For example, AI's Advanced disclosure is view-local `@State`; it is not persisted by `SettingsRootViewModel`.

**Required navigation contract from the follow-up:** An explicit sidebar click opens that section's main page, including when that section is already selected. Intentional deep links can open a nested destination. Returning to a section should not silently restore the last nested route. Reset navigation state, not the user's actual settings, unsaved content, or active recording.

Keeping a route identifier is cheap and does not cache a rendered screen. The current Settings code can recreate its root view model, restore the route from defaults, build the destination form, and perform the same synchronous display reads again. This explains how unwanted route memory and repeated preparation coexist.

## 3. Recommended next steps

### A. Agree on the window contract, then simplify policy

1. Main window: normal macOS window behavior. Explicit Open always brings that window forward. User cold launch opens it; login/background launch follows a separate explicit rule. Preserve frame and assigned Space.
2. Stop changing app activation policy merely because the main window gains main status. Make Dock/menu-bar mode a deliberate app policy, not a focus callback effect.
3. Live meeting transcript: a user-opened window should remain visible when another app becomes active and should remain in its assigned Space. Prefer a normal `NSWindow`; decide separately whether “Always on Top” is needed.
4. Flower: retain nonactivation for capture safety, explicitly keep it visible across app deactivation, and preserve its user-selected position. Decide whether all-Spaces behavior should remain.
5. Make `isVisible` report actual visibility, and make “Open MacParakeet” consistently open the main window.
6. Keep deliberate user close, capture-end cleanup, and transient-toast expiration. Decide whether a live transcript should remain open as finalization begins instead of silently hiding it.

Do this as a separate change from performance work so window behavior can be verified independently.

### B. Prioritize ordinary navigation; capture its stall rather than requiring a search scenario

Use a release build and record the exact build identity. Do not replace or restart an active recording to get the sample.

During a reported stall, use Activity Monitor → MacParakeet → Sample Process, or capture a local Instruments Time Profiler / Hangs trace. Treat traces as private diagnostics and inspect them before sharing.

Test these ranked predictions:

| Candidate | Prediction / distinguishing measurement |
| --- | --- |
| Settings render-time Keychain reads | Switch System ↔ AI and Capture workflows with a saved AI configuration, without search or recording. Sample for `SecItemCopyMatching` / Security calls on the main thread. A cached display snapshot should eliminate Keychain calls during these clicks. |
| Shared database queue blocks foreground | Open Settings immediately after a broad/no-match Library search. Main-thread sample shows a synchronous GRDB/dispatch wait while another thread scans/decodes/searches transcripts. Removing synchronous foreground access eliminates that UI wait. |
| Full-row Library load is too large | First-page latency and decoded bytes grow with transcript length, not just result count. A metadata-only query sharply reduces load time. |
| Meeting row preview work | With records already loaded, meeting-list entry or hover spends main-thread CPU in text cleanup/string operations. Cached previews remove that repeated work. |
| Detail preparation | Opening a long transcript spends main-thread CPU in Reading Turn/segment/index builders. Preparing one immutable snapshot off-main removes the stall. |
| Permission/device refresh | Settings hitches repeat near the polling interval and samples show Core Audio/device enumeration. A cached, event-driven device list removes that repeated work. |

Record click-to-first-response and click-to-content-ready separately. A loading state is acceptable only when clicks, dragging, and other navigation remain responsive.

### C. Likely performance change order, subject to the sample

1. Remove Keychain/configuration reads from Settings render-time getters. Publish an in-memory saved-configuration/status snapshot and refresh it at explicit change boundaries. Verify that ordinary tab/workflow clicks make zero Keychain requests.
2. Introduce small Library list records. **Ordinary first-page loading must not decode word timestamps, Reading Turn documents, full text, or chat history.** Fetch those only when opening detail or running an explicit operation. This is justified without a Library-search reproduction.
3. Apply the root-on-sidebar-click navigation contract consistently, while keeping deliberate deep links and preserving user settings/content.
4. Remove synchronous database and file work from main-actor navigation/actions. Audit call sites, not only whether a method says `async` or uses `Task`.
5. Compute/cache snippets before rendering. Prepare detail snapshots off-main, cache by transcript revision and cleanup settings, and publish only the current result.
6. Refresh sections based on changes/freshness rather than unconditionally repeating all preparation on every appearance.
7. Treat cancellation and indexed Library search as secondary work after ordinary navigation is responsive.

Do not make “switch DatabaseQueue to DatabasePool” the first blanket fix. Concurrent reads can help, but cannot make synchronous main-thread decoding, writes, or text processing safe.

### D. Verification gates

- Window matrix: cold launch, Dock reopen, menu Open, close/reopen, minimize/restore, app switching, assigned Desktop switching, full-screen app, second display, menu-bar-only on/off, live recording and paused recording.
- Confirm main-window frame/Space remains stable; user-opened live transcript remains visible during app switching; flower remains present and draggable during recording.
- Use synthetic small and large libraries, including pages representing 8, 10, 20, and 40 hours of recordings and legacy meetings without clean text. Ordinary list queries must decode no transcript-body fields. Do not edit or clear the user's database.
- Test System ↔ AI and Capture's Dictation ↔ Transcription ↔ Meetings with no search and no active recording. Include a saved cloud provider, a local CLI provider, and no saved provider. Count Keychain/config-store calls as well as measuring frame response.
- Test Settings → Library → Settings and repeated clicks on the selected Settings sidebar item. Both explicit Settings clicks should land at the section root; an intentional AI deep link must still reach AI.
- Measure navigation while search, recording, and finalization are active. Include a controlled database-lock case to prove that UI interaction does not wait on the lock.
- Existing coordinator tests explicitly note that some floating-window visibility is not exercised. Add real AppKit behavior checks, not only assertions that a controller exists. Source: [MeetingRecordingFlowCoordinatorTests.swift:891–892](../../Tests/MacParakeetTests/MeetingRecordingFlow/MeetingRecordingFlowCoordinatorTests.swift#L891).

## Bottom line

The source supports the complaint that the UI does too much work for simple actions. The first priorities are **Keychain access during Settings rendering, full-transcript loading for ordinary Library cards, and unwanted nested-route restoration**. Library search is not required to expose these design problems and is not the user's priority.

The main window has custom lifecycle and visibility handling that should be simplified. Its exact Space-delay sequence remains unmeasured. The floating-window deactivation policy is a separate confirmed issue. Neither should be dismissed because the app uses native window classes.

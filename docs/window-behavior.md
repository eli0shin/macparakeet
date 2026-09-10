# Window behavior contract and verification

This document records the window policies for ticket 053. “Desktop” means a macOS Space.

## Window inventory

| Surface | Focus policy | Desktop and placement policy | Hide or close triggers |
| --- | --- | --- | --- |
| Main window | Normal key/main window. Explicit launch, Dock reopen, app-menu Open, menu-bar Open, and Settings links activate it. Focus changes do not change Dock mode. | Normal assigned Desktop. AppKit frame autosave uses `MainWindow`; first creation is centered only when no frame exists. | User close only orders out the retained window. It does not stop dictation or a meeting. |
| Live meeting Notes / Transcript / Ask | Normal key/main `NSWindow`; it does not hide when the app deactivates. | Normal assigned Desktop and normal window level. AppKit frame autosave uses `MeetingRecordingPanel`. It does not move to the active Desktop or join all Desktops. | User close orders out only this surface. Recording stop/finalization teardown closes it and releases its active-session view model. Reopen before teardown uses the same view model, including notes and Ask state. |
| Recording flower | Nonactivating floating panel; cannot become key/main and explicitly stays visible when the app deactivates. | Joins all Desktops and full-screen Desktops. AppKit frame autosave uses `MeetingRecordingPill`; an unavailable-display frame is replaced once with a position on an available display. | The visibility preference orders it out and later reuses its frame. Canceled quit restores it when recording is active. Recording cancellation/error hides it immediately. Successful stop keeps completion feedback visible until its timed dismissal. |
| Dictation/live-preview overlay | Nonactivating capture overlay; explicitly stays visible when the app deactivates. It resigns key status before paste. | Joins all Desktops; capture owns bottom-center placement. | Dictation flow completion, cancellation, or error. |
| Idle dictation pill | Nonactivating capture control; explicitly stays visible when the app deactivates. | Joins all Desktops; controller owns bottom-center placement. | Preference change, dictation start, or app termination. |
| Media URL input | Keyable floating input. Resigning key intentionally dismisses it. | Joins all Desktops; controller owns placement. | Resign key, Escape, or explicit close. |
| Transform progress | Nonactivating, click-through progress surface; explicitly stays visible when the app deactivates. | Joins all Desktops; transform operation owns placement. | Transform completion/error delayed teardown. |
| Meeting countdown | Nonactivating toast; explicitly stays visible when the app deactivates. | Joins all Desktops; countdown owns top-right placement on the current attention display. | Countdown completion, user dismiss, early confirmation, replacement, or programmatic cancellation. |
| Onboarding | Normal separate onboarding window. | Centered by onboarding on presentation. | Completion or deliberate dismissal. Incomplete onboarding can reopen on app activation, but it does not satisfy an explicit request for the main window. |

Dock/menu-bar activation policy is set only at process startup and when the user changes that setting. A direct launch opens the main window for a returning user. An `SMAppService.mainApp` login-item launch starts in the background. The flower action and menu item named **Open MacParakeet** open the main window; clicking the flower itself still opens the live meeting window.

## Runtime trace

The `MainWindow` unified-log category records open, focus, move, resize, minimize, restore, and close callbacks with visibility, activation policy, and frame. Use this during reproduction:

```bash
log stream --level debug --predicate 'subsystem == "com.macparakeet.app" AND category == "MainWindow"'
```

This trace distinguishes activation-policy hiding or app-driven placement from a delayed main-thread render. Ticket 053 does not claim that the reported wallpaper-then-window delay is a window-policy defect because it has not been reproduced or timed. If the trace shows no hide, reopen, policy, move, or resize event during the delay, attach the timing evidence to ticket 052.

## Manual verification

The following run used an isolated app-state directory so that test recordings and preferences did not use the normal user database.

| Item | Value |
| --- | --- |
| Date | 2026-09-10 |
| Commit | `8cf4dc15e77d` |
| Build | Debug, `MacParakeet-Dev.app`, source `manual-window-qa` (`scripts/dev/run_app.sh` / Xcode Debug build) |
| App state | `MACPARAKEET_DEBUG_APP_STATE_DIR=/tmp/macparakeet-053-qa-state` |
| System | macOS 26.6.2, Apple M1 Pro, one built-in 3024×1964 Retina display |
| Window manager | AeroSpace was active. It tiled and moved normal windows. Frame changes attributed to it are noted below. |
| Evidence | Accessibility window state, Core Graphics on-screen state, and the `MainWindow` unified-log trace |

`policy=0` below is the regular Dock activation policy. `policy=1` is menu-bar-only accessory policy.

| Mode and case | Observed callback sequence | Placement and visibility result | Result |
| --- | --- | --- | --- |
| Dock mode, returning-user direct launch | `became-key` → `became-main` → `moved` → `open` → `resized` → `moved`, all with `policy=0` | Main window opened frontmost. Its final Accessibility frame was `(756,32) 860×949`; the trace records AppKit coordinates `(756,1) 860×949`. AeroSpace caused the intermediate moves and resize. | Pass |
| Dock mode, deactivate and reactivate | `resigned-key` → `resigned-main`, then `became-main` → `became-key` | The main window remained visible while Finder was active and returned as the key/main window without recreation. | Pass |
| Dock mode, minimize and reopen | `resigned-main` → `resigned-key` → `miniaturized`, then `became-key` → `became-main` → `deminiaturized` → `open` | Reopen restored the retained main window at the same `860×949` frame. | Pass |
| Dock mode, close and reopen | `will-close` → `resigned-main` → `resigned-key`, then `became-key` → `became-main` → `open` | Close removed the main window from the visible Accessibility window list. Reopen reused it and preserved its frame. | Pass |
| Window menu, **Show MacParakeet Dev** | `will-close` sequence, then `open` → `became-main` → `became-key` | The Window menu reopened the main window. | Pass |
| Menu-bar **Open MacParakeet Dev** during a meeting | `will-close` sequence, then `became-key` → `became-main` → `open` | With the main window closed, the recording flower and **Meeting Recording** window remained. Open restored only the main window; it did not replace or recreate the live meeting window. | Pass |
| Menu-bar-only mode | Main-window resign callbacks reported `policy=1`; close/reopen reported `will-close` and then `became-key` → `became-main` → `open`, all with `policy=1` | Changing the setting changed `NSRunningApplication.activationPolicy` from regular (`0`) to accessory (`1`) without hiding the main, live meeting, or flower windows. The menu-bar Open action restored a closed main window while the live meeting stayed open. The setting was changed back to Dock mode after the run. | Pass |
| Active meeting, live window close/reopen | Main window only resigned key/main when the live window became key; no main-window close callback occurred | Starting a recording showed three surfaces: main window, normal **Meeting Recording** window, and nonactivating flower. Closing the live window left the main window and flower visible, and **Stop Recording** remained available. Clicking the flower reopened the same live window. | Pass |
| Paused meeting | No main-window callback, as expected | Accessibility changed the live control from **Pause recording** to **Resume recording**. While paused and Finder was active, all three meeting surfaces remained instantiated and non-minimized. Closing the main window left the live window and flower; menu-bar Open restored the main window. Resume changed the control back to **Pause recording**. | Pass |
| Canceled quit during an active meeting | No main-window open/close callback | Quit hid the flower and presented the recording decision alert. **Cancel Quit** dismissed the alert and restored the flower beside the retained main and live windows. | Pass |
| Desktop/workspace switch | Main window resigned key/main and remained `visible=true`; AeroSpace then reported and performed normal-window moves | On another AeroSpace workspace, only the all-Desktop flower was on screen. Returning to the assigned workspace restored the normal main and live windows. AeroSpace uses virtual workspaces, so this is not a clean native-macOS-Space-only result. | Pass with environment note |
| Another app full-screen | Main window resigned key/main and stayed logically visible | With LM Studio in its native full-screen Desktop, Core Graphics reported the flower on screen at floating layer 3. The normal main and live windows did not enter the full-screen Desktop. Returning to their assigned workspace showed all three surfaces again. | Pass |
| Frame retention under external placement | `moved` callbacks recorded normal-window frame changes, including off-workspace coordinates, followed by the prior visible-workspace frame when focused | AeroSpace, not MacParakeet, controlled normal-window tiling. Close/reopen retained the frame that the window manager assigned. No app-driven move-to-active-Desktop behavior was observed. | Pass with environment note |

### Cases not available in this run

| Case | Status | Reason and retained coverage |
| --- | --- | --- |
| Multiple physical displays | Not run | The test Mac had one online built-in display. Automated tests cover choosing an available screen and retaining a valid saved flower frame. |
| Physical display removal | Not run | No second display was available to disconnect. Automated tests cover replacing an unavailable-display flower frame with a position on an available display. |
| `SMAppService.mainApp` login-item delivery | Not run | The tested artifact was a development bundle launched from `.build`, not an installed release app delivered by the signed login-item service. Launch-policy tests cover direct-launch versus login-item decisions, but this run does not claim system login-item delivery or focus behavior. |

Desktop assignment, display removal, and login-item delivery remain AppKit/system behaviors that cannot be fully established by a headless Swift test. Repeat the unavailable cases on signed release hardware with two displays before a release for which those system integrations are a gate.

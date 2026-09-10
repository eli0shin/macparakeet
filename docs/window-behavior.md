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

## Manual verification boundary

Desktop assignment, another app's full-screen Desktop, multiple displays, display removal, and login-item delivery are manual AppKit/system behaviors. They are not reliable in a headless Swift test. Run the ticket matrix in both Dock and menu-bar-only modes with active and paused meetings. Record the build, each observed callback sequence, and the visible Desktop/display result. No such manual run is claimed by this document.

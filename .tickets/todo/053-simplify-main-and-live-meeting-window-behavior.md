---
Assigned-To:
Tags: []
Parent:
Blocked-By: []
---

# Simplify main and live meeting window behavior

## What to build

Make the main window and user-opened live meeting transcript behave like normal
macOS windows: explicit opening shows the requested window, user placement is
stable, and switching apps or Desktops does not cause unexpected hiding or
relocation. Keep the recording flower useful without stealing keyboard focus.

The main window does have custom handling: activation-policy changes on focus
and close, visibility-dependent reopen behavior, forced activation/re-show, and
window/hosting-view destruction and recreation. Do not dismiss the issue because
its base class is NSWindow or because there is no explicit Space-switch handler.

The user's wallpaper-then-window symptom has not yet been reproduced or timed.
Trace the actual window lifecycle while reproducing it; distinguish policy-driven
hiding from a delayed main-thread render without assuming either is the cause.

## Window and interaction inventory

### 1. Main window: user launch, Dock reopen, menu Open, and minimize/restore

Current behavior: ordinary cold launch has no explicit main-window presentation
for a returning user. Reopen only activates the application if a primary window
reports visible, instead of consistently bringing forward the requested main
window. Other explicit Open paths do bring it forward.

Required behavior:
- [ ] User-initiated launch opens the main window. Login/background launch has
  a separate explicit policy and does not unexpectedly take focus.
- [ ] Dock reopen, app-menu Open, and menu-bar Open reliably expose the main
  window, including when closed, minimized, obscured, or on another Desktop.
- [ ] Preserve its assigned Desktop and use normal macOS activation behavior
  rather than moving the window to the caller's current Desktop.
- [ ] Opening Settings intentionally reaches Settings; an unrelated visible
  onboarding or meeting window does not substitute for the requested main window.

### 2. Main window: focus, close/reopen, and Dock/menu-bar mode

Current behavior: in menu-bar-only mode, gaining main status sets regular app
activation policy; closing can set accessory policy. Changing to accessory mode
explicitly re-shows the main window to repair hiding. Close discards its hosting
view and the coordinator's window reference.

Required behavior:
- [ ] Gaining or losing main/key status does not change the app activation
  policy. Closing the main window does not trigger an automatic Dock-mode change.
- [ ] Dock/menu-bar mode is changed only at startup or an explicit mode change,
  not as a side effect of window focus. A visible main window remains visible
  when the user changes mode.
- [ ] Avoid unnecessary window/hosting-view destruction and reconstruction on
  ordinary close/reopen; reuse the window where appropriate and preserve frame.
- [ ] Main-window close does not stop dictation services or an active meeting.
- [ ] Closing the main window or changing Dock mode does not unintentionally
  hide the recording flower or a user-opened live transcript.

### 3. Main window: drag, resize, assigned Desktop, and display changes

Required behavior:
- [ ] User position and size survive ordinary close/reopen and app restart.
- [ ] Switching away from and back to its assigned Desktop does not initiate
  app-driven hide/re-show or reposition operations.
- [ ] Drag and resize remain under user control; no activation callback resets
  the frame or moves the window to a different screen.
- [ ] Test the reported wallpaper-then-window sequence and record the actual
  callbacks/policy changes. If a remaining delay is rendering rather than window
  policy, document that evidence for ticket 052 instead of claiming it is fixed.
- [ ] Disconnecting a display leaves the window recoverable on an available
  display without imposing repeated placement changes during normal use.

### 4. Live meeting Notes / Transcript / Ask window: open and switch apps/Desktops

Current behavior: a floating NSPanel inherits hide-on-deactivate and explicitly
moves to the active Space. Opening activates the app. Close is intercepted and
orders it out. The session lifecycle also hides/closes it.

Required behavior:
- [ ] A user-opened live transcript remains visible when another app becomes
  active. Explicitly specify this rather than inheriting NSPanel defaults.
- [ ] Remove automatic move-to-active-Space behavior. Preserve its user-chosen
  Desktop, position, and size with normal window semantics.
- [ ] Prefer a normal window for this working surface. If a panel or floating
  level is retained, document the specific product requirement; do not retain
  special behavior merely because the old controller used it.
- [ ] User close hides/closes only this surface and does not stop recording.
  Reopening restores the same active meeting and does not lose notes or Ask state.
- [ ] Inventory every stop/finalization/teardown hide. Preserve recording-end
  cleanup, but make the intended transition explicit. If keeping the transcript
  open through finalization needs a new product flow, record that decision rather
  than silently adding one or hiding an active working window.

### 5. Recording flower: show, drag, app switching, and recording lifecycle

Current behavior: a nonactivating floating panel joins all Spaces, inherits panel
visibility defaults, normally loses its frame on hide, and reports panel existence
as visibility. Special preference/quit paths preserve the frame only temporarily.

Required behavior:
- [ ] The flower stays present during active/paused recording when enabled,
  including app switching. It does not take keyboard focus from the current app.
- [ ] User-dragged position survives hide/show, later recordings, and app restart;
  validate saved placement against available displays.
- [ ] Keep current all-Spaces behavior for this capture control unless an explicit
  product decision changes it. Do not impose the flower's policy on working windows.
- [ ] Visibility reporting reflects actual window state, not whether a panel
  object exists. Re-show works even when the panel exists but is not visible.
- [ ] Explicit hide preference, canceled quit recovery, recording end, and
  completion feedback each have a documented, tested visibility transition.
- [ ] “Open MacParakeet” consistently opens the main window, not the live meeting
  panel. Clicking the flower can retain its separate live-meeting-panel action.

### 6. Other transient windows: classify, do not remove behavior blindly

- [ ] Inventory dictation/live-preview overlay, idle dictation pill, media URL
  input, Transform progress, meeting countdown toast, and onboarding. For each,
  record focus policy, Desktop policy, placement ownership, and every hide trigger.
- [ ] Correct unintended deactivation hiding for capture overlays that are meant
  to remain visible while another app is active. Preserve dictation paste focus.
- [ ] Preserve intentional dismissal for transient countdowns, explicit cancel,
  and completed operations. Do not turn every toast into a persistent window.
- [ ] Separate onboarding's deliberate incomplete-flow reopening from normal
  main-window Open behavior; it must not suppress the requested main window.

## Acceptance and verification matrix

- [ ] Exercise normal Dock mode and menu-bar-only mode independently.
- [ ] Exercise user cold launch, background/login launch, Dock reopen, menu Open,
  close/reopen, minimize/restore, and switching between the app and another app.
- [ ] Exercise assigned Desktop switching, a full-screen foreground app, a second
  display, and display removal. Record actual placement and visibility outcomes.
- [ ] Repeat relevant cases while a meeting is active and paused, with the main
  window open and closed, and with the live transcript open and closed.
- [ ] Add focused AppKit-level tests for policy, reopen, frame persistence, and
  visible-window behavior where automatable. Controller-existence assertions do
  not prove actual visibility. Record manual cases where Desktop automation is
  not reliable rather than claiming unrun verification.
- [ ] No recording, notes, transcript, or meeting artifact is discarded by window
  management. Test using synthetic/dev data, not destructive recovery operations.
- [ ] Run focused tests per iteration; full suite at most once as the final gate.

## Out of scope

- Library data loading, Settings rendering, and sidebar route resets; covered by
  ticket 052. This ticket may report rendering evidence to that work without
  blocking the independently verifiable window-policy changes.
- Unrelated visual redesign or global removal of all transient windows.
- Changing capture, final transcription, or user-data retention rules.

## Blocked by

None — can start immediately. Ticket 052 can proceed independently.

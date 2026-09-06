---
Assigned-To:
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Diagnose and fix the macOS beachball that occurs when the user scrolls a meeting transcript in the current development build. Treat this as a performance regression, not a speculative refactor. Build a tight, red-capable measurement loop that drives the real transcript scrolling/rendering path with a representative long meeting and detects main-thread stalls or unacceptable frame latency. Capture a Time Profiler or equivalent trace before changing production code, rank falsifiable hypotheses, and change one variable at a time.

The private authorized qualification meetings may be used locally for diagnosis, including `/Users/elioshinsky/Library/Application Support/MacParakeet/meeting-recordings/185A233D-6CFA-4331-B13B-26E4BBD5F1E3` and `/Users/elioshinsky/Library/Application Support/MacParakeet/meeting-recordings/7F0D02F0-C652-41AA-B4FD-344C41024D72`. Never commit meeting audio, transcripts, identifiers, local paths, captured private content, diagnostics, or derived fixtures. If a committed fixture is needed, generate synthetic public-safe transcript data with the same structural scale.

Preserve Reading Turn formatting, speaker labels, selection, search, editing, copy/export, and scrolling position. Keep expensive formatting, database work, and layout computation off the main actor where possible. Do not mask the issue with delays, debouncing that changes visible behavior, reduced transcript content, or disabled features.

## Acceptance criteria

- [ ] One documented, agent-runnable command exercises the actual long-transcript scrolling/rendering seam and fails on the pre-fix stall threshold.
- [ ] Baseline measurements and a profiler trace identify the dominant main-thread work before the fix; the diagnosis records ranked hypotheses and evidence.
- [ ] The smallest load-bearing reproduction is converted to a public-safe regression or performance test at the correct seam.
- [ ] The fix removes the beachball and materially improves measured scroll/frame latency on the original representative meeting.
- [ ] Reading Turns, speaker labels, search, selection, editing, copy/export, and scroll-position behavior remain correct.
- [ ] No private meeting content, identifiers, paths, traces, or diagnostics enter Git.
- [ ] All temporary instrumentation and throwaway artifacts are removed before review.
- [ ] Focused tests and applicable CI checks pass.
- [ ] The PR documents before/after measurements, profiler evidence, the confirmed cause, and remaining limits.

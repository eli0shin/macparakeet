# Final transcript detail performance qualification

Ticket 067 measures the combined completed-meeting detail after tickets 060–066.
All fixture text is generated in the test. No meeting transcript, identifier,
local path, or Instruments capture is committed.

## Reproduce

Run the strict release gate:

```bash
scripts/dev/check_final_transcript_detail_performance.sh
```

The script builds all SwiftPM test targets with `-c release`, then runs only
`FinalTranscriptDetailPerformanceTests`. The normal test suite skips this
machine-time test. The release build omits tests that require DEBUG-only fixture
hooks; their normal debug coverage is unchanged, and the optimized product is
not compiled with DEBUG behavior.

The strict gate uses these limits:

- initial readiness: less than 1,000 ms of main-thread CPU;
- largest initial run-loop update: less than 250 ms (the Instruments microhang
  threshold);
- scrolling, playback, find input, and settled find presentation: less than
  16 ms per measured main-thread update.

Use this command to collect a Time Profiler capture outside the repository:

```bash
MACPARAKEET_FINAL_TRANSCRIPT_PERFORMANCE=1 \
  xcrun xctrace record \
  --template 'Time Profiler' \
  --time-limit 15s \
  --output /tmp/final-transcript.trace \
  --launch -- \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xctest \
  -XCTest MacParakeetTests.FinalTranscriptDetailPerformanceTests/testProductionRendererReportsReleaseInteractionCPU \
  .build/arm64-apple-macosx/release/MacParakeetPackageTests.xctest

xcrun xctrace export \
  --input /tmp/final-transcript.trace \
  --toc \
  --output /tmp/final-transcript-toc.xml
```

Delete the capture after inspection. Do not add it to Git.

## Fixture and machine

The production `TranscriptResultView` receives one completed Final transcript
with:

- 1,200 variable-height Reading Turns;
- 72,000 timed words across four speakers;
- 578,398 UTF-16 text units;
- 18,000,000 ms (5 hours) of synthetic meeting time;
- a 1,000 × 800 point detail viewport;
- 9,000 settled matches for the query `public`.

Recorded 2026-09-13 on an Apple M1 Pro MacBook Pro with 16 GB memory, macOS
26.6.2 (25G83), Xcode 26.6 (17F113), and Apple Swift 6.3.3. Measurements use
SwiftPM release optimization. Values are main-thread CPU time, not wall time,
unless stated otherwise.

## Results

The parent ticket's historical diagnosis used a debug build and a different
synthetic fixture. It measured about 3,350 ms for 1,200 eager Reading Turn rows,
scroll updates as high as about 480 ms, 136 ms of main-thread matching, 43 ms of
range grouping, and 1,390 ms of highlighted attributed-text construction. Those
numbers are evidence of the old debug path, not a release baseline.

This ticket first measured the combined release path before its scoped type-erasure
and repeated-find corrections:

| Mode | Initial total | Largest initial update | Scroll | Playback | Find input | Settled-find update |
|---|---:|---:|---:|---:|---:|---:|
| Reading | 1,699.14 ms | 1,304.83 ms | 21.84 ms | Not exercised | 24.56 ms | 43.52 ms |
| Text | 138.04 ms | 47.36 ms | 1.46 ms | Not exercised | 19.84 ms | 39.37 ms |

The first harness had no playable media mode, so its playback numbers measured
state invalidation but not playback follow. They are omitted here. The final
harness explicitly enters the production audio playback-follow path, starts near
the end without realizing intervening Reading Turns, and verifies the target row
before measuring ordinary ticks.

The correction erases the large generic Reading header and selected transcript
surface before AppKit hosts them. It also avoids rebuilding immutable find
blocks when an already-open find session receives another query. A representative
release run after the correction reported:

| Mode | Initial total | Largest initial update | Scroll | Playback | Find input | Find settle total | Settled-find update |
|---|---:|---:|---:|---:|---:|---:|---:|
| Reading | 650.47 ms | 423.67 ms | 39.31 ms | 41.95 ms | 16.93 ms | 357.58 ms | 116.55 ms |
| Text | 134.40 ms | 46.16 ms | 2.42 ms | 6.09 ms | 8.85 ms | 238.17 ms | 43.27 ms |

Initial Reading CPU fell by 61.7%, and its largest initial update fell by 67.5%.
Text playback, scrolling, and direct find input meet the one-frame target. The
final playback-follow correction proved that Reading playback does not yet meet
it.

## Time Profiler evidence

A release Time Profiler recording used the exact command above and the same
production-renderer gate. The main-thread call tree showed the remaining Reading
initial update under SwiftUI `AttributeGraph` graph updates and stack sizing,
then AppKit layout and Core Animation transaction commit. The hottest inclusive
families were `AG::Graph::UpdateStack::update`, `LayoutEngineBox.sizeThatFits`,
`StackLayout` sizing/placement, `NSView.layoutSubtreeIfNeeded`, and
`CA::Transaction::commit`. Across 4,262 sampled main-thread stacks, the final
trace included 1,472 `AttributeGraph` update samples, 2,050 layout-engine
sizing samples, 1,303 `NSView.layoutSubtreeIfNeeded` samples, and 2,282 Core
Animation commit samples. Native Reading Turn row-height calculation was not
sampled as a dominant stack. The narrow Reading Turn coordinator update appeared
in 67 samples after the harness entered the real playback-follow path.
The Hangs instrument did not emit an automatic potential-hang row for the XCTest
process, so this conclusion uses the gate's per-update CPU measurements and the
Time Profiler call tree rather than an automatic hang classification.

The recording's Points of Interest events showed narrow transcript-detail
module evaluation and `TranscriptPlayback / Reading Turn Presentation Update`
intervals. The final playback-follow measurement reached about 42 ms in Reading
and 6 ms in Text. The gate confirmed that the largest initial Reading
transaction exceeds its 250 ms
microhang budget. Settled find causes a smaller SwiftUI/AttributeGraph and
Core Animation presentation transaction in both modes; those measured updates
remain between 43 and 117 ms. These stalls are explained, but they do not meet the
program's responsiveness target.

## Remaining blocker

The strict gate intentionally fails. Parent ticket 059 must not close until a
follow-up does all of the following:

1. Remove or split the remaining cold `TranscriptResultView`/Reading-header
   SwiftUI type and layout transaction so no initial main-thread update reaches
   250 ms. The current Reading result is about 424 ms.
2. Keep native Reading row realization below 16 ms during ordinary scrolling.
   The current worst sampled update is about 39 ms.
3. Keep Reading playback-follow updates below 16 ms. The current worst ordinary
   tick after direct near-end startup is about 42 ms; Text mode is about 6 ms.
4. Split or reduce the settled-find SwiftUI presentation transaction below
   16 ms in both modes. Current updates are about 117 ms in Reading and 43 ms in
   Text.
5. Keep each Reading find-field edit below 16 ms. The current worst edit is
   about 17 ms; Text mode is about 9 ms.
6. Re-run this release gate and Time Profiler command on the same fixture. Do
   not raise the budgets or hide the work behind a progress indicator.

This is a precise program blocker, not a claim that the parent responsiveness
criteria pass.

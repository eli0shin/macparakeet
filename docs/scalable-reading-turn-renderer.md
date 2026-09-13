# Scalable Reading Turn renderer evaluation

Ticket 062 replaces the completed-meeting Reading surface's eager SwiftUI row
layout. All data and measurements below use generated public text.

## Frame budget

The production regression uses 1,200 variable-height Reading Turns at 800 × 600
points. In a debug test process, it requires:

- less than 750 ms of initial main-thread CPU;
- less than 16 ms of main-thread CPU for each ordinary 120-point scroll step;
- fewer than 30 realized rows at one time;
- exact settled top and bottom bounds;
- direct realization of the last Reading Turn.

Run it with:

```bash
scripts/dev/check_transcript_scrolling_performance.sh
```

Machine-time gates are environment-sensitive. These limits are intentionally
above the measured result and materially below the old eager path.

## Evidence and decision

The baseline diagnosis in parent ticket 059 measured about 3,350 ms of initial
main-thread layout and sampled large updates up to about 480 ms for 1,200 eager
SwiftUI rows. The eager renderer's production structure required SwiftUI to
shape, wrap, and lay out every off-screen Reading Turn view graph. Ticket 020's
Time Profiler trace separately identified SwiftUI lazy layout as the dominant
work in the rejected selectable variable-height `LazyVStack` path.

The branch-only public prototype is commit `f34b5ed1` on
`prototype/062-appkit-reading-turn-table`. Its standalone AppKit table measured
262 ms of initial debug wall time, realized 5 of 1,200 rows, and navigated
directly to the last row while 5 rows remained visible.

The production renderer uses the same design with native selectable row text,
controls, accessibility, and exact cached text heights. A local debug run
measured 314 ms of initial main-thread CPU and a 7.17 ms worst ordinary scroll
step. The committed gate drives `MeetingReadingTurnContentView`, which is the
renderer used by `TranscriptResultView`.

## Playback update profiling

Completed-meeting playback time is observed inside
`MeetingReadingTurnPlaybackView`, below the transcript detail boundary. The
playback index resolves the active Reading Turn without realizing preceding
rows. The AppKit coordinator then updates only the previous and new active rows
and scrolls only when the target or navigation token changes.

The 1,200-turn playback regression starts at the final Reading Turn, then
samples 120 one-second ticks including a large backward seek. A local debug run
reported 34.76 ms of main-thread CPU for the worst tick, below its 100 ms
regression limit. The renderer kept fewer than 30 rows realized.

In Instruments, select the Points of Interest track and inspect
`TranscriptPlayback / Reading Turn Presentation Update`. The interval contains
the main-thread table work for each narrow presentation update. Header
remeasurement and full-row reloads must not occur in ordinary playback
intervals.

## Rejected designs

- **Plain `VStack`:** It creates every off-screen view graph. Initial work grows
  with all Reading Turns and produced the 3,350 ms baseline.
- **`LazyVStack`:** Ticket 020 proved a macOS 26 feedback loop with selectable,
  variable-height rows after scrolling down and back up. Restoring it is not
  safe.
- **SwiftUI `List`:** The diagnostic reduced initial work to about 400 ms, but
  row realization still took about 75–90 ms and estimated document bounds were
  unstable.
- **One TextKit document:** Text shaping is efficient, but speaker rename and
  seek controls, per-turn context actions, playback focus, and per-turn
  accessibility would need text attachments or a synchronized overlay model.
  That adds two interaction models and weakens the Reading Turn seam.
- **Hosted SwiftUI rows in an AppKit table:** It bounds row count, but each newly
  visible row still constructs a selectable SwiftUI graph. Native AppKit rows
  preserve the required interactions with less realization work.

## Trade-offs

Exact heights still require one bounded text measurement per Reading Turn when
the transcript, width, or font scale changes. This work does not create row view
graphs, and its result gives the table stable full-document bounds. Normal
playback and current-search highlighting update only visible native rows.

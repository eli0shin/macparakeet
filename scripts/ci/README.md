# CI checks

## Five-minute normal-PR target

The old workflow took a median 20:38 across eight successful PR runs on
2026-09-05. Release compilation alone took a median 7:33. The target is now
**five minutes from PR workflow creation to the final `swift-test` status**
for ordinary source changes. This is a performance target, not a five-minute
kill switch. Cold caches and hosted runner queues must be included when
reporting results.

The workflow runs:

| Lane | When | Checks |
|---|---|---|
| `changes` | Every PR, main push, manual run | Script tests, subsystem README references, change classification |
| `debug-tests` | Code/input changes | One app/CLI/test build with concurrency warnings; all XCTest and Swift Testing cases; debug CLI smoke |
| `swift6` | Code/input changes, parallel with debug | First-party Swift 6 compilation without WhisperKit; informational format lint |
| `release` | Release-input PRs, every main push, manual run | Optimized release build, release CLI smoke, bundle smoke |
| `swift-test` | Always | Stable, fail-closed result for all required lanes |

Release inputs include package manifests/lockfile, `.github/`, `scripts/ci/`,
`scripts/dist/`, assets, source resources, Xcode projects/workspaces, plists,
entitlements, and xcconfig files. Ordinary source PRs deliberately do not
wait for release optimization. This accepts the risk that another release-only
compiler/linker error can first appear on main. Run manual CI before releasing;
the bundle smoke is not signing/notarization or complete distribution validation.

Only known prose paths skip compilation: root Markdown, Markdown under docs,
plans, spec, integrations, and source README files. The CLI changelog remains a
test input because `CLIVersionTests` checks it against the binary version. Unknown files,
fixtures, JSON contracts, and mixed changes still receive code checks. Renames
include old and new paths. The complete PR diff is used, not only its last commit.
There are no workflow-level path skips, so prose PRs also report a final status.

The dependency cache includes checkouts, repositories, binary artifacts and
SwiftPM workspace state. It does **not** claim incremental compiled-output reuse.
The Swift 6 lane has its own runner, so it no longer needs a second build path.
Default debug/release dependencies still include WhisperKit. Tests and product
behavior are unchanged; no regression suite has been removed.

## Grouped test execution

SwiftPM 6.0.2's `swift test --parallel` creates a new XCTest process for each
case. With more than 5,000 cases this repeats process startup and bundle loading
thousands of times. `run_tests.py` instead:

1. Discovers XCTest cases from the already-built package with SwiftPM.
2. Assigns whole classes to three groups, balancing case counts deterministically.
3. Runs each group in one `xcrun xctest` process, concurrently.
4. Requires each group's executed count to equal its discovered case count.
5. Runs native Swift Testing separately once, through SwiftPM.

Unknown discovery output, missing bundles, count mismatches, subprocess failures,
and timeouts fail the run. Every group gets a separate full log; assignments and
timings are saved as JSON. No test retries or failure suppression are added.
Class grouping preserves normal XCTest class lifecycle but does not preserve the
old process-per-test isolation. Tests must clean up shared state, as they must
for the supported default sequential `swift test` command.

Case-count balancing is not runtime balancing. The timing artifacts should guide
any later change to grouping; do not exclude expensive regression tests merely
to meet the target.

## Local verification

Run from the worktree that owns the change:

```bash
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
swift build --build-tests -Xswiftc -warn-concurrency
python3 scripts/ci/run_tests.py --filter 'TextProcessingPipelineTests|CLI.*Tests'
bash scripts/ci/cli_smoke.sh .build/debug/macparakeet-cli

# Once, as the final full-suite gate:
python3 scripts/ci/run_tests.py
```

The runner expects the default `.build/debug` location and one SwiftPM XCTest
bundle. It fails if the package changes to produce a different bundle layout.
The optional filter is for focused local checks; CI does not pass it.
`scripts/dev/ci_local.sh` remains the slower clean release-path check.

Artifacts under `.ci-logs/` include `test-shards.json`, `test-timings.json`, each
group's log, and native Swift Testing output. Build/test durations also appear
in the Actions job summaries. Use run/job timestamps for end-to-end time; do
not sum parallel job durations.

## Initial measurements

Local Apple Silicon, current installed Xcode (not the hosted Xcode 16.1 runner):

- Cold `swift build --build-tests -Xswiftc -warn-concurrency`: **136.71 seconds**.
- Focused 586 XCTest cases, grouped at three workers, including discovery and
  the filtered Swift Testing run: **25.36 seconds**.
- Same focus with SwiftPM per-test parallel execution and three workers:
  **32.21 seconds**.
- Default eight-worker per-test execution on this local machine: **13.55 seconds**.
  This is not an equal-worker comparison; more local CPUs can outweigh launch cost.

The final full-suite grouped run completed in **85.16 seconds**: all **5,136
XCTest cases** (including 20 existing skips) and **17 Swift Testing tests**, with
no failures. The three XCTest groups took 58.52, 82.85, and 60.02 seconds.
The local cold build plus full test execution therefore total **221.87 seconds
(3:42)**, excluding setup, CLI smoke, and the independent Swift 6 lane. The
slowest group contains both `MeetingAecMeasurementTests` (21.33 seconds) and
`DictationServiceTests` (19.02 seconds); runtime-aware grouping is a possible
next improvement if hosted results miss the target.

These are not proof of the hosted five-minute target. Validate a normal source
PR after the workflow is deployed, including cache restore and runner wait time.
A PR that changes this CI implementation also runs the release lane by design
and is not a normal-source timing sample.

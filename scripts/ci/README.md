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
| `preflight` | Every PR, non-documentation main push, manual run | Script tests, installer checks, subsystem README references, and change classification |
| `test_suite` | Code/input changes | One full Swift 6 app/CLI/test build with WhisperKit; all XCTest and Swift Testing cases; debug CLI smoke; informational format lint |
| `signed_test_dmg` | Explicit manual request on `main`, after protected-environment approval | Build, Developer ID sign, notarize, staple, verify, and upload a seven-day CI test DMG |
| `Build, Sign, and Publish GitHub Release` | Successful trusted `main` push CI with shipping changes | Derive the next tag, build, sign, notarize, verify, then publish `MacParakeet.dmg` on GitHub Releases |
| `ci_gate` (`swift-test` check) | Always | Stable, fail-closed result for all required lanes |

PR CI does not compile an unused optimized Release product or fixture app bundle.
The protected publication workflow builds and verifies the actual distributable
app and CLI once after the required CI checks pass. Release-only compiler,
packaging, signing, or notarization errors can therefore first appear during
publication.

All macOS lanes use the macOS 26 runner and Xcode 26.5. Distributable apps must
link the macOS 26 SDK so system SwiftUI controls, including the main sidebar,
have the same appearance as local development builds on macOS 26.

A manual run on `main` publishes the protected artifact only when
`publish_signed_artifact` is enabled
and the `signed-ci-artifact` environment approves the job. The protected job
requires a non-sentinel `X.Y.Z` input and environment secrets, uses a temporary
keychain, builds the normal runtime helpers and required meeting echo assets,
then runs the established signing/notarization path. It mounts and verifies the
DMG with `codesign`, Gatekeeper, and `stapler`, and executes helper version
smokes before uploading `MacParakeet-signed-notarized-ci-test` for seven days.
Missing credentials or any verification failure leaves no uploadable trusted
DMG. This test artifact is not published to GitHub Releases and is not an official
release.

Pushes to `main` do not start CI when all changed paths are ticket tracking,
anything under docs, plans, spec, or integrations, root Markdown, or source
README files. This also prevents a downstream `workflow_run` release workflow
from starting for those pushes. A mixed push starts the normal CI lanes. Manual
dispatch remains available. Pull requests
remain unfiltered so they report the stable final status.

The classifier uses the same ignored paths. The CLI changelog remains a test
input because `CLIVersionTests` checks it against the binary version. Unknown
files, test fixtures, and mixed changes still receive code checks. Renames
include old and new paths. The complete PR or push diff is used, not only its
last commit.

The separate release workflow runs only after successful push CI on this repository's
`main`. It compares the successful commit with the most recent `vX.Y.Z` tag. Production
sources, package manifests, assets, distribution scripts, resources, plists,
entitlements, and xcconfig files are shipping changes. Tests, tickets, documentation,
plans, specs, benchmarks, workflows, CI/development scripts, and all Markdown are not.
A reachable baseline version tag is required; this fork starts from `v0.7.3`. The
default increment is patch; `[minor]` and `[major]` in the commits since the prior tag
override it. Release runs are serialized. Verification completes before the workflow
pushes its annotated tag and creates the GitHub Release. Failed publication cleanup
removes draft releases and tags when GitHub confirms their incomplete state. The next
run applies the same cleanup to an interrupted automation tag that has no matching
release. A version tag with a different annotation, such as the intentional `v0.7.3`
baseline, is preserved when it has no GitHub Release and remains available to release
planning.

Default debug and production dependencies still include WhisperKit. Tests and
product behavior are unchanged; no regression suite has been removed.

## Compiled SwiftPM cache

Each build lane caches its complete `.build` directory: dependency checkouts,
compiled objects and modules, binary artifacts, module caches, and SwiftPM/llbuild
state. Keeping these together preserves the source/output timestamps needed for
reuse.

Cache keys include:

- The lane: Swift 6 debug/tests or optimized release.
- Actual Swift and Xcode versions, SDK build, macOS build, architecture,
  selected developer directory, and absolute checkout path.
- Package manifest and lockfile contents.
- Workflow, setup action, and cache-key implementation contents. This includes
  the compiler flags and optional dependency routes declared in the workflow.

There is no compiled-cache prefix fallback across incompatible inputs. On a
miss, the old source dependency cache can seed a cold build. Compatible keys
are stable across source commits: we do not upload a large archive on every PR
update. GitHub saves a new compiled cache only after the complete job succeeds.
Cache scope follows GitHub's branch rules: main can seed later PRs; one PR's
merge-ref cache does not seed unrelated PRs or main.

Every run still invokes SwiftPM on the current source checkout. Source mtimes
are **not** restored or normalized to trick the compiler into skipping work.
Cached first-party outputs are allowed, but current source changes must rebuild.
A real SwiftPM fixture archives/restores `.build`, proves unchanged dependency
objects are reused, then proves a changed app source produces the new binary
output. It uses POSIX/PAX tar, like Actions, to preserve sub-second timestamps.
The Linux control tests check key separation and invalidation without compiling
Swift. The debug lane runs the real cache fixture for CI/distribution input
changes, every non-documentation main push, and manual runs.

`build-cache.txt` records the key and hit status. A cache hit alone is not proof
of a faster build: compare cold and warm job times including restore/save time,
and inspect compilation messages to verify dependency objects were reused.
Compiled caching is optional for correctness; a miss takes the normal build
path. A cold run plus a same-head rerun is needed to measure the first rollout.

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

# Cache reuse/invalidation fixture (small isolated package, no project build):
CI_SWIFT_CACHE_INTEGRATION=1 python3 -m unittest discover -s scripts/ci -p 'test_build_cache.py'

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

## Hosted baseline before compiled caching

[Run 33970463983](https://github.com/eli0shin/macparakeet/actions/runs/33970463983)
passed on GitHub's macOS 14 / Xcode 16.1 runners:

| Work | Time |
|---|---:|
| Debug build (app, CLI, tests) | 4:33 |
| Full test execution (5,195 XCTest + 17 Swift Testing cases) | 2:30 |
| Debug job including setup/artifacts | 7:54 |
| Swift 6 job | 5:27 |
| Release job | 8:56 |
| Complete workflow, including release | 9:24 |

The five-minute ordinary-source target was **not met**. Compiled-cache savings
must be measured against this hosted baseline, not against the local figures
below. First-run cache creation may take longer; subsequent restores must save
more compilation time than their transfer/extraction cost.

## Initial local measurements

Local Apple Silicon, the Xcode version installed when these measurements were taken:

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
(3:42)**, excluding setup and CLI smoke. The
slowest group contains both `MeetingAecMeasurementTests` (21.33 seconds) and
`DictationServiceTests` (19.02 seconds); runtime-aware grouping is a possible
next improvement if hosted results miss the target.

These are not proof of the hosted five-minute target. Validate a normal source
PR after the workflow is deployed, including cache restore and runner wait time.
A PR that changes this CI implementation is not a normal-source timing sample.

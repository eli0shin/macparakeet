---
Assigned-To: macparakeet@033-skip-all-automation-for-docs-only-and-ticket-only-changes
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## Problem

A push containing only `.tickets/todo/032-remove-upstream-telemetry-from-fork-builds.md`
started CI run [34125359410](https://github.com/eli0shin/macparakeet/actions/runs/34125359410).
The run started debug tests, Swift 6 checks, a release build, and the development
artifact path. This wastes macOS runner time and can publish an artifact for a
change that does not alter the product.

The immediate cause is that `scripts/ci/classify_changes.py` deliberately
returns `code=true` and `release=true` for every push to `main`. The workflow
also has no path filter, so GitHub starts it for ticket and documentation-only
pushes.

## Required behavior

When every changed path is documentation or ticket tracking, GitHub Actions must
not start the CI workflow at all. This includes:

- `.tickets/**`
- `docs/**`, `plans/**`, `spec/**`, and `integrations/**`
- repository Markdown files such as `README.md`, `AGENTS.md`, and `CLAUDE.md`

A mixed push that contains any source, test, workflow, package, asset,
packaging, or other product input must still run CI normally. Manual
`workflow_dispatch` must remain available.

Use workflow `paths-ignore` rules for the no-run boundary. Align the existing
change classifier and its existing unit tests with the same path policy so a
future caller does not classify tickets as code or release inputs. Do not add a
new test framework or verification script.

Check the release work in ticket `030`: documentation-only and ticket-only
changes must not start or publish a tagged release after that workflow lands.
Do not weaken source-change CI or signed release verification.

## Acceptance criteria

- [ ] A push containing only `.tickets/**` changes starts no GitHub Actions CI
      workflow and creates no build, test run, artifact, tag, or release.
- [ ] The same no-run behavior applies to documentation-only changes in the
      listed documentation paths and repository Markdown files.
- [ ] A mixed push with at least one non-documentation/non-ticket path runs the
      existing CI lanes normally.
- [ ] `workflow_dispatch` still runs when invoked manually.
- [ ] The existing classifier tests are updated; no new test framework or
      standalone verification script is added.
- [ ] The future tagged-release flow from ticket `030` cannot publish from a
      documentation-only or ticket-only change.

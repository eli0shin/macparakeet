---
Assigned-To: macparakeet@030-publish-tagged-github-releases-from-ci
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Continuous delivery: every green push to `main` cuts a signed, notarized GitHub
Release with no human input. Nothing is typed, no version is entered, no tag is
pushed by hand.

Today `.github/workflows/` contains only `ci.yml`, triggering on `push: [main]`,
`pull_request`, and `workflow_dispatch`. Ticket `022` proved signing and
notarization work, but the version is a hand-passed `VERSION=X.Y.Z` env var and
the output is a 7-day workflow artifact. There is no version source of truth in
the repo, nothing creates a tag, and nothing publishes a release.

## Flow

```
push to main
  └─ ci.yml green
       └─ release.yml
            ├─ did any shipping file change? ── no ──▶ stop, no tag, no bump
            ├─ last tag v0.1.4 → next v0.1.5
            │    ([minor] or [major] in commit message overrides bump size)
            ├─ git tag v0.1.5 && git push --tags
            ├─ build + sign + notarize + verify
            └─ gh release create v0.1.5 MacParakeet.dmg
```

## What counts as a shipping change

Changes that do not alter the app users install must not cut a release or
increment the version. A docs edit, a ticket edit, or a test-only change leaves
the published version exactly where it was.

Ships: `Sources/` excluding tests, `Package.swift`, `Package.resolved`,
`Assets/`, `scripts/dist/`, and any `Resources`, `.plist`, `.entitlements`, or
`.xcconfig` path.

Does not ship: `Tests/`, `docs/`, `plans/`, `spec/`, `.tickets/`, `benchmarks/`,
`.github/`, `scripts/ci/`, `scripts/dev/`, and any `.md` file.

`scripts/ci/classify_changes.py` already classifies paths for CI cost control,
but neither of its existing flags is this set: `code` is true for tests and
tickets, and `release` is true only for packaging-affecting paths and false for
ordinary `Sources/*.swift` edits. Add a third classification rather than
overloading either. Note also that `classify_changes.py` short-circuits to all-
true on `main` pushes; the release gate needs the real diff against the previous
release tag, not that short-circuit.

Comparing against the previous tag rather than the previous commit matters: a
push that mixes a docs commit and a code commit must still release, and a run
that failed after tagging must not skip the code that was already tagged.

The previous git tag is the version source of truth; no `VERSION` file. The
default bump is patch. A commit message containing `[minor]` or `[major]`
selects a larger bump. The build number stays a monotonic UTC timestamp.

Reuse existing pieces rather than rebuilding: `build_app_bundle.sh`,
`sign_notarize.sh` (which already runs `verify_release_version.sh` and rejects
the sentinel `0.0.0`), `verify_signed_dmg.sh`, `verify_downloadable_app.sh`, and
the six secrets already provisioned in the protected `signed-ci-artifact`
environment.

Tag pushing requires write permission, so the release job needs
`permissions: contents: write`. `ci.yml` is currently `contents: read` — keep
that job read-only and scope the elevated permission to the release job alone.

## Distribution boundary

GitHub Releases on `eli0shin/macparakeet` is the only publication target. This
fork does not publish to Cloudflare R2, Cloudflare Pages, a Sparkle `appcast`,
or any Homebrew tap or cask. Ticket `031` removes the docs describing those
surfaces.

## Acceptance criteria

- [ ] A release workflow runs after CI succeeds on `main` and does not run for
      pull requests or other untrusted events.
- [ ] A push that changes only non-shipping paths produces no tag, no version
      increment, and no release.
- [ ] A push mixing shipping and non-shipping changes produces exactly one
      release.
- [ ] The shipping-path classification is unit tested, including tests,
      tickets, docs, and workflow files as non-shipping.
- [ ] The next version is derived from the most recent git tag, defaulting to a
      patch bump, with `[minor]` and `[major]` commit-message overrides.
- [ ] The workflow creates and pushes the `vX.Y.Z` tag itself.
- [ ] Elevated `contents: write` permission is scoped to the release job only.
- [ ] The build number remains a monotonic UTC timestamp.
- [ ] The release job uses the protected `signed-ci-artifact` environment and
      its existing six secrets, with the same ephemeral keychain and
      cleanup-on-failure behavior as `publish_signed_artifact.sh`.
- [ ] The DMG is verified with `verify_signed_dmg.sh` and
      `verify_downloadable_app.sh` before publication; verification failure
      blocks the release and leaves no tag behind.
- [ ] `gh release create` publishes on `eli0shin/macparakeet` with the DMG
      attached as `MacParakeet.dmg`.
- [ ] Concurrent or re-run pushes cannot produce a duplicate or skipped version.
- [ ] Tests cover version derivation from the previous tag, bump overrides,
      event gating, and fail-closed verification.
- [ ] A real merge to `main` produces a downloadable release whose DMG passes
      `codesign --verify --deep --strict`, `spctl --assess`, and
      `stapler validate` after download through the browser.

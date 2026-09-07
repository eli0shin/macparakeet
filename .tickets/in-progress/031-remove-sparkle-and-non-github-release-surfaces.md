---
Assigned-To: macparakeet@031-remove-sparkle-and-non-github-release-surfaces
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to do

GitHub Releases on `eli0shin/macparakeet` is the only publication target for
this fork. Remove Sparkle entirely, and remove the documentation that instructs
a reader to publish anywhere else.

Sparkle exists to deliver in-app updates from a hosted appcast feed. This fork
has no feed and will not have one, so the framework is dead weight: it embeds a
framework, three nested helper bundles, and XPC services into every build, all
of which must be signed, notarized, and verified. Users update by downloading
the newer DMG from GitHub Releases.

The docs danger is concrete: `npx wrangler r2 object put macparakeet-downloads/...`
and `wrangler pages deploy --project-name macparakeet-website` are scoped to a
Cloudflare account, not a GitHub repo. Being on a fork does not stop them from
overwriting the DMG and appcast that upstream's users auto-update from.

## Remove Sparkle

Framework and dependency:

- `Package.swift`: the `sparkle-project/Sparkle` package dependency and the
  `Sparkle` product on the app target.
- `Sources/MacParakeet/App/SparkleUpdateGuard.swift` and
  `Tests/MacParakeetTests/App/SparkleUpdateGuardTests.swift` — delete both.

Call sites (`import Sparkle`, `SPUStandardUpdaterController`, `SPUUpdater`):

- `Sources/MacParakeet/AppDelegate.swift` — the lazy `updaterController`
  properties.
- `Sources/MacParakeet/App/AppWindowCoordinator.swift` — the stored controller
  and its initializer parameter.
- `Sources/MacParakeet/App/MenuBarCoordinator.swift` — the stored controller and
  both "Check for Updates" menu items.
- `Sources/MacParakeet/Views/MainWindowView.swift` and
  `Sources/MacParakeet/Views/Settings/SettingsView.swift` — the `SPUUpdater`
  properties and the update section of the settings UI.

Do not touch the `sparkles` SF Symbol. It appears in roughly fourteen view files
and is unrelated.

Packaging:

- `scripts/dist/build_app_bundle.sh` — framework embedding, the rpath entry, and
  the `SUFeedURL` / `SUPublicEDKey` `Info.plist` keys.
- `scripts/dist/sign_notarize.sh` — nested signing of Sparkle's XPC services,
  `Autoupdate`, and `Updater.app`.
- `scripts/ci/verify_downloadable_app.sh`,
  `scripts/ci/publish_development_artifact.sh`, `scripts/ci/test_ci.py`,
  `scripts/dev/run_app.sh` — assertions and references to `Sparkle.framework`.

## Remove non-GitHub release docs

- `docs/distribution.md`: the R2 upload section, steps 3-7 of the release
  workflow, the "Standalone CLI Homebrew release" section, the R2/appcast/Pages/
  Homebrew quick-reference lines, the matching pitfalls rows, and the
  "Auto-Updates (Sparkle)" section in full.
- `scripts/dist/homebrew-tap-scaffold/` in full.
- `README.md` and `integrations/README.md`: Homebrew install instructions
  pointing at upstream's channels.
- `docs/human-qa-guide.md`: the Sparkle release-candidate QA path.
- `docs/marketing.md`: the official Homebrew cask claim.

## Leave alone

Historical and non-release material; rewriting it would falsify the record:

- `.tickets/done/`, `docs/audits/`, `docs/research/`, `docs/brainstorms/`,
  `docs/planning/`, `plans/active/`, `plans/completed/`
- `Sources/CLI/CHANGELOG.md`
- `docs/agents/qa-agents.md` and `docs/telemetry.md` — their Cloudflare and
  Homebrew mentions are telemetry endpoints and unrelated examples

`THIRD_PARTY_LICENSES.md` loses its Sparkle entry once the dependency is gone.

## Acceptance criteria

- [ ] No Sparkle package dependency, import, or symbol remains in `Sources/`,
      `Tests/`, or `Package.swift`.
- [ ] The built app bundle contains no `Sparkle.framework`, `Autoupdate`,
      `Updater.app`, or Sparkle XPC services.
- [ ] `Info.plist` no longer carries `SUFeedURL` or `SUPublicEDKey`.
- [ ] `build_app_bundle.sh` and `sign_notarize.sh` succeed with no Sparkle
      steps, and signing/notarization still passes on the resulting DMG.
- [ ] CI verification scripts no longer assert Sparkle's presence.
- [ ] No "Check for Updates" menu item or update section remains in the UI.
- [ ] The `sparkles` SF Symbol is untouched.
- [ ] No document instructs a reader to upload to R2, deploy to Cloudflare
      Pages, publish an appcast, or update a Homebrew tap or cask.
- [ ] `docs/distribution.md` describes exactly one release path.
- [ ] `scripts/dist/homebrew-tap-scaffold/` is deleted and nothing outside
      historical documents references it.
- [ ] `README.md` and `integrations/README.md` describe installing from this
      fork's GitHub Releases.
- [ ] `THIRD_PARTY_LICENSES.md` no longer lists Sparkle.
- [ ] `swift build` and `swift test` pass.
- [ ] Historical documents listed above are unmodified.

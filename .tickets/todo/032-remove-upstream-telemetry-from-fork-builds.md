---
Assigned-To:
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## Why

This fork publishes its own signed builds. Those builds must not send usage or
crash data to upstream infrastructure at `macparakeet.com`. The inherited
telemetry client is enabled by default and sends app, CLI, operation, device,
and crash events to `https://macparakeet.com/api/telemetry`. Publishing that
behavior under this fork creates an ownership and consent problem: users obtain
the app from this fork, but their data goes to a different operator.

The required security boundary is simple: a build published by this fork must
never contact the upstream telemetry endpoint. Prefer removal of network
telemetry over preserving an unused configurable pipeline.

## What to do

Remove the active telemetry and crash-upload path from fork builds.

Preferred implementation:

- Remove `TelemetryService` network delivery, the upstream endpoint, telemetry
  preference/configuration surfaces, and CLI telemetry initialization.
- Stop uploading pending crash reports. A local crash report can remain for
  user-requested diagnosis, but it must stay on the Mac unless the user
  explicitly attaches it to feedback.
- Remove the Settings telemetry toggle and CLI `config ... telemetry` option;
  neither should imply that this fork has a telemetry service.
- Remove telemetry-only tests and production code when they have no local use.
- Keep local `os.Logger` and audio diagnostic logging. They are not network
  telemetry and are useful when a user explicitly supplies diagnostics.
- Update active README, integration, architecture, feature, privacy, and ADR
  text so this fork states that it does not collect or upload telemetry.
  Preserve historical audit and planning records as historical records.

There are many `Telemetry.send(...)` call sites. If deleting all instrumentation
in one change creates excessive risk, the acceptable minimum for the next
published build is a compile-time/no-op boundary that cannot be enabled by
Settings, UserDefaults, CLI flags, environment variables, or dependency
injection. In that minimum implementation:

- Configure `NoOpTelemetryService` unconditionally for both app and CLI.
- Remove the default `https://macparakeet.com/api` URL and support for
  `MACPARAKEET_TELEMETRY_URL` from production code.
- Remove or disable pending crash-report upload.
- Remove user-facing controls and documentation that say telemetry can be
  enabled.
- Add a follow-up ticket for deletion of the remaining dead event definitions
  and call sites.

Do not change user-initiated feedback delivery in this ticket. Feedback is a
separate explicit action and has its own endpoint and attachment controls. Do
make sure crash or diagnostic data is not sent through feedback without the
existing explicit user action.

## Governing files

Start with:

- `Sources/MacParakeetCore/Services/Telemetry/TelemetryService.swift`
- `Sources/MacParakeetCore/Services/Telemetry/CrashReporter.swift`
- `Sources/MacParakeetCore/Services/Telemetry/TelemetryEvent.swift`
- `Sources/MacParakeet/App/AppEnvironment.swift`
- `Sources/MacParakeet/AppDelegate.swift`
- `Sources/CLI/Commands/CLITelemetry.swift`
- `Sources/CLI/Commands/ConfigCommand.swift`
- `Sources/MacParakeetViewModels/SettingsViewModel.swift`
- `Sources/MacParakeet/Views/Settings/SettingsView.swift`
- `README.md`, `integrations/README.md`, `docs/telemetry.md`
- `spec/adr/012-telemetry-system.md`, `spec/README.md`,
  `spec/02-features.md`, and `spec/03-architecture.md`

Check all of `Sources/`, packaging scripts, and generated app metadata for
`macparakeet.com/api/telemetry`, the broader upstream API base URL, and
telemetry environment overrides. Do not remove unrelated URLs needed for model
downloads, user-selected AI providers, media imports, or explicit feedback.

## Acceptance criteria

- [ ] The app and CLI composition roots contain no telemetry transport and do
      not start an automatic crash-report upload.
- [ ] Production code contains no upstream telemetry endpoint and no HTTP
      telemetry request builder.
- [ ] `MACPARAKEET_TELEMETRY_URL`, `MACPARAKEET_TELEMETRY`, `DO_NOT_TRACK`, and
      persisted `telemetryEnabled` state cannot enable telemetry in the app or
      CLI.
- [ ] A pending crash report remains local or is removed locally; it is not
      uploaded automatically on the next launch.
- [ ] Settings and CLI help/config do not expose a telemetry switch that no
      longer has a service behind it.
- [ ] Active privacy and architecture documentation says that fork builds do
      not collect or upload telemetry and does not direct contributors to the
      upstream Cloudflare Worker or D1 database.
- [ ] Historical audit/planning documents remain intact or are clearly marked
      as upstream history rather than rewritten as current fork behavior.
- [ ] User-initiated feedback still works and does not attach crash reports or
      diagnostic logs without explicit user action.
- [ ] Do not add tests or a new telemetry-specific verification script. Remove
      or update inherited tests only as needed after the telemetry code is
      removed or disabled.
- [ ] Review confirms that production source contains no upstream telemetry URL,
      telemetry transport wiring, or automatic crash-upload call.
- [ ] `swift build` and the existing `swift test` suite pass.

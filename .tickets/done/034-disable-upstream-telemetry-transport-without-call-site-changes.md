---
Assigned-To:
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## Goal

Prevent this fork from sending telemetry or crash data to upstream developer infrastructure. This is a very small transport-configuration change. It is not a telemetry cleanup or refactor.

## Hard scope boundary

Every existing telemetry call site must remain in place. Do not delete, rename, move, rewrite, or otherwise modify any `Telemetry.send(...)` call site, event definition, event case, event catalog, telemetry-named helper, local spy, or related function signature anywhere in the project.

Preserve the existing UI and all other product behavior. The existing telemetry control may only be made non-interactive and forced off. Do not remove or redesign the control.

Only change the minimum code that:

1. defines or selects the upstream telemetry URL or transport;
2. composes the telemetry service in the app or CLI;
3. reads configuration to decide whether remote telemetry is enabled; or
4. enables or disables the existing telemetry UI control.

Remove the upstream telemetry URL and any override that can restore it. Force the effective telemetry setting off. Configure only a no-op transport so preferences, UserDefaults, environment variables, CLI flags, or dependency injection cannot enable remote telemetry or automatic crash upload.

## Forbidden changes

- Do not modify a single telemetry call site.
- Do not delete telemetry instrumentation, event definitions, event cases, helpers, or tests.
- Do not rename telemetry-related or unrelated symbols.
- Do not modify ADRs, specs, READMEs, changelogs, or any other documentation.
- Do not perform formatting, cleanup, signature propagation, API reshaping, or adjacent refactoring.
- Do not expand scope for reviewer suggestions, minor findings, style issues, documentation consistency, or cleanup opportunities.
- If the required security boundary cannot be completed within the allowed setup, URL, enablement, and existing-control code, stop and report the blocker. Do not widen the diff.

## Review rule

Only a proven correctness or security defect inside the allowed files can block this ticket. Ignore reviewer requests that add files, cleanup, documentation, renames, call-site edits, or any other scope. There must be no iterative scope expansion.

## Acceptance criteria

- [x] Every telemetry call site and event definition is byte-for-byte unchanged.
- [x] The existing telemetry UI remains present, is disabled, and cannot enable telemetry.
- [x] No upstream telemetry URL or environment override remains available to production composition.
- [x] App and CLI always use a no-op telemetry transport.
- [x] Automatic crash upload cannot start.
- [x] Preferences, UserDefaults, environment variables, CLI flags, and dependency injection cannot enable remote telemetry.
- [x] No ADR, spec, README, changelog, test, or unrelated file changes.
- [x] The diff is limited to the minimum telemetry setup, URL, enablement, and existing-control files.
- [x] Existing focused build and tests pass without modifying tests.

## Resolution

PR #37 merged as `8290e16e`. The implementation changed three allowed composition/control files with 8 additions and 3 deletions. CI run `34154523039` passed, and release run `34155638464` published signed and notarized `v0.7.5` for the exact merge SHA.

Downloaded release asset SHA-256: `f42b8bf6b20839db06360fd84a64ba12d53e0259f0d274de79b948557843763b`. Direct verification passed Developer ID identity/team checks, notarization and staples, Gatekeeper assessment, nested signatures, packaged helpers, privacy-surface checks, and isolated launch outside the checkout. Packaged executables contain no `MACPARAKEET_TELEMETRY_URL`, `MACPARAKEET_TELEMETRY_ENABLED`, or `/telemetry` transport marker. The remaining shared `https://macparakeet.com/api` string belongs to the preserved user-initiated feedback service.

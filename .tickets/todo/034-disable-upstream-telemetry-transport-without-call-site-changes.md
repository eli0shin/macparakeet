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

- [ ] Every telemetry call site and event definition is byte-for-byte unchanged.
- [ ] The existing telemetry UI remains present, is disabled, and cannot enable telemetry.
- [ ] No upstream telemetry URL or environment override remains available to production composition.
- [ ] App and CLI always use a no-op telemetry transport.
- [ ] Automatic crash upload cannot start.
- [ ] Preferences, UserDefaults, environment variables, CLI flags, and dependency injection cannot enable remote telemetry.
- [ ] No ADR, spec, README, changelog, test, or unrelated file changes.
- [ ] The diff is limited to the minimum telemetry setup, URL, enablement, and existing-control files.
- [ ] Existing focused build and tests pass without modifying tests.

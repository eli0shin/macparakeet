---
Assigned-To: macparakeet@034-delete-dead-telemetry-instrumentation
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## Why

Ticket 032 removed all remote telemetry transport and automatic crash upload.
The inherited event catalog, `Telemetry.send(...)` call sites, and local test
spies remain as inert compatibility code to keep that security change scoped.

## What to do

Delete the dead event definitions, inherited call sites, telemetry-only local
spies, and telemetry-named helpers that have no non-telemetry use. Preserve
local `os.Logger`, audio diagnostics, user-initiated feedback, and local crash
reports. Do not add a new analytics transport.

## Acceptance criteria

- [ ] Production code has no dead `Telemetry.send(...)` instrumentation.
- [ ] Telemetry-only types and tests are removed.
- [ ] Local logging, diagnostics, feedback, and crash-report persistence keep
      their current behavior.
- [ ] Active documentation remains clear that fork builds do not collect or
      upload telemetry.

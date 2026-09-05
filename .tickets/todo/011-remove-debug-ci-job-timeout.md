---
Assigned-To:
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Increase the CI `debug-tests` job timeout from 10 minutes to 20 minutes so a successful build and test run is not cancelled during cache cleanup.

## Acceptance criteria

- [ ] The `debug-tests` job timeout is 20 minutes.
- [ ] Existing step-level timeout and fast-PR behavior remain unchanged unless a test requires a narrow correction.
- [ ] CI workflow tests cover the 20-minute job timeout.
- [ ] Applicable CI checks pass.

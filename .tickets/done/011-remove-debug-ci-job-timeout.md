---
Assigned-To: macparakeet@011-remove-debug-ci-job-timeout
Tags:
  - ready-for-agent
Parent:
Blocked-By: []
---

## What to build

Increase the CI `debug-tests` job timeout from 10 minutes to 20 minutes so a successful build and test run is not cancelled during cache cleanup.

## Acceptance criteria

- [x] The `debug-tests` job timeout is 20 minutes.
- [x] Existing step-level timeout and fast-PR behavior remain unchanged unless a test requires a narrow correction.
- [x] CI workflow tests cover the 20-minute job timeout.
- [x] Applicable CI checks pass.

## Resolution

Increased the `debug-tests` outer job timeout to 20 minutes while preserving all step-level timeouts and fast-PR behavior. Added focused workflow coverage. Reviewed and merged in PR #11 at commit `9cb15796dd4e3ec8de875b2fb970b7ab032cf2a9`.

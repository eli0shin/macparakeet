---
Assigned-To:
Tags:
  - ready-for-agent
Parent: 019-restore-downloadable-development-builds
Blocked-By: []
---

## What to build

Fix the landing development artifact so the packaged app actually launches after the documented quarantine-removal step. Artifact `9983487734` from run `34013802132` passed archive, DMG, signature, symlink, helper, CLI, and sensitive-file checks, but the exact downloaded app terminated immediately with illegal instruction after quarantine removal.

The captured launch error is:

```text
MacParakeet/resource_bundle_accessor.swift:12: Fatal error: could not load resource bundle: from .../MacParakeet.app/MacParakeet_MacParakeet.bundle or /Users/runner/work/macparakeet/macparakeet/.build/arm64-apple-macosx/release/MacParakeet_MacParakeet.bundle
```

Diagnose the bundle-layout contract used by SwiftPM-generated resource accessors. Correct the production-shaped app assembly at the governing distribution seam, not only the CI wrapper, and preserve official release behavior. Add an agent-runnable packaged-launch smoke that catches this exact immediate termination without relying on a developer checkout path. Do not weaken signing or package allowlists.

## Acceptance criteria

- [ ] A pre-fix packaged-app launch smoke deterministically catches the missing `MacParakeet_MacParakeet.bundle` failure.
- [ ] The app assembly places or resolves all SwiftPM resource bundles where their generated accessors expect them.
- [ ] The packaged app remains alive past startup when launched outside the checkout after quarantine removal.
- [ ] Resource access works without fallback to `/Users/runner/work/.../.build/...` or any checkout path.
- [ ] The change applies consistently to development, protected signed/notarized, and official distribution bundles.
- [ ] Strict signatures, package allowlists, relative symlinks, helper/CLI smokes, and Applications shortcut remain valid.
- [ ] Workflow or distribution tests lock the packaged-launch and resource-layout contract.
- [ ] Applicable CI checks pass, then the landing artifact is downloaded and launch-tested again.

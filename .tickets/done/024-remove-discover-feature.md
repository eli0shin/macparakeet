---
Assigned-To: macparakeet@024-remove-discover-feature
Tags:
  - ready-for-agent
Parent: 023-simplify-meeting-transcript-experience
Blocked-By: []
---

## What to build

Remove Discover completely. Delete the small pinned Discover hint at the bottom of the main sidebar and the page it opens. Remove the now-unused feature rather than leaving a hidden network or cache subsystem behind.

The removal includes navigation state and routing, views, view model, models, services, remote feed requests, thoughts submission, local cache, bundled fallback content, telemetry cases used only by Discover, dependency wiring, tests, and obsolete feature documentation. Preserve generic infrastructure that has other callers. Update architecture and UI specifications so they describe the product that remains.

## Acceptance criteria

- [x] The pinned Discover sidebar hint and Discover destination no longer exist.
- [x] No hidden Discover feed refresh, cache read/write, or thoughts submission runs at launch or later.
- [x] Discover-only views, models, services, assets, dependency wiring, telemetry, and tests are removed.
- [x] Shared telemetry or networking infrastructure used by other features remains intact.
- [x] Navigation selection migration or fallback cannot leave the main window blank when an old persisted selection names Discover.
- [x] Architecture, UI, privacy/network, and telemetry documentation contains no stale claim that Discover is an active product surface.
- [x] Focused navigation and startup tests prove the remaining sidebar destinations work.
- [x] Applicable CI checks pass.

## Resolution

Removed the complete Discover product surface while preserving the shared Merkaba shape used by prompts. Added startup and navigation coverage for the remaining destinations. Reviewed and squash-merged PR #23 at commit `700ade0f`.

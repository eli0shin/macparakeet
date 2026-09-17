# Universal Processing Progress Prototype

Throwaway UI prototype for one app-wide offline-processing surface.

Open `index.html` in a browser. Use the floating switcher or the Left and Right Arrow keys to compare:

- **A — Focus bar:** one foreground operation with secondary work behind a count.
- **B — Focused stack:** the focused bar stays compact; **2 more** opens equally detailed concurrent-job bars above it.
- **C — Summary + inspector:** a compact summary opens a structured job inspector.

Use the scenario controls to inspect one job, concurrent work, a completed transcript with AI content, and item-owned failures. **View** navigates to the related Library item; the current item has no redundant action label. The selected B direction combines the focused progress stack with one compact issue summary. The summary expands, but individual issue rows do not. Each issue has an × dismiss control, and a defined recovery action (`Retry`) appears directly beside ×. Completed work, including the “Transcript ready + AI” scenario, has no global footer.

No production logic, persistence, network access, or animated progress is included.

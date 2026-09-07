# Ticket 028 implementation

Scope: `.tickets/todo/028-add-custom-words.md`. Agreed English Parakeet TDT final
recognition, one existing word store, opt-in download, bounded long audio,
honest fallback, focused verification. No benchmark project.

Must preserve: stored entries, replacement/Raw semantics, base transcripts on
failure, cancellation, word timing alignment, scheduler/ANE gate, privacy.

Implementation and automated verification complete:
- Shared vocabulary validation, distinct entry forms, activation consent and progress.
- FluidAudio 0.15.6, opt-in short-term safety controls, and ModelHub migration.
  Unified explicit downloads/cache checks retain the context-specific encoder;
  the obsolete preprocessor is no longer required by the SDK.
- Admission-time vocabulary snapshots, content-free notices, bounded overlapping
  audio windows, source-relative timing edits, and cancellation-aware preparation.
- CLI controls/contracts, docs, and independent review approved.
- 226 focused tests passed. Swift 6 build passed (WhisperKit excluded as in CI).
- Full suite ran once: 5,214 tests, 21 skipped, four assertions failed in two
  Unified cache tests. Fixed the compatibility issue; affected tests passed on
  focused rerun. Full suite not repeated.

User-verified on 2026-09-06: vocabulary hints work with Parakeet in MacParakeet Dev.
This is a practical smoke result, not a measured accuracy claim. Changes remain
uncommitted. See the ticket handoff for automated verification details.

Upstream evidence: FluidAudio PR #722 documents optional short-term boost taper
and spotter similarity floors; #805 adds non-mutating candidate spans. These
support conservative matching and bounded rescoring. They do not establish
measured improvement for this app. Release 0.15.6 also includes long-audio merge
and model download fixes. No model weights will be downloaded during automated
tests. `no-mistakes` is not installed in this environment.

# Meeting Artifacts v1

## Meeting speaker detection

`meeting-recording-metadata.json` and `recording.lock` include the additive
track-specific choices `systemSpeakerDetection` and
`microphoneSpeakerDetection`. New recordings capture both defaults at start.
The in-meeting audio-controls popover can change either choice independently;
a successful change atomically rewrites `recording.lock`, applies to later live
preview chunks and that meeting's final transcript, and becomes the default for
new meetings. Already displayed live words keep their attribution. A chunk
whose speaker-detection work is in flight when the choice changes is reconciled
to the latest successfully persisted choice before it is emitted, so a stale
result cannot restore the previous attribution behavior. Each independent live
diarization call namespaces its local speaker IDs because repeated local indices
such as `S1` are not evidence of one identity across chunks. Live preview does
not perform cross-chunk speaker matching.

Missing or malformed `systemSpeakerDetection` values identify legacy artifacts
and use the current meeting default during finalization or app-default archive
retranscription. Missing or malformed `microphoneSpeakerDetection` values
decode as false. Lock rewrites, metadata updates, normal stop, crash recovery,
and archive loading preserve captured choices. Explicit CLI on/off options and
`--no-diarize` still override captured choices for that CLI run. No database
migration is needed; speaker IDs and timing evidence use the existing
transcript fields.

Enabled recordings use `microphone:<id>` for detected local speakers and
`microphone:unknown` for unattributed local speech. Default labels are
`Local Speaker N` and `Local Speakers`. Disabled and legacy recordings retain
`microphone` / `Me`; system IDs remain `system:<id>` with `system` as fallback.
IDs preserve capture source even after a speaker is renamed. There is no
cross-track identity matching. Readable artifacts, exports, and agent context
use the same source-aware Reading Turns as the app.

Detection runs after capture, on the same microphone audio selected for STT.
It needs timed words. Empty or failed detection retains the transcript with a
neutral local label; cancellation aborts finalization. Audio retention is
unchanged. Adjust Speakers requires retained audio, changes attribution only
on the selected track, and preserves the other track's evidence and names.

> Status: ACTIVE - stable local meeting session artifact contract.

## Purpose

A meeting session folder is the durable local view of a recorded meeting. It is
safe for Finder actions, CLI automation, hooks, support diagnostics, and future
agent workflows to inspect. The database row remains canonical for meeting
identity and current metadata; files are refreshed views of that row and its
related prompt results.

For meeting rows, `transcriptions.meetingArtifactFolderPath` is the durable
folder locator. `transcriptions.filePath` is only the mixed-audio
playback/export path and may be cleared by user deletion or retention.

## Producers

- `MeetingRecordingService`: creates session folders and source audio.
- `MeetingTranscriptFinalizer` / meeting finalization: completes the DB row and
  final transcript.
- `MeetingArtifactStore`: materializes `manifest.json`, `meeting.md`,
  `transcript.json`, `notes.md`, `prompt-results.json`, and
  `prompt-results/*.md`.
- `macparakeet-cli meetings artifact`: refreshes and returns the artifact
  snapshot.
- Meeting notes and prompt-result write paths: refresh artifact views after
  user notes or agent-authored results change.

## Consumers

- Library, Meetings, and detail-view "Open Meeting Folder" / "Copy Artifact
  Folder Path" actions.
- Audio-specific "Show Audio in Finder" / "Save Audio As..." actions while
  retained meeting audio is still available.
- `macparakeet-cli meetings artifact` and `--envelope` output.
- Meeting automation hooks through `MACPARAKEET_ARTIFACT_DIR` and
  `MACPARAKEET_ARTIFACT_MANIFEST`.
- Support diagnostics and future local agent workflows.

## Stable Folder Entries

The v1 folder can contain these stable filenames:

- `meeting-playback.m4a`: mixed playback/export audio referenced by
  `transcriptions.filePath` while retained.
- `microphone-raw.m4a`: optional source mic audio.
- `system-raw.m4a`: optional source system audio.
- `microphone-cleaned.m4a`: optional derived echo-cancelled mic (16 kHz mono),
  produced after stop from `microphone-raw.m4a` + `system-raw.m4a` when a meeting echo
  suppressor is loaded (plan #605 U3). Internal STT input for the local ("Me")
  track only after final-STT readiness/decodability gates pass, not a
  user-facing export; the raw `microphone-raw.m4a` remains the source of truth.
  Absent on initial cleanup for single-source meetings, missing/unloaded AEC
  assets, render failures, and when the echo-path probe finds no system-audio
  bleed to cancel. GUI and CLI retranscription regenerate this derived file
  from retained source tracks with a snapshot of the current residual echo
  setting, including when a cleaned file already exists. Successful renders
  replace the prior derived file; failed, timed-out, or cancelled renders keep
  it but do not route the current transcription to that stale file. Raw tracks
  and playback remain unchanged. Removed with other managed audio by
  retention/detach.
- `meeting-recording-metadata.json`: optional source-alignment and speech-route
  sidecar. It also keeps the optional captured `systemSpeakerDetection` choice
  and the default-false `microphoneSpeakerDetection` choice described above.
  `speechEngine` is the authoritative final-transcription selection;
  optional additive `previewSpeechEngine` records the live-preview route when
  one was supported. Missing preview provenance remains valid for legacy
  folders. It may also include additive `echoSuppression` provenance with
  `reasonCode` plus optional `modelVersion`, `renderDurationMs`,
  `delayEstimateMs`, and `probeBestCorrelation` fields so shared artifact
  folders can explain cleaned-vs-raw microphone routing without app logs.
  The additive `rawNotPrepared` reason means no render was scheduled and no
  usable cleaned file was found; it does not assert that AEC assets are missing.
  `rawNoAECAssets` is reserved for an unavailable processor. It
  may also include additive `startContext` with the one-shot local start
  snapshot. `calendarEventSnapshot`, when present, is local EventKit context
  and can include attendee/organizer names and emails. New finalized recordings
  also include additive `captureReport`, the frame-derived recording coverage
  report described below; legacy sidecars may omit it. An unreadable optional
  report is treated as unknown without invalidating the remaining sidecar.
  Each source-alignment track keeps `writtenFrameCount` as real captured frames
  and may include `timelineFrameCount` for its playable end after inserting
  silence across capture-recovery gaps. Legacy tracks omit the latter and use
  written frames for both meanings. New captures derive start offsets from each
  writer's effective file origin, so leading buffers without a valid host time
  are not shifted a second time when timestamps become available. Crash
  recovery preserves known host times and start offsets, rescales the real
  written duration to a repaired file's sample rate (clamped to surviving
  media), refreshes the playable timeline from the repaired media, and drops
  tracks whose media cannot be recovered.
- `manifest.json`: folder manifest.
- `meeting.md`: deterministic Markdown view for users and local agents. It
  keeps YAML frontmatter with local metadata and stable sections for title,
  notes when present, transcript, prompt results when present, and artifact
  paths. Completed, unedited meetings project the same Reading Turn document as
  the app, readable exports, and AI context, including one start time per turn.
  Edited meetings use plain edited transcript text because word alignment is no
  longer valid. Untimed fallback text does not fabricate a speaker or time.
- `transcript.json`: transcript view. It keeps separate raw and cleaned text;
  its readable `transcript` projection prefers cleaned text.
- `notes.md`: optional user notes view. Removed when notes are empty or nil.
- `prompt-results.json`: JSON array of prompt-result records.
- `prompt-results/`: refreshed directory of per-result Markdown files.
- `prompt-results/*.md`: filenames use a stable two-digit 1-based index prefix
  plus sanitized prompt-result name.

New recordings write the role-explicit audio filenames above. For read
compatibility with folders created before the in-place v1 audio filename
rename, readers and artifact materializers must also resolve legacy
`microphone.m4a` and `system.m4a` when the current raw-audio filename is absent.
Regenerated `manifest.json` and `meeting.md` path fields point to the actual
existing current or legacy raw-audio file. New captures must not create legacy
raw-audio filenames.

## Stable JSON Fields

`MeetingArtifactSnapshot` and CLI artifact output keep these fields stable:

- `schema`: `com.macparakeet.meeting-session`
- `schemaVersion`: `1`
- `generatedAt`
- `meetingID`
- `title`
- `folderPath`
- `manifestPath`
- `markdownPath`
- `rawMicrophoneAudioPath`
- `cleanedMicrophoneAudioPath`
- `rawSystemAudioPath`
- `playbackAudioPath`
- `transcriptPath`
- `notesPath`
- `promptResultsPath`
- `promptResultsDirectoryPath`
- `promptResultCount`
- `calendarEventSnapshot`
- `meetingCaptureReport`

`manifest.json` keeps:

- `schema`
- `schemaVersion`
- `generatedAt`
- `meeting` (including optional `startContext`)
- `files`
- `promptResults`

`manifest.meeting.calendarEventSnapshot`, when present, keeps the same local
EventKit snapshot shape as `transcriptions.calendarEventSnapshot`: confidence,
event identifiers, scheduled time range, title, attendee/organizer names and
emails, meeting URL/service, and capture timestamp.

`manifest.meeting.meetingCaptureReport`, `transcript.json`'s optional
`meetingCaptureReport`, and `MeetingArtifactSnapshot.meetingCaptureReport` use
the same additive shape as `transcriptions.meetingCaptureReport`:

- `quality`: `healthy` or `partial`
- `sourceMode`: `microphone_only`, `system_only`, or `microphone_and_system`
- `elapsedDurationMs`: pause-adjusted time capture was expected to be active
- `capturedDurationMs`: end of the longest selected playable source timeline,
  including silence inserted to preserve capture-recovery gaps
- `sources`: stable microphone/system-order records with `source`,
  `writtenDurationMs`, `coverageRatio`, and `status` (`complete`,
  `coverage_shortfall`, `interrupted`, `unavailable`, or `capture_failed`)
- `interruptedSources`: terminally interrupted selected sources
- `captureFailed`: runtime capture-control failure, kept separate from final
  frame-derived quality
- `playbackFallbackSource`: optional `microphone` or `system` marker when both
  selected source files were decodable but canonical playback had to use only
  the named source because combining them failed; its presence makes `quality`
  partial without changing otherwise-complete source capture statuses

Meeting `durationMs` is the probed duration of the decodable
`meeting-playback.m4a` artifact. Normal finalization keeps it equal to
`capturedDurationMs`. Crash recovery refreshes surviving source media facts and
rebuilds `capturedDurationMs`, while preserving elapsed/interruption history,
so both values remain coherent even when a damaged source must be dropped. A
partial report does not change transcription `status`: successfully processed
partial audio remains `completed`. Archived reconstruction re-probes the
resolved canonical playback file and uses a supplied stored duration only when
that media probe fails. Missing or unreadable reports on legacy artifacts mean
unknown, not healthy.

`manifest.files` keeps path fields for `folderPath`, `playbackAudioPath`,
`rawMicrophoneAudioPath`, `cleanedMicrophoneAudioPath`, `rawSystemAudioPath`,
`metadataPath`, `manifestPath`, `markdownPath`, `transcriptPath`, `notesPath`,
`promptResultsPath`, and `promptResultsDirectoryPath`.

`meeting.md` frontmatter keeps the local Markdown schema
`com.macparakeet.meeting-markdown` with `schemaVersion: 1`, meeting identity,
timestamps, duration/status/source/engine metadata, artifact/audio paths when
available, `speakerLabelsIncluded`, and `promptResultCount`. The body section
order is: title, optional notes, transcript, optional prompt results, and
artifact paths.

`transcript.json` keeps meeting essentials: `id`, `title`, timestamps,
`durationMs`, `status`, raw/clean/transcript text, word/speaker/diarization
fields, durable `transcriptSegments`, `userNotes`, language/engine attribution,
`sourceType`, `recoveredFromCrash`, `isTranscriptEdited`, and optional
`startContext`, `calendarEventSnapshot`, and `meetingCaptureReport`.

For newly finalized and explicitly re-transcribed meetings, `rawTranscript`
and `wordTimestamps` preserve STT evidence while `cleanTranscript` stores the
separate deterministic readable text. Existing meeting artifacts are not
backfilled on read; a refreshed legacy artifact can still derive its readable
Markdown projection without changing the database row. Evidence-focused JSON
fields and subtitle cues remain raw and timed.

`transcriptSegments` is an additive v1 field populated from the DB row when a
meeting has durable segments. Each segment keeps `id`, `startMs`, `endMs`,
`speakerId`, `speakerLabel`, `text`, and a half-open `wordRange`
(`startIndex`, `endIndexExclusive`) into the same transcript's
`wordTimestamps` array. Segment IDs are stable for that transcript version;
meeting retranscription may replace the array with newly minted segment IDs.

`startContext`, when present, keeps the recording-start snapshot:

- `triggerKind`: `manual`, `hotkey`, or `calendar_auto_start`
- `sourceMode`: configured meeting source mode at start (`microphone_only`,
  `microphone_and_system`, or `system_only`)
- `frontmostApplication`: optional object with `bundleIdentifier` and
  `localizedName`

`calendarEventSnapshot`, when present, keeps local calendar context captured at
recording start. It can include EventKit identifiers, title, scheduled
start/end, attendee/organizer names and emails, meeting URL/service, confidence,
and capture timestamp.

## Non-Stable Fields

- `generatedAt` changes on every materialization.
- Absolute paths vary by user, configured meeting artifact folder, and DEBUG
  smoke-state root.
- Prompt-result ordering follows the supplied prompt-result input order.
- Prompt-result Markdown body can gain additive sections when the
  corresponding JSON fields remain readable.

## Versioning And Compatibility

The current schema is v1. This contract absorbed the pre-hardening rename to
role-explicit audio filenames and path fields in place before external
compatibility was promised. Future additive fields and new optional files can
remain v1 when old consumers can ignore them. Future renames or removals of
stable filenames or fields require a schema-version bump and CLI/changelog
notes.

The database row stays canonical. Do not teach features to treat the folder as
the source of truth for mutable meeting metadata unless the contract is updated
with a migration and conflict-resolution rule.

Audio retention and "Remove Audio Only" clear `transcriptions.filePath` but
must preserve `transcriptions.meetingArtifactFolderPath` and leave the folder's
non-audio artifact files in place. The retention sweeper acts only on the
age-based `delete_after_days` mode. `delete_immediately` ("Remove audio after
transcription") applies at capture/finalization to new recordings and must
never retroactively remove previously saved audio — selecting it in Settings
is not consent to delete the existing library. Bulk meeting-audio cleanup removes top-level
app-managed audio files in the session folder, including canonical filenames
and other managed audio extensions, while preserving JSON/Markdown artifacts.
Full meeting deletion removes the artifact folder even when retained audio was
already deleted.

## Tests that enforce this

- `MeetingArtifactStoreTests`
- `MeetingsCommandTests`
- `HistoryCommandTests`
- `MeetingAudioRetentionSweeperTests`
- `TranscriptionDeletionCleanupTests`
- `TranscriptionRepositoryTests`

Focused coverage pins stable filenames, schema/schemaVersion, manifest path
references, `meeting.md` frontmatter/sections, transcript essentials,
`notes.md` deletion, refreshed `prompt-results/` contents, durable transcript
segments in `transcript.json`, speaker-label Markdown fallback, non-meeting
rejection, CLI artifact envelope fields, retained-out audio, full deletion
after audio detach, and artifact-folder path preservation.

## When this changes

Update this file, `spec/01-data-model.md`, `Sources/CLI/CHANGELOG.md` when CLI
users are affected, and the focused XCTest coverage in the same PR.

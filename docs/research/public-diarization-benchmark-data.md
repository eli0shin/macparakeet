# Public audio and reference annotations

Primary-source check, 2026-09-09. No datasets downloaded or benchmark runs performed.

## AMI: best first fit for meeting transcription and diarization

The AMI corpus contains approximately 100 hours of human meeting recordings, with synchronized headset and distant-microphone channels, orthographic transcripts, and manual annotations. Many meetings are role-based design scenarios; others are naturally occurring. Signals, transcripts, and some annotations are CC-BY-4.0. The download selector allows individual meetings/channels rather than requiring the entire corpus.

- Corpus: https://groups.inf.ed.ac.uk/ami/corpus/index.shtml
- Audio and manual annotation downloads: https://groups.inf.ed.ac.uk/ami/download/
- Official partitions: https://groups.inf.ed.ac.uk/ami/corpus/datasets.shtml
- Ready-made diarization references and scoring setup: https://github.com/BUTSpeechFIT/AMI-diarization-setup

The BUT setup derives RTTM references from manual annotations v1.6.2 and uses the Full-corpus-ASR partition. Its references merge adjacent same-speaker word segments but retain actual silent gaps; this is an acoustic scoring convention, not a requirement for separate rendered Reading Turns. Select a declared partition and channel condition. Headset mix and single distant microphone should be reported separately. ES2004a is one available evaluation meeting; selecting a small subset is a diagnostic run, not a published whole-corpus score.

## VoxConverse: additional multi-speaker/overlap coverage

Public RTTM speaker-time references for varied real-world video audio, including debates/news and overlapping speech. The maintainers explicitly require version 0.3 because earlier test references had errors.

- Repository and referenced audio archives: https://github.com/joonson/voxconverse
- Dataset site: https://robots.ox.ac.uk/~vgg/data/voxconverse/index.html

Availability caveat: the repository lists audio archives, but the official site currently says audio is unavailable there. Archive availability was not verified by downloading. Do not promise immediate access to the audio. The repository specifies research use under CC-BY-4.0 with original video copyright retained.

## LibriSpeech: transcription-only control

Read English audiobook speech paired with reference text, CC-BY-4.0. `test-clean` is approximately 346 MB compressed and `test-other` approximately 328 MB. Useful for word recognition, not natural multi-speaker turn-taking.

- Official downloads, sizes, checksums and license: https://www.openslr.org/12

## Suggested initial download: six complete AMI meetings

Durations checked against the [BUT UEM files](https://github.com/BUTSpeechFIT/AMI-diarization-setup/tree/main/uems), which cover whole recording lengths:

| Role | Meeting | Duration, rounded |
| --- | --- | --- |
| Development | ES2011a | 18:34 |
| Development | IS1008a | 15:44 |
| Development | TS3004a | 22:25 |
| Held-out evaluation | ES2004a | 17:29 |
| Held-out evaluation | IS1009a | 13:59 |
| Held-out evaluation | TS3003a | 25:06 |

Total unique meeting time is approximately 1 hour 53 minutes. Download the headset mix and one distant-microphone channel for each: 12 audio files, representing six conversations under two recording conditions. These are an initial diagnostic subset, not a full-corpus benchmark. They all use the `a` session; later expansion should include later meeting phases and longer recordings. Do not tune against the held-out three while still describing them as held out. No audio was downloaded during this metadata check.

## Measurement proposal

- Diarization error: missed speech, false speech, and speaker confusion reported separately, with collar and overlap policy stated.
- Recognition error: WER against the corpus reference, with normalization recorded.
- End-product attribution: speaker-attributed word errors and falsely introduced speaker changes inside reference single-speaker contributions. These must be scored from the saved result, not only the model timeline.
- Match arbitrary predicted speaker IDs to reference IDs once per recording; per-turn remapping can conceal identity errors.
- Use annotated corpus references, not another model's predictions, as ground truth. Missing or truncated references must stop scoring, not be replaced with placeholders.
- Keep configuration selection on development data separate from held-out reporting. Aggregate scores do not replace inspection of error intervals and the complete readable transcript.

These measurements are proposals, not implemented scoring tools or evidence that the current PR fixes acoustic attribution.

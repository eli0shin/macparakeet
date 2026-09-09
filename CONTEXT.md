# MacParakeet

MacParakeet provides local-first dictation, transcription, and meeting recording.

## Language

### Meeting transcripts

**Reading Turn**:
A speaker-labeled contribution in a readable meeting transcript. A Reading Turn is not necessarily the speaker's entire uninterrupted speech.

**Speech Block**:
A continuous contribution by one speaker, bounded by an audible pause or a paragraph boundary. A surrounding Speech Block can be split to insert a shorter contribution while keeping that inserted contribution whole.

**Contained overlap**:
An overlap in which one Speech Block starts and ends within another Speech Block.

**Crossing overlap**:
An overlap in which the later-starting Speech Block continues beyond the end of the earlier-starting Speech Block.

**Overlapping speech**:
Speech from two or more people who speak at the same time. Overlapping transcript timestamps alone do not establish overlapping speech.
_Avoid_: Simultaneous-speech grouping (the name of a removed presentation feature, not the speech itself)

**Final transcript**:
The transcript produced after a recording is processed, rather than the live preview shown during recording.

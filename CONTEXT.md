# MacParakeet

MacParakeet provides local-first dictation, transcription, and meeting recording.

## Language

### Meeting transcripts

**Reading Turn**:
A speaker-labeled contribution persisted in the final transcript. Consecutive words attributed to the same speaker form one Reading Turn; paragraph breaks remain inside that contribution.

**Speech Block**:
A continuous acoustic contribution by one speaker. The final transcript does not infer Speech Blocks from whole-recording speaker spans or recursively reorder them. Paragraph breaks alone do not establish speaker changes.

**Contained overlap**:
An overlap in which one Speech Block starts and ends within another Speech Block.

**Crossing overlap**:
An overlap in which the later-starting Speech Block continues beyond the end of the earlier-starting Speech Block.

**Overlapping speech**:
Speech from two or more people who speak at the same time. Overlapping transcript timestamps alone do not establish overlapping speech.
_Avoid_: Simultaneous-speech grouping (the name of a removed presentation feature, not the speech itself)

**Final transcript**:
The transcript produced after a recording is processed, rather than the live preview shown during recording.

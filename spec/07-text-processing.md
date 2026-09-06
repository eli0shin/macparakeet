# 07 - Text Processing

> Status: **ACTIVE** - Authoritative, current

Text processing transforms raw STT output into polished text. MacParakeet offers a deterministic pipeline for fast, predictable results.

---

## Deterministic Pipeline (v0.2)

A 5-step pipeline that runs in sub-millisecond time. Pure function: same input always produces the same output and optional post-paste action.

```
Raw STT Text → Filler Removal → Custom Words → Trailing Action Extraction → Snippet Expansion → Whitespace Cleanup → Clean Text
```

### Step 1: Filler Removal

Removes only always-safe hesitation sounds:

- "uh", "umm", "uhh"

Implementation uses `NSRegularExpression` with word boundaries (`\b`) to avoid partial matches. Portuguese and German `um`, words like "like", "so", "right", and phrases like "you know" are intentionally not stripped by default because they can carry meaning.

### Step 2: Custom Word Replacements

User-defined word corrections applied with case-insensitive matching and whole-word boundaries.

Two categories:

| Type | Purpose | Example |
|------|---------|---------|
| Vocabulary anchors | Enforce correct casing | "kubernetes" → "Kubernetes" |
| Corrections | Fix common STT errors | "aye pee eye" → "API" |

- Matching is **case-insensitive** with **whole-word boundaries**
- **Disabled** words are skipped (user can toggle without deleting)
- Applied in the order they appear in the database

**Meetings:** enabled custom words apply to the separate deterministic
`cleanTranscript` and its readable Reading Turn projection. They do not rewrite
`rawTranscript`, timed words, source attribution, or diarization evidence.
Meeting cleanup is always on, independent of the dictation Raw/Clean mode.
`MeetingTranscriptCleaner` also uses the shared conservative filler policy,
whitespace and punctuation normalization, and sentence capitalization. Snippet
expansion, trailing actions, paste actions, dictation insertion styling, and
LLM calls are not part of this path.

## Meeting Reading Turn presentation

Completed meetings have a separate pure presentation boundary. `MeetingTranscriptPresentationBuilder` reads the finalized transcript text, source-aware words, speaker roster, retained diarization regions, and optional custom vocabulary and returns ordered Reading Turns with stable evidence-derived identity, source, optional time range, paragraphs, and underlying word indexes. It forms utterances independently inside each capture source before it reconciles remote speakers. Microphone utterances remain **Me**. System utterances use aggregate overlap duration from refined-speaker diarization regions; legacy meetings without those regions use aggregate word-label duration. Equal evidence remains the generic system fallback instead of receiving an arbitrary speaker.

Sentence boundaries form mergeable utterances. A 2.5-second pause or a completed exchange with the other capture source forms a non-mergeable boundary. After attribution, adjacent same-speaker utterances merge across accepted short pauses. An isolated remote-speaker or generic-fallback run between the same stable speaker is absorbed when it has less than one second of reliable evidence. It remains a separate contribution when at least 200 ms of concurrent remote-speaker regions supports genuine overlap; the stable speaker's words on both sides remain one Reading Turn. A run at or above the one-second threshold remains a distinct exchange. Paragraphs split at a 2.5-second pause and pack complete sentences up to three sentences and 80 words. A single sentence can exceed 80 words when no safe sentence boundary exists. Paragraphs stay inside their Reading Turn and do not repeat its speaker header.

The builder marks microphone/system contributions as one overlap group when their Reading Turn ranges intersect for at least 200 ms. Two remote contributions receive the same treatment only when retained diarization regions for their resolved speakers also overlap for at least 200 ms. Weak fallback or unattributed fragments do not receive a refined identity to create an overlap group. The group's identity comes from the earliest contribution, and contributions remain ordered by start time and capture-source rank.

Normal readable mode removes only `uh`, `umm`, and `uhh`, applies custom vocabulary, normalizes whitespace and punctuation artifacts, and capitalizes paragraph starts. It is always selected for completed meetings, independent of the dictation Raw/Clean preference. Explicit evidence paths can select verbatim wording with the same turns, paragraph boundaries, speaker attribution, order, timing, and word references. Neither policy runs snippet expansion, trailing paste actions, or dictation insertion styling. Both retain references to every supplied word so canonical wording and timing remain recoverable. The builder also exposes content-free fixture metrics for turns per minute, blocks shorter than three words, isolated speaker flips, fallback-speaker transitions, and median words per turn. This derivation is deterministic, local, and read-only. It does not update raw words, source attribution, timestamps, or diarization regions. Meetings without word timings receive one unlabelled, untimed text fallback. Legacy rows with no persisted clean transcript use this fallback without a database write.

### Step 3: Trailing Action Extraction

If the user's text ends with an enabled action-snippet trigger, the trigger is stripped and the action is returned through `TextProcessingResult.postPasteAction`. This is how Voice Return-style behavior can simulate Return after paste without leaving a configured trigger phrase such as "press return" or "zatwierdź" in the transcript.

- Action snippets are matched longest-first, case-insensitive, and punctuation-tolerant at the end of the text.
- Voice Return can inject multiple configured trigger phrases for the same Return action.
- Extraction happens before normal snippet expansion so a plain snippet cannot consume or rewrite the action trigger.
- Raw mode skips the full clean pipeline, but still performs this terminal action extraction so Voice Return works in both Raw and Clean.

### Step 4: Snippet Expansion

Trigger phrases are replaced with their full expansion text.

- **Triggers are natural language phrases**, not abbreviations — because Parakeet STT outputs natural speech, users will say "my signature" not "sig". Triggers must match what the STT actually produces.
- Snippets are **sorted by trigger length descending** (longest first) to prevent partial matches when one trigger is a prefix of another
- Matching is **case-insensitive** with **whole-phrase boundaries**
- Expanded snippet IDs are tracked so use counts can be updated after processing
- Example: `"my signature"` → `"Best regards, David"`

### Step 5: Whitespace Cleanup + Insertion Style

Final normalization pass:

1. **Collapse multiple spaces** — `"hello   world"` → `"hello world"`
2. **Remove space before punctuation** — `"hello ."` → `"hello."`
3. **Trim** — strip leading/trailing whitespace
4. **Apply insertion style**:
   - **Sentence** (default): capitalize the first letter and keep final sentence punctuation.
   - **Inline**: remove terminal sentence punctuation (`.`, `!`, `?`) and lowercase ordinary sentence-initial capitalization so the result can replace selected text, fill fields, or append to typed text. Acronyms, camelCase, custom vocabulary, and expanded snippet casing are preserved.

---

## Processing Modes

| Mode | Processing | Engine | Latency |
|------|-----------|--------|---------|
| Raw | None | N/A | 0ms |
| Clean | Deterministic pipeline | TextProcessingPipeline | <1ms |

### Mode Details

**Raw**: No processing. The exact text output from Parakeet is used as-is. Useful for debugging or when the user wants full control.

**Clean** (default): The deterministic 5-step pipeline runs. Fast and predictable. Good for most dictation use cases.

Clean dictation also has an insertion-style preference. Sentence style keeps
the historical sentence-shaped output. Inline style keeps the same deterministic
pipeline but shapes the final output for selected-text replacement, search
fields, forms, terminal commands, and hybrid typing.

---

## Database Tables

### custom_words

Stores user-defined vocabulary anchors and corrections.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| word | TEXT | The word/phrase to match (case-insensitive) |
| replacement | TEXT | The corrected word/phrase (nullable = vocabulary anchor) |
| source | TEXT | `.manual` (user-created) or `.learned` (auto-detected, future) |
| isEnabled | BOOLEAN | Whether this word is active |
| createdAt | DATETIME | When created |
| updatedAt | DATETIME | When last modified |

### text_snippets

Stores trigger-to-expansion mappings.

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| trigger | TEXT | Natural language trigger phrase (e.g., "my address") |
| expansion | TEXT | The full expansion text |
| action | TEXT | Optional post-paste action; non-null rows are action snippets, not text-expansion snippets |
| useCount | INTEGER | Number of times expanded |
| isEnabled | BOOLEAN | Whether this snippet is active |
| createdAt | DATETIME | When created |
| updatedAt | DATETIME | When last modified |

---

## CLI Commands

### Text Processing

```bash
# Run clean processing on text
macparakeet-cli vocab process "uh hello kubernetes is great"
# → "Hello Kubernetes is great."

# Process and copy to clipboard
macparakeet-cli vocab process "text here" --copy

# Transcribe with processing
macparakeet-cli transcribe recording.wav --mode clean
macparakeet-cli transcribe recording.wav --mode raw
```

### Custom Words

```bash
# List all custom words
macparakeet-cli vocab words list

# Add a vocabulary anchor
macparakeet-cli vocab words add "kubernetes" "Kubernetes"

# Add a correction
macparakeet-cli vocab words add "aye pee eye" "API"

# Delete a custom word
macparakeet-cli vocab words delete <id>
```

### Text Snippets

```bash
# List all snippets
macparakeet-cli vocab snippets list

# Add a snippet (trigger is a natural phrase, not an abbreviation)
macparakeet-cli vocab snippets add "my signature" "Best regards, David"

# Edit a snippet
macparakeet-cli vocab snippets edit <id> --trigger "my signature" --expansion "Best regards, Daniel"

# Delete a snippet
macparakeet-cli vocab snippets delete <id>
```

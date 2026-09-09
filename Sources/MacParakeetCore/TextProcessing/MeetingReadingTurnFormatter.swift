import Foundation

/// An AI text override for one stable Reading Turn. The deterministic source
/// text is retained so stale formatting cannot attach to rebuilt evidence.
public struct MeetingReadingTurnFormatting: Codable, Sendable, Equatable {
    public let turnID: ReadingTurnIdentity
    public let deterministicText: String
    public let formattedText: String

    public init(
        turnID: ReadingTurnIdentity,
        deterministicText: String,
        formattedText: String
    ) {
        self.turnID = turnID
        self.deterministicText = deterministicText
        self.formattedText = formattedText
    }
}

public struct MeetingReadingTurnFormattingProgress: Sendable, Equatable {
    public let completedRequests: Int
    public let totalRequests: Int

    public init(completedRequests: Int, totalRequests: Int) {
        self.completedRequests = completedRequests
        self.totalRequests = totalRequests
    }
}

public struct MeetingReadingTurnFormattingResult: Sendable, Equatable {
    public let formatting: [MeetingReadingTurnFormatting]
    public let progress: MeetingReadingTurnFormattingProgress
    public let wasCancelled: Bool

    public init(
        formatting: [MeetingReadingTurnFormatting],
        progress: MeetingReadingTurnFormattingProgress,
        wasCancelled: Bool
    ) {
        self.formatting = formatting
        self.progress = progress
        self.wasCancelled = wasCancelled
    }
}

/// One independently cleaned entry in a meeting batch. IDs are transport-only;
/// speaker identity, timing, and Reading Turn identity never enter the prompt.
public struct MeetingReadingTurnBatchEntry: Codable, Sendable, Equatable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

public struct MeetingReadingTurnFormattingBatch: Sendable, Equatable {
    public let entries: [MeetingReadingTurnBatchEntry]

    public var transcriptCharacterCount: Int {
        entries.reduce(0) { $0 + $1.text.count }
    }

    public func encodedJSON() throws -> String {
        let data = try JSONEncoder().encode(BatchRequest(entries: entries))
        return String(decoding: data, as: UTF8.self)
    }
}

/// Formats meeting paragraphs through bounded, serial batches. Batches can
/// cross Reading Turn and speaker boundaries. Each failed batch is retried
/// twice, then its source text is used without deterministic cleanup.
public struct MeetingReadingTurnFormatter {
    public typealias FormatRequest = (MeetingReadingTurnFormattingBatch) async throws -> String
    public typealias ProgressHandler = @Sendable (MeetingReadingTurnFormattingProgress) -> Void

    public let maximumRequestCharacters: Int
    public let maximumAttempts: Int

    public init(
        maximumRequestCharacters: Int = AIFormatter.maxTranscriptionInputChars,
        maximumAttempts: Int = 3
    ) {
        precondition(maximumRequestCharacters > 0)
        precondition(maximumAttempts > 0)
        self.maximumRequestCharacters = maximumRequestCharacters
        self.maximumAttempts = maximumAttempts
    }

    public func format(
        _ document: MeetingTranscriptPresentationDocument,
        sourceDocument: MeetingTranscriptPresentationDocument? = nil,
        isolation: isolated (any Actor)? = #isolation,
        using formatRequest: FormatRequest,
        onProgress: ProgressHandler? = nil
    ) async -> MeetingReadingTurnFormattingResult {
        let parts = makeParts(for: document, sourceDocument: sourceDocument ?? document)
        let batches = makeBatches(parts)
        var completedBatches = 0
        var outputsByPartID: [String: String] = [:]
        onProgress?(.init(completedRequests: 0, totalRequests: batches.count))

        for batch in batches {
            if Task.isCancelled {
                return makeResult(
                    document: document,
                    parts: parts,
                    outputsByPartID: outputsByPartID,
                    completedRequests: completedBatches,
                    totalRequests: batches.count,
                    wasCancelled: true
                )
            }

            var mappedOutput: [String: String]?
            for _ in 0..<maximumAttempts {
                if Task.isCancelled { break }
                do {
                    let response = try await formatRequest(batch.request)
                    if Task.isCancelled { break }
                    mappedOutput = try Self.parse(response, expectedIDs: batch.parts.map(\.id))
                    break
                } catch is CancellationError {
                    return makeResult(
                        document: document,
                        parts: parts,
                        outputsByPartID: outputsByPartID,
                        completedRequests: completedBatches,
                        totalRequests: batches.count,
                        wasCancelled: true
                    )
                } catch {
                    continue
                }
            }

            if Task.isCancelled {
                return makeResult(
                    document: document,
                    parts: parts,
                    outputsByPartID: outputsByPartID,
                    completedRequests: completedBatches,
                    totalRequests: batches.count,
                    wasCancelled: true
                )
            }

            for part in batch.parts {
                outputsByPartID[part.id] = mappedOutput?[part.id] ?? part.text
            }
            completedBatches += 1
            onProgress?(.init(completedRequests: completedBatches, totalRequests: batches.count))
        }

        return makeResult(
            document: document,
            parts: parts,
            outputsByPartID: outputsByPartID,
            completedRequests: completedBatches,
            totalRequests: batches.count,
            wasCancelled: false
        )
    }

    private func makeParts(
        for document: MeetingTranscriptPresentationDocument,
        sourceDocument: MeetingTranscriptPresentationDocument
    ) -> [Part] {
        let sourceTurns = Dictionary(uniqueKeysWithValues: sourceDocument.turns.map { ($0.id, $0) })
        var parts: [Part] = []

        for (turnIndex, turn) in document.turns.enumerated() {
            let sourceTurn = sourceTurns[turn.id] ?? turn
            for (paragraphIndex, paragraph) in sourceTurn.paragraphs.enumerated() where !paragraph.text.isEmpty {
                let chunks = splitOversizedParagraph(paragraph.text)
                for (partIndex, chunk) in chunks.enumerated() {
                    parts.append(
                        Part(
                            id: "entry-\(turnIndex)-\(paragraphIndex)-\(partIndex)",
                            turnIndex: turnIndex,
                            paragraphIndex: paragraphIndex,
                            partIndex: partIndex,
                            text: chunk
                        ))
                }
            }
        }
        return parts
    }

    private func makeBatches(_ parts: [Part]) -> [Batch] {
        var batches: [Batch] = []
        var current: [Part] = []
        var currentCharacters = 0

        for part in parts {
            if !current.isEmpty, currentCharacters + part.text.count > maximumRequestCharacters {
                batches.append(Batch(parts: current))
                current = []
                currentCharacters = 0
            }
            current.append(part)
            currentCharacters += part.text.count
        }
        if !current.isEmpty { batches.append(Batch(parts: current)) }
        return batches
    }

    private func splitOversizedParagraph(_ paragraph: String) -> [String] {
        guard paragraph.count > maximumRequestCharacters else { return [paragraph] }
        let characters = Array(paragraph)
        var chunks: [String] = []
        var start = 0
        while characters.count - start > maximumRequestCharacters {
            let upperBound = start + maximumRequestCharacters
            var split = upperBound
            if upperBound > start {
                for candidate in stride(from: upperBound, through: start + 1, by: -1) {
                    if isSentenceBoundary(in: characters, at: candidate, after: start) {
                        split = candidate
                        break
                    }
                }
            }
            chunks.append(String(characters[start..<split]))
            start = split
        }
        if start < characters.count { chunks.append(String(characters[start...])) }
        return chunks
    }

    private func isSentenceBoundary(
        in characters: [Character],
        at candidate: Int,
        after start: Int
    ) -> Bool {
        let closingCharacters: Set<Character> = ["\"", "'", "”", "’", ")", "]", "}", "】", "」", "』"]
        var endingIndex = candidate
        while endingIndex > start, closingCharacters.contains(characters[endingIndex - 1]) {
            endingIndex -= 1
        }
        guard endingIndex > start else { return false }

        let ending = characters[endingIndex - 1]
        if ["。", "？", "！"].contains(ending) { return true }
        guard [".", "?", "!"].contains(ending) else { return false }
        return candidate == characters.count || characters[candidate].isWhitespace
    }

    private func makeResult(
        document: MeetingTranscriptPresentationDocument,
        parts: [Part],
        outputsByPartID: [String: String],
        completedRequests: Int,
        totalRequests: Int,
        wasCancelled: Bool
    ) -> MeetingReadingTurnFormattingResult {
        let partsByTurn = Dictionary(grouping: parts, by: \.turnIndex)
        let formatting = document.turns.enumerated().compactMap { turnIndex, turn -> MeetingReadingTurnFormatting? in
            guard let turnParts = partsByTurn[turnIndex],
                turnParts.allSatisfy({ outputsByPartID[$0.id] != nil })
            else { return nil }

            let paragraphs = Dictionary(grouping: turnParts, by: \.paragraphIndex)
                .sorted { $0.key < $1.key }
                .map { _, paragraphParts in
                    paragraphParts.sorted { $0.partIndex < $1.partIndex }
                        .compactMap { outputsByPartID[$0.id] }
                        .joined()
                }
            return MeetingReadingTurnFormatting(
                turnID: turn.id,
                deterministicText: turn.deterministicText,
                formattedText: paragraphs.joined(separator: "\n\n")
            )
        }
        return MeetingReadingTurnFormattingResult(
            formatting: formatting,
            progress: .init(completedRequests: completedRequests, totalRequests: totalRequests),
            wasCancelled: wasCancelled
        )
    }

    private static func parse(_ output: String, expectedIDs: [String]) throws -> [String: String] {
        var candidate = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("```"), let firstNewline = candidate.firstIndex(of: "\n") {
            candidate = String(candidate[candidate.index(after: firstNewline)...])
            if let fence = candidate.range(of: "```", options: .backwards) {
                candidate = String(candidate[..<fence.lowerBound])
            }
        }
        let response = try JSONDecoder().decode(BatchResponse.self, from: Data(candidate.utf8))
        guard response.entries.count == expectedIDs.count else { throw BatchResponseError.invalidIDs }
        var mapped: [String: String] = [:]
        for entry in response.entries {
            guard expectedIDs.contains(entry.id), mapped.updateValue(entry.text, forKey: entry.id) == nil else {
                throw BatchResponseError.invalidIDs
            }
        }
        guard Set(mapped.keys) == Set(expectedIDs) else { throw BatchResponseError.invalidIDs }
        return mapped
    }
}

private struct Part {
    let id: String
    let turnIndex: Int
    let paragraphIndex: Int
    let partIndex: Int
    let text: String
}

private struct Batch {
    let parts: [Part]

    var request: MeetingReadingTurnFormattingBatch {
        MeetingReadingTurnFormattingBatch(
            entries: parts.map { MeetingReadingTurnBatchEntry(id: $0.id, text: $0.text) }
        )
    }
}

private struct BatchRequest: Codable {
    let entries: [MeetingReadingTurnBatchEntry]
}

private struct BatchResponse: Decodable {
    let entries: [MeetingReadingTurnBatchEntry]
}

private enum BatchResponseError: Error {
    case invalidIDs
}

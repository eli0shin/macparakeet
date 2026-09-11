import Foundation

/// A validated AI text override for one stable Reading Turn. The deterministic
/// source text is retained so stale formatting cannot attach to rebuilt evidence.
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

/// One Reading Turn in a provider-independent cleanup request or response.
public struct MeetingReadingTurnBatchEntry: Codable, Sendable, Equatable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// A serial cleanup request. `diagnosticID` links the raw provider response to
/// this batch but is not encoded into the model input.
public struct MeetingReadingTurnFormattingBatch: Sendable, Equatable {
    public let entries: [MeetingReadingTurnBatchEntry]
    public let diagnosticID: UUID

    public var transcriptCharacterCount: Int {
        entries.reduce(0) { $0 + $1.text.count }
    }

    public func encodedJSON() throws -> String {
        let data = try JSONEncoder().encode(BatchPayload(entries: entries))
        return String(decoding: data, as: UTF8.self)
    }
}

/// Formats finalized Reading Turns through small, serial requests. Complete
/// turns of 500 or more characters are always sent alone without a size cap.
/// Consecutive shorter turns are packed without exceeding 500 characters or
/// 10 turns. Optional boundary repair carries the final complete returned turn
/// into the next planned request. Failed batches fall back independently and do
/// not block later batches.
public struct MeetingReadingTurnFormatter {
    public typealias FormatRequest = (MeetingReadingTurnFormattingBatch) async throws -> String
    public typealias ProgressHandler = @Sendable (MeetingReadingTurnFormattingProgress) -> Void
    public typealias DiagnosticSink = @Sendable (MeetingFormattingDiagnostic) async -> Void

    public static let shortTurnBatchCharacterLimit = 500
    public static let maximumTurnsPerBatch = 10

    private let diagnosticSink: DiagnosticSink

    public init() {
        diagnosticSink = { await MeetingFormattingDiagnosticLog.shared.append($0) }
    }

    public init(diagnosticSink: @escaping DiagnosticSink) {
        self.diagnosticSink = diagnosticSink
    }

    public static func promptTemplate(
        _ template: String,
        repairSpeakerTurnBoundaries: Bool = false
    ) -> String {
        let normalized = AIFormatter.normalizedPromptTemplate(template)
        let contract =
            if repairSpeakerTurnBoundaries {
                """
                Reading Turn batch requirements (these take priority over other output instructions):
                Clean the entries in order and preserve every entry ID exactly.
                Text at a boundary may belong to the immediately preceding or following entry. Move only clearly misplaced hanging words between those adjacent entries. If the correct boundary is unclear, preserve it.
                Return the complete cleaned text for every entry, including any entry whose complete replacement is empty. Do not return diffs, patches, word IDs, split positions, or edit operations.
                Return only JSON in this form: {"entries":[{"id":"turn ID","text":"complete cleaned text"}]}.
                Include every input ID exactly once. Do not add commentary.
                """
            } else {
                """
            Reading Turn batch requirements (these take priority over other output instructions):
            Clean each entry independently. Preserve every entry ID exactly.
            Do not combine entries or move text between entries.
            Return only JSON in this form: {"entries":[{"id":"turn ID","text":"cleaned text"}]}.
            Include every input ID exactly once. Do not add commentary.
            """
            }

        guard normalized.contains(AIFormatter.transcriptPlaceholder) else {
            return normalized + "\n\n" + contract + "\n\nReading Turn batch:\n" + AIFormatter.transcriptPlaceholder
        }
        return normalized.replacingOccurrences(
            of: AIFormatter.transcriptPlaceholder,
            with: contract + "\n\nReading Turn batch:\n" + AIFormatter.transcriptPlaceholder
        )
    }

    public func format(
        _ document: MeetingTranscriptPresentationDocument,
        repairSpeakerTurnBoundaries: Bool = false,
        using formatRequest: FormatRequest,
        onProgress: ProgressHandler? = nil
    ) async -> MeetingReadingTurnFormattingResult {
        let parts = document.turns.enumerated().compactMap { index, turn -> Part? in
            guard turn.deterministicText.contains(where: { !$0.isWhitespace }) else { return nil }
            return Part(id: "turn-\(index)", turn: turn)
        }
        let batches = makeBatches(parts)
        var formattingByID: [String: MeetingReadingTurnFormatting] = [:]
        var carry: RollingCarry?
        var completedRequests = 0
        onProgress?(.init(completedRequests: 0, totalRequests: batches.count))

        for (batchIndex, batch) in batches.enumerated() {
            guard !Task.isCancelled else {
                commit(carry, to: &formattingByID)
                return result(
                    formatting: orderedFormatting(parts, from: formattingByID),
                    completedRequests: completedRequests,
                    totalRequests: batches.count,
                    wasCancelled: true
                )
            }

            let isLastBatch = batchIndex == batches.index(before: batches.endIndex)
            var requestParts = batch.parts
            if repairSpeakerTurnBoundaries, let carry {
                requestParts.insert(carry.part, at: 0)
            }
            let requestEntries = requestParts.map { part in
                MeetingReadingTurnBatchEntry(
                    id: part.id,
                    text: carry?.part.id == part.id
                        ? carry?.text ?? part.turn.deterministicText : part.turn.deterministicText
                )
            }
            let request = MeetingReadingTurnFormattingBatch(entries: requestEntries, diagnosticID: UUID())
            let input = (try? request.encodedJSON()) ?? ""

            do {
                let rawOutput = try await formatRequest(request)
                guard !Task.isCancelled else {
                    await record(
                        id: request.diagnosticID,
                        outcome: "cancelled",
                        reason: "cancelled_after_response",
                        input: input,
                        output: rawOutput,
                        expectedTurns: requestParts.count,
                        actualTurns: nil
                    )
                    commit(carry, to: &formattingByID)
                    return result(
                        formatting: orderedFormatting(parts, from: formattingByID),
                        completedRequests: completedRequests,
                        totalRequests: batches.count,
                        wasCancelled: true
                    )
                }

                do {
                    let parsed = try Self.parse(rawOutput, expectedIDs: requestParts.map(\.id))
                    if repairSpeakerTurnBoundaries {
                        carry = settleRollingBatch(
                            previousCarry: carry,
                            newParts: batch.parts,
                            outputs: parsed.outputs,
                            isLastBatch: isLastBatch,
                            formattingByID: &formattingByID
                        )
                    } else {
                        for part in batch.parts {
                            guard let output = parsed.outputs[part.id] else { continue }
                            formattingByID[part.id] = formatting(for: part, output: output)
                        }
                    }
                    let accepted = parsed.outputs.count
                    let outcome =
                        parsed.reasons.isEmpty
                        ? "accepted"
                        : (accepted == 0 ? "rejected" : "partially_accepted")
                    await record(
                        id: request.diagnosticID,
                        outcome: outcome,
                        reason: parsed.reasons.isEmpty ? nil : parsed.reasons.joined(separator: "; "),
                        input: input,
                        output: rawOutput,
                        expectedTurns: requestParts.count,
                        actualTurns: parsed.actualEntryCount
                    )
                } catch {
                    if repairSpeakerTurnBoundaries {
                        carry = settleRollingBatch(
                            previousCarry: carry,
                            newParts: batch.parts,
                            outputs: [:],
                            isLastBatch: isLastBatch,
                            formattingByID: &formattingByID
                        )
                    }
                    await record(
                        id: request.diagnosticID,
                        outcome: "rejected",
                        reason: "invalid_batch_response error=\(String(reflecting: error))",
                        input: input,
                        output: rawOutput,
                        expectedTurns: requestParts.count,
                        actualTurns: nil
                    )
                }
            } catch is CancellationError {
                await record(
                    id: request.diagnosticID,
                    outcome: "cancelled",
                    reason: "request_cancelled",
                    input: input,
                    output: nil,
                    expectedTurns: requestParts.count,
                    actualTurns: nil
                )
                commit(carry, to: &formattingByID)
                return result(
                    formatting: orderedFormatting(parts, from: formattingByID),
                    completedRequests: completedRequests,
                    totalRequests: batches.count,
                    wasCancelled: true
                )
            } catch {
                if repairSpeakerTurnBoundaries {
                    carry = settleRollingBatch(
                        previousCarry: carry,
                        newParts: batch.parts,
                        outputs: [:],
                        isLastBatch: isLastBatch,
                        formattingByID: &formattingByID
                    )
                }
                await record(
                    id: request.diagnosticID,
                    outcome: "rejected",
                    reason: "request_failed error=\(String(reflecting: error))",
                    input: input,
                    output: nil,
                    expectedTurns: requestParts.count,
                    actualTurns: nil
                )
            }

            completedRequests += 1
            onProgress?(.init(completedRequests: completedRequests, totalRequests: batches.count))
        }

        commit(carry, to: &formattingByID)
        return result(
            formatting: orderedFormatting(parts, from: formattingByID),
            completedRequests: completedRequests,
            totalRequests: batches.count,
            wasCancelled: false
        )
    }

    private func settleRollingBatch(
        previousCarry: RollingCarry?,
        newParts: [Part],
        outputs: [String: String],
        isLastBatch: Bool,
        formattingByID: inout [String: MeetingReadingTurnFormatting]
    ) -> RollingCarry? {
        var resolved: [RollingCarry] = []
        if let previousCarry {
            resolved.append(
                outputs[previousCarry.part.id].map {
                    RollingCarry(
                        part: previousCarry.part,
                        text: $0,
                        formatting: formatting(for: previousCarry.part, output: $0)
                    )
                } ?? previousCarry
            )
        }
        resolved.append(
            contentsOf: newParts.map { part in
                guard let output = outputs[part.id] else {
                    return RollingCarry(part: part, text: part.turn.deterministicText, formatting: nil)
                }
                return RollingCarry(part: part, text: output, formatting: formatting(for: part, output: output))
            })

        if isLastBatch {
            for value in resolved { commit(value, to: &formattingByID) }
            return nil
        }
        for value in resolved.dropLast() { commit(value, to: &formattingByID) }
        return resolved.last
    }

    private func formatting(for part: Part, output: String) -> MeetingReadingTurnFormatting {
        MeetingReadingTurnFormatting(
            turnID: part.turn.id,
            deterministicText: part.turn.deterministicText,
            formattedText: output
        )
    }

    private func commit(
        _ carry: RollingCarry?,
        to formattingByID: inout [String: MeetingReadingTurnFormatting]
    ) {
        guard let carry, let formatting = carry.formatting else { return }
        formattingByID[carry.part.id] = formatting
    }

    private func orderedFormatting(
        _ parts: [Part],
        from formattingByID: [String: MeetingReadingTurnFormatting]
    ) -> [MeetingReadingTurnFormatting] {
        parts.compactMap { formattingByID[$0.id] }
    }

    private func makeBatches(_ parts: [Part]) -> [Batch] {
        var batches: [Batch] = []
        var shortParts: [Part] = []
        var shortCharacterCount = 0

        func flushShortParts() {
            guard !shortParts.isEmpty else { return }
            batches.append(Batch(parts: shortParts))
            shortParts = []
            shortCharacterCount = 0
        }

        for part in parts {
            let count = part.turn.deterministicText.count
            if count >= Self.shortTurnBatchCharacterLimit {
                flushShortParts()
                batches.append(Batch(parts: [part]))
            } else if !shortParts.isEmpty,
                shortParts.count >= Self.maximumTurnsPerBatch
                    || shortCharacterCount + count > Self.shortTurnBatchCharacterLimit
            {
                flushShortParts()
                shortParts = [part]
                shortCharacterCount = count
            } else {
                shortParts.append(part)
                shortCharacterCount += count
            }
        }
        flushShortParts()
        return batches
    }

    private func record(
        id: UUID,
        outcome: String,
        reason: String?,
        input: String,
        output: String?,
        expectedTurns: Int,
        actualTurns: Int?
    ) async {
        await diagnosticSink(
            MeetingFormattingDiagnostic(
                id: id, createdAt: Date(), outcome: outcome, reason: reason,
                input: input, output: output,
                expectedTurns: expectedTurns, actualTurns: actualTurns
            ))
    }

    private func result(
        formatting: [MeetingReadingTurnFormatting],
        completedRequests: Int,
        totalRequests: Int,
        wasCancelled: Bool
    ) -> MeetingReadingTurnFormattingResult {
        MeetingReadingTurnFormattingResult(
            formatting: formatting,
            progress: .init(completedRequests: completedRequests, totalRequests: totalRequests),
            wasCancelled: wasCancelled
        )
    }

    private static func parse(_ output: String, expectedIDs: [String]) throws -> ParsedBatchResponse {
        var candidate = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("```"), let firstNewline = candidate.firstIndex(of: "\n") {
            candidate = String(candidate[candidate.index(after: firstNewline)...])
            if let closingFence = candidate.range(of: "```", options: .backwards) {
                candidate = String(candidate[..<closingFence.lowerBound])
            }
        }
        let payload = try JSONDecoder().decode(BatchPayload.self, from: Data(candidate.utf8))
        let expected = Set(expectedIDs)
        var mapped: [String: String] = [:]
        var duplicated: Set<String> = []
        var reasons: [String] = []

        for entry in payload.entries {
            guard expected.contains(entry.id) else {
                reasons.append("unknown_id id=\(entry.id)")
                continue
            }
            guard !duplicated.contains(entry.id) else { continue }
            if mapped[entry.id] != nil {
                mapped.removeValue(forKey: entry.id)
                duplicated.insert(entry.id)
                reasons.append("duplicate_id id=\(entry.id)")
                continue
            }
            mapped[entry.id] = AIFormatter.normalizedFormattedOutput(entry.text)
        }
        for id in expectedIDs where mapped[id] == nil && !duplicated.contains(id) {
            reasons.append("missing_id id=\(id)")
        }
        return ParsedBatchResponse(
            outputs: mapped,
            reasons: reasons,
            actualEntryCount: payload.entries.count
        )
    }

}

private struct Part {
    let id: String
    let turn: ReadingTurn
}

private struct RollingCarry {
    let part: Part
    let text: String
    let formatting: MeetingReadingTurnFormatting?
}

private struct Batch {
    let parts: [Part]

    var request: MeetingReadingTurnFormattingBatch {
        MeetingReadingTurnFormattingBatch(
            entries: parts.map { MeetingReadingTurnBatchEntry(id: $0.id, text: $0.turn.deterministicText) },
            diagnosticID: UUID()
        )
    }
}

private struct BatchPayload: Codable {
    let entries: [MeetingReadingTurnBatchEntry]
}

private struct ParsedBatchResponse {
    let outputs: [String: String]
    let reasons: [String]
    let actualEntryCount: Int
}

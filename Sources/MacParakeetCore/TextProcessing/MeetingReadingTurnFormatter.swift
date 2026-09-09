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

/// Formats all complete Reading Turns in one request. The boundary marker lets
/// the response map back to stable turns without dropping transcript text.
/// A malformed or content-changing response leaves every turn deterministic.
public struct MeetingReadingTurnFormatter {
    public typealias FormatRequest = (String) async throws -> String
    public typealias ProgressHandler = @Sendable (MeetingReadingTurnFormattingProgress) -> Void

    private static let turnBoundary = "<<<MACPARAKEET_READING_TURN_BOUNDARY>>>"

    public typealias DiagnosticSink = @Sendable (MeetingFormattingDiagnostic) async -> Void
    private let diagnosticSink: DiagnosticSink

    public init() {
        diagnosticSink = { await MeetingFormattingDiagnosticLog.shared.append($0) }
    }

    public init(diagnosticSink: @escaping DiagnosticSink) {
        self.diagnosticSink = diagnosticSink
    }

    public static func promptTemplate(_ template: String) -> String {
        AIFormatter.normalizedPromptTemplate(template) + """


            Meeting transcript structure requirements (these take priority over paragraph styling):
            Preserve every <<<MACPARAKEET_READING_TURN_BOUNDARY>>> marker exactly and in order.
            Each marker separates speakers' contributions. Clean each contribution independently.
            Never merge, split, remove, or move contributions across these markers.
            Keep short contributions such as Yes or Okay, even when they are only one word.
            Return the cleaned text with all markers intact. Do not add commentary.
            """
    }

    public func format(
        _ document: MeetingTranscriptPresentationDocument,
        using formatRequest: FormatRequest,
        onProgress: ProgressHandler? = nil,
        diagnosticID: UUID = UUID()
    ) async -> MeetingReadingTurnFormattingResult {
        let turns = document.turns.filter {
            $0.deterministicText.contains(where: { !$0.isWhitespace })
        }
        let totalRequests = turns.isEmpty ? 0 : 1
        let request = turns.map(\.deterministicText).joined(
            separator: "\n\n\(Self.turnBoundary)\n\n"
        )
        func record(_ outcome: String, reason: String? = nil, output: String? = nil, actualTurns: Int? = nil) async {
            await diagnosticSink(
                MeetingFormattingDiagnostic(
                    id: diagnosticID, createdAt: Date(), outcome: outcome, reason: reason,
                    input: request, output: output, expectedTurns: turns.count, actualTurns: actualTurns
                ))
        }
        onProgress?(.init(completedRequests: 0, totalRequests: totalRequests))
        guard !turns.isEmpty else {
            await record("skipped", reason: "no_nonempty_turns")
            return result(formatting: [], completedRequests: 0, totalRequests: 0, wasCancelled: false)
        }
        guard !Task.isCancelled else {
            await record("cancelled", reason: "cancelled_before_request")
            return result(formatting: [], completedRequests: 0, totalRequests: 1, wasCancelled: true)
        }
        do {
            let rawOutput = try await formatRequest(request)
            guard !Task.isCancelled else {
                await record("cancelled", reason: "cancelled_after_response", output: rawOutput)
                return result(formatting: [], completedRequests: 0, totalRequests: 1, wasCancelled: true)
            }
            let outputs = rawOutput.components(separatedBy: Self.turnBoundary).map {
                AIFormatter.normalizedFormattedOutput($0)
            }
            var reasons: [String] = []
            if outputs.count != turns.count {
                reasons.append(
                    "turn_count_mismatch expected=\(turns.count) actual=\(outputs.count) expected_boundaries=\(turns.count - 1) actual_boundaries=\(outputs.count - 1)"
                )
            } else {
                for (index, pair) in zip(turns, outputs).enumerated() {
                    if let reason = Self.rejectionReason(
                        input: pair.0.deterministicText, output: pair.1, turn: index + 1)
                    {
                        reasons.append(reason)
                    }
                }
            }
            let formatting =
                reasons.isEmpty
                ? zip(turns, outputs).map {
                    MeetingReadingTurnFormatting(
                        turnID: $0.id, deterministicText: $0.deterministicText, formattedText: $1)
                } : []
            await record(
                reasons.isEmpty ? "accepted" : "rejected",
                reason: reasons.isEmpty ? nil : reasons.joined(separator: "; "),
                output: rawOutput, actualTurns: outputs.count)
            onProgress?(.init(completedRequests: 1, totalRequests: 1))
            return result(formatting: formatting, completedRequests: 1, totalRequests: 1, wasCancelled: false)
        } catch is CancellationError {
            await record("cancelled", reason: "request_cancelled")
            return result(formatting: [], completedRequests: 0, totalRequests: 1, wasCancelled: true)
        } catch {
            await record("rejected", reason: "request_failed error=\(String(reflecting: error))")
            onProgress?(.init(completedRequests: 1, totalRequests: 1))
            return result(formatting: [], completedRequests: 1, totalRequests: 1, wasCancelled: false)
        }
    }

    private func result(
        formatting: [MeetingReadingTurnFormatting],
        completedRequests: Int,
        totalRequests: Int,
        wasCancelled: Bool
    ) -> MeetingReadingTurnFormattingResult {
        MeetingReadingTurnFormattingResult(
            formatting: formatting,
            progress: .init(
                completedRequests: completedRequests,
                totalRequests: totalRequests
            ),
            wasCancelled: wasCancelled
        )
    }

    /// AI may change punctuation, casing, and a bounded amount of wording. It
    /// may not drop protected values or replace a large share of lexical content.
    private static func rejectionReason(input: String, output: String, turn: Int) -> String? {
        guard output.contains(where: { !$0.isWhitespace }) else { return "empty_output turn=\(turn)" }
        let inputTokens = lexicalTokens(in: input)
        let outputTokens = lexicalTokens(in: output)
        guard !inputTokens.isEmpty, !outputTokens.isEmpty else {
            return
                "no_lexical_tokens turn=\(turn) input_tokens=\(inputTokens.count) output_tokens=\(outputTokens.count)"
        }
        let inputProtected = protectedTokens(in: input)
        let outputProtected = protectedTokens(in: output)
        guard inputProtected == outputProtected else {
            return "protected_values_changed turn=\(turn) expected=\(inputProtected) actual=\(outputProtected)"
        }
        let changedTokenCount = outputTokens.difference(from: inputTokens).count
        let baseline = max(inputTokens.count, outputTokens.count)
        let ratio = Double(changedTokenCount) / Double(baseline)
        guard ratio <= 0.35 else {
            return
                "lexical_change_exceeded turn=\(turn) changed_tokens=\(changedTokenCount) baseline_tokens=\(baseline) ratio=\(ratio) limit=0.35"
        }
        let maxLength = max(input.count * 3 / 2, input.count + 200)
        guard output.count <= maxLength else {
            return
                "output_length_exceeded turn=\(turn) input_chars=\(input.count) output_chars=\(output.count) limit=\(maxLength)"
        }
        return nil
    }

    private static func lexicalTokens(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func tokenCounts(_ tokens: [String]) -> [String: Int] {
        tokens.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private static func protectedTokens(in text: String) -> [String: Int] {
        let tokens = text.split(whereSeparator: \.isWhitespace).compactMap { raw -> String? in
            let token = raw.trimmingCharacters(in: .punctuationCharacters)
            guard
                token.contains(where: \.isNumber)
                    || token.contains("@")
                    || token.contains("://")
            else { return nil }
            return token.lowercased()
        }
        return tokenCounts(tokens)
    }
}

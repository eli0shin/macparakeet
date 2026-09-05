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

/// Formats complete Reading Turns through bounded, serial requests. A turn is
/// committed only after all of its requests pass preservation validation.
/// Failed or cancelled work leaves that turn's deterministic text unchanged.
public struct MeetingReadingTurnFormatter {
    public typealias FormatRequest = (String) async throws -> String
    public typealias ProgressHandler = @Sendable (MeetingReadingTurnFormattingProgress) -> Void

    public let maximumRequestCharacters: Int

    public init(maximumRequestCharacters: Int = AIFormatter.maxTranscriptionInputChars) {
        precondition(maximumRequestCharacters > 0)
        self.maximumRequestCharacters = maximumRequestCharacters
    }

    public func format(
        _ document: MeetingTranscriptPresentationDocument,
        using formatRequest: FormatRequest,
        onProgress: ProgressHandler? = nil
    ) async -> MeetingReadingTurnFormattingResult {
        let plans = document.turns.map(makePlan)
        let totalRequests = plans.reduce(0) { $0 + ($1?.requests.count ?? 0) }
        var completedRequests = 0
        var formatting: [MeetingReadingTurnFormatting] = []
        onProgress?(.init(completedRequests: 0, totalRequests: totalRequests))

        for (turn, plan) in zip(document.turns, plans) {
            if Task.isCancelled {
                return result(
                    formatting: formatting,
                    completedRequests: completedRequests,
                    totalRequests: totalRequests,
                    wasCancelled: true
                )
            }
            guard let plan else { continue }
            var outputs: [String] = []
            var turnIsValid = true
            var attemptedRequests = 0

            for request in plan.requests {
                if Task.isCancelled {
                    return result(
                        formatting: formatting,
                        completedRequests: completedRequests,
                        totalRequests: totalRequests,
                        wasCancelled: true
                    )
                }

                attemptedRequests += 1
                do {
                    let rawOutput = try await formatRequest(request)
                    if Task.isCancelled {
                        return result(
                            formatting: formatting,
                            completedRequests: completedRequests,
                            totalRequests: totalRequests,
                            wasCancelled: true
                        )
                    }
                    let output = AIFormatter.normalizedFormattedOutput(rawOutput)
                    guard Self.preservesContent(input: request, output: output) else {
                        turnIsValid = false
                        completedRequests += 1
                        onProgress?(
                            .init(
                                completedRequests: completedRequests,
                                totalRequests: totalRequests
                            ))
                        break
                    }
                    outputs.append(output)
                } catch is CancellationError {
                    return result(
                        formatting: formatting,
                        completedRequests: completedRequests,
                        totalRequests: totalRequests,
                        wasCancelled: true
                    )
                } catch {
                    turnIsValid = false
                }

                completedRequests += 1
                onProgress?(
                    .init(
                        completedRequests: completedRequests,
                        totalRequests: totalRequests
                    ))
                if !turnIsValid { break }
            }

            guard turnIsValid, outputs.count == plan.requests.count else {
                let skippedRequests = plan.requests.count - attemptedRequests
                if skippedRequests > 0 {
                    completedRequests += skippedRequests
                    onProgress?(
                        .init(
                            completedRequests: completedRequests,
                            totalRequests: totalRequests
                        ))
                }
                continue
            }
            if Task.isCancelled {
                return result(
                    formatting: formatting,
                    completedRequests: completedRequests,
                    totalRequests: totalRequests,
                    wasCancelled: true
                )
            }
            let formattedText = outputs.joined(separator: "\n\n")
            formatting.append(
                MeetingReadingTurnFormatting(
                    turnID: turn.id,
                    deterministicText: turn.deterministicText,
                    formattedText: formattedText
                )
            )
        }

        return result(
            formatting: formatting,
            completedRequests: completedRequests,
            totalRequests: totalRequests,
            wasCancelled: Task.isCancelled
        )
    }

    private func makePlan(for turn: ReadingTurn) -> TurnPlan? {
        let paragraphs = turn.paragraphs.map(\.text).filter { !$0.isEmpty }
        guard !paragraphs.isEmpty,
            paragraphs.allSatisfy({ $0.count <= maximumRequestCharacters })
        else { return nil }

        var requests: [String] = []
        var current = ""
        for paragraph in paragraphs {
            let candidate = current.isEmpty ? paragraph : current + "\n\n" + paragraph
            if candidate.count <= maximumRequestCharacters {
                current = candidate
            } else {
                requests.append(current)
                current = paragraph
            }
        }
        if !current.isEmpty { requests.append(current) }
        return requests.isEmpty ? nil : TurnPlan(requests: requests)
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
    private static func preservesContent(input: String, output: String) -> Bool {
        guard output.contains(where: { !$0.isWhitespace }) else { return false }
        let inputTokens = lexicalTokens(in: input)
        let outputTokens = lexicalTokens(in: output)
        guard !inputTokens.isEmpty, !outputTokens.isEmpty else { return false }
        guard protectedTokens(in: input) == protectedTokens(in: output) else { return false }

        let changedTokenCount = outputTokens.difference(from: inputTokens).count
        let baseline = max(inputTokens.count, outputTokens.count)
        return Double(changedTokenCount) / Double(baseline) <= 0.35
            && output.count <= max(input.count * 3 / 2, input.count + 200)
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

private struct TurnPlan {
    let requests: [String]
}

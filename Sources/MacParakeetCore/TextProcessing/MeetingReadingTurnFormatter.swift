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

    public init() {}

    public func format(
        _ document: MeetingTranscriptPresentationDocument,
        using formatRequest: FormatRequest,
        onProgress: ProgressHandler? = nil
    ) async -> MeetingReadingTurnFormattingResult {
        let turns = document.turns.filter {
            $0.deterministicText.contains(where: { !$0.isWhitespace })
        }
        let totalRequests = turns.isEmpty ? 0 : 1
        onProgress?(.init(completedRequests: 0, totalRequests: totalRequests))
        guard !turns.isEmpty else {
            return result(formatting: [], completedRequests: 0, totalRequests: 0, wasCancelled: false)
            }
        guard !Task.isCancelled else {
            return result(formatting: [], completedRequests: 0, totalRequests: 1, wasCancelled: true)
                }

        let request = turns.map(\.deterministicText).joined(
            separator: "\n\n\(Self.turnBoundary)\n\n"
        )
                do {
                    let rawOutput = try await formatRequest(request)
            guard !Task.isCancelled else {
                return result(formatting: [], completedRequests: 0, totalRequests: 1, wasCancelled: true)
                    }
            let outputs = rawOutput.components(separatedBy: Self.turnBoundary).map {
                AIFormatter.normalizedFormattedOutput($0)
                    }
            let formatting: [MeetingReadingTurnFormatting]
            if outputs.count == turns.count,
                zip(turns, outputs).allSatisfy({
                    Self.preservesContent(input: $0.deterministicText, output: $1)
                })
            {
                formatting = zip(turns, outputs).map {
                MeetingReadingTurnFormatting(
                        turnID: $0.id,
                        deterministicText: $0.deterministicText,
                        formattedText: $1
            )
        }
            } else {
                formatting = []
            }
            onProgress?(.init(completedRequests: 1, totalRequests: 1))
            return result(formatting: formatting, completedRequests: 1, totalRequests: 1, wasCancelled: false)
        } catch is CancellationError {
            return result(formatting: [], completedRequests: 0, totalRequests: 1, wasCancelled: true)
        } catch {
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

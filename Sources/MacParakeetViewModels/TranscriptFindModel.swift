import Foundation

/// Asynchronous matcher backing the in-transcript find bar.
///
/// The model is deliberately ignorant of SwiftUI and of how the transcript is
/// rendered. It searches an ordered list of text blocks and produces one
/// globally ordered match list. The draft `query` is published immediately;
/// settled matches arrive later after debounce and off-main-actor matching.
///
/// Match positions are `NSRange` values (UTF-16 offsets) relative to each
/// block. They bridge directly to the attributed transcript rendering.
@MainActor
@Observable
public final class TranscriptFindModel {
    public struct Match: Equatable, Sendable {
        /// Index into the blocks last passed to `setBlocks`.
        public let blockIndex: Int
        /// UTF-16 range of the match within that block's text.
        public let range: NSRange

        public init(blockIndex: Int, range: NSRange) {
            self.blockIndex = blockIndex
            self.range = range
        }
    }

    /// The current field value. This changes synchronously for every edit.
    public private(set) var query: String = ""

    /// True while the latest non-empty query is waiting or matching.
    public private(set) var isSearching = false

    /// Matches for the latest settled query, in reading order.
    public private(set) var matches: [Match] = []

    /// Index into `matches` of the emphasized match.
    public private(set) var currentMatchIndex: Int?

    private let debounce: Duration
    private var blocks: [String] = []
    private var searchGeneration: UInt64 = 0
    private var searchTask: Task<Void, Never>?

    public init(debounce: Duration = .milliseconds(75)) {
        self.debounce = debounce
    }

    // MARK: - Mutation

    /// Publish a field edit immediately, then schedule matching off the main
    /// actor. A trimmed-empty query cancels work and clears results immediately.
    public func setQuery(_ newValue: String) {
        guard newValue != query else { return }
        query = newValue
        scheduleSearch(preserving: nil, preferredIndex: nil)
    }

    /// Replace the searched content and re-run the current query against it.
    /// The current match is retained when the same block/range still exists;
    /// otherwise its ordinal is retained where possible.
    public func setBlocks(_ blocks: [String]) {
        let previousCurrent = current
        let previousIndex = currentMatchIndex
        self.blocks = blocks
        scheduleSearch(preserving: previousCurrent, preferredIndex: previousIndex)
    }

    /// Clear the draft query, settled results, and all pending work.
    public func clear() {
        query = ""
        cancelSearchAndClearResults()
    }

    /// Advance the cursor to the next match, wrapping at the end.
    public func next() {
        guard !matches.isEmpty else { return }
        let index = currentMatchIndex ?? -1
        currentMatchIndex = (index + 1) % matches.count
    }

    /// Move the cursor to the previous match, wrapping at the start.
    public func prev() {
        guard !matches.isEmpty else { return }
        let index = currentMatchIndex ?? 0
        currentMatchIndex = (index - 1 + matches.count) % matches.count
    }

    // MARK: - Derived state

    public var matchCount: Int { matches.count }
    public var hasMatches: Bool { !matches.isEmpty }

    public var current: Match? {
        guard let index = currentMatchIndex, matches.indices.contains(index) else { return nil }
        return matches[index]
    }

    /// 1-based "current of total" position, or `nil` without settled matches.
    public var displayPosition: (current: Int, total: Int)? {
        guard let index = currentMatchIndex, matches.indices.contains(index) else { return nil }
        return (index + 1, matches.count)
    }

    // MARK: - Search scheduling

    private func scheduleSearch(preserving previousCurrent: Match?, preferredIndex: Int?) {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()

        matches = []
        currentMatchIndex = nil

        // Search the untrimmed query so leading and trailing spaces remain
        // literal, but treat a whitespace-only draft as empty.
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isSearching = false
            searchTask = nil
            return
        }

        isSearching = true
        let needle = query
        let blockSnapshot = blocks
        let debounce = debounce

        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
                try Task.checkCancellation()

                let worker = Task.detached(priority: .userInitiated) {
                    try Self.findMatches(in: blockSnapshot, needle: needle)
                }
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()

                guard let self, self.searchGeneration == generation, self.query == needle else { return }
                self.publish(result, preserving: previousCurrent, preferredIndex: preferredIndex)
            } catch is CancellationError {
                // A newer query, new blocks, or clear operation owns the state.
            } catch {
                // Matching has no expected non-cancellation failure.
            }
        }
    }

    private func cancelSearchAndClearResults() {
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        matches = []
        currentMatchIndex = nil
    }

    private func publish(_ result: [Match], preserving previousCurrent: Match?, preferredIndex: Int?) {
        searchTask = nil
        isSearching = false
        matches = result

        guard !result.isEmpty else {
            currentMatchIndex = nil
            return
        }
        if let previousCurrent, let retainedIndex = result.firstIndex(of: previousCurrent) {
            currentMatchIndex = retainedIndex
        } else if let preferredIndex {
            currentMatchIndex = min(max(preferredIndex, 0), result.count - 1)
        } else {
            currentMatchIndex = 0
        }
    }

    // MARK: - Off-main-actor matching

    /// Scans at most this many Characters between cancellation checks. This
    /// keeps cancellation bounded even when Text mode supplies one large block.
    private nonisolated static let cancellationChunkSize = 4_096

    private nonisolated static func findMatches(in blocks: [String], needle: String) throws -> [Match] {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        // Unicode folding can expand one query Character into multiple source
        // Characters (for example, "ﬃ" matches "ffi"). Eighteen covers the
        // longest Unicode compatibility decomposition; the extra Character
        // covers the boundary itself. This keeps chunked matching equivalent
        // to a full range search.
        let overlapCharacterCount = max(needle.count * 18 + 1, 1)
        var result: [Match] = []

        for (blockIndex, text) in blocks.enumerated() where !text.isEmpty {
            try Task.checkCancellation()
            var chunkStart = text.startIndex
            var minimumSearchStart = text.startIndex

            while chunkStart < text.endIndex {
                try Task.checkCancellation()
                let chunkEnd =
                    text.index(
                        chunkStart,
                        offsetBy: cancellationChunkSize,
                        limitedBy: text.endIndex
                    ) ?? text.endIndex
                // Include enough look-ahead to find a match that starts just
                // before the chunk boundary. Only starts in the core chunk are
                // accepted, so overlap cannot duplicate matches.
                let searchEnd =
                    text.index(
                        chunkEnd,
                        offsetBy: overlapCharacterCount,
                        limitedBy: text.endIndex
                    ) ?? text.endIndex
                var searchStart = max(minimumSearchStart, chunkStart)

                while searchStart < searchEnd,
                    let found = text.range(of: needle, options: options, range: searchStart..<searchEnd),
                    found.lowerBound < chunkEnd
                {
                    try Task.checkCancellation()
                    result.append(Match(blockIndex: blockIndex, range: NSRange(found, in: text)))
                    searchStart =
                        found.upperBound > found.lowerBound
                        ? found.upperBound
                        : text.index(after: found.lowerBound)
                    minimumSearchStart = searchStart
                }

                chunkStart = chunkEnd
            }
        }

        return result
    }
}

import Foundation
import SwiftUI

/// Decides how the timed transcript body is laid out.
///
/// On macOS 26, selectable variable-height rows can trap a `LazyVStack` in a
/// self-feeding layout loop after the user scrolls down and back up. A plain
/// stack has no lazy view cache, so normal transcripts use it. Very large
/// transcripts keep lazy layout to avoid materializing an unbounded view tree.
struct TranscriptBodyStack<Content: View>: View {
    let rowCount: Int
    let content: Content

    init(
        rowCount: Int,
        @ViewBuilder content: () -> Content
    ) {
        self.rowCount = rowCount
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if TranscriptBodyLayout.usesLazyStack(rowCount: rowCount) {
            LazyVStack(
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                content
            }
        } else {
            VStack(
                alignment: .leading,
                spacing: DesignSystem.Spacing.md
            ) {
                content
            }
        }
    }
}

enum TranscriptBodyLayout {
    static let nonLazyRowLimit = 400

    static func usesLazyStack(
        rowCount: Int,
        environment: [String: String] = launchEnvironment
    ) -> Bool {
        if let override = debugOverride(
            named: "MACPARAKEET_DEBUG_TRANSCRIPT_LAZY",
            environment: environment
        ) {
            return override
        }
        return rowCount > nonLazyRowLimit
    }

    private static let launchEnvironment = ProcessInfo.processInfo.environment

    static func debugOverride(
        named name: String,
        environment: [String: String] = launchEnvironment
    ) -> Bool? {
        #if DEBUG
        guard let raw = environment[name]?.lowercased() else { return nil }
        switch raw {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
        #else
        return nil
        #endif
    }
}

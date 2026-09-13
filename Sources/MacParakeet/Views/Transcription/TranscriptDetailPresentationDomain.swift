import SwiftUI
import os

/// User-interaction seams in transcript detail. Each seam has an immutable
/// revision and can be measured or hosted through the production view path.
enum TranscriptDetailPresentationModule: String, CaseIterable, Hashable, Sendable {
    case header
    case actions
    case transcriptDocument
    case findSession
    case playbackFollow
    case speakerEditing
    case aiPanes
}

/// The exact display inputs that invalidate one transcript-detail presentation
/// module. Values are small semantic descriptions, not the mutable view-model
/// graph or the complete transcript.
struct TranscriptDetailPresentationRevision: Equatable, Sendable {
    let values: [String]

    init(_ values: [String]) {
        self.values = values
    }
}

@MainActor
final class TranscriptFindSessionDriver {
    private let setQueryAction: (String) -> Void

    init(setQuery: @escaping (String) -> Void) {
        self.setQueryAction = setQuery
    }

    func setQuery(_ query: String) {
        setQueryAction(query)
    }
}

private let transcriptDetailPresentationSignposter = OSSignposter(
    subsystem: "com.macparakeet",
    category: "TranscriptDetailPresentation"
)

/// An Equatable SwiftUI seam that stops unrelated parent state changes before
/// they evaluate the module content. The content closure executes only when the
/// module's immutable revision changes.
struct TranscriptDetailInvalidationDomain<Content: View>: View, Equatable {
    let module: TranscriptDetailPresentationModule
    let revision: TranscriptDetailPresentationRevision
    let evaluationProbe: ((TranscriptDetailPresentationModule) -> Void)?
    private let content: () -> Content

    init(
        module: TranscriptDetailPresentationModule,
        revision: TranscriptDetailPresentationRevision,
        evaluationProbe: ((TranscriptDetailPresentationModule) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.module = module
        self.revision = revision
        self.evaluationProbe = evaluationProbe
        self.content = content
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.module == rhs.module && lhs.revision == rhs.revision
    }

    var body: some View {
        let _ = recordEvaluation()
        content()
    }

    private func recordEvaluation() {
        evaluationProbe?(module)
        switch module {
        case .header:
            transcriptDetailPresentationSignposter.emitEvent("Header Body")
        case .actions:
            transcriptDetailPresentationSignposter.emitEvent("Actions Body")
        case .transcriptDocument:
            transcriptDetailPresentationSignposter.emitEvent("Transcript Document Body")
        case .findSession:
            transcriptDetailPresentationSignposter.emitEvent("Find Session Body")
        case .playbackFollow:
            transcriptDetailPresentationSignposter.emitEvent("Playback Follow Body")
        case .speakerEditing:
            transcriptDetailPresentationSignposter.emitEvent("Speaker Editing Body")
        case .aiPanes:
            transcriptDetailPresentationSignposter.emitEvent("AI Panes Body")
        }
    }
}

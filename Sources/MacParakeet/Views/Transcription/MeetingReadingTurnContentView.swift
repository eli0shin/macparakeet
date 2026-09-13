import AppKit
import SwiftUI
import MacParakeetCore

struct IdentifiedReadingTurn: Identifiable, Sendable {
    let turn: ReadingTurn
    let scrollID: Int

    var id: ReadingTurnIdentity { turn.id }
}

func identifiedReadingTurns(_ turns: [ReadingTurn]) -> [IdentifiedReadingTurn] {
    turns.enumerated().map { index, turn in
        IdentifiedReadingTurn(turn: turn, scrollID: -2_000_000_000 + index)
    }
}

enum MeetingReadingTurnLayout {
    static let interTurnSpacing: CGFloat = 2
    static let horizontalPadding = DesignSystem.Spacing.sm
    static let verticalPadding: CGFloat = 7
    static let bylineSpacing: CGFloat = 6
    static let bodyIndent: CGFloat = 13
    static let speakerMarkerSize: CGFloat = 7
    static let playbackFocusWidth: CGFloat = 2
    /// Leading between text lines; paragraph blank lines come from the text.
    static let bodyLineSpacing: CGFloat = 4
    static let bylineHeight: CGFloat = 20
}

func readingTurnScrollTarget(
    for currentMs: Int,
    in turns: [IdentifiedReadingTurn],
    playbackIndex: ReadingTurnPlaybackIndex? = nil
) -> Int? {
    if let playbackIndex {
        guard let target = playbackIndex.turnID(at: currentMs) else { return nil }
        return turns.first { $0.id == target }?.scrollID
    }
    return turns.filter { ($0.turn.timeRange?.startMs ?? .max) <= currentMs }
        .max { ($0.turn.timeRange?.startMs ?? .min) < ($1.turn.timeRange?.startMs ?? .min) }?.scrollID
}

/// The completed-meeting Reading surface. `NSTableView` realizes only visible
/// Reading Turns. Its delegate supplies stable cached heights for the complete
/// document, so exact bounds and distant navigation do not depend on estimated
/// SwiftUI lazy layout.
struct MeetingReadingTurnContentView<Header: View>: NSViewRepresentable {
    let turns: [IdentifiedReadingTurn]
    let speakerColorMap: [String: Color]
    let header: Header
    let contentRevision: Int
    let headerRevision: Int
    let activeScrollID: Int?
    let navigationScrollID: Int?
    let navigationToken: Int
    let timestampLabel: (Int) -> String
    let isTimestampSeekable: Bool
    let onTimestampTap: (Int) -> Void
    let onCopyTurn: (ReadingTurn) -> Void
    let onRenameSpeaker: (String, String) -> Void
    var bodyPointSize: CGFloat = 15
    var currentHighlight: (id: Int, range: NSRange)?

    init(
        turns: [IdentifiedReadingTurn],
        speakerColorMap: [String: Color],
        contentRevision: Int = 0,
        headerRevision: Int = 0,
        activeScrollID: Int?,
        navigationScrollID: Int? = nil,
        navigationToken: Int = 0,
        timestampLabel: @escaping (Int) -> String,
        isTimestampSeekable: Bool,
        onTimestampTap: @escaping (Int) -> Void,
        onCopyTurn: @escaping (ReadingTurn) -> Void,
        onRenameSpeaker: @escaping (String, String) -> Void = { _, _ in },
        bodyPointSize: CGFloat = 15,
        currentHighlight: (id: Int, range: NSRange)? = nil,
        @ViewBuilder header: () -> Header
    ) {
        self.turns = turns
        self.speakerColorMap = speakerColorMap
        self.header = header()
        self.contentRevision = contentRevision
        self.headerRevision = headerRevision
        self.activeScrollID = activeScrollID
        self.navigationScrollID = navigationScrollID
        self.navigationToken = navigationToken
        self.timestampLabel = timestampLabel
        self.isTimestampSeekable = isTimestampSeekable
        self.onTimestampTap = onTimestampTap
        self.onCopyTurn = onCopyTurn
        self.onRenameSpeaker = onRenameSpeaker
        self.bodyPointSize = bodyPointSize
        self.currentHighlight = currentHighlight
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = TranscriptTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.intercellSpacing = NSSize(width: 0, height: MeetingReadingTurnLayout.interTurnSpacing)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAutomaticRowHeights = false
        table.addTableColumn(NSTableColumn(identifier: .transcriptColumn))
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.setAccessibilityLabel("Meeting transcript Reading Turns")

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = table
        context.coordinator.tableView = table
        context.coordinator.scrollView = scrollView
        table.onWidthChange = { [weak coordinator = context.coordinator] width in
            coordinator?.tableWidthDidChange(width)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private var parent: MeetingReadingTurnContentView
        private var heightCache: [Int: CGFloat] = [:]
        private var scrollRows: [Int: Int] = [:]
        private var contentSignature: ContentSignature
        private var measuredWidth: CGFloat = 0
        private var lastHeaderRevision: Int
        private var lastNavigationToken: Int?
        private var lastNavigationID: Int?
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?

        init(parent: MeetingReadingTurnContentView) {
            self.parent = parent
            contentSignature = ContentSignature(parent)
            lastHeaderRevision = parent.headerRevision
            super.init()
            rebuildScrollRows()
        }

        func numberOfRows(in _: NSTableView) -> Int { parent.turns.count + 1 }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if row == 0 { return headerHeight(for: tableView) }
            let turnIndex = row - 1
            if let cached = heightCache[turnIndex] { return cached }
            let height = Self.turnHeight(
                text: parent.turns[turnIndex].turn.text,
                width: tableView.bounds.width,
                pointSize: parent.bodyPointSize
            )
            heightCache[turnIndex] = height
            return height
        }

        func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
            if row == 0 {
                let identifier = NSUserInterfaceItemIdentifier.headerRow
                let host =
                    (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSHostingView<AnyView>)
                    ?? NSHostingView(rootView: AnyView(EmptyView()))
                host.identifier = identifier
                host.rootView = AnyView(parent.header.frame(maxWidth: .infinity, alignment: .leading))
                return host
            }

            let identifier = NSUserInterfaceItemIdentifier.readingTurnRow
            let view =
                (tableView.makeView(withIdentifier: identifier, owner: nil) as? ReadingTurnTableCellView)
                ?? ReadingTurnTableCellView(identifier: identifier)
            configure(view, row: row)
            return view
        }

        func update(parent: MeetingReadingTurnContentView) {
            let previousSignature = contentSignature
            let previousHeaderRevision = lastHeaderRevision
            self.parent = parent
            contentSignature = ContentSignature(parent)
            lastHeaderRevision = parent.headerRevision

            guard let tableView else { return }
            let width = tableView.bounds.width
            let contentChanged = previousSignature != contentSignature
            let widthChanged = abs(width - measuredWidth) > 0.5
            if contentChanged {
                heightCache.removeAll(keepingCapacity: true)
                rebuildScrollRows()
                tableView.reloadData()
            } else if widthChanged {
                heightCache.removeAll(keepingCapacity: true)
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<tableView.numberOfRows))
            } else {
                updateVisibleRows(in: tableView)
            }
            measuredWidth = width

            if previousHeaderRevision != parent.headerRevision, !contentChanged {
                tableView.reloadData(forRowIndexes: IndexSet(integer: 0), columnIndexes: IndexSet(integer: 0))
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: 0))
            }
            navigateIfNeeded(in: tableView)
        }

        func tableWidthDidChange(_ width: CGFloat) {
            guard let tableView, width > 1, abs(width - measuredWidth) > 0.5 else { return }
            measuredWidth = width
            heightCache.removeAll(keepingCapacity: true)
            guard tableView.numberOfRows > 0 else { return }
            tableView.noteHeightOfRows(
                withIndexesChanged: IndexSet(integersIn: 0..<tableView.numberOfRows)
            )
            tableView.layoutSubtreeIfNeeded()
            clampScrollPosition()
            lastNavigationID = nil
            navigateIfNeeded(in: tableView)
        }

        private func clampScrollPosition() {
            guard let tableView, let scrollView else { return }
            let clipView = scrollView.contentView
            let maximumY = max(0, tableView.frame.height - clipView.bounds.height)
            let y = min(max(0, clipView.bounds.origin.y), maximumY)
            guard y != clipView.bounds.origin.y else { return }
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: y))
            scrollView.reflectScrolledClipView(clipView)
        }

        private func updateVisibleRows(in tableView: NSTableView) {
            let rows = tableView.rows(in: tableView.visibleRect)
            guard rows.location != NSNotFound else { return }
            for row in rows.location..<(rows.location + rows.length) where row > 0 {
                if let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
                    as? ReadingTurnTableCellView
                {
                    configure(view, row: row)
                }
            }
        }

        private func configure(_ view: ReadingTurnTableCellView, row: Int) {
            let identified = parent.turns[row - 1]
            let color =
                parent.speakerColorMap[identified.turn.speakerId]
                .map(NSColor.init)
                ?? sourceColor(for: identified.turn.source)
            view.configure(
                identified: identified,
                speakerColor: color,
                isActive: parent.activeScrollID == identified.scrollID,
                timestampLabel: parent.timestampLabel,
                isTimestampSeekable: parent.isTimestampSeekable,
                onTimestampTap: parent.onTimestampTap,
                onCopyTurn: parent.onCopyTurn,
                onRenameSpeaker: parent.onRenameSpeaker,
                bodyPointSize: parent.bodyPointSize,
                currentRange: parent.currentHighlight?.id == identified.scrollID
                    ? parent.currentHighlight?.range
                    : nil
            )
        }

        private func navigateIfNeeded(in tableView: NSTableView) {
            guard let scrollID = parent.navigationScrollID,
                lastNavigationID != scrollID || lastNavigationToken != parent.navigationToken,
                let row = scrollRows[scrollID]
            else { return }
            lastNavigationID = scrollID
            lastNavigationToken = parent.navigationToken
            tableView.layoutSubtreeIfNeeded()
            let rowRect = tableView.rect(ofRow: row)
            guard let clipView = scrollView?.contentView else {
                tableView.scrollRowToVisible(row)
                return
            }
            let maximumY = max(0, tableView.bounds.height - clipView.bounds.height)
            let centeredY = min(max(0, rowRect.midY - clipView.bounds.height / 2), maximumY)
            clipView.scroll(to: NSPoint(x: 0, y: centeredY))
            scrollView?.reflectScrolledClipView(clipView)
        }

        private func rebuildScrollRows() {
            scrollRows = Dictionary(
                uniqueKeysWithValues: parent.turns.enumerated().map { ($0.element.scrollID, $0.offset + 1) }
            )
        }

        private func headerHeight(for tableView: NSTableView) -> CGFloat {
            let width = max(1, tableView.bounds.width)
            let host = NSHostingView(
                rootView: AnyView(parent.header.frame(width: width, alignment: .leading))
            )
            host.frame.size.width = width
            return max(1, ceil(host.fittingSize.height))
        }

        private func sourceColor(for source: ReadingTurnSource) -> NSColor {
            switch source {
            case .microphone:
                return NSColor(DesignSystem.Colors.accent)
            case .system:
                return NSColor(DesignSystem.Colors.speakerColor(for: 1))
            case .unknown:
                return NSColor(DesignSystem.Colors.textTertiary)
            }
        }

        private static func turnHeight(text: String, width: CGFloat, pointSize: CGFloat) -> CGFloat {
            let textWidth = max(
                1,
                width - (MeetingReadingTurnLayout.horizontalPadding * 2)
                    - MeetingReadingTurnLayout.bodyIndent
            )
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = MeetingReadingTurnLayout.bodyLineSpacing
            let cell = NSTextFieldCell(textCell: "")
            cell.wraps = true
            cell.isScrollable = false
            cell.lineBreakMode = .byWordWrapping
            cell.attributedStringValue = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: pointSize),
                    .paragraphStyle: paragraph,
                ]
            )
            let bodyHeight = ceil(
                cell.cellSize(
                    forBounds: NSRect(
                        origin: .zero,
                        size: NSSize(width: textWidth, height: .greatestFiniteMagnitude)
                    )
                ).height
            )
            return bodyHeight
                + MeetingReadingTurnLayout.bylineHeight
                + DesignSystem.Spacing.xs
                + (MeetingReadingTurnLayout.verticalPadding * 2)
        }
    }
}

private struct ContentSignature: Equatable {
    let count: Int
    let firstID: ReadingTurnIdentity?
    let lastID: ReadingTurnIdentity?
    let pointSize: CGFloat
    let revision: Int

    init<Header>(_ parent: MeetingReadingTurnContentView<Header>) {
        count = parent.turns.count
        firstID = parent.turns.first?.id
        lastID = parent.turns.last?.id
        pointSize = parent.bodyPointSize
        revision = parent.contentRevision
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let transcriptColumn = NSUserInterfaceItemIdentifier("MeetingTranscriptColumn")
    static let headerRow = NSUserInterfaceItemIdentifier("MeetingTranscriptHeader")
    static let readingTurnRow = NSUserInterfaceItemIdentifier("MeetingReadingTurnRow")
}

private final class TranscriptTableView: NSTableView {
    var onWidthChange: ((CGFloat) -> Void)?
    private var reportedWidth: CGFloat = 0

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let width = bounds.width
        if width > 1, abs(width - reportedWidth) > 0.5 {
            reportedWidth = width
            onWidthChange?(width)
        }
    }
}

@MainActor
private final class ReadingTurnTableCellView: NSTableCellView, NSTextFieldDelegate {
    private let focusBar = NSView()
    private let marker = NSView()
    private let speakerLabel = NSTextField(labelWithString: "")
    private let renameButton = NSButton()
    private let timestampButton = NSButton()
    private let bodyLabel = ReadingTurnTextField(labelWithString: "")
    private var identified: IdentifiedReadingTurn?
    private var onTimestampTap: ((Int) -> Void)?
    private var onCopyTurn: ((ReadingTurn) -> Void)?
    private var onRenameSpeaker: ((String, String) -> Void)?
    private var originalSpeakerLabel = ""

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        wantsLayer = true

        focusBar.wantsLayer = true
        marker.wantsLayer = true

        speakerLabel.isEditable = false
        speakerLabel.isSelectable = false
        speakerLabel.isBordered = false
        speakerLabel.drawsBackground = false
        speakerLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        speakerLabel.delegate = self
        speakerLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        renameButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        renameButton.title = ""
        renameButton.isBordered = false
        renameButton.target = self
        renameButton.action = #selector(beginRename)

        timestampButton.isBordered = false
        timestampButton.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timestampButton.target = self
        timestampButton.action = #selector(timestampPressed)

        bodyLabel.isSelectable = true
        bodyLabel.isEditable = false
        bodyLabel.isBordered = false
        bodyLabel.drawsBackground = false
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.cell?.wraps = true
        bodyLabel.cell?.isScrollable = false
        bodyLabel.owner = self

        for view in [focusBar, marker, speakerLabel, renameButton, timestampButton, bodyLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            focusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            focusBar.topAnchor.constraint(equalTo: topAnchor),
            focusBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            focusBar.widthAnchor.constraint(equalToConstant: MeetingReadingTurnLayout.playbackFocusWidth),

            marker.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: MeetingReadingTurnLayout.horizontalPadding),
            marker.topAnchor.constraint(equalTo: topAnchor, constant: MeetingReadingTurnLayout.verticalPadding + 6.5),
            marker.widthAnchor.constraint(equalToConstant: MeetingReadingTurnLayout.speakerMarkerSize),
            marker.heightAnchor.constraint(equalToConstant: MeetingReadingTurnLayout.speakerMarkerSize),

            speakerLabel.leadingAnchor.constraint(
                equalTo: marker.trailingAnchor, constant: MeetingReadingTurnLayout.bylineSpacing),
            speakerLabel.topAnchor.constraint(equalTo: topAnchor, constant: MeetingReadingTurnLayout.verticalPadding),
            speakerLabel.heightAnchor.constraint(equalToConstant: MeetingReadingTurnLayout.bylineHeight),
            speakerLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 200),

            renameButton.leadingAnchor.constraint(
                equalTo: speakerLabel.trailingAnchor, constant: MeetingReadingTurnLayout.bylineSpacing),
            renameButton.centerYAnchor.constraint(equalTo: speakerLabel.centerYAnchor),
            renameButton.widthAnchor.constraint(equalToConstant: 20),
            renameButton.heightAnchor.constraint(equalToConstant: 20),

            timestampButton.leadingAnchor.constraint(
                equalTo: renameButton.trailingAnchor, constant: MeetingReadingTurnLayout.bylineSpacing),
            timestampButton.centerYAnchor.constraint(equalTo: speakerLabel.centerYAnchor),
            timestampButton.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -MeetingReadingTurnLayout.horizontalPadding),

            bodyLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: MeetingReadingTurnLayout.horizontalPadding + MeetingReadingTurnLayout.bodyIndent
            ),
            bodyLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -MeetingReadingTurnLayout.horizontalPadding),
            bodyLabel.topAnchor.constraint(
                equalTo: topAnchor,
                constant: MeetingReadingTurnLayout.verticalPadding
                    + MeetingReadingTurnLayout.bylineHeight
                    + DesignSystem.Spacing.xs
            ),
            bodyLabel.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -MeetingReadingTurnLayout.verticalPadding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(
        identified: IdentifiedReadingTurn,
        speakerColor: NSColor,
        isActive: Bool,
        timestampLabel: (Int) -> String,
        isTimestampSeekable: Bool,
        onTimestampTap: @escaping (Int) -> Void,
        onCopyTurn: @escaping (ReadingTurn) -> Void,
        onRenameSpeaker: @escaping (String, String) -> Void,
        bodyPointSize: CGFloat,
        currentRange: NSRange?
    ) {
        self.identified = identified
        self.onTimestampTap = onTimestampTap
        self.onCopyTurn = onCopyTurn
        self.onRenameSpeaker = onRenameSpeaker
        originalSpeakerLabel = identified.turn.speakerLabel
        if !speakerLabel.isEditable { speakerLabel.stringValue = originalSpeakerLabel }

        marker.layer?.cornerRadius = MeetingReadingTurnLayout.speakerMarkerSize / 2
        marker.layer?.backgroundColor =
            speakerColor.withAlphaComponent(
                DesignSystem.Colors.transcriptSpeakerLabelAlpha
            ).cgColor
        focusBar.layer?.backgroundColor = speakerColor.withAlphaComponent(isActive ? 0.8 : 0).cgColor
        speakerLabel.textColor = speakerColor

        renameButton.toolTip = SpeakerRenameAccessibility.renameButtonLabel(for: originalSpeakerLabel)
        renameButton.setAccessibilityLabel(SpeakerRenameAccessibility.renameButtonLabel(for: originalSpeakerLabel))
        renameButton.setAccessibilityHelp(SpeakerRenameAccessibility.renameButtonHint)
        renameButton.setAccessibilityIdentifier(
            SpeakerRenameAccessibility.renameButtonIdentifier(contextID: renameContextID)
        )

        if let startMs = identified.turn.timeRange?.startMs {
            timestampButton.title = timestampLabel(startMs)
            timestampButton.tag = startMs
            timestampButton.isHidden = false
            timestampButton.isEnabled = isTimestampSeekable
            timestampButton.contentTintColor = isTimestampSeekable ? .secondaryLabelColor : .tertiaryLabelColor
            timestampButton.toolTip = isTimestampSeekable ? "Play from this Reading Turn" : "Audio is not ready"
            timestampButton.setAccessibilityLabel("Start time \(timestampLabel(startMs))")
            timestampButton.setAccessibilityHelp(isTimestampSeekable ? "Play from this Reading Turn" : "")
        } else {
            timestampButton.isHidden = true
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = MeetingReadingTurnLayout.bodyLineSpacing
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: bodyPointSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSMutableAttributedString(string: identified.turn.text, attributes: attributes)
        if let currentRange,
            currentRange.location >= 0,
            currentRange.length >= 0,
            NSMaxRange(currentRange) <= attributed.length
        {
            attributed.addAttribute(
                .backgroundColor,
                value: NSColor(DesignSystem.Colors.accent).withAlphaComponent(0.55),
                range: currentRange
            )
        }
        bodyLabel.attributedStringValue = attributed
        setAccessibilityLabel("\(identified.turn.speakerLabel) reading turn")
    }

    @objc private func timestampPressed() {
        onTimestampTap?(timestampButton.tag)
    }

    @objc private func beginRename() {
        speakerLabel.isEditable = true
        speakerLabel.isSelectable = true
        speakerLabel.becomeFirstResponder()
        speakerLabel.currentEditor()?.selectAll(nil)
        speakerLabel.setAccessibilityLabel(SpeakerRenameAccessibility.speakerNameFieldLabel)
        speakerLabel.setAccessibilityHelp(SpeakerRenameAccessibility.speakerNameFieldHint)
        speakerLabel.setAccessibilityIdentifier(
            SpeakerRenameAccessibility.speakerNameFieldIdentifier(contextID: renameContextID)
        )
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        let movement = (notification.userInfo?["NSTextMovement"] as? Int).flatMap(NSTextMovement.init)
        finishRename(commit: movement != .cancel)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        finishRename(commit: false)
        return true
    }

    private func finishRename(commit: Bool) {
        guard speakerLabel.isEditable, let identified else { return }
        let value = speakerLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        speakerLabel.isEditable = false
        speakerLabel.isSelectable = false
        if commit, !value.isEmpty, value != originalSpeakerLabel {
            onRenameSpeaker?(identified.turn.speakerId, value)
        } else {
            speakerLabel.stringValue = originalSpeakerLabel
        }
        window?.makeFirstResponder(bodyLabel)
    }

    fileprivate func copyReadingTurn() {
        guard let turn = identified?.turn else { return }
        onCopyTurn?(turn)
    }

    private var renameContextID: String {
        guard let turn = identified?.turn else { return "turn:unknown" }
        return SpeakerRenameAccessibility.turnRenameContextIdentifier(
            speakerID: turn.speakerId,
            firstStartMs: turn.timeRange?.startMs,
            duplicateOrdinal: turn.id.firstWordIndex ?? 0
        )
    }
}

private final class ReadingTurnTextField: NSTextField {
    weak var owner: ReadingTurnTableCellView?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let item = NSMenuItem(title: "Copy Reading Turn", action: #selector(copyReadingTurn), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func copyReadingTurn() { owner?.copyReadingTurn() }
}

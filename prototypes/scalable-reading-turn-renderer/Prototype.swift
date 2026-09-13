#!/usr/bin/env swift

import AppKit

// THROWAWAY PROTOTYPE: compare exact-height NSTableView virtualization with the
// eager SwiftUI Reading Turn shape. It uses only generated public text.

final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let texts = (0..<1_200).map { index in
        Array(
            repeating: "Public synthetic meeting text keeps variable wrapping and selection.",
            count: [1, 4, 10, 18][index % 4]
        ).joined(separator: " ")
    }
    var realized = 0

    func numberOfRows(in _: NSTableView) -> Int { texts.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let width = max(1, tableView.bounds.width - 32)
        let bounds = (texts[row] as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: NSFont.systemFont(ofSize: 15)]
        )
        return ceil(bounds.height) + 38
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let field = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField)
            ?? NSTextField(wrappingLabelWithString: "")
        field.identifier = id
        field.isSelectable = true
        field.stringValue = texts[row]
        realized += 1
        return field
    }
}

let app = NSApplication.shared
let rows = Rows()
let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("transcript")))
table.headerView = nil
table.dataSource = rows
table.delegate = rows
let measuredHeight = rows.texts.indices.reduce(CGFloat.zero) {
    $0 + rows.tableView(table, heightOfRow: $1) + 2
}
table.frame.size.height = measuredHeight
let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
scroll.hasVerticalScroller = true
scroll.documentView = table
let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = scroll
window.orderFront(nil)
let start = ProcessInfo.processInfo.systemUptime
table.reloadData()
scroll.layoutSubtreeIfNeeded()
table.layoutSubtreeIfNeeded()
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
let initialMs = (ProcessInfo.processInfo.systemUptime - start) * 1_000
let initialRealized = rows.realized

table.scrollRowToVisible(1_199)
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
let finalVisible = table.rows(in: table.visibleRect)
print(String(format: "initial_ms=%.1f", initialMs))
print("initial_realized=\(initialRealized) total=\(rows.texts.count)")
print("last_row_visible=\(finalVisible.contains(1_199)) visible_count=\(finalVisible.length)")
app.terminate(nil)

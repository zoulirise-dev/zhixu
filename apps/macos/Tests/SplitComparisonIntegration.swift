import AppKit

@main struct SplitComparisonIntegration {
    @MainActor static func main() throws {
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw GitFailure.message("FAIL: " + message) }
            print("PASS: " + message)
        }
        let before = "共同\n旧内容\n尾部\n"
        let after = "共同\n新内容\n新增👋\n尾部\n"
        let comparison = RestoreComparison.make(current: .file(Data(before.utf8), false), backup: .file(Data(after.utf8), false))
        let split = SplitComparison(rows: comparison.rows)
        try check(split.left.count == split.right.count, "panes have equal aligned row counts")
        try check(split.left.map(\.text) == ["共同", "旧内容", "", "尾部"], "shorter replacement block is padded")
        try check(split.right.map(\.text) == ["共同", "新内容", "新增👋", "尾部"], "backup replacement lines align")
        try check(split.left[2].old == nil && split.left.last?.old == 3 && split.right.last?.new == 4, "blank rows have no number and real lines retain source numbers")
        let deleted = SplitComparison(rows: DiffLine.added("a\nb").map { DiffLine(text: $0.text, old: $0.new, new: nil, kind: .removed) })
        try check(deleted.right.allSatisfy { $0.text.isEmpty && $0.new == nil }, "deleted file has empty backup pane")
        _ = NSApplication.shared
        let host = RestoreSplitHost(frame: NSRect(x: 0, y: 0, width: 900, height: 360))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let rows = (1...200).map { (line: Int) in DiffLine(text: "let line\(line) = \(line)", old: line, new: line, kind: .context) }
        host.apply(rows: rows, path: "demo.swift")
        for surface in [host.left, host.right] {
            surface.layoutSubtreeIfNeeded()
            surface.editor.layoutManager?.ensureLayout(for: surface.editor.textContainer!)
            surface.editor.sizeToFit()
        }
        host.left.contentView.scroll(to: NSPoint(x: 0, y: 800))
        try check(host.left.contentView.bounds.minY > 0 && abs(host.left.contentView.bounds.minY - host.right.contentView.bounds.minY) < 1, "scrolling current pane synchronizes backup")
        host.right.contentView.scroll(to: NSPoint(x: 0, y: 1800))
        try check(abs(host.left.contentView.bounds.minY - host.right.contentView.bounds.minY) < 1, "scrolling backup pane synchronizes current")
        try check(!host.left.editor.isEditable && !host.right.editor.isEditable, "both comparison panes are read-only")
        host.apply(rows: comparison.rows, path: "demo.swift")
        try check(host.left.contentView.bounds.minY == 0 && host.right.contentView.bounds.minY == 0, "switching conflict resets both scroll positions")
        print("All split comparison checks passed")
    }
}

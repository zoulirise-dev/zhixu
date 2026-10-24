import SwiftUI
import AppKit

struct RestoreSplitEditor: NSViewRepresentable {
    let rows: [DiffLine]
    let path: String
    func makeNSView(context: Context) -> RestoreSplitHost { RestoreSplitHost() }
    func updateNSView(_ host: RestoreSplitHost, context: Context) { host.apply(rows: rows, path: path) }
}

final class RestoreSplitHost: NSView {
    let left = EditorSurface()
    let right = EditorSurface()
    private var syncing = false
    private var rows: [DiffLine]?
    private var path: String?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.masksToBounds = true
        for surface in [left, right] {
            addSubview(surface)
            surface.useSingleDiffColumn()
            surface.hasVerticalScroller = true
            // Identical viewport heights keep the final rows aligned even with long lines.
            surface.autohidesScrollers = false
            surface.scrollerStyle = .legacy
        }
        left.editor.setAccessibilityLabel(L("当前文件，只读"))
        right.editor.setAccessibilityLabel(L("备份文件，只读"))
        left.onScroll = { [weak self] in self?.synchronize(fromLeft: true) }
        right.onScroll = { [weak self] in self?.synchronize(fromLeft: false) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let width = floor((bounds.width - 1) / 2)
        left.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        right.frame = NSRect(x: width + 1, y: 0, width: bounds.width - width - 1, height: bounds.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill(); dirtyRect.fill()
    }
    func apply(rows: [DiffLine], path: String) {
        guard self.rows != rows || self.path != path else { return }
        self.rows = rows; self.path = path
        let split = SplitComparison(rows: rows)
        // Each pane has its own source line numbers, including gaps for alignment.
        let rightRows = split.right.map { DiffLine(text: $0.text, old: nil, new: $0.new, kind: $0.kind) }
        syncing = true
        for (surface, lines) in [(left, split.left), (right, rightRows)] {
            surface.apply(text: lines.map(\.text).joined(separator: "\n"), language: SourceLanguage.detect(path), editable: false, diffLines: lines, isDiff: true, baseline: nil)
            surface.contentView.scroll(to: .zero)
            surface.reflectScrolledClipView(surface.contentView)
        }
        syncing = false
    }
    private func synchronize(fromLeft: Bool) {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let source = fromLeft ? left : right
        let target = fromLeft ? right : left
        // Horizontal scrolling remains independent so long lines can be inspected separately.
        target.contentView.scroll(to: NSPoint(x: target.contentView.bounds.minX, y: source.contentView.bounds.minY))
        target.reflectScrolledClipView(target.contentView)
    }
}

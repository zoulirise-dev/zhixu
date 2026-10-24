import SwiftUI
import AppKit

struct SourceFileIcon: View {
    let path: String
    private var kind: (String, Color, Bool) {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (name as NSString).pathExtension
        switch ext {
        case "js", "jsx", "mjs", "cjs": return ("JS", Color(red: 0.65, green: 0.51, blue: 0.02), true)
        case "ts", "tsx": return ("TS", .blue, true)
        case "php": return ("php", Color(red: 0.57, green: 0.38, blue: 0.73), true)
        case "css", "scss", "sass", "less": return ("number", Color(red: 0.18, green: 0.53, blue: 0.67), false)
        case "html", "htm", "xml", "vue", "svelte": return ("chevron.left.forwardslash.chevron.right", .orange, false)
        case "json", "yaml", "yml", "toml": return ("curlybraces", Color(red: 0.65, green: 0.51, blue: 0.02), false)
        case "md", "txt": return ("doc.text", .secondary, false)
        case "swift": return ("swift", .orange, false)
        case "py": return ("PY", .blue, true)
        case "png", "jpg", "jpeg", "svg", "ico", "webp": return ("photo", .purple, false)
        default:
            if name.contains("env") || name.contains("config") { return ("gearshape", .secondary, false) }
            if name.hasPrefix(".git") { return ("diamond", .secondary, false) }
            return ("doc", .secondary, false)
        }
    }
    var body: some View {
        Group {
            if kind.2 { Text(kind.0).font(.system(size: kind.0 == "php" ? 8 : 9, weight: .bold, design: .monospaced)) }
            else { Image(systemName: kind.0).font(.system(size: 11, weight: .medium)) }
        }.foregroundStyle(kind.1).frame(width: 16, height: 16).accessibilityHidden(true)
    }
}

@MainActor final class ExplorerState: ObservableObject {
    @Published var expanded = Set<String>()
    @Published var searchCollapsed = Set<String>()
    @Published var searchFolders = Set<String>()
    @Published var tree: [FileNode] = []
    @Published var rows: [VisibleFileRow] = []
    var sourcePaths: [String]?
    func reset() {
        expanded = []; searchCollapsed = []; searchFolders = []
        tree = []; rows = []; sourcePaths = nil
    }
}

struct FileExplorer: View {
    @ObservedObject var state: ExplorerState
    let paths: [String]
    let changes: [Change]
    let searching: Bool
    let cutPaths: Set<String>
    let ignoredPaths: Set<String>
    let expandFolder: (String) -> Void
    let shortcutsEnabled: Bool
    let clipboardAction: (String, [String], String) -> Void
    @Binding var selection: Set<String>
    let openFile: (String) -> Void
    let pinFile: (String) -> Void
    let menuItems: (String?, Bool) -> [AppMenuItem]
    @State private var anchor: String?
    @State private var focusedPath: String?
    @FocusState private var focused: Bool
    private var expandedPaths: Set<String> {
        searching ? state.searchFolders.subtracting(state.searchCollapsed) : state.expanded
    }
    @State private var decorations: [String: FileGitStatus] = [:]
    private func rebuildRows() { state.rows = VisibleFileRow.flatten(state.tree, expanded: expandedPaths) }
    private func toggle(_ path: String) {
        if searching {
            if state.searchCollapsed.contains(path) { state.searchCollapsed.remove(path) } else { state.searchCollapsed.insert(path) }
        } else {
            if state.expanded.contains(path) { state.expanded.remove(path) } else { state.expanded.insert(path) }
        }
        rebuildRows()
        if expandedPaths.contains(path) { expandFolder(path) }
    }
    private func select(_ row: VisibleFileRow) {
        focused = true; focusedPath = row.id
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift), let anchor, let first = state.rows.firstIndex(where: { $0.id == anchor }), let last = state.rows.firstIndex(where: { $0.id == row.id }) {
            selection.formUnion(state.rows[min(first,last)...max(first,last)].map(\.id)); return
        }
        if modifiers.contains(.command) {
            if selection.contains(row.id) { selection.remove(row.id) } else { selection.insert(row.id) }
            anchor = row.id; return
        }
        selection = [row.id]; anchor = row.id
        if row.node.children != nil { toggle(row.id) } else { openFile(row.id) }
    }
    private func clipboardShortcut(_ key: String) {
        let path = focusedPath.flatMap { selection.contains($0) ? $0 : nil } ?? selection.sorted().first
        let isFolder = state.rows.first(where: { $0.id == path })?.node.children != nil
        let destination = path.map { isFolder ? $0 : ($0 as NSString).deletingLastPathComponent } ?? ""
        clipboardAction(key, Array(selection), destination)
    }
    var body: some View {
        let expansion = expandedPaths
        ScrollViewReader { proxy in
            GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(spacing: 0) {
                    ForEach(state.rows) { row in
                        ExplorerRow(row: row, status: decorations[row.id], ignored: ignoredPaths.contains(row.id), expanded: expansion.contains(row.id), selected: selection.contains(row.id), action: { select(row) }, doubleClick: { if row.node.children == nil { selection = [row.id]; pinFile(row.id) } })
                            .opacity(cutPaths.contains { row.id == $0 || row.id.hasPrefix($0 + "/") } ? 0.4 : 1)
                            .themedContextMenu {
                                focused = true; focusedPath = row.id
                                if !selection.contains(row.id) { selection = [row.id]; anchor = row.id }
                                return menuItems(row.id, row.node.children != nil)
                            }
                            .id(row.id)
                    }
                    }.frame(height: CGFloat(state.rows.count) * 24, alignment: .top)
                    if state.rows.isEmpty { Text(L("没有匹配的文件")).font(.system(size: 12)).foregroundStyle(.secondary).padding(24).allowsHitTesting(false) }
                    Color.clear.frame(height: max(80, geometry.size.height - CGFloat(state.rows.count * 24) - (state.rows.isEmpty ? 65 : 8)))
                        .contentShape(Rectangle())
                        .onTapGesture { focused = true; focusedPath = nil; selection = []; anchor = nil }
                        .themedContextMenu {
                            focused = true; focusedPath = nil; selection = []; anchor = nil
                            return menuItems(nil, true)
                        }
                }.padding(.horizontal, 6).padding(.vertical, 4)
            }.background(Color(nsColor: AppTheme.panel)).focusable().focused($focused).focusEffectDisabled()
                .onKeyPress(phases: .down) { press in
                    guard shortcutsEnabled, press.modifiers == .command, ["x", "c", "v"].contains(press.characters.lowercased()) else { return .ignored }
                    clipboardShortcut(press.characters.lowercased())
                    return .handled
                }
                .task(id: paths) {
                    if state.sourcePaths == paths { rebuildRows(); return }
                    let source = paths
                    let (nodes, folders) = await Task.detached(priority: .userInitiated) {
                        var folders = Set<String>()
                        for path in source {
                            var parts = path.split(separator: "/"); parts.removeLast()
                            while !parts.isEmpty { folders.insert(parts.joined(separator: "/")); parts.removeLast() }
                        }
                        return (FileNode.tree(source), folders)
                    }.value
                    guard !Task.isCancelled else { return }
                    if searching { state.searchCollapsed = [] }
                    state.sourcePaths = source
                    state.tree = nodes; state.searchFolders = folders; rebuildRows()
                }
                .onAppear { decorations = FileGitStatus.decorations(changes) }
                .onChange(of: searching) { _, _ in rebuildRows() }
                .onChange(of: changes) { _, _ in decorations = FileGitStatus.decorations(changes) }
                .onMoveCommand { direction in
                    guard !state.rows.isEmpty else { return }
                    let index = state.rows.firstIndex { $0.id == focusedPath } ?? 0
                    let row = state.rows[index]
                    if direction == .right, row.node.children != nil, !expandedPaths.contains(row.id) { toggle(row.id); return }
                    if direction == .left, row.node.children != nil, expandedPaths.contains(row.id) { toggle(row.id); return }
                    let next = direction == .down ? min(index + 1, state.rows.count - 1) : direction == .up ? max(0, index - 1) : index
                    let target = state.rows[next]
                    focusedPath = target.id; anchor = target.id; selection = [target.id]
                    proxy.scrollTo(target.id)
                    if target.node.children == nil { openFile(target.id) }
                }
            }
        }
    }
}

private struct ExplorerRow: View {
    let row: VisibleFileRow
    let status: FileGitStatus?
    let ignored: Bool
    let expanded: Bool
    let selected: Bool
    let action: () -> Void
    let doubleClick: () -> Void
    @State private var hovered = false
    private var rowContent: some View {
        HStack(spacing: 5) {
            Color.clear.frame(width: CGFloat(row.depth) * 14)
            if row.node.children != nil {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).frame(width: 14)
            } else { SourceFileIcon(path: row.id).saturation(ignored ? 0 : 1).opacity(ignored ? 0.55 : 1).frame(width: 14) }
            Text(row.node.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(ignored ? Color.secondary : (status?.color ?? ink)).strikethrough(status == .deleted && row.node.children == nil)
            Spacer(minLength: 4)
            if let status {
                if row.node.children != nil { Circle().fill(status.color.opacity(0.8)).frame(width: 5, height: 5).frame(width: 14) }
                else { Text(status.badge).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(status.color).frame(width: 14) }
            }
        }
    }
    private var guideLines: some View {
        HStack(spacing: 13) {
            ForEach(0..<row.depth, id: \.self) { _ in Color.gray.opacity(0.16).frame(width: 1) }
        }.padding(.leading, 13).allowsHitTesting(false)
    }
    private var accessibleName: String {
        let folderState = row.node.children == nil ? "" : (expanded ? L("，已展开") : L("，已折叠"))
        return row.node.name + folderState + (ignored ? "，" + L("已忽略") : "") + (status.map { "，" + $0.label } ?? "")
    }
    var body: some View {
        rowContent.padding(.horizontal, 6).frame(height: 24)
            .background(selected ? accent.opacity(0.10) : hovered ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 3))
            .overlay(alignment: .leading) { guideLines }
            .contentShape(Rectangle()).onTapGesture {
                if row.node.children == nil, NSApp.currentEvent?.clickCount == 2 { doubleClick() } else { action() }
            }.onHover { hovered = $0 }.actionCursor()
            .help(row.id + (ignored ? " · " + L("已忽略") : "") + (status.map { " · " + $0.label } ?? ""))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibleName)
            .accessibilityAddTraits(.isButton).accessibilityAction { action() }
    }
}

struct ChangeFileRow: View {
    let change: Change
    let staged: Bool
    var advanced = true
    @Binding var checked: Bool
    let select: () -> Void
    let stage: () -> Void
    @State private var hovered = false
    var body: some View {
        let status = advanced ? FileGitStatus(change, staged: staged) : FileGitStatus(change)
        HStack(spacing: 5) {
            Toggle(L("选择 ") + change.path, isOn: $checked).labelsHidden().toggleStyle(ThemeCheckboxStyle())
            Button(action: select) {
                HStack(spacing: 5) {
                    SourceFileIcon(path: change.path)
                    Text((change.path as NSString).lastPathComponent).font(.system(size: 12)).foregroundStyle(status.color).strikethrough(status == .deleted).lineLimit(1).layoutPriority(1)
                    if change.path.contains("/") { Text((change.path as NSString).deletingLastPathComponent).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(CursorPlainButtonStyle()).help(change.path + " · " + status.label)
            if advanced { Button(action: stage) { Image(systemName: staged ? "minus" : "plus").font(.system(size: 12)).frame(width: 18, height: 20).contentShape(Rectangle()) }
                .buttonStyle(CursorPlainButtonStyle()).foregroundStyle(.secondary).opacity(hovered || checked ? 1 : 0.25)
                .help(staged ? L("取消暂存此文件") : L("暂存此文件"))
            }
            Text(status.badge).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(status.color).frame(width: 14).help(status.label)
        }.padding(.horizontal, 6).frame(height: 24)
            .background(checked ? accent.opacity(0.10) : hovered ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 3))
            .onHover { hovered = $0 }
    }
}

struct ResizableWorkspace<Left: View, Right: View>: View {
    let left: Left
    let right: Right
    @AppStorage("workspaceListWidth") private var savedWidth = 300.0
    @AppStorage("workspaceListWidthDefault300Applied") private var appliedDefaultWidth = false
    @State private var dragStart: CGFloat?
    @State private var hovering = false
    var body: some View {
        GeometryReader { geometry in
            let limit = max(260, geometry.size.width - 287)
            let width = min(max(260, savedWidth), limit)
            HStack(spacing: 0) {
                left.frame(width: width).panelCard()
                Rectangle().fill(Color.clear).frame(width: 7)
                    .overlay { Rectangle().fill(hovering || dragStart != nil ? accent.opacity(0.5) : hairline).frame(width: hovering || dragStart != nil ? 2 : 1) }
                    .overlay {
                        ResizeHandle(hover: { hovering = $0 }, drag: { translation in
                            if dragStart == nil { dragStart = width }
                            savedWidth = min(max(260, (dragStart ?? width) + translation), limit)
                        }, end: { dragStart = nil }, reset: { savedWidth = 300 })
                    }
                    .help(L("左右拖动调整列表宽度；双击恢复 300 像素"))
                    .accessibilityLabel(L("列表宽度"))
                    .accessibilityValue(L("{0} 像素", [String(describing: Int(width))]))
                    .accessibilityAdjustableAction { direction in
                        savedWidth = min(max(260, width + (direction == .increment ? 20 : -20)), limit)
                    }
                right.frame(maxWidth: .infinity, maxHeight: .infinity).panelCard()
            }
            .onAppear {
                if !appliedDefaultWidth {
                    savedWidth = 300
                    appliedDefaultWidth = true
                }
            }
        }
    }
}


private struct ResizeHandle: NSViewRepresentable {
    @Environment(\.isEnabled) private var enabled
    let hover: (Bool) -> Void
    let drag: (CGFloat) -> Void
    let end: () -> Void
    let reset: () -> Void
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ view: HandleView, context: Context) {
        view.hover = hover; view.drag = drag; view.end = end; view.reset = reset
        view.enabled = enabled
    }
    final class HandleView: NSView {
        var enabled = true {
            didSet {
                guard oldValue != enabled else { return }
                if !enabled {
                    startX = nil
                    if NSCursor.current == NSCursor.resizeLeftRight { NSCursor.arrow.set() }
                    DispatchQueue.main.async { [weak self] in self?.hover?(false); self?.end?() }
                }
                discardCursorRects()
                updateTrackingAreas()
                window?.invalidateCursorRects(for: self)
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { enabled ? super.hitTest(point) : nil }
        var hover: ((Bool) -> Void)?
        var drag: ((CGFloat) -> Void)?
        var end: (() -> Void)?
        var reset: (() -> Void)?
        private var area: NSTrackingArea?
        private var startX: CGFloat?
        override var acceptsFirstResponder: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { if enabled { addCursorRect(bounds, cursor: .resizeLeftRight) } }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area); self.area = nil }
            guard enabled else { return }
            let tracking = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseEnteredAndExited, .cursorUpdate], owner: self)
            addTrackingArea(tracking); area = tracking
        }
        override func cursorUpdate(with event: NSEvent) { if enabled { NSCursor.resizeLeftRight.set() } }
        override func mouseEntered(with event: NSEvent) { guard enabled else { return }; hover?(true); NSCursor.resizeLeftRight.set() }
        override func mouseExited(with event: NSEvent) {
            guard enabled else { return }
            hover?(false)
            if startX == nil { NSCursor.arrow.set() }
        }
        override func mouseDown(with event: NSEvent) {
            guard enabled else { return }
            NSCursor.resizeLeftRight.set()
            if event.clickCount == 2 { reset?(); startX = nil; return }
            startX = event.locationInWindow.x
        }
        override func mouseDragged(with event: NSEvent) {
            guard enabled, let startX else { return }
            NSCursor.resizeLeftRight.set()
            drag?(event.locationInWindow.x - startX)
        }
        override func mouseUp(with event: NSEvent) {
            guard enabled else { return }
            startX = nil; end?()
            if bounds.contains(convert(event.locationInWindow, from: nil)) { NSCursor.resizeLeftRight.set() }
            else { NSCursor.arrow.set() }
        }
    }
}

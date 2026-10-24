import Foundation

struct FileNode: Identifiable {
    let path: String
    let name: String
    let children: [FileNode]?
    var id: String { path }
    static func tree(_ paths: [String], prefix: String = "") -> [FileNode] {
        let groups = Dictionary(grouping: paths) { String($0.split(separator: "/").first ?? "") }
        return groups.keys.sorted { a, b in
            let aFolder = groups[a]!.contains { $0.contains("/") }, bFolder = groups[b]!.contains { $0.contains("/") }
            return aFolder == bFolder ? a.localizedStandardCompare(b) == .orderedAscending : aFolder
        }.map { name in
            let full = prefix.isEmpty ? name : prefix + "/" + name
            let folder = groups[name]!.contains { $0.contains("/") }
            let nested = groups[name]!.filter { $0.contains("/") }.map { String($0.dropFirst(name.count + 1)) }.filter { !$0.isEmpty }
            return FileNode(path: full, name: name, children: folder ? tree(nested, prefix: full) : nil)
        }
    }
}

/// Shared status precedence for file badges and ancestor-folder indicators.
enum FileGitStatus: Int {
    case untracked = 1, added, renamed, modified, deleted, conflict
    var badge: String {
        switch self {
        case .untracked: return "U"
        case .added: return "A"
        case .renamed: return "R"
        case .modified: return "M"
        case .deleted: return "D"
        case .conflict: return "!"
        }
    }
    var label: String {
        switch self {
        case .untracked: return L("未跟踪")
        case .added: return L("新增")
        case .renamed: return L("重命名")
        case .modified: return L("已修改")
        case .deleted: return L("已删除")
        case .conflict: return L("合并冲突")
        }
    }
    init(_ change: Change) {
        if change.conflict { self = .conflict }
        else if change.index == "?" { self = .untracked }
        else if change.index == "D" || change.work == "D" { self = .deleted }
        else if change.index == "R" || change.work == "R" { self = .renamed }
        else if change.index == "A" { self = .added }
        else { self = .modified }
    }
    init(_ change: Change, staged: Bool) {
        if change.conflict { self = .conflict; return }
        if change.index == "?" { self = .untracked; return }
        switch staged ? change.index : change.work {
        case "A": self = .added
        case "D": self = .deleted
        case "R", "C": self = .renamed
        default: self = .modified
        }
    }
    static func decorations(_ changes: [Change]) -> [String: FileGitStatus] {
        var result: [String: FileGitStatus] = [:]
        for change in changes {
            let status = FileGitStatus(change)
            var parts = change.path.split(separator: "/")
            while !parts.isEmpty {
                let path = parts.joined(separator: "/")
                if (result[path]?.rawValue ?? 0) < status.rawValue { result[path] = status }
                parts.removeLast()
            }
        }
        return result
    }
}

struct VisibleFileRow: Identifiable {
    let node: FileNode
    let depth: Int
    var id: String { node.path }
    static func flatten(_ nodes: [FileNode], expanded: Set<String>, depth: Int = 0) -> [VisibleFileRow] {
        nodes.flatMap { node in
            [VisibleFileRow(node: node, depth: depth)] +
            (expanded.contains(node.path) ? flatten(node.children ?? [], expanded: expanded, depth: depth + 1) : [])
        }
    }
}

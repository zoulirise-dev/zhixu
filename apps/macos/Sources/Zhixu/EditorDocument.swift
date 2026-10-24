import Foundation

struct EditorDocument: Identifiable {
    let id: String
    let path: String
    var text: String
    var savedText: String
    var editable: Bool
    var preview: Bool = true
    var isDiff: Bool = false
    var baseline: String? = nil
    var diffLines: [DiffLine] = []
    var dirty: Bool { editable && text != savedText }
    var name: String { (path as NSString).lastPathComponent }
}

struct DiffLine: Equatable {
    enum Kind { case context, added, removed }
    let text: String
    let old: Int?
    let new: Int?
    let kind: Kind

    static func parse(_ patch: String) -> [DiffLine] {
        var result: [DiffLine] = [], old = 0, new = 0, inHunk = false
        for line in patch.components(separatedBy: "\n") {
            if line.hasPrefix("@@ ") {
                let fields = line.split(separator: " ")
                guard fields.count >= 3,
                      let a = Int(fields[1].dropFirst().split(separator: ",")[0]),
                      let b = Int(fields[2].dropFirst().split(separator: ",")[0]) else { continue }
                old = a; new = b; inHunk = true
            } else if line.hasPrefix("diff --git ") { inHunk = false }
            else if inHunk, let marker = line.first {
                let text = String(line.dropFirst())
                switch marker {
                case " ": result.append(DiffLine(text: text, old: old, new: new, kind: .context)); old += 1; new += 1
                case "+": result.append(DiffLine(text: text, old: nil, new: new, kind: .added)); new += 1
                case "-": result.append(DiffLine(text: text, old: old, new: nil, kind: .removed)); old += 1
                default: break
                }
            }
        }
        return result
    }
    static func added(_ text: String) -> [DiffLine] {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines.enumerated().map { DiffLine(text: $0.element, old: nil, new: $0.offset + 1, kind: .added) }
    }
}

struct LineChange: Equatable {
    enum Kind { case added, modified, deleted }
    let line: Int // zero-based line in the current buffer
    let kind: Kind
    var afterLine: Bool = false
    static func compare(base: String, current: String) -> [LineChange] {
        func lines(_ text: String) -> [String] {
            guard !text.isEmpty else { return [] }
            return text.components(separatedBy: "\n")
        }
        let old = lines(base), new = lines(current)
        guard old != new else { return [] }
        let difference = new.difference(from: old)
        var removed = Set<Int>(), added = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }
        var a = 0, b = 0, result: [LineChange] = []
        while a < old.count || b < new.count {
            let start = b
            var deletions = 0
            while removed.contains(a) { a += 1; deletions += 1 }
            while added.contains(b) { b += 1 }
            if b > start {
                for line in start..<b { result.append(LineChange(line: line, kind: deletions > 0 ? .modified : .added)) }
            } else if deletions > 0 {
                result.append(LineChange(line: min(b, max(0, new.count - 1)), kind: .deleted, afterLine: b >= new.count && !new.isEmpty))
            }
            if a < old.count { a += 1 }
            if b < new.count { b += 1 }
        }
        return result
    }
}

/// A read-only comparison of the exact snapshots used by the restore decision.
struct RestoreComparison {
    let rows: [DiffLine]
    let note: String
    let available: Bool
    var text: String { rows.map(\.text).joined(separator: "\n") }
    static func make(current: StashRestore.Snapshot, backup: StashRestore.Snapshot) -> Self {
        func decode(_ value: StashRestore.Snapshot) -> String? {
            switch value {
            case .missing: return ""
            case .link(let target): return target
            case .file(let data, _):
                guard data.count <= 512_000, !data.contains(0) else { return nil }
                return String(data: data, encoding: .utf8)
            case .directory: return nil
            }
        }
        guard let a = decode(current), let b = decode(backup) else {
            return Self(rows: [], note: L("此文件为二进制、非 UTF-8 文本、文件夹或超过 500 KB，无法显示文本差异。"), available: false)
        }
        func lines(_ text: String) -> [String] {
            if text.isEmpty { return [] }
            var result = text.components(separatedBy: "\n")
            if result.last == "" { result.removeLast() }
            return result
        }
        let old = lines(a), new = lines(b)
        guard old.count + new.count <= 10_000 else {
            return Self(rows: [], note: L("文件行数过多，无法显示文本差异。"), available: false)
        }
        var removed = Set<Int>(), added = Set<Int>()
        for change in new.difference(from: old) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }
        var i = 0, j = 0, rows: [DiffLine] = []
        while i < old.count || j < new.count {
            if removed.contains(i) {
                rows.append(DiffLine(text: old[i], old: i + 1, new: nil, kind: .removed)); i += 1
            } else if added.contains(j) {
                rows.append(DiffLine(text: new[j], old: nil, new: j + 1, kind: .added)); j += 1
            } else {
                rows.append(DiffLine(text: old[i], old: i + 1, new: j + 1, kind: .context)); i += 1; j += 1
            }
        }
        var notes: [String] = []
        if a.hasSuffix("\n") != b.hasSuffix("\n") {
            notes.append(L("文件末尾换行：当前{0}，备份{1}", [String(describing: a.hasSuffix("\n") ? L("有") : L("无")), String(describing: b.hasSuffix("\n") ? L("有") : L("无"))]))
        }
        if case .file(_, let x) = current, case .file(_, let y) = backup, x != y {
            notes.append(L("执行权限：当前{0}，备份{1}", [String(describing: x ? L("可执行") : L("不可执行")), String(describing: y ? L("可执行") : L("不可执行"))]))
        }
        if a == b { notes.insert(L("文本内容相同，文件类型或属性不同"), at: 0) }
        return Self(rows: rows, note: notes.joined(separator: " · "), available: true)
    }
}

/// Keep unchanged lines opposite each other; pad unequal change blocks with blank rows.
struct SplitComparison {
    let left: [DiffLine]
    let right: [DiffLine]
    init(rows: [DiffLine]) {
        var left: [DiffLine] = [], right: [DiffLine] = []
        var index = 0
        let blank = DiffLine(text: "", old: nil, new: nil, kind: .context)
        while index < rows.count {
            if rows[index].kind == .context {
                left.append(rows[index]); right.append(rows[index]); index += 1
            } else {
                var removed: [DiffLine] = [], added: [DiffLine] = []
                while index < rows.count && rows[index].kind != .context {
                    if rows[index].kind == .removed { removed.append(rows[index]) }
                    else { added.append(rows[index]) }
                    index += 1
                }
                for offset in 0..<max(removed.count, added.count) {
                    left.append(offset < removed.count ? removed[offset] : blank)
                    right.append(offset < added.count ? added[offset] : blank)
                }
            }
        }
        self.left = left; self.right = right
    }
}

struct ConflictBlock: Identifiable {
    let start: Int
    let end: Int
    let ours: [String]
    let theirs: [String]
    var id: Int { start }
    static func parse(_ text: String) -> [Self] {
        let lines = text.components(separatedBy: "\n")
        var result: [Self] = [], i = 0
        while i < lines.count {
            guard lines[i].hasPrefix("<<<<<<< ") else { i += 1; continue }
            let start = i; i += 1
            var ours: [String] = [], theirs: [String] = [], base = false
            while i < lines.count && lines[i] != "=======" {
                if lines[i].hasPrefix("||||||| ") { base = true }
                else if !base { ours.append(lines[i]) }
                i += 1
            }
            guard i < lines.count else { break }; i += 1
            while i < lines.count && !lines[i].hasPrefix(">>>>>>> ") { theirs.append(lines[i]); i += 1 }
            guard i < lines.count else { break }
            result.append(Self(start: start, end: i, ours: ours, theirs: theirs)); i += 1
        }
        return result
    }
    func replacing(in text: String, choice: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        lines.replaceSubrange(start...end, with: choice == 0 ? ours : choice == 1 ? theirs : ours + theirs)
        return lines.joined(separator: "\n")
    }
}

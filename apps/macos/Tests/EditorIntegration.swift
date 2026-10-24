import Foundation
import AppKit

@main struct EditorIntegration {
    @MainActor static func main() async throws {
        func check(_ condition: Bool, _ label: String) throws { guard condition else { throw GitFailure.message("FAIL: " + label) }; print("PASS: " + label) }
        func snapshot(_ text: String, executable: Bool = false) -> StashRestore.Snapshot { .file(Data(text.utf8), executable) }
        let comparison = RestoreComparison.make(current: snapshot("same\n旧内容👋\ntail\n"), backup: snapshot("same\n新内容\n新增\ntail\n"))
        try check(comparison.rows.filter { $0.kind != .added }.map(\.text) == ["same", "旧内容👋", "tail"], "restore comparison reconstructs current version")
        try check(comparison.rows.filter { $0.kind != .removed }.map(\.text) == ["same", "新内容", "新增", "tail"], "restore comparison reconstructs backup version")
        try check(comparison.rows.last?.old == 3 && comparison.rows.last?.new == 4, "restore comparison keeps both line numbers")
        try check(RestoreComparison.make(current: snapshot("a"), backup: snapshot("a\n")).note.contains("末尾换行"), "restore comparison explains EOF newline change")
        try check(RestoreComparison.make(current: snapshot("a"), backup: snapshot("a", executable: true)).note.contains("执行权限"), "restore comparison explains mode-only change")
        try check(RestoreComparison.make(current: snapshot("a\n"), backup: .missing).rows.allSatisfy { $0.kind == .removed }, "restore deletion shows removed content")
        try check(!RestoreComparison.make(current: .file(Data([0, 1]), false), backup: snapshot("a")).available, "binary restore comparison has explicit fallback")
        try check(RestoreComparison.make(current: .link("before"), backup: .link("after")).rows.count == 2, "symlink comparison shows target difference")
        let patch = "diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1,3 +1,4 @@\n same\n-old\n+new\n+中文👋\n tail\n\\ No newline at end of file\n"
        let rows = DiffLine.parse(patch)
        try check(rows.map(\.text) == ["same", "old", "new", "中文👋", "tail"], "inline diff strips patch metadata and preserves Unicode")
        try check(rows.map(\.old) == [1, 2, nil, nil, 3] && rows.map(\.new) == [1, nil, 2, 3, 4], "inline diff keeps independent old/new line numbers")
        try check(rows[1].kind == .removed && rows[2].kind == .added, "inline diff distinguishes additions and removals")
        try check(DiffLine.added("a\n\n").map(\.text) == ["a", ""], "untracked file preserves blank lines without phantom final line")
        try check(DiffLine.parse("@@ -1,2 +0,0 @@\n-a\n-b\n").map(\.old) == [1, 2], "deleted file retains old line numbers")
        try check(LineChange.compare(base: "a\nb\nc", current: "a\nB\nc") == [LineChange(line: 1, kind: .modified)], "gutter replacement is blue")
        try check(LineChange.compare(base: "a\nc", current: "a\nb\nc") == [LineChange(line: 1, kind: .added)], "gutter insertion is green")
        try check(LineChange.compare(base: "a\nb\nc", current: "a\nc") == [LineChange(line: 1, kind: .deleted)], "gutter deletion anchors before next line")
        try check(LineChange.compare(base: "a\nb", current: "a") == [LineChange(line: 0, kind: .deleted, afterLine: true)], "EOF deletion anchors after final line")
        try check(LineChange.compare(base: "a", current: "a").isEmpty, "reverting edits clears gutter")
        let cases: [(SourceLanguage, String, String, SyntaxKind)] = [
            (.java, "public class Demo { String name = \"你好\"; }", "class", .keyword),
            (.php, "<p>Hello</p><?php echo \"world\"; ?>", "echo", .keyword),
            (.html, "<h1 class=\"title\">Hello</h1>", "<h1", .tag),
            (.css, ".card { color: #fff; }", "color", .property),
            (.json, "{\"name\": \"hello\", \"n\": 42}", "\"name\"", .property),
            (.markdown, "# Hello\n\n**world**", "# Hello", .heading),
            (.javascript, "const x = 42; // class const", "const", .keyword),
            (.typescript, "interface Person { name: string }", "interface", .keyword),
            (.python, "def greet(name):\n    return 'hi'", "def", .keyword),
            (.swift, "let greeting = \"你好👋\"\nfunc run() {}", "func", .keyword),
            (.sql, "SELECT name FROM users", "SELECT", .keyword),
            (.yaml, "name: value\n# hello", "name", .property),
            (.shell, "echo \"hello\" # comment", "echo", .keyword)
        ]
        for (language, source, target, kind) in cases {
            let range = (source as NSString).range(of: target)
            let tokens = SyntaxHighlighter.tokens(source, language: language)
            try check(tokens.contains { $0.kind == kind && NSIntersectionRange($0.range, range).length == range.length }, "syntax: " + language.rawValue)
        }
        let embedded = "<script>const n = 1;</script><style>.a { color: red; }</style>"
        let nested = SyntaxHighlighter.tokens(embedded, language: .html)
        try check(nested.contains { $0.kind == .keyword && (embedded as NSString).substring(with: $0.range) == "const" }, "embedded JavaScript highlighting")
        try check(nested.contains { $0.kind == .property && (embedded as NSString).substring(with: $0.range) == "color" }, "embedded CSS highlighting")
        let comment = "// public class false\nString s = \"class\";"
        let commentTokens = SyntaxHighlighter.tokens(comment, language: .java)
        try check(!commentTokens.contains { $0.kind == .keyword }, "keywords inside comments and strings are not highlighted separately")
        let html = MarkdownRenderer.render("# Title\n\n- item\n\n```java\nclass Test {}\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n<script>alert(1)</script>")
        try check(html.contains("<h1>Title</h1>") && html.contains("<li>item</li>") && html.contains("<pre><code>class Test {}"), "Markdown headings, lists and fenced code")
        try check(html.contains("<table>") && html.contains("&lt;script&gt;") && !html.contains("<script>"), "Markdown tables and escaped raw HTML")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-editor-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.java", "b.php", "c.md"] { try "original \(name)\n".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        let suite = "zhixu-editor-" + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let model = Workspace(defaults: prefs, restore: false)
        model.project = Project(path: root.path)
        func waitPreview() async throws {
            for _ in 0..<500 {
                if !model.loadingPreview { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw GitFailure.message("Preview timeout")
        }
        model.load("a.java", staged: false); try await waitPreview(); model.load("b.php", staged: false); try await waitPreview()
        try check(model.tabs.count == 1 && model.activeTabID == "b.php", "new file replaces unchanged preview tab")
        model.code = "<?php echo 'edited'; ?>"
        try check(model.tabs[0].dirty && !model.tabs[0].preview, "editing marks tab dirty and pins it")
        model.load("c.md", staged: false); try await waitPreview()
        try check(model.tabs.count == 2 && model.tabs[0].text.contains("edited"), "switching files preserves unsaved buffer")
        model.activateTab("b.php")
        try check(model.dirty && model.code.contains("edited"), "returning to tab restores unsaved content")
        try check(model.save() && !model.dirty && !model.tabs[0].dirty && !model.tabs[0].preview, "save clears dirty dot and retains pinned tab")
        try check(try String(contentsOf: root.appendingPathComponent("b.php"), encoding: .utf8) == model.code, "save writes the correct buffer")
        model.load("a.java", staged: false); try await waitPreview()
        try check(model.tabs.count == 2 && model.tabs.contains { $0.id == "b.php" } && !model.tabs.contains { $0.id == "c.md" }, "only preview tab is replaced")
        model.code = "changed locally"
        try "changed externally".write(to: root.appendingPathComponent("a.java"), atomically: true, encoding: .utf8)
        try check(!model.save() && model.dirty, "external disk changes block overwrite and retain edits")
        model.activateTab("b.php"); model.closeTab("b.php")
        try check(model.activeTabID == "a.java" && model.code == "changed locally", "closing saved tab selects remaining dirty buffer")
        _ = try await Git.run(root.path, ["init", "-q"])
        _ = try await Git.run(root.path, ["add", "--", "a.java"])
        _ = try await Git.run(root.path, ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "base"])
        try "staged\n".write(to: root.appendingPathComponent("a.java"), atomically: true, encoding: .utf8)
        _ = try await Git.run(root.path, ["add", "--", "a.java"])
        try "working\n".write(to: root.appendingPathComponent("a.java"), atomically: true, encoding: .utf8)
        try await model.refresh()
        func waitForLoad() async throws {
            for _ in 0..<500 {
                if !model.loadingPreview { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw GitFailure.message("Diff loading timed out")
        }
        model.loadDiff("a.java", staged: true); try await waitForLoad()
        try check(model.code.contains("staged") && !model.code.contains("working"), "staged diff compares HEAD with index")
        model.pinTab(model.activeTabID!)
        model.loadDiff("a.java", staged: false); try await waitForLoad()
        try check(model.code == "staged\nworking", "unstaged diff compares index with working file")
        model.loadDiff("a.java", staged: false, combined: true); try await waitForLoad()
        try check(model.code.contains("changed externally") && model.code.contains("working") && !model.code.contains("staged"), "simple mode preview compares HEAD with full working content")
        model.checked = ["c.md"]; model.message = "selected"
        try check(model.commitItems.map(\.path) == ["c.md"] && model.canCommit, "simple mode enables checked untracked files")
        model.advancedMode = true
        try check(model.commitItems.isEmpty && !model.canCommit, "advanced mode requires selected staged content")
        model.checked = ["a.java"]
        try check(model.commitItems.map(\.path) == ["a.java"], "advanced mode limits commit to checked staged files")
        model.advancedMode = false
        model.activateTab("a.java")
        try check(model.code == "changed locally" && model.dirty, "diff previews never replace unsaved source buffer")
        model.loadDiff("c.md", staged: false); try await waitForLoad()
        try check(model.tabs.first(where: { $0.id == model.activeTabID })?.diffLines.allSatisfy { $0.kind == .added } == true && model.code == "original c.md", "untracked diff displays added source lines")
        model.loadDiff("a.java", staged: false)
        try check(!model.busy, "preview loading does not disable whole application")
        model.load("b.php", staged: false); model.load("a.java", staged: false)
        try await waitPreview()
        try check(model.activeTabID == "a.java", "rapid file switching keeps latest selection")
        model.checked = ["a.java", "c.md"]
        let activeBeforeRefresh = model.activeTabID, bufferBeforeRefresh = model.code
        let idsBeforeRefresh = model.tabs.map(\.id)
        try "new change".write(to: root.appendingPathComponent("refresh-only.txt"), atomically: true, encoding: .utf8)
        model.refreshChanges()
        try check(!model.busy && model.changesRefreshing, "list refresh never enables global busy state")
        model.checked.insert("b.php")
        while model.changesRefreshing { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.changes.contains { $0.path == "refresh-only.txt" }, "list refresh discovers disk changes")
        try check(model.checked == ["a.java", "b.php", "c.md"], "list refresh preserves selection including changes made while loading")
        try check(model.activeTabID == activeBeforeRefresh && model.code == bufferBeforeRefresh && model.tabs.map(\.id) == idsBeforeRefresh && model.dirty, "list refresh preserves active tab and unsaved editor buffer")
        let stashRoot = root.appendingPathComponent("stash-case")
        try FileManager.default.createDirectory(at: stashRoot, withIntermediateDirectories: true)
        func stashGit(_ args: [String]) async throws -> String { try await Git.run(stashRoot.path, args) }
        _ = try await stashGit(["init", "-q"])
        _ = try await stashGit(["config", "user.name", "Test"])
        _ = try await stashGit(["config", "user.email", "test@example.invalid"])
        let trackedURL = stashRoot.appendingPathComponent("tracked.txt"), untrackedURL = stashRoot.appendingPathComponent("new.txt")
        try "base".write(to: trackedURL, atomically: true, encoding: .utf8)
        _ = try await stashGit(["add", "."]); _ = try await stashGit(["commit", "-qm", "base"])
        try "restored change".write(to: trackedURL, atomically: true, encoding: .utf8)
        try "backup version".write(to: untrackedURL, atomically: true, encoding: .utf8)
        _ = try await stashGit(["stash", "push", "-u"])
        try "existing version".write(to: untrackedURL, atomically: true, encoding: .utf8)
        model.clearEditors(); try await model.open(stashRoot.path)
        model.error = nil
        model.sync("pop")
        for _ in 0..<500 {
            if model.restoreConflict != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try check(model.restoreConflict?.path == "new.txt", "restore presents differing file before any writes")
        try check(try String(contentsOf: trackedURL, encoding: .utf8) == "base", "restore waits for choice before changing tracked content")
        model.answerRestore(.keep)
        while model.busy {
            if let entry = model.restoreConflict { model.answerRestore(entry.path == "tracked.txt" ? .backup : .keep) }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try check(model.error == nil && model.notice.contains("保留当前 1"), "keep current completes without raw Git error")
        try check(model.changes.contains { $0.path == "tracked.txt" }, "failed stash restore still refreshes restored changes")
        try check(try String(contentsOf: trackedURL, encoding: .utf8) == "restored change", "partial restore applies tracked changes")
        try check(try String(contentsOf: untrackedURL, encoding: .utf8) == "existing version", "partial restore never overwrites existing untracked file")
        try check(!(try await stashGit(["stash", "list"])).isEmpty, "partial restore retains stash backup")
        print("All editor checks passed")
    }
}

import Foundation

@main struct Integration {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) async throws -> String { try await Git.run(root.path, args) }
        func check(_ condition: Bool, _ name: String) throws { guard condition else { throw GitFailure.message("FAIL: " + name) }; print("PASS: " + name) }
        _ = try await git(["init", "-b", "main"])
        _ = try await git(["config", "user.name", "Integration Test"])
        _ = try await git(["config", "user.email", "test@example.invalid"])
        let first = "中文 file.txt", second = "keep.txt"
        try "first\n".write(to: root.appendingPathComponent(first), atomically: true, encoding: .utf8)
        try "other\n".write(to: root.appendingPathComponent(second), atomically: true, encoding: .utf8)
        var state = Change.parse(try await git(["status", "--porcelain=v1", "-z"]))
        try check(state.count == 2 && state.allSatisfy { !$0.staged && $0.unstaged }, "new files and Unicode paths")
        _ = try await git(["add", "--", first])
        state = Change.parse(try await git(["status", "--porcelain=v1", "-z"]))
        try check(state.filter(\.staged).map(\.path) == [first], "stage only selected file")
        _ = try await git(["rm", "--cached", "--", first])
        try check(FileManager.default.fileExists(atPath: root.appendingPathComponent(first).path), "unstage initial commit preserves file")
        _ = try await git(["add", "--", first]); _ = try await git(["commit", "-m", "Initial"])
        let tracked = try await git(["ls-files", "-z"])
        try check(tracked.split(separator: "\0").map(String.init) == [first], "commit excludes unselected file")
        try "first\nsecond\n".write(to: root.appendingPathComponent(first), atomically: true, encoding: .utf8)
        _ = try await git(["add", "--", first])
        try "first\nsecond\nthird\n".write(to: root.appendingPathComponent(first), atomically: true, encoding: .utf8)
        state = Change.parse(try await git(["status", "--porcelain=v1", "-z"]))
        try check(state.contains { $0.path == first && $0.staged && $0.unstaged }, "separate staged and unstaged modifications")
        _ = try await git(["reset", "-q", "HEAD", "--", first])
        let content = try String(contentsOf: root.appendingPathComponent(first), encoding: .utf8)
        try check(content.contains("third"), "unstage preserves worktree edits")
        _ = try await git(["add", "--", first]); _ = try await git(["commit", "-m", "Update"])
        _ = try await git(["mv", "--", first, "renamed.txt"])
        state = Change.parse(try await git(["status", "--porcelain=v1", "-z"]))
        try check(state.contains { $0.path == "renamed.txt" && $0.original == first }, "rename parsing")
        _ = try await git(["switch", "-c", "feature/test"])
        let branch = try await git(["symbolic-ref", "--short", "HEAD"])
        try check(branch.trimmingCharacters(in: .whitespacesAndNewlines) == "feature/test", "branch creation and switching")
        let tree = FileNode.tree(["README.md", "src/components/Button.swift", "src/App.swift", "Assets/icon.png"])
        try check(tree.map(\.name) == ["Assets", "src", "README.md"], "file tree groups folders before files")
        try check(tree[1].children?.first?.children?.first?.path == "src/components/Button.swift", "file tree preserves nested full paths")
        for number in 0..<51 { _ = try await git(["commit", "--allow-empty", "-m", "Pagination \(number)"]) }
        let firstPage = try await git(["log", "--max-count=51", "--skip=0", "--format=%h"])
        let secondPage = try await git(["log", "--max-count=51", "--skip=50", "--format=%h"])
        let firstIDs = firstPage.split(separator: "\n"), secondIDs = secondPage.split(separator: "\n")
        try check(firstIDs.count == 51 && secondIDs.count == 3, "history page size and final page")
        try check(Set(firstIDs.prefix(50)).isDisjoint(with: Set(secondIDs)), "history pagination has no duplicate commits")
        let decorations = FileGitStatus.decorations([
            Change(path: "src/new.js", original: nil, index: "?", work: "?"),
            Change(path: "src/deep/changed.js", original: nil, index: "M", work: " "),
            Change(path: "removed.txt", original: nil, index: "D", work: " "),
            Change(path: "merge.txt", original: nil, index: "U", work: "U")
        ])
        try check(decorations["src/new.js"] == .untracked && decorations["src/deep/changed.js"] == .modified, "tree file status badges")
        try check(decorations["src"] == .modified && decorations["src/deep"] == .modified && decorations["sr"] == nil, "tree ancestor indicators and path boundaries")
        try check(decorations["removed.txt"] == .deleted && decorations["merge.txt"] == .conflict, "tree deletion and conflict markers")
        let mixed = Change(path: "new.txt", original: nil, index: "A", work: "M")
        try check(FileGitStatus(mixed, staged: true) == .added && FileGitStatus(mixed, staged: false) == .modified, "staged and unstaged badges use their own status")
        let localOnly = try await PendingPush.read(root.path)
        try check(localOnly.upstream == nil && localOnly.ids.count == 53, "unlinked branch counts local-only commits")
        _ = try await git(["init", "--bare", "remote.git"])
        _ = try await git(["remote", "add", "origin", root.appendingPathComponent("remote.git").path])
        _ = try await git(["push", "--set-upstream", "origin", "HEAD"])
        let synced = try await PendingPush.read(root.path)
        try check(synced.ids.isEmpty && synced.upstream == "origin/feature/test", "successful push clears pending count")
        _ = try await git(["commit", "--allow-empty", "-m", "Local one"])
        _ = try await git(["commit", "--allow-empty", "-m", "Local two"])
        let pending = try await PendingPush.read(root.path)
        try check(pending.ids.count == 2, "two local commits await push")
        let log = try await git(["log", "-z", "--max-count=3", "--date=short", "--format=%H%x00%h%x00%s%x00%an%x00%ad"])
        let entries = CommitEntry.parse(log)
        try check(entries.count == 3 && entries[0].subject == "Local two" && entries[1].subject == "Local one", "structured commit history parses full hashes")
        try check(entries.prefix(2).allSatisfy { pending.ids.contains($0.id) } && !pending.ids.contains(entries[2].id), "only unpublished history entries receive badges")
        _ = try await git(["update-ref", "refs/remotes/origin/unrelated", "HEAD"])
        let targeted = try await PendingPush.read(root.path)
        try check(targeted.ids.count == 2, "comparison uses tracked branch, not unrelated remotes")
        _ = try await git(["remote", "set-url", "--push", "origin", root.appendingPathComponent("missing-remote.git").path])
        let rejected = (try? await git(["push"])) == nil
        let afterFailure = try await PendingPush.read(root.path)
        try check(rejected && afterFailure.ids == pending.ids, "failed push preserves local commits and pending count")
        _ = try await git(["remote", "set-url", "--push", "origin", root.appendingPathComponent("remote.git").path])
        _ = try await git(["push"])
        let afterPush = try await PendingPush.read(root.path)
        try check(afterPush.ids.isEmpty, "retry push clears pending badges")
        try await MainActor.run {
            let suite = "zhixu-test-" + UUID().uuidString
            let preferences = UserDefaults(suiteName: suite)!
            defer { preferences.removePersistentDomain(forName: suite) }
            let model = Workspace(defaults: preferences, restore: false)
            let current = Project(path: root.path)
            let other = Project(path: root.appendingPathComponent("remote.git").path)
            model.projects = [current, other]; model.project = current
            model.files = ["sample.txt"]; model.pendingPushIDs = ["abc"]; model.message = "Draft"
            try check(model.removeProject(other) && model.project == current && model.files == ["sample.txt"], "remove inactive project preserves current workspace")
            model.projects.append(other); model.busy = true
            try check(!model.removeProject(current), "project removal blocked during Git operations")
            model.busy = false
            try check(model.removeProject(current) && model.project == nil && model.projects == [other], "current project can be removed")
            try check(model.files.isEmpty && model.pendingPushIDs.isEmpty && model.message.isEmpty, "remove current project clears stale workspace state")
            try check(preferences.string(forKey: "lastProject") == nil && FileManager.default.fileExists(atPath: root.path), "removal clears persisted selection and preserves repository files")
        }
        let roots = FileNode.tree(["app/controller/Main.php", "app/view/index.html", "README.md"])
        let closedRows = VisibleFileRow.flatten(roots, expanded: [])
        let openRows = VisibleFileRow.flatten(roots, expanded: ["app", "app/view"])
        try check(closedRows.map(\.id) == ["app", "README.md"], "collapsed explorer hides descendants")
        try check(openRows.map(\.id) == ["app", "app/controller", "app/view", "app/view/index.html", "README.md"] && openRows[3].depth == 2, "expanded explorer preserves order and indentation")
        print("All integration checks passed")
    }
}

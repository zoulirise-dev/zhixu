import Foundation

@main struct SelectedCommitIntegration {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-selected-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) async throws -> String { try await Git.run(root.path, args) }
        func write(_ path: String, _ text: String) throws { try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        func check(_ value: Bool, _ name: String) throws { if !value { throw GitFailure.message("FAIL: " + name) }; print("PASS: " + name) }
        func commit(_ paths: Set<String>, staged: Bool = false) async throws {
            let items = Change.parse(try await git(["status", "--porcelain=v1", "-z", "--untracked-files=all"])).filter { paths.contains($0.path) }
            let warning = try await SelectedCommit.run(root: root.path, items: items, message: "selected", stagedOnly: staged)
            try check(warning == nil, "selected index reconciles")
        }
        _ = try await git(["init", "-q"])
        _ = try await git(["config", "user.name", "Test"])
        _ = try await git(["config", "user.email", "test@example.invalid"])
        try write("选择 空格.txt", "first\n"); try write("other.txt", "base\n")
        _ = try await git(["add", "."])
        try await commit(["选择 空格.txt"])
        try check(try await git(["ls-tree", "--name-only", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines) != "other.txt", "initial commit excludes unchecked staged file")
        try check(try await git(["diff", "--cached", "--name-only"]).trimmingCharacters(in: .whitespacesAndNewlines) == "other.txt", "initial commit retains unchecked staging")
        try await commit(["other.txt"])
        try write("other.txt", "base\nstaged\n")
        _ = try await git(["add", "--", "other.txt"])
        try write("other.txt", "base\nstaged\nworking\n")
        let stagedBefore = try await git(["show", ":other.txt"])
        try write("选择 空格.txt", "changed\n")
        try await commit(["选择 空格.txt"])
        try check(try await git(["show", "HEAD:other.txt"]) == "base\n", "unchecked staged modification excluded from commit")
        try check(try await git(["show", ":other.txt"]) == stagedBefore, "unchecked partial staging preserved exactly")
        try check(try String(contentsOf: root.appendingPathComponent("other.txt"), encoding: .utf8) == "base\nstaged\nworking\n", "unchecked working file untouched")
        try await commit(["other.txt"], staged: true)
        try check(try await git(["show", "HEAD:other.txt"]) == stagedBefore, "advanced mode commits only selected staged content")
        try check(try await git(["diff", "--name-only"]).contains("other.txt"), "advanced mode leaves unstaged edits")
        try await commit(["other.txt"])
        try check(try await git(["show", "HEAD:other.txt"]) == "base\nstaged\nworking\n", "simple mode commits latest selected working content")
        _ = try await git(["mv", "--", "选择 空格.txt", "renamed.txt"])
        try await commit(["renamed.txt"])
        let tree = try await git(["ls-tree", "--name-only", "HEAD"])
        try check(tree.contains("renamed.txt") && !tree.contains("选择"), "rename includes both paths")
        try FileManager.default.removeItem(at: root.appendingPathComponent("renamed.txt"))
        try await commit(["renamed.txt"])
        try check(!(try await git(["ls-tree", "--name-only", "HEAD"])).contains("renamed.txt"), "selected deletion commits correctly")
        try write("new.txt", "new\n"); try await commit(["new.txt"])
        try check(try await git(["show", "HEAD:new.txt"]) == "new\n", "untracked selected file commits without manual staging")
        try write("advanced-new.txt", "staged new\n")
        _ = try await git(["add", "--", "advanced-new.txt"])
        try await commit(["advanced-new.txt"], staged: true)
        try check(try await git(["show", "HEAD:advanced-new.txt"]) == "staged new\n", "advanced mode supports staged additions")
        _ = try await git(["mv", "--", "advanced-new.txt", "advanced-renamed.txt"])
        try await commit(["advanced-renamed.txt"], staged: true)
        _ = try await git(["rm", "--", "advanced-renamed.txt"])
        try await commit(["advanced-renamed.txt"], staged: true)
        try check(!(try await git(["ls-tree", "--name-only", "HEAD"])).contains("advanced-"), "advanced mode supports staged renames and deletions")
        let copy = Change(path: "copy.txt", original: "other.txt", index: "C", work: " ")
        try check(copy.paths == ["copy.txt"], "copy selection never includes source file")
        try write("new.txt", "staged\n"); _ = try await git(["add", "--", "new.txt"])
        try write("new.txt", "working\n")
        let indexBefore = try await git(["ls-files", "--stage", "-z"])
        let headBefore = try await git(["rev-parse", "HEAD"])
        let hook = root.appendingPathComponent(".git/hooks/pre-commit")
        try "#!/bin/sh\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        do { try await commit(["new.txt"]); throw GitFailure.message("FAIL: hook should reject commit") }
        catch { try check(try await git(["rev-parse", "HEAD"]) == headBefore, "rejected commit preserves HEAD") }
        try check(try await git(["ls-files", "--stage", "-z"]) == indexBefore, "rejected commit preserves real index exactly")
        try check(try String(contentsOf: root.appendingPathComponent("new.txt"), encoding: .utf8) == "working\n", "rejected commit preserves working content")
        print("All selected commit checks passed")
    }
}

import Foundation

@main struct LocalHistoryIntegration {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-history-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.path
        func git(_ args: [String]) async throws -> String { try await Git.run(root, args).trimmingCharacters(in: .whitespacesAndNewlines) }
        func write(_ text: String) throws { try text.write(to: directory.appendingPathComponent("demo.txt"), atomically: true, encoding: .utf8) }
        func check(_ value: Bool, _ message: String) throws { if !value { throw GitFailure.message("FAIL: " + message) }; print("PASS: " + message) }
        _ = try await git(["init", "-b", "main"])
        _ = try await git(["config", "user.name", "History Test"])
        _ = try await git(["config", "user.email", "test@example.invalid"])
        try write("initial\n")
        _ = try await git(["add", "."]); _ = try await git(["commit", "-m", "initial"])
        let first = try await git(["rev-parse", "HEAD"])
        try write("committed\n")
        _ = try await git(["add", "."]); _ = try await git(["commit", "-m", "second"])
        let second = try await git(["rev-parse", "HEAD"])
        let tree = try await git(["rev-parse", "HEAD^{tree}"])
        try write("staged only\n"); _ = try await git(["add", "."])
        try write("working only\n")
        let indexBefore = try await git(["write-tree"])
        try await LocalCommitHistory.amendMessage(root: root, oid: second, message: "新说明\n\n完整正文")
        let amended = try await git(["rev-parse", "HEAD"])
        try check(try await git(["rev-parse", "HEAD^{tree}"]) == tree, "amending message never includes staged files")
        try check(try await git(["write-tree"]) == indexBefore, "amending preserves index")
        try check(try await git(["show", "-s", "--format=%B", "HEAD"]) == "新说明\n\n完整正文", "multiline message saved")
        do { try await LocalCommitHistory.undo(root: root, oid: second); throw GitFailure.message("stale operation accepted") }
        catch { try check(error.localizedDescription.contains("当前提交已变化"), "stale history rejected") }
        _ = try await git(["update-ref", "refs/remotes/origin/main", amended])
        do { try await LocalCommitHistory.undo(root: root, oid: amended); throw GitFailure.message("remote operation accepted") }
        catch { try check(error.localizedDescription.contains("远程分支"), "published commit rejected") }
        _ = try await git(["update-ref", "-d", "refs/remotes/origin/main"])
        try await LocalCommitHistory.undo(root: root, oid: amended)
        try check(try await git(["rev-parse", "HEAD"]) == first, "undo returns to previous commit")
        try check(try await git(["write-tree"]) == indexBefore, "undo preserves independently staged version")
        try check(try String(contentsOf: directory.appendingPathComponent("demo.txt"), encoding: .utf8) == "working only\n", "undo preserves working contents")
        try check(try await git(["rev-parse", "ORIG_HEAD"]) == amended, "previous commit remains recoverable")
        try await LocalCommitHistory.undo(root: root, oid: first)
        try check((try? await git(["rev-parse", "--verify", "HEAD"])) == nil, "initial commit can be undone")
        try check(try await git(["write-tree"]) == indexBefore, "initial undo also preserves staged contents")
        print("All local history checks passed")
    }
}

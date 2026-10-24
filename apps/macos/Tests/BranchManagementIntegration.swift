import Foundation
@main struct BranchManagementIntegration {
    static func main() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-branches-" + UUID().uuidString)
        let work = base.appendingPathComponent("work"), remote = base.appendingPathComponent("remote.git")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        func git(_ args: [String]) async throws -> String { try await Git.run(work.path, args).trimmingCharacters(in: .whitespacesAndNewlines) }
        func check(_ ok: Bool, _ name: String) throws { guard ok else { throw GitFailure.message("FAIL: " + name) }; print("PASS: " + name) }
        func plan(_ name: String, remote: Bool = false) async throws -> BranchMutation { try await BranchMutation.prepare(root: work.path, branch: Branch(name: name, remote: remote)) }
        _ = try await Git.run(remote.path, ["init", "--bare"])
        _ = try await git(["init", "-b", "main"])
        _ = try await git(["config", "user.name", "Test"]); _ = try await git(["config", "user.email", "test@example.invalid"])
        try "base".write(to: work.appendingPathComponent("file"), atomically: true, encoding: .utf8)
        _ = try await git(["add", "."]); _ = try await git(["commit", "-m", "base"])
        let current = try await plan("main")
        do { try await current.apply(root: work.path, newName: nil); throw GitFailure.message("accepted current delete") }
        catch { try check(error.localizedDescription.contains("不能删除当前"), "current local branch cannot be deleted") }
        try await current.apply(root: work.path, newName: "primary")
        try check(try await git(["branch", "--show-current"]) == "primary", "current local branch can be renamed")
        _ = try await git(["branch", "merged"])
        try await plan("merged").apply(root: work.path, newName: nil)
        try check((try? await git(["rev-parse", "--verify", "refs/heads/merged"])) == nil, "merged local branch deleted")
        _ = try await git(["switch", "-c", "unique"])
        _ = try await git(["commit", "--allow-empty", "-m", "unique"])
        _ = try await git(["switch", "primary"])
        do { try await plan("unique").apply(root: work.path, newName: nil); throw GitFailure.message("deleted unique") }
        catch { try check(error.localizedDescription.contains("未合并"), "unmerged local commits are protected") }
        _ = try await git(["remote", "add", "origin", remote.path])
        _ = try await git(["push", "-u", "origin", "primary:feature"])
        let original = try await plan("origin/feature", remote: true)
        do { try await original.apply(root: work.path, newName: nil); throw GitFailure.message("deleted current upstream") }
        catch { try check(error.localizedDescription.contains("不能删除当前"), "current upstream cannot be deleted") }
        try await original.apply(root: work.path, newName: "renamed/topic")
        try check(try await git(["rev-parse", "--abbrev-ref", "@{upstream}"]) == "origin/renamed/topic", "remote rename updates local upstream")
        try check(try await git(["ls-remote", "--heads", "origin", "refs/heads/feature"]).isEmpty, "remote old name removed")
        try check(!(try await git(["ls-remote", "--heads", "origin", "refs/heads/renamed/topic"])).isEmpty, "remote new name created")
        _ = try await git(["push", "origin", "primary:existing"])
        do { try await plan("origin/renamed/topic", remote: true).apply(root: work.path, newName: "existing"); throw GitFailure.message("overwrote existing") }
        catch { try check(error.localizedDescription.contains("远程操作未完成"), "existing remote destination rejected atomically") }
        try check(!(try await git(["ls-remote", "--heads", "origin", "refs/heads/renamed/topic"])).isEmpty, "failed rename retains old branch")
        _ = try await git(["branch", "--unset-upstream"])
        try await plan("origin/renamed/topic", remote: true).apply(root: work.path, newName: nil)
        try check(try await git(["ls-remote", "--heads", "origin", "refs/heads/renamed/topic"]).isEmpty, "noncurrent remote branch deleted")
        let stale = try await plan("origin/existing", remote: true)
        _ = try await Git.run(remote.path, ["fetch", work.path, "unique"])
        _ = try await Git.run(remote.path, ["update-ref", "refs/heads/existing", try await git(["rev-parse", "unique"])])
        do { try await stale.apply(root: work.path, newName: nil); throw GitFailure.message("deleted changed remote") }
        catch { try check(error.localizedDescription.contains("远程操作未完成"), "lease protects remote commits changed since confirmation") }
        print("All branch management checks passed")
    }
}

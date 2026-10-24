import Foundation
@main struct BranchListIntegration {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-branch-list-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) async throws -> String { try await Git.run(root.path, args).trimmingCharacters(in: .whitespacesAndNewlines) }
        func check(_ ok: Bool, _ title: String) throws { guard ok else { throw GitFailure.message(title) }; print("PASS: " + title) }
        _ = try await git(["init", "-b", "main"])
        _ = try await git(["config", "user.name", "Test"]); _ = try await git(["config", "user.email", "test@example.invalid"])
        _ = try await Git.run(root.path, ["commit", "--allow-empty", "-m", "older"], environment: ["GIT_AUTHOR_DATE": "2025-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2025-01-01T00:00:00Z"])
        let older = try await git(["rev-parse", "HEAD"])
        _ = try await Git.run(root.path, ["commit", "--allow-empty", "-m", "newer"], environment: ["GIT_AUTHOR_DATE": "2025-02-01T00:00:00Z", "GIT_COMMITTER_DATE": "2025-02-01T00:00:00Z"])
        let newer = try await git(["rev-parse", "HEAD"])
        _ = try await git(["branch", "feature/local", older])
        _ = try await git(["update-ref", "refs/remotes/中文远程/main", older])
        _ = try await git(["symbolic-ref", "refs/remotes/中文远程/HEAD", "refs/remotes/中文远程/main"])
        var branches = try await Branch.read(root.path, current: "main")
        try check(branches.filter(\.remote).map(\.name) == ["中文远程/main"], "remote HEAD pointer is excluded even when Git shortens its name")
        try check(branches.contains { $0.name == "feature/local" && !$0.remote }, "slash in local branch name does not make it remote")
        var updates = "update refs/remotes/中文远程/newest \(newer)\n"
        for number in 0..<125 { updates += "update refs/remotes/中文远程/branch-\(number) \(older)\n" }
        _ = try await Git.run(root.path, ["update-ref", "--stdin"], input: updates)
        branches = try await Branch.read(root.path, current: "main")
        let remotes = branches.filter(\.remote)
        try check(remotes.count == 127 && Set(remotes.map(\.id)).count == 127, "all remote branches remain available for paging and search")
        try check(remotes.first?.name == "中文远程/newest", "remote branches sort by latest commit timestamp descending")
        try check(branches.first?.name == "main" && branches.first?.remote == false, "current local branch stays first")
    }
}

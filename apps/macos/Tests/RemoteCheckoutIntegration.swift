import Foundation
@main struct RemoteCheckoutIntegration {
    @MainActor static func main() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-checkout-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let remote = base.appendingPathComponent("remote.git").path, root = base.appendingPathComponent("repo").path
        func git(_ args: [String]) async throws -> String { try await Git.run(root, args) }
        func check(_ value: Bool, _ title: String) throws { guard value else { throw GitFailure.message(title) }; print("PASS: " + title) }
        _ = try await Git.run(base.path, ["init", "--bare", "-b", "main", remote])
        _ = try await Git.run(base.path, ["clone", remote, root])
        _ = try await git(["config", "user.name", "Test"]); _ = try await git(["config", "user.email", "test@example.invalid"])
        let file = URL(fileURLWithPath: root).appendingPathComponent("version.txt")
        try "main".write(to: file, atomically: true, encoding: .utf8)
        _ = try await git(["add", "."]); _ = try await git(["commit", "-m", "main"])
        for version in ["1.0.3", "1.0.6"] {
            _ = try await git(["switch", "-c", version, "main"])
            try version.write(to: file, atomically: true, encoding: .utf8)
            _ = try await git(["commit", "-am", version]); _ = try await git(["push", "-u", "origin", version])
        }
        let suite = "zhixu-checkout-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = Workspace(defaults: defaults, restore: false); try await model.open(root)
        _ = try await git(["commit", "--allow-empty", "-m", "local only"])
        let localHead = try await git(["rev-parse", "HEAD"])
        for _ in 0..<2 {
            try await model.switchBranch(Branch(name: "origin/1.0.3", remote: true))
            try check(model.branch == "1.0.3", "remote 1.0.3 reuses local tracking branch")
            try await model.switchBranch(Branch(name: "origin/1.0.6", remote: true))
            let after = try await git(["rev-parse", "HEAD"])
            try check(model.branch == "1.0.6" && after == localHead, "remote 1.0.6 round-trip preserves unpublished commit")
        }
        _ = try await git(["branch", "-m", "renamed"])
        try await model.switchBranch(Branch(name: "main", remote: false))
        try await model.switchBranch(Branch(name: "origin/1.0.6", remote: true))
        try check(model.branch == "renamed", "renamed tracking branch is reused")
        _ = try await git(["remote", "add", "mirror", remote]); _ = try await git(["fetch", "mirror"])
        _ = try await git(["branch", "1.0.6", "renamed"])
        try await model.switchBranch(Branch(name: "mirror/1.0.6", remote: true))
        let mirrorUpstream = try await git(["rev-parse", "--abbrev-ref", "@{upstream}"])
        try check(model.branch == "mirror-1.0.6" && mirrorUpstream.trimmingCharacters(in: .whitespacesAndNewlines) == "mirror/1.0.6", "same-name unrelated local branch is preserved using distinct tracking name")
        let preserved = try await git(["rev-parse", "refs/heads/1.0.6"])
        try check(preserved == localHead, "same-name local commits are untouched")
        try "working change".write(to: file, atomically: true, encoding: .utf8)
        try await model.switchBranch(Branch(name: "origin/1.0.3", remote: true))
        try check(model.branchSwitchPrompt != nil, "reused tracking branch still offers dirty-switch choices")
        try await model.applyBranchSwitch(model.branchSwitchPrompt!, choice: .stash)
        try check(model.branch == "1.0.3" && model.changes.isEmpty, "stash choice uses resolved existing branch")
    }
}

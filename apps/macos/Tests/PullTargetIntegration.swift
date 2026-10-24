import Foundation
@main struct PullTargetIntegration {
    @MainActor static func main() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-pull-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let a = base.appendingPathComponent("a.git").path, b = base.appendingPathComponent("b.git").path
        let root = base.appendingPathComponent("local").path, other = base.appendingPathComponent("other").path
        func git(_ path: String, _ args: [String]) async throws -> String { try await Git.run(path, args) }
        func check(_ condition: Bool, _ title: String) throws { if !condition { throw GitFailure.message(title) }; print("PASS: " + title) }
        _ = try await git(base.path, ["init", "--bare", "-b", "main", a])
        _ = try await git(base.path, ["clone", a, root])
        for key in ["user.name", "user.email"] { _ = try await git(root, ["config", key, "test@example.invalid"]) }
        _ = try await git(root, ["commit", "--allow-empty", "-m", "base"])
        _ = try await git(root, ["push", "-u", "origin", "main"])
        _ = try await git(base.path, ["clone", "--bare", a, b])
        _ = try await git(base.path, ["clone", b, other])
        for key in ["user.name", "user.email"] { _ = try await git(other, ["config", key, "test@example.invalid"]) }
        _ = try await git(other, ["commit", "--allow-empty", "-m", "remote update"])
        _ = try await git(other, ["push"])
        _ = try await git(root, ["remote", "add", "backup", b])
        // Pull must use fetch URL, not push URL, and must not contact other remotes.
        _ = try await git(root, ["remote", "set-url", "--push", "backup", base.appendingPathComponent("missing-push.git").path])
        _ = try await git(root, ["remote", "set-url", "origin", base.appendingPathComponent("missing.git").path])
        let suite = "zhixu-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = Workspace(defaults: defaults, restore: false)
        try await model.open(root)
        func wait() async throws { while model.busy || model.historyRefreshing { try await Task.sleep(nanoseconds: 10_000_000) } }
        let before = try await git(root, ["rev-parse", "HEAD"])
        model.sync("pull"); try await wait()
        try check(model.pullRequest?.targets.count == 2, "multiple remotes offer pull selection")
        let unmodified = try await git(root, ["rev-parse", "HEAD"])
        try check(before == unmodified, "selection does not merge before confirmation")
        model.confirmPull(remote: "backup"); try await wait()
        let after = try await git(root, ["rev-parse", "HEAD"]), expected = try await git(b, ["rev-parse", "HEAD"])
        try check(model.error == nil && model.remoteFailure == nil && after == expected, "selected fetch URL pulls without contacting unavailable origin or push URL")
        let tracked = try await git(root, ["config", "branch.main.remote"])
        try check(tracked.trimmingCharacters(in: .whitespacesAndNewlines) == "origin", "alternate pull preserves tracking")
        model.sync("push"); try await wait()
        try check(model.pushRequest != nil, "multiple remotes offer push selection")
        model.pushRequest = nil
        _ = try await git(root, ["remote", "remove", "backup"])
        _ = try await git(root, ["remote", "set-url", "origin", b])
        model.sync("pull"); try await wait()
        try check(model.pullRequest == nil && model.error == nil, "single remote pulls without selection")
        model.sync("push"); try await wait()
        try check(model.pushRequest == nil && model.error == nil && model.remoteFailure == nil, "single remote pushes without selection")
        let count = model.history.count
        _ = try await git(root, ["commit", "--allow-empty", "-m", "external commit"])
        model.code = "draft"; model.message = "keep message"; model.checked = ["keep.txt"]
        model.refreshHistory()
        try check(!model.busy && model.historyRefreshing, "history refresh does not disable workspace")
        try await wait()
        try check(model.history.count == count + 1 && model.code == "draft" && model.message == "keep message" && model.checked == ["keep.txt"], "history refresh preserves editor, message and selection")
    }
}

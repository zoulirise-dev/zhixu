import Foundation
@main struct GitWorkflowIntegration {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-workflow-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = directory.appendingPathComponent("remote.git"), local = directory.appendingPathComponent("local"), other = directory.appendingPathComponent("other")
        func git(_ root: URL, _ args: [String]) async throws -> String { try await Git.run(root.path, args) }
        func check(_ value: Bool, _ title: String) throws { guard value else { throw GitFailure.message(title) }; print("PASS: " + title) }
        func write(_ root: URL, _ text: String) throws { try text.write(to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8) }
        _ = try await git(directory, ["init", "--bare", "-b", "main", remote.path])
        _ = try await git(directory, ["clone", remote.path, local.path])
        for root in [local] { _ = try await git(root, ["config", "user.name", "Test"]); _ = try await git(root, ["config", "user.email", "test@example.invalid"]) }
        try write(local, "base\n"); _ = try await git(local, ["add", "."]); _ = try await git(local, ["commit", "-m", "base"]); _ = try await git(local, ["push", "-u", "origin", "main"])
        _ = try await git(directory, ["clone", remote.path, other.path])
        _ = try await git(other, ["config", "user.name", "Other"]); _ = try await git(other, ["config", "user.email", "other@example.invalid"])
        try write(other, "remote change\n"); _ = try await git(other, ["commit", "-am", "remote"]); _ = try await git(other, ["push"])
        try write(local, "local change\n"); _ = try await git(local, ["commit", "-am", "local"])
        let name = "zhixu-workflow-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = Workspace(defaults: defaults, restore: false)
        try await model.open(local.path)
        model.sync("pull")
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.error == nil && model.pendingPullCount == 1 && model.pendingPushIDs.count == 1 && model.toolConfirmation != nil, "pull fetches and offers divergence confirmation")
        model.applyToolConfirmation()
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.error == nil && model.operationKind == "merge" && model.changes.contains(where: \.conflict), "confirmed divergent pull enters conflict workflow")
        try check(!model.canCommit, "ordinary selective commit is disabled during merge")
        model.resolveConflict("file.txt")
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.conflictFile != nil, "conflict editor model loads file")
        model.saveConflict(.text("local and remote\n"))
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.conflictFile == nil && !model.changes.contains(where: \.conflict), "save marks conflict resolved")
        model.continueGitOperation()
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.operationKind == nil && model.pendingPullCount == 0 && model.error == nil, "continue completes pull merge and updates behind count")
        model.prepareRevert(model.history.first!)
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.toolConfirmation != nil, "revert uses explicit confirmation")
        model.toolConfirmation = nil
        model.prepareIgnore(path: "build", kind: .folder)
        model.applyToolConfirmation()
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        let ignore = try String(contentsOf: local.appendingPathComponent(".gitignore"), encoding: .utf8)
        try check(ignore == "/build/\n" && model.changes.contains { $0.path == ".gitignore" }, "ignore confirmation updates working tree and change list")
        _ = try await git(local, ["remote", "set-url", "origin", directory.appendingPathComponent("missing.git").path])
        model.checked = [".gitignore"]; model.message = "retry safety"
        model.commit(pushAfter: true)
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.pushRequest == nil, "single remote commit and push skips selection")
        try check(model.remoteFailure?.arguments.first == "push" && model.error == nil, "commit-and-push failure offers remote recovery")
        let committedHead = try await git(local, ["rev-parse", "HEAD"])
        _ = try await git(local, ["remote", "set-url", "origin", remote.path])
        model.retryRemote()
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        let retriedHead = try await git(local, ["rev-parse", "HEAD"])
        let remoteHead = try await git(remote, ["rev-parse", "refs/heads/main"])
        try check(model.remoteFailure == nil && model.error == nil && committedHead == retriedHead && remoteHead == committedHead, "retry pushes existing commit without committing twice")
    }
}

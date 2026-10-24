import Foundation
@main struct ActivityIntegration {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-activity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.path
        _ = try await Git.run(root, ["init", "-b", "main"])
        _ = try await Git.run(root, ["config", "user.name", "Test"])
        _ = try await Git.run(root, ["config", "user.email", "test@example.invalid"])
        _ = try await Git.run(root, ["commit", "--allow-empty", "-m", "test"])
        _ = try await Git.run(root, ["remote", "add", "origin", directory.appendingPathComponent("remote.git").path])
        let fake = directory.appendingPathComponent("git-delay")
        try "#!/bin/sh\ncase \" $* \" in *' push '*) /bin/sleep 10; exit 0;; *) exec /usr/bin/git \"$@\";; esac\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        let suite = "zhixu-activity-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = Workspace(defaults: defaults, restore: false)
        try await model.open(root)
        await Git.executableContext.withValue(fake.path) {
            model.sync("push")
            for _ in 0..<200 {
                if model.canCancelGit { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        guard model.busy, model.canCancelGit, model.activityTitle == L("推送"), model.activityLabel == L("正在推送到远程仓库…") else { throw GitFailure.message("missing visible push state") }
        model.cancelGitOperation()
        for _ in 0..<300 { if !model.busy { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        guard !model.busy, !model.canCancelGit, model.error == nil else { throw GitFailure.message("cancellation did not clear running state") }
        print("PASS: slow push exposes title, phase, cancellation; cancelling clears activity")
    }
}

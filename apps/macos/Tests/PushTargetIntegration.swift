import Foundation

@main struct PushTargetIntegration {
    static func main() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-push-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("local").path
        let first = base.appendingPathComponent("first.git").path
        let second = base.appendingPathComponent("second.git").path
        for path in [first, second] { _ = try await Git.run(base.path, ["init", "--bare", path]) }
        _ = try await Git.run(base.path, ["init", "-b", "main", root])
        _ = try await Git.run(root, ["config", "user.name", "Test"])
        _ = try await Git.run(root, ["config", "user.email", "test@example.invalid"])
        _ = try await Git.run(root, ["commit", "--allow-empty", "-m", "first"])
        do { _ = try await GitPushPlan.prepare(root); fatalError("missing remote accepted") } catch is GitFailure {}
        _ = try await Git.run(root, ["remote", "add", "官网", first])
        _ = try await Git.run(root, ["remote", "add", "backup", second])
        _ = try await Git.run(root, ["config", "remote.pushDefault", "backup"])
        var plan = try await GitPushPlan.prepare(root)
        precondition(plan.defaultRemote == "backup" && plan.targets.count == 2)
        try await plan.validate(remote: "官网")
        _ = try await Git.run(root, plan.arguments(remote: "官网"))
        let tracking = try await Git.run(root, ["config", "branch.main.remote"])
        precondition(tracking.trimmingCharacters(in: .whitespacesAndNewlines) == "官网")
        let untouched = try? await Git.run(second, ["rev-parse", "--verify", "refs/heads/main"])
        precondition(untouched == nil)
        // A configured remote refspec must not silently push additional branches.
        _ = try await Git.run(root, ["branch", "extra"])
        _ = try await Git.run(root, ["config", "remote.backup.push", "refs/heads/extra:refs/heads/extra"])
        plan = try await GitPushPlan.prepare(root)
        _ = try await Git.run(root, plan.arguments(remote: "backup"))
        let unchanged = try await Git.run(root, ["config", "branch.main.remote"])
        precondition(unchanged == tracking)
        let unwanted = try? await Git.run(second, ["rev-parse", "--verify", "refs/heads/extra"])
        precondition(unwanted == nil)
        let expected = try await Git.run(root, ["rev-parse", "HEAD"])
        let actual = try await Git.run(second, ["rev-parse", "refs/heads/main"])
        precondition(expected == actual)
        _ = try await Git.run(root, ["config", "branch.main.merge", "refs/heads/release"])
        plan = try await GitPushPlan.prepare(root)
        precondition(plan.targets.first { $0.name == "官网" }?.branch == "release")
        precondition(plan.targets.first { $0.name == "backup" }?.branch == "main")
        _ = try await Git.run(root, ["remote", "set-url", "--push", "backup", first])
        do { try await plan.validate(remote: "backup"); fatalError("changed destination accepted") } catch is GitFailure {}
        plan = try await GitPushPlan.prepare(root)
        precondition(plan.targets.first { $0.name == "backup" }?.urls == [first])
        _ = try await Git.run(root, ["switch", "extra"])
        do { try await plan.validate(remote: "backup"); fatalError("changed branch accepted") } catch is GitFailure {}
        print("PASS: selected remote only, default precedence, tracking, explicit refspec, push URL and stale-plan protection")
    }
}

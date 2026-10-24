import Foundation

@main struct SettingsRemoteIntegration {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let globalPath = root + "/test-global-config"
        let previousGlobal = ProcessInfo.processInfo.environment["GIT_CONFIG_GLOBAL"]
        setenv("GIT_CONFIG_GLOBAL", globalPath, 1)
        defer {
            if let previousGlobal { setenv("GIT_CONFIG_GLOBAL", previousGlobal, 1) }
            else { unsetenv("GIT_CONFIG_GLOBAL") }
        }
        try "[user]\nname = Computer Author\nemail = computer@example.invalid\n".write(toFile: globalPath, atomically: true, encoding: .utf8)
        _ = try await Git.run(root, ["init", "-b", "main"])
        let initial = await GitCommitAuthor.read(root)
        precondition(initial.name == "Computer Author" && initial.email == "computer@example.invalid")
        var selected = await GitSettingsRemote.current(root)
        precondition(selected.name == "origin" && selected.url.isEmpty)
        try await GitSettingsRemote.save(root, name: selected.name, url: "  ")
        let empty = try await Git.run(root, ["remote"])
        precondition(empty.isEmpty)
        _ = try await Git.run(root, ["remote", "add", "宠物官网", "https://example.invalid/site.git"])
        selected = await GitSettingsRemote.current(root)
        precondition(selected.name == "宠物官网" && selected.url == "https://example.invalid/site.git")
        _ = try await Git.run(root, ["remote", "add", "origin", "https://example.invalid/origin.git"])
        selected = await GitSettingsRemote.current(root)
        precondition(selected.name == "origin")
        let choices = try await GitSettingsRemote.list(root)
        precondition(choices.count == 2)
        precondition(choices.first { $0.name == "origin" }?.url == "https://example.invalid/origin.git")
        precondition(choices.first { $0.name == "宠物官网" }?.url == "https://example.invalid/site.git")
        _ = try await Git.run(root, ["config", "branch.main.remote", "宠物官网"])
        selected = await GitSettingsRemote.current(root)
        precondition(selected.name == "宠物官网")
        try await GitSettingsRemote.save(root, name: selected.name, url: "https://example.invalid/updated.git")
        try await GitSettingsRemote.save(root, name: selected.name, url: "")
        let updated = await GitSettingsRemote.current(root)
        let origin = try await Git.run(root, ["remote", "get-url", "origin"])
        precondition(updated.url == "https://example.invalid/updated.git")
        precondition(origin.trimmingCharacters(in: .whitespacesAndNewlines) == "https://example.invalid/origin.git")
        try await GitSettingsRemote.add(root, name: "gitee", url: "https://example.invalid/gitee.git")
        let entry = GitSettingsRemote.Entry(name: "gitee", url: "https://example.invalid/gitee.git")
        // Old per-remote presets must not override the effective project identity.
        _ = try await Git.run(root, ["config", "remote.gitee.zhixuauthorname", "Legacy Author"])
        _ = try await Git.run(root, ["config", "remote.gitee.zhixuauthoremail", "legacy@example.invalid"])
        let inherited = await GitCommitAuthor.read(root)
        precondition(inherited.email == "computer@example.invalid")
        _ = try await Git.run(root, ["-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "first"])
        let first = try await Git.run(root, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try await GitCommitAuthor.save(root, name: " Project Author ", email: " project@example.invalid ")
        let reloaded = await GitCommitAuthor.read(root)
        precondition(reloaded.name == "Project Author" && reloaded.email == "project@example.invalid")
        let global = try String(contentsOfFile: globalPath, encoding: .utf8)
        precondition(global.contains("computer@example.invalid") && !global.contains("project@example.invalid"))
        do { try await GitCommitAuthor.save(root, name: "", email: "bad"); preconditionFailure("empty author accepted") } catch {}
        do { try await GitCommitAuthor.save(root, name: "Bad\nName", email: "bad"); preconditionFailure("newline accepted") } catch {}
        _ = try await Git.run(root, ["-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "second"])
        let firstAuthor = try await Git.run(root, ["show", "-s", "--format=%an|%ae", first])
        let secondAuthor = try await Git.run(root, ["show", "-s", "--format=%an|%ae", "HEAD"])
        precondition(firstAuthor.trimmingCharacters(in: .whitespacesAndNewlines) == "Computer Author|computer@example.invalid")
        precondition(secondAuthor.trimmingCharacters(in: .whitespacesAndNewlines) == "Project Author|project@example.invalid")
        _ = try await Git.run(root, ["config", "branch.main.remote", "gitee"])
        try await GitSettingsRemote.rename(root, entry: entry, to: "backup")
        let afterRename = await GitCommitAuthor.read(root)
        precondition(afterRename.email == "project@example.invalid")
        let upstream = try await Git.run(root, ["config", "branch.main.remote"])
        precondition(upstream.trimmingCharacters(in: .whitespacesAndNewlines) == "backup")
        do { try await GitSettingsRemote.remove(root, entry: entry); preconditionFailure("stale entry accepted") } catch {}
        do { try await GitSettingsRemote.add(root, name: "origin", url: "x"); preconditionFailure("duplicate accepted") } catch {}
        do { try await GitSettingsRemote.add(root, name: "bad name", url: "x"); preconditionFailure("invalid name accepted") } catch {}
        try await GitSettingsRemote.remove(root, entry: .init(name: "backup", url: entry.url))
        let afterRemove = await GitCommitAuthor.read(root)
        precondition(afterRemove.email == "project@example.invalid")
        let retained = try await Git.run(root, ["show", "-s", "--format=%an|%ae", "HEAD"])
        precondition(retained == secondAuthor)
        print("Settings remote and author identity tests passed")
    }
}

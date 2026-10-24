import Foundation

@main struct SettingsRemoteIntegration {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        _ = try await Git.run(root, ["init", "-b", "main"])
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
        print("Settings remote tests passed")
    }
}

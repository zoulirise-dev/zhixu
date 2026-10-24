import Foundation

@main struct OpenFolderIntegration {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-open-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "zhixu-open-" + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let model = Workspace(defaults: prefs, restore: false)
        func check(_ condition: Bool, _ title: String) throws {
            guard condition else { throw GitFailure.message(title) }
            print("PASS: " + title)
        }
        let folder = root.appendingPathComponent("中文 项目")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "source".write(to: folder.appendingPathComponent("main.txt"), atomically: true, encoding: .utf8)
        try "secret.txt\n".write(to: folder.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "local fixture".write(to: folder.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        var prompts = 0
        try await model.openFolder(folder.path, confirmInitialization: { _ in prompts += 1; return false })
        try check(prompts == 1 && model.projects.isEmpty && model.project == nil && !FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path), "cancel does not initialize or add project")
        try await model.openFolder(folder.path, confirmInitialization: { _ in prompts += 1; return true })
        try check(model.branch == "main" && model.project != nil && model.changes.contains { $0.path == "main.txt" } && !model.changes.contains { $0.path == "secret.txt" }, "confirmation initializes main and honors existing gitignore")
        let content = try String(contentsOf: folder.appendingPathComponent("main.txt"), encoding: .utf8)
        let secret = try String(contentsOf: folder.appendingPathComponent("secret.txt"), encoding: .utf8)
        let staged = try await Git.run(folder.path, ["diff", "--cached", "--name-only"])
        let remotes = try await Git.run(folder.path, ["remote"])
        let head = try? await Git.run(folder.path, ["rev-parse", "--verify", "HEAD"])
        try check(content == "source" && secret == "local fixture" && staged.isEmpty && remotes.isEmpty && head == nil, "initialization preserves files without staging, committing, or configuring remotes")
        let child = folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try await model.openFolder(child.path, confirmInitialization: { _ in prompts += 1; return true })
        try check(prompts == 2 && !FileManager.default.fileExists(atPath: child.appendingPathComponent(".git").path), "repository subfolder opens parent without nested initialization")
        let previous = model.project
        let broken = root.appendingPathComponent("broken")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try "gitdir: missing-data\n".write(to: broken.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        do { try await model.openFolder(broken.path, confirmInitialization: { _ in prompts += 1; return true }); throw GitFailure.message("broken repo accepted") }
        catch { try check(error.localizedDescription.contains("不会重新初始化"), "damaged repository not offered initialization") }
        let bare = root.appendingPathComponent("bare.git")
        _ = try await Git.run(root.path, ["init", "--bare", bare.path])
        do { try await model.openFolder(bare.path, confirmInitialization: { _ in prompts += 1; return true }); throw GitFailure.message("bare accepted") }
        catch { try check(error.localizedDescription.contains("裸仓库"), "bare repository has actionable message") }
        do { try await model.openFolder(root.appendingPathComponent("missing").path, confirmInitialization: { _ in prompts += 1; return true }); throw GitFailure.message("missing accepted") }
        catch { try check(error.localizedDescription.contains("不存在"), "missing folder not offered initialization") }
        try check(prompts == 2 && model.project == previous, "failed opens preserve current project")
        // Recheck confirmation races without resetting a newly created branch.
        let race = root.appendingPathComponent("race")
        _ = try await Git.run(root.path, ["init", "-b", "feature", race.path])
        try await model.openFolder(race.path, create: true, confirmInitialization: { _ in prompts += 1; return true })
        try check(model.branch == "feature" && prompts == 2, "create flow opens existing repository without resetting its branch")
    }
}

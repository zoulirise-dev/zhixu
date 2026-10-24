import Foundation
@main struct DiscardIntegration {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-discard-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) async throws -> String { try await Git.run(root.path, args) }
        func write(_ path: String, _ text: String) throws { try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        func read(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
        func check(_ ok: Bool, _ name: String) throws { guard ok else { throw GitFailure.message("FAIL: " + name) }; print("PASS: " + name) }
        func plan(_ path: String) async throws -> DiscardFilePlan {
            let changes = Change.parse(try await git(["status", "--porcelain=v1", "-z", "--untracked-files=all"]))
            return try await DiscardFilePlan.prepare(root: root.path, change: changes.first { $0.path == path }!)
        }
        let trash: @Sendable (URL) throws -> Void = { url in
            let destination = root.appendingPathComponent("trash-" + UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
        }
        _ = try await git(["init", "-b", "main"])
        _ = try await git(["config", "user.name", "Test"]); _ = try await git(["config", "user.email", "test@example.invalid"])
        try write("first.txt", "first content")
        _ = try await git(["add", "first.txt"])
        let first = try await plan("first.txt")
        try await first.apply(trash: trash)
        try check((try await git(["ls-files"])).isEmpty && !FileManager.default.fileExists(atPath: root.appendingPathComponent("first.txt").path), "unborn staged addition removed from index and retained by trash handler")
        try write("file.txt", "base"); try write("other.txt", "other")
        _ = try await git(["add", "file.txt", "other.txt"]); _ = try await git(["commit", "-m", "base"])
        try write("file.txt", "staged"); _ = try await git(["add", "file.txt"])
        try write("file.txt", "working"); try write("other.txt", "untouched changes")
        try await plan("file.txt").apply(trash: trash)
        let index = try await git(["show", ":file.txt"])
        try check(try read("file.txt") == "base" && index == "base", "tracked staged and unstaged contents restored to HEAD")
        try check(try read("other.txt") == "untouched changes", "unrelated changes preserved")
        try FileManager.default.removeItem(at: root.appendingPathComponent("file.txt"))
        try await plan("file.txt").apply(trash: trash)
        try check(try read("file.txt") == "base", "deleted tracked file restored")
        _ = try await git(["mv", "file.txt", "renamed.txt"])
        let renamed = try await plan("renamed.txt")
        try await renamed.apply(trash: trash)
        try check(try read("file.txt") == "base" && !FileManager.default.fileExists(atPath: root.appendingPathComponent("renamed.txt").path), "rename restores original path without touching unrelated files")
        try write("new.txt", "new content")
        try await plan("new.txt").apply(trash: trash)
        let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("trash-") }
        try check(try backups.contains { try String(contentsOf: $0, encoding: .utf8) == "new content" }, "untracked content retained instead of permanently deleted")
        try write("file.txt", "before dialog")
        let stale = try await plan("file.txt")
        try write("file.txt", "changed after dialog")
        do { try await stale.apply(trash: trash); throw GitFailure.message("accepted stale plan") }
        catch { try check(error.localizedDescription.contains("确认期间"), "concurrent edits block discard") }
        try check(try read("file.txt") == "changed after dialog", "concurrent edits preserved")
        let changes = Change.parse(try await git(["status", "--porcelain=v1", "-z", "--untracked-files=all"]))
        let batch = try await DiscardChangesPlan.prepare(root: root.path, changes: changes, all: true)
        try write("appeared.txt", "new during confirmation")
        do { try await batch.validate(); throw GitFailure.message("accepted changed list") }
        catch { try check(error.localizedDescription.contains("变更列表已变化"), "batch rejects newly appearing changes before discarding any files") }
        try check(try read("file.txt") == "changed after dialog", "batch preflight preserves earlier files")
        try FileManager.default.removeItem(at: root.appendingPathComponent("appeared.txt"))
        try await batch.validate()
        // Store test trash outside the repository so it does not become another change.
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-trash-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        for file in batch.files {
            try await file.apply(trash: { url in try FileManager.default.moveItem(at: url, to: outside.appendingPathComponent(UUID().uuidString)) })
        }
        try check((try await git(["status", "--porcelain=v1"])).isEmpty, "batch restores all tracked changes and trashes all new files")

    }
}

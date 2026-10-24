import Foundation

@main struct StashRestoreIntegration {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-stash-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) async throws -> String { try await Git.run(root.path, args) }
        func write(_ path: String, _ text: String) throws { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
        func read(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
        func check(_ condition: Bool, _ label: String) throws { guard condition else { throw GitFailure.message("FAIL: " + label) }; print("PASS: " + label) }
        _ = try await git(["init", "-q"])
        _ = try await git(["config", "user.name", "Test"])
        _ = try await git(["config", "user.email", "test@example.invalid"])
        try write("tracked.txt", "base")
        _ = try await git(["add", "."]); _ = try await git(["commit", "-qm", "base"])
        try write("tracked.txt", "restored tracked")
        for path in ["same.txt", "keep.txt", "replace.txt", "missing.txt", "中文 空格.txt"] { try write(path, "backup " + path) }
        let binary = Data([0, 255, 128, 1, 10, 0])
        try binary.write(to: root.appendingPathComponent("binary.dat"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: "same.txt")
        _ = try await git(["stash", "push", "-u"])
        for path in ["missing.txt", "link", "中文 空格.txt"] {
            if (try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(path).path)) != nil { try FileManager.default.removeItem(at: root.appendingPathComponent(path)) }
        }
        let oid = try await git(["rev-parse", "refs/stash"])
        try write("same.txt", "backup same.txt")
        try write("keep.txt", "keep current")
        try write("replace.txt", "replace current")
        try binary.write(to: root.appendingPathComponent("binary.dat"))
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("missing.txt").path), "missing-file fixture starts absent")
        let plan = try await StashRestore.prepare(root.path)
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("missing.txt").path), "planning never writes missing untracked files")
        defer { plan.cleanup() }
        try check(Set(plan.conflicts.map(\.path)) == ["keep.txt", "replace.txt", "tracked.txt"], "only different existing files require decisions")
        try check(try read("tracked.txt") == "base", "planning never modifies tracked files")
        let result = try await StashRestore.apply(plan, choices: ["keep.txt": .keep, "replace.txt": .backup, "tracked.txt": .backup])
        try check(try read("tracked.txt") == "restored tracked", "tracked modifications restored")
        try check(try read("keep.txt") == "keep current", "keep current preserves chosen content")
        try check(try read("replace.txt") == "backup replace.txt", "restore backup replaces only chosen file")
        try check(try read("missing.txt") == "backup missing.txt" && read("中文 空格.txt") == "backup 中文 空格.txt", "missing and Unicode files restored")
        try check(try Data(contentsOf: root.appendingPathComponent("binary.dat")) == binary && result.contains("相同跳过 2"), "binary and identical files skip without errors")
        try check(try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent("link").path) == "same.txt", "symbolic link restored without dereferencing")
        try check(try await git(["rev-parse", "refs/stash"]) == oid, "original stash backup retained")
        let repeated = try await StashRestore.prepare(root.path)
        defer { repeated.cleanup() }
        _ = try await StashRestore.apply(repeated, choices: ["keep.txt": .keep])
        try check(try read("tracked.txt") == "restored tracked", "repeat restore skips already-applied tracked content")
        let stale = try await StashRestore.prepare(root.path)
        defer { stale.cleanup() }
        try write("replace.txt", "external edit")
        var rejected = false
        do { _ = try await StashRestore.apply(stale, choices: ["keep.txt": .backup]) } catch { rejected = true }
        try check(rejected && read("keep.txt") == "keep current" && read("replace.txt") == "external edit", "changed-after-comparison aborts before writing")
        let cancelled = try await StashRestore.prepare(root.path)
        defer { cancelled.cleanup() }
        rejected = false
        do { _ = try await StashRestore.apply(cancelled, choices: ["keep.txt": .cancel, "replace.txt": .backup]) } catch { rejected = true }
        try check(rejected && read("replace.txt") == "external edit", "cancel performs no writes")
        // A directory cannot be silently replaced with a saved file.
        try FileManager.default.removeItem(at: root.appendingPathComponent("replace.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("replace.txt"), withIntermediateDirectories: true)
        let directoryPlan = try await StashRestore.prepare(root.path)
        defer { directoryPlan.cleanup() }
        try check(directoryPlan.conflicts.first { $0.path == "replace.txt" }?.canReplace == false, "directory collision disables destructive replacement")
        try write("tracked.txt", "local tracked edit")
        let keepTracked = try await StashRestore.prepare(root.path)
        defer { keepTracked.cleanup() }
        _ = try await StashRestore.apply(keepTracked, choices: Dictionary(uniqueKeysWithValues: keepTracked.conflicts.map { ($0.path, .keep) }))
        try check(try read("tracked.txt") == "local tracked edit", "keep current also preserves tracked local modifications")
        try FileManager.default.removeItem(at: root.appendingPathComponent("tracked.txt"))
        _ = try await git(["stash", "push", "-u"])
        let deletion = try await StashRestore.prepare(root.path)
        defer { deletion.cleanup() }
        try check(deletion.entries.first { $0.path == "tracked.txt" }?.backup == .missing, "backup deletion is explicitly represented")
        var deletionChoices = Dictionary(uniqueKeysWithValues: deletion.conflicts.map { ($0.path, StashRestore.Choice.keep) })
        deletionChoices["tracked.txt"] = .backup
        _ = try await StashRestore.apply(deletion, choices: deletionChoices)
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("tracked.txt").path), "explicit backup choice restores deletion")
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("outside").path, withDestinationPath: root.deletingLastPathComponent().path)
        rejected = false
        do { _ = try StashRestore.destination(root.path, "outside/file.txt") } catch { rejected = true }
        try check(rejected, "restore rejects paths through symlink parents")
        print("All stash restoration checks passed")
    }
}

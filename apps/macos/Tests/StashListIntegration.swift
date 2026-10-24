import Foundation
@main struct StashListIntegration {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-stash-list-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) async throws -> String { try await Git.run(root.path, args, literalPaths: args.first != "stash") }
        func write(_ name: String, _ text: String) throws { try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        func check(_ value: Bool, _ message: String) throws { guard value else { throw GitFailure.message(message) }; print("PASS: " + message) }
        _ = try await git(["init", "-b", "main"])
        _ = try await git(["config", "user.name", "Test"]); _ = try await git(["config", "user.email", "test@example.invalid"])
        try check(try await StashRecord.read(root.path).isEmpty, "empty stash list")
        try write("tracked.txt", "base\n")
        _ = try await git(["add", "."]); _ = try await git(["commit", "-m", "base"])
        try write("tracked.txt", "first backup\n"); try write("中文 空格.txt", "first new file\n")
        _ = try await git(["stash", "push", "-u", "-m", "first backup"])
        let original = try await StashRecord.read(root.path)[0]
        _ = try await git(["switch", "-c", "feature/demo"])
        try write("tracked.txt", "second backup\n")
        _ = try await git(["stash", "push", "-u", "-m", "second backup"])
        let records = try await StashRecord.read(root.path)
        try check(records.count == 2 && records[0].branch == "feature/demo" && records[1].branch == "main" && records[1].id == original.id, "all records retain source branch and newest-first ordering")
        try check(records[0].date.timeIntervalSince1970 > 0 && records[0].message == "second backup", "timestamp and message decoded")
        let files = try await original.files(root.path)
        let tracked = files.first { $0.path == "tracked.txt" }!
        let new = files.first { $0.path == "中文 空格.txt" }!
        try check(try await original.preview(root.path, file: tracked).contains("+first backup"), "older tracked preview compares with its own base")
        try check(try await original.preview(root.path, file: new) == "first new file\n" && new.untracked, "preview includes untracked Unicode paths")
        let plan = try await StashRestore.prepare(root.path, oid: original.id)
        defer { plan.cleanup() }
        var choices: [String: StashRestore.Choice] = [:]
        for entry in plan.conflicts { choices[entry.path] = .backup }
        _ = try await StashRestore.apply(plan, choices: choices)
        let restored = try String(contentsOf: root.appendingPathComponent("tracked.txt"), encoding: .utf8)
        try check(restored == "first backup\n", "restores selected old record even after stash index shifts")
        try check(try await StashRecord.read(root.path).count == 2, "restore preserves original records")
        let workBefore = try await git(["diff"])
        let indexBefore = try await git(["ls-files", "--stage"])
        let editedOID = try await original.deletingFile(root.path, file: tracked)
        let editedRecords = try await StashRecord.read(root.path)
        let edited = editedRecords.first { $0.id == editedOID }!
        try check(edited.date == original.date && edited.branch == original.branch, "editing backup retains original time and branch")
        try check(try await edited.files(root.path) == [new], "deleting tracked backup file preserves untracked backup")
        let restoreEdited = try await StashRestore.prepare(root.path, oid: edited.id)
        defer { restoreEdited.cleanup() }
        try check(restoreEdited.entries.map(\.path) == [new.path], "deleted file cannot be restored from updated backup")
        let emptyOID = try await edited.deletingFile(root.path, file: new)
        let emptyRecord = try await StashRecord.read(root.path).first { $0.id == emptyOID }!
        try check(try await emptyRecord.files(root.path).isEmpty, "deleting untracked backup file removes only its snapshot")
        let workAfter = try await git(["diff"])
        let indexAfter = try await git(["ls-files", "--stage"])
        try check(workAfter == workBefore && indexAfter == indexBefore, "editing backup does not change working files or real index")
        try await emptyRecord.delete(root.path)
        let remaining = try await StashRecord.read(root.path)
        try check(remaining.count == 1 && remaining[0].id == records[0].id, "deleting whole backup preserves other records despite shifted indexes")
        do { _ = try await StashRestore.prepare(root.path, oid: original.id); throw GitFailure.message("accepted deleted record") }
        catch { try check(error.localizedDescription.contains("已不存在"), "deleted selection is rejected rather than restoring another record") }
    }
}

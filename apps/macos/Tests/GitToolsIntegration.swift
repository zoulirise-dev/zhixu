import Foundation
@main struct GitToolsIntegration {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-tools-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) async throws -> String { try await Git.run(root.path, args, literalPaths: args.first != "check-ignore") }
        func write(_ path: String, _ value: String) throws { try value.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        func read(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
        func check(_ value: Bool, _ title: String) throws { guard value else { throw GitFailure.message("FAIL: " + title) }; print("PASS: " + title) }
        _ = try await git(["init", "-b", "main"])
        _ = try await git(["config", "user.name", "Test"]); _ = try await git(["config", "user.email", "test@example.invalid"])
        try write("a.txt", "base\n"); try write("b.txt", "base b\n")
        _ = try await git(["add", "."]); _ = try await git(["commit", "-m", "initial"])
        let initial = try await GitTools.oid(root.path, "HEAD")
        let first = try await GitTools.commitReview(root.path, ref: initial)
        try check(first.files.count == 2 && first.files.allSatisfy { $0.status == "A" }, "root commit details compare against empty tree")
        let firstPatch = try await GitTools.patch(root.path, review: first, path: "a.txt")
        try check(firstPatch.contains("+base"), "commit details include per-file diff")
        _ = try await git(["switch", "-c", "feature"])
        try write("a.txt", "feature\n"); try write("b.txt", "feature b\n")
        _ = try await git(["commit", "-am", "feature change"])
        let feature = try await GitTools.oid(root.path, "HEAD")
        _ = try await git(["switch", "main"])
        try write("a.txt", "main\n"); try write("b.txt", "main b\n")
        _ = try await git(["commit", "-am", "main change"])
        let main = try await GitTools.oid(root.path, "HEAD")
        let comparison = try await GitTools.compare(root.path, ref: "refs/heads/feature")
        try check(comparison.currentOnly.count == 1 && comparison.commits.count == 1 && comparison.files.count == 2, "branch comparison shows both unique commit sets and changed files")
        _ = try await git(["remote", "add", "origin", root.path])
        _ = try await git(["update-ref", "refs/remotes/origin/main", feature])
        _ = try await git(["config", "branch.main.remote", "origin"]); _ = try await git(["config", "branch.main.merge", "refs/heads/main"])
        let pending = try await PendingPush.read(root.path)
        try check(pending.ids.count == 1 && pending.behind == 1, "ahead and behind detect divergent branches")
        do { try await GitTools.integrate(root.path, ref: feature, expectedHead: initial); throw GitFailure.message("stale accepted") }
        catch { try check(error.localizedDescription.contains("当前分支已变化"), "merge rejects stale head confirmation") }
        do { try await GitTools.integrate(root.path, ref: feature, expectedHead: main); throw GitFailure.message("conflict expected") }
        catch { try check(try await GitTools.operation(root.path) == "merge", "merge conflict retains operation state") }
        let conflict = try await GitConflict.read(root.path, path: "a.txt")
        try check(GitConflict.text(conflict.ours) == "main\n" && GitConflict.text(conflict.theirs) == "feature\n", "conflict sides come from unmerged index stages")
        var result = GitConflict.text(conflict.current)!
        let blocks = ConflictBlock.parse(result)
        try check(blocks.count == 1, "conflict block parser detects normal markers")
        result = blocks[0].replacing(in: result, choice: 2)
        try await conflict.save(.text(result))
        try check(try read("a.txt") == "main\nfeature\n", "per-block keep-both saves merged result")
        do { try await GitTools.continueOperation(root.path); throw GitFailure.message("unresolved continue") }
        catch { try check(error.localizedDescription.contains("未解决"), "continue refuses remaining conflicts") }
        let b = try await GitConflict.read(root.path, path: "b.txt")
        try await b.save(.theirs)
        try await GitTools.continueOperation(root.path)
        try check(try await GitTools.operation(root.path) == nil, "all resolved files allow merge continuation")
        let merged = try await GitTools.oid(root.path, "HEAD")
        let parents = try await git(["show", "-s", "--format=%P", merged])
        try check(parents.split(whereSeparator: \.isWhitespace).count == 2, "merge creates proper two-parent commit")
        let history = try await GitTools.fileHistory(root.path, path: "a.txt", page: 0)
        try check(history.count >= 3, "file history lists relevant commits")
        let restoration = try await GitTools.FileRestore.prepare(root.path, path: "a.txt", ref: initial)
        let indexBefore = try await git(["show", ":a.txt"])
        try await restoration.apply()
        let indexAfter = try await git(["show", ":a.txt"])
        try check(try read("a.txt") == "base\n" && indexBefore == indexAfter, "historical file restore modifies worktree only")
        let staleRestore = try await GitTools.FileRestore.prepare(root.path, path: "a.txt", ref: initial)
        try write("a.txt", "new local\n")
        do { try await staleRestore.apply(); throw GitFailure.message("stale restore accepted") }
        catch { try check(error.localizedDescription.contains("已变化"), "historical restore preserves concurrent edits") }
        _ = try await git(["restore", "--worktree", "a.txt"])
        try await GitTools.integrate(root.path, ref: merged, expectedHead: merged, revert: true)
        try check(try read("a.txt") == "main\n" && read("b.txt") == "main b\n", "revert merge uses first parent and restores previous content")
        let reverted = try await GitTools.oid(root.path, "HEAD")
        let reverseParent = try await GitTools.oid(root.path, "HEAD^1")
        try check(reverted != merged && reverseParent == merged, "revert appends commit without rewriting shared history")
        _ = try await git(["switch", "-c", "abort-source", initial])
        try write("a.txt", "incoming abort\n")
        _ = try await git(["commit", "-am", "abort source"])
        _ = try await git(["switch", "main"])
        do { try await GitTools.integrate(root.path, ref: "abort-source", expectedHead: reverted) } catch { }
        try await GitTools.abortOperation(root.path, expected: "merge")
        try check(try await GitTools.oid(root.path, "HEAD") == reverted, "abort merge returns to original head")
        try check(try read("a.txt") == "main\n", "abort merge restores original worktree")
        try GitTools.ignore(root.path, path: "odd [1].log", kind: .file)
        try GitTools.ignore(root.path, path: "build folder", kind: .folder)
        try GitTools.ignore(root.path, path: "other.tmp", kind: .suffix)
        try write("odd [1].log", "ignore me")
        try write("another.tmp", "ignore me")
        let ignored = try await git(["check-ignore", "--", "odd [1].log", "another.tmp", "build folder/x"])
        try check(ignored.contains("odd [1].log") && ignored.contains("another.tmp") && ignored.contains("build folder/x"), "ignore file/folder/extension rules escape special characters")
        let ignoreBefore = try read(".gitignore")
        try GitTools.ignore(root.path, path: "other.tmp", kind: .suffix)
        try check(try read(".gitignore") == ignoreBefore, "ignore rules are not duplicated")
        let diff3 = "before\n<<<<<<< ours\none\n||||||| base\nbase\n=======\ntwo\n>>>>>>> theirs\nafter\n"
        let block = ConflictBlock.parse(diff3)[0]
        try check(block.replacing(in: diff3, choice: 1) == "before\ntwo\nafter\n", "conflict parser handles diff3 base section and trailing newline")

        let edge = root.appendingPathComponent("edge-tests")
        try FileManager.default.createDirectory(at: edge, withIntermediateDirectories: true)
        func eg(_ args: [String]) async throws -> String { try await Git.run(edge.path, args) }
        func ew(_ path: String, _ value: String) throws { try value.write(to: edge.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        _ = try await eg(["init", "-b", "main"])
        _ = try await eg(["config", "user.name", "Test"]); _ = try await eg(["config", "user.email", "test@example.invalid"])
        try ew("old.txt", "original\n")
        _ = try await eg(["add", "."]); _ = try await eg(["commit", "-m", "base"])
        let original = try await GitTools.oid(edge.path, "HEAD")
        _ = try await eg(["mv", "old.txt", "renamed.txt"]); _ = try await eg(["commit", "-m", "rename"])
        let renamedHistory = try await GitTools.fileHistory(edge.path, path: "renamed.txt", page: 0)
        try check(renamedHistory.count == 2 && renamedHistory.last?.historicalPath == "old.txt", "file history follows renames and remembers historical path")
        try ew("renamed.txt", "local edit\n")
        let renameRestore = try await GitTools.FileRestore.prepare(edge.path, path: "renamed.txt", ref: original, sourcePath: "old.txt")
        try await renameRestore.apply()
        try check(try String(contentsOf: edge.appendingPathComponent("renamed.txt"), encoding: .utf8) == "original\n" && !FileManager.default.fileExists(atPath: edge.appendingPathComponent("old.txt").path), "renamed file restores old content under current name")
        _ = try await eg(["switch", "-c", "delete-file"])
        _ = try await eg(["rm", "renamed.txt"]); _ = try await eg(["commit", "-m", "delete"])
        _ = try await eg(["switch", "main"])
        try ew("renamed.txt", "main changed\n"); _ = try await eg(["commit", "-am", "modify"])
        let beforeDelete = try await GitTools.oid(edge.path, "HEAD")
        do { try await GitTools.integrate(edge.path, ref: "delete-file", expectedHead: beforeDelete) } catch { }
        let deleteConflict = try await GitConflict.read(edge.path, path: "renamed.txt")
        try check(deleteConflict.theirs == .missing, "modify/delete conflict identifies deleted side")
        try ew("renamed.txt", "concurrent edit\n")
        do { try await deleteConflict.save(.theirs); throw GitFailure.message("stale conflict accepted") }
        catch { try check(error.localizedDescription.contains("已变化"), "conflict resolution refuses concurrent file edits") }
        try await GitConflict.read(edge.path, path: "renamed.txt").save(.theirs)
        try await GitTools.continueOperation(edge.path)
        try check(!FileManager.default.fileExists(atPath: edge.appendingPathComponent("renamed.txt").path), "choosing deleted side removes file and completes merge")
        _ = try await eg(["switch", "-c", "rebase-target", original])
        try ew("old.txt", "target rebase\n"); _ = try await eg(["commit", "-am", "target"])
        _ = try await eg(["switch", "-c", "rebase-source", original])
        try ew("old.txt", "source rebase\n"); _ = try await eg(["commit", "-am", "source"])
        do { _ = try await eg(["rebase", "rebase-target"]) } catch { }
        try check(try await GitTools.operation(edge.path) == "rebase", "existing rebase operation detected")
        try await GitConflict.read(edge.path, path: "old.txt").save(.text("combined rebase\n"))
        try await GitTools.continueOperation(edge.path)
        try check(try await GitTools.operation(edge.path) == nil, "rebase can continue after conflict resolution")
        try Data([0, 1, 2]).write(to: edge.appendingPathComponent("binary.dat"))
        _ = try await eg(["add", "."]); _ = try await eg(["commit", "-m", "binary base"])
        let binaryBase = try await GitTools.oid(edge.path, "HEAD")
        _ = try await eg(["switch", "-c", "binary-target"])
        try Data([0, 7, 8]).write(to: edge.appendingPathComponent("binary.dat"))
        _ = try await eg(["commit", "-am", "binary target"])
        _ = try await eg(["switch", "-c", "binary-source", binaryBase])
        try Data([0, 3, 4]).write(to: edge.appendingPathComponent("binary.dat"))
        _ = try await eg(["commit", "-am", "binary source"])
        let binaryHead = try await GitTools.oid(edge.path, "HEAD")
        do { try await GitTools.integrate(edge.path, ref: "binary-target", expectedHead: binaryHead) } catch { }
        let binaryConflict = try await GitConflict.read(edge.path, path: "binary.dat")
        try check(GitConflict.text(binaryConflict.theirs) == nil, "binary conflict does not decode as editable text")
        try await binaryConflict.save(.theirs)
        try check(try Data(contentsOf: edge.appendingPathComponent("binary.dat")) == Data([0, 7, 8]), "binary resolution preserves exact bytes")
        try await GitTools.continueOperation(edge.path)
    }
}

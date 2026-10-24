import Foundation

@main struct BranchSwitchIntegration {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-switch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ args: [String]) async throws -> String { try await Git.run(root.path, args) }
        func write(_ name: String, _ content: String) throws { try content.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        func read(_ name: String) throws -> String { try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }
        func check(_ value: Bool, _ title: String) throws { if !value { throw GitFailure.message(title) }; print("PASS: " + title) }
        _ = try await git(["init", "-b", "main"])
        _ = try await git(["config", "user.name", "Test"]); _ = try await git(["config", "user.email", "test@example.invalid"])
        let key = "zhixu-switch-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: key)!
        defer { defaults.removePersistentDomain(forName: key) }
        let model = Workspace(defaults: defaults, restore: false)
        try await model.open(root.path)
        try check(model.branch == "main" && model.branches.contains { $0.name == "main" && !$0.remote && $0.unborn }, "current branch remains visible before its first commit")
        try check(!model.canDeleteBranch(Branch(name: "main", remote: false, unborn: true)), "unborn current branch cannot be deleted")
        try write("draft.txt", "staged\n")
        _ = try await git(["add", "draft.txt"])
        try write("draft.txt", "staged\nworking\n")
        let unborn = try await BranchMutation.prepare(root: root.path, branch: Branch(name: "main", remote: false, unborn: true))
        try await unborn.apply(root: root.path, newName: "renamed")
        let renamedHead = try await git(["symbolic-ref", "--short", "HEAD"])
        let draftIndex = try await git(["show", ":draft.txt"])
        try check(renamedHead.trimmingCharacters(in: .whitespacesAndNewlines) == "renamed" && draftIndex == "staged\n" && read("draft.txt") == "staged\nworking\n", "unborn rename preserves staged and working contents")
        do {
            try await unborn.apply(root: root.path, newName: "stale")
            throw GitFailure.message("accepted stale unborn rename")
        } catch { try check(error.localizedDescription.contains("分支已发生变化"), "stale unborn rename is rejected") }
        let back = try await BranchMutation.prepare(root: root.path, branch: Branch(name: "renamed", remote: false, unborn: true))
        try await back.apply(root: root.path, newName: "main")
        try await model.refresh()
        model.newBranch("premature")
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        let unbornHead = try await git(["symbolic-ref", "--short", "HEAD"])
        try check(model.error != nil && unbornHead.trimmingCharacters(in: .whitespacesAndNewlines) == "main", "creating a branch before first commit preserves original branch name")
        model.error = nil
        try write("shared.txt", "base\n"); try write("conflict.txt", "base\n")
        _ = try await git(["add", "."]); _ = try await git(["commit", "-m", "base"])
        model.newBranch("feature")
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.error == nil && model.branch == "feature" && model.branches.contains { $0.name == "main" && !$0.remote }, "creating a branch after first commit retains original branch")
        try write("conflict.txt", "feature\n")
        _ = try await git(["commit", "-am", "feature change"]); _ = try await git(["switch", "main"])
        try write("shared.txt", "staged\n"); _ = try await git(["add", "shared.txt"])
        try write("shared.txt", "staged\nunstaged\n"); try write("new.txt", "untracked\n")
        try await model.refresh()
        try check(model.branches.contains { $0.name == "main" && !$0.unborn }, "committed branch no longer shows unborn label")
        model.checkout(Branch(name: "feature", remote: false))
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.error == nil && model.branch == "feature", "checkout allows safe dirty-worktree switching")
        let staged = try await git(["show", ":shared.txt"])
        try check(staged == "staged\n" && read("shared.txt") == "staged\nunstaged\n" && read("new.txt") == "untracked\n", "staged, unstaged and untracked content survives switch")
        try await model.switchBranch(Branch(name: "main", remote: false))
        try write("conflict.txt", "local edit\n"); try await model.refresh()
        model.load("conflict.txt", staged: false)
        while model.loadingPreview { try await Task.sleep(nanoseconds: 10_000_000) }
        model.checkout(Branch(name: "feature", remote: false))
        while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        let head = try await git(["branch", "--show-current"])
        try check(model.error == nil && model.branchSwitchPrompt != nil && head.trimmingCharacters(in: .whitespacesAndNewlines) == "main", "Git rejects switch that would overwrite local changes")
        try check(read("conflict.txt") == "local edit\n" && model.activeTabID == "conflict.txt", "failed switch preserves file and editor tab")
        try check(staged == (try await git(["show", ":shared.txt"])), "failed switch preserves staging area")
        let prompt = model.branchSwitchPrompt!
        try write("conflict.txt", "edited during dialog\n")
        do { try await model.applyBranchSwitch(prompt, choice: .stash); throw GitFailure.message("accepted stale dialog") }
        catch { try check(error.localizedDescription.contains("确认期间"), "changed content blocks stale branch dialog") }
        try check(read("conflict.txt") == "edited during dialog\n", "stale dialog preserves edits")
        try await model.switchBranch(Branch(name: "feature", remote: false))
        try await model.applyBranchSwitch(model.branchSwitchPrompt!, choice: .stash)
        try check(model.branch == "feature" && model.changes.isEmpty, "stash choice switches with clean worktree")
        let backup = try await git(["rev-parse", "refs/stash"])
        let newBackup = try await git(["show", "stash@{0}^3:new.txt"])
        try check(newBackup == "untracked\n", "stash includes untracked files")
        _ = try await git(["switch", "main"])
        _ = try await git(["stash", "apply", backup.trimmingCharacters(in: .whitespacesAndNewlines)])
        try await model.refresh()
        try await model.switchBranch(Branch(name: "feature", remote: false))
        do { try await model.applyBranchSwitch(model.branchSwitchPrompt!, choice: .carry); throw GitFailure.message("expected merge conflict") }
        catch { try check(error.localizedDescription.contains("完整备份"), "carry reports conflicts with recoverable backup") }
        try check(model.branch == "feature" && model.changes.contains(where: { $0.conflict }), "carry keeps destination branch and exposes conflicts")
        try check(!(try await git(["stash", "list"])).isEmpty, "carry retains backup")
        _ = try await git(["reset", "--hard", "HEAD"])
        try FileManager.default.removeItem(at: root.appendingPathComponent("new.txt"))
        _ = try await git(["switch", "main"])
        try write("conflict.txt", "discard this\n")
        try await model.refresh()
        try await model.switchBranch(Branch(name: "feature", remote: false))
        try await model.applyBranchSwitch(model.branchSwitchPrompt!, choice: .discard)
        try check(model.branch == "feature" && model.changes.isEmpty && read("conflict.txt") == "feature\n", "discard choice clears tracked modifications and switches")
        let baseLines = (1...30).map { "line \($0)" }
        try write("merge.txt", baseLines.joined(separator: "\n") + "\n")
        _ = try await git(["add", "merge.txt"]); _ = try await git(["commit", "-m", "merge base"])
        _ = try await git(["switch", "-c", "carry-target"])
        var targetLines = baseLines; targetLines[0] = "target first line"
        try write("merge.txt", targetLines.joined(separator: "\n") + "\n")
        _ = try await git(["commit", "-am", "target change"])
        _ = try await git(["switch", "feature"])
        var localLines = baseLines; localLines[29] = "local last line"
        try write("merge.txt", localLines.joined(separator: "\n") + "\n")
        try write("carry-new.txt", "keep me")
        try await model.refresh()
        try await model.switchBranch(Branch(name: "carry-target", remote: false))
        try await model.applyBranchSwitch(model.branchSwitchPrompt!, choice: .carry)
        let merged = try read("merge.txt")
        try check(model.branch == "carry-target" && merged.contains("target first line") && merged.contains("local last line") && read("carry-new.txt") == "keep me", "carry merges nonoverlapping changes and restores new files")
        model.error = nil
        do { try await model.switchBranch(Branch(name: "missing", remote: false)); throw GitFailure.message("accepted missing branch") }
        catch { try check(model.branchSwitchPrompt == nil, "unrelated switch failures do not show overwrite prompt") }

    }
}

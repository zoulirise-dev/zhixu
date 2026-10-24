import Foundation

@main struct ExplorerIntegration {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-explorer-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await Git.run(root.path, ["init", "-b", "main"])
        let key = "explorer-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: key)!
        defer { defaults.removePersistentDomain(forName: key) }
        let model = Workspace(defaults: defaults, restore: false)
        try await model.open(root.path)
        func wait() async throws { while model.busy || model.loadingPreview { try await Task.sleep(nanoseconds: 10_000_000) } }
        func check(_ ok: Bool, _ name: String) throws { guard ok else { throw GitFailure.message("FAIL: " + name) }; print("PASS: " + name) }
        model.editFiles(action: "folder", paths: [], destination: "parent/empty")
        try await wait()
        try check(model.error == nil && model.files.contains("parent/empty/"), "nested empty directories remain visible")
        model.editFiles(action: "file", paths: [], destination: "parent/empty/test.txt")
        try await wait()
        try check(model.error == nil && model.activeDocument?.path == "parent/empty/test.txt", "new file opens in editor")
        model.editFiles(action: "rename", paths: ["parent"], destination: "renamed")
        try await wait()
        try check(model.error == nil && model.activeDocument?.path == "renamed/empty/test.txt", "folder rename updates descendant editor tabs")
        model.copyFiles(["renamed", "renamed/empty/test.txt"], cut: false)
        try check(model.fileClipboard?.paths == ["renamed"], "selection excludes descendants of selected folders")
        model.editFiles(action: "folder", paths: [], destination: "target")
        try await wait()
        model.editFiles(action: "paste", paths: [], destination: "target")
        try await wait()
        try check(model.error == nil && FileManager.default.fileExists(atPath: root.appendingPathComponent("target/renamed/empty/test.txt").path), "recursive copy preserves directory contents")
        model.copyFiles(["renamed/empty/test.txt"], cut: true)
        try check(model.cutFilePaths == ["renamed/empty/test.txt"], "cut exposes pending paths for dimmed rows")
        model.editFiles(action: "paste", paths: [], destination: "target")
        try await wait()
        try check(model.cutFilePaths.isEmpty, "successful paste clears dimmed rows")
        try check(model.error == nil && model.fileClipboard == nil && model.activeDocument?.path == "target/test.txt", "cut and paste updates tabs and clears clipboard")
        do { try ExplorerFiles.transfer(root: root.path, source: "target/test.txt", destination: "target/renamed/empty/test.txt", move: true); throw GitFailure.message("accepted overwrite") }
        catch { try check(error.localizedDescription.contains("同名"), "existing destination cannot be overwritten") }
        let copied = try ExplorerFiles.paste(root: root.path, source: "target/test.txt", directory: "target", move: false)
        let second = try ExplorerFiles.paste(root: root.path, source: "target/test.txt", directory: "target", move: false)
        try check(copied == "target/test 副本.txt" && second == "target/test 副本 2.txt", "repeated same-directory paste preserves file extension and increments suffix")
        let copiedFolder = try ExplorerFiles.paste(root: root.path, source: "target/renamed", directory: "target", move: false)
        try check(copiedFolder == "target/renamed 副本" && FileManager.default.fileExists(atPath: root.appendingPathComponent(copiedFolder + "/empty/test.txt").path), "same-directory folder copy preserves contents")
        try ExplorerFiles.create(root: root.path, path: ".env", folder: false)
        try check(try ExplorerFiles.paste(root: root.path, source: ".env", directory: "", move: false) == ".env 副本", "dotfile duplicate keeps original name")
        try check(try ExplorerFiles.paste(root: root.path, source: "target/test.txt", directory: "target", move: true) == "target/test.txt", "same-directory cut paste is a no-op")
        for invalid in ["../escape", ".git/config", "/tmp/escape"] {
            do { try ExplorerFiles.create(root: root.path, path: invalid, folder: false); throw GitFailure.message("accepted unsafe path") }
            catch { try check(error.localizedDescription.contains("有效名称"), "invalid path rejected: " + invalid) }
        }
        let activePath = model.activeDocument?.path
        model.code = "unsaved buffer"
        model.checked = ["target/test.txt"]
        try "external".write(to: root.appendingPathComponent("external.txt"), atomically: true, encoding: .utf8)
        model.refreshFiles()
        try check(!model.busy, "file refresh does not disable the whole app")
        while model.filesRefreshing { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.files.contains("external.txt"), "file refresh discovers external changes")
        try check(model.activeDocument?.path == activePath && model.code == "unsaved buffer" && model.dirty && model.checked == ["target/test.txt"], "file refresh preserves unsaved editor and checked state")
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("outside").path, withDestinationPath: root.deletingLastPathComponent().path)
        do { try ExplorerFiles.create(root: root.path, path: "outside/escape", folder: false); throw GitFailure.message("followed external link") }
        catch { try check(error.localizedDescription.contains("项目外"), "symlink parent cannot escape workspace") }
        // Ignored content belongs in the explorer, but not in commit candidates.
        let cache = root.appendingPathComponent(".cache/nested")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try "cache file".write(to: cache.appendingPathComponent("generated.txt"), atomically: true, encoding: .utf8)
        try "keep".write(to: root.appendingPathComponent(".cache/tracked.txt"), atomically: true, encoding: .utf8)
        _ = try await Git.run(root.path, ["add", ".cache/tracked.txt"])
        try "local".write(to: root.appendingPathComponent("local.env"), atomically: true, encoding: .utf8)
        try ".cache/\nlocal.env\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        model.refreshFiles()
        while model.filesRefreshing { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.files.contains("local.env") && model.ignoredFiles.contains("local.env"), "ignored dot/config files remain visible and dimmed")
        try check(!model.files.contains(".cache/nested/generated.txt"), "collapsed ignored directories do not recursively scan content")
        try check(!model.ignoredFiles.contains(".cache/tracked.txt"), "tracked files are not dimmed by later ignore rules")
        try check(!model.changes.contains { $0.path == "local.env" || $0.path == ".cache/nested/generated.txt" }, "ignored files stay outside change list")
        // Git can expose nested ignored roots when a parent also has tracked files.
        model.expandIgnoredFolder(".cache")
        while model.filesRefreshing { try await Task.sleep(nanoseconds: 10_000_000) }
        model.expandIgnoredFolder(".cache/nested")
        while model.filesRefreshing { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.files.contains(".cache/nested/generated.txt") && model.ignoredFiles.contains(".cache/nested/generated.txt"), "expanding ignored directory loads dimmed children")
        try check(model.code == "unsaved buffer" && model.dirty && model.checked == ["target/test.txt"], "ignored-directory expansion preserves edits and selection")
        try "new".write(to: cache.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        model.refreshFiles()
        while model.filesRefreshing { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(model.files.contains(".cache/nested/new.txt"), "refresh updates already expanded ignored folders")
        try FileManager.default.removeItem(at: root.appendingPathComponent(".gitignore"))
        model.refreshFiles()
        while model.filesRefreshing { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(!model.ignoredFiles.contains("local.env") && model.changes.contains { $0.path == "local.env" }, "removing ignore rule restores normal status")
        try check(!model.files.contains { $0 == ".git" || $0.hasPrefix(".git/") }, "Git internal metadata stays hidden")
        let other = root.appendingPathComponent("other-project")
        _ = try await Git.run(root.path, ["init", "-b", "main", other.path])
        try await model.open(other.path)
        try check(model.ignoredFiles.isEmpty && !model.files.contains("local.env"), "switching projects clears ignored explorer state")
        print("All explorer checks passed")
    }
}

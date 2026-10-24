import Foundation

@main struct ResponsivenessIntegration {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-load-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "zhixu-load-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try await Task.detached {
            for directory in 0..<50 {
                let folder = root.appendingPathComponent("src/group\(directory)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for file in 0..<100 {
                    try Data("const value\(file) = '中文';\n".utf8).write(to: folder.appendingPathComponent("file\(file).js"))
                }
            }
            let ignored = root.appendingPathComponent("node_modules/generated")
            try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
            for file in 0..<2000 { try Data("ignored".utf8).write(to: ignored.appendingPathComponent("\(file).js")) }
            try "node_modules/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        }.value
        _ = try await Git.run(root.path, ["init", "-b", "main"])
        _ = try await Git.run(root.path, ["add", "."])
        _ = try await Git.run(root.path, ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "base"])
        let model = Workspace(defaults: defaults, restore: false)
        var maxGap: TimeInterval = 0
        var last = Date()
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000)
                let now = Date(); maxGap = max(maxGap, now.timeIntervalSince(last)); last = now
            }
        }
        defer { heartbeat.cancel() }
        let start = Date()
        try await model.open(root.path)
        let openTime = Date().timeIntervalSince(start)
        guard model.files.count == 5002, model.files.contains("node_modules/"), model.ignoredFiles.contains("node_modules"), !model.files.contains("node_modules/generated/") else { throw GitFailure.message("incorrect large repository listing") }
        model.load("src/group0/file0.js", staged: false)
        while model.loadingPreview { try await Task.sleep(nanoseconds: 10_000_000) }
        model.code = "unsaved 中文 buffer"
        model.checked = ["src/group0/file0.js"]
        let refreshStart = Date()
        for _ in 0..<10 {
            model.refreshFiles()
            guard !model.busy else { throw GitFailure.message("refresh blocked entire application") }
            while model.filesRefreshing { try await Task.sleep(nanoseconds: 10_000_000) }
        }
        guard model.error == nil, model.code == "unsaved 中文 buffer", model.dirty, model.checked == ["src/group0/file0.js"] else { throw GitFailure.message("refresh lost editing state") }
        print(String(format: "PASS: 5000 tracked files + 2000 ignored files; open %.3fs, 10 refreshes %.3fs, largest main-actor heartbeat gap %.3fs", openTime, Date().timeIntervalSince(refreshStart), maxGap))
        print("PASS: repeated large repository refresh preserves unsaved Chinese buffer and checked files")
    }
}

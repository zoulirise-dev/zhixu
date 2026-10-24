import Foundation
@main struct BrowserLoginIntegration {
    @MainActor static func main() async throws {
        func check(_ value: Bool, _ title: String) throws {
            guard value else { throw GitFailure.message(title) }; print("PASS: " + title)
        }
        try check(BrowserLogin.deviceCode(in: "! First copy your one-time code: ABCD-1234\n") == "ABCD-1234", "parse official device code")
        try check(BrowserLogin.deviceCode(in: "! One-time code (ABCD-1234) copied to clipboard") == "ABCD-1234", "parse official copied code format")
        try check(BrowserLogin.deviceCode(in: "secret: ghp_example_not_a_code") == nil, "never display token as code")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-login-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let env = BrowserLogin.isolatedEnvironment(directory: root)
        try check(env["GH_CONFIG_DIR"] == root.path && env["GIT_CONFIG_GLOBAL"] == root.appendingPathComponent("gitconfig").path, "separate gh and Git configurations")
        try check(env["GH_TOKEN"] == nil && env["GITHUB_TOKEN"] == nil, "existing environment credentials are not used")
        var opened = 0
        let login = BrowserLogin(openAuthorization: { opened += 1 })
        let script = root.appendingPathComponent("fake-login")
        try Data("#!/bin/sh\nprintf '! First copy your one-time code: ABCD-1234\\n' >&2\nexec /bin/sleep 10\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let job = Task { try await login.run(script, [], environment: env, directory: root, progress: true) }
        for _ in 0..<30 {
            if !login.code.isEmpty { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try check(login.code == "ABCD-1234" && opened == 1, "show code and open browser before login completes")
        job.cancel()
        do { _ = try await job.value; throw GitFailure.message("cancel ignored") }
        catch is CancellationError { print("PASS: cancellation terminates login promptly") }
        let bad = root.appendingPathComponent("failed-login")
        try Data("#!/bin/sh\nprintf 'secret-server-output' >&2\nexit 1\n".utf8).write(to: bad)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bad.path)
        do { _ = try await login.run(bad, [], environment: env, directory: root); throw GitFailure.message("failure ignored") }
        catch { try check(!error.localizedDescription.contains("secret-server-output") && error.localizedDescription != "failure ignored", "raw authentication errors are not shown") }
    }
}

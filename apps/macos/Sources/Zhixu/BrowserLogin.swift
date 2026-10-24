import Foundation
import AppKit
import SwiftUI

/// Runs the official GitHub CLI OAuth flow in a private, disposable configuration.
/// It never changes the user's gh accounts or Git credential helpers.
@MainActor final class BrowserLogin: ObservableObject {
    @Published var running = false
    @Published var code = ""
    @Published var message = ""
    private var task: Task<Void, Never>?
    private var process: Process?
    private var generation = UUID()
    private let openAuthorization: () -> Void
    init(openAuthorization: @escaping () -> Void = { NSWorkspace.shared.open(URL(string: "https://github.com/login/device")!) }) {
        self.openAuthorization = openAuthorization
    }
    static var executable: URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/gh")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        return nil
    }
    nonisolated static func deviceCode(in output: String) -> String? {
        let pattern = #"(?i)(?:one-time code|device code)(?::\s*| \()([A-Z0-9]{4}-[A-Z0-9]{4})"#
        guard let expression = try? NSRegularExpression(pattern: pattern), let match = expression.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)), let range = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[range])
    }
    static func isolatedEnvironment(directory: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GH_") && !$0.key.hasPrefix("GITHUB_") && !$0.key.hasPrefix("GIT_") }
        env["GH_CONFIG_DIR"] = directory.path
        env["GH_NO_UPDATE_NOTIFIER"] = "1"
        env["GH_NO_EXTENSION_UPDATE_NOTIFIER"] = "1"
        env["GH_PROMPT_DISABLED"] = "1"
        env["GH_BROWSER"] = "/usr/bin/open"
        env["GH_HOST"] = "github.com"
        env["GIT_CONFIG_GLOBAL"] = directory.appendingPathComponent("gitconfig").path
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["NO_COLOR"] = "1"
        env["LC_ALL"] = "C"
        return env
    }
    func cancel() {
        if running { message = L("已取消登录。") }
        generation = UUID(); task?.cancel(); task = nil
        process?.terminate(); running = false; code = ""
    }
    func start(completed: @escaping (GitAccount) -> Void) {
        guard !running else { return }
        guard let executable = Self.executable else { message = L("网页登录组件缺失，请重新安装完整应用。"); return }
        let request = UUID(); generation = request; running = true; code = ""
        message = L("正在打开 GitHub 授权页面…")
        task = Task {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-login-" + UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                defer { try? FileManager.default.removeItem(at: directory) }
                let env = Self.isolatedEnvironment(directory: directory)
                // gh's temporary plaintext store is confined to this owner-only directory,
                // imported immediately into Keychain, and removed on success/failure/cancel.
                // This avoids gh writing to the user's existing shared Keychain credentials.
                _ = try await run(executable, ["auth", "login", "--hostname", "github.com", "--web", "--git-protocol", "https", "--skip-ssh-key", "--insecure-storage"], environment: env, directory: directory, progress: true)
                try Task.checkCancellation()
                let credential = try await run(executable, ["auth", "token", "--hostname", "github.com"], environment: env, directory: directory)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !credential.isEmpty else { throw GitFailure.message(L("未收到登录凭据，请重试。")) }
                let userData = try await run(executable, ["api", "user"], environment: env, directory: directory)
                struct User: Decodable { let login: String; let name: String?; let email: String? }
                let user = try JSONDecoder().decode(User.self, from: Data(userData.utf8))
                try Task.checkCancellation()
                guard generation == request else { return }
                var accounts = AccountStore.accounts()
                var account = accounts.first { $0.host == "github.com" && $0.username == user.login && $0.method == "https" } ?? GitAccount()
                account.label = "GitHub · " + user.login; account.host = "github.com"; account.username = user.login; account.method = "https"
                account.name = user.name ?? user.login; account.email = user.email ?? ""
                try AccountStore.setToken(credential, id: account.id)
                if let i = accounts.firstIndex(where: { $0.id == account.id }) { accounts[i] = account } else { accounts.append(account) }
                try AccountStore.save(accounts)
                AccountStore.rememberLogin(account)
                message = L("登录成功，已记住登录状态。点击重试继续。")
                completed(account)
            } catch is CancellationError {
                if generation == request { message = L("已取消登录。") }
            } catch {
                if generation == request { message = error.localizedDescription }
            }
            if generation == request { running = false; code = ""; task = nil }
        }
    }
    private func show(code: String, request: UUID) {
        guard generation == request else { return }
        if self.code.isEmpty { openAuthorization() }
        self.code = code
        message = L("在浏览器输入验证码并确认授权，完成后会自动返回。")
    }
    func run(_ executable: URL, _ args: [String], environment: [String: String], directory: URL, progress: Bool = false) async throws -> String {
        try Task.checkCancellation()
        let process = Process(); self.process = process
        process.executableURL = executable; process.arguments = args; process.environment = environment; process.currentDirectoryURL = directory
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors; process.standardInput = FileHandle.nullDevice
        // Drain both pipes concurrently to keep cancellation responsive and prevent pipe deadlocks.
        try process.run()
        let out = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
        let request = generation
        let err = Task.detached { [weak self] in
            var collected = Data()
            while true {
                let chunk = errors.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                collected.append(chunk)
                if progress, let code = Self.deviceCode(in: String(decoding: collected, as: UTF8.self)) {
                    await self?.show(code: code, request: request)
                }
            }
            return collected
        }
        let deadline = Date().addingTimeInterval(progress ? 900 : 30)
        while process.isRunning {
            if Task.isCancelled || Date() >= deadline {
                process.terminate()
                while process.isRunning { try? await Task.sleep(nanoseconds: 50_000_000) }
                _ = await out.value; _ = await err.value
                if Task.isCancelled { throw CancellationError() }
                throw GitFailure.message(L("登录等待超时，请重试。"))
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        let stdout = await out.value, stderr = await err.value
        if self.process === process { self.process = nil }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            // Do not surface raw CLI output: it could contain credentials or server diagnostics.
            throw GitFailure.message(L("登录未完成。请检查网络，或重新打开网页完成授权。"))
        }
        _ = stderr
        return String(decoding: stdout, as: UTF8.self)
    }
}

import Foundation
import Security

struct GitAccount: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var label = ""
    var name = ""
    var email = ""
    var method = "system"
    var host = "github.com"
    var username = ""
    var keyPath = ""
}

/// HTTPS credential scope includes the port; repositories on another server
/// must never receive this server's saved password. Default 443 stays compatible.
enum HTTPSGitServer {
    static func key(_ address: String) -> String? {
        guard let url = URLComponents(string: address), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || (1...65535).contains(url.port!) else { return nil }
        let authority = host.contains(":") && !host.hasPrefix("[") ? "[" + host + "]" : host
        return authority + ((url.port ?? 443) == 443 ? "" : ":" + String(url.port!))
    }
    static func normalize(_ server: String) -> String? {
        guard let url = URLComponents(string: "https://" + server), url.path.isEmpty, url.query == nil else { return nil }
        return key("https://" + server)
    }
}

enum AccountStore {
    // Legacy project overrides are intentionally never used by remote commands.
    static func migrate(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "projectAccounts")
        defaults.removeObject(forKey: "projectAccountSnapshots")
    }
    static func rememberLogin(_ account: GitAccount, defaults: UserDefaults = .standard) {
        guard account.method == "https", let server = HTTPSGitServer.normalize(account.host) else { return }
        var remembered = defaults.dictionary(forKey: "rememberedGitLogins") as? [String: String] ?? [:]
        remembered[server] = account.id
        defaults.set(remembered, forKey: "rememberedGitLogins")
    }
    static func rememberedLogin(host: String = "github.com", defaults: UserDefaults = .standard) -> GitAccount? {
        guard let host = HTTPSGitServer.normalize(host) else { return nil }
        let id = (defaults.dictionary(forKey: "rememberedGitLogins") as? [String: String])?[host]
            ?? (host == "github.com" ? defaults.string(forKey: "rememberedGitHubLogin") : nil)
        return accounts(defaults).first { $0.id == id && $0.method == "https" && HTTPSGitServer.normalize($0.host) == host }
    }
    static func rememberSuccessful(_ account: GitAccount, secret: String) throws {
        try setToken(secret, id: account.id)
        var saved = accounts()
        if let index = saved.firstIndex(where: { $0.id == account.id }) { saved[index] = account } else { saved.append(account) }
        try save(saved)
        rememberLogin(account)
    }

    static func accounts(_ defaults: UserDefaults = .standard) -> [GitAccount] {
        guard let data = defaults.data(forKey: "gitAccounts") else { return [] }
        return (try? JSONDecoder().decode([GitAccount].self, from: data)) ?? []
    }
    static func save(_ accounts: [GitAccount], defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(accounts), forKey: "gitAccounts")
    }
    static func selected(_ root: String, defaults: UserDefaults = .standard) -> GitAccount? {
        let path = URL(fileURLWithPath: root).standardizedFileURL.path
        if let snapshots = defaults.dictionary(forKey: "projectAccountSnapshots") as? [String: Data], let data = snapshots[path], let account = try? JSONDecoder().decode(GitAccount.self, from: data) { return account }
        let id = (defaults.dictionary(forKey: "projectAccounts") as? [String: String])?[URL(fileURLWithPath: root).standardizedFileURL.path]
        return accounts(defaults).first { $0.id == id }
    }
    static func bind(_ account: GitAccount?, root: String, defaults: UserDefaults = .standard) {
        var bindings = defaults.dictionary(forKey: "projectAccounts") as? [String: String] ?? [:]
        bindings[URL(fileURLWithPath: root).standardizedFileURL.path] = account?.id
        defaults.set(bindings, forKey: "projectAccounts")
        var snapshots = defaults.dictionary(forKey: "projectAccountSnapshots") as? [String: Data] ?? [:]
        snapshots[URL(fileURLWithPath: root).standardizedFileURL.path] = account.flatMap { try? JSONEncoder().encode($0) }
        defaults.set(snapshots, forKey: "projectAccountSnapshots")
    }
    static func token(_ id: String) throws -> String {
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.zhixu.git.accounts", kSecAttrAccount as String: id, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw GitFailure.message(L("无法读取账号令牌，请在设置中重新保存令牌。")) }
        return value
    }
    static func setToken(_ value: String, id: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.zhixu.git.accounts", kSecAttrAccount as String: id]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = Data(value.utf8)
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw GitFailure.message(L("无法保存令牌到钥匙串。")) }; return
        }
        guard status == errSecSuccess else { throw GitFailure.message(L("无法保存令牌到钥匙串。")) }
    }
    static func deleteToken(_ id: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.zhixu.git.accounts", kSecAttrAccount as String: id] as CFDictionary)
    }
}

struct GitAuthentication {
    var arguments: [String] = []
    var environment: [String: String] = [:]
    var secret: String? = nil
    static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func validate(_ url: String, account: GitAccount) throws {
        if account.method == "https" {
            guard let server = HTTPSGitServer.key(url), server == HTTPSGitServer.normalize(account.host) else {
                throw GitFailure.message(L("远程服务器或端口与已保存的认证不一致，请检查仓库地址。"))
            }
            return
        }
        let host: String?
        if url.contains("://") {
            let parsed = URLComponents(string: url)
            guard (account.method == "https" && parsed?.scheme == "https") || (account.method == "ssh" && parsed?.scheme == "ssh") else { throw GitFailure.message(L("远程地址协议与所选账号不一致。")) }
            host = parsed?.host
        } else if account.method == "ssh", let colon = url.firstIndex(of: ":") {
            host = String(url[..<colon].split(separator: "@").last ?? "")
        } else { throw GitFailure.message(L("远程地址协议与所选账号不一致。")) }
        guard host?.lowercased() == account.host.lowercased(), !account.host.isEmpty else { throw GitFailure.message(L("远程服务器与已保存的认证不一致，请检查仓库地址。")) }
    }
    static func prepare(_ root: String, args: [String], destinations: [String] = [], account: GitAccount? = nil, secret: String? = nil) async throws -> GitAuthentication {
        guard let command = args.first, ["fetch", "pull", "push", "ls-remote", "clone"].contains(command), let account, account.method != "system" else { return GitAuthentication() }
        guard !destinations.isEmpty else { throw GitFailure.message(L("请先配置远程仓库地址。")) }
        for url in destinations { try validate(url, account: account) }
        if account.method == "ssh" {
            let path = (account.keyPath as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { throw GitFailure.message(L("SSH 私钥文件不存在。")) }
            return GitAuthentication(environment: ["GIT_SSH_COMMAND": "ssh -i \(quote(path)) -o IdentitiesOnly=yes -o BatchMode=yes"])
        }
        let token: String
        do { token = try secret ?? AccountStore.token(account.id) }
        catch { throw GitRemoteFailure(root: root, arguments: args, destinations: destinations, kind: .authentication) }
        return GitAuthentication(arguments: ["-c", "credential.helper=", "-c", "http.followRedirects=false"], environment: ["ZHIXU_GIT_USERNAME": account.username, "ZHIXU_GIT_TOKEN": token], secret: token)
    }
}

struct GitLoginAttempt: Sendable {
    let account: GitAccount
    let secret: String?
}


/// Publish only a credential that has just completed a Git operation successfully.
/// `approve` uses the same URL/path policy and helpers as command-line Git/IDEs.
enum SharedGitCredentials {
    static func approve(root: String, destinations: [String], account: GitAccount, secret: String) async throws {
        guard !destinations.isEmpty, !account.username.isEmpty, !secret.isEmpty,
              [account.username, secret].allSatisfy({ !$0.contains("\n") && !$0.contains("\r") && !$0.contains("\0") }) else {
            throw GitFailure.message("Invalid credential fields")
        }
        let executable = try await GitEnvironment.shared.executable()
        var environment = ProcessInfo.processInfo.environment
        for key in ["ZHIXU_GIT_TOKEN", "ZHIXU_GIT_USERNAME", "GIT_ASKPASS"] { environment.removeValue(forKey: key) }
        environment["GIT_TERMINAL_PROMPT"] = "0"; environment["LC_ALL"] = "C"
        for destination in Set(destinations) {
            try GitAuthentication.validate(destination, account: account)
            guard !destination.contains("\n"), !destination.contains("\r"), !destination.contains("\0") else { throw GitFailure.message("Invalid credential URL") }
            let helpers = try await GitProcess.run(executable, arguments: ["-C", root, "config", "--get-urlmatch", "credential.helper", destination], environment: environment)
            if helpers.code == 1 {
                // No helper configured: adopt macOS's standard secure helper.
                // Never replace an existing helper or an explicit empty override.
                let configured = try await GitProcess.run(executable, arguments: ["config", "--global", "--add", "credential.helper", "osxkeychain"], environment: environment)
                guard configured.code == 0 else { throw GitFailure.message("Credential helper unavailable") }
            } else {
                guard helpers.code == 0, !helpers.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GitFailure.message("Credential helper disabled") }
            }
            let input = "url=\(destination)\nusername=\(account.username)\npassword=\(secret)\n\n"
            let saved = try await GitProcess.run(executable, arguments: ["-C", root, "credential", "approve"], environment: environment, input: input, timeout: 30)
            // Git can return zero even if a helper failed; stderr is never exposed
            // because a third-party helper could accidentally print a credential.
            guard saved.code == 0, saved.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GitFailure.message("Credential helper did not save") }
        }
    }
}

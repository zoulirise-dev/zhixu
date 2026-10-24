import Foundation
@main struct AccountIntegration {
    static func main() async throws {
        func check(_ condition: Bool, _ title: String) throws {
            guard condition else { throw GitFailure.message(title) }; print("PASS: " + title)
        }
        let suite = "zhixu-account-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var account = GitAccount(); account.name = "Test"; account.email = "test@example.invalid"; account.label = "Work"; account.method = "https"
        try AccountStore.save([account], defaults: defaults)
        AccountStore.bind(account, root: "/tmp/project-a", defaults: defaults)
        try check(AccountStore.selected("/tmp/project-a", defaults: defaults) == account, "project account persists")
        try check(AccountStore.selected("/tmp/project-b", defaults: defaults) == nil, "other projects stay unchanged")
        var edited = account; edited.name = "Edited"
        try AccountStore.save([edited], defaults: defaults)
        try check(AccountStore.selected("/tmp/project-a", defaults: defaults)?.name == "Test", "editing a profile requires explicit application")
        AccountStore.bind(nil, root: "/tmp/project-a", defaults: defaults)
        try check(AccountStore.selected("/tmp/project-a", defaults: defaults) == nil, "system authentication fallback")
        try GitAuthentication.validate("https://github.com/org/repo.git", account: account)
        do { try GitAuthentication.validate("https://evil.example/repo.git", account: account); throw GitFailure.message("host accepted") } catch { try check(error.localizedDescription != "host accepted", "reject mismatched host") }
        do { try GitAuthentication.validate("http://github.com/org/repo.git", account: account); throw GitFailure.message("http accepted") } catch { try check(error.localizedDescription != "http accepted", "reject insecure transport") }
        AccountStore.rememberLogin(edited, defaults: defaults)
        let reopened = UserDefaults(suiteName: suite)!
        try check(AccountStore.rememberedLogin(defaults: reopened)?.id == edited.id, "browser login remembered across store reloads")
        try check(AccountStore.selected("/tmp/new-clone", defaults: reopened) == nil, "remembered login does not override system authentication for new projects")
        var wrongHost = edited; wrongHost.id = UUID().uuidString; wrongHost.host = "example.invalid"
        AccountStore.rememberLogin(wrongHost, defaults: defaults)
        try check(AccountStore.rememberedLogin(defaults: defaults)?.id == edited.id, "another server cannot replace GitHub login")
        AccountStore.bind(account, root: "/tmp/legacy", defaults: defaults)
        AccountStore.migrate(defaults: defaults)
        try check(AccountStore.selected("/tmp/legacy", defaults: defaults) == nil, "legacy project bindings are removed")
        try check(AccountStore.rememberedLogin(defaults: defaults)?.id == edited.id, "migration preserves browser login")
        var gitee = account; gitee.id = UUID().uuidString; gitee.host = "gitee.com"
        try AccountStore.save([edited, gitee], defaults: defaults)
        AccountStore.rememberLogin(gitee, defaults: defaults)
        try check(AccountStore.rememberedLogin(host: "gitee.com", defaults: defaults)?.id == gitee.id, "Gitee remembered independently")
        try check(AccountStore.rememberedLogin(defaults: defaults)?.id == edited.id, "Gitee cannot replace GitHub login")
        var custom = account; custom.id = UUID().uuidString; custom.host = "git.company.invalid:8443"
        var normal = custom; normal.id = UUID().uuidString; normal.host = "git.company.invalid"
        try AccountStore.save([edited, gitee, custom, normal], defaults: defaults)
        AccountStore.rememberLogin(custom, defaults: defaults)
        AccountStore.rememberLogin(normal, defaults: defaults)
        try check(AccountStore.rememberedLogin(host: "git.company.invalid:8443", defaults: defaults)?.id == custom.id, "custom HTTPS port remembers its own login")
        try check(AccountStore.rememberedLogin(host: "git.company.invalid:443", defaults: defaults)?.id == normal.id, "default HTTPS port shares canonical server key")
        try GitAuthentication.validate("https://git.company.invalid:8443/group/repo.git", account: custom)
        do { try GitAuthentication.validate("https://git.company.invalid/group/repo.git", account: custom); throw GitFailure.message("port accepted") } catch { try check(error.localizedDescription != "port accepted", "saved password cannot cross ports") }
        try check(HTTPSGitServer.key("https://GIT.Company.invalid:443/repo") == "git.company.invalid", "server names normalize case and standard port")
        try check(HTTPSGitServer.key("https://[::1]:8443/repo") == "[::1]:8443", "IPv6 self-hosted HTTPS address")
        account.method = "ssh"
        try GitAuthentication.validate("git@github.com:org/repo.git", account: account)
        try GitAuthentication.validate("ssh://git@github.com/org/repo.git", account: account)
        try check(GitAuthentication.quote("/tmp/a'b") == "'/tmp/a'\\''b'", "SSH paths are shell quoted")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await Git.run(root.path, ["init"])
        _ = try await Git.run(root.path, ["config", "--local", "user.name", account.name])
        let name = try await Git.run(root.path, ["config", "--local", "user.name"])
        try check(name.trimmingCharacters(in: .whitespacesAndNewlines) == account.name, "local identity is applied")
        _ = try await Git.run(root.path, ["remote", "add", "origin", "https://github.com/example/test.git"])
        let origin = try await Git.run(root.path, ["remote", "get-url", "origin"])
        try check(origin.trimmingCharacters(in: .whitespacesAndNewlines) == "https://github.com/example/test.git", "origin can be prefilled")
    }
}

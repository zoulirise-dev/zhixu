import Foundation
import Darwin

@main struct AuthReliabilityIntegration {
    static func check(_ value: Bool, _ message: String) throws {
        guard value else { throw GitFailure.message(message) }; print("PASS: " + message)
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-auth-reliability-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do { _ = try await GitEnvironment(candidates: []).executable(); throw GitFailure.message("missing Git accepted") }
        catch is GitEnvironmentMissing { print("PASS: clean-machine missing Git is actionable") }
        let realGit = try await GitEnvironment.shared.executable()
        let discovered = try await GitEnvironment(candidates: [realGit]).executable()
        try check(discovered == realGit, "installed Git detected")
        _ = try await Git.run(root.path, ["init", "-b", "main"])
        _ = try await Git.run(root.path, ["remote", "add", "origin", "https://gitee.com/example/test.git"])
        _ = try await Git.run(root.path, ["remote", "add", "github", "https://github.com/example/test.git"])
        let target = try await Git.destinations(root.path, ["push", "--set-upstream", "origin", "HEAD"])
        try check(target == ["https://gitee.com/example/test.git"], "explicit remote excludes unrelated GitHub URL")
        _ = try await Git.run(root.path, ["config", "branch.main.remote", "github"])
        _ = try await Git.run(root.path, ["config", "remote.pushDefault", "origin"])
        let push = try await Git.destinations(root.path, ["push"])
        let pull = try await Git.destinations(root.path, ["pull"])
        try check(push == target && pull == ["https://github.com/example/test.git"], "push and pull honor different configured remotes")
        let failure = GitRemoteFailure(root: root.path, arguments: ["push"], destinations: target, kind: .authentication)
        try check(failure.canPasswordLogin && !failure.canLogin, "Gitee requests password, not GitHub browser login")
        for url in ["http://gitee.com/a", "https://user:secret@gitee.com/a", "https://gitee.com:0/a", "git@gitee.com:a"] {
            try check(!GitRemoteFailure(root: root.path, arguments: ["push"], destinations: [url], kind: .authentication).canPasswordLogin, "no credentials offered to untrusted endpoint")
        }
        let sharedStore = root.appendingPathComponent("shared-credentials.json")
        let helper = root.appendingPathComponent("credential-helper.py")
        let helperSource = """
        #!/usr/bin/python3
        import json, pathlib, sys
        store = pathlib.Path(__file__).with_name('shared-credentials.json')
        fields = dict(line.rstrip('\\n').split('=', 1) for line in sys.stdin if '=' in line)
        key = fields.get('protocol', '') + '://' + fields.get('host', '') + '/' + fields.get('path', '')
        entries = json.loads(store.read_text()) if store.exists() else {}
        if sys.argv[1] == 'store':
            entries[key] = fields
            store.write_text(json.dumps(entries))
            store.chmod(0o600)
        elif sys.argv[1] == 'get':
            saved = entries.get(key, {})
            if not fields.get('username') or fields.get('username') == saved.get('username'):
                for k, v in saved.items(): print(k + '=' + v)
        elif sys.argv[1] == 'erase':
            entries.pop(key, None)
            store.write_text(json.dumps(entries))
        """
        try Data(helperSource.utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        // Override the helper only inside this temporary repository; never put
        // virtual gitee.com/github.com credentials into the user's shared Keychain.
        _ = try await Git.run(root.path, ["config", "--add", "credential.helper", ""])
        _ = try await Git.run(root.path, ["config", "--add", "credential.helper", helper.path])
        let script = root.appendingPathComponent("fake-git")
        // Deterministic transport: no external requests; local metadata uses real Git.
        let content = """
        #!/bin/sh
        for arg in "$@"; do
          case "$arg" in
            push|fetch)
              if [ "$ZHIXU_GIT_TOKEN" != 'test-password-only' ]; then
                echo 'fatal: Authentication failed' >&2; exit 128
              fi
              test "$("$GIT_ASKPASS" 'Username')" = 'test-user' || exit 2
              test "$("$GIT_ASKPASS" 'Password')" = 'test-password-only' || exit 3
              exit 0;;
          esac
        done
        exec '\(realGit)' "$@"
        """
        try Data(content.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        var account = GitAccount(); account.host = "gitee.com"; account.method = "https"; account.username = "test-user"
        var testAccountIDs = [account.id]
        let oldAccounts = AccountStore.accounts()
        let oldRemembered = UserDefaults.standard.object(forKey: "rememberedGitLogins")
        defer {
            for id in testAccountIDs { AccountStore.deleteToken(id) }
            try? AccountStore.save(oldAccounts)
            if let oldRemembered { UserDefaults.standard.set(oldRemembered, forKey: "rememberedGitLogins") }
            else { UserDefaults.standard.removeObject(forKey: "rememberedGitLogins") }
        }
        try await Git.executableContext.withValue(script.path) {
            do {
                _ = try await Git.loginContext.withValue(GitLoginAttempt(account: account, secret: "wrong-test-password")) { try await Git.run(root.path, ["push", "origin"]) }
                throw GitFailure.message("wrong password accepted")
            } catch let f as GitRemoteFailure { try check(f.canPasswordLogin, "failed password returns themed sign-in recovery") }
            try check(!AccountStore.accounts().contains { $0.id == account.id }, "failed password is not saved")
            try check(!FileManager.default.fileExists(atPath: sharedStore.path), "failed password never reaches shared Git storage")
            let model = Workspace(restore: false)
            model.remoteFailure = failure
            model.retryRemote(account: account, password: "test-password-only")
            while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
            try check(model.remoteFailure == nil && model.error == nil && model.notice == L("操作完成"), "dialog login automatically resumes the failed operation")
            try check(AccountStore.rememberedLogin(host: "gitee.com")?.id == account.id, "successful operation remembers Gitee login")
            _ = try await Git.run(root.path, ["push", "origin"])
            print("PASS: next operation uses computer auth first, then remembered login")
            var independentEnv = ProcessInfo.processInfo.environment; independentEnv["GIT_TERMINAL_PROMPT"] = "0"
            let independent = try await GitProcess.run(realGit, arguments: ["-c", "credential.helper=", "-c", "credential.helper=" + helper.path, "credential", "fill"], environment: independentEnv, input: "protocol=https\nhost=gitee.com\n\n")
            try check(independent.code == 0 && independent.output.contains("password=test-password-only") && independent.output.contains("username=test-user"), "independent Git client can reuse login without Zhixu")
            do {
                _ = try await Git.run(root.path, ["fetch", "--all", "--prune"])
                throw GitFailure.message("unrelated remote authenticated")
            } catch let f as GitRemoteFailure {
                try check(f.arguments == ["fetch", "--prune", "github"] && f.canLogin, "fetch-all identifies only the failing remote; Gitee secret not sent to GitHub")
            }
        }
        for server in ["gitlab.com", "git.company.invalid:8443"] {
            var custom = GitAccount(); custom.host = server; custom.method = "https"; custom.username = "test-user"
            testAccountIDs.append(custom.id)
            _ = try await Git.run(root.path, ["remote", "set-url", "origin", "https://" + server + "/team/repo.git"])
            try await Git.executableContext.withValue(script.path) {
                do {
                    _ = try await Git.loginContext.withValue(GitLoginAttempt(account: custom, secret: "wrong-test-password")) { try await Git.run(root.path, ["push", "origin"]) }
                    throw GitFailure.message("wrong generic password accepted")
                } catch let f as GitRemoteFailure { try check(f.canPasswordLogin && f.loginServer == server, "failed custom login stays scoped to its server") }
                try check(!AccountStore.accounts().contains { $0.id == custom.id }, "failed custom password is not saved")
                let model = Workspace(restore: false)
                model.remoteFailure = GitRemoteFailure(root: root.path, arguments: ["push", "origin"], destinations: ["https://" + server + "/team/repo.git"], kind: .authentication)
                model.retryRemote(account: custom, password: "test-password-only")
                while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
                try check(model.remoteFailure == nil && model.error == nil, "custom login resumes operation")
                try check(AccountStore.rememberedLogin(host: server)?.id == custom.id, "custom login remembered in Keychain")
                _ = try await Git.run(root.path, ["push", "origin"])
                print("PASS: remembered custom login reused for " + server)
            }
        }
        try check(AccountStore.rememberedLogin(host: "gitee.com")?.id == account.id, "GitLab and company logins preserve Gitee credentials")
        try check(AccountStore.rememberedLogin(host: "git.company.invalid") == nil, "custom-port login is not reused on standard port")
        // Respect path-specific credential configuration, including usernames.
        _ = try await Git.run(root.path, ["config", "credential.useHttpPath", "true"])
        var scoped = account; scoped.host = "git.company.invalid:8443"
        try await SharedGitCredentials.approve(root: root.path, destinations: ["https://git.company.invalid:8443/team/one.git"], account: scoped, secret: "path-test-password")
        let stored = try JSONSerialization.jsonObject(with: Data(contentsOf: sharedStore)) as! [String: Any]
        try check(stored["https://git.company.invalid:8443/team/one.git"] != nil && stored["https://git.company.invalid/team/one.git"] == nil, "shared helper respects useHttpPath and custom port")
        let broken = root.appendingPathComponent("broken-helper")
        try Data("#!/bin/sh\necho 'test-helper-failure' >&2\nexit 1\n".utf8).write(to: broken)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: broken.path)
        _ = try await Git.run(root.path, ["config", "--unset-all", "credential.helper"])
        _ = try await Git.run(root.path, ["config", "--add", "credential.helper", ""])
        _ = try await Git.run(root.path, ["config", "--add", "credential.helper", broken.path])
        try await Git.executableContext.withValue(script.path) {
            let model = Workspace(restore: false)
            model.remoteFailure = GitRemoteFailure(root: root.path, arguments: ["push", "origin"], destinations: ["https://git.company.invalid:8443/team/repo.git"], kind: .authentication)
            model.retryRemote(account: scoped, password: "test-password-only")
            while model.busy { try await Task.sleep(nanoseconds: 10_000_000) }
            try check(model.remoteFailure == nil && model.notice == L("操作完成") && model.error?.contains("操作已成功") == true, "helper failure warns without replaying a successful push")
        }
        // Real macOS helper round-trip, restricted to one unique .invalid host.
        _ = try await Git.run(root.path, ["config", "--unset-all", "credential.helper"])
        _ = try await Git.run(root.path, ["config", "--add", "credential.helper", ""])
        _ = try await Git.run(root.path, ["config", "--add", "credential.helper", "osxkeychain"])
        var native = GitAccount(); native.method = "https"; native.host = "zhixu-test-" + UUID().uuidString.lowercased() + ".invalid"; native.username = "zhixu-test-user"
        let nativeURL = "https://" + native.host + "/repo.git"
        let nativeInput = "protocol=https\nhost=\(native.host)\npath=repo.git\nusername=\(native.username)\n\n"
        let nativeArgs = ["-c", "credential.helper=", "-c", "credential.helper=osxkeychain", "-c", "credential.useHttpPath=true", "credential"]
        do {
            try await SharedGitCredentials.approve(root: root.path, destinations: [nativeURL], account: native, secret: "native-test-secret")
            var env = ProcessInfo.processInfo.environment; env["GIT_TERMINAL_PROMPT"] = "0"
            let independent = try await GitProcess.run(realGit, arguments: nativeArgs + ["fill"], environment: env, input: nativeInput, timeout: 15)
            try check(independent.code == 0 && independent.output.contains("password=native-test-secret"), "independent Git reads credential from real macOS osxkeychain")
        } catch {
            _ = try? await GitProcess.run(realGit, arguments: nativeArgs + ["reject"], input: nativeInput, timeout: 15)
            throw error
        }
        _ = try await GitProcess.run(realGit, arguments: nativeArgs + ["reject"], input: nativeInput, timeout: 15)
        print("PASS: isolated shared Keychain test credential removed")
        let pidFile = root.appendingPathComponent("pid")
        let processScript = root.appendingPathComponent("wait")
        try Data("#!/bin/sh\necho $$ > '\(pidFile.path)'\n/bin/sleep 30 &\necho $! >> '\(pidFile.path)'\nwait\n".utf8).write(to: processScript)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: processScript.path)
        let start = Date()
        do { _ = try await GitProcess.run(processScript.path, arguments: [], timeout: 1.0); throw GitFailure.message("timeout missing") }
        catch { try check(error.localizedDescription.contains("超时") && Date().timeIntervalSince(start) < 3, "hung process has bounded timeout: " + error.localizedDescription) }
        let pids = try String(contentsOf: pidFile, encoding: .utf8).split(separator: "\n").compactMap { Int32($0) }
        try await Task.sleep(nanoseconds: 200_000_000)
        try check(pids.count == 2 && pids.allSatisfy { kill($0, 0) == -1 }, "timed-out Git and helper processes are reaped")
        let task = Task { try await GitProcess.run(processScript.path, arguments: [], timeout: 30) }
        try await Task.sleep(nanoseconds: 150_000_000); task.cancel()
        do { _ = try await task.value; throw GitFailure.message("cancel missing") }
        catch is CancellationError { print("PASS: canceled process exits promptly") }
        _ = try await Git.run(root.path, ["status", "--porcelain"])
        print("PASS: subsequent Git operations still work")
    }
}

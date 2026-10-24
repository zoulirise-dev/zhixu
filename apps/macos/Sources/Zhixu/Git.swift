import Foundation
import Darwin

struct CommandResult: Sendable { let output: String; let code: Int32; var errorOutput: String = "" }
enum GitFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
struct GitEnvironmentMissing: LocalizedError {
    var errorDescription: String? { L("未检测到可用的 Git。请安装命令行工具，完成后点击重新检查。") }
}

/// No pipes to deadlock, bounded execution, and cancellation that reaps the child.
enum GitProcess {
    static func run(_ executable: String, arguments: [String], environment: [String: String]? = nil, input: String? = nil, timeout: TimeInterval = 120) async throws -> CommandResult {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-git-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        var env = environment ?? ProcessInfo.processInfo.environment
        if env["ZHIXU_GIT_TOKEN"] != nil {
            let askpass = directory.appendingPathComponent("askpass")
            try Data("#!/bin/sh\ncase \"$1\" in *Username*) printf '%s\\n' \"$ZHIXU_GIT_USERNAME\";; *) printf '%s\\n' \"$ZHIXU_GIT_TOKEN\";; esac\n".utf8).write(to: askpass)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpass.path)
            env["GIT_ASKPASS"] = askpass.path
        }
        process.environment = env
        let out = directory.appendingPathComponent("out"), err = directory.appendingPathComponent("err")
        FileManager.default.createFile(atPath: out.path, contents: nil); FileManager.default.createFile(atPath: err.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: out), stderr = try FileHandle(forWritingTo: err)
        defer { try? stdout.close(); try? stderr.close() }
        process.standardOutput = stdout; process.standardError = stderr; process.standardInput = FileHandle.nullDevice
        var stdin: FileHandle?
        if let input {
            let file = directory.appendingPathComponent("input"); try Data(input.utf8).write(to: file)
            stdin = try FileHandle(forReadingFrom: file); process.standardInput = stdin
        }
        defer { try? stdin?.close() }
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled || Date() >= deadline {
                // Foundation normally creates a process group. Terminate helpers/hooks
                // with Git, but never signal the application's own process group.
                let pid = process.processIdentifier
                let target = getpgid(pid) == pid ? -pid : pid
                kill(target, SIGTERM)
                // Ignore task cancellation only during process cleanup.
                await Task.detached {
                    let end = Date().addingTimeInterval(1)
                    while process.isRunning && Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
                    if process.isRunning { kill(target, SIGKILL) }
                    let killedDeadline = Date().addingTimeInterval(1)
                    while process.isRunning && Date() < killedDeadline { try? await Task.sleep(nanoseconds: 20_000_000) }
                }.value
                if Task.isCancelled { throw CancellationError() }
                throw GitFailure.message(L("Git 操作超时，已停止等待。请刷新状态后重试；已完成的提交不会撤销。"))
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let a = String(decoding: (try? Data(contentsOf: out)) ?? Data(), as: UTF8.self)
        let b = String(decoding: (try? Data(contentsOf: err)) ?? Data(), as: UTF8.self)
        return CommandResult(output: process.terminationStatus == 0 ? a : b + a, code: process.terminationStatus, errorOutput: b)
    }
}

actor GitEnvironment {
    static let shared = GitEnvironment()
    private var cached: String?
    private let candidatesOverride: [String]?
    init(candidates: [String]? = nil) { candidatesOverride = candidates }
    func executable(refresh: Bool = false) async throws -> String {
        if !refresh, let cached { return cached }
        cached = nil
        let candidates: [String]
        if let override = candidatesOverride { candidates = override }
        else {
            let selection = try await GitProcess.run("/usr/bin/xcode-select", arguments: ["-p"], timeout: 5)
            let developer = selection.output.trimmingCharacters(in: .whitespacesAndNewlines)
            candidates = (selection.code == 0 ? [developer + "/usr/bin/git"] : []) + ["/opt/homebrew/bin/git", "/usr/local/bin/git"]
        }
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw GitEnvironmentMissing() }
        let check = try await GitProcess.run(found, arguments: ["--version"], timeout: 5)
        guard check.code == 0, check.output.hasPrefix("git version") else { throw GitEnvironmentMissing() }
        cached = found; return found
    }
}

enum Git {
    static let executableContext = TaskLocal<String?>(wrappedValue: nil)
    static let loginContext = TaskLocal<GitLoginAttempt?>(wrappedValue: nil)
    static var loginAttempt: GitLoginAttempt? { loginContext.get() }
    static let credentialWarningContext = TaskLocal<(@Sendable (String) async -> Void)?>(wrappedValue: nil)
    static let statusContext = TaskLocal<(@Sendable (String) async -> Void)?>(wrappedValue: nil)
    static let activityContext = TaskLocal<(@Sendable (Bool) async -> Void)?>(wrappedValue: nil)
    static var remoteActivity: (@Sendable (Bool) async -> Void)? { activityContext.get() }
    static let remoteCommands = ["fetch", "pull", "push", "clone", "ls-remote"]
    static func destinations(_ root: String, _ args: [String]) async throws -> [String] {
        guard let command = args.first, remoteCommands.contains(command), !(command == "ls-remote" && args.contains("--get-url")) else { return [] }
        let positional = args.dropFirst().filter { !$0.hasPrefix("-") }
        if command == "clone" {
            guard let url = positional.first else { return [] }
            return [try await run(root, ["ls-remote", "--get-url", "--", url]).trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        var remote = positional.first
        if remote == nil {
            let branch = (try? await run(root, ["symbolic-ref", "--short", "HEAD"]))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let keys = (command == "push" ? ["branch.\(branch).pushRemote", "remote.pushDefault"] : []) + ["branch.\(branch).remote"]
            for key in keys {
                if let value = try? await run(root, ["config", "--get", key]), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { remote = value.trimmingCharacters(in: .whitespacesAndNewlines); break }
            }
            if remote == nil { remote = "origin" }
        }
        guard let remote else { return [] }
        if let urls = try? await run(root, ["remote", "get-url", "--all"] + (command == "push" ? ["--push"] : []) + [remote]) { return urls.split(separator: "\n").map(String.init) }
        return [try await run(root, ["ls-remote", "--get-url", "--", remote]).trimmingCharacters(in: .whitespacesAndNewlines)]
    }
    static func run(_ root: String, _ args: [String], environment: [String: String] = [:], input: String? = nil, literalPaths: Bool = true, account: GitAccount? = nil) async throws -> String {
        try Task.checkCancellation()
        // Each remote gets its own authentication boundary and actionable failure.
        if args.first == "fetch", args.contains("--all") {
            let names = try await run(root, ["remote"]).split(separator: "\n").map(String.init)
            var result = ""
            for name in names { result += try await run(root, args.filter { $0 != "--all" } + [name], environment: environment, literalPaths: literalPaths, account: account) }
            return result
        }
        let executable: String
        if let override = executableContext.get() { executable = override } else { executable = try await GitEnvironment.shared.executable() }
        let destinations = try await destinations(root, args)
        let host = GitRemoteFailure.loginHost(destinations)
        let attempt = host.flatMap { server in loginAttempt.flatMap { HTTPSGitServer.normalize($0.account.host) == server ? $0 : nil } }
        let effectiveAccount = account ?? attempt?.account
        let authentication = try await GitAuthentication.prepare(root, args: args, destinations: destinations, account: effectiveAccount, secret: attempt?.secret)
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"; env["GIT_EDITOR"] = "true"; env["LC_ALL"] = "C"
        env.merge(authentication.environment) { _, new in new }; env.merge(environment) { _, new in new }
        let remote = remoteCommands.contains(args.first ?? "") && !(args.first == "ls-remote" && args.contains("--get-url"))
        let result: CommandResult
        if remote { await statusContext.get()?(args.first ?? ""); await remoteActivity?(true) }
        do {
            result = try await GitProcess.run(executable, arguments: (literalPaths ? ["--literal-pathspecs"] : []) + authentication.arguments + ["-C", root] + args, environment: env, input: input, timeout: remote ? 600 : 120)
        } catch {
            if remote { await remoteActivity?(false) }
            throw error
        }
        if remote { await remoteActivity?(false) }
        guard result.code == 0 else {
            var message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let secret = authentication.secret, !secret.isEmpty { message = message.replacingOccurrences(of: secret, with: "***") }
            if remote {
                let failure = GitRemoteFailure(root: root, arguments: args, destinations: destinations, kind: GitRemoteFailure.classify(message))
                if effectiveAccount == nil, failure.canAuthenticate, let host, let remembered = AccountStore.rememberedLogin(host: host) {
                    return try await run(root, args, environment: environment, input: input, literalPaths: literalPaths, account: remembered)
                }
                throw failure
            }
            throw GitFailure.message(message)
        }
        if remote, let effectiveAccount, effectiveAccount.method == "https", let secret = authentication.secret {
            // Successful operation first, then persistence. A storage failure must
            // never turn a completed push into a failed operation that gets replayed.
            var privateSaved = true
            if attempt?.secret != nil {
                do { try AccountStore.rememberSuccessful(effectiveAccount, secret: secret) }
                catch { privateSaved = false }
            }
            do {
                try await SharedGitCredentials.approve(root: root, destinations: destinations, account: effectiveAccount, secret: secret)
            } catch {
                await credentialWarningContext.get()?(privateSaved
                    ? L("操作已成功，登录信息保留在枝序钥匙串中，但未能同步到电脑 Git 的凭据助手。其他软件可能仍需登录。")
                    : L("操作已成功，但登录信息未能保存。下次可能需要重新登录，不要重复提交。"))
            }
        }
        return result.output
    }
}

struct Project: Identifiable, Codable, Hashable {
    var id: String { path }
    let path: String
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}
struct Change: Identifiable, Hashable {
    let path: String
    let original: String?
    let index: Character
    let work: Character
    var id: String { path }
    var staged: Bool { index != " " && index != "?" }
    var unstaged: Bool { work != " " || index == "?" }
    var conflict: Bool { index == "U" || work == "U" || (index == "A" && work == "A") || (index == "D" && work == "D") }
    var paths: [String] {
        if let original, index == "R" || work == "R" { return [original, path] }
        return [path]
    }
    static func parse(_ text: String) -> [Change] {
        let records = text.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var result: [Change] = [], i = 0
        while i < records.count {
            let row = records[i]; i += 1
            guard row.count >= 4 else { continue }
            let chars = Array(row.prefix(2)); let path = String(row.dropFirst(3))
            var original: String?
            if chars.contains("R") || chars.contains("C") {
                if i < records.count { original = records[i]; i += 1 }
            }
            result.append(Change(path: path, original: original, index: chars[0], work: chars[1]))
        }
        return result
    }
}
struct Branch: Identifiable {
    let name: String
    let remote: Bool
    var unborn = false
    var lastCommit: Int64 = 0
    var id: String { (remote ? "remote:" : "local:") + name }
    static func read(_ root: String, current: String) async throws -> [Branch] {
        let output = try await Git.run(root, ["for-each-ref", "--format=%(refname)%00%(symref)%00%(committerdate:unix)", "refs/heads", "refs/remotes"])
        var result = output.split(separator: "\n").compactMap { line -> Branch? in
            let fields = line.components(separatedBy: "\0")
            guard fields.count == 3, fields[1].isEmpty else { return nil }
            let ref = fields[0]
            let remote = ref.hasPrefix("refs/remotes/")
            guard remote || ref.hasPrefix("refs/heads/"), !(remote && ref.hasSuffix("/HEAD")) else { return nil }
            let prefix = remote ? "refs/remotes/" : "refs/heads/"
            return Branch(name: String(ref.dropFirst(prefix.count)), remote: remote, lastCommit: Int64(fields[2]) ?? 0)
        }
        if current != "游离 HEAD", !result.contains(where: { !$0.remote && $0.name == current }) {
            result.append(Branch(name: current, remote: false, unborn: true))
        }
        return result.sorted { a, b in
            if a.remote != b.remote { return !a.remote }
            if !a.remote, (a.name == current) != (b.name == current) { return a.name == current }
            if a.lastCommit != b.lastCommit { return a.lastCommit > b.lastCommit }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

struct CommitEntry: Identifiable {
    let id: String
    let shortID: String
    let subject: String
    let author: String
    let date: String
    var historicalPath: String? = nil
    static func parse(_ output: String) -> [CommitEntry] {
        let fields = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        return stride(from: 0, to: max(0, fields.count - 4), by: 5).compactMap { i in
            let id = fields[i].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            return CommitEntry(id: id, shortID: fields[i + 1], subject: fields[i + 2], author: fields[i + 3], date: fields[i + 4])
        }
    }
}
struct PendingPush {
    var behind = 0
    let ids: Set<String>
    let upstream: String?
    static func read(_ root: String) async throws -> PendingPush {
        guard (try? await Git.run(root, ["rev-parse", "--verify", "HEAD"])) != nil else { return PendingPush(ids: [], upstream: nil) }
        let upstream = try? await Git.run(root, ["rev-parse", "--abbrev-ref", "@{upstream}"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let args = upstream == nil ? ["rev-list", "HEAD", "--not", "--remotes"] : ["rev-list", "@{upstream}..HEAD"]
        let output = try await Git.run(root, args)
        let behind = upstream == nil ? 0 : Int(try await Git.run(root, ["rev-list", "--count", "HEAD..@{upstream}"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return PendingPush(behind: behind, ids: Set(output.split(separator: "\n").map(String.init)), upstream: upstream)
    }
}

/// Builds an isolated index so unchecked staged files never enter this commit.
enum SelectedCommit {
    static func run(root: String, items: [Change], message: String, stagedOnly: Bool) async throws -> String? {
        let paths = Array(Set(items.flatMap(\.paths))).sorted()
        guard !paths.isEmpty else { throw GitFailure.message(L("请先勾选要提交的文件。")) }
        for ref in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD"] {
            if (try? await Git.run(root, ["rev-parse", "--verify", ref])) != nil {
                throw GitFailure.message(L("仓库正在合并、拣选或还原提交，请先完成当前操作后再按文件提交。"))
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-commit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let env = ["GIT_INDEX_FILE": directory.appendingPathComponent("index").path]
        let hasHead = (try? await Git.run(root, ["rev-parse", "--verify", "HEAD"])) != nil
        _ = try await Git.run(root, hasHead ? ["read-tree", "HEAD"] : ["read-tree", "--empty"], environment: env)
        if stagedOnly {
            let entries = try await Git.run(root, ["ls-files", "--stage", "-z", "--"] + paths)
            _ = try await Git.run(root, ["update-index", "--force-remove", "--"] + paths, environment: env)
            _ = try await Git.run(root, ["update-index", "-z", "--index-info"], environment: env, input: entries)
        } else {
            _ = try await Git.run(root, ["add", "-A", "--"] + paths, environment: env)
        }
        let included = try await Git.run(root, ["diff", "--cached", "--name-only", "--no-renames", "-z"], environment: env)
        guard !included.isEmpty else { throw GitFailure.message(L("勾选文件没有可提交的修改。")) }
        guard Set(included.split(separator: "\0").map(String.init)).isSubset(of: Set(paths)) else {
            throw GitFailure.message(L("提交范围与勾选文件不一致，已取消提交。"))
        }
        _ = try await Git.run(root, ["commit", "-m", message], environment: env)
        // Only selected entries are reconciled; unchecked partial staging remains intact.
        do {
            _ = try await Git.run(root, ["reset", "-q", "HEAD", "--"] + paths)
            return nil
        } catch {
            return L("提交已成功，但暂存区同步失败。请刷新并检查暂存状态，不要重复提交。\n\n") + error.localizedDescription
        }
    }
}

/// Compare immutable stash snapshots before restoring any tracked or untracked file.
enum StashRestore {
    enum Choice { case keep, backup, cancel }
    enum Snapshot: Equatable {
        case missing, file(Data, Bool), link(String), directory
        var summary: String {
            switch self {
            case .missing: return L("不存在")
            case .file(let data, _): return ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            case .link: return L("符号链接")
            case .directory: return L("文件夹（需要手动处理）")
            }
        }
    }
    struct Entry: Identifiable {
        var id: String { path }
        let path: String
        let source: URL
        let current: Snapshot
        let backup: Snapshot
        var differs: Bool { current != .missing && current != backup }
        var canReplace: Bool { current != .directory }
    }
    struct Plan {
        let root: String
        let oid: String
        let directory: URL
        let entries: [Entry]
        var conflicts: [Entry] { entries.filter(\.differs) }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }
    static func snapshot(_ url: URL) throws -> Snapshot {
        let fm = FileManager.default
        let attributes: [FileAttributeKey: Any]
        do { attributes = try fm.attributesOfItem(atPath: url.path) }
        catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return .missing }
            throw error
        }
        switch attributes[.type] as? FileAttributeType {
        case .typeSymbolicLink: return .link(try fm.destinationOfSymbolicLink(atPath: url.path))
        case .typeDirectory: return .directory
        case .typeRegular:
            let executable = ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o111 != 0
            return .file(try Data(contentsOf: url), executable)
        default: throw GitFailure.message(L("无法比较这个文件类型：{0}", [String(describing: url.lastPathComponent)]))
        }
    }
    static func destination(_ root: String, _ path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.lowercased() != ".git" }) else {
            throw GitFailure.message(L("备份包含不支持的路径，未恢复任何文件。"))
        }
        var parent = URL(fileURLWithPath: root)
        for part in parts.dropLast() {
            parent.appendPathComponent(String(part))
            if let attributes = try? FileManager.default.attributesOfItem(atPath: parent.path), attributes[.type] as? FileAttributeType != .typeDirectory {
                throw GitFailure.message(L("「{0}」的上级路径不是普通文件夹，请先处理该路径后重试。备份仍保留。", [String(describing: path)]))
            }
        }
        return URL(fileURLWithPath: root).appendingPathComponent(path)
    }
    static func prepare(_ root: String, oid requestedOID: String? = nil) async throws -> Plan {
        if let requestedOID {
            guard try await StashRecord.read(root).contains(where: { $0.id == requestedOID }) else {
                throw GitFailure.message(L("这条临时修改记录已不存在，请刷新列表。"))
            }
        }
        guard let oid = try? await Git.run(root, ["rev-parse", "--verify", requestedOID ?? "refs/stash"]).trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw GitFailure.message(L("没有可恢复的临时修改。"))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-restore-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let tracked = try await Git.run(root, ["diff", "--name-only", "--no-renames", "-z", oid + "^1", oid]).split(separator: "\0").map(String.init)
            let third = try? await Git.run(root, ["rev-parse", "--verify", oid + "^3"])
            let untracked = third == nil ? [] : try await Git.run(root, ["ls-tree", "-r", "-z", "--name-only", oid + "^3"]).split(separator: "\0").map(String.init)
            let allPaths = Array(Set(tracked + untracked)).sorted()
            for path in allPaths { _ = try destination(root, path) }
            let extracted = directory.appendingPathComponent("files")
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
            let env = ["GIT_INDEX_FILE": directory.appendingPathComponent("index").path]
            if !tracked.isEmpty {
                // Export only changed paths; absent paths represent deletions in the backup.
                let present = try await Git.run(root, ["ls-tree", "-r", "-z", "--name-only", oid, "--"] + tracked)
                _ = try await Git.run(root, ["read-tree", oid], environment: env)
                if !present.isEmpty {
                    _ = try await Git.run(root, ["checkout-index", "--prefix=" + extracted.path + "/", "-z", "--stdin"], environment: env, input: present)
                }
            }
            if !untracked.isEmpty {
                _ = try await Git.run(root, ["read-tree", oid + "^3"], environment: env)
                _ = try await Git.run(root, ["checkout-index", "--prefix=" + extracted.path + "/", "--all"], environment: env)
            }
            let entries = try await Task.detached(priority: .userInitiated) {
                try allPaths.map { path in
                    let source = extracted.appendingPathComponent(path)
                    return Entry(path: path, source: source, current: try snapshot(destination(root, path)), backup: try snapshot(source))
                }
            }.value
            return Plan(root: root, oid: oid, directory: directory, entries: entries)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    static func apply(_ plan: Plan, choices: [String: Choice]) async throws -> String {
        // Collect every answer before touching the working tree. Revalidate after the dialogs.
        for entry in plan.conflicts {
            guard let choice = choices[entry.path], choice != .cancel else { throw GitFailure.message(L("已取消恢复，文件和备份均保持不变。")) }
            guard choice != .backup || entry.canReplace else { throw GitFailure.message(L("不能用备份覆盖文件夹「{0}」。备份仍保留。", [String(describing: entry.path)])) }
        }
        try await Task.detached(priority: .userInitiated) {
            for entry in plan.entries {
                guard try snapshot(destination(plan.root, entry.path)) == entry.current else {
                    throw GitFailure.message(L("「{0}」在比较后发生了变化，请重新恢复并选择。尚未写入文件，备份仍保留。", [String(describing: entry.path)]))
                }
            }
        }.value
        var restored = 0, skipped = 0, kept = 0
        for entry in plan.entries {
            if entry.current == entry.backup { skipped += 1; continue }
            if entry.differs, choices[entry.path] == .keep { kept += 1; continue }
            do {
                try await Task.detached(priority: .userInitiated) {
                    let url = try destination(plan.root, entry.path)
                    guard try snapshot(url) == entry.current else { throw GitFailure.message(L("文件在恢复期间发生了变化")) }
                    if entry.backup == .missing {
                        // Only a regular file or link can reach here; directory replacement is forbidden.
                        try FileManager.default.removeItem(at: url)
                        return
                    }
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let temporary = url.deletingLastPathComponent().appendingPathComponent(".zhixu-restore-" + UUID().uuidString)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    try FileManager.default.copyItem(at: entry.source, to: temporary)
                    // rename replaces files/symlinks atomically, without following the destination link.
                    guard rename(temporary.path, url.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                }.value
                restored += 1
            } catch {
                throw GitFailure.message(L("「{0}」未能恢复，已停止后续写入。请检查变更列表；原备份仍保留。", [String(describing: entry.path)]))
            }
        }
        return L("已恢复修改 · 文件恢复 {0}，相同跳过 {1}，保留当前 {2} · 原备份保留", [String(describing: restored), String(describing: skipped), String(describing: kept)])
    }
}

/// Changes only the current local branch ref; working files and the index remain untouched.
enum LocalCommitHistory {
    static func validate(root: String, oid: String) async throws -> String {
        let head = try await Git.run(root, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard head == oid else { throw GitFailure.message(L("当前提交已变化，请刷新历史后重试。")) }
        guard let branch = try? await Git.run(root, ["symbolic-ref", "--quiet", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw GitFailure.message(L("请先切换到本地分支再操作。"))
        }
        let remote = try await Git.run(root, ["for-each-ref", "--contains=" + oid, "--format=%(refname)", "refs/remotes"])
        guard remote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitFailure.message(L("此提交已存在于已知远程分支，不能在这里撤销或改写。"))
        }
        for state in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"] {
            let path = try await Git.run(root, ["rev-parse", "--path-format=absolute", "--git-path", state]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !FileManager.default.fileExists(atPath: path) else { throw GitFailure.message(L("请先完成当前合并或变基操作。")) }
        }
        return branch
    }
    static func undo(root: String, oid: String) async throws {
        let branch = try await validate(root: root, oid: oid)
        let parents = try await Git.run(root, ["show", "-s", "--format=%P", oid]).split(whereSeparator: \.isWhitespace).map(String.init)
        _ = try await Git.run(root, ["update-ref", "ORIG_HEAD", oid])
        if let parent = parents.first {
            _ = try await Git.run(root, ["update-ref", "-m", L("枝序：撤销本地提交，保留修改"), branch, parent, oid])
        } else {
            _ = try await Git.run(root, ["update-ref", "-d", branch, oid])
        }
    }
    static func amendMessage(root: String, oid: String, message: String) async throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GitFailure.message(L("请填写提交说明。")) }
        let branch = try await validate(root: root, oid: oid)
        let tree = try await Git.run(root, ["show", "-s", "--format=%T", oid]).trimmingCharacters(in: .whitespacesAndNewlines)
        let parents = try await Git.run(root, ["show", "-s", "--format=%P", oid]).split(whereSeparator: \.isWhitespace).map(String.init)
        let author = try await Git.run(root, ["show", "-s", "--format=%an%x00%ae%x00%aI", oid]).trimmingCharacters(in: .newlines).components(separatedBy: "\0")
        guard author.count == 3 else { throw GitFailure.message(L("无法读取提交作者。")) }
        let newOID = try await Git.run(root, ["commit-tree", tree] + parents.flatMap { ["-p", $0] }, environment: ["GIT_AUTHOR_NAME": author[0], "GIT_AUTHOR_EMAIL": author[1], "GIT_AUTHOR_DATE": author[2]], input: message + "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await Git.run(root, ["update-ref", "-m", L("枝序：修改本地提交说明"), branch, newOID, oid])
    }
}

struct BranchMutation {
    let branch: Branch
    let oid: String
    let remote: String?
    let shortName: String
    static func prepare(root: String, branch: Branch) async throws -> Self {
        var remote: String?, shortName = branch.name
        if branch.remote {
            let names = try await Git.run(root, ["remote"]).split(separator: "\n").map(String.init).sorted { $0.count > $1.count }
            guard let match = names.first(where: { branch.name.hasPrefix($0 + "/") }) else { throw GitFailure.message(L("找不到这个分支所属的远程仓库，请刷新后重试。")) }
            remote = match; shortName = String(branch.name.dropFirst(match.count + 1))
            guard shortName != "HEAD" else { throw GitFailure.message(L("远程默认分支指针不能重命名或删除。")) }
        }
        let ref = (branch.remote ? "refs/remotes/" : "refs/heads/") + branch.name
        if !branch.remote && branch.unborn {
            let current = try await Git.run(root, ["symbolic-ref", "--quiet", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == ref, (try? await Git.run(root, ["rev-parse", "--verify", ref])) == nil else {
                throw GitFailure.message(L("分支已发生变化，请刷新后重试。"))
            }
            return Self(branch: branch, oid: "", remote: nil, shortName: shortName)
        }
        let oid = try await Git.run(root, ["rev-parse", "--verify", ref]).trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(branch: branch, oid: oid, remote: remote, shortName: shortName)
    }
    func apply(root: String, newName: String?) async throws {
        if let newName {
            guard !newName.hasPrefix("-"), !newName.contains("\0"), newName != shortName else { throw GitFailure.message(L("请输入不同且有效的分支名称。")) }
            _ = try await Git.run(root, ["check-ref-format", "refs/heads/" + newName])
        }
        let current = (try? await Git.run(root, ["symbolic-ref", "--quiet", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        let upstream = (try? await Git.run(root, ["for-each-ref", "--format=%(upstream)", current]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        let ref = (branch.remote ? "refs/remotes/" : "refs/heads/") + branch.name
        if newName == nil && (ref == current || (branch.remote && ref == upstream)) {
            throw GitFailure.message(L("不能删除当前分支或当前分支正在跟踪的远程分支，请先切换分支。"))
        }
        if !branch.remote && branch.unborn {
            guard let newName, current == ref,
                  (try? await Git.run(root, ["rev-parse", "--verify", ref])) == nil else {
                throw GitFailure.message(L("分支已发生变化，请刷新后重试。"))
            }
            // Git renames the unborn HEAD and its branch configuration without touching files or the index.
            _ = try await Git.run(root, ["branch", "-m", "--", shortName, newName])
            return
        }
        let latest = try await Git.run(root, ["rev-parse", "--verify", ref]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard latest == oid else { throw GitFailure.message(L("分支已发生变化，请刷新后重试。")) }
        if let remote {
            let oldRef = "refs/heads/" + shortName
            var args = ["push", "--atomic", "--force-with-lease=\(oldRef):\(oid)"]
            if let newName {
                let newRef = "refs/heads/" + newName
                // Git can treat an identical existing destination as up-to-date, bypassing its lease.
                let existing = try await Git.run(root, ["ls-remote", "--refs", "--", remote, newRef])
                guard existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw GitFailure.message(L("远程操作未完成：新分支名称已存在，请换一个名称。"))
                }
                args += ["--force-with-lease=\(newRef):", "--", remote, "\(oid):\(newRef)", ":" + oldRef]
            } else { args += ["--", remote, ":" + oldRef] }
            do { _ = try await Git.run(root, args) }
            catch { throw GitFailure.message(L("远程操作未完成。远程分支可能已更新、名称已存在、分支受保护，或服务器不支持原子操作。请获取最新状态后重试。\n\n") + error.localizedDescription) }
            // Explicit refs also work with custom fetch mappings; keep other tracking branches intact.
            _ = try? await Git.run(root, ["update-ref", "-d", ref, oid])
            if let newName {
                let newTracking = "refs/remotes/" + remote + "/" + newName
                _ = try? await Git.run(root, ["update-ref", newTracking, oid, String(repeating: "0", count: oid.count)])
                let locals = try await Git.run(root, ["for-each-ref", "--format=%(refname:strip=2)%00%(upstream)", "refs/heads"])
                // push may prune the old tracking ref, but upstream configuration still names it.
                for line in locals.split(separator: "\n") {
                    let fields = line.components(separatedBy: "\0")
                    guard fields.count == 2, fields[1] == ref else { continue }
                    _ = try await Git.run(root, ["config", "branch." + fields[0] + ".merge", "refs/heads/" + newName])
                }
            }
        } else if let newName {
            _ = try await Git.run(root, ["branch", "-m", "--", shortName, newName])
        } else {
            do { _ = try await Git.run(root, ["branch", "-d", "--", shortName]) }
            catch { throw GitFailure.message(L("未删除分支：它可能包含未合并的提交，或正被其他工作区使用。请先合并或切换后重试。\n\n") + error.localizedDescription) }
        }
    }
}

/// Filesystem actions stay inside the workspace and never overwrite an existing item.
enum ExplorerFiles {
    static func url(_ path: String, root: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !parts.contains(".."), !parts.contains(".git"), !parts.contains(""), !parts.contains("."), !path.contains("\0") else {
            throw GitFailure.message(L("请输入项目内的有效名称，不能包含 .. 或 .git。"))
        }
        let base = URL(fileURLWithPath: root).resolvingSymlinksInPath()
        let result = base.appendingPathComponent(path)
        guard result.deletingLastPathComponent().resolvingSymlinksInPath().path.hasPrefix(base.path + "/") || result.deletingLastPathComponent().resolvingSymlinksInPath() == base else {
            throw GitFailure.message(L("不能操作项目外的路径。"))
        }
        return result
    }
    static func create(root: String, path: String, folder: Bool) throws {
        let target = try url(path, root: root)
        guard (try? target.resourceValues(forKeys: [.isSymbolicLinkKey])) == nil else { throw GitFailure.message(L("同名文件或文件夹已存在。")) }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if folder { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
        else { try Data().write(to: target, options: .withoutOverwriting) }
    }
    static func paste(root: String, source: String, directory: String, move: Bool) throws -> String {
        let from = try url(source, root: root)
        let name = from.lastPathComponent
        func child(_ name: String) -> String { directory.isEmpty ? name : directory + "/" + name }
        var destination = child(name)
        if move && destination == source { return source }
        if !move, (try? url(destination, root: root).resourceValues(forKeys: [.isSymbolicLinkKey])) != nil {
            let isFolder = (try? from.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map { $0.isDirectory == true && $0.isSymbolicLink != true } ?? false
            let ext = isFolder ? "" : (name as NSString).pathExtension
            let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
            var number = 1
            repeat {
                let suffix = number == 1 ? L(" 副本") : L(" 副本 {0}", [String(describing: number)])
                destination = child(stem + suffix + (ext.isEmpty ? "" : "." + ext))
                number += 1
            } while (try? url(destination, root: root).resourceValues(forKeys: [.isSymbolicLinkKey])) != nil
        }
        try transfer(root: root, source: source, destination: destination, move: move)
        return destination
    }
    static func transfer(root: String, source: String, destination: String, move: Bool) throws {
        let from = try url(source, root: root), to = try url(destination, root: root)
        guard destination != source, !destination.hasPrefix(source + "/") else { throw GitFailure.message(L("不能放入自身或自身的子文件夹。")) }
        guard (try? to.resourceValues(forKeys: [.isSymbolicLinkKey])) == nil else { throw GitFailure.message(L("目标位置已有同名文件或文件夹，请先重命名。")) }
        if move { try FileManager.default.moveItem(at: from, to: to) }
        else { try FileManager.default.copyItem(at: from, to: to) }
    }
}

struct DiscardFilePlan {
    let root: String
    let change: Change
    let head: String?
    let index: String
    let snapshots: [String: StashRestore.Snapshot]
    let committedPaths: Set<String>
    var removesNewFile: Bool { !committedPaths.contains(change.path) }

    static func prepare(root: String, change: Change) async throws -> Self {
        guard !change.conflict else { throw GitFailure.message(L("此文件有合并冲突，请先解决冲突。")) }
        let current = Change.parse(try await Git.run(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]))
        guard current.contains(change) else { throw GitFailure.message(L("文件状态已变化，请刷新后重试。")) }
        let head = try? await Git.run(root, ["rev-parse", "--verify", "HEAD"])
        let index = try await Git.run(root, ["ls-files", "--stage", "-z", "--"] + change.paths)
        let tree = head == nil ? "" : try await Git.run(root, ["ls-tree", "-z", "HEAD", "--"] + change.paths)
        guard !tree.split(separator: "\0").contains(where: { $0.hasPrefix("160000 ") }),
              !index.split(separator: "\0").contains(where: { $0.hasPrefix("160000 ") }) else {
            throw GitFailure.message(L("子模块的更改请进入子模块项目处理。"))
        }
        let committed = Set(tree.split(separator: "\0").compactMap { row -> String? in
            guard let tab = row.firstIndex(of: "\t") else { return nil }
            return String(row[row.index(after: tab)...])
        })
        let snapshots = try await Task.detached {
            var result: [String: StashRestore.Snapshot] = [:]
            for path in change.paths {
                let url = try StashRestore.destination(root, path)
                let snapshot = try StashRestore.snapshot(url)
                guard snapshot != .directory else { throw GitFailure.message(L("该路径当前是文件夹，请先检查目录内容，未撤销任何更改。")) }
                result[path] = snapshot
            }
            return result
        }.value
        return Self(root: root, change: change, head: head, index: index, snapshots: snapshots, committedPaths: committed)
    }
    func validate() async throws {
        let current = try await Self.prepare(root: root, change: change)
        guard current.head == head, current.index == index, current.snapshots == snapshots else {
            throw GitFailure.message(L("确认期间文件或分支发生了变化，未撤销更改，请重新检查。"))
        }
    }
    func apply(trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) async throws {
        try await validate()
        // New files have no committed version: retain them in Trash before removing their index entry.
        for path in change.paths where !committedPaths.contains(path) {
            if snapshots[path] != .missing {
                try await Task.detached {
                    try trash(StashRestore.destination(root, path))
                }.value
            }
            _ = try await Git.run(root, ["update-index", "--force-remove", "--", path])
        }
        if !committedPaths.isEmpty {
            _ = try await Git.run(root, ["restore", "--source=HEAD", "--staged", "--worktree", "--"] + committedPaths.sorted())
        }
    }
}

/// Captures exactly the changes shown at confirmation time; never expands to newly appearing files.
struct DiscardChangesPlan {
    let root: String
    let files: [DiscardFilePlan]
    let all: Bool
    static func prepare(root: String, changes: [Change], all: Bool) async throws -> Self {
        guard !changes.isEmpty else { throw GitFailure.message(L("没有可撤销的更改。")) }
        var files: [DiscardFilePlan] = []
        for change in changes { files.append(try await DiscardFilePlan.prepare(root: root, change: change)) }
        let plan = Self(root: root, files: files, all: all)
        try await plan.validate()
        return plan
    }
    func validate() async throws {
        if all {
            let current = Change.parse(try await Git.run(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]))
            guard Set(current) == Set(files.map(\.change)) else {
                throw GitFailure.message(L("变更列表已变化，请刷新并重新确认，未撤销任何更改。"))
            }
        }
        for file in files { try await file.validate() }
    }
}

struct StashRecord: Identifiable, Equatable {
    let id: String
    let reference: String
    let branch: String
    let date: Date
    let message: String
    static func read(_ root: String) async throws -> [Self] {
        let output = try await Git.run(root, ["stash", "list", "--format=%H%x00%gd%x00%ct%x00%gs"])
        return output.split(separator: "\n").compactMap { row -> Self? in
            let fields = row.components(separatedBy: "\0")
            guard fields.count == 4, let timestamp = Double(fields[2]) else { return nil }
            let subject = fields[3]
            let prefix = subject.hasPrefix("On ") ? "On " : subject.hasPrefix("WIP on ") ? "WIP on " : ""
            let body = String(subject.dropFirst(prefix.count))
            let separator = body.range(of: ": ")
            let branch = !prefix.isEmpty ? separator.map { String(body[..<$0.lowerBound]) } ?? L("未知分支") : L("未知分支")
            let message = separator.map { String(body[$0.upperBound...]) } ?? subject
            return Self(id: fields[0], reference: fields[1], branch: branch, date: Date(timeIntervalSince1970: timestamp), message: message)
        }.sorted { $0.date > $1.date }
    }
    func delete(_ root: String) async throws {
        // Stash indexes shift whenever another record is added or removed; resolve the selected OID again.
        guard let current = try await Self.read(root).first(where: { $0.id == id }) else {
            throw GitFailure.message(L("这条临时修改记录已不存在，请刷新列表。"))
        }
        _ = try await Git.run(root, ["stash", "drop", current.reference])
    }
    func deletingFile(_ root: String, file: File) async throws -> String {
        guard try await Self.read(root).contains(where: { $0.id == id }),
              try await files(root).contains(file) else {
            throw GitFailure.message(L("备份记录或文件已变化，请刷新列表。"))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-stash-edit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let env = ["GIT_INDEX_FILE": directory.appendingPathComponent("index").path]
        let base = try await Git.run(root, ["rev-parse", id + "^1"]).trimmingCharacters(in: .whitespacesAndNewlines)
        func editedTree(_ commit: String, restoreBase: Bool) async throws -> String {
            _ = try await Git.run(root, ["read-tree", commit], environment: env)
            let original = restoreBase ? try await Git.run(root, ["ls-tree", "-z", base, "--", file.path]) : ""
            if let row = original.split(separator: "\0").first, let tab = row.firstIndex(of: "\t") {
                let fields = row[..<tab].split(separator: " ")
                guard fields.count == 3 else { throw GitFailure.message(L("无法读取文件的原版本。")) }
                _ = try await Git.run(root, ["update-index", "--add", "--cacheinfo", String(fields[0]), String(fields[2]), file.path], environment: env)
            } else {
                _ = try await Git.run(root, ["update-index", "--force-remove", "--", file.path], environment: env)
            }
            return try await Git.run(root, ["write-tree"], environment: env).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func commit(_ original: String, tree: String, parents: [String]) async throws -> String {
            let metadata = try await Git.run(root, ["show", "-s", "--format=%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI", original]).trimmingCharacters(in: .newlines).components(separatedBy: "\0")
            guard metadata.count == 6 else { throw GitFailure.message(L("无法读取备份信息。")) }
            let identity = ["GIT_AUTHOR_NAME": metadata[0], "GIT_AUTHOR_EMAIL": metadata[1], "GIT_AUTHOR_DATE": metadata[2], "GIT_COMMITTER_NAME": metadata[3], "GIT_COMMITTER_EMAIL": metadata[4], "GIT_COMMITTER_DATE": metadata[5]]
            let message = try await Git.run(root, ["show", "-s", "--format=%B", original])
            return try await Git.run(root, ["commit-tree", tree] + parents.flatMap { ["-p", $0] }, environment: identity, input: message).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let oldIndex = try await Git.run(root, ["rev-parse", id + "^2"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let index = file.untracked ? oldIndex : try await commit(oldIndex, tree: editedTree(oldIndex, restoreBase: true), parents: [base])
        var parents = [base, index]
        if let third = try? await Git.run(root, ["rev-parse", "--verify", id + "^3"]).trimmingCharacters(in: .whitespacesAndNewlines) {
            parents.append(file.untracked ? try await commit(third, tree: editedTree(third, restoreBase: false), parents: []) : third)
        }
        let tree = file.untracked ? try await Git.run(root, ["rev-parse", id + "^{tree}"]).trimmingCharacters(in: .whitespacesAndNewlines) : try await editedTree(id, restoreBase: true)
        let replacement = try await commit(id, tree: tree, parents: parents)
        guard try await Self.read(root).contains(where: { $0.id == id }) else {
            throw GitFailure.message(L("备份记录已被删除，未更新列表。"))
        }
        let subject = try await Git.run(root, ["show", "-s", "--format=%s", id]).trimmingCharacters(in: .newlines)
        // Save the replacement before dropping the original so a failure cannot lose the other files.
        _ = try await Git.run(root, ["stash", "store", "-m", subject, replacement])
        do { try await delete(root) }
        catch { throw GitFailure.message(L("已保存更新后的备份，但旧记录未能移除；两条记录都保留，请刷新列表检查。")) }
        return replacement
    }
    struct File: Identifiable, Equatable {
        let path: String
        let untracked: Bool
        var id: String { path }
    }
    func files(_ root: String) async throws -> [File] {
        let tracked = try await Git.run(root, ["diff", "--name-only", "--no-renames", "-z", id + "^1", id]).split(separator: "\0").map(String.init)
        let third = try? await Git.run(root, ["rev-parse", "--verify", id + "^3"])
        let new = third == nil ? [] : try await Git.run(root, ["ls-tree", "-r", "--name-only", "-z", id + "^3"]).split(separator: "\0").map(String.init)
        return (tracked.map { File(path: $0, untracked: false) } + new.map { File(path: $0, untracked: true) }).sorted { $0.path < $1.path }
    }
    func preview(_ root: String, file: File) async throws -> String {
        if file.untracked { return try await Git.run(root, ["show", id + "^3:" + file.path]) }
        return try await Git.run(root, ["diff", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames", "--unified=10000", id + "^1", id, "--", file.path])
    }
}

/// Shared operations for history review, integration and conflict resolution.
enum GitTools {
    struct ReviewFile: Identifiable, Equatable {
        let path: String
        let status: String
        var id: String { path }
    }
    struct Review {
        let title: String
        let base: String
        let target: String
        let files: [ReviewFile]
        let commits: [CommitEntry]
        var currentOnly: [CommitEntry] = []
    }
    static let logFormat = "%H%x00%h%x00%s%x00%an%x00%ad%x00"
    static func oid(_ root: String, _ ref: String) async throws -> String {
        try await Git.run(root, ["rev-parse", "--verify", ref + "^{commit}"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func operation(_ root: String) async throws -> String? {
        for (file, kind) in [("rebase-merge", "rebase"), ("rebase-apply", "rebase"), ("MERGE_HEAD", "merge"), ("REVERT_HEAD", "revert"), ("CHERRY_PICK_HEAD", "cherry-pick")] {
            let path = try await Git.run(root, ["rev-parse", "--path-format=absolute", "--git-path", file]).trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.fileExists(atPath: path) { return kind }
        }
        return nil
    }
    static func requireClean(_ root: String) async throws {
        guard try await operation(root) == nil else { throw GitFailure.message(L("请先完成或中止正在进行的 Git 操作。")) }
        guard try await Git.run(root, ["status", "--porcelain=v1", "--untracked-files=all"]).isEmpty else {
            throw GitFailure.message(L("请先提交或临时收起当前修改，再执行此操作。"))
        }
    }
    static func changedFiles(_ root: String, base: String, target: String) async throws -> [ReviewFile] {
        let output = try await Git.run(root, ["diff", "--name-status", "--no-renames", "-z", base, target])
        let fields = output.split(separator: "\0").map(String.init)
        return stride(from: 0, to: max(0, fields.count - 1), by: 2).map { ReviewFile(path: fields[$0 + 1], status: fields[$0]) }
    }
    static func commitReview(_ root: String, ref: String) async throws -> Review {
        let target = try await oid(root, ref)
        let parents = try await Git.run(root, ["show", "-s", "--format=%P", target]).split(whereSeparator: \.isWhitespace).map(String.init)
        let base: String
        if let first = parents.first { base = first }
        else { base = try await Git.run(root, ["hash-object", "-w", "-t", "tree", "--stdin"], input: "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let title = try await Git.run(root, ["show", "-s", "--format=%h · %s", target]).trimmingCharacters(in: .newlines)
        return Review(title: title + (parents.count > 1 ? L("（相对第一父提交）") : ""), base: base, target: target, files: try await changedFiles(root, base: base, target: target), commits: [])
    }
    static func compare(_ root: String, ref: String) async throws -> Review {
        let base = try await oid(root, "HEAD"), target = try await oid(root, ref)
        let log = try await Git.run(root, ["log", "--date=short", "--format=" + logFormat, base + ".." + target])
        let currentLog = try await Git.run(root, ["log", "--date=short", "--format=" + logFormat, target + ".." + base])
        return Review(title: L("当前分支 → ") + ref, base: base, target: target, files: try await changedFiles(root, base: base, target: target), commits: CommitEntry.parse(log), currentOnly: CommitEntry.parse(currentLog))
    }
    static func patch(_ root: String, review: Review, path: String) async throws -> String {
        try await Git.run(root, ["diff", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames", "--unified=10000", review.base, review.target, "--", path])
    }
    static func fileHistory(_ root: String, path: String, page: Int) async throws -> [CommitEntry] {
        guard (try? await oid(root, "HEAD")) != nil else { return [] }
        // Walk rename metadata from the newest commit, including the preceding pages, to retain the path at each revision.
        let output = try await Git.run(root, ["log", "--follow", "--name-status", "-z", "--date=short", "--format=" + logFormat, "--max-count=\((page + 1) * 50 + 1)", "HEAD", "--", path])
        let tokens = output.components(separatedBy: "\0")
        func isOID(_ value: String) -> Bool { (value.count == 40 || value.count == 64) && value.allSatisfy { $0.isHexDigit } }
        var i = 0, currentPath = path, entries: [CommitEntry] = []
        while i + 4 < tokens.count {
            let id = tokens[i].trimmingCharacters(in: .whitespacesAndNewlines)
            guard isOID(id) else { i += 1; continue }
            var entry = CommitEntry(id: id, shortID: tokens[i + 1], subject: tokens[i + 2], author: tokens[i + 3], date: tokens[i + 4])
            entry.historicalPath = currentPath; i += 5
            while i < tokens.count {
                let status = tokens[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if isOID(status) { break }
                if status.isEmpty { i += 1; continue }
                if status.hasPrefix("R"), i + 2 < tokens.count {
                    let old = tokens[i + 1], new = tokens[i + 2]
                    if new == currentPath { currentPath = old }
                    i += 3
                } else { i += 2 }
            }
            entries.append(entry)
        }
        return Array(entries.dropFirst(page * 50).prefix(51))
    }
    static func integrate(_ root: String, ref: String, expectedHead: String, revert: Bool = false, expectedBranch: String? = nil) async throws {
        try await requireClean(root)
        if let expectedBranch {
            guard try await Git.run(root, ["rev-parse", "--symbolic-full-name", "HEAD"]) == expectedBranch else { throw GitFailure.message(L("当前分支已切换，请重新确认。")) }
        }
        guard try await oid(root, "HEAD") == expectedHead else { throw GitFailure.message(L("当前分支已变化，请重新确认。")) }
        let target = try await oid(root, ref)
        if revert {
            let parents = try await Git.run(root, ["show", "-s", "--format=%P", target]).split(whereSeparator: \.isWhitespace)
            _ = try await Git.run(root, ["revert", "--no-edit"] + (parents.count > 1 ? ["-m", "1"] : []) + [target])
        } else { _ = try await Git.run(root, ["merge", "--no-edit", target]) }
    }
    static func continueOperation(_ root: String) async throws {
        guard let kind = try await operation(root) else { throw GitFailure.message(L("当前没有需要继续的操作。")) }
        guard try await Git.run(root, ["ls-files", "--unmerged"]).isEmpty else { throw GitFailure.message(L("还有未解决的冲突，请先处理并标记已解决。")) }
        _ = try await Git.run(root, kind == "merge" ? ["commit", "--no-edit"] : [kind, "--continue"])
    }
    static func abortOperation(_ root: String, expected: String) async throws {
        guard try await operation(root) == expected else { throw GitFailure.message(L("操作状态已变化，请刷新后重试。")) }
        _ = try await Git.run(root, [expected, "--abort"])
    }
    struct FileRestore {
        let root: String
        let path: String
        let target: String
        let sourcePath: String
        let current: StashRestore.Snapshot
        let head: String
        let index: String
        static func prepare(_ root: String, path: String, ref: String, sourcePath: String? = nil) async throws -> Self {
            guard try await GitTools.operation(root) == nil else { throw GitFailure.message(L("请先完成当前 Git 操作。")) }
            let target = try await GitTools.oid(root, ref)
            let url = try StashRestore.destination(root, path)
            let snapshot = try StashRestore.snapshot(url)
            guard snapshot != .directory else { throw GitFailure.message(L("不能用历史文件替换目录。")) }
            return Self(root: root, path: path, target: target, sourcePath: sourcePath ?? path, current: snapshot, head: try await GitTools.oid(root, "HEAD"), index: try await Git.run(root, ["ls-files", "--stage", "--", path]))
        }
        func apply() async throws {
            let latest = try await Self.prepare(root, path: path, ref: target, sourcePath: sourcePath)
            guard latest.current == current, latest.head == head, latest.index == index else { throw GitFailure.message(L("文件或分支已变化，请重新确认恢复。")) }
            let tree = try await Git.run(root, ["ls-tree", "-z", target, "--", sourcePath])
            if tree.isEmpty {
                if current != .missing { try FileManager.default.trashItem(at: StashRestore.destination(root, path), resultingItemURL: nil) }
            } else {
                guard !tree.hasPrefix("160000 ") else { throw GitFailure.message(L("请进入子模块处理历史版本。")) }
                if sourcePath == path {
                    _ = try await Git.run(root, ["restore", "--source=" + target, "--worktree", "--", path])
                } else {
                    _ = try StashRestore.destination(root, sourcePath)
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-file-version-" + UUID().uuidString)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let env = ["GIT_INDEX_FILE": directory.appendingPathComponent("index").path]
                    _ = try await Git.run(root, ["read-tree", target], environment: env)
                    _ = try await Git.run(root, ["checkout-index", "--prefix=" + directory.path + "/", "--", sourcePath], environment: env)
                    let destination = try StashRestore.destination(root, path)
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let temporary = destination.deletingLastPathComponent().appendingPathComponent(".zhixu-history-" + UUID().uuidString)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    try FileManager.default.copyItem(at: directory.appendingPathComponent(sourcePath), to: temporary)
                    guard try StashRestore.snapshot(destination) == current else { throw GitFailure.message(L("文件已变化，未覆盖。")) }
                    guard rename(temporary.path, destination.path) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                }
            }
        }
    }
    enum IgnoreKind { case file, folder, suffix }
    static func ignorePattern(path: String, kind: IgnoreKind) throws -> String {
        guard !path.isEmpty, !path.contains("\n"), !path.contains("\r") else { throw GitFailure.message(L("此路径不能写入忽略规则。")) }
        func escape(_ input: String) -> String {
            var output = ""
            for c in input { if "\\*?[]!# ".contains(c) { output.append("\\") }; output.append(c) }
            return output
        }
        switch kind {
        case .file: return "/" + escape(path)
        case .folder: return "/" + escape(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) + "/"
        case .suffix:
            let ext = (path as NSString).pathExtension
            guard !ext.isEmpty else { throw GitFailure.message(L("此文件没有扩展名，请选择忽略此文件。")) }
            return "*." + escape(ext)
        }
    }
    static func ignore(_ root: String, path: String, kind: IgnoreKind) throws {
        _ = try StashRestore.destination(root, path)
        let url = try StashRestore.destination(root, ".gitignore")
        let snapshot = try StashRestore.snapshot(url)
        guard snapshot == .missing || { if case .file = snapshot { return true }; return false }() else { throw GitFailure.message(L(".gitignore 不是普通文件，未修改。")) }
        let original = snapshot == .missing ? "" : try String(contentsOf: url, encoding: .utf8)
        let rule = try ignorePattern(path: path, kind: kind)
        if original.components(separatedBy: "\n").contains(rule) { return }
        try (original + (original.isEmpty || original.hasSuffix("\n") ? "" : "\n") + rule + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

struct GitConflict {
    let root: String
    let path: String
    let index: String
    let current: StashRestore.Snapshot
    let ours: StashRestore.Snapshot
    let theirs: StashRestore.Snapshot
    static func text(_ snapshot: StashRestore.Snapshot) -> String? {
        if snapshot == .missing { return "" }
        if case .file(let data, _) = snapshot, data.count <= 2_000_000, !data.contains(0) { return String(data: data, encoding: .utf8) }
        return nil
    }
    static func read(_ root: String, path: String) async throws -> Self {
        let url = try StashRestore.destination(root, path)
        let index = try await Git.run(root, ["ls-files", "--unmerged", "-z", "--", path])
        guard !index.isEmpty else { throw GitFailure.message(L("此文件已不再存在冲突。")) }
        guard !index.split(separator: "\0").contains(where: { $0.hasPrefix("160000 ") }) else { throw GitFailure.message(L("子模块冲突请进入子模块处理。")) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zhixu-conflict-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func side(_ stage: Int) async throws -> StashRestore.Snapshot {
            guard index.split(separator: "\0").contains(where: { $0.split(separator: "\t")[0].hasSuffix(" \(stage)") }) else { return .missing }
            _ = try await Git.run(root, ["checkout-index", "--stage=\(stage)", "--prefix=" + directory.path + "/", "--force", "--", path])
            return try StashRestore.snapshot(directory.appendingPathComponent(path))
        }
        return Self(root: root, path: path, index: index, current: try StashRestore.snapshot(url), ours: try await side(2), theirs: try await side(3))
    }
    enum Resolution { case text(String), ours, theirs }
    func save(_ resolution: Resolution) async throws {
        let url = try StashRestore.destination(root, path)
        guard try await Git.run(root, ["ls-files", "--unmerged", "-z", "--", path]) == index,
              try StashRestore.snapshot(url) == current else { throw GitFailure.message(L("文件或冲突状态已变化，请重新打开冲突编辑器。")) }
        let snapshot: StashRestore.Snapshot
        switch resolution {
        case .ours: snapshot = ours
        case .theirs: snapshot = theirs
        case .text(let text):
            guard !text.components(separatedBy: "\n").contains(where: { $0.hasPrefix("<<<<<<< ") || $0.hasPrefix(">>>>>>> ") || $0 == "=======" }) else { throw GitFailure.message(L("仍有冲突标记，请处理完所有冲突块。")) }
            let executable: Bool
            if case .file(_, let value) = current { executable = value } else { executable = false }
            snapshot = .file(Data(text.utf8), executable)
        }
        guard current != .directory else { throw GitFailure.message(L("当前路径是目录，未覆盖。")) }
        if snapshot == .missing {
            if current != .missing { try FileManager.default.removeItem(at: url) }
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if case .link(let target) = snapshot {
                if current != .missing { try FileManager.default.removeItem(at: url) }
                try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
            } else if case .file(let data, let executable) = snapshot {
                if case .link = current { try FileManager.default.removeItem(at: url) }
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
            }
        }
        _ = try await Git.run(root, ["add", "-A", "--", path])
    }
}

/// Only remote commands produce this error; local Git errors retain their existing handling.
struct GitRemoteFailure: LocalizedError, Identifiable {
    enum Kind { case authentication, permission, network, repository, rejected, other }
    let id = UUID()
    let root: String
    let arguments: [String]
    let destinations: [String]
    let kind: Kind
    var errorDescription: String? { message }
    static func classify(_ output: String) -> Kind {
        let s = output.lowercased()
        if ["could not resolve", "failed to connect", "connection timed out", "connection refused", "network is unreachable", "connection reset", "ssl certificate", "proxy", "host key verification failed"].contains(where: s.contains) { return .network }
        if ["permission to", "write access", "not allowed to push", "protected branch", "403"].contains(where: s.contains) { return .permission }
        if ["authentication failed", "could not read username", "could not read password", "terminal prompts disabled", "invalid username or", "permission denied (publickey", "401", "invalid credentials", "http basic: access denied"].contains(where: s.contains) { return .authentication }
        if ["repository not found", "does not appear to be a git repository", "not found", "could not read from remote repository"].contains(where: s.contains) { return .repository }
        if ["non-fast-forward", "fetch first", "[rejected]"].contains(where: s.contains) { return .rejected }
        return .other
    }
    static func loginHost(_ destinations: [String]) -> String? {
        guard !destinations.isEmpty else { return nil }
        let servers = destinations.compactMap(HTTPSGitServer.key)
        guard servers.count == destinations.count, let server = servers.first,
              servers.allSatisfy({ $0 == server }) else { return nil }
        return server
    }
    var loginServer: String? { Self.loginHost(destinations) }
    var canAuthenticate: Bool { loginServer != nil && [.authentication, .permission, .repository].contains(kind) }
    var canLogin: Bool { canAuthenticate && loginServer == "github.com" }
    var canPasswordLogin: Bool { canAuthenticate && loginServer != "github.com" }
    var title: String {
        switch kind {
        case .authentication: return L("需要登录远程仓库")
        case .permission: return L("当前账号没有操作权限")
        case .network: return L("无法连接远程仓库")
        case .repository: return L("无法访问此仓库")
        case .rejected: return L("远程拒绝了这次推送")
        case .other: return L("远程操作未完成")
        }
    }
    var message: String {
        switch kind {
        case .authentication: return canPasswordLogin ? L("请输入有权访问此仓库的账号和密码，登录后将自动继续。") : canLogin ? L("电脑已有认证不可用或已过期。登录 GitHub 后将自动继续。") : L("电脑已有认证不可用或已过期。请登录有权访问仓库的账号，再重试。SSH 地址请检查电脑上的 SSH 配置。")
        case .permission: return L("请确认当前账号有此仓库的操作权限；分支保护规则也可能禁止直接推送。可切换有权限的账号后重试。")
        case .network: return L("请检查网络、代理和服务器连接；使用 SSH 时也请检查主机信任配置。连接恢复后可重试，无需切换账号。")
        case .repository: return L("仓库地址可能不正确、仓库已删除，或当前账号无权查看私有仓库。请检查地址与账号权限。")
        case .rejected: return L("远程分支可能已有新提交。请先获取、拉取并处理分叉，再推送；本地提交仍然保留。")
        case .other: return L("远程服务器未能完成请求。请检查仓库设置和服务状态后重试；本地提交仍然保留。")
        }
    }
}


/// Settings edits the selected remote, including repositories that do not use origin.
enum GitSettingsRemote {
    struct Entry: Identifiable, Sendable {
        let name: String
        let url: String
        var id: String { name }
    }
    static func list(_ root: String) async throws -> [Entry] {
        let names = try await Git.run(root, ["remote"]).split(separator: "\n").map(String.init)
        var result: [Entry] = []
        for name in names {
            let url = try await Git.run(root, ["remote", "get-url", name]).trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(Entry(name: name, url: url))
        }
        return result
    }
    static func current(_ root: String) async -> (name: String, url: String) {
        func read(_ args: [String]) async -> String {
            ((try? await Git.run(root, args)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let remotes = await read(["remote"]).split(separator: "\n").map(String.init)
        let branch = await read(["symbolic-ref", "--quiet", "--short", "HEAD"])
        let tracked = branch.isEmpty ? "" : await read(["config", "branch.\(branch).remote"])
        let name = remotes.contains(tracked) ? tracked : (remotes.contains("origin") ? "origin" : remotes.first ?? "origin")
        return (name, remotes.contains(name) ? await read(["remote", "get-url", name]) : "")
    }

    static func save(_ root: String, name: String, url: String) async throws {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        let remotes = try await Git.run(root, ["remote"]).split(separator: "\n").map(String.init)
        _ = try await Git.run(root, remotes.contains(name) ? ["remote", "set-url", name, url] : ["remote", "add", name, url])
    }
}

struct GitPushPlan: Sendable {
    struct Target: Identifiable, Sendable {
        let name: String
        let urls: [String]
        let branch: String
        var id: String { name }
    }
    let root: String
    let branch: String
    let targets: [Target]
    let defaultRemote: String
    let hasUpstream: Bool

    static func prepare(_ root: String) async throws -> GitPushPlan {
        func read(_ args: [String]) async -> String {
            ((try? await Git.run(root, args)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let branch = await read(["symbolic-ref", "--quiet", "--short", "HEAD"])
        guard !branch.isEmpty else { throw GitFailure.message(L("请先切换到本地分支，再推送。")) }
        let names = try await Git.run(root, ["remote"]).split(separator: "\n").map(String.init)
        guard !names.isEmpty else { throw GitFailure.message(L("尚未配置远程仓库，请先在设置中填写远程地址。")) }
        let upstreamRemote = await read(["config", "branch.\(branch).remote"])
        let merge = await read(["config", "branch.\(branch).merge"])
        var preferred = ""
        for key in ["branch.\(branch).pushRemote", "remote.pushDefault", "branch.\(branch).remote"] {
            let value = await read(["config", key])
            if names.contains(value) { preferred = value; break }
        }
        if preferred.isEmpty { preferred = names.contains("origin") ? "origin" : names[0] }
        var targets: [Target] = []
        for name in names {
            let urls = try await Git.run(root, ["remote", "get-url", "--push", "--all", name]).split(separator: "\n").map(String.init)
            let targetBranch = name == upstreamRemote && merge.hasPrefix("refs/heads/") ? String(merge.dropFirst("refs/heads/".count)) : branch
            targets.append(Target(name: name, urls: urls, branch: targetBranch))
        }
        return GitPushPlan(root: root, branch: branch, targets: targets, defaultRemote: preferred, hasUpstream: !upstreamRemote.isEmpty && !merge.isEmpty)
    }
    func arguments(remote: String) throws -> [String] {
        guard let target = targets.first(where: { $0.name == remote }) else { throw GitFailure.message(L("远程仓库已变化，请重新选择。")) }
        return ["push", "--no-follow-tags"] + (hasUpstream ? [] : ["--set-upstream"]) + ["--", target.name, "HEAD:refs/heads/" + target.branch]
    }
    func validate(remote: String) async throws {
        let current = try await Git.run(root, ["symbolic-ref", "--short", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard current == branch else { throw GitFailure.message(L("当前分支已变化，请重新选择推送目标。")) }
        let fresh = try await Self.prepare(root)
        guard let before = targets.first(where: { $0.name == remote }),
              let after = fresh.targets.first(where: { $0.name == remote }),
              before.urls == after.urls, before.branch == after.branch, hasUpstream == fresh.hasUpstream else {
            throw GitFailure.message(L("远程仓库已变化，请重新选择。"))
        }
    }
}

struct GitPullPlan: Sendable {
    let root: String
    let branch: String
    let targets: [GitPushPlan.Target]
    let defaultRemote: String
    static func prepare(_ root: String) async throws -> GitPullPlan {
        func read(_ args: [String]) async -> String {
            ((try? await Git.run(root, args)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let branch = await read(["symbolic-ref", "--quiet", "--short", "HEAD"])
        guard !branch.isEmpty else { throw GitFailure.message(L("请先切换到本地分支，再拉取。")) }
        let remotes = try await GitSettingsRemote.list(root)
        guard !remotes.isEmpty else { throw GitFailure.message(L("尚未配置远程仓库，请先在设置中填写远程地址。")) }
        let tracked = await read(["config", "branch.\(branch).remote"])
        let merge = await read(["config", "branch.\(branch).merge"])
        let targets = remotes.map { item in
            GitPushPlan.Target(name: item.name, urls: [item.url], branch: item.name == tracked && merge.hasPrefix("refs/heads/") ? String(merge.dropFirst("refs/heads/".count)) : branch)
        }
        let preferred = targets.contains { $0.name == tracked } ? tracked : targets.contains { $0.name == "origin" } ? "origin" : targets[0].name
        return GitPullPlan(root: root, branch: branch, targets: targets, defaultRemote: preferred)
    }
    func arguments(remote: String) throws -> [String] {
        guard let target = targets.first(where: { $0.name == remote }) else { throw GitFailure.message(L("远程仓库已变化，请重新选择。")) }
        return ["fetch", "--no-tags", "--", target.name, "refs/heads/" + target.branch]
    }
    func validate(remote: String) async throws {
        let fresh = try await Self.prepare(root)
        guard fresh.branch == branch else { throw GitFailure.message(L("当前分支已变化，请重新选择拉取来源。")) }
        guard let before = targets.first(where: { $0.name == remote }), let after = fresh.targets.first(where: { $0.name == remote }), before.urls == after.urls, before.branch == after.branch else {
            throw GitFailure.message(L("远程仓库已变化，请重新选择。"))
        }
    }
}

struct BranchCheckoutPlan: Equatable {
    let arguments: [String]
    let reference: String
    static func prepare(_ root: String, branch: Branch) async throws -> Self {
        if !branch.remote { return Self(arguments: ["switch", "--no-guess", "--", branch.name], reference: "refs/heads/" + branch.name) }
        let reference = "refs/remotes/" + branch.name
        _ = try await Git.run(root, ["rev-parse", "--verify", reference + "^{commit}"])
        let remotes = try await Git.run(root, ["remote"]).split(separator: "\n").map(String.init).sorted { $0.count > $1.count }
        guard let remote = remotes.first(where: { branch.name.hasPrefix($0 + "/") }) else { throw GitFailure.message(L("远程仓库已变化，请重新选择。")) }
        let short = String(branch.name.dropFirst(remote.count + 1))
        let rows = try await Git.run(root, ["for-each-ref", "--format=%(refname)%00%(upstream)", "refs/heads/"]).split(separator: "\n").map { $0.split(separator: "\0", omittingEmptySubsequences: false).map(String.init) }.map { row in [String(row[0].dropFirst("refs/heads/".count))] + Array(row.dropFirst()) }
        let names = rows.compactMap(\.first)
        let current = (try? await Git.run(root, ["symbolic-ref", "--short", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        let matching = rows.filter { $0.count == 2 && $0[1] == reference }.map { $0[0] }
        if let local = matching.first(where: { $0 == current }) ?? matching.first(where: { $0 == short }) ?? matching.first {
            return Self(arguments: ["switch", "--no-guess", "--", local], reference: "refs/heads/" + local)
        }
        func occupied(_ name: String) -> Bool { names.contains { $0 == name || $0.hasPrefix(name + "/") || name.hasPrefix($0 + "/") } }
        var local = short
        if occupied(local) {
            let base = (remote + "-" + short).replacingOccurrences(of: "/", with: "-")
            local = base; var number = 2
            while occupied(local) { local = base + "-" + String(number); number += 1 }
        }
        return Self(arguments: ["switch", "--track", "-c", local, "--", reference], reference: reference)
    }
}


/// Distinguish an ordinary folder from inaccessible, bare, or damaged repositories.
enum GitProjectFolder {
    static func repository(_ path: String) async throws -> String? {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            throw GitFailure.message(L("文件夹不存在或无法访问，请重新选择。"))
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw GitFailure.message(L("无法读取此文件夹，请检查访问权限后重试。"))
        }
        do {
            return try await Git.run(url.path, ["rev-parse", "--show-toplevel"]).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let failure as GitFailure {
            let message = failure.localizedDescription
            if message.contains("must be run in a work tree") {
                throw GitFailure.message(L("此文件夹是裸仓库，没有可编辑的工作区。请克隆到其他文件夹后打开。"))
            }
            guard message.contains("not a git repository") else { throw failure }
            var ancestor = url
            while true {
                let metadata = ancestor.appendingPathComponent(".git")
                if (try? FileManager.default.attributesOfItem(atPath: metadata.path)) != nil {
                    throw GitFailure.message(L("检测到 Git 数据，但仓库无法读取。请检查仓库和访问权限；不会重新初始化。"))
                }
                let parent = ancestor.deletingLastPathComponent()
                if parent.path == ancestor.path { break }
                ancestor = parent
            }
            return nil
        }
    }
}

import SwiftUI
import AppKit

@MainActor final class Workspace: ObservableObject {
    @Published var projects: [Project] = []
    @Published var project: Project?
    @Published var changes: [Change] = []
    @Published var branches: [Branch] = []
    @Published var branch = "尚未打开项目"
    @Published var selected: Change?
    @Published var selectedStaged = false
    @Published var checked = Set<String>()
    @Published var advancedMode = false { didSet { defaults.set(advancedMode, forKey: "advancedStagingMode") } }
    var commitItems: [Change] { changes.filter { checked.contains($0.path) && (!advancedMode || $0.staged) } }
    var canCommit: Bool { !busy && operationKind == nil && !commitItems.isEmpty && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !changes.contains(where: \.conflict) }
    @Published var diff = ""
    @Published var tabs: [EditorDocument] = []
    @Published var activeTabID: String?
    private var activatingTab = false
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = 0
    private var baselineRevision = 0
    private var pinOnLoad: String?
    var loadingPreview = false
    @Published var code = "" {
        didSet {
            guard !activatingTab, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
            tabs[index].text = code
            if tabs[index].dirty { tabs[index].preview = false }
        }
    }
    @Published var savedCode = ""
    @Published var canEdit = false
    @Published var editing = false
    @Published var message = ""
    @Published var activityTitle = ""
    @Published var activityLabel = L("正在处理，请稍候…")
    @Published var activityStarted = Date()
    @Published var busy = false
    @Published var changesRefreshing = false
    private var changesRefreshTask: Task<Void, Never>?
    private var changesRefreshRevision = 0
    private func cancelChangesRefresh() {
        changesRefreshRevision += 1; changesRefreshTask?.cancel(); changesRefreshTask = nil
        if changesRefreshing { changesRefreshing = false }
    }
    func refreshChanges() {
        guard !busy, !changesRefreshing, let root = project?.path else { return }
        changesRefreshRevision += 1; let revision = changesRefreshRevision
        changesRefreshing = true
        changesRefreshTask = Task {
            defer { if revision == self.changesRefreshRevision { self.changesRefreshing = false } }
            do {
                let result = Change.parse(try await Git.run(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]))
                guard !Task.isCancelled, revision == self.changesRefreshRevision, self.project?.path == root else { return }
                if self.changes != result { self.changes = result }
                let operation = try await GitTools.operation(root)
                let pending = try await PendingPush.read(root)
                guard revision == self.changesRefreshRevision, self.project?.path == root, !Task.isCancelled else { return }
                self.operationKind = operation; self.pendingPullCount = pending.behind; self.pendingPushIDs = pending.ids
            } catch {
                if !Task.isCancelled, revision == self.changesRefreshRevision, self.project?.path == root { self.error = error.localizedDescription }
            }
        }
    }
    @Published var error: String?
    @Published var restoreConflict: StashRestore.Entry?
    @Published var restoreConflictProgress = ""
    private var restoreAnswer: CheckedContinuation<StashRestore.Choice, Never>?
    func answerRestore(_ choice: StashRestore.Choice) {
        let continuation = restoreAnswer; restoreAnswer = nil; restoreConflict = nil
        continuation?.resume(returning: choice)
    }
    func restoreStash(oid: String? = nil, resolve: ((StashRestore.Entry) async -> StashRestore.Choice)? = nil) async throws {
        guard let root = project?.path else { return }
        let plan = try await StashRestore.prepare(root, oid: oid)
        defer { plan.cleanup() }
        var choices: [String: StashRestore.Choice] = [:]
        for (index, entry) in plan.conflicts.enumerated() {
            let choice: StashRestore.Choice
            if let resolve { choice = await resolve(entry) }
            else {
                restoreConflictProgress = "\(index + 1) / \(plan.conflicts.count)"
                choice = await withCheckedContinuation { continuation in
                    restoreAnswer = continuation; restoreConflict = entry
                }
            }
            if choice == .cancel { notice = L("已取消恢复，文件与备份保持不变"); return }
            choices[entry.path] = choice
        }
        do {
            let result = try await StashRestore.apply(plan, choices: choices)
            for entry in plan.entries where entry.current != entry.backup && choices[entry.path] != .keep {
                guard let index = tabs.firstIndex(where: { $0.id == entry.path && !$0.dirty }) else { continue }
                if case .file(let data, _) = entry.backup, data.count <= 2_000_000, !data.contains(0), let text = String(data: data, encoding: .utf8) {
                    tabs[index].text = text; tabs[index].savedText = text
                } else {
                    tabs[index].text = L("此文件已恢复为删除状态或非文本文件。"); tabs[index].savedText = tabs[index].text; tabs[index].editable = false
                }
                if activeTabID == entry.path { activateTab(entry.path) }
            }
            try await refresh(); notice = result
        } catch {
            let failure = error
            try? await refresh()
            throw failure
        }
    }
    func restoreStashRecord(_ record: StashRecord) {
        guard !busy, allowNavigation() else { return }
        perform { try await self.restoreStash(oid: record.id) }
    }
    @Published var notice = L("欢迎使用枝序")
    @Published var branchAction: BranchMutation?
    @Published var branchActionName = ""
    @Published var branchActionIsDelete = false
    private var branchActionRoot: String?
    func canDeleteBranch(_ target: Branch) -> Bool {
        !busy && (target.remote ? target.name != upstream : target.name != branch)
    }
    func prepareBranchAction(_ target: Branch, delete: Bool) {
        guard !busy, let root = project?.path, !delete || canDeleteBranch(target) else { return }
        perform {
            let plan = try await BranchMutation.prepare(root: root, branch: target)
            self.branchActionRoot = root; self.branchActionName = plan.shortName
            self.branchActionIsDelete = delete; self.branchAction = plan
        }
    }
    func applyBranchAction() {
        guard !busy, let plan = branchAction, let root = branchActionRoot, root == project?.path else { return }
        let name = branchActionIsDelete ? nil : branchActionName.trimmingCharacters(in: .whitespacesAndNewlines)
        branchAction = nil
        perform {
            do {
                try await plan.apply(root: root, newName: name)
                try await self.refresh()
                self.notice = name == nil ? L("已删除分支 ") + plan.branch.name : L("分支已重命名为 ") + name!
            } catch {
                let failure = error
                try? await self.refresh()
                throw failure
            }
        }
    }
    @Published var historyAction: CommitEntry?
    @Published var historyActionMessage = ""
    @Published var historyActionIsAmend = false
    private var historyActionRoot: String?
    func canChangeHistory(_ item: CommitEntry) -> Bool {
        !busy && historyPage == 0 && history.first?.id == item.id && pendingPushIDs.contains(item.id)
    }
    func prepareHistoryAction(_ item: CommitEntry, amend: Bool) {
        guard canChangeHistory(item), let root = project?.path else { return }
        perform {
            _ = try await LocalCommitHistory.validate(root: root, oid: item.id)
            self.historyActionMessage = try await Git.run(root, ["show", "-s", "--format=%B", item.id]).trimmingCharacters(in: .newlines)
            self.historyActionRoot = root; self.historyActionIsAmend = amend; self.historyAction = item
        }
    }
    func applyHistoryAction() {
        guard !busy, let item = historyAction, let root = historyActionRoot, root == project?.path else { return }
        let amend = historyActionIsAmend, description = historyActionMessage
        historyAction = nil
        perform {
            if amend { try await LocalCommitHistory.amendMessage(root: root, oid: item.id, message: description) }
            else {
                try await LocalCommitHistory.undo(root: root, oid: item.id)
                if self.message.isEmpty { self.message = description }
            }
            self.historyPage = 0
            try await self.refresh()
            self.notice = amend ? L("已修改提交说明 · 文件和暂存内容保持不变") : L("已撤销提交 · 修改已回到变更列表，暂存内容保留")
        }
    }
    @Published var history: [CommitEntry] = []
    @Published var pendingPushIDs = Set<String>()
    @Published var pendingPullCount = 0
    @Published var operationKind: String?
    var operationTitle: String { ["merge": L("合并"), "rebase": L("变基"), "revert": L("反向提交"), "cherry-pick": L("挑选提交")][operationKind ?? ""] ?? L("Git 操作") }
    @Published var reviewRequest: ReviewRequest?
    @Published var conflictFile: GitConflict?
    @Published var toolConfirmation: ToolConfirmation?
    struct ReviewRequest: Identifiable {
        enum Mode { case commit(String), file(String), compare(String) }
        let id = UUID()
        let root: String
        let mode: Mode
    }
    struct ToolConfirmation {
        enum Action {
            case merge(String, String, String), revert(String, String, String), abort(String)
            case restore(GitTools.FileRestore), ignore(String, GitTools.IgnoreKind)
        }
        let root: String
        let title: String
        let detail: String
        let action: Action
    }
    func showReview(_ mode: ReviewRequest.Mode) {
        guard !busy, let root = project?.path else { return }
        reviewRequest = ReviewRequest(root: root, mode: mode)
    }
    func compareBranch(_ target: Branch) {
        showReview(.compare((target.remote ? "refs/remotes/" : "refs/heads/") + target.name))
    }
    func prepareMerge(ref: String) {
        guard !busy, let root = project?.path, allowNavigation() else { return }
        perform {
            try await GitTools.requireClean(root)
            let head = try await GitTools.oid(root, "HEAD"), target = try await GitTools.oid(root, ref)
            self.toolConfirmation = ToolConfirmation(root: root, title: L("合并到当前分支？"), detail: L("将「") + ref + L("」合并到「") + self.branch + L("」。可能产生合并提交；若有冲突，会进入冲突解决流程。"), action: .merge(target, head, try await Git.run(root, ["rev-parse", "--symbolic-full-name", "HEAD"])))
        }
    }
    func prepareRevert(_ item: CommitEntry) {
        guard !busy, let root = project?.path, allowNavigation() else { return }
        perform {
            try await GitTools.requireClean(root)
            let head = try await GitTools.oid(root, "HEAD")
            self.toolConfirmation = ToolConfirmation(root: root, title: L("生成反向提交？"), detail: item.shortID + " · " + item.subject + L("\n新增一条提交抵消这次修改，保留原历史；之后仍需推送。合并提交以第一父提交为基准。"), action: .revert(item.id, head, try await Git.run(root, ["rev-parse", "--symbolic-full-name", "HEAD"])))
        }
    }
    func prepareFileRestore(path: String, ref: String, sourcePath: String? = nil) {
        guard !busy, let root = project?.path, allowNavigation() else { return }
        perform {
            let plan = try await GitTools.FileRestore.prepare(root, path: path, ref: ref, sourcePath: sourcePath)
            self.toolConfirmation = ToolConfirmation(root: root, title: L("恢复此文件到所选版本？"), detail: path + L("\n将覆盖当前工作区中的此文件，暂存区保持不变；历史中不存在的文件将移到废纸篓。恢复后请检查并提交。"), action: .restore(plan))
        }
    }
    func prepareIgnore(path: String, kind: GitTools.IgnoreKind) {
        guard !busy, let root = project?.path, allowNavigation() else { return }
        do {
            let pattern = try GitTools.ignorePattern(path: path, kind: kind)
            toolConfirmation = ToolConfirmation(root: root, title: L("添加忽略规则？"), detail: L("写入项目 .gitignore：\n") + pattern + L("\n已被 Git 跟踪的文件不会因忽略规则停止跟踪。"), action: .ignore(path, kind))
        } catch { self.error = error.localizedDescription }
    }
    func resolveConflict(_ path: String) {
        guard !busy, let root = project?.path, allowNavigation() else { return }
        perform { self.conflictFile = try await GitConflict.read(root, path: path) }
    }
    func saveConflict(_ resolution: GitConflict.Resolution) {
        guard !busy, let file = conflictFile, file.root == project?.path else { return }
        perform {
            try await file.save(resolution)
            self.conflictFile = nil
            self.updateMovedTabs(old: file.path, new: nil)
            try await self.refresh()
            self.notice = L("已标记解决 · ") + file.path
        }
    }
    func continueGitOperation() {
        guard !busy, let root = project?.path, allowNavigation() else { return }
        perform {
            do { try await GitTools.continueOperation(root); self.clearEditors(); try await self.refresh() }
            catch { try? await self.refresh(); throw error }
        }
    }
    func prepareAbort() {
        guard !busy, let root = project?.path, let kind = operationKind else { return }
        toolConfirmation = ToolConfirmation(root: root, title: L("中止当前操作？"), detail: L("将中止正在进行的") + operationTitle + L("，本次冲突解决过程中所做的编辑将被丢弃。"), action: .abort(kind))
    }
    func applyToolConfirmation() {
        guard !busy, let confirmation = toolConfirmation, confirmation.root == project?.path else { return }
        toolConfirmation = nil
        switch confirmation.action {
        case .merge, .revert, .abort:
            reviewRequest = nil
        case .restore, .ignore: break
        }
        perform {
            do {
                switch confirmation.action {
                case .merge(let target, let head, let branch): try await GitTools.integrate(confirmation.root, ref: target, expectedHead: head, expectedBranch: branch)
                case .revert(let target, let head, let branch): try await GitTools.integrate(confirmation.root, ref: target, expectedHead: head, revert: true, expectedBranch: branch)
                case .abort(let kind): try await GitTools.abortOperation(confirmation.root, expected: kind)
                case .restore(let plan): try await plan.apply()
                case .ignore(let path, let kind): try GitTools.ignore(confirmation.root, path: path, kind: kind)
                }
                self.clearEditors(); try await self.refresh(); self.notice = L("操作完成")
            } catch {
                self.clearEditors(); try? await self.refresh()
                if self.changes.contains(where: \.conflict) {
                    self.notice = L("存在冲突，请在变更列表点击“解决冲突”")
                } else { throw error }
            }
        }
    }
    @Published var historyPage = 0
    @Published var historyHasNext = false
    @Published var files: [String] = []
    @Published var editorPath: String?
    @Published var upstream = "未关联远程分支"
    var dirty: Bool { code != savedCode }
    var activeDocument: EditorDocument? { tabs.first { $0.id == activeTabID } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard, restore: Bool = true) {
        self.defaults = defaults
        AccountStore.migrate(defaults: defaults)
        advancedMode = defaults.bool(forKey: "advancedStagingMode")
        guard restore else { return }
        if let data = defaults.data(forKey: "projects"), let saved = try? JSONDecoder().decode([Project].self, from: data) { projects = saved }
        if let path = defaults.string(forKey: "lastProject"), let p = projects.first(where: { $0.path == path }) { project = p }
        perform {
            _ = try await GitEnvironment.shared.executable(refresh: true)
            if self.project != nil { try await self.refresh() }
        }
    }
    func persist() { defaults.set(try? JSONEncoder().encode(projects), forKey: "projects"); defaults.set(project?.path, forKey: "lastProject") }
    @discardableResult func removeProject(_ removed: Project) -> Bool {
        guard !busy else { return false }
        if project == removed {
            guard allowNavigation() else { return false }
            clearEditors(); project = nil; changes = []; branches = []; selected = nil; checked = []
            editorPath = nil; code = ""; savedCode = ""; diff = ""; canEdit = false; editing = false
            message = ""; history = []; historyPage = 0; historyHasNext = false
            pendingPushIDs = []; pendingPullCount = 0; operationKind = nil; reviewRequest = nil; conflictFile = nil; toolConfirmation = nil; files = []; ignoredFiles = []; expandedIgnoredFolders = []; branch = "尚未打开项目"; upstream = "未关联远程分支"
        }
        projects.removeAll { $0 == removed }
        persist(); notice = L("已从列表移除 {0} · 磁盘文件保留", [String(describing: removed.name)])
        return true
    }
    var conflictDraftDirty = false
    func allowNavigation() -> Bool {
        if conflictDraftDirty {
            let answer = AppDialogs.confirm(L("合并结果尚未保存"), message: L("请返回冲突编辑器保存结果；放弃编辑不会修改磁盘中的冲突文件。"), accept: L("返回编辑"), discard: L("放弃编辑并继续"))
            guard answer == 2 else { return false }
            conflictDraftDirty = false
            conflictFile = nil
        }
        let unsaved = tabs.filter(\.dirty)
        guard !unsaved.isEmpty else { return true }
        switch AppDialogs.confirm(L("有 {0} 个文件尚未保存", [String(describing: unsaved.count)]), message: L("保存所有修改后继续，或放弃这些编辑。"), accept: L("全部保存并继续"), discard: L("放弃修改")) {
        case 1: return unsaved.allSatisfy { saveTab($0.id) }
        case 2:
            for i in tabs.indices { tabs[i].text = tabs[i].savedText }
            if let id = activeTabID { activateTab(id) }; return true
        default: return false
        }
    }
    func clearEditors() {
        cancelHistoryRefresh(); cancelChangesRefresh()
        previewGeneration += 1; previewTask?.cancel(); loadingPreview = false; pinOnLoad = nil
        tabs = []; activeTabID = nil; editorPath = nil; code = ""; savedCode = ""; canEdit = false; editing = true
    }
    func activateTab(_ id: String, cancelPending: Bool = true) {
        if cancelPending { previewGeneration += 1; previewTask?.cancel(); loadingPreview = false }
        guard let doc = tabs.first(where: { $0.id == id }) else { return }
        activatingTab = true
        activeTabID = id; editorPath = doc.path; code = doc.text; savedCode = doc.savedText; canEdit = doc.editable; editing = !doc.isDiff
        activatingTab = false
    }
    func pinTab(_ id: String) { pinOnLoad = id; if let i = tabs.firstIndex(where: { $0.id == id }) { tabs[i].preview = false } }
    func presentDocument(_ document: EditorDocument) {
        if tabs.contains(where: { $0.id == document.id }) { activateTab(document.id, cancelPending: false); return }
        if let preview = tabs.firstIndex(where: { $0.preview && !$0.dirty }) { tabs[preview] = document }
        else { tabs.append(document) }
        activateTab(document.id, cancelPending: false)
    }
    func closeTab(_ id: String) {
        guard !busy, let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        if tabs[i].dirty {
            switch AppDialogs.confirm(L("保存对「{0}」的修改？", [String(describing: tabs[i].name)]), message: L("关闭前保存，或放弃此文件的编辑。"), accept: L("保存"), discard: L("不保存")) {
            case 1: guard saveTab(id) else { return }
            case 2: break
            default: return
            }
        }
        tabs.remove(at: i)
        if activeTabID == id {
            if tabs.isEmpty { clearEditors() }
            else { activateTab(tabs[min(i, tabs.count - 1)].id) }
        }
    }
    @Published var remoteFailure: GitRemoteFailure?
    var remoteRetry: (() -> Void)?
    @Published var gitSetupMessage = ""
    @Published var missingGit = false
    @Published var canCancelGit = false
    private var operationTask: Task<Void, Never>?
    private var credentialWarning: String?
    func retryRemote(account: GitAccount? = nil, password: String? = nil) {
        guard let failure = remoteFailure, !busy else { return }
        remoteFailure = nil
        let attempt = account.map { GitLoginAttempt(account: $0, secret: password) }
        Git.loginContext.withValue(attempt) {
            if let retry = remoteRetry { remoteRetry = nil; retry(); return }
            perform {
                _ = try await Git.run(failure.root, failure.arguments)
                if failure.arguments.first == "clone", let target = failure.arguments.last {
                    try await self.open(target)
                } else if self.project?.path == failure.root { try await self.refresh() }
                self.notice = L("操作完成")
            }
        }
    }
    func cancelGitOperation() {
        guard canCancelGit else { return }
        canCancelGit = false
        operationTask?.cancel()
    }
    func checkGitEnvironment() {
        missingGit = false
        perform {
            _ = try await GitEnvironment.shared.executable(refresh: true)
            if self.project != nil { try await self.refresh() }
            self.notice = L("Git 已就绪")
        }
    }
    func installGitTools() {
        gitSetupMessage = ""
        Task {
            do {
                let result = try await GitProcess.run("/usr/bin/xcode-select", arguments: ["--install"], timeout: 10)
                if result.code != 0 { self.gitSetupMessage = L("未能启动安装程序。请在系统设置的软件更新中安装命令行工具，然后重新检查。") }
                else { self.gitSetupMessage = L("请完成 macOS 安装窗口中的步骤，然后点击重新检查。") }
            } catch { self.gitSetupMessage = error.localizedDescription }
        }
    }
    func perform(title: String = "", remoteRetry: (() -> Void)? = nil, _ body: @escaping () async throws -> Void) {
        guard !busy else { return }; cancelHistoryRefresh(); cancelChangesRefresh(); cancelFilesRefresh(); busy = true; credentialWarning = nil; activityTitle = title; activityStarted = Date(); activityLabel = L("正在处理，请稍候…")
        operationTask = Task { [self] in
            defer {
                busy = false; canCancelGit = false; operationTask = nil
                if error == nil && remoteFailure == nil, let credentialWarning { error = credentialWarning }
                credentialWarning = nil
            }
            do {
                try await Git.credentialWarningContext.withValue({ [weak self] message in
                    await self?.recordCredentialWarning(message)
                }) {
                    try await Git.activityContext.withValue({ [weak self] active in
                        await self?.setRemoteActivity(active)
                    }) {
                        try await Git.statusContext.withValue({ [weak self] command in
                            await self?.setActivityLabel(command)
                        }) { try await body() }
                    }
                }
            } catch is CancellationError {
                notice = L("已取消网络操作。已完成的提交会保留，请刷新确认远程状态。")
            } catch is GitEnvironmentMissing {
                missingGit = true
            } catch let failure as GitRemoteFailure {
                self.remoteFailure = failure; self.remoteRetry = remoteRetry
            } catch { self.error = error.localizedDescription }
        }
    }
    private func recordCredentialWarning(_ message: String) { credentialWarning = message }
    private func setActivityLabel(_ command: String) {
        activityLabel = L(command == "push" ? "正在推送到远程仓库…" : command == "clone" ? "正在克隆仓库…" : command == "fetch" || command == "pull" ? "正在获取远程更新…" : "正在连接远程仓库…")
    }
    private func setRemoteActivity(_ active: Bool) {
        canCancelGit = active
        if !active { activityLabel = L("正在更新本地状态…") }
    }
    func chooseProject(create: Bool = false) {
        guard !busy, allowNavigation() else { return }
        AppDialogs.directory(title: create ? L("创建 Git 项目") : L("打开 Git 项目"), name: create ? L("我的项目") : nil, prompt: create ? L("创建项目") : L("打开项目")) { [weak self] url in
            guard let self, let url, !self.busy, self.allowNavigation() else { return }
            self.perform { try await self.openFolder(url.path, create: create) }
        }
    }

    /// Used after folder selection. Cancellation must not alter files or the current project.
    func openFolder(_ path: String, create: Bool = false, confirmInitialization: ((String) -> Bool)? = nil) async throws {
        if create { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
        if let root = try await GitProjectFolder.repository(path) { try await open(root); return }
        let confirmed = create || (confirmInitialization?(path) ?? (AppDialogs.confirm(
            L("此文件夹尚未初始化 Git"),
            message: L("是否将此文件夹初始化为 Git 项目？现有文件会保留，不会自动提交或上传。\n{0}", [path]),
            accept: L("初始化并打开")) == 1))
        guard confirmed else { return }
        // Recheck after confirmation: another app may have initialized this directory.
        if let root = try await GitProjectFolder.repository(path) { try await open(root); return }
        _ = try await Git.run(path, ["init", "-b", "main"])
        try await open(path)
    }

    func open(_ path: String) async throws {
        guard let root = try await GitProjectFolder.repository(path) else {
            throw GitFailure.message(L("此文件夹尚未初始化 Git，请通过“打开项目”选择并初始化。"))
        }
        let p = Project(path: root)
        if !projects.contains(p) { projects.append(p) }
        cancelFilesRefresh(); expandedIgnoredFolders = []; ignoredFiles = []; pendingExplorerReload = false
        clearEditors(); project = p; historyPage = 0; selected = nil; editorPath = nil; checked = []; code = ""; savedCode = ""; diff = ""; message = ""; persist()
        try await refresh()
    }
    func switchProject(_ p: Project) { guard !busy, allowNavigation() else { return }; perform { try await self.open(p.path) } }
    func refresh() async throws {
        cancelFilesRefresh(); cancelHistoryRefresh(); cancelChangesRefresh()
        guard let root = project?.path else { return }
        changes = Change.parse(try await Git.run(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]))
        checked.formIntersection(Set(changes.map(\.path)))
        branch = (try? await Git.run(root, ["symbolic-ref", "--short", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "游离 HEAD"
        branches = try await Branch.read(root, current: branch)
        let pending = try await PendingPush.read(root)
        upstream = pending.upstream ?? "未关联远程分支"
        pendingPushIDs = pending.ids
        pendingPullCount = pending.behind
        operationKind = try await GitTools.operation(root)
        try await readHistory()
        let snapshot = try await readFiles(root: root, fileChanges: changes)
        files = snapshot.paths; ignoredFiles = snapshot.ignored
        baselineRevision += 1; let revision = baselineRevision
        let openPaths = tabs.filter { !$0.isDiff && $0.editable }.map(\.path)
        Task {
            for path in openPaths {
                let baseline = (try? await Git.run(root, ["show", ":" + path])) ?? ""
                guard self.project?.path == root, revision == self.baselineRevision else { return }
                if let index = self.tabs.firstIndex(where: { $0.id == path }) { self.tabs[index].baseline = baseline }
            }
        }
        notice = L("已更新 · {0} 个变更", [String(describing: changes.count)])
    }
    @Published var ignoredFiles = Set<String>()
    private var expandedIgnoredFolders = Set<String>()
    private var pendingExplorerReload = false
    private struct ExplorerSnapshot { let paths: [String]; let ignored: Set<String> }
    func expandIgnoredFolder(_ path: String) {
        guard !busy, ignoredFiles.contains(path), !expandedIgnoredFolders.contains(path) else { return }
        expandedIgnoredFolders.insert(path)
        if filesRefreshing { pendingExplorerReload = true } else { refreshFiles() }
    }
    private func readFiles(root: String, fileChanges: [Change]) async throws -> ExplorerSnapshot {
        async let trackedOutput = Git.run(root, ["ls-files", "-z", "--cached", "--others", "--exclude-standard"])
        async let directoryOutput = Git.run(root, ["ls-files", "-z", "--others", "--directory", "--exclude-standard"])
        async let ignoredOutput = try? Git.run(root, ["ls-files", "-z", "--others", "--ignored", "--directory", "--exclude-standard"])
        let (tracked, directoryEntries, ignoredEntries) = try await (trackedOutput, directoryOutput, ignoredOutput)
        let listedFiles = Array(Set(tracked.split(separator: "\0").map(String.init)).union(fileChanges.map(\.path))).sorted()
        // Include empty untracked directories, which Git does not include in its file index.
        let directoryRoots = directoryEntries.split(separator: "\0").map(String.init).filter { $0.hasSuffix("/") }
        let ignored = Set((ignoredEntries ?? "").split(separator: "\0").map(String.init))
        let expanded = expandedIgnoredFolders
        let folders = await Task.detached {
            var result = directoryRoots
            for relative in directoryRoots {
                let base = URL(fileURLWithPath: root).appendingPathComponent(relative)
                guard let iterator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
                while let url = iterator.nextObject() as? URL {
                    let path = String(url.path.dropFirst(root.count + 1))
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    if url.lastPathComponent == ".git" || values?.isSymbolicLink == true || ignored.contains(path) || ignored.contains(path + "/") { iterator.skipDescendants(); continue }
                    if values?.isDirectory == true { result.append(path + "/") }
                }
            }
            // Ignored directory roots are visible immediately; only enumerate their
            // direct children after expansion, never recursively scan build caches.
            for relative in expanded.sorted() {
                let base = URL(fileURLWithPath: root).appendingPathComponent(relative)
                let canonical = base.resolvingSymlinksInPath().path
                let canonicalRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
                guard canonical.hasPrefix(canonicalRoot + "/"),
                      let children = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
                for child in children where child.lastPathComponent != ".git" {
                    let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    let folder = values?.isDirectory == true && values?.isSymbolicLink != true
                    result.append(relative + "/" + child.lastPathComponent + (folder ? "/" : ""))
                }
            }
            return result
        }.value
        let paths = Array(Set(listedFiles).union(folders).union(ignored)).filter { !$0.split(separator: "/").contains(".git") }.sorted()
        let ignoredRoots = ignored.filter { $0.hasSuffix("/") }
        let nonIgnored = Set(listedFiles)
        let dimmed = Set(paths.filter { path in
            !nonIgnored.contains(path) && (ignored.contains(path) || ignoredRoots.contains { path.hasPrefix($0) })
        }.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 })
        return ExplorerSnapshot(paths: paths, ignored: dimmed)
    }
    @Published var filesRefreshing = false
    private var filesRefreshTask: Task<Void, Never>?
    private var filesRefreshRevision = 0
    func refreshFiles() {
        guard !busy, !filesRefreshing, let root = project?.path else { return }
        filesRefreshRevision += 1
        let revision = filesRefreshRevision
        filesRefreshing = true
        filesRefreshTask = Task {
            defer { if revision == self.filesRefreshRevision { self.filesRefreshing = false } }
            do {
                repeat {
                    self.pendingExplorerReload = false
                    let changes = Change.parse(try await Git.run(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]))
                    let snapshot = try await self.readFiles(root: root, fileChanges: changes)
                    guard !Task.isCancelled, revision == self.filesRefreshRevision, self.project?.path == root else { return }
                    if self.files != snapshot.paths { self.files = snapshot.paths }
                    if self.ignoredFiles != snapshot.ignored { self.ignoredFiles = snapshot.ignored }
                    if self.changes != changes { self.changes = changes }
                    self.notice = L("文件列表已刷新")
                } while self.pendingExplorerReload
            } catch {
                if !Task.isCancelled, revision == self.filesRefreshRevision, self.project?.path == root { self.error = error.localizedDescription }
            }
        }
    }
    private func cancelFilesRefresh() {
        filesRefreshRevision += 1
        filesRefreshTask?.cancel(); filesRefreshTask = nil; filesRefreshing = false
    }
    func load(_ path: String, staged: Bool, change: Change? = nil) {
        guard !busy, let root = project?.path else { return }
        selected = change; selectedStaged = staged
        if tabs.contains(where: { $0.id == path }) { previewGeneration += 1; previewTask?.cancel(); loadingPreview = false; activateTab(path); return }
        previewGeneration += 1; let generation = previewGeneration
        previewTask?.cancel(); loadingPreview = true
        previewTask = Task {
            let text = await Task.detached(priority: .userInitiated) { () -> String? in
                let url = URL(fileURLWithPath: root).appendingPathComponent(path)
                guard url.resolvingSymlinksInPath().path.hasPrefix(root + "/"), !path.split(separator: "/").contains(".git"),
                      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
                      let data = try? Data(contentsOf: url), !data.contains(0) else { return nil }
                return String(data: data, encoding: .utf8)
            }.value
            guard generation == self.previewGeneration, self.project?.path == root, !Task.isCancelled else { return }
            let content = text ?? L("此文件无法作为文本编辑（可能已删除、是二进制文件或大于 2 MB）。")
            var document = EditorDocument(id: path, path: path, text: content, savedText: content, editable: text != nil)
            document.preview = self.pinOnLoad != path
            self.presentDocument(document)
            self.loadingPreview = false
            // Git's index is the baseline for unstaged editor decorations, like VS Code.
            let revision = self.baselineRevision
            let baseline = (try? await Git.run(root, ["show", ":" + path])) ?? ""
            guard self.project?.path == root, revision == self.baselineRevision,
                  let index = self.tabs.firstIndex(where: { $0.id == path }) else { return }
            self.tabs[index].baseline = baseline
        }
    }

    func loadDiff(_ path: String, staged: Bool, combined: Bool = false) {
        guard !busy, let root = project?.path else { return }
        previewGeneration += 1; let generation = previewGeneration
        previewTask?.cancel(); loadingPreview = true
        previewTask = Task {
          defer { if generation == self.previewGeneration { self.loadingPreview = false } }
          do {
            self.selected = self.changes.first { $0.path == path }; self.selectedStaged = staged
            let paths = self.selected?.paths ?? [path]
            var comparison = staged ? ["--cached"] : []
            if combined {
                if (try? await Git.run(root, ["rev-parse", "--verify", "HEAD"])) != nil { comparison = ["HEAD"] }
                else { comparison = [try await Git.run(root, ["hash-object", "-w", "-t", "tree", "--stdin"], input: "").trimmingCharacters(in: .whitespacesAndNewlines)] }
            }
            let content = try await Git.run(root, ["diff", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=1000000"] + comparison + ["--"] + paths)
            guard generation == self.previewGeneration, self.project?.path == root, !Task.isCancelled else { return }
            let untracked = self.selected?.index == "?"
            let lines = await Task.detached(priority: .userInitiated) {
                var lines = DiffLine.parse(content)
            if content.isEmpty, !staged, untracked {
                let url = URL(fileURLWithPath: root).appendingPathComponent(path)
                if url.resolvingSymlinksInPath().path.hasPrefix(root + "/"),
                   let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
                   let data = try? Data(contentsOf: url), !data.contains(0), let source = String(data: data, encoding: .utf8) {
                    lines = DiffLine.added(source)
                }
            }
                return lines
            }.value
            let text = lines.isEmpty ? (content.isEmpty ? L("没有可显示的文本差异。") : L("此文件的差异无法以文本显示。")) : lines.map(\.text).joined(separator: "\n")
            let id = combined ? "diff:combined:\(path)" : "diff:\(staged):\(path)"
            var document = EditorDocument(id: id, path: path, text: text, savedText: text, editable: false, isDiff: true, diffLines: lines)
            guard generation == self.previewGeneration, self.project?.path == root, !Task.isCancelled else { return }
            if let index = self.tabs.firstIndex(where: { $0.id == id }) {
                document.preview = self.tabs[index].preview; self.tabs[index] = document
            }
            guard generation == self.previewGeneration, self.project?.path == root, !Task.isCancelled else { return }
            self.presentDocument(document)
          } catch { if generation == self.previewGeneration, !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    @discardableResult func save() -> Bool {
        guard let id = activeTabID else { return true }
        return saveTab(id)
    }
    @discardableResult func saveTab(_ id: String) -> Bool {
        guard let i = tabs.firstIndex(where: { $0.id == id }), let root = project?.path else { return false }
        let doc = tabs[i]
        guard doc.dirty else { return true }
        do {
            let url = URL(fileURLWithPath: root).appendingPathComponent(doc.path)
            guard url.resolvingSymlinksInPath().path.hasPrefix(root + "/"), !doc.path.split(separator: "/").contains(".git") else { throw GitFailure.message(L("无法编辑项目外的文件或 Git 内部文件。")) }
            let disk = try String(contentsOf: url, encoding: .utf8)
            guard disk == doc.savedText else { throw GitFailure.message(L("「{0}」已被其他程序修改。为避免覆盖，请复制当前编辑内容后重新打开文件。", [String(describing: doc.name)])) }
            try doc.text.write(to: url, atomically: true, encoding: .utf8)
            tabs[i].savedText = doc.text; tabs[i].preview = false
            if activeTabID == id { savedCode = doc.text }
            notice = L("已保存 {0}", [String(describing: doc.path)]); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func stage(_ items: [Change], undo: Bool = false) {
        guard let root = project?.path, !items.isEmpty, allowNavigation() else { return }
        perform {
            let paths = Array(Set(items.flatMap(\.paths)))
            if undo {
                let hasHead = (try? await Git.run(root, ["rev-parse", "--verify", "HEAD"])) != nil
                _ = try await Git.run(root, (hasHead ? ["reset", "-q", "HEAD", "--"] : ["rm", "--cached", "-r", "--"]) + paths)
            } else { _ = try await Git.run(root, ["add", "--"] + paths) }
            try await self.refresh(); self.selected = nil; self.diff = ""; self.notice = undo ? L("已取消暂存，文件修改仍保留") : L("已暂存所选文件")
        }
    }
    struct PushRequest {
        let plan: GitPushPlan
        let commitFirst: Bool
    }
    @Published var pushRequest: PushRequest?
    func preparePush(commitFirst: Bool = false) {
        guard !busy, let root = project?.path, allowNavigation() else { return }
        let items = commitItems, stagedOnly = advancedMode, description = message
        perform(title: L(commitFirst ? "提交并推送" : "推送")) {
            let plan = try await GitPushPlan.prepare(root)
            if plan.targets.count == 1 {
                let remote = plan.targets[0].name
                if commitFirst {
                    try await self.commitPrepared(root: root, items: items, stagedOnly: stagedOnly, description: description, pushPlan: plan, pushRemote: remote)
                } else {
                    try await plan.validate(remote: remote)
                    _ = try await Git.run(root, plan.arguments(remote: remote))
                    try await self.refresh(); self.notice = L("操作完成")
                }
            } else { self.pushRequest = PushRequest(plan: plan, commitFirst: commitFirst) }
        }
    }
    func confirmPush(remote: String) {
        guard !busy, let request = pushRequest, request.plan.root == project?.path else { return }
        pushRequest = nil
        if request.commitFirst {
            commit(pushAfter: true, pushPlan: request.plan, pushRemote: remote)
        } else {
            perform(title: L("推送")) {
                try await request.plan.validate(remote: remote)
                _ = try await Git.run(request.plan.root, request.plan.arguments(remote: remote))
                try await self.refresh(); self.notice = L("操作完成")
            }
        }
    }
    func commit(pushAfter: Bool = false, pushPlan: GitPushPlan? = nil, pushRemote: String? = nil) {
        guard let root = project?.path, canCommit, allowNavigation() else { return }
        if pushAfter && pushPlan == nil { preparePush(commitFirst: true); return }
        let items = commitItems, stagedOnly = advancedMode, description = message
        perform(title: L(pushAfter ? "提交并推送" : "提交")) {
            try await self.commitPrepared(root: root, items: items, stagedOnly: stagedOnly, description: description, pushPlan: pushPlan, pushRemote: pushRemote)
        }
    }
    private func commitPrepared(root: String, items: [Change], stagedOnly: Bool, description: String, pushPlan: GitPushPlan?, pushRemote: String?) async throws {
            if let pushPlan, let pushRemote { try await pushPlan.validate(remote: pushRemote) }
            let warning = try await SelectedCommit.run(root: root, items: items, message: description, stagedOnly: stagedOnly)
            self.message = ""; self.historyPage = 0; self.selected = nil
            try await self.refresh()
            self.notice = L("提交成功 · 已记录到本地历史")
            if let warning { self.error = warning; return }
            if pushPlan != nil {
                do {
                    guard let pushPlan, let pushRemote else { throw GitFailure.message(L("远程仓库已变化，请重新选择。")) }
                    _ = try await Git.run(root, pushPlan.arguments(remote: pushRemote))
                } catch {
                    self.notice = L("已提交到本地 · 推送失败，可点击顶部推送重试")
                    if let failure = error as? GitRemoteFailure { throw failure }
                    throw GitFailure.message(L("提交已成功保存到本地，但推送失败。无需再次提交，可点击顶部「推送」重试。\n\n") + error.localizedDescription)
                }
                try await self.refresh(); self.notice = L("提交并推送成功")
            }
    }

    func checkout(_ b: Branch) {
        guard !busy, project != nil else { return }
        if !b.remote && b.name == branch { return }
        guard allowNavigation() else { return }
        perform { try await self.switchBranch(b) }
    }
    struct BranchSwitchPrompt {
        let target: Branch
        let targetOID: String
        let checkoutPlan: BranchCheckoutPlan
        let sourceRef: String
        let changes: DiscardChangesPlan
    }
    @Published var branchSwitchPrompt: BranchSwitchPrompt?
    func switchBranch(_ b: Branch) async throws {
        guard let root = project?.path else { return }
        let checkout = try await BranchCheckoutPlan.prepare(root, branch: b)
        do {
            _ = try await Git.run(root, checkout.arguments, environment: ["LC_ALL": "C"])
        } catch {
            let reason = error.localizedDescription
            if reason.contains("would be overwritten by checkout") || reason.contains("would be overwritten by merge") {
                let current = Change.parse(try await Git.run(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]))
                let plan = try await DiscardChangesPlan.prepare(root: root, changes: current, all: true)
                branchSwitchPrompt = BranchSwitchPrompt(target: b,
                    targetOID: try await Git.run(root, ["rev-parse", "--verify", checkout.reference]), checkoutPlan: checkout,
                    sourceRef: try await Git.run(root, ["rev-parse", "--symbolic-full-name", "HEAD"]), changes: plan)
                return
            }
            throw GitFailure.message(L("未能切换分支。\n\n") + reason)
        }
        clearEditors()
        try await refresh()
        notice = L("已切换到 ") + branch + (changes.isEmpty ? "" : L(" · 本地修改已保留"))
    }
    enum BranchSwitchChoice { case stash, carry, discard }
    func resolveBranchSwitch(_ choice: BranchSwitchChoice) {
        guard !busy, let prompt = branchSwitchPrompt else { return }
        perform { try await self.applyBranchSwitch(prompt, choice: choice) }
    }
    func applyBranchSwitch(_ prompt: BranchSwitchPrompt, choice: BranchSwitchChoice) async throws {
        guard let root = project?.path, root == prompt.changes.root else { return }
        // Revalidate both branches and every file before saving or discarding anything.
        guard try await Git.run(root, ["rev-parse", "--symbolic-full-name", "HEAD"]) == prompt.sourceRef,
              try await Git.run(root, ["rev-parse", "--verify", prompt.checkoutPlan.reference]) == prompt.targetOID,
              try await BranchCheckoutPlan.prepare(root, branch: prompt.target) == prompt.checkoutPlan else {
            branchSwitchPrompt = nil
            throw GitFailure.message(L("分支已发生变化，请重新选择目标分支。"))
        }
        do { try await prompt.changes.validate() }
        catch { branchSwitchPrompt = nil; throw error }
        branchSwitchPrompt = nil
        var backup: String?
        do {
            if choice == .discard {
                for file in prompt.changes.files {
                    try await file.apply()
                    for path in file.change.paths { updateMovedTabs(old: path, new: nil) }
                }
            } else {
                let previous = try? await Git.run(root, ["rev-parse", "--verify", "refs/stash"])
                _ = try await Git.run(root, ["stash", "push", "--include-untracked", "-m", L("枝序：切换到 ") + prompt.target.name + L(" 前临时收起")], literalPaths: false)
                let created = try await Git.run(root, ["rev-parse", "--verify", "refs/stash"])
                guard created != previous else { throw GitFailure.message(L("未能创建修改备份，已停止切换。")) }
                backup = created.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            _ = try await Git.run(root, prompt.checkoutPlan.arguments, environment: ["LC_ALL": "C"])
            clearEditors()
            if choice == .carry, let backup {
                do { _ = try await Git.run(root, ["stash", "apply", backup]) }
                catch {
                    try? await refresh()
                    throw GitFailure.message(L("已切换到「") + prompt.target.name + L("」，但携带修改时未能全部恢复，可能存在内容冲突。请在变更列表检查并处理；完整备份仍保留在临时收起记录中。"))
                }
            }
            try await refresh()
            notice = L("已切换到 ") + branch + (choice == .stash ? L(" · 修改已临时收起，可稍后恢复") : choice == .carry ? L(" · 已携带修改，备份已保留") : L(" · 已放弃原工作区更改"))
        } catch {
            clearEditors()
            try? await refresh()
            if backup != nil && branch != prompt.target.name && !prompt.target.remote {
                throw GitFailure.message(L("切换未完成，修改备份已保留在临时收起记录中，可恢复。\n\n") + error.localizedDescription)
            }
            throw error
        }
    }
    func newBranch(_ name: String) {
        guard let root = project?.path, allowNavigation() else { return }
        guard !name.hasPrefix("-") else { error = L("分支名称不能以 - 开头。"); return }
        perform {
            guard (try? await Git.run(root, ["rev-parse", "--verify", "HEAD^{commit}"])) != nil else {
                throw GitFailure.message(L("当前分支尚无提交，请先勾选文件并完成首次提交，再创建新分支。这样才能保留当前分支，并从它创建独立的新分支。"))
            }
            _ = try await Git.run(root, ["check-ref-format", "--branch", name])
            _ = try await Git.run(root, ["switch", "-c", name])
            try await self.refresh()
        }
    }
    @Published var pullRequest: GitPullPlan?
    func preparePull() {
        guard !busy, let root = project?.path, allowNavigation() else { return }
        var retry: (() -> Void)?
        perform(title: L("拉取"), remoteRetry: { retry?() }) { [self] in
            let plan = try await GitPullPlan.prepare(root)
            if plan.targets.count == 1 {
                let remote = plan.targets[0].name
                retry = { [weak self] in self?.pull(plan: plan, remote: remote) }
                try await self.pullPrepared(plan: plan, remote: remote)
            } else { self.pullRequest = plan }
        }
    }
    func confirmPull(remote: String) {
        guard !busy, let plan = pullRequest, plan.root == project?.path else { return }
        pullRequest = nil
        pull(plan: plan, remote: remote)
    }
    private func pull(plan: GitPullPlan, remote: String) {
        guard !busy, plan.root == project?.path, allowNavigation() else { return }
        perform(title: L("拉取"), remoteRetry: { [weak self] in self?.pull(plan: plan, remote: remote) }) {
            try await self.pullPrepared(plan: plan, remote: remote)
        }
    }
    private func pullPrepared(plan: GitPullPlan, remote: String) async throws {
        let root = plan.root
        try await plan.validate(remote: remote)
        try await GitTools.requireClean(root)
        let head = try await GitTools.oid(root, "HEAD")
        _ = try await Git.run(root, plan.arguments(remote: remote))
        let target = try await GitTools.oid(root, "FETCH_HEAD")
        try await plan.validate(remote: remote)
        try await GitTools.requireClean(root)
        guard try await GitTools.oid(root, "HEAD") == head else { throw GitFailure.message(L("当前分支已变化，请重新选择拉取来源。")) }
        let counts = try await Git.run(root, ["rev-list", "--left-right", "--count", head + "..." + target]).split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        try await self.refresh()
        if counts.count == 2, counts[0] > 0, counts[1] > 0 {
            self.toolConfirmation = ToolConfirmation(root: root, title: L("本地与远程已分叉"), detail: L("拉取来源：{0}", [remote + "/" + (plan.targets.first { $0.name == remote }?.branch ?? plan.branch)]) + "\n" + L("本地领先 {0} 条、落后 {1} 条。合并远程更新会保留双方提交；如有冲突，可在应用中处理。", [String(counts[0]), String(counts[1])]), action: .merge(target, head, try await Git.run(root, ["rev-parse", "--symbolic-full-name", "HEAD"])))
            return
        }
        _ = try await Git.run(root, ["merge", "--ff-only", target])
        self.clearEditors(); try await self.refresh(); self.notice = L("操作完成")
    }

    func sync(_ action: String) {
        guard let root = project?.path, allowNavigation() else { return }
        if action == "push" { preparePush(); return }
        if action == "pull" { preparePull(); return }
        if action == "pop" {
            perform { try await self.restoreStash() }
            return
        }
        perform(title: L(action == "fetch" ? "获取" : "正在处理，请稍候…"), remoteRetry: { [weak self] in self?.sync(action) }) {
            let args: [String]
            switch action {
            case "fetch": args = ["fetch", "--all", "--prune"]
            case "stash": args = ["stash", "push", "--include-untracked", "-m", L("枝序：临时保存")]
            default: args = ["stash", "pop"]
            }
            _ = try await Git.run(root, args, literalPaths: action != "stash")
            if ["pull", "stash", "pop"].contains(action) { self.clearEditors() }
            try await self.refresh()
            self.notice = action == "pop" ? L("已恢复最近收起的修改") : action == "stash" ? L("已临时收起修改") : L("操作完成")
        }
    }
    func clone(_ url: String) {
        guard !busy, allowNavigation() else { return }
        AppDialogs.directory(title: L("选择克隆位置"), name: URL(string: url)?.deletingPathExtension().lastPathComponent ?? "project", prompt: L("克隆")) { [weak self] target in
            guard let self, let target, !self.busy, self.allowNavigation() else { return }
            self.perform { _ = try await Git.run(target.deletingLastPathComponent().path, ["clone", "--", url, target.path]); try await self.open(target.path) }
        }
    }

    @Published var discardFile: DiscardChangesPlan?
    func prepareDiscard(_ change: Change) {
        guard !busy, let root = project?.path else { return }
        perform { self.discardFile = try await DiscardChangesPlan.prepare(root: root, changes: [change], all: false) }
    }
    var allChangesChecked: Bool { !changes.isEmpty && changes.allSatisfy { checked.contains($0.path) } }
    func prepareDiscardAll() {
        guard !busy, allChangesChecked, let root = project?.path else { return }
        let targets = changes
        perform { self.discardFile = try await DiscardChangesPlan.prepare(root: root, changes: targets, all: true) }
    }
    func applyDiscard() {
        guard !busy, let plan = discardFile, plan.root == project?.path else { return }
        discardFile = nil
        let active = activeDocument
        perform {
            do {
                try await plan.validate()
                for file in plan.files {
                    try await file.apply()
                    for path in file.change.paths { self.updateMovedTabs(old: path, new: nil) }
                }
                try await self.refresh()
                if let active, !active.isDiff, plan.files.contains(where: { $0.committedPaths.contains(active.path) }) {
                    let url = URL(fileURLWithPath: plan.root).appendingPathComponent(active.path)
                    let text = await Task.detached { try? String(contentsOf: url, encoding: .utf8) }.value
                    if let text { self.presentDocument(EditorDocument(id: active.path, path: active.path, text: text, savedText: text, editable: true, preview: active.preview, baseline: text)) }
                }
                self.notice = plan.all ? L("已撤销全部 {0} 个文件的更改", [String(describing: plan.files.count)]) : L("已撤销「") + plan.files[0].change.path + L("」的更改")
            } catch { try? await self.refresh(); throw error }
        }
    }
    @Published var fileClipboard: (root: String, paths: [String], cut: Bool)?
    var cutFilePaths: Set<String> {
        guard let clipboard = fileClipboard, clipboard.cut, clipboard.root == project?.path else { return [] }
        return Set(clipboard.paths)
    }
    func copyFiles(_ paths: [String], cut: Bool) {
        guard let root = project?.path else { return }
        let top = paths.sorted().filter { path in !paths.contains { path.hasPrefix($0 + "/") } }
        fileClipboard = (root, top, cut)
        notice = L(cut ? "已剪切 {0} 项，请在目标目录右键粘贴" : "已复制 {0} 项，请在目标目录右键粘贴", [String(describing: top.count)])
    }
    func editFiles(action: String, paths: [String], destination: String = "") {
        guard !busy, let root = project?.path, allowNavigation() else { return }
        let top = paths.sorted().filter { path in !paths.contains { path.hasPrefix($0 + "/") } }
        let clipboard = fileClipboard
        if action == "paste", clipboard == nil || clipboard?.root != root { return }
        perform {
            do {
                if action == "file" || action == "folder" {
                    try await Task.detached { try ExplorerFiles.create(root: root, path: destination, folder: action == "folder") }.value
                } else if action == "rename", let old = top.first {
                    try await Task.detached { try ExplorerFiles.transfer(root: root, source: old, destination: destination, move: true) }.value
                    self.updateMovedTabs(old: old, new: destination)
                } else if action == "delete" {
                    for path in top {
                        try await Task.detached {
                            let url = try ExplorerFiles.url(path, root: root)
                            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        }.value
                        self.updateMovedTabs(old: path, new: nil)
                    }
                } else if action == "paste", let clipboard, clipboard.root == root {
                    for old in clipboard.paths {
                        let target = try await Task.detached { try ExplorerFiles.paste(root: root, source: old, directory: destination, move: clipboard.cut) }.value
                        if clipboard.cut {
                            self.updateMovedTabs(old: old, new: target)
                            self.fileClipboard?.paths.removeAll { $0 == old }
                        }
                    }
                    if clipboard.cut { self.fileClipboard = nil }
                }
                try await self.refresh()
                if action == "file" { self.presentDocument(EditorDocument(id: destination, path: destination, text: "", savedText: "", editable: true, preview: false)) }
                self.notice = action == "delete" ? L("已移到废纸篓") : L("文件列表已更新")
            } catch {
                try? await self.refresh()
                throw error
            }
        }
    }
    private func updateMovedTabs(old: String, new: String?) {
        let active = activeTabID
        var nextActive = active
        tabs = tabs.compactMap { doc in
            guard doc.path == old || doc.path.hasPrefix(old + "/") else { return doc }
            guard let new else { return nil }
            let path = new + doc.path.dropFirst(old.count)
            let id = doc.isDiff ? String(doc.id.dropLast(doc.path.count)) + path : path
            if active == doc.id { nextActive = id }
            return EditorDocument(id: id, path: path, text: doc.text, savedText: doc.savedText, editable: doc.editable, preview: doc.preview, isDiff: doc.isDiff, baseline: doc.baseline, diffLines: doc.diffLines)
        }
        if let nextActive, tabs.contains(where: { $0.id == nextActive }) { activateTab(nextActive) }
        else if let first = tabs.first { activateTab(first.id) }
        else { clearEditors() }
    }
    func createFile(_ path: String) {
        guard let root = project?.path, allowNavigation() else { return }
        let parts = path.split(separator: "/")
        guard !path.isEmpty, !path.hasPrefix("/"), !parts.contains(".."), !parts.contains(".git") else { error = L("请输入项目内的相对路径，例如 src/main.js。"); return }
        let url = URL(fileURLWithPath: root).appendingPathComponent(path)
        guard url.resolvingSymlinksInPath().path.hasPrefix(root + "/"), !FileManager.default.fileExists(atPath: url.path) else { error = L("文件已存在或路径不在当前项目内。"); return }
        perform {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url, options: .withoutOverwriting)
            try await self.refresh()
            self.selected = nil; self.presentDocument(EditorDocument(id: path, path: path, text: "", savedText: "", editable: true, preview: false)); self.notice = L("已创建 ") + path
        }
    }
    func configure(name: String, email: String, remote: String, remoteName: String = "origin") {
        guard let root = project?.path else { return }
        perform {
            _ = try await Git.run(root, ["config", "--local", "user.name", name])
            _ = try await Git.run(root, ["config", "--local", "user.email", email])
            try await GitSettingsRemote.save(root, name: remoteName, url: remote)
            try await self.refresh(); self.notice = L("项目设置已保存")
        }
    }

    @Published var historyRefreshing = false
    private var historyRefreshTask: Task<Void, Never>?
    private var historyRefreshRevision = 0
    private func cancelHistoryRefresh() {
        historyRefreshRevision += 1; historyRefreshTask?.cancel(); historyRefreshTask = nil
        historyRefreshing = false
    }
    func refreshHistory() {
        guard !busy, !historyRefreshing, let root = project?.path else { return }
        historyRefreshRevision += 1
        let revision = historyRefreshRevision, page = historyPage
        historyRefreshing = true
        historyRefreshTask = Task {
            defer { if revision == self.historyRefreshRevision { self.historyRefreshing = false } }
            do {
                let hasHead = (try? await Git.run(root, ["rev-parse", "--verify", "HEAD"])) != nil
                let output = hasHead ? try await Git.run(root, ["log", "-z", "--max-count=51", "--skip=\(page * 50)", "--date=short", "--format=%H%x00%h%x00%s%x00%an%x00%ad"]) : ""
                let pending = try await PendingPush.read(root)
                guard !Task.isCancelled, revision == self.historyRefreshRevision, self.project?.path == root, self.historyPage == page else { return }
                let entries = CommitEntry.parse(output)
                self.historyHasNext = entries.count > 50; self.history = Array(entries.prefix(50))
                self.pendingPushIDs = pending.ids; self.pendingPullCount = pending.behind
                self.notice = L("提交历史已刷新")
            } catch {
                if !Task.isCancelled, revision == self.historyRefreshRevision, self.project?.path == root { self.error = error.localizedDescription }
            }
        }
    }
    func readHistory() async throws {
        guard let root = project?.path else { return }
        let output = (try? await Git.run(root, ["log", "-z", "--max-count=51", "--skip=\(historyPage * 50)", "--date=short", "--format=%H%x00%h%x00%s%x00%an%x00%ad"])) ?? ""
        let entries = CommitEntry.parse(output)
        historyHasNext = entries.count > 50; history = Array(entries.prefix(50))
    }
    func turnHistoryPage(_ delta: Int) {
        guard !busy else { return }
        perform { self.historyPage = max(0, self.historyPage + delta); try await self.readHistory() }
    }

}

import SwiftUI
import AppKit

let accent = Color(red: 0.12, green: 0.39, blue: 0.94)
let ink = Color.primary
let surface = Color(nsColor: AppTheme.subtle)
let hairline = Color.primary.opacity(0.07)

private var appVersionLabel: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("开发版")
    #if arch(arm64)
    return version + " · macOS M"
    #else
    return version + " · macOS Intel"
    #endif
}

struct BranchMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.23).fill(LinearGradient(colors: [Color(red: 0.14, green: 0.63, blue: 1), Color(red: 0.01, green: 0.34, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Path { p in
                    p.move(to: CGPoint(x: w * 0.25, y: w * 0.30))
                    p.addLine(to: CGPoint(x: w * 0.68, y: w * 0.26))
                    p.addCurve(to: CGPoint(x: w * 0.72, y: w * 0.32), control1: CGPoint(x: w * 0.75, y: w * 0.25), control2: CGPoint(x: w * 0.77, y: w * 0.28))
                    p.addLine(to: CGPoint(x: w * 0.28, y: w * 0.68))
                    p.addCurve(to: CGPoint(x: w * 0.32, y: w * 0.74), control1: CGPoint(x: w * 0.23, y: w * 0.72), control2: CGPoint(x: w * 0.25, y: w * 0.76))
                    p.addLine(to: CGPoint(x: w * 0.75, y: w * 0.70))
                }.stroke(.white, style: StrokeStyle(lineWidth: w * 0.085, lineCap: .round, lineJoin: .round))
                ForEach(0..<2) { i in
                    let point = i == 0 ? CGPoint(x: 0.25, y: 0.30) : CGPoint(x: 0.75, y: 0.70)
                    Circle().fill(.white).frame(width: w * 0.18, height: w * 0.18).position(x: w * point.x, y: w * point.y)
                }
            }
        }.accessibilityLabel(L("枝序 Git 分支标志"))
    }
}

@main struct ZhixuApp: App {
    init() { AppLanguage.bootstrap() }
    @StateObject private var model = Workspace()
    @AppStorage("colorMode") private var colorMode = "system"
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup(L("枝序 · 让 Git 简单一点")) {
            ContentView().environmentObject(model).frame(minWidth: 1080, minHeight: 720).tint(accent)
                .onAppear { delegate.model = model; AppTheme.apply(colorMode); NSApp.activate(ignoringOtherApps: true) }
        }.defaultSize(width: 1420, height: 900).windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) { Button(L("设置…")) { NotificationCenter.default.post(name: .init("ShowWorkspaceSettings"), object: nil) }.keyboardShortcut(",") }
            CommandGroup(replacing: .newItem) { Button(L("打开 Git 项目…")) { model.chooseProject() }.keyboardShortcut("o"); Button(L("创建项目…")) { model.chooseProject(create: true) }.keyboardShortcut("n") }
            CommandGroup(replacing: .saveItem) { Button(L("保存文件")) { if model.save() { model.perform { try await model.refresh() } } }.keyboardShortcut("s").disabled(!model.dirty) }
            CommandGroup(before: .windowList) { Button(L("关闭当前文件")) { if let id = model.activeTabID { model.closeTab(id) } }.keyboardShortcut("w").disabled(model.activeTabID == nil) }
            CommandMenu("Git") { Button(L("刷新变更")) { model.refreshChanges() }.keyboardShortcut("r"); Button(L("提交所选文件")) { model.commit() }.keyboardShortcut(.return, modifiers: [.command]).disabled(!model.canCommit) }
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: Workspace?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { model?.allowNavigation() == false ? .terminateCancel : .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
struct ContentView: View {
    @EnvironmentObject var m: Workspace
    @State var dialog: String?
    @State private var showingBranches = false
    @StateObject private var contextMenus = ThemedMenuPresenter.shared
    @State var input = ""
    @State private var fileAction: String?
    @State private var fileTargets: [String] = []
    @State private var fileParent = ""
    @State var section = "变更"
    @State var filter = ""
    @State var collapsedGroups = Set<String>()
    @State var selectionAnchor: String?
    @State var treeSelection = Set<String>()
    @StateObject private var explorerState = ExplorerState()
    @State var hoveredProject: String?
    @State private var hoveredCommit: String?
    @State var markdownPreviews = Set<String>()
    @State var editorPosition = L("行 1，列 1")
    @State private var showingStashes = false
    @State private var confirmDiscardSwitch = false
    @ViewBuilder private var branchSwitchDialog: some View {
        if let prompt = m.branchSwitchPrompt {
            ZStack {
                Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
                DialogCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) { DialogCloseButton { m.branchSwitchPrompt = nil }; Text(confirmDiscardSwitch ? L("放弃修改并切换？") : L("切换分支会覆盖当前修改")).font(.system(size: 14, weight: .medium)); Spacer() }.dialogHeader()
                        Text(L("目标分支：") + prompt.target.name).font(.system(size: 12, weight: .medium))
                        Text(confirmDiscardSwitch
                             ? L("将放弃全部 {0} 个变更文件的已暂存和未暂存更改。已有文件恢复到提交版本，新增文件移到废纸篓，然后切换分支。", [String(describing: prompt.changes.files.count)])
                             : L("当前有 {0} 个变更文件。请选择如何处理这些修改，或取消并留在当前分支。", [String(describing: prompt.changes.files.count)]))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        if confirmDiscardSwitch {
                            HStack {
                                Spacer()
                                Button(L("返回")) { confirmDiscardSwitch = false }.buttonStyle(DialogButtonStyle())
                                Button(L("确认放弃并切换")) { m.resolveBranchSwitch(.discard) }.buttonStyle(DialogButtonStyle(primary: true))
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                switchChoice(L("临时收起修改并切换"), detail: L("保存修改备份，切换后可手动恢复。"), choice: .stash)
                                switchChoice(L("携带修改切换"), detail: L("将修改应用到目标分支；可能产生冲突，备份会保留。"), choice: .carry)
                                Button { confirmDiscardSwitch = true } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L("放弃修改并切换")).foregroundStyle(.red)
                                        Text(L("丢弃当前修改，再切换到目标分支。")).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                }.buttonStyle(ChoiceCardStyle(destructive: true))
                            }
                            HStack { Spacer(); Button(L("取消")) { m.branchSwitchPrompt = nil }.buttonStyle(DialogButtonStyle()) }
                        }
                    }.frame(width: 450).disabled(m.busy)
                }
            }.onExitCommand { if !m.busy { m.branchSwitchPrompt = nil } }
             .onAppear { confirmDiscardSwitch = false }
        }
    }
    private func switchChoice(_ title: String, detail: String, choice: Workspace.BranchSwitchChoice) -> some View {
        Button { m.resolveBranchSwitch(choice) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }.buttonStyle(ChoiceCardStyle())
    }
    @ViewBuilder private var discardFileDialog: some View {
        if let plan = m.discardFile {
            ZStack {
                Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
                DialogCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) { DialogCloseButton { m.discardFile = nil }; Text(plan.all ? L("撤销所有更改？") : L("撤销此文件的更改？")).font(.system(size: 14, weight: .medium)); Spacer() }.dialogHeader()
                        if plan.all {
                            Text(L("将撤销当前项目全部 {0} 个变更文件。", [String(describing: plan.files.count)])).font(.system(size: 12))
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(plan.files, id: \.change.path) { file in
                                        Text(file.change.path).font(.system(size: 12, design: .monospaced))
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxHeight: 140)
                            Text(L("已暂存、未暂存的更改都会恢复到最近一次提交；新增文件将移到废纸篓。以上文件在编辑器中尚未保存的修改也会被丢弃。")).font(.system(size: 12)).foregroundStyle(.secondary)
                        } else if let file = plan.files.first {
                            Text(file.change.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            Text(file.removesNewFile
                                 ? L("这是新增文件，没有已提交的版本。现有文件将移到废纸篓，并取消暂存；可从访达恢复。")
                                 : L("此文件将恢复到最近一次提交的版本，已暂存、未暂存的修改都会被丢弃。"))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            if file.change.original != nil { Text(L("重命名前后的路径都会恢复到提交时的状态。")).font(.system(size: 12)).foregroundStyle(.secondary) }
                            Text(L("仅处理此文件，不影响其他勾选文件。此文件在编辑器中尚未保存的修改也会被丢弃。"))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        HStack {
                            Spacer()
                            Button(L("取消")) { m.discardFile = nil }.buttonStyle(DialogButtonStyle())
                            Button(plan.all ? L("撤销所有更改") : L("撤销更改")) { m.applyDiscard() }.buttonStyle(DialogButtonStyle(primary: true)).disabled(m.busy)
                        }
                    }.frame(width: 440)
                }
            }.onExitCommand { m.discardFile = nil }
        }
    }
    @ViewBuilder private var fileActionDialog: some View {
            if let action = fileAction {
                ZStack {
                    Color.black.opacity(0.22).ignoresSafeArea()
                    DialogCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 10) { DialogCloseButton { fileAction = nil }; Text(action == "delete" ? L("移到废纸篓") : action == "rename" ? L("重命名") : action == "folder" ? L("创建文件夹") : L("创建文件")).font(.system(size: 14, weight: .medium)); Spacer() }.dialogHeader()
                            Text(action == "delete" ? L("将选中的 {0} 项移到废纸篓，可在访达中恢复。", [String(describing: fileTargets.count)]) : L("位置：") + (fileParent.isEmpty ? L("项目根目录") : fileParent)).font(.system(size: 12)).foregroundStyle(.secondary)
                            if action != "delete" { TextField(L("名称"), text: $input).textFieldStyle(.plain).padding(10).background(surface, in: RoundedRectangle(cornerRadius: 8)) }
                            HStack {
                                Spacer()
                                Button(L("取消")) { fileAction = nil }.buttonStyle(DialogButtonStyle())
                                Button(action == "delete" ? L("移到废纸篓") : L("确定")) {
                                    let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let destination = fileParent.isEmpty ? name : fileParent + "/" + name
                                    fileAction = nil
                                    m.editFiles(action: action, paths: fileTargets, destination: destination)
                                    treeSelection = []
                                }.buttonStyle(DialogButtonStyle(primary: true)).disabled(action != "delete" && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }.frame(width: 420)
                    }
                }.onExitCommand { fileAction = nil }
            }
    }
    @ViewBuilder private var branchActionDialog: some View {
            if let plan = m.branchAction {
                ZStack {
                    Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
                    DialogCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) { DialogCloseButton { m.branchAction = nil }; Text((m.branchActionIsDelete ? L("删除") : L("重命名")) + (plan.branch.remote ? L("远程分支") : L("本地分支"))).font(.system(size: 14, weight: .medium)); Spacer() }.dialogHeader()
                            Text(plan.branch.name).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            Text(plan.branch.remote
                                 ? (m.branchActionIsDelete ? L("将删除远程仓库中的这个分支，其他协作者也会受到影响。") : L("将在远程仓库创建新名称并删除旧名称，同时更新本地跟踪关系。"))
                                 : (m.branchActionIsDelete ? L("只删除本地分支，工作区文件不变；有未合并提交时不会删除。") : L("修改本地分支名称，工作区文件和远程分支不变。")))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            if !m.branchActionIsDelete {
                                TextField(L("新分支名称"), text: $m.branchActionName).textFieldStyle(.plain).padding(10)
                                    .background(surface, in: RoundedRectangle(cornerRadius: 8))
                            }
                            HStack {
                                Spacer()
                                Button(L("取消")) { m.branchAction = nil }.buttonStyle(DialogButtonStyle())
                                Button(m.branchActionIsDelete ? L("确认删除") : L("确认重命名")) { m.applyBranchAction() }
                                    .buttonStyle(DialogButtonStyle(primary: true))
                                    .disabled(m.busy || (!m.branchActionIsDelete && (m.branchActionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || m.branchActionName == plan.shortName)))
                            }
                        }.frame(width: 460)
                    }
                }.onExitCommand { m.branchAction = nil }
            }
    }
    @ViewBuilder private var historyActionDialog: some View {
            if let item = m.historyAction {
                ZStack {
                    Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
                    DialogCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) { DialogCloseButton { m.historyAction = nil }; Text(m.historyActionIsAmend ? L("修改提交说明") : L("撤销最近一次提交？")).font(.system(size: 14, weight: .medium)); Spacer() }.dialogHeader()
                            Text(item.shortID + " · " + item.subject).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                            Text(m.historyActionIsAmend ? L("只修改这条提交的说明，不包含当前未提交的修改。") : L("提交将退回上一次记录，代码修改和暂存内容都会保留，可在变更列表重新提交。"))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            Text(L("未推送状态以最近获取的远程信息为准。")).font(.system(size: 11)).foregroundStyle(.secondary)
                            if m.historyActionIsAmend {
                                TextEditor(text: $m.historyActionMessage).font(.system(size: 13)).scrollContentBackground(.hidden)
                                    .padding(8).frame(height: 110).background(surface, in: RoundedRectangle(cornerRadius: 8))
                            }
                            HStack {
                                Spacer()
                                Button(L("取消")) { m.historyAction = nil }.buttonStyle(DialogButtonStyle())
                                Button(m.historyActionIsAmend ? L("保存说明") : L("撤销并保留修改")) { m.applyHistoryAction() }
                                    .buttonStyle(DialogButtonStyle(primary: true))
                                    .disabled(m.busy || (m.historyActionIsAmend && m.historyActionMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                            }
                        }.frame(width: 460)
                    }
                }.onExitCommand { m.historyAction = nil }
            }
    }
    @ViewBuilder private var generalDialog: some View {
            if dialog != nil || m.error != nil {
                ZStack {
                    Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
                    if let error = m.error {
                        DialogCard { VStack(alignment: .leading, spacing: 18) { HStack(spacing: 10) { DialogCloseButton { m.error = nil }; Text(L("操作未完成")).font(.system(size: 14, weight: .medium)); Spacer() }.dialogHeader(); Text(error).textSelection(.enabled); HStack { Spacer(); Button(L("知道了")) { m.error = nil }.buttonStyle(DialogButtonStyle(primary: true)) } }.frame(width: 440) }
                    } else if dialog == "settings" { WorkspaceSettings(close: { dialog = nil }).environmentObject(m) }
                    else { DialogCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) { DialogCloseButton { dialog = nil }; Text(dialog == "clone" ? L("克隆远程项目") : dialog == "file" ? L("新建文件") : L("创建本地分支")).font(.system(size: 14, weight: .medium)); Spacer() }.dialogHeader()
                Text(dialog == "clone" ? L("输入仓库的 HTTPS 或 SSH 地址，随后选择保存位置。") : dialog == "file" ? L("输入相对路径，也可以同时创建文件夹。") : L("从当前提交创建并切换到新分支。")).foregroundStyle(.secondary)
                TextField("", text: $input, prompt: Text(verbatim: dialog == "clone" ? "git@github.com:you/project.git" : dialog == "file" ? "src/main.js" : "feature/my-feature").foregroundColor(.secondary))
                    .textFieldStyle(.plain).padding(10).frame(maxWidth: .infinity).background(surface, in: RoundedRectangle(cornerRadius: 8))
                HStack { Spacer(); Button(L("取消")) { dialog = nil }.buttonStyle(DialogButtonStyle()); Button(dialog == "branch" ? L("创建分支") : L("继续")) { let type = dialog; dialog = nil; if type == "clone" { m.clone(input) } else if type == "file" { m.createFile(input) } else { m.newBranch(input) } }.buttonStyle(FlatButtonStyle(kind: .primary)).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.frame(width: 430).fixedSize(horizontal: false, vertical: true)
                    } }
                }
            }
    }
    private func explorerMenu(_ path: String?, folder: Bool) -> [AppMenuItem] {
        let parent = path.map { folder ? $0 : ($0 as NSString).deletingLastPathComponent } ?? ""
        let targets = path.map { treeSelection.contains($0) ? Array(treeSelection) : [$0] } ?? []
        func prompt(_ action: String) {
            fileTargets = targets; fileParent = parent
            if action == "rename", let path {
                fileParent = (path as NSString).deletingLastPathComponent
                input = (path as NSString).lastPathComponent
            } else { input = "" }
            fileAction = action
        }
        var items = [
            AppMenuItem(title: L("创建文件…"), icon: "doc.badge.plus", enabled: !m.busy) { prompt("file") },
            AppMenuItem(title: L("创建文件夹…"), icon: "folder.badge.plus", enabled: !m.busy) { prompt("folder") },
            AppMenuItem(title: L("在访达中打开"), icon: "folder", enabled: m.project != nil) {
                guard let root = m.project?.path else { return }
                let url = URL(fileURLWithPath: root).appendingPathComponent(path ?? "")
                if folder { NSWorkspace.shared.open(url) } else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            },
            AppMenuItem(title: L("剪切"), icon: "scissors", enabled: !m.busy && path != nil) { m.copyFiles(targets, cut: true) },
            AppMenuItem(title: L("复制"), icon: "doc.on.doc", enabled: !m.busy && path != nil) { m.copyFiles(targets, cut: false) },
            AppMenuItem(title: L("粘贴"), icon: "doc.on.clipboard", enabled: !m.busy && m.fileClipboard?.root == m.project?.path && m.fileClipboard != nil) { m.editFiles(action: "paste", paths: [], destination: parent) },
            AppMenuItem(title: L("重命名…"), icon: "pencil", enabled: !m.busy && targets.count == 1) { prompt("rename") },
            AppMenuItem(title: L("删除…"), icon: "trash", enabled: !m.busy && path != nil) { prompt("delete") }
        ]
        if let path, !folder { items.append(AppMenuItem(title: L("查看差异"), icon: "doc.text.magnifyingglass", enabled: !m.busy) { m.loadDiff(path, staged: false) }) }
        if let path {
            if !folder { items.append(AppMenuItem(title: L("文件历史…"), icon: "clock", enabled: !m.busy) { m.showReview(.file(path)) }) }
            items += ignoreMenu(path, folder: folder)
        }
        return items
    }
    private func ignoreMenu(_ path: String, folder: Bool = false) -> [AppMenuItem] {
        var items = [AppMenuItem(title: folder ? L("忽略此文件夹…") : L("忽略此文件…"), icon: "eye.slash", enabled: !m.busy) { m.prepareIgnore(path: path, kind: folder ? .folder : .file) }]
        let parent = (path as NSString).deletingLastPathComponent
        if !folder && !parent.isEmpty { items.append(AppMenuItem(title: L("忽略所在文件夹…"), icon: "folder.badge.minus", enabled: !m.busy) { m.prepareIgnore(path: parent, kind: .folder) }) }
        if !folder && !(path as NSString).pathExtension.isEmpty { items.append(AppMenuItem(title: L("忽略此类文件…"), icon: "doc.badge.minus", enabled: !m.busy) { m.prepareIgnore(path: path, kind: .suffix) }) }
        return items
    }
    private var workspaceLayout: some View {
        VStack(spacing: 0) {
            AppTitleBar().frame(height: 45)
            HStack(spacing: 12) {
                sidebar.frame(width: 220).panelCard()
                VStack(spacing: 10) {
                    toolbar.panelCard()
                    if m.project == nil { welcome.panelCard() } else {
                        ResizableWorkspace(left: changePanel, right: detail)
                    }
                }
            }.padding(.horizontal, 12).padding(.bottom, 8)
            HStack(spacing: 8) {
                Circle().fill(m.busy ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(m.busy ? L("正在处理，请稍候…") : m.notice)
                if m.canCancelGit { Button(L("取消")) { m.cancelGitOperation() }.buttonStyle(CursorPlainButtonStyle()).actionCursor() }
                Spacer()
                if m.project != nil { Image(systemName: "point.3.connected.trianglepath.dotted"); Text(m.upstream == "未关联远程分支" ? L("未关联远程分支") : m.upstream) }
                Text(appVersionLabel).padding(.leading, 12).fixedSize()
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 26)
        }.background(Color(nsColor: AppTheme.canvas)).foregroundStyle(ink).ignoresSafeArea(.container, edges: .top)
    }
    private var hasModal: Bool {
        m.pullRequest != nil || m.pushRequest != nil || m.missingGit || dialog != nil || fileAction != nil || m.remoteFailure != nil || m.error != nil || m.discardFile != nil || m.branchSwitchPrompt != nil || m.branchAction != nil || m.historyAction != nil || showingStashes || m.restoreConflict != nil || m.reviewRequest != nil || m.conflictFile != nil || m.toolConfirmation != nil
    }
    private var workspaceWithBranches: some View {
        workspaceLayout
        .disabled(hasModal || showingBranches || contextMenus.request != nil)
        .allowsHitTesting(!hasModal && !showingBranches && contextMenus.request == nil)
        .onReceive(NotificationCenter.default.publisher(for: .init("ShowWorkspaceSettings"))) { _ in dialog = "settings" }
        .onChange(of: m.project?.path) { _, _ in m.pullRequest = nil; m.pushRequest = nil; treeSelection = []; selectionAnchor = nil; filter = ""; fileAction = nil; m.discardFile = nil; m.branchSwitchPrompt = nil; m.reviewRequest = nil; m.conflictFile = nil; m.toolConfirmation = nil; explorerState.reset() }
        .onChange(of: dialog) { _, _ in showingBranches = false }
        .onChange(of: m.project?.path) { _, _ in showingBranches = false }
        .onChange(of: m.busy) { _, busy in if busy { showingBranches = false } }
        .overlayPreferenceValue(BranchButtonAnchor.self) { anchor in
            if showingBranches, let anchor {
                GeometryReader { geometry in
                    let bounds = geometry[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { showingBranches = false }
                        BranchPicker(branches: m.branches, current: m.branch, select: { branch in
                            showingBranches = false
                            m.checkout(branch)
                        }, create: {
                            showingBranches = false
                            if m.branches.contains(where: { !$0.remote && $0.name == m.branch && $0.unborn }) {
                                m.error = L("当前分支尚无提交，请先勾选文件并完成首次提交，再创建新分支。首次提交后，原分支和新分支都会保留。")
                            } else { input = ""; dialog = "branch" }
                        },
                           canDelete: m.canDeleteBranch,
                           rename: { m.prepareBranchAction($0, delete: false) },
                           delete: { m.prepareBranchAction($0, delete: true) },
                           compare: { showingBranches = false; m.compareBranch($0) },
                           merge: { target in showingBranches = false; m.prepareMerge(ref: (target.remote ? "refs/remotes/" : "refs/heads/") + target.name) })
                        .offset(x: max(12, min(bounds.minX, geometry.size.width - 312)), y: bounds.maxY + 8)
                    }.onExitCommand { showingBranches = false }
                }
            }
        }
    }
    var body: some View {
        workspaceWithBranches
        .onChange(of: contextMenus.request != nil) { _, shown in if shown && contextMenus.request?.keepsBranchPickerOpen != true { showingBranches = false } }
        .onChange(of: dialog) { _, _ in ThemedMenuPresenter.dismiss() }
        .onChange(of: m.busy) { _, busy in if busy { ThemedMenuPresenter.dismiss() } }
        .overlay { AppMenuOverlay(presenter: contextMenus) }
        .overlay { fileActionDialog }
        .overlay { discardFileDialog }
        .overlay { branchSwitchDialog }
        .overlay { branchActionDialog }
        .overlay { if let request = m.pullRequest { PullTargetDialog(model: m, request: request) } }
        .overlay { if let request = m.pushRequest { PushTargetDialog(model: m, request: request) } }
        .overlay {
            if showingStashes, let root = m.project?.path {
                StashBrowser(root: root, close: { showingStashes = false }, restore: { record in
                    showingStashes = false
                    m.restoreStashRecord(record)
                })
            }
        }
        .overlay { historyActionDialog }
        .overlay {
            if let entry = m.restoreConflict {
                ZStack {
                    Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
                    RestoreConflictDialog(entry: entry, progress: m.restoreConflictProgress, answer: m.answerRestore)
                        .id(entry.path)
                }.onExitCommand { m.answerRestore(.cancel) }
            }
        }
        .overlay { if let request = m.reviewRequest { GitReviewBrowser(model: m, request: request).id(request.id) } }
        .overlay { if let conflict = m.conflictFile { ConflictEditorDialog(model: m, conflict: conflict).id(conflict.path) } }
        .overlay { if let confirmation = m.toolConfirmation { GitToolConfirmationView(model: m, confirmation: confirmation) } }
        .overlay { generalDialog }
        .overlay { if let failure = m.remoteFailure { RemoteFailureDialog(model: m, failure: failure, settings: { dialog = "settings" }).id(failure.id) } }
        .overlay { if m.missingGit { GitSetupDialog(model: m) } }
        .background(ScrollStyleInstaller())
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                BranchMark().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) { Text(L("枝序")).font(.system(size: 17, weight: .semibold)); Text(L("让 Git 简单一点")).font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 20).frame(height: 52).padding(.bottom, 20)
            HStack { Text(L("我的项目")).font(.system(size: 11, weight: .semibold)); Spacer(); Text("\(m.projects.count)").font(.system(size: 11, design: .monospaced)) }.foregroundStyle(.secondary).padding(.horizontal, 22)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(m.projects) { p in
                        Button { m.switchProject(p) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "square.stack.3d.up").foregroundStyle(m.project == p ? accent : .secondary)
                                VStack(alignment: .leading, spacing: 4) { Text(p.name).font(.system(size: 13, weight: .semibold)).lineLimit(1); Text(p.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                                Spacer(minLength: 0)
                                if m.project == p { Circle().fill(accent).frame(width: 5, height: 5) }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(m.project == p ? accent.opacity(0.09) : hoveredProject == p.id ? Color.primary.opacity(0.035) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .leading) { if m.project == p { RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: 2, height: 24) } }
                        }.buttonStyle(CursorPlainButtonStyle()).disabled(m.busy)
                        .onHover { hoveredProject = $0 ? p.id : nil }
                        .themedContextMenu { [
                            AppMenuItem(title: L("在访达中显示"), icon: "folder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: p.path) },
                            AppMenuItem(title: L("从列表移除（保留文件）"), icon: "minus.circle", enabled: !m.busy) { m.removeProject(p) }
                        ] }
                    }
                }.padding(12)
            }
            VStack(spacing: 10) {
                Button { m.chooseProject(create: true) } label: { Label(L("创建新项目"), systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(FlatButtonStyle(kind: .primary))
                HStack { Button(L("打开项目")) { m.chooseProject() }; Spacer(); Button(L("克隆仓库")) { input = ""; dialog = "clone" } }.buttonStyle(CursorPlainButtonStyle()).font(.system(size: 12)).foregroundStyle(accent)
            }.disabled(m.busy).padding(18)
        }.background(surface)
    }
    var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) { Text(m.project?.name ?? L("工作空间")).font(.system(size: 15, weight: .semibold)).lineLimit(1); Text(m.project?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? L("打开项目，开始工作")).font(.system(size: 11)).foregroundStyle(.secondary) }
            Spacer()
            if m.project != nil {
                Button { showingBranches.toggle() } label: {
                    Label { Text(m.branch == "游离 HEAD" ? L("游离 HEAD") : m.branch) } icon: { GitBranchIcon() }.font(.system(size: 12, weight: .medium))
                }.fixedSize().help(L("选择分支"))
                    .anchorPreference(key: BranchButtonAnchor.self, value: .bounds) { $0 }

                Button { section = "历史" } label: {
                    Label(L("待推送 {0} 条", [String(describing: m.pendingPushIDs.count)]), systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(m.pendingPushIDs.isEmpty ? Color.secondary : accent)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(accent.opacity(m.pendingPushIDs.isEmpty ? 0.04 : 0.10), in: RoundedRectangle(cornerRadius: 5))
                }.help(m.upstream == "未关联远程分支" ? L("尚未关联远程分支；统计当前分支中所有已知远程分支都没有的提交。点击查看历史。") : L("相对 {0} 的本地提交，基于最近一次获取或推送的信息。点击查看历史；点击获取可更新远程状态。", [String(describing: m.upstream)]))
                if m.upstream != "未关联远程分支" {
                    Button { m.showReview(.compare("@{upstream}")) } label: {
                        Label(L("待拉取 {0} 条", [String(describing: m.pendingPullCount)]) + (m.pendingPullCount > 0 && !m.pendingPushIDs.isEmpty ? L(" · 已分叉") : ""), systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(m.pendingPullCount > 0 ? Color.orange : .secondary)
                    }.help(L("基于最近获取的远程信息；点击查看双方独有提交及文件差异"))
                }
                Divider().frame(height: 22)
                Button { m.sync("fetch") } label: { Label(L("获取"), systemImage: "arrow.clockwise") }.help(L("获取：更新远程分支和提交信息，不合并到当前分支"))
                Button { m.sync("pull") } label: { Label(L("拉取"), systemImage: "arrow.down") }.help(L("拉取：获取远程更新；分叉时确认合并后继续"))
                Button { m.sync("push") } label: { Label(L("推送"), systemImage: "arrow.up") }.help(L("推送：将当前分支的本地提交上传到远程仓库"))
                Button { m.refreshChanges() } label: { Image(systemName: "arrow.triangle.2.circlepath") }.help(L("刷新：重新读取本地变更状态，不联网、不拉取代码 ⌘R"))

            }
            Button { dialog = "settings" } label: { Image(systemName: "gearshape") }.help(L("设置 ⌘,"))
        }.buttonStyle(FlatButtonStyle(kind: .quiet)).disabled(m.busy).padding(.horizontal, 24).frame(height: 52).background(Color(nsColor: AppTheme.panel))
    }
    var welcome: some View {
        VStack(spacing: 20) {
            BranchMark().frame(width: 56, height: 56)
            Text(L("开始你的下一个项目")).font(.system(size: 28, weight: .bold))
            Text(L("管理分支、审阅修改、提交代码。\n所有项目，一个工作空间。")).multilineTextAlignment(.center).foregroundStyle(.secondary).lineSpacing(8)
            HStack(spacing: 14) { Button(L("创建新项目")) { m.chooseProject(create: true) }.buttonStyle(FlatButtonStyle(kind: .primary)); Button(L("打开已有项目")) { m.chooseProject() }.buttonStyle(FlatButtonStyle(kind: .secondary)) }.controlSize(.large).padding(.top, 12)
            HStack(spacing: 28) { Label(L("多项目切换"), systemImage: "square.stack"); Label(L("逐文件暂存"), systemImage: "checkmark.square"); Label(L("内置代码编辑"), systemImage: "curlybraces") }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 26)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.985, green: 0.99, blue: 0.995))
    }
    var treeBinding: Binding<Set<String>> {
        Binding(get: { treeSelection }, set: { new in
            let added = new.subtracting(treeSelection)
            treeSelection = new
            if added.count == 1, let path = added.first, m.files.contains(path) { m.load(path, staged: false) }
        })
    }
    var changePanel: some View {
        VStack(spacing: 0) {
            WorkspaceTabs(selection: $section).padding(.horizontal, 16).padding(.bottom, section == "历史" ? 18 : section == "文件" ? 4 : 6)
            if section == "变更" {
                HStack { Text(L("工作区变更")).font(.system(size: 13, weight: .semibold)); Text("\(m.changes.count)").font(.caption).foregroundStyle(.secondary); Spacer()
                    Button { m.refreshChanges() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium)).frame(width: 24, height: 24).contentShape(Rectangle())
                    }.buttonStyle(CursorPlainButtonStyle()).foregroundStyle(.secondary).disabled(m.busy || m.changesRefreshing).help(L("刷新工作区变更 ⌘R")).accessibilityLabel(L("刷新工作区变更"))
                    Button {
                    ThemedMenuPresenter.showMore([
                        AppMenuItem(title: m.advancedMode ? L("退出高级模式") : L("高级模式：手动暂存"), icon: "slider.horizontal.3", enabled: !m.busy) { m.advancedMode.toggle() },
                        AppMenuItem(title: L("临时收起修改"), icon: "archivebox", enabled: !m.busy && !m.changes.isEmpty) { m.sync("stash") },
                        AppMenuItem(title: L("临时收起的修改…"), icon: "archivebox", enabled: !m.busy) { showingStashes = true }
                    ])
                } label: { Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium)).frame(width: 26, height: 24).contentShape(Rectangle()) }.buttonStyle(CursorPlainButtonStyle()).help(L("更多")).background(MoreMenuAnchor()) }.frame(height: 28).padding(.horizontal, 16).padding(.bottom, 6)
                if m.operationKind != nil || m.changes.contains(where: \.conflict) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(m.operationKind != nil ? L("正在进行：") + m.operationTitle : L("存在待解决的冲突")).font(.system(size: 12, weight: .semibold))
                        Text(L("点击冲突文件处理，保存并标记已解决后继续。")).font(.system(size: 10)).foregroundStyle(.secondary)
                        if m.operationKind != nil {
                            HStack {
                                Button(L("继续操作")) { m.continueGitOperation() }.disabled(m.changes.contains(where: \.conflict))
                                Button(L("中止…")) { m.prepareAbort() }
                            }.buttonStyle(DialogButtonStyle())
                        }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12).padding(.bottom, 6)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        if m.advancedMode {
                            HStack { Text(L("高级模式 · 手动暂存")); Spacer(); Button(L("退出")) { m.advancedMode = false }.buttonStyle(CursorPlainButtonStyle()).foregroundStyle(accent) }
                                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 6)
                            fileGroup(L("未暂存"), subtitle: L("勾选文件后可手动暂存"), items: m.changes.filter(\.unstaged), staged: false)
                            fileGroup(L("已暂存"), subtitle: L("仅提交勾选文件的已暂存内容"), items: m.changes.filter(\.staged), staged: true)
                        } else {
                            flatChanges
                        }
                    }
                }
                commitBox
            } else if section == "文件" {
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                        TextField(L("搜索项目文件…"), text: $filter).textFieldStyle(.plain).font(.system(size: 12))
                        if !filter.isEmpty {
                            Button { filter = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                                .buttonStyle(CursorPlainButtonStyle()).foregroundStyle(.secondary).help(L("清空搜索"))
                        }
                    }.padding(.horizontal, 9).frame(height: 30)
                        .background(surface, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(hairline))
                    Button { m.refreshFiles() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12)).frame(width: 28, height: 30)
                    }.buttonStyle(FlatButtonStyle(kind: .quiet)).disabled(m.busy || m.filesRefreshing)
                        .help(L("刷新文件列表，保留当前编辑和选择")).accessibilityLabel(L("刷新文件列表"))
                }.padding(.horizontal, 12)
                FileExplorer(state: explorerState, paths: m.files.filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }, changes: m.changes, searching: !filter.isEmpty,
                             cutPaths: m.cutFilePaths, ignoredPaths: m.ignoredFiles, expandFolder: { m.expandIgnoredFolder($0) },
                             shortcutsEnabled: !m.busy && dialog == nil && fileAction == nil && m.error == nil && m.discardFile == nil && m.branchSwitchPrompt == nil && m.reviewRequest == nil && m.conflictFile == nil && m.toolConfirmation == nil && !showingStashes && contextMenus.request == nil,
                             clipboardAction: { key, paths, destination in
                                 if key == "v" { m.editFiles(action: "paste", paths: [], destination: destination) }
                                 else if !paths.isEmpty { m.copyFiles(paths, cut: key == "x") }
                             }, selection: $treeSelection, openFile: { path in
                    m.load(path, staged: false)
                }, pinFile: { path in
                    m.load(path, staged: false); m.pinTab(path)
                }, menuItems: { path, folder in explorerMenu(path, folder: folder) }).id(m.project?.path)
                HStack {
                    if !treeSelection.isEmpty { Text(L("已选 {0} 项", [String(describing: treeSelection.count)])).font(.system(size: 10)).foregroundStyle(.secondary) }
                    Spacer()
                    if m.advancedMode { Button(L("暂存所选变更")) {
                        m.stage(m.changes.filter { change in change.unstaged && treeSelection.contains { change.path == $0 || change.path.hasPrefix($0 + "/") } })
                    }.font(.system(size: 11)).disabled(!m.changes.contains { change in change.unstaged && treeSelection.contains { change.path == $0 || change.path.hasPrefix($0 + "/") } })
                    }
                }.padding(12)
            } else {
                HStack {
                    Text(L("提交历史")).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(L("每页 50 条")).font(.caption).foregroundStyle(.secondary)
                    Button { m.refreshHistory() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12)).frame(width: 26, height: 24).contentShape(Rectangle())
                    }.buttonStyle(CursorPlainButtonStyle()).foregroundStyle(.secondary)
                        .disabled(m.busy || m.historyRefreshing || m.project == nil)
                        .help(L("刷新提交历史")).accessibilityLabel(L("刷新提交历史"))
                }.padding(.horizontal, 18).padding(.bottom, 12)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(m.history) { item in
                            Button { m.showReview(.commit(item.id)) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "circle.inset.filled").foregroundStyle(accent).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.shortID + "  " + item.subject).font(.system(size: 12, weight: .medium))
                                    Text(item.author + " · " + item.date).font(.system(size: 10)).foregroundStyle(.secondary)
                                    if m.pendingPushIDs.contains(item.id) {
                                        Label(L("未推送"), systemImage: "arrow.up.circle.fill")
                                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(accent)
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
                                    }
                                }
                            }.padding(.vertical, 12).padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
                                .background(hoveredCommit == item.id ? accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                                .onHover { hoveredCommit = $0 ? item.id : (hoveredCommit == item.id ? nil : hoveredCommit) }
                                .animation(.easeOut(duration: 0.12), value: hoveredCommit == item.id)
                            }.buttonStyle(CursorPlainButtonStyle())
                                .disabled(m.busy)
                                .themedContextMenu {
                                    [AppMenuItem(title: L("查看提交详情…"), icon: "doc.text.magnifyingglass") { m.showReview(.commit(item.id)) },
                                     AppMenuItem(title: L("生成反向提交…"), icon: "arrow.uturn.backward", enabled: !m.busy) { m.prepareRevert(item) },
                                     AppMenuItem(title: L("复制提交哈希"), icon: "doc.on.doc") {
                                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.id, forType: .string)
                                    }, AppMenuItem(title: L("撤销提交，保留修改"), icon: "arrow.uturn.backward", enabled: m.canChangeHistory(item)) {
                                        m.prepareHistoryAction(item, amend: false)
                                    }, AppMenuItem(title: L("修改提交说明"), icon: "square.and.pencil", enabled: m.canChangeHistory(item)) {
                                        m.prepareHistoryAction(item, amend: true)
                                    }]
                                }
                            Divider()
                        }

                    }.padding(.horizontal, 10)
                }.id(m.historyPage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if m.history.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "clock").font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
                                Text(m.historyPage == 0 ? L("暂无提交历史") : L("本页暂无记录")).font(.system(size: 13, weight: .medium))
                                Text(m.historyPage == 0 ? L("完成首次提交后，历史记录会显示在这里。") : L("请返回上一页查看。")).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                if !m.history.isEmpty || m.historyPage > 0 {
                HStack {
                    Button { m.turnHistoryPage(-1) } label: { Label(L("上一页"), systemImage: "chevron.left") }.disabled(m.historyPage == 0)
                    Spacer()
                    Text(L("第 {0} 页", [String(describing: m.historyPage + 1)])).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button { m.turnHistoryPage(1) } label: { Label(L("下一页"), systemImage: "chevron.right") }.disabled(!m.historyHasNext)
                }.buttonStyle(FlatButtonStyle(kind: .quiet)).font(.system(size: 11)).padding(16)
                }

            }
        }.background(Color(nsColor: AppTheme.panel)).disabled(m.busy)
    }
    func selectChange(_ c: Change, items: [Change], staged: Bool) {
        if c.conflict { m.resolveConflict(c.path); return }
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift), let anchor = selectionAnchor, let first = items.firstIndex(where: { $0.path == anchor }), let last = items.firstIndex(where: { $0.path == c.path }) {
            m.checked.formUnion(items[min(first, last)...max(first, last)].map(\.path))
        } else if modifiers.contains(.command) {
            if m.checked.contains(c.path) { m.checked.remove(c.path) } else { m.checked.insert(c.path) }
            selectionAnchor = c.path
        } else {
            selectionAnchor = c.path
        }
        m.loadDiff(c.path, staged: staged, combined: !m.advancedMode)
    }
    var flatChanges: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Toggle(L("全选变更文件"), isOn: Binding(get: { !m.changes.isEmpty && m.changes.allSatisfy { m.checked.contains($0.path) } }, set: { value in
                    if value { m.checked.formUnion(m.changes.map(\.path)) } else { m.checked.subtract(m.changes.map(\.path)) }
                })).labelsHidden().toggleStyle(ThemeCheckboxStyle(mixed: !m.checked.isEmpty && !m.changes.allSatisfy { m.checked.contains($0.path) })).disabled(m.changes.isEmpty)
                Text(L("全选")).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 6).frame(height: 28)
            changeRows(m.changes, staged: false)
            if m.changes.isEmpty {
                Text(L("工作区很干净")).font(.system(size: 11)).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 20)
            }
        }.padding(.horizontal, 10).padding(.bottom, 8)
    }
    @ViewBuilder func changeRows(_ items: [Change], staged: Bool) -> some View {
                ForEach(items) { c in
                    ChangeFileRow(change: c, staged: staged, advanced: m.advancedMode, checked: Binding(get: { m.checked.contains(c.path) }, set: {
                        if $0 { m.checked.insert(c.path) } else { m.checked.remove(c.path) }; selectionAnchor = c.path
                    }), select: { selectChange(c, items: items, staged: staged) }, stage: { m.stage([c], undo: staged) })
                    .themedContextMenu {
                        var items = [
                        AppMenuItem(title: L("查看差异"), icon: "doc.text.magnifyingglass", enabled: !m.busy) { m.loadDiff(c.path, staged: staged, combined: !m.advancedMode) },
                        AppMenuItem(title: L("撤销更改…"), icon: "arrow.uturn.backward", enabled: !m.busy && !c.conflict) { m.prepareDiscard(c) }
                        ]
                        if c.conflict { items.insert(AppMenuItem(title: L("解决冲突…"), icon: "arrow.triangle.merge", enabled: !m.busy) { m.resolveConflict(c.path) }, at: 0) }
                        items.append(AppMenuItem(title: L("文件历史…"), icon: "clock", enabled: !m.busy) { m.showReview(.file(c.path)) })
                        items += ignoreMenu(c.path)
                        if m.allChangesChecked {
                            items.append(AppMenuItem(title: L("撤销所有更改…"), icon: "arrow.uturn.backward.circle", enabled: !m.busy && !m.changes.contains(where: { $0.conflict })) { m.prepareDiscardAll() })
                        }
                        return items
                    }
                }
    }
    func fileGroup(_ title: String, subtitle: String, items: [Change], staged: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Button {
                    if collapsedGroups.contains(title) { collapsedGroups.remove(title) } else { collapsedGroups.insert(title) }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: collapsedGroups.contains(title) ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .bold)).frame(width: 9)
                        Circle().fill(staged ? Color.green : accent).frame(width: 5, height: 5)
                        Text(title).font(.system(size: 12, weight: .semibold))
                        Text("\(items.count)").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(CursorPlainButtonStyle()).help(L("展开或收起") + title)
                if m.advancedMode && !items.isEmpty {
                    Button(staged ? L("取消所选") : L("暂存所选")) { m.stage(items.filter { m.checked.contains($0.path) }, undo: staged) }.font(.system(size: 10)).disabled(!items.contains { m.checked.contains($0.path) })
                }
            }.padding(.horizontal, 10).frame(height: 36)
            if !collapsedGroups.contains(title) {
                HStack(spacing: 7) {
                    Toggle(L("全选") + title, isOn: Binding(get: { !items.isEmpty && items.allSatisfy { m.checked.contains($0.path) } }, set: { selected in
                        if selected { m.checked.formUnion(items.map(\.path)) } else { m.checked.subtract(items.map(\.path)) }
                    })).labelsHidden().toggleStyle(ThemeCheckboxStyle(mixed: items.contains { m.checked.contains($0.path) } && !items.allSatisfy { m.checked.contains($0.path) })).disabled(items.isEmpty)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.horizontal, 10).padding(.bottom, 5)
                if items.isEmpty { Text(staged ? L("暂存区是空的") : L("工作区很干净")).font(.system(size: 11)).foregroundStyle(.tertiary).padding(.vertical, 12).frame(maxWidth: .infinity) }
                changeRows(items, staged: staged)
            }
        }.padding(.vertical, 6).background(surface, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(hairline, lineWidth: 1)).padding(.horizontal, 10).padding(.bottom, 10)
    }
    var commitBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(L("提交更改")).font(.system(size: 12, weight: .semibold)); Spacer(); Text("⌘ ↵").font(.caption).foregroundStyle(.tertiary) }
            CommitAuthorSummary().environmentObject(m)
            TextEditor(text: $m.message).font(.system(size: 12)).scrollContentBackground(.hidden).padding(6).frame(height: 54).background(Color(nsColor: AppTheme.panel), in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.gray.opacity(0.18))).overlay(alignment: .topLeading) { if m.message.isEmpty { Text(L("填写提交说明…")).font(.system(size: 12)).foregroundStyle(.tertiary).padding(.leading, 11).padding(.top, 6).allowsHitTesting(false) } }
            Text(m.advancedMode ? L("已选择 {0} 个文件的暂存内容", [String(describing: m.commitItems.count)]) : L("已选择 {0} 个文件", [String(describing: m.commitItems.count)])).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { m.commit() } label: {
                    Label(L("提交"), systemImage: "checkmark").frame(maxWidth: .infinity)
                }.buttonStyle(FlatButtonStyle(kind: .secondary)).help(L("仅记录到本地 Git 历史，不上传远程"))
                Button { m.commit(pushAfter: true) } label: {
                    Label(L("提交并推送"), systemImage: "arrow.up").frame(maxWidth: .infinity)
                }.buttonStyle(FlatButtonStyle(kind: .primary)).help(L("提交勾选的文件，再推送当前分支的全部待推送提交"))
            }.font(.system(size: 12, weight: .semibold))
                .disabled(!m.canCommit)
            Text(m.advancedMode ? L("仅提交勾选文件的已暂存内容") : L("仅提交勾选文件 · 自动准备提交内容")).font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }.padding(.horizontal, 12).padding(.vertical, 10).background(surface).overlay(alignment: .top) { hairline.frame(height: 1) }
    }
    var detail: some View {
        VStack(spacing: 0) {
            if let document = m.activeDocument {
                HStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(m.tabs) { tab in
                                    EditorTabChip(document: tab, active: tab.id == m.activeTabID,
                                        select: { m.activateTab(tab.id) }, pin: { m.pinTab(tab.id) }, close: { m.closeTab(tab.id) })
                                        .id(tab.id)
                                }
                            }
                        }.onChange(of: m.activeTabID) { _, id in if let id { proxy.scrollTo(id) } }
                    }
                    if SourceLanguage.detect(document.path) == .markdown && !document.isDiff {
                        Button { if markdownPreviews.contains(document.id) { markdownPreviews.remove(document.id) } else { markdownPreviews.insert(document.id) } } label: {
                            Label(markdownPreviews.contains(document.id) ? L("原文") : L("预览"), systemImage: markdownPreviews.contains(document.id) ? "chevron.left.forwardslash.chevron.right" : "eye")
                                .font(.system(size: 11))
                        }.buttonStyle(CompactThemeButtonStyle()).padding(.horizontal, 6)
                    }
                }.frame(height: 32).background(surface)
                hairline.frame(height: 1)
                ZStack {
                    CodeEditor(text: $m.code, documentID: document.id, openIDs: Set(m.tabs.map(\.id)), path: document.path, editable: document.editable && !m.busy, diff: document.isDiff, diffLines: document.diffLines, baseline: document.baseline, position: $editorPosition)
                        .opacity(markdownPreviews.contains(document.id) ? 0 : 1)
                        .allowsHitTesting(!markdownPreviews.contains(document.id))
                        .accessibilityHidden(markdownPreviews.contains(document.id))
                    if markdownPreviews.contains(document.id) {
                        MarkdownPreview(text: m.code, path: document.path, root: m.project?.path ?? "")
                    }
                }
                .clipped()
                HStack(spacing: 12) {
                    Text(document.path).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(editorPosition)
                    Text(document.isDiff ? L("Diff · 只读") : SourceLanguage.detect(document.path).rawValue)
                    Text("UTF-8")
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 22).background(surface)
            } else {
                VStack(spacing: 16) { Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 28, weight: .light)).foregroundStyle(Color.gray.opacity(0.45)).frame(width: 60, height: 60).background(surface, in: RoundedRectangle(cornerRadius: 12)); Text(L("选择文件以查看修改")).font(.system(size: 17, weight: .semibold)); Text(L("在左侧查看变更，或切换到文件树编辑代码。")).font(.system(size: 12)).multilineTextAlignment(.center).lineSpacing(7).foregroundStyle(.secondary); HStack(spacing: 24) { shortcut("⌘ O", L("打开项目")); shortcut("⌘ S", L("保存文件")); shortcut("⌘ R", L("刷新状态")) }.padding(.top, 20) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(Color(nsColor: AppTheme.panel)).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    func shortcut(_ key: String, _ label: String) -> some View { VStack(spacing: 8) { Text(key).font(.system(size: 12, design: .monospaced)).padding(.horizontal, 10).padding(.vertical, 5).background(Color(nsColor: AppTheme.panel), in: RoundedRectangle(cornerRadius: 5)); Text(label).font(.system(size: 10)).foregroundStyle(.secondary) } }
}

extension FileGitStatus {
    var color: Color {
        switch self {
        case .untracked, .added: return Color(red: 0.12, green: 0.48, blue: 0.30)
        case .modified: return Color(red: 0.65, green: 0.40, blue: 0.08)
        case .renamed: return accent
        case .deleted: return Color(red: 0.73, green: 0.26, blue: 0.24)
        case .conflict: return .red
        }
    }
}


struct FlatButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        FlatButtonBody(label: configuration.label, kind: kind, enabled: enabled, pressed: configuration.isPressed)
    }
    private struct FlatButtonBody: View {
        let label: ButtonStyleConfiguration.Label
        let kind: Kind
        let enabled: Bool
        let pressed: Bool
        @State private var hovered = false
        var body: some View {
            label.font(.system(size: 12, weight: .medium))
                .padding(.horizontal, kind == .quiet ? 7 : 12).padding(.vertical, 8)
                .foregroundStyle(!enabled ? Color.gray.opacity(0.5) : kind == .primary ? Color.white : ink)
                .background(background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(kind == .secondary ? hairline : .clear, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 6)).actionCursor()
                .onHover { hovered = $0 }
        }
        var background: Color {
            if !enabled { return kind == .quiet ? .clear : Color.primary.opacity(0.035) }
            if kind == .primary { return accent.opacity(pressed ? 0.75 : hovered ? 0.88 : 1) }
            return pressed ? Color.primary.opacity(0.08) : hovered ? Color.primary.opacity(0.045) : kind == .secondary ? Color(nsColor: AppTheme.panel) : .clear
        }
    }
}
struct WorkspaceTabs: View {
    @Binding var selection: String
    @State private var hovered: String?
    var body: some View {
        HStack(spacing: 8) {
            ForEach(["变更", "文件", "历史"], id: \.self) { tab in
                Button { selection = tab } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab == "变更" ? "square.and.pencil" : tab == "文件" ? "folder" : "clock")
                        Text(L(tab))
                    }.font(.system(size: 12, weight: selection == tab ? .semibold : .regular))
                        .foregroundStyle(selection == tab ? ink : Color.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(selection == tab ? accent.opacity(0.09) : hovered == tab ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .bottom) { if selection == tab { RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: 24, height: 2) } }
                        .frame(height: 48)
                        .contentShape(Rectangle())
                }.buttonStyle(CursorPlainButtonStyle()).onHover { hovered = $0 ? tab : nil }
                    .animation(.easeOut(duration: 0.12), value: hovered)
            }
            Spacer(minLength: 0)
        }
    }
}


struct EditorTabChip: View {
    let document: EditorDocument
    let active: Bool
    let select: () -> Void
    let pin: () -> Void
    let close: () -> Void
    @State private var hovered = false
    @State private var closeHovered = false
    var body: some View {
        HStack(spacing: 7) {
            Button(action: select) {
                HStack(spacing: 6) {
                    SourceFileIcon(path: document.path)
                    Text(document.name + (document.isDiff ? L(" · 差异") : ""))
                        .font(.system(size: 12)).italic(document.preview).lineLimit(1)
                }.contentShape(Rectangle()).frame(height: 32)
            }.buttonStyle(CursorPlainButtonStyle()).simultaneousGesture(TapGesture(count: 2).onEnded { pin() })
            if document.dirty { Circle().fill(accent).frame(width: 6, height: 6).help(L("未保存")) }
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 9, weight: .medium)).frame(width: 20, height: 20).background(closeHovered ? Color.primary.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 4)).contentShape(Rectangle()) }
                .buttonStyle(CursorPlainButtonStyle()).foregroundStyle(.secondary).opacity(active || hovered ? 1 : 0.5).onHover { closeHovered = $0 }.help(L("关闭文件 ⌘W"))
        }.padding(.horizontal, 10).frame(height: 32)
            .background(active ? Color(nsColor: AppTheme.panel) : hovered ? Color.primary.opacity(0.025) : Color.clear)
            .overlay(alignment: .top) { if active { accent.frame(height: 2) } }
            .overlay(alignment: .trailing) { hairline.frame(width: 1) }
            .onHover { hovered = $0 }.help(document.path + (document.preview ? L(" · 预览标签，双击固定") : ""))
    }
}

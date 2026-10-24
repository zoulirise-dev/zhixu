import SwiftUI

struct WorkspaceSettings: View {
    @EnvironmentObject var model: Workspace
    @AppStorage("editorCompletion") private var editorCompletion = true
    @AppStorage("colorMode") private var mode = "system"
    @AppStorage("appLanguage") private var language = AppLanguage.current
    @State private var name = ""
    @State private var email = ""
    @State private var remote = ""
    @State private var remoteName = "origin"
    @State private var originalRemote = ""
    @State private var remotes: [GitSettingsRemote.Entry] = []
    @State private var remoteDrafts: [String: String] = [:]
    @State private var choosingRemote = false
    @State private var gitVersion = L("读取中…")
    @State private var gitPath = ""
    @State private var gitExec = L("读取中…")
    @State private var gitName = ""
    @State private var gitEmail = ""
    @State private var loaded = false
    let close: () -> Void
    var body: some View {
        GeometryReader { geometry in
        DialogCard(bottomPadding: 8) {
            VStack(spacing: 0) {
                HStack(spacing: 10) { DialogCloseButton(action: close); Text(L("设置")).font(.system(size: 14, weight: .medium)); Spacer() }
                    .dialogHeader()
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("语言")).font(.headline)
                    HStack(spacing: 8) {
                        Button { language = "zh-Hans" } label: { Text(verbatim: "中文").frame(maxWidth: .infinity) }.buttonStyle(DialogButtonStyle(primary: language == "zh-Hans"))
                        Button { language = "en" } label: { Text(verbatim: "English").frame(maxWidth: .infinity) }.buttonStyle(DialogButtonStyle(primary: language == "en"))
                    }
                    Text(L("重新打开应用后生效。")).font(.caption).foregroundStyle(language == AppLanguage.current ? Color.secondary : Color.blue)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("色彩模式")).font(.headline)
                    HStack(spacing: 8) {
                        ForEach([("system", L("跟随系统")), ("light", L("日间")), ("dark", L("夜间"))], id: \.0) { value, title in
                            Button { mode = value } label: { Label(title, systemImage: value == "system" ? "desktopcomputer" : value == "light" ? "sun.max" : "moon").frame(maxWidth: .infinity) }.buttonStyle(DialogButtonStyle(primary: mode == value))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Toggle(L("编辑器自动补全"), isOn: $editorCompletion).toggleStyle(ThemeCheckboxStyle()); Text(L("编辑器自动补全")).font(.headline) }
                    Text(L("括号配对、自动缩进、语言关键字和代码片段。Tab 接受，Esc 关闭；全部在本机完成。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("本机 Git")).font(.headline)
                    info(L("使用版本"), gitVersion); info(L("执行文件"), gitPath)
                    info(L("工具目录"), gitExec); info(L("全局姓名"), gitName); info(L("全局邮箱"), gitEmail)
                    Text(L("显示枝序实际调用的系统 Git；项目身份可覆盖全局身份。")).font(.caption).foregroundStyle(.secondary)
                }.padding(14).background(Color(nsColor: AppTheme.subtle), in: RoundedRectangle(cornerRadius: 10))
                if let project = model.project {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("项目 · {0}", [String(describing: project.name)])).font(.headline)
                        field(L("提交者姓名"), value: $name).disabled(!loaded); field(L("提交者邮箱"), value: $email).disabled(!loaded)
                        remoteSelector
                        field(L("{0} 远程仓库地址", [remoteName]), value: $remote).disabled(!loaded)
                        Text(L(originalRemote.isEmpty ? "尚未配置远程仓库，可正常本地提交；填写地址后才能连接远程仓库。" : "当前远程仓库地址。留空保留原设置，不会删除远程仓库。")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("关于")).font(.headline)
                    Text(L("枝序 · 让 Git 简单一点")).font(.system(size: 13, weight: .medium))
                    info(L("版本"), Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("开发版"))
                    info(L("作者"), "zoulirise")
                    HStack(alignment: .top, spacing: 12) {
                        Text(L("联系邮箱")).font(.caption).foregroundStyle(.secondary).frame(width: 68, alignment: .leading)
                        Link("zoulirise@gmail.com", destination: URL(string: "mailto:zoulirise@gmail.com")!).font(.caption).actionCursor()
                    }
                    Text("© 2026 zoulirise").font(.caption).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: AppTheme.subtle), in: RoundedRectangle(cornerRadius: 10))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20).padding(.trailing, 20)
                }.frame(width: 520).padding(.trailing, -20)
                    .overlay(alignment: .top) { scrollFade(top: true) }
                    .overlay(alignment: .bottom) { scrollFade(top: false) }
                HStack {
                    Spacer()
                    if model.project != nil {
                        Button(L("保存项目设置")) { model.configure(name: name, email: email, remote: remote == originalRemote ? "" : remote, remoteName: remoteName); close() }
                            .buttonStyle(DialogButtonStyle(primary: true)).disabled(!loaded || model.busy || name.isEmpty || email.isEmpty)
                    } else { Button(L("关闭"), action: close).buttonStyle(DialogButtonStyle()) }
                }.frame(height: 40)
            }.frame(width: 500).frame(height: min(760, geometry.size.height - 100))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.onChange(of: mode) { _, value in AppTheme.apply(value) }.task(id: model.project?.path) { await load() }
    }
    private var remoteSelector: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("远程仓库")).font(.caption).foregroundStyle(.secondary)
            Button { choosingRemote.toggle() } label: {
                HStack {
                    Text(remoteName).lineLimit(1)
                    Spacer()
                    Image(systemName: choosingRemote ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .medium))
                }.frame(maxWidth: .infinity)
            }.buttonStyle(DialogButtonStyle()).disabled(!loaded || remotes.count < 2)
            if choosingRemote {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(remotes) { item in
                            Button {
                                remoteDrafts[remoteName] = remote
                                remoteName = item.name
                                originalRemote = item.url
                                remote = remoteDrafts[item.name] ?? item.url
                                choosingRemote = false
                            } label: {
                                HStack {
                                    Text(item.name).lineLimit(1)
                                    Spacer()
                                    if item.name == remoteName { Image(systemName: "checkmark").foregroundStyle(.blue) }
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(CompactThemeButtonStyle())
                        }
                    }.padding(4)
                }.frame(height: min(CGFloat(remotes.count) * 26 + 8, 160))
                    .background(Color(nsColor: AppTheme.subtle), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    private func scrollFade(top: Bool) -> some View {
        let background = Color(nsColor: AppTheme.panel)
        return LinearGradient(stops: [
            .init(color: background, location: 0),
            .init(color: background.opacity(0.88), location: 0.25),
            .init(color: background.opacity(0), location: 1)
        ], startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top)
            .frame(height: 20).padding(.trailing, 12)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func field(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); TextField(title, text: value).textFieldStyle(.plain).padding(10).background(Color(nsColor: AppTheme.subtle), in: RoundedRectangle(cornerRadius: 7)) }
    }
    private func info(_ title: String, _ value: String) -> some View { HStack(alignment: .top) { Text(title).foregroundStyle(.secondary).frame(width: AppLanguage.current == "en" ? 92 : 72, alignment: .leading); Text(value.isEmpty ? L("未配置") : value).lineLimit(2).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).help(value) }.font(.system(size: 12)) }
    private func load() async {
        loaded = false
        gitPath = (try? await GitEnvironment.shared.executable()) ?? L("不可用，请安装 Git 或 Xcode 命令行工具")
        let root = model.project?.path
        name = ""; email = ""; remote = ""; originalRemote = ""; remoteName = "origin"
        remotes = []; remoteDrafts = [:]; choosingRemote = false
        @Sendable func read(_ args: [String], root: String = "/") async -> String { ((try? await Git.run(root, args)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        async let version = read(["--version"])
        async let exec = read(["--exec-path"])
        async let globalName = read(["config", "--global", "user.name"])
        async let globalEmail = read(["config", "--global", "user.email"])
        if let root {
            async let projectName = read(["config", "user.name"], root: root)
            async let projectEmail = read(["config", "user.email"], root: root)
            async let selectedRemote = GitSettingsRemote.current(root)
            async let remoteList = try? GitSettingsRemote.list(root)
            let values = await (projectName, projectEmail, selectedRemote, remoteList)
            guard !Task.isCancelled, model.project?.path == root else { return }
            name = values.0; email = values.1
            remoteName = values.2.name; remote = values.2.url; originalRemote = remote
            remotes = values.3 ?? []
        }
        let values = await (version, exec, globalName, globalEmail)
        guard !Task.isCancelled, model.project?.path == root else { return }
        (gitVersion, gitExec, gitName, gitEmail) = values
        loaded = true
    }
}

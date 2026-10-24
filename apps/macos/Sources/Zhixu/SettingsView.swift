import SwiftUI

struct WorkspaceSettings: View {
    @EnvironmentObject var model: Workspace
    @AppStorage("editorCompletion") private var editorCompletion = true
    @AppStorage("colorMode") private var mode = "system"
    @AppStorage("appLanguage") private var language = AppLanguage.current
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
    @State private var editingRemote = ""
    @State private var newRemoteName = ""
    @State private var newRemoteURL = ""
    @State private var profileName = ""
    @State private var profileEmail = ""
    @State private var remoteError = ""
    @State private var remoteSaved = false
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
                        Button(L("新增远程仓库")) { editingRemote = "add"; newRemoteName = ""; newRemoteURL = "" }
                            .buttonStyle(CompactThemeButtonStyle()).disabled(!loaded || model.busy)
                        if editingRemote == "add" { remoteEditForm.disabled(model.busy) }
                        VStack(alignment: .leading, spacing: 12) {
                        remoteSelector
                        field(L("{0} 远程仓库地址", [remoteName]), value: $remote).disabled(!loaded)
                        Text(L(originalRemote.isEmpty ? "尚未配置远程仓库，可正常本地提交；填写地址后才能连接远程仓库。" : "当前远程仓库地址。留空保留原设置，不会删除远程仓库。")).font(.caption).foregroundStyle(.secondary)
                        remoteManagement
                        }.padding(14).background(Color(nsColor: AppTheme.subtle), in: RoundedRectangle(cornerRadius: 10))
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
                        Button(L("保存项目设置")) { saveSettings() }
                            .buttonStyle(DialogButtonStyle(primary: true)).disabled(!loaded || model.busy || profileName.isEmpty || profileEmail.isEmpty)
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
            }.buttonStyle(SettingsRemoteButtonStyle(selected: choosingRemote)).disabled(!loaded || model.busy || remotes.isEmpty)
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
                                loadProfile()
                            } label: {
                                HStack {
                                    Text(item.name).lineLimit(1)
                                    Spacer()
                                    if item.name == remoteName { Image(systemName: "checkmark").foregroundStyle(.blue) }
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(SettingsRemoteButtonStyle(selected: item.name == remoteName))
                        }
                    }.padding(4)
                }.frame(height: min(CGFloat(remotes.count) * 36 + 8, 160))
                    .background(Color(nsColor: AppTheme.subtle), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    private var selectedEntry: GitSettingsRemote.Entry? { remotes.first { $0.name == remoteName } }
    private func loadProfile() {
        let profile = model.authorProfiles.first { $0.remote == remoteName }
        profileName = profile?.name ?? gitName; profileEmail = profile?.email ?? gitEmail
    }
    private func remoteAction(_ action: @escaping (String) async throws -> String?) {
        guard let root = model.project?.path else { return }
        remoteError = ""; remoteSaved = false
        model.perform {
            do {
                let selection = try await action(root)
                let entries = try await GitSettingsRemote.list(root)
                try await model.refresh()
                guard model.project?.path == root else { return }
                remotes = entries
                if let entry = entries.first(where: { $0.name == (selection ?? remoteName) }) ?? entries.first {
                    remoteName = entry.name; remote = entry.url; originalRemote = entry.url
                } else { remoteName = "origin"; remote = ""; originalRemote = "" }
                remoteDrafts = [:]; choosingRemote = false; editingRemote = ""; loadProfile(); remoteSaved = true
            } catch { remoteError = error.localizedDescription }
        }
    }
    private func saveSettings() {
        guard let root = model.project?.path else { return }
        let author = profileName, mail = profileEmail, address = remote, selected = remoteName
        remoteError = ""
        model.perform {
            do {
                try GitAuthorProfile.validate(name: author, email: mail)
                try await GitSettingsRemote.save(root, name: selected, url: address)
                if let entry = try await GitSettingsRemote.list(root).first(where: { $0.name == selected }) {
                    try await GitAuthorProfile.save(root, entry: entry, name: author, email: mail)
                } else {
                    _ = try await Git.run(root, ["config", "--local", "user.name", author])
                    _ = try await Git.run(root, ["config", "--local", "user.email", mail])
                }
                try await model.refresh()
                close()
            } catch { remoteError = error.localizedDescription }
        }
    }
    private var remoteEditForm: some View {
        VStack(alignment: .leading, spacing: 8) {
                field(L("远程名称"), value: $newRemoteName)
                if editingRemote == "add" { field(L("远程仓库地址"), value: $newRemoteURL) }
                HStack {
                    Button(L("取消")) { editingRemote = "" }
                    Button(L("确认")) {
                        let title = newRemoteName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let address = newRemoteURL; let action = editingRemote; let entry = selectedEntry
                        remoteAction { root in
                            if action == "add" { try await GitSettingsRemote.add(root, name: title, url: address) }
                            else if let entry { try await GitSettingsRemote.rename(root, entry: entry, to: title) }
                            return title
                        }
                    }.disabled(newRemoteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (editingRemote == "add" && newRemoteURL.isEmpty))
                }.buttonStyle(DialogButtonStyle())
            }
    }
    private var remoteManagement: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(L("重命名")) { editingRemote = "rename"; newRemoteName = remoteName }.disabled(selectedEntry == nil)
                Button(L("移除")) {
                    guard let entry = selectedEntry else { return }
                    if AppDialogs.confirm(L("移除远程仓库？"), message: L("仅移除本项目的远程配置和对应署名预设，不删除远程网站上的仓库、本地文件或提交。"), accept: L("移除")) == 1 {
                        remoteAction { root in try await GitSettingsRemote.remove(root, entry: entry); return nil }
                    }
                }.disabled(selectedEntry == nil)
            }.buttonStyle(CompactThemeButtonStyle())
            if editingRemote == "rename" { remoteEditForm }
            VStack(alignment: .leading, spacing: 8) {
                    Text(L("提交署名")).font(.system(size: 12, weight: .medium))
                    field(L("提交者姓名"), value: $profileName)
                    field(L("提交者邮箱"), value: $profileEmail)
                    Text(L(selectedEntry == nil ? "默认填入电脑的 Git 署名，可修改。保存后用于此项目的新提交。" : "默认填入电脑的 Git 署名，可修改。保存后可在提交区域选择，不影响已有提交。")).font(.caption).foregroundStyle(.secondary)

                }
            if remoteSaved { Text(L("已保存")).font(.caption).foregroundStyle(.secondary) }
            if !remoteError.isEmpty { Text(remoteError).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }.disabled(!loaded || model.busy)
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
        SettingsInputField(title: title, value: value)
    }
    private func info(_ title: String, _ value: String) -> some View { HStack(alignment: .top) { Text(title).foregroundStyle(.secondary).frame(width: AppLanguage.current == "en" ? 92 : 72, alignment: .leading); Text(value.isEmpty ? L("未配置") : value).lineLimit(2).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).help(value) }.font(.system(size: 12)) }
    private func load() async {
        loaded = false
        gitPath = (try? await GitEnvironment.shared.executable()) ?? L("不可用，请安装 Git 或 Xcode 命令行工具")
        let root = model.project?.path
        remote = ""; originalRemote = ""; remoteName = "origin"
        remotes = []; remoteDrafts = [:]; choosingRemote = false
        @Sendable func read(_ args: [String], root: String = "/") async -> String { ((try? await Git.run(root, args)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        async let version = read(["--version"])
        async let exec = read(["--exec-path"])
        async let globalName = read(["config", "--global", "user.name"])
        async let globalEmail = read(["config", "--global", "user.email"])
        if let root {
            async let selectedRemote = GitSettingsRemote.current(root)
            async let remoteList = try? GitSettingsRemote.list(root)
            let values = await (selectedRemote, remoteList)
            guard !Task.isCancelled, model.project?.path == root else { return }
            remoteName = values.0.name; remote = values.0.url; originalRemote = remote
            remotes = values.1 ?? []
        }
        let values = await (version, exec, globalName, globalEmail)
        guard !Task.isCancelled, model.project?.path == root else { return }
        (gitVersion, gitExec, gitName, gitEmail) = values
        loadProfile()
        loaded = true
    }
}

struct CommitAuthorPicker: View {
    @EnvironmentObject var model: Workspace
    @State private var expanded = false
    private var authorLabel: String {
        guard !model.currentAuthorName.isEmpty else { return L("未配置提交署名") }
        let profile = model.authorProfiles.first { $0.name == model.currentAuthorName && $0.email == model.currentAuthorEmail }
        return profile.map { $0.remote + " · " + $0.name } ?? model.currentAuthorName
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "person.crop.circle")
                    Text(authorLabel).lineLimit(1)
                    Spacer()
                    if !model.authorProfiles.isEmpty { Image(systemName: "chevron.down").font(.system(size: 9)) }
                }.font(.system(size: 11)).frame(maxWidth: .infinity)
            }.buttonStyle(CompactThemeButtonStyle()).disabled(model.busy || model.authorProfiles.isEmpty)
                .help(model.currentAuthorEmail)
                .popover(isPresented: $expanded, arrowEdge: .bottom) {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(model.authorProfiles) { profile in
                                Button {
                                    expanded = false
                                    model.useAuthor(profile)
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(profile.remote + " · " + profile.name)
                                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                                            Text(profile.email).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                        if profile.name == model.currentAuthorName && profile.email == model.currentAuthorEmail {
                                            Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                                        }
                                    }.padding(.horizontal, 10).frame(height: 48)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(AuthorChoiceStyle(selected: profile.name == model.currentAuthorName && profile.email == model.currentAuthorEmail))
                                    .disabled(model.busy).help(profile.remote + " · " + profile.name + "\n" + profile.email)
                            }
                        }.padding(6)
                    }.frame(width: 300, height: min(CGFloat(model.authorProfiles.count) * 51 + 9, 264))
                        .background(Color(nsColor: AppTheme.panel))
                }

        }.onChange(of: model.project?.path) { _, _ in expanded = false }
            .onChange(of: model.busy) { _, busy in if busy { expanded = false } }
    }
}

private struct SettingsInputField: View {
    let title: String
    @Binding var value: String
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: $value).textFieldStyle(.plain).focused($focused)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(Color(nsColor: AppTheme.panel), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(focused ? Color.accentColor : Color.primary.opacity(0.18), lineWidth: 1))
        }
    }
}

private struct SettingsRemoteButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        StyledContent(configuration: configuration, selected: selected)
    }
    private struct StyledContent: View {
        let configuration: Configuration
        let selected: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label.font(.system(size: 12)).foregroundStyle(selected ? Color.accentColor : Color.primary)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(selected || hovered ? Color.accentColor.opacity(configuration.isPressed ? 0.20 : 0.10) : Color(nsColor: AppTheme.panel), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected || hovered ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.14)))
                .contentShape(RoundedRectangle(cornerRadius: 7)).onHover { hovered = $0 }.actionCursor()
        }
    }
}

private struct AuthorChoiceStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        ChoiceContent(configuration: configuration, selected: selected)
    }
    private struct ChoiceContent: View {
        let configuration: Configuration
        let selected: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(accent.opacity(configuration.isPressed ? 0.20 : hovered ? 0.13 : selected ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { hovered = $0 }.actionCursor()
        }
    }
}

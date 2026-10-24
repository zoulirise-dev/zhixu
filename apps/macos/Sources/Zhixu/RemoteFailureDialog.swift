import SwiftUI
import AppKit

struct RemoteFailureDialog: View {
    @ObservedObject var model: Workspace
    let failure: GitRemoteFailure
    let settings: () -> Void
    @StateObject private var login = BrowserLogin()
    @State private var username = ""
    @State private var password = ""
    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
            DialogCard(bottomPadding: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        DialogCloseButton { dismiss() }
                        Text(failure.title).font(.system(size: 14, weight: .medium))
                        Spacer()
                    }.dialogHeader()
                    Text(failure.message).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    if failure.canPasswordLogin {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("https://" + (failure.loginServer ?? "")).font(.caption).foregroundStyle(.secondary)
                            TextField(L("用户名"), text: $username).textFieldStyle(.plain)
                                .padding(10).background(Color(nsColor: AppTheme.subtle), in: RoundedRectangle(cornerRadius: 7))
                            SecureField(L("密码"), text: $password).textFieldStyle(.plain)
                                .padding(10).background(Color(nsColor: AppTheme.subtle), in: RoundedRectangle(cornerRadius: 7))
                            Text(L("验证成功后交给电脑的 Git 凭据助手保存，使用相同认证的软件可共用。若账号要求令牌，可填在密码处。")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !login.message.isEmpty {
                        Text(login.message).font(.caption).foregroundStyle(.secondary)
                    }
                    if !login.code.isEmpty {
                        HStack {
                            Text(login.code).font(.system(.title3, design: .monospaced)).textSelection(.enabled)
                            Button(L("复制验证码")) {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(login.code, forType: .string)
                            }.buttonStyle(DialogButtonStyle())
                            Button(L("打开授权网页")) { NSWorkspace.shared.open(URL(string: "https://github.com/login/device")!) }.buttonStyle(DialogButtonStyle())
                        }
                    }
                    HStack {
                        Button(L("仓库设置")) { dismiss(); settings() }.buttonStyle(DialogButtonStyle())
                        Spacer()
                        if login.running {
                            Button(L("取消登录")) { login.cancel() }.buttonStyle(DialogButtonStyle())
                        } else {
                            if failure.canLogin {
                                Button(L("登录 GitHub")) { login.start { model.retryRemote(account: $0) } }.buttonStyle(DialogButtonStyle(primary: true))
                            }
                            if failure.canPasswordLogin {
                                Button(L("登录并继续")) { passwordLogin() }
                                    .buttonStyle(DialogButtonStyle(primary: true))
                                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                            }
                            Button(L("重试")) { model.retryRemote() }.buttonStyle(DialogButtonStyle(primary: !failure.canAuthenticate))
                        }
                    }.padding(.top, 4)
                }.frame(width: 490)
            }
        }.onAppear { username = failure.loginServer.flatMap { AccountStore.rememberedLogin(host: $0)?.username } ?? "" }
        .onDisappear { login.cancel(); password = "" }.onExitCommand { dismiss() }
    }
    private func passwordLogin() {
        guard failure.canPasswordLogin, let server = failure.loginServer else { return }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        var saved = AccountStore.accounts().first { HTTPSGitServer.normalize($0.host) == server && $0.username == user && $0.method == "https" } ?? GitAccount()
        saved.host = server; saved.method = "https"; saved.username = user; saved.label = server + " · " + user
        let secret = password; password = ""
        model.retryRemote(account: saved, password: secret)
    }
    private func dismiss() { login.cancel(); model.remoteFailure = nil; model.remoteRetry = nil }
}


struct GitSetupDialog: View {
    @ObservedObject var model: Workspace
    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
            DialogCard(bottomPadding: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        DialogCloseButton { model.missingGit = false }
                        Text(L("首次使用：安装 Git")).font(.system(size: 14, weight: .medium))
                        Spacer()
                    }.dialogHeader()
                    Text(L("枝序需要 Git 才能管理仓库。点击安装命令行工具，按 macOS 提示完成安装，再返回重新检查。无需安装完整 Xcode。"))
                        .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    if !model.gitSetupMessage.isEmpty { Text(model.gitSetupMessage).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button(L("安装命令行工具")) { model.installGitTools() }.buttonStyle(DialogButtonStyle())
                        Spacer()
                        Button(L("重新检查")) { model.checkGitEnvironment() }.buttonStyle(DialogButtonStyle(primary: true))
                    }
                }.frame(width: 460)
            }
        }
    }
}

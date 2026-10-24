import SwiftUI

struct PullTargetDialog: View {
    @ObservedObject var model: Workspace
    let request: GitPullPlan
    @State private var selected = ""
    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
            DialogCard(bottomPadding: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        DialogCloseButton { model.pullRequest = nil }
                        Text(L("选择拉取来源")).font(.system(size: 14, weight: .medium))
                        Spacer()
                    }.dialogHeader()
                    Text(L("本地分支：{0}", [request.branch])).font(.system(size: 12)).padding(.bottom, 10)
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(request.targets) { target in
                                Button { selected = target.name } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(target.name).fontWeight(.semibold)
                                            Spacer()
                                            if selected == target.name { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                                        }
                                        Text(L("来源分支：") + target.branch)
                                        ForEach(target.urls, id: \.self) { url in
                                            Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(ChoiceCardStyle())
                                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected == target.name ? Color.blue : .clear, lineWidth: 1.5))
                            }
                        }.padding(2)
                    }.frame(height: min(CGFloat(request.targets.count) * 112, 340))
                    Text(L("从所选远程的对应分支拉取到当前分支，不改变跟踪关系。"))
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 10)
                    HStack {
                        Spacer()
                        Button(L("取消")) { model.pullRequest = nil }.buttonStyle(DialogButtonStyle())
                        Button(L("拉取")) { model.confirmPull(remote: selected) }
                            .buttonStyle(DialogButtonStyle(primary: true)).disabled(selected.isEmpty || model.busy)
                    }.frame(height: 40)
                }.frame(width: 460)
            }
        }.onAppear { selected = request.defaultRemote }
            .onExitCommand { model.pullRequest = nil }
    }
}

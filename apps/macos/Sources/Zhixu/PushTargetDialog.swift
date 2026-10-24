import SwiftUI

struct PushTargetDialog: View {
    @ObservedObject var model: Workspace
    let request: Workspace.PushRequest
    @State private var selected = ""
    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
            DialogCard(bottomPadding: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        DialogCloseButton { model.pushRequest = nil }
                        Text(L("选择推送目标")).font(.system(size: 14, weight: .medium))
                        Spacer()
                    }.dialogHeader()
                    Text(L("本地分支：{0}", [request.plan.branch])).font(.system(size: 12)).padding(.bottom, 10)
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(request.plan.targets) { target in
                                Button { selected = target.name } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(target.name).fontWeight(.semibold)
                                            Spacer()
                                            if selected == target.name { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                                        }
                                        Text(L("目标分支：") + target.branch)
                                        ForEach(target.urls, id: \.self) { url in
                                            Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(ChoiceCardStyle())
                                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected == target.name ? Color.blue : .clear, lineWidth: 1.5))
                            }
                        }.padding(2)
                    }.frame(height: min(CGFloat(request.plan.targets.count) * 112, 340))
                    Text(L("仅推送到所选远程；已有的分支跟踪关系保持不变。首次推送会建立跟踪关系。"))
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 10)
                    HStack {
                        Spacer()
                        Button(L("取消")) { model.pushRequest = nil }.buttonStyle(DialogButtonStyle())
                        Button(L(request.commitFirst ? "提交并推送" : "推送")) { model.confirmPush(remote: selected) }
                            .buttonStyle(DialogButtonStyle(primary: true)).disabled(selected.isEmpty || model.busy)
                    }.frame(height: 40)
                }.frame(width: 460)
            }
        }.onAppear { selected = request.plan.defaultRemote }
            .onExitCommand { model.pushRequest = nil }
    }
}

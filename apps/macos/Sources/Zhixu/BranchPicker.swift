import SwiftUI

struct BranchButtonAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}
struct BranchPicker: View {
    let branches: [Branch]
    let current: String
    let select: (Branch) -> Void
    let create: () -> Void
    let canDelete: (Branch) -> Bool
    let rename: (Branch) -> Void
    let delete: (Branch) -> Void
    let compare: (Branch) -> Void
    let merge: (Branch) -> Void
    @State private var hovered: String?
    @State private var search = ""
    @State private var createHovered = false
    @State private var localLimit = 50
    @State private var remoteLimit = 50
    private var filtered: [Branch] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return branches.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }
    private func loadMore(remote: Bool) {
        if remote { remoteLimit += 50 } else { localLimit += 50 }
    }
    private var listHeight: CGFloat {
        let localRows = max(1, filtered.filter { !$0.remote }.count)
        let remoteRows = max(1, filtered.filter(\.remote).count)
        return min(340, 84 + CGFloat(localRows + remoteRows) * 34)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if branches.count > 12 {
                TextField(L("搜索分支…"), text: $search).textFieldStyle(.plain).font(.system(size: 12))
                    .padding(8).background(surface, in: RoundedRectangle(cornerRadius: 6)).padding(8)
                    .onChange(of: search) { _, _ in localLimit = 50; remoteLimit = 50 }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    group(L("本地分支"), remote: false)
                    group(L("远程分支 · 创建本地跟踪分支"), remote: true)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }.frame(maxWidth: .infinity).frame(height: listHeight)
            Divider().padding(.horizontal, 12)
            Button(action: create) {
                Label(L("创建新分支…"), systemImage: "plus").font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
                    .background(createHovered ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(CursorPlainButtonStyle()).foregroundStyle(accent).onHover { createHovered = $0 }.padding(4)
        }.frame(width: 300).background(Color(nsColor: AppTheme.panel), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(hairline))
            .compositingGroup().shadow(color: .black.opacity(0.16), radius: 18, y: 6)
    }
    private func group(_ title: String, remote: Bool) -> some View {
        let items = filtered.filter { $0.remote == remote }
        let limit = remote ? remoteLimit : localLimit
        return LazyVStack(alignment: .leading, spacing: 3) {
            Text(title + " · \(items.count)").help(remote ? L("按末次提交时间倒序；基于最近获取的远程信息") : L("当前分支置顶，其余按末次提交时间倒序")).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 3)
            if items.isEmpty { Text(!search.isEmpty ? L("没有匹配的分支") : remote ? L("暂无远程分支") : L("暂无本地分支")).font(.system(size: 11)).foregroundStyle(.tertiary).padding(.horizontal, 8).padding(.vertical, 6) }
            ForEach(Array(items.prefix(limit))) { branch in
                Button { select(branch) } label: {
                    HStack(spacing: 8) {
                        Group { if remote { Image(systemName: "cloud") } else { GitBranchIcon() } }.foregroundStyle(.secondary)
                        Text(branch.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        if branch.unborn { Text(L("尚无提交")).font(.system(size: 10)).foregroundStyle(.secondary) }
                        if !remote && branch.name == current { Image(systemName: "checkmark").foregroundStyle(accent) }
                    }.font(.system(size: 12)).padding(.horizontal, 8).frame(height: 31).contentShape(Rectangle())
                        .background(hovered == branch.id ? Color.primary.opacity(0.05) : !remote && branch.name == current ? accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(CursorPlainButtonStyle()).onHover { hovered = $0 ? branch.id : nil }.help(branch.name)
                    .themedContextMenu(keepsBranchPickerOpen: true) {
                        [AppMenuItem(title: L("与当前分支对比…"), icon: "arrow.left.arrow.right") { compare(branch) },
                         AppMenuItem(title: L("合并到当前分支…"), icon: "arrow.triangle.merge", enabled: remote || branch.name != current) { merge(branch) },
                         AppMenuItem(title: remote ? L("重命名远程分支…") : L("重命名分支…"), icon: "pencil") { rename(branch) },
                         AppMenuItem(title: canDelete(branch) ? (remote ? L("删除远程分支…") : L("删除分支…")) : L("当前分支不能删除"), icon: "trash", enabled: canDelete(branch)) { delete(branch) }]
                    }
            }
            if items.count > limit {
                Button(L("加载更多（已显示 {0} / {1}）", [String(describing: limit), String(describing: items.count)])) { loadMore(remote: remote) }
                    .buttonStyle(CursorPlainButtonStyle()).font(.system(size: 11)).foregroundStyle(accent)
                    .frame(maxWidth: .infinity).frame(height: 30)
                    .onAppear { loadMore(remote: remote) }
                    .id("more-\(remote)-\(limit)-\(search)")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

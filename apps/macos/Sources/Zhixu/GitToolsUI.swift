import SwiftUI

struct GitToolConfirmationView: View {
    @ObservedObject var model: Workspace
    let confirmation: Workspace.ToolConfirmation
    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
            DialogCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) { DialogCloseButton { if !model.busy { model.toolConfirmation = nil } }; Text(confirmation.title).font(.system(size: 14, weight: .medium)); Spacer() }.dialogHeader()
                    Text(confirmation.detail).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Spacer()
                        Button(L("取消")) { model.toolConfirmation = nil }.buttonStyle(DialogButtonStyle())
                        Button(L("确认")) { model.applyToolConfirmation() }.buttonStyle(DialogButtonStyle(primary: true))
                    }.disabled(model.busy)
                }.frame(width: 460)
            }
        }.onExitCommand { if !model.busy { model.toolConfirmation = nil } }
    }
}

struct ConflictEditorDialog: View {
    @ObservedObject var model: Workspace
    let conflict: GitConflict
    @State private var result = ""
    @State private var confirmingClose = false
    private func requestClose() {
        guard !model.busy else { return }
        if result != (GitConflict.text(conflict.current) ?? "") { confirmingClose = true }
        else { model.conflictFile = nil }
    }
    private var blocks: [ConflictBlock] { ConflictBlock.parse(result) }
    private var textSupported: Bool { GitConflict.text(conflict.current) != nil && GitConflict.text(conflict.ours) != nil && GitConflict.text(conflict.theirs) != nil }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
                DialogCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            DialogCloseButton { requestClose() }
                            Text(L("解决冲突")).font(.system(size: 14, weight: .medium))
                            Text(conflict.path).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                            Spacer()
                        }.dialogHeader()
                        Text(L("逐块选择后可直接编辑合并结果；标记已解决会保存并暂存此文件。当前版本和传入版本以此次 Git 操作为准。"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if textSupported {
                            if !blocks.isEmpty {
                                ScrollView {
                                    VStack(spacing: 4) {
                                        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                                            HStack {
                                                Text(L("冲突 {0} · 第 {1} 行", [String(describing: index + 1), String(describing: block.start + 1)])).font(.system(size: 11))
                                                Spacer()
                                                Button(L("采用当前")) { result = block.replacing(in: result, choice: 0) }.buttonStyle(DialogButtonStyle())
                                                Button(L("采用传入")) { result = block.replacing(in: result, choice: 1) }.buttonStyle(DialogButtonStyle())
                                                Button(L("保留两者")) { result = block.replacing(in: result, choice: 2) }.buttonStyle(DialogButtonStyle())
                                            }
                                        }
                                    }
                                }.frame(height: min(110, CGFloat(blocks.count) * 36))
                            }
                            HStack(spacing: 10) {
                                pane(L("当前版本") + (conflict.ours == .missing ? L("（已删除）") : ""), text: .constant(GitConflict.text(conflict.ours) ?? ""), id: "ours", editable: false)
                                pane(L("传入版本") + (conflict.theirs == .missing ? L("（已删除）") : ""), text: .constant(GitConflict.text(conflict.theirs) ?? ""), id: "theirs", editable: false)
                                pane(L("合并结果 · 可编辑"), text: $result, id: "result", editable: true)
                            }.frame(maxHeight: .infinity)
                            HStack {
                                Button(L("全部采用当前")) { result = GitConflict.text(conflict.ours) ?? "" }.buttonStyle(DialogButtonStyle())
                                Button(L("全部采用传入")) { result = GitConflict.text(conflict.theirs) ?? "" }.buttonStyle(DialogButtonStyle())
                                if conflict.ours == .missing { Button(L("确认删除（当前）")) { model.saveConflict(.ours) }.buttonStyle(DialogButtonStyle()) }
                                else if conflict.theirs == .missing { Button(L("确认删除（传入）")) { model.saveConflict(.theirs) }.buttonStyle(DialogButtonStyle()) }
                                Spacer()
                                Text(L("剩余 {0} 块", [String(describing: blocks.count)])).font(.system(size: 11)).foregroundStyle(.secondary)
                                Button(L("保存并标记已解决")) { model.saveConflict(.text(result)) }.buttonStyle(DialogButtonStyle(primary: true)).disabled(!blocks.isEmpty)
                            }
                        } else {
                            Text(L("此冲突包含二进制文件、符号链接或超大文件，无法逐块编辑。请选择保留的完整版本。"))
                                .font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                            HStack {
                                Spacer()
                                Button(L("采用当前并标记解决")) { model.saveConflict(.ours) }.buttonStyle(DialogButtonStyle())
                                Button(L("采用传入并标记解决")) { model.saveConflict(.theirs) }.buttonStyle(DialogButtonStyle(primary: true))
                            }
                        }
                    }.frame(width: min(1250, geometry.size.width - 90), height: min(730, geometry.size.height - 100)).disabled(model.busy)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.onAppear { result = GitConflict.text(conflict.current) ?? ""; model.conflictDraftDirty = false }
            .onChange(of: result) { _, value in model.conflictDraftDirty = value != (GitConflict.text(conflict.current) ?? "") }
            .onDisappear { model.conflictDraftDirty = false }
            .onExitCommand { if confirmingClose { confirmingClose = false } else { requestClose() } }
            .overlay {
                if confirmingClose {
                    ZStack {
                        Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
                        DialogCard {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 10) { DialogCloseButton { confirmingClose = false }; Text(L("合并结果尚未保存")).font(.system(size: 14, weight: .medium)); Spacer() }.dialogHeader()
                                Text(L("关闭将丢弃本次编辑的合并结果，磁盘中的冲突文件会保留。")).font(.system(size: 12)).foregroundStyle(.secondary)
                                HStack {
                                    Button(L("放弃编辑并关闭")) { model.conflictFile = nil }.buttonStyle(DialogButtonStyle())
                                    Spacer()
                                    Button(L("继续编辑")) { confirmingClose = false }.buttonStyle(DialogButtonStyle(primary: true))
                                }
                            }.frame(width: 420)
                        }
                    }
                }
            }
    }
    private func pane(_ title: String, text: Binding<String>, id: String, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium))
            CodeEditor(text: text, documentID: id, openIDs: [id], path: conflict.path, editable: editable, diff: false, diffLines: [], baseline: nil, position: .constant(""))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GitReviewBrowser: View {
    @ObservedObject var model: Workspace
    let request: Workspace.ReviewRequest
    @State private var review: GitTools.Review?
    @State private var history: [CommitEntry] = []
    @State private var selectedCommit: String?
    @State private var file: GitTools.ReviewFile?
    @State private var page = 0
    @State private var hasNext = false
    @State private var loading = true
    @State private var previewLoading = false
    @State private var failure: String?
    @State private var lines: [DiffLine] = []
    @State private var text = ""
    @State private var hovered: String?
    private var filePath: String? { if case .file(let path) = request.mode { return path }; return nil }
    private var compareRef: String? { if case .compare(let ref) = request.mode { return ref }; return nil }
    private var previewID: String { (review?.target ?? "") + ":" + (file?.path ?? "") }
    private var title: String { filePath != nil ? L("文件历史") : compareRef != nil ? L("分支对比") : L("提交详情") }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
                DialogCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            DialogCloseButton { model.reviewRequest = nil }
                            Text(title).font(.system(size: 14, weight: .medium))
                            if let filePath { Text(filePath).font(.system(size: 12)).lineLimit(1) }
                            Spacer()
                        }.dialogHeader()
                        if let review { Text(review.title).font(.system(size: 12)).textSelection(.enabled).lineLimit(2) }
                        if let failure { Text(failure).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled) }
                        if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                        else {
                            HStack(alignment: .top, spacing: 12) {
                                if filePath != nil || compareRef != nil {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ScrollView {
                                            LazyVStack(alignment: .leading, spacing: 5) {
                                                if filePath != nil {
                                                    ForEach(history) { item in commitRow(item, selectable: true) }
                                                    if history.isEmpty { Text(L("此路径暂无历史记录")).font(.system(size: 12)).foregroundStyle(.secondary) }
                                                } else if let review {
                                                    Text(L("当前独有 · {0}", [String(describing: review.currentOnly.count)])).font(.system(size: 12, weight: .semibold))
                                                    ForEach(review.currentOnly) { item in commitRow(item, selectable: false) }
                                                    Text(L("目标独有 · {0}", [String(describing: review.commits.count)])).font(.system(size: 12, weight: .semibold)).padding(.top, 8)
                                                    ForEach(review.commits) { item in commitRow(item, selectable: false) }
                                                }
                                            }.padding(2)
                                        }
                                        if filePath != nil {
                                            HStack {
                                                Button(L("上一页")) { page -= 1 }.disabled(page == 0)
                                                Spacer(); Text("\(page + 1)")
                                                Button(L("下一页")) { page += 1 }.disabled(!hasNext)
                                            }.font(.system(size: 11)).buttonStyle(DialogButtonStyle())
                                        }
                                    }.frame(width: 230)
                                }
                                ScrollView {
                                    LazyVStack(spacing: 3) {
                                        ForEach(review?.files ?? []) { item in
                                            Button { file = item } label: {
                                                HStack {
                                                    Text(item.status).foregroundStyle(item.status == "A" ? .green : item.status == "D" ? .red : .blue)
                                                    Text(item.path).lineLimit(2).truncationMode(.middle)
                                                    Spacer(minLength: 0)
                                                }.font(.system(size: 11)).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                                    .background(file?.id == item.id ? Color.blue.opacity(0.12) : hovered == item.id ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                                    .contentShape(Rectangle())
                                            }.buttonStyle(CursorPlainButtonStyle()).onHover { hovered = $0 ? item.id : nil }
                                        }
                                        if review?.files.isEmpty == true { Text(L("没有文件差异")).font(.system(size: 12)).foregroundStyle(.secondary).padding() }
                                    }
                                }.frame(width: 200)
                                VStack(alignment: .leading, spacing: 6) {
                                    if let file {
                                        Text(file.path + L(" · 差异")).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        if previewLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                                        else { CodeEditor(text: .constant(text), documentID: previewID, openIDs: [previewID], path: file.path, editable: false, diff: true, diffLines: lines, baseline: nil, position: .constant("")) }
                                    } else { Text(L("选择文件查看差异")).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                                }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                            }.frame(maxHeight: .infinity)
                        }
                        HStack {
                            Text(compareRef == nil ? L("差异相对该提交的父版本；恢复操作只修改工作区。") : L("文件对比为两个分支当前版本的直接差异。"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            if let compareRef {
                                Button(L("合并到当前分支…")) { model.prepareMerge(ref: compareRef) }.buttonStyle(DialogButtonStyle(primary: true)).disabled(model.busy || loading)
                            } else if let file, let review {
                                Button(L("恢复此文件到该版本…")) { model.prepareFileRestore(path: filePath ?? file.path, ref: review.target, sourcePath: file.path) }.buttonStyle(DialogButtonStyle()).disabled(model.busy)
                            }
                        }
                    }.frame(width: min(1250, geometry.size.width - 90), height: min(730, geometry.size.height - 100))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.onExitCommand { if model.toolConfirmation == nil { model.reviewRequest = nil } }
        .task(id: page) {
            loading = true; failure = nil; review = nil; file = nil
            do {
                switch request.mode {
                case .commit(let oid):
                    let value = try await GitTools.commitReview(request.root, ref: oid)
                    guard !Task.isCancelled else { return }; review = value; file = value.files.first
                case .compare(let ref):
                    let value = try await GitTools.compare(request.root, ref: ref)
                    guard !Task.isCancelled else { return }; review = value; file = value.files.first
                case .file(let path):
                    let values = try await GitTools.fileHistory(request.root, path: path, page: page)
                    guard !Task.isCancelled else { return }; hasNext = values.count > 50; history = Array(values.prefix(50)); selectedCommit = history.first?.id
                }
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
        .task(id: selectedCommit) {
            guard let selectedCommit else { return }
            review = nil; file = nil; failure = nil
            do {
                let value = try await GitTools.commitReview(request.root, ref: selectedCommit)
                guard !Task.isCancelled else { return }
                let historicalPath = history.first { $0.id == selectedCommit }?.historicalPath ?? filePath
                let relevant = value.files.filter { $0.path == historicalPath }
                review = GitTools.Review(title: value.title, base: value.base, target: value.target, files: relevant, commits: [])
                file = relevant.first
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
        }
        .task(id: previewID) {
            lines = []; text = ""; previewLoading = true
            if let review, let file {
                do {
                    let patch = try await GitTools.patch(request.root, review: review, path: file.path)
                    let parsed = await Task.detached { patch.utf8.count > 2_000_000 ? [] : DiffLine.parse(patch) }.value
                    guard !Task.isCancelled else { return }
                    lines = parsed; text = parsed.isEmpty ? L("此文件没有可显示的文本差异，可能为二进制、权限更改或内容过大。") : parsed.map(\.text).joined(separator: "\n")
                } catch { if !Task.isCancelled { failure = error.localizedDescription } }
            }
            if !Task.isCancelled { previewLoading = false }
        }
    }
    private func commitRow(_ item: CommitEntry, selectable: Bool) -> some View {
        Button {
            if selectable {
                guard selectedCommit != item.id else { return }
                review = nil; file = nil; failure = nil
                selectedCommit = item.id
            }
            else { model.showReview(.commit(item.id)) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.shortID + " · " + item.subject).lineLimit(2)
                Text(item.author + " · " + item.date).font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(ChoiceCardStyle())
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selectedCommit == item.id ? Color.blue : .clear))
    }
}

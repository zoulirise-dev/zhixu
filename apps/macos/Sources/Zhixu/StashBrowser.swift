import SwiftUI

struct StashBrowser: View {
    let root: String
    let close: () -> Void
    let restore: (StashRecord) -> Void
    @State private var records: [StashRecord] = []
    @State private var selectedID: String?
    @State private var files: [StashRecord.File] = []
    @State private var selectedFile: StashRecord.File?
    @State private var lines: [DiffLine] = []
    @State private var text = ""
    @State private var loading = true
    @State private var loadingFiles = false
    @State private var loadingDiff = false
    @State private var failure: String?
    @State private var revision = 0
    @State private var deletion: (record: StashRecord, file: StashRecord.File?)?
    @State private var deleting = false
    @State private var hoveredFile: String?
    private var selected: StashRecord? { records.first { $0.id == selectedID } }
    private var previewID: String { (selectedID ?? "") + ":" + (selectedFile?.path ?? "") }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.22).ignoresSafeArea().onTapGesture {}
                DialogCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            DialogCloseButton(action: close)
                            Text(L("临时收起的修改")).font(.system(size: 14, weight: .medium))
                            Text(L("{0} 条", [String(describing: records.count)])).font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            Button { revision += 1 } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(DialogButtonStyle()).help(L("刷新记录"))
                        }.dialogHeader()
                        Text(L("按收起时间倒序排列。差异对比收起时的原版本；恢复到当前工作区后，原备份仍保留。"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if let failure { Text(failure).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled) }
                        if records.isEmpty {
                            VStack(spacing: 12) {
                                if loading { ProgressView() }
                                else {
                                    Image(systemName: "archivebox").font(.system(size: 32, weight: .light)).foregroundStyle(.tertiary)
                                    Text(failure == nil ? L("暂无临时收起的修改") : L("未能加载备份记录")).font(.system(size: 14, weight: .medium))
                                    Text(failure == nil ? L("在工作区变更的更多菜单中选择“临时收起修改”，备份会显示在这里。") : L("请点击右上角刷新重试。"))
                                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 350)
                                }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                        HStack(spacing: 12) {
                            ScrollView {
                                LazyVStack(spacing: 5) {
                                    ForEach(records) { record in
                                        Button { selectedID = record.id } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Label(record.branch, systemImage: "arrow.triangle.branch").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                                Text(record.date.formatted(date: .numeric, time: .standard)).font(.system(size: 11)).foregroundStyle(.secondary)
                                                Text(record.message).font(.system(size: 11)).lineLimit(2)
                                                Text(record.reference).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                            }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
                                        }.buttonStyle(ChoiceCardStyle())
                                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selectedID == record.id ? Color.blue : .clear))
                                    }
                                }.padding(2)
                            }.frame(width: 220)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(L("文件 · {0}", [String(describing: files.count)])).font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Button {
                                        if let selected, let selectedFile { deletion = (selected, selectedFile) }
                                    } label: { Image(systemName: "trash") }.buttonStyle(DialogButtonStyle())
                                        .disabled(selectedFile == nil || loadingFiles).help(L("从备份中删除所选文件"))
                                }
                                if loadingFiles { ProgressView().frame(maxWidth: .infinity) }
                                ScrollView {
                                    LazyVStack(spacing: 2) {
                                        ForEach(files) { file in
                                            Button { selectedFile = file } label: {
                                                HStack {
                                                    Image(systemName: "doc.text")
                                                    Text(file.path).lineLimit(1).truncationMode(.middle)
                                                    Spacer(minLength: 4)
                                                    if file.untracked { Text(L("新增")).foregroundStyle(.green) }
                                                }.font(.system(size: 11)).padding(.horizontal, 8).frame(height: 26)
                                                    .background(selectedFile == file ? Color.blue.opacity(0.14) : hoveredFile == file.id ? Color.primary.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                                                    .contentShape(Rectangle())
                                            }.buttonStyle(CursorPlainButtonStyle()).help(file.path).onHover { hoveredFile = $0 ? file.id : nil }
                                        }
                                    }
                                }.frame(maxHeight: .infinity)
                            }.frame(width: 200)
                            VStack(alignment: .leading, spacing: 8) {
                                if let file = selectedFile {
                                    Text(file.path + L(" · 差异")).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                    if loadingDiff { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                                    else {
                                        CodeEditor(text: .constant(text), documentID: previewID, openIDs: [previewID], path: file.path, editable: false, diff: true, diffLines: lines, baseline: nil, position: .constant(""))
                                            .clipShape(RoundedRectangle(cornerRadius: 7))
                                    }
                                } else {
                                    Text(selected != nil && files.isEmpty && !loadingFiles ? L("此备份已没有文件更改") : L("选择记录和文件查看差异")).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        HStack {
                            Text(selected.map { L("所选记录来自「") + $0.branch + L("」分支") } ?? L("请选择一条记录")).font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Button(L("删除整条备份…")) { if let selected { deletion = (selected, nil) } }
                                .buttonStyle(DialogButtonStyle()).disabled(selected == nil || loading)
                            Button(L("恢复所选记录")) { if let selected { restore(selected) } }.buttonStyle(DialogButtonStyle(primary: true)).disabled(selected == nil || loading || loadingFiles)
                        }
                        }
                    }.frame(width: min(1050, max(400, geometry.size.width - 100)), height: min(680, max(300, geometry.size.height - 100)))
                }.frame(maxWidth: .infinity, maxHeight: .infinity).disabled(deletion != nil || deleting)
                if let deletion {
                    Color.black.opacity(0.18).ignoresSafeArea().onTapGesture {}
                    DialogCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) { DialogCloseButton { self.deletion = nil }; Text(deletion.file == nil ? L("删除整条备份？") : L("从备份中删除此文件？")).font(.system(size: 14, weight: .medium)); Spacer() }.dialogHeader()
                            Text(deletion.record.branch + " · " + deletion.record.date.formatted(date: .numeric, time: .standard)).font(.system(size: 12)).foregroundStyle(.secondary)
                            if let file = deletion.file { Text(file.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
                            Text(deletion.file == nil ? L("这条临时收起记录将被删除，之后无法从列表恢复。当前项目文件不会改变。") : L("仅删除备份中这个文件的修改，其他备份文件保留。当前项目文件不会改变。删除后无法从此记录恢复该文件。"))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            HStack {
                                Spacer()
                                Button(L("取消")) { self.deletion = nil }.buttonStyle(DialogButtonStyle())
                                Button(deleting ? L("正在删除…") : L("确认删除")) { deleteConfirmed() }.buttonStyle(DialogButtonStyle(primary: true))
                            }.disabled(deleting)
                        }.frame(width: 420)
                    }
                }
            }
        }.onExitCommand { if !deleting { if deletion != nil { deletion = nil } else { close() } } }
        .task(id: revision) {
            loading = true; failure = nil
            do {
                let result = try await StashRecord.read(root)
                guard !Task.isCancelled else { return }
                records = result
                if !result.contains(where: { $0.id == selectedID }) { selectedID = result.first?.id }
            } catch { if !Task.isCancelled { failure = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
        .task(id: selectedID) {
            files = []; selectedFile = nil; failure = nil; loadingFiles = true
            if let selected {
                do {
                    let result = try await selected.files(root)
                    guard !Task.isCancelled else { return }
                    files = result; selectedFile = result.first
                } catch { if !Task.isCancelled { failure = error.localizedDescription } }
            }
            if !Task.isCancelled { loadingFiles = false }
        }
        .task(id: previewID) {
            lines = []; text = ""; loadingDiff = true
            if let selected, let file = selectedFile {
                do {
                    let content = try await selected.preview(root, file: file)
                    guard !Task.isCancelled else { return }
                    if content.utf8.count > 2_000_000 || content.contains("\0") {
                        text = L("此文件为二进制或内容过大，无法显示文本差异。")
                    } else {
                        lines = file.untracked ? DiffLine.added(content) : DiffLine.parse(content)
                        text = lines.isEmpty ? L("没有可显示的文本差异（可能仅修改权限或文件类型）。") : lines.map(\.text).joined(separator: "\n")
                    }
                } catch { if !Task.isCancelled { failure = error.localizedDescription } }
            }
            if !Task.isCancelled { loadingDiff = false }
        }
    }
    private func deleteConfirmed() {
        guard let deletion, !deleting else { return }
        deleting = true
        Task {
            do {
                var replacement: String?
                if let file = deletion.file {
                    replacement = try await deletion.record.deletingFile(root, file: file)
                } else { try await deletion.record.delete(root) }
                records = try await StashRecord.read(root)
                selectedID = replacement ?? records.first?.id
                failure = nil
                self.deletion = nil
            } catch {
                self.deletion = nil
                failure = error.localizedDescription
            }
            deleting = false
        }
    }

}

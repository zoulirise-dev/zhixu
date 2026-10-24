import SwiftUI

struct RestoreConflictDialog: View {
    let entry: StashRestore.Entry
    let progress: String
    let answer: (StashRestore.Choice) -> Void
    @State private var comparison: RestoreComparison?
    var body: some View {
        GeometryReader { geometry in
            DialogCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        DialogCloseButton { answer(.cancel) }
                        Text(L("对比并恢复文件")).font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(progress).font(.system(size: 12)).foregroundStyle(.secondary)
                    }.dialogHeader()
                    Text(entry.path).font(.system(size: 12, design: .monospaced)).lineLimit(2).textSelection(.enabled)
                    Text(entry.backup == .missing ? L("备份中已删除此文件。恢复备份会删除当前文件，原备份会保留。") : L("查看当前文件与备份的差异，再选择要保留的版本。原备份会保留。"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        HStack {
                            Text(L("左右对照 · 同步滚动"))
                            Spacer()
                            if let comparison {
                                Text("−\(comparison.rows.filter { $0.kind == .removed }.count)").foregroundStyle(.red)
                                Text("+\(comparison.rows.filter { $0.kind == .added }.count)").foregroundStyle(.green)
                            }
                        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(10)
                            .background(Color(nsColor: AppTheme.subtle))
                        if let comparison {
                            if comparison.available {
                                HStack(spacing: 0) {
                                    Text(L("当前文件 · {0}", [String(describing: entry.current.summary)])).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(L("备份文件 · {0}", [String(describing: entry.backup.summary)])).frame(maxWidth: .infinity, alignment: .leading)
                                }.font(.system(size: 12, weight: .medium)).padding(10)
                                    .background(Color(nsColor: AppTheme.subtle))
                                RestoreSplitEditor(rows: comparison.rows, path: entry.path)
                            } else {
                                Text(comparison.note).font(.system(size: 13)).foregroundStyle(.secondary)
                                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            ProgressView(L("正在对比内容…")).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }.frame(maxHeight: .infinity).background(Color(nsColor: AppTheme.panel))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.09)))
                    if let comparison, comparison.available, !comparison.note.isEmpty {
                        Text(comparison.note).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Button(L("取消恢复")) { answer(.cancel) }.buttonStyle(DialogButtonStyle())
                            Spacer()
                            Button(L("保留当前文件")) { answer(.keep) }.buttonStyle(DialogButtonStyle())
                        }.frame(maxWidth: .infinity)
                        HStack {
                            Spacer()
                            Button(entry.backup == .missing ? L("恢复备份（删除文件）") : L("恢复备份")) { answer(.backup) }
                                .buttonStyle(DialogButtonStyle(primary: true)).disabled(!entry.canReplace)
                        }.frame(maxWidth: .infinity)
                    }
                }.frame(width: min(1160, max(0, geometry.size.width - 96)), height: min(640, max(0, geometry.size.height - 96)))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.task(id: entry.id) {
            let current = entry.current, backup = entry.backup
            let result = await Task.detached(priority: .userInitiated) { RestoreComparison.make(current: current, backup: backup) }.value
            guard !Task.isCancelled else { return }
            comparison = result
        }
    }
}

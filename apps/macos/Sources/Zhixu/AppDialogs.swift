import AppKit
import SwiftUI

private final class ThemedPanel: NSPanel { override var canBecomeKey: Bool { true } }
private final class DialogBackground: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        AppTheme.panel.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 16, yRadius: 16).fill()
        NSColor.separatorColor.setStroke(); NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 16, yRadius: 16).stroke()
    }
}
private final class DialogAction: NSButton {
    let handler: () -> Void
    let primary: Bool
    private var hovered = false
    private var hoverArea: NSTrackingArea?
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    init(_ title: String, frame: NSRect, primary: Bool = false, action: @escaping () -> Void) {
        handler = action; self.primary = primary
        super.init(frame: frame)
        self.title = title; isBordered = false; target = self; self.action = #selector(invoke)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func invoke() { handler() }
    override func draw(_ dirtyRect: NSRect) {
        (primary ? NSColor.systemBlue.withAlphaComponent(isHighlighted ? 0.72 : hovered ? 0.88 : 1) : NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.14 : hovered ? 0.10 : 0.065)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        if !primary {
            NSColor.labelColor.withAlphaComponent(hovered ? 0.20 : 0.13).setStroke()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: primary ? NSColor.white : NSColor.labelColor]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}
@MainActor enum AppDialogs {
    private static func panel(_ title: String, size: NSSize) -> ThemedPanel {
        let panel = ThemedPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = title; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.contentView = DialogBackground(frame: NSRect(origin: .zero, size: size))
        if let window = NSApp.mainWindow { panel.setFrameOrigin(NSPoint(x: window.frame.midX - size.width / 2, y: window.frame.midY - size.height / 2)) } else { panel.center() }
        return panel
    }
    @discardableResult private static func label(_ text: String, _ frame: NSRect, in view: NSView, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text); field.frame = frame
        field.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular); view.addSubview(field); return field
    }
    private static func field(_ value: String, _ frame: NSRect, in view: NSView) -> NSTextField {
        let field = NSTextField(string: value); field.frame = frame; field.isBordered = false; field.focusRingType = .none
        field.drawsBackground = true; field.backgroundColor = AppTheme.subtle; field.font = .systemFont(ofSize: 13)
        field.wantsLayer = true; field.layer?.cornerRadius = 7; view.addSubview(field); return field
    }
    static func confirm(_ title: String, message: String, accept: String, discard: String = "") -> Int {
        let width: CGFloat = 440
        let messageFont = NSFont.systemFont(ofSize: 13)
        let messageHeight = max(34, ceil((message as NSString).boundingRect(with: NSSize(width: width - 40, height: 400), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: messageFont]).height))
        let footerY: CGFloat = 54 + messageHeight + 16
        let panel = panel(title, size: NSSize(width: width, height: footerY + 48)), view = panel.contentView!
        let heading = label(title, NSRect(x: 42, y: 11, width: width - 60, height: 20), in: view, size: 13, bold: true)
        heading.maximumNumberOfLines = 1; heading.lineBreakMode = .byTruncatingMiddle; heading.toolTip = title
        let close = NSHostingView(rootView: DialogCloseButton { NSApp.stopModal(withCode: .init(rawValue: 0)) })
        close.frame = NSRect(x: 10, y: 8, width: 22, height: 24); view.addSubview(close)
        label(message, NSRect(x: 20, y: 54, width: width - 40, height: messageHeight), in: view).textColor = .secondaryLabelColor
        func buttonWidth(_ title: String) -> CGFloat {
            max(72, min(150, ceil((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width) + 24))
        }
        let acceptWidth = buttonWidth(accept), cancelWidth = buttonWidth(L("取消"))
        let cancel = DialogAction(L("取消"), frame: NSRect(x: width - 20 - acceptWidth - 8 - cancelWidth, y: footerY, width: cancelWidth, height: 30)) { NSApp.stopModal(withCode: .init(rawValue: 0)) }; cancel.keyEquivalent = "\u{1b}"
        view.addSubview(cancel)
        if !discard.isEmpty {
        view.addSubview(DialogAction(discard, frame: NSRect(x: 20, y: footerY, width: min(buttonWidth(discard), width - 20 - acceptWidth - 8 - cancelWidth - 32), height: 30)) { NSApp.stopModal(withCode: .init(rawValue: 2)) })
        }
        view.addSubview(DialogAction(accept, frame: NSRect(x: width - 20 - acceptWidth, y: footerY, width: acceptWidth, height: 30), primary: true) { NSApp.stopModal(withCode: .init(rawValue: 1)) })
        panel.makeKeyAndOrderFront(nil); let answer = NSApp.runModal(for: panel).rawValue; panel.orderOut(nil); return answer
    }
    private static var directoryPanel: NSPanel?
    static func directory(title: String, name: String? = nil, prompt: String, completion: @escaping (URL?) -> Void) {
        guard directoryPanel == nil else { directoryPanel?.makeKeyAndOrderFront(nil); return }
        // Present after the SwiftUI button transaction finishes; never nest runModal in it.
        let parent = NSApp.mainWindow
        let panel = panel(title, size: NSSize(width: 780, height: 610))
        directoryPanel = panel
        var completed = false
        let finish: (URL?) -> Void = { value in
            guard !completed else { return }
            completed = true
            if let parent = panel.sheetParent { parent.endSheet(panel) }
            panel.orderOut(nil)
            panel.contentView = nil
            directoryPanel = nil
            DispatchQueue.main.async { completion(value) }
        }
        panel.contentView = NSHostingView(rootView: DirectoryPickerView(title: title, name: name, prompt: prompt, finish: finish))
        DispatchQueue.main.async {
            if let parent { parent.beginSheet(panel) }
            else { panel.makeKeyAndOrderFront(nil) }
        }
    }

}

private struct DirectoryPickerView: View {
    let title: String
    let name: String?
    let prompt: String
    let finish: (URL?) -> Void
    @State private var current = FileManager.default.homeDirectoryForCurrentUser
    @State private var selected: URL?
    @State private var folders: [URL] = []
    @State private var path = ""
    @State private var newName = ""
    @State private var error = ""
    @State private var hovered: URL?
    @State private var hoveredShortcut: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loading = false
    @State private var navigationID = UUID()
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var target: URL { selected ?? current }
    private var destination: URL {
        name == nil ? target : target.appendingPathComponent(newName.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) { DialogCloseButton { navigationID = UUID(); finish(nil) }; Text(title).font(.system(size: 14, weight: .medium)); Spacer() }.dialogHeader()
            Text(name == nil ? L("单击选择文件夹，双击进入。也可以直接选择当前文件夹。") : L("选择保存位置，再填写新文件夹名称。双击文件夹可进入。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { navigate(current.deletingLastPathComponent()) } label: { Label(L("上一级"), systemImage: "arrow.up") }
                    .buttonStyle(DialogButtonStyle()).disabled(current.path == "/")
                TextField(L("输入文件夹路径，按回车前往"), text: $path)
                    .textFieldStyle(.plain).font(.system(size: 12)).padding(10)
                    .background(Color(nsColor: AppTheme.subtle), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { goToPath() }.accessibilityLabel(L("文件夹路径"))
                Button(L("前往")) { goToPath() }.buttonStyle(DialogButtonStyle())
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("常用位置")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(8)
                    shortcut(L("个人目录"), icon: "house", url: home)
                    shortcut(L("桌面"), icon: "desktopcomputer", url: home.appendingPathComponent("Desktop"))
                    shortcut(L("文稿"), icon: "doc", url: home.appendingPathComponent("Documents"))
                    shortcut(L("下载"), icon: "arrow.down.circle", url: home.appendingPathComponent("Downloads"))
                    shortcut(L("磁盘"), icon: "internaldrive", url: URL(fileURLWithPath: "/"))
                    Spacer()
                }.padding(8).frame(width: 140).background(Color(nsColor: AppTheme.subtle), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(current.lastPathComponent.isEmpty ? L("磁盘根目录") : current.lastPathComponent).fontWeight(.semibold).lineLimit(1)
                        Spacer()
                        Text(loading ? L("正在读取…") : L("{0} 个文件夹", [String(describing: folders.count)])).foregroundStyle(.secondary)
                    }.font(.system(size: 12)).padding(12)
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            if folders.isEmpty {
                                Text(L("这里没有子文件夹\n可以选择当前文件夹"))
                                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity).padding(.vertical, 50)
                            }
                            ForEach(folders, id: \.path) { folder in
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill").foregroundStyle(.blue)
                                    Text(folder.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    if selected == folder { Image(systemName: "checkmark").foregroundStyle(.blue) }
                                    Button { navigate(folder) } label: {
                                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).frame(width: 28, height: 28)
                                    }.buttonStyle(CursorPlainButtonStyle()).foregroundStyle(.secondary).help(L("进入文件夹"))
                                }.font(.system(size: 13)).padding(.leading, 10).padding(.trailing, 4).frame(height: 36)
                                    .background(selected == folder ? Color.blue.opacity(0.10) : hovered == folder ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { navigate(folder) }
                                    .onTapGesture { selected = folder; error = "" }
                                    .onHover { hovered = $0 ? folder : nil }
                                    .accessibilityElement(children: .contain).accessibilityLabel(folder.lastPathComponent)
                                    .accessibilityAction(named: L("选择文件夹")) { selected = folder }
                            }
                        }.padding(6)
                    }.id(current.path).disabled(loading).opacity(loading ? 0.5 : 1)
                }.frame(maxWidth: .infinity).background(Color(nsColor: AppTheme.panel), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.09)))
            }.frame(maxHeight: .infinity)
            if name != nil {
                HStack {
                    Text(L("新文件夹名称")).font(.system(size: 12))
                    TextField(L("例如：my-project"), text: $newName).textFieldStyle(.plain).padding(9)
                        .background(Color(nsColor: AppTheme.subtle), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(name == nil ? L("将选择") : L("将创建")).fontWeight(.medium)
                    Spacer()
                    if selected != nil {
                        Button(L("改选当前文件夹")) { selected = nil }.buttonStyle(CursorPlainButtonStyle()).foregroundStyle(.blue)
                    }
                }.font(.system(size: 11))
                Text(destination.path).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(destination.path)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 10) {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
                Spacer(minLength: 0)
                Button(L("取消")) { navigationID = UUID(); finish(nil) }.buttonStyle(DialogButtonStyle()).keyboardShortcut(.cancelAction)
                Button(prompt) { confirm() }.buttonStyle(DialogButtonStyle(primary: true)).disabled(loading)
            }
        }.padding(.horizontal, 24).padding(.bottom, 20).frame(width: 780, height: 610)
            .background(Color(nsColor: AppTheme.panel), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.09)))
            .background(ScrollStyleInstaller())
            .onAppear { newName = name ?? ""; navigate(home) }
            .onDisappear { navigationID = UUID() }
    }
    private func shortcut(_ title: String, icon: String, url: URL) -> some View {
        Button { navigate(url) } label: {
            Label(title, systemImage: icon).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(9)
                .foregroundStyle(current == url ? Color.blue : Color.primary)
                .background(current == url ? Color.blue.opacity(hoveredShortcut == url ? 0.14 : 0.09) : hoveredShortcut == url ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(CursorPlainButtonStyle())
            .onHover { hoveredShortcut = $0 ? url : (hoveredShortcut == url ? nil : hoveredShortcut) }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hoveredShortcut == url)
    }
    private func goToPath() {
        navigate(URL(fileURLWithPath: (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath).standardizedFileURL)
    }
    private func navigate(_ url: URL, confirmAfterLoading: Bool = false) {
        let request = UUID()
        navigationID = request; loading = true; error = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard navigationID == request, loading else { return }
            navigationID = UUID(); loading = false
            error = L("读取此文件夹超时。可以选择其他位置，或检查系统的文件夹访问权限。")
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            }
            DispatchQueue.main.async {
                guard navigationID == request else { return }
                loading = false
                switch result {
                case .success(let values):
                    current = url; path = url.path; folders = values; selected = nil; error = ""
                    if confirmAfterLoading { confirm() }
                case .failure:
                    error = L("无法打开此路径，请检查文件夹是否存在以及访问权限。")
                }
            }
        }
    }
    private func confirm() {
        guard !loading else { return }
        if path != current.path {
            let url = URL(fileURLWithPath: (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath).standardizedFileURL
            navigate(url, confirmAfterLoading: true)
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            error = L("请选择存在的文件夹"); return
        }
        if name != nil {
            let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.contains("/"), !value.contains("\0"), value != ".", value != ".." else {
                error = L("请输入有效的新文件夹名称"); return
            }
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                error = L("这个文件夹名称已存在，请换一个名称"); return
            }
        }
        finish(destination)
    }
}

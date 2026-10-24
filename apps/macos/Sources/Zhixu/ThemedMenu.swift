import SwiftUI
import AppKit

struct AppMenuItem: Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    var enabled = true
    let action: () -> Void
}
private enum MenuLayout {
    static func width(for items: [AppMenuItem]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12)
        let labelWidth = items.map { ($0.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        // Outer padding, row padding, icon and gap match AppMenuList.
        return max(144, ceil(labelWidth) + 16 + 20 + 16 + 18 + 4)
    }
}
@MainActor final class ThemedMenuPresenter: ObservableObject {
    struct Request { let items: [AppMenuItem]; let point: CGPoint; var keepsBranchPickerOpen = false }
    static let shared = ThemedMenuPresenter()
    static weak var moreAnchor: NSView?
    @Published var request: Request?
    private var monitor: Any?
    private var observer: NSObjectProtocol?
    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { event in
            if event.type == .keyDown, event.keyCode == 53, self.request != nil { self.request = nil; return nil }
            if event.type == .scrollWheel { self.request = nil }
            return event
        }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in MainActor.assumeIsolated { Self.dismiss() } }
    }
    static func dismiss() { shared.request = nil }
    static func showMore(_ items: [AppMenuItem]) {
        guard let view = moreAnchor, let window = view.window else { return }
        let rect = view.convert(view.bounds, to: nil)
        show(items, at: window.convertPoint(toScreen: NSPoint(x: rect.minX, y: rect.minY - 5)), window: window)
    }
    static func show(_ items: [AppMenuItem], at point: NSPoint = NSEvent.mouseLocation, window: NSWindow? = nil, keepsBranchPickerOpen: Bool = false) {
        guard !items.isEmpty, let owner = window ?? NSApp.mainWindow ?? NSApp.keyWindow else { return }
        let local = owner.convertPoint(fromScreen: point)
        shared.request = Request(items: items, point: CGPoint(x: local.x, y: owner.frame.height - local.y), keepsBranchPickerOpen: keepsBranchPickerOpen)
    }
}
struct AppMenuOverlay: View {
    @ObservedObject var presenter: ThemedMenuPresenter
    var body: some View {
        GeometryReader { geometry in
            if let request = presenter.request {
                ZStack(alignment: .topLeading) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { ThemedMenuPresenter.dismiss() }
                    AppMenuList(items: request.items)
                        .compositingGroup().shadow(color: .black.opacity(0.16), radius: 18, y: 6)
                        .offset(x: max(8, min(request.point.x, geometry.size.width - MenuLayout.width(for: request.items) - 8)),
                                y: max(8, min(request.point.y, geometry.size.height - CGFloat(request.items.count * 36 + 24))))
                }
            }
        }.ignoresSafeArea(.container, edges: .top).allowsHitTesting(presenter.request != nil)
    }
}
private struct AppMenuList: View {
    let items: [AppMenuItem]
    @State private var hovered: String?
    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                Button { ThemedMenuPresenter.dismiss(); item.action() } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon).frame(width: 16).foregroundStyle(.secondary)
                        Text(item.title).lineLimit(1).fixedSize(horizontal: true, vertical: false); Spacer(minLength: 0)
                    }.font(.system(size: 12)).padding(.horizontal, 10).frame(height: 36).contentShape(Rectangle())
                        .background(hovered == item.id && item.enabled ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(CursorPlainButtonStyle()).disabled(!item.enabled).opacity(item.enabled ? 1 : 0.4)
                    .onHover { hovered = $0 ? item.id : nil }
            }
        }.padding(8).frame(width: MenuLayout.width(for: items)).background(Color(nsColor: AppTheme.panel), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }
}
private struct ContextMenuCapture: NSViewRepresentable {
    @Environment(\.isEnabled) private var enabled
    let keepsBranchPickerOpen: Bool
    let items: () -> [AppMenuItem]
    func makeNSView(context: Context) -> ContextMenuView { ContextMenuView() }
    func updateNSView(_ view: ContextMenuView, context: Context) { view.items = items; view.keepsBranchPickerOpen = keepsBranchPickerOpen; view.enabled = enabled }
}
private final class ContextMenuView: NSView {
    var enabled = true
    var keepsBranchPickerOpen = false
    var items: (() -> [AppMenuItem])?
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, self.enabled, let window = self.window, event.window === window,
                  event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                  !self.isHiddenOrHasHiddenAncestor,
                  self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                  self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
            let entries = self.items?() ?? []
            guard !entries.isEmpty else { return event }
            let location = event.locationInWindow
            ThemedMenuPresenter.show(entries, at: window.convertPoint(toScreen: location), window: window, keepsBranchPickerOpen: self.keepsBranchPickerOpen)
            return nil
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
extension View {
    func themedContextMenu(keepsBranchPickerOpen: Bool = false, _ items: @escaping () -> [AppMenuItem]) -> some View {
        background(GeometryReader { geometry in
            ContextMenuCapture(keepsBranchPickerOpen: keepsBranchPickerOpen, items: items).frame(width: geometry.size.width, height: geometry.size.height)
        })
    }
}

struct MoreMenuAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { let view = MenuAnchorView(); ThemedMenuPresenter.moreAnchor = view; return view }
    func updateNSView(_ view: NSView, context: Context) { ThemedMenuPresenter.moreAnchor = view }
}
private final class MenuAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

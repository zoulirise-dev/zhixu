import SwiftUI
import AppKit

enum AppTheme {
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    static let canvas = adaptive(NSColor(red: 0.95, green: 0.96, blue: 0.975, alpha: 1), NSColor(white: 0.10, alpha: 1))
    static let panel = adaptive(.white, NSColor(white: 0.145, alpha: 1))
    static let subtle = adaptive(NSColor(white: 0.975, alpha: 1), NSColor(white: 0.18, alpha: 1))
    static func apply(_ mode: String) { NSApp.appearance = mode == "light" ? NSAppearance(named: .aqua) : mode == "dark" ? NSAppearance(named: .darkAqua) : nil }
}
// Native cursor rectangles survive AppKit cursor resets and do not share a
// global push/pop stack across nested SwiftUI hover regions.
struct ActionCursor: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.background(ActionCursorRegion(enabled: enabled))
            // SwiftUI's hosting view may reset the background NSView cursor.
            // Reassert it from the actual interactive region on every move.
            .onContinuousHover { phase in
                guard enabled else { return }
                switch phase {
                case .active: NSCursor.pointingHand.set()
                case .ended:
                    if NSCursor.current == .pointingHand { NSCursor.arrow.set() }
                }
            }
            .onChange(of: enabled) { _, value in
                if !value, NSCursor.current == .pointingHand { NSCursor.arrow.set() }
            }
    }
}
private struct ActionCursorRegion: NSViewRepresentable {
    let enabled: Bool
    func makeNSView(context: Context) -> ActionCursorView { ActionCursorView() }
    func updateNSView(_ view: ActionCursorView, context: Context) { view.cursorEnabled = enabled }
}
final class ActionCursorView: NSView {
    var cursorEnabled = true {
        didSet {
            guard oldValue != cursorEnabled else { return }
            updateTrackingAreas()
            window?.invalidateCursorRects(for: self)
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func resetCursorRects() {
        super.resetCursorRects()
        if cursorEnabled, !isHiddenOrHasHiddenAncestor {
            addCursorRect(visibleRect, cursor: .pointingHand)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        if cursorEnabled {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
        }
    }
    override func cursorUpdate(with event: NSEvent) {
        if cursorEnabled { NSCursor.pointingHand.set() }
    }
}
extension View { func actionCursor() -> some View { modifier(ActionCursor()) } }
struct CursorPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.actionCursor() }
}
struct DialogButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        DialogButtonBody(configuration: configuration, primary: primary)
    }
    private struct DialogButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 9)
                .foregroundStyle(primary ? Color.white : Color.primary)
                .background(primary ? Color.blue.opacity(configuration.isPressed ? 0.72 : hovered ? 0.88 : 1) : Color.primary.opacity(configuration.isPressed ? 0.14 : hovered ? 0.10 : 0.065), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(primary ? Color.clear : Color.primary.opacity(hovered ? 0.20 : 0.13)))
                .opacity(enabled ? 1 : 0.4)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovered = $0 }.actionCursor()
                .animation(.easeOut(duration: 0.12), value: hovered)
        }
    }
}
struct DialogCard<Content: View>: View {
    var bottomPadding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View { content.padding(.horizontal, 24).padding(.bottom, bottomPadding).background(Color(nsColor: AppTheme.panel), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.09))).compositingGroup().shadow(color: .black.opacity(0.18), radius: 24, y: 8) }
}

/// Compact checkbox shared by file rows and their select-all controls.
struct ThemeCheckboxStyle: ToggleStyle {
    var mixed = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        ThemeCheckbox(isOn: configuration.$isOn, mixed: mixed, enabled: enabled)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .toggleStyle(.checkbox)
                    .accessibilityValue(mixed ? L("部分选中") : configuration.isOn ? L("已选中") : L("未选中"))
            }
    }
}
private struct ThemeCheckbox: View {
    @Binding var isOn: Bool
    let mixed: Bool
    let enabled: Bool
    @State private var hovering = false
    var body: some View {
        Button { isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(isOn || mixed ? Color.blue : Color.primary.opacity(hovering ? 0.06 : 0.025))
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(isOn || mixed || hovering ? Color.blue.opacity(0.85) : Color.primary.opacity(0.23), lineWidth: 1) }
                .overlay {
                    if isOn || mixed {
                        Image(systemName: mixed ? "minus" : "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 14, height: 14)
                .frame(width: 20, height: 22).contentShape(Rectangle())
        }.buttonStyle(CursorPlainButtonStyle()).opacity(enabled ? 1 : 0.4).onHover { hovering = $0 }
    }
}

struct CompactThemeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CompactButtonBody(label: configuration.label, pressed: configuration.isPressed)
    }
    private struct CompactButtonBody: View {
        let label: ButtonStyleConfiguration.Label
        let pressed: Bool
        @State private var hovered = false
        var body: some View {
            label.font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9).frame(height: 24)
                .foregroundStyle(Color.blue)
                .background(Color.blue.opacity(pressed ? 0.19 : hovered ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.blue.opacity(hovered ? 0.3 : 0.16)))
                .actionCursor().contentShape(RoundedRectangle(cornerRadius: 6)).onHover { hovered = $0 }
        }
    }
}

struct ChoiceCardStyle: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        ChoiceCardBody(configuration: configuration, destructive: destructive)
    }
    private struct ChoiceCardBody: View {
        let configuration: ButtonStyleConfiguration
        let destructive: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        private var tint: Color { destructive ? .red : .blue }
        var body: some View {
            configuration.label.font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(enabled && (hovered || configuration.isPressed) ? tint.opacity(configuration.isPressed ? 0.20 : 0.10) : Color(nsColor: AppTheme.subtle), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(enabled && (hovered || configuration.isPressed) ? tint.opacity(0.6) : Color.clear))
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .actionCursor().scaleEffect(configuration.isPressed ? 0.985 : 1)
                .animation(.easeOut(duration: 0.12), value: hovered)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
    }
}

/// Use the same AppKit close widget as macOS windows, with a dialog-specific action.
struct DialogCloseButton: NSViewRepresentable {
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    func makeNSView(context: Context) -> NativeDialogClose { NativeDialogClose() }
    func updateNSView(_ view: NativeDialogClose, context: Context) {
        view.action = action
        view.button?.isEnabled = enabled
        view.button?.toolTip = L("关闭")
        view.button?.setAccessibilityLabel(L("关闭弹窗"))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NativeDialogClose, context: Context) -> CGSize? {
        CGSize(width: 22, height: 24)
    }
}
final class NativeDialogClose: NSView {
    let button = NSWindow.standardWindowButton(.closeButton, for: [.titled, .closable])
    var action: () -> Void = {}
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if let button {
            button.target = self; button.action = #selector(closeDialog)
            addSubview(button)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        if let button {
            // Text's visible glyphs sit slightly below its typographic frame center.
            // Match that optical center while keeping the native control and hit area.
            let opticalOffset: CGFloat = isFlipped ? 1 : -1
            button.setFrameOrigin(NSPoint(x: (bounds.width - button.frame.width) / 2,
                                          y: (bounds.height - button.frame.height) / 2 + opticalOffset))
        }
    }
    @objc private func closeDialog() { action() }
}

private struct DialogHeaderLayout: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(height: 40).padding(.leading, -14)
    }
}
extension View {
    func dialogHeader() -> some View { modifier(DialogHeaderLayout()) }
}


struct GitBranchIcon: View {
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 4, y: 4.6)); path.addLine(to: CGPoint(x: 4, y: 11.4))
                path.move(to: CGPoint(x: 12, y: 6.6)); path.addLine(to: CGPoint(x: 12, y: 7.4))
                path.addCurve(to: CGPoint(x: 4, y: 10), control1: CGPoint(x: 12, y: 10), control2: CGPoint(x: 4, y: 7.4))
            }.stroke(style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            ForEach(0..<3) { index in
                Circle().stroke(lineWidth: 1.1).frame(width: 3.2, height: 3.2)
                    .position(x: index == 2 ? 12 : 4, y: index == 0 ? 3 : index == 1 ? 13 : 5)
            }
        }.frame(width: 16, height: 16).accessibilityHidden(true)
    }
}

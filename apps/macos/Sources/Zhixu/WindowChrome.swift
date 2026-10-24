import SwiftUI
import AppKit

struct AppTitleBar: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableTitleView { DraggableTitleView() }
    func updateNSView(_ view: DraggableTitleView, context: Context) {}
}
final class DraggableTitleView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.titleVisibility = .hidden
        window?.titlebarAppearsTransparent = true
        DispatchQueue.main.async { [weak self] in self?.centerWindowButtons() }
    }
    override func layout() {
        super.layout()
        centerWindowButtons()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
    private func centerWindowButtons() {
        guard window?.styleMask.contains(.fullScreen) != true else { return }
        guard let close = window?.standardWindowButton(.closeButton), let closeParent = close.superview else { return }
        let inset = (bounds.height - close.frame.height) / 2
        let left = closeParent.convert(NSPoint(x: bounds.minX + inset, y: bounds.midY), from: self).x
        let shift = left - close.frame.minX
        // Move the native group as a unit, preserving system sizes and spacing.
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window?.standardWindowButton(kind), let parent = button.superview else { continue }
            let center = parent.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: self)
            button.setFrameOrigin(NSPoint(x: button.frame.minX + shift, y: center.y - button.frame.height / 2))
        }
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        AppTheme.canvas.setFill(); bounds.fill()
        let title = L("枝序 · 让 Git 简单一点") as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
        let size = title.size(withAttributes: attributes)
        title.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}
struct PanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Color(nsColor: AppTheme.panel))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.055), lineWidth: 1))
    }
}
extension View { func panelCard() -> some View { modifier(PanelCard()) } }

import SwiftUI
import AppKit

/// Keep AppKit's scrolling, dragging and accessibility behavior; only replace its drawing.
final class SlimScroller: NSScroller {
    private var hovered = false
    private var pressed = false
    private var tracking: NSTrackingArea?
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 10 }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func draw(_ dirtyRect: NSRect) { drawKnob() }
    override func drawKnob() {
        var knob = rect(for: .knob)
        guard knob.width > 0, knob.height > 0, knobProportion < 1 else { return }
        if bounds.height > bounds.width {
            knob.origin.x = bounds.midX - 3
            knob.size.width = 6
        } else {
            knob.origin.y = bounds.midY - 3
            knob.size.height = 6
        }
        NSColor.labelColor.withAlphaComponent(pressed ? 0.55 : hovered ? 0.40 : 0.13).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 3, yRadius: 3).fill()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        pressed = true; needsDisplay = true
        super.mouseDown(with: event)
        pressed = false; needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

struct ScrollStyleInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> Installer { Installer() }
    func updateNSView(_ view: Installer, context: Context) { view.schedule() }
    final class Installer: NSView {
        private var pending = false
        private var observer: Timer?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer?.invalidate(); observer = nil
            if window != nil {
                schedule()
                // SwiftUI can materialize native scroll views after its representable update.
                observer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.schedule() }
            }
        }
        deinit { observer?.invalidate() }
        override func layout() { super.layout(); schedule() }
        func schedule() {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pending = false
                if let root = self.window?.contentView { self.install(in: root) }
            }
        }
        private func install(in view: NSView) {
            if let scroll = view as? NSScrollView {
                // Keep the subtle thumb visible while idle; overlay style would fade it out entirely.
                if scroll.scrollerStyle != .legacy { scroll.scrollerStyle = .legacy }
                if let old = scroll.verticalScroller, !(old is SlimScroller) {
                    let replacement = SlimScroller(frame: old.frame)
                    replacement.doubleValue = old.doubleValue; replacement.knobProportion = old.knobProportion
                    replacement.isEnabled = old.isEnabled
                    replacement.target = old.target; replacement.action = old.action
                    let visible = scroll.hasVerticalScroller
                    scroll.verticalScroller = replacement
                    scroll.hasVerticalScroller = visible
                }
                if let old = scroll.horizontalScroller, !(old is SlimScroller) {
                    let replacement = SlimScroller(frame: old.frame)
                    replacement.doubleValue = old.doubleValue; replacement.knobProportion = old.knobProportion
                    replacement.isEnabled = old.isEnabled
                    replacement.target = old.target; replacement.action = old.action
                    let visible = scroll.hasHorizontalScroller
                    scroll.horizontalScroller = replacement
                    scroll.hasHorizontalScroller = visible
                }
            }
            for child in view.subviews { install(in: child) }
        }
    }
}

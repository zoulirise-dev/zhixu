import AppKit
import SwiftUI
@main struct ScrollStyleIntegration {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        func check(_ value: Bool, _ title: String) throws {
            guard value else { throw NSError(domain: title, code: 1) }; print("PASS: " + title)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300)); window.contentView = root
        let installer = ScrollStyleInstaller.Installer(frame: .zero); root.addSubview(installer)
        let scroll = NSScrollView(frame: root.bounds); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 1000)); root.addSubview(scroll)
        for _ in 0..<20 {
            if scroll.verticalScroller is SlimScroller { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try check(scroll.verticalScroller is SlimScroller, "style delayed SwiftUI scroll views")
        try check(SlimScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) == 10, "narrow scrollbar hit area")
        try check(!scroll.hasHorizontalScroller, "preserve hidden scrollbar state")
        try check(installer.hitTest(.zero) == nil, "installer does not intercept input")
        window.contentView = nil
    }
}

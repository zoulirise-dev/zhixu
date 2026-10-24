import AppKit
@main struct DialogCloseIntegration {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let close = NativeDialogClose(frame: NSRect(x: 0, y: 0, width: 22, height: 24))
        var calls = 0
        close.action = { calls += 1 }
        window.contentView!.addSubview(close)
        guard let button = close.button else { throw NSError(domain: "Missing native close widget", code: 1) }
        button.performClick(nil)
        guard calls == 1, window.contentView != nil else { throw NSError(domain: "Close action failed", code: 2) }
        print("PASS: native AppKit close widget invokes dialog action without closing its window")
    }
}

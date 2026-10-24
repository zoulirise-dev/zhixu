import AppKit
@main struct DialogLayoutIntegration {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        var size = NSSize.zero
        var snapshotError: Error?
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if let panel = NSApp.modalWindow, let view = panel.contentView {
                size = panel.frame.size
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    do { try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/compact-confirm.png")) } catch { snapshotError = error }
                }
            }
            NSApp.stopModal(withCode: .init(rawValue: 0))
        }
        let result = AppDialogs.confirm("保存对「.prettierrc.js」的修改？", message: "关闭前保存，或放弃此文件的编辑。", accept: "保存", discard: "不保存")
        if let snapshotError { throw snapshotError }
        guard result == 0, size.width == 440, size.height <= 160 else { throw NSError(domain: "Compact layout or cancel action", code: 1) }
        print("PASS: compact save dialog 440 x \(Int(size.height)), cancellation preserved")
    }
}

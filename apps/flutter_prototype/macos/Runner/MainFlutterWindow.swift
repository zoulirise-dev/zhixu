import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private func menuLabels(_ menu: NSMenu?) -> [String] {
    guard let menu else { return [] }
    return menu.items.flatMap { [$0.title] + menuLabels($0.submenu) }
  }
  private var chinese = true
  private var titleDimmer: NSView?
  private var modalOpacity: CGFloat = 0
  private var titleStrip: ZhixuTitleStrip?
  private var desktopChannel: FlutterMethodChannel?
  private var dialogButtons: [Int: NSButton] = [:]
  @objc private func closeDialog(_ sender: NSButton) {
    desktopChannel?.invokeMethod("closeDialog", arguments: sender.tag)
  }
  private func updateDialogButtons() {
    let last = dialogButtons.keys.max()
    for (id, button) in dialogButtons { button.isHidden = id != last }
  }

  private func updateTitleDimmer() {
    guard let strip = titleStrip, let host = contentView?.superview else { return }
    if titleDimmer == nil {
      let mask = NSView(frame: .zero)
      mask.wantsLayer = true
      mask.layer?.backgroundColor = NSColor.black.cgColor
      host.addSubview(mask, positioned: .above, relativeTo: nil)
      titleDimmer = mask
    }
    titleDimmer?.frame = host.convert(strip.bounds, from: strip)
    titleDimmer?.alphaValue = modalOpacity
    titleDimmer?.isHidden = modalOpacity <= 0.001
    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      if let button = standardWindowButton(kind) {
        for overlay in button.subviews.compactMap({ $0 as? ZhixuHandCursor }) {
          overlay.isHidden = modalOpacity > 0.001
          invalidateCursorRects(for: overlay)
        }
      }
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: windowFrame.minX, y: windowFrame.minY, width: 1420, height: 900), display: true)
    self.minSize = NSSize(width: 1080, height: 720)
    self.title = "枝序 · 让 Git 简单一点"
    self.styleMask.insert(.fullSizeContentView)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.titlebarSeparatorStyle = .none
    self.isMovableByWindowBackground = false
    let strip = ZhixuTitleStrip(frame: NSRect(x: 0, y: flutterViewController.view.bounds.height - 45, width: flutterViewController.view.bounds.width, height: 45))
    strip.autoresizingMask = [.width, .minYMargin]
    flutterViewController.view.addSubview(strip)
    self.titleStrip = strip
    strip.layoutChanged = { [weak self] in self?.updateTitleDimmer() }
    self.center()

    let channel = FlutterMethodChannel(name: "app.zhixu/desktop", binaryMessenger: flutterViewController.engine.binaryMessenger)
    self.desktopChannel = channel
    channel.setMethodCallHandler { [weak self, weak flutterViewController] call, result in
      guard let self, let flutterViewController else { result(nil); return }
      if call.method == "modalBarrier", let opacity = call.arguments as? Double {
        self.modalOpacity = CGFloat(max(0, min(1, opacity)))
        self.updateTitleDimmer()
        result(nil); return
      }
      if call.method == "windowAction", let action = call.arguments as? String {
        result(nil)
        switch action {
        case "quit": NSApp.terminate(nil)
        case "minimize": self.performMiniaturize(nil)
        case "zoom": self.performZoom(nil)
        case "fullscreen": self.toggleFullScreen(nil)
        default: break
        }
        return
      }
      if call.method == "preferredLanguages" { result(Locale.preferredLanguages); return }
      if call.method == "windowChrome", let args = call.arguments as? [String: Any] {
        if let language = args["language"] as? String {
          self.chinese = language != "English"
          for button in self.dialogButtons.values { button.toolTip = self.chinese ? "关闭" : "Close" }
        }
        if let dark = args["dark"] as? Bool { self.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); self.titleStrip?.dark = dark }
        if let title = args["title"] as? String { self.title = title; self.titleStrip?.text = title }
        self.titleStrip?.needsDisplay = true
        self.titleStrip?.needsLayout = true
        result(nil); return
      }
      if call.method == "chromeMetrics" {
        if let button = self.standardWindowButton(.closeButton), let parent = button.superview {
          let frame = parent.convert(button.frame, to: flutterViewController.view)
          result(["language": self.chinese ? "zh" : "en", "menuTitles": NSApp.mainMenu?.items.map { $0.title } ?? [], "menuLabels": self.menuLabels(NSApp.mainMenu), "modalOpacity": Double(self.modalOpacity), "height": Double(self.titleStrip?.bounds.height ?? 0), "left": Double(frame.minX), "top": Double(flutterViewController.view.bounds.height - frame.maxY)])
        } else { result(["height": 45.0, "left": -1.0, "top": -1.0]) }
        return
      }
      if call.method == "dialogClose", let args = call.arguments as? [String: Any], let id = args["id"] as? Int,
         let x = args["x"] as? Double, let y = args["y"] as? Double,
         let width = args["width"] as? Double, let height = args["height"] as? Double {
        let view = flutterViewController.view
        let button: NSButton
        if let existing = self.dialogButtons[id] { button = existing }
        else if let native = NSWindow.standardWindowButton(.closeButton, for: [.titled, .closable]) {
          button = native; button.tag = id; button.target = self; button.action = #selector(MainFlutterWindow.closeDialog(_:))
          button.toolTip = self.chinese ? "关闭" : "Close"; view.addSubview(button); self.dialogButtons[id] = button
        } else { result(nil); return }
        let px = x + (width - button.frame.width) / 2
        let py = view.isFlipped ? y + (height - button.frame.height) / 2 : view.bounds.height - y - (height + button.frame.height) / 2
        button.setFrameOrigin(NSPoint(x: px, y: py)); ZhixuHandCursor.install(on: button); self.updateDialogButtons(); result(nil); return
      }
      if call.method == "removeDialogClose", let args = call.arguments as? [String: Any], let id = args["id"] as? Int {
        self.dialogButtons.removeValue(forKey: id)?.removeFromSuperview(); self.updateDialogButtons(); result(nil); return
      }

      if call.method == "trash", let args = call.arguments as? [String: Any], let path = args["path"] as? String {
        do {
          try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
          result(nil)
        } catch { result(FlutterError(code: "trash_failed", message: "无法移到废纸篓", details: nil)) }
      } else { result(FlutterMethodNotImplemented) }
    }
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

// Same 45 pt draggable strip and native-button positioning as WindowChrome.swift.
final class ZhixuTitleStrip: NSView {
  var layoutChanged: (() -> Void)?
  var dark = false
  var text = "枝序 · 让 Git 简单一点"
  override var mouseDownCanMoveWindow: Bool { true }
  override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); DispatchQueue.main.async { [weak self] in self?.positionButtons() } }
  override func layout() { super.layout(); positionButtons(); layoutChanged?() }
  override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
  private func positionButtons() {
    guard window?.styleMask.contains(.fullScreen) != true,
          let close = window?.standardWindowButton(.closeButton), let parent = close.superview else { return }
    let inset = (bounds.height - close.frame.height) / 2
    let x = parent.convert(NSPoint(x: inset, y: bounds.midY), from: self).x
    let shift = x - close.frame.minX
    for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      guard let button = window?.standardWindowButton(kind), let container = button.superview else { continue }
      let center = container.convert(NSPoint(x: bounds.midX, y: bounds.midY), from: self)
      button.setFrameOrigin(NSPoint(x: button.frame.minX + shift, y: center.y - button.frame.height / 2))
      ZhixuHandCursor.install(on: button)
    }
  }
  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
  }
  override func draw(_ dirtyRect: NSRect) {
    (dark ? NSColor(calibratedWhite: 0.102, alpha: 1) : NSColor(red: 242/255, green: 245/255, blue: 249/255, alpha: 1)).setFill()
    bounds.fill()
    let title = text as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
    let size = title.size(withAttributes: attributes)
    title.draw(at: NSPoint(x: (bounds.width - size.width)/2, y: (bounds.height - size.height)/2), withAttributes: attributes)
  }
}

// Keep AppKit's real window buttons and add only a cursor rectangle.
final class ZhixuHandCursor: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func resetCursorRects() {
    super.resetCursorRects()
    guard !isHidden, let button = superview as? NSButton, button.isEnabled else { return }
    addCursorRect(bounds, cursor: .pointingHand)
  }
  static func install(on button: NSButton) {
    guard !button.subviews.contains(where: { $0 is ZhixuHandCursor }) else { return }
    let cursor = ZhixuHandCursor(frame: button.bounds)
    cursor.autoresizingMask = [.width, .height]
    button.addSubview(cursor)
    button.window?.invalidateCursorRects(for: cursor)
  }
}

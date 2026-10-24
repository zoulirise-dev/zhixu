import SwiftUI
import AppKit

struct CodeEditor: NSViewRepresentable {
    @Environment(\.isEnabled) private var enabled
    @Binding var text: String
    let documentID: String
    let openIDs: Set<String>
    let path: String
    let editable: Bool
    let diff: Bool
    let diffLines: [DiffLine]
    let baseline: String?
    @Binding var position: String
    func makeNSView(context: Context) -> EditorHost { EditorHost() }
    func updateNSView(_ host: EditorHost, context: Context) {
        let surface = host.show(documentID, validIDs: openIDs)
        host.interactionEnabled = enabled
        surface.onChange = { [weak host] value in if host?.activeID == documentID { text = value } }
        surface.onPosition = { [weak host] value in if host?.activeID == documentID { position = value } }
        surface.apply(text: text, language: SourceLanguage.detect(path), editable: editable && enabled, diffLines: diffLines, isDiff: diff, baseline: baseline)
    }
}
final class EditorHost: NSView {
    var interactionEnabled = true {
        didSet {
            guard oldValue != interactionEnabled else { return }
            minimap.interactionEnabled = interactionEnabled
            minimap.discardCursorRects(); window?.invalidateCursorRects(for: minimap)
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { interactionEnabled ? super.hitTest(point) : nil }

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.masksToBounds = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private let minimap = CodeMinimap()
    private var surfaces: [String: EditorSurface] = [:]
    private(set) var activeID: String?
    func show(_ id: String, validIDs: Set<String>) -> EditorSurface {
        for key in Array(surfaces.keys) where !validIDs.contains(key) { surfaces[key]?.removeFromSuperview(); surfaces.removeValue(forKey: key) }
        let surface = surfaces[id] ?? EditorSurface()
        surfaces[id] = surface
        if activeID != id {
            surfaces[activeID ?? ""]?.editor.dismissCompletion()
            subviews.forEach { $0.removeFromSuperview() }
            addSubview(surface); addSubview(minimap); activeID = id
            minimap.surface = surface
            surface.onScroll = { [weak self] in self?.minimap.needsDisplay = true }
            surface.editor.onHighlight = { [weak self] in self?.minimap.needsDisplay = true }
            needsLayout = true; layoutSubtreeIfNeeded()
        }
        return surface
    }
    override func layout() {
        super.layout()
        let width: CGFloat = bounds.width > 250 ? 84 : 36
        surfaces[activeID ?? ""]?.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - width), height: bounds.height)
        minimap.frame = NSRect(x: bounds.width - width, y: 0, width: width, height: bounds.height)
    }
}
final class EditorSurface: NSScrollView, NSTextViewDelegate, NSTextStorageDelegate {
    let editor: HighlightTextView
    private let numbers: LineNumberRuler
    var onChange: ((String) -> Void)?
    var onPosition: ((String) -> Void)?
    var onScroll: (() -> Void)?
    private var installing = false
    private var baseline: String?
    private var markerRevision = 0
    private var markerWork: DispatchWorkItem?
    private func updateMarkers() {
        markerRevision += 1; let revision = markerRevision
        markerWork?.cancel()
        guard let baseline else { numbers.changeMarkers = [:]; numbers.needsDisplay = true; return }
        let source = editor.string
        let work = DispatchWorkItem { [weak self] in
            let markers = LineChange.compare(base: baseline, current: source)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.markerRevision == revision else { return }
                self.numbers.changeMarkers = Dictionary(grouping: markers, by: \.line)
                self.numbers.needsDisplay = true
            }
        }
        markerWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    init() {
        editor = HighlightTextView(frame: .zero)
        numbers = LineNumberRuler()
        super.init(frame: .zero)
        drawsBackground = true; backgroundColor = AppTheme.panel
        hasVerticalScroller = false; hasHorizontalScroller = true; autohidesScrollers = true
        editor.isRichText = false; editor.importsGraphics = false; editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false; editor.isContinuousSpellCheckingEnabled = false; editor.isGrammarCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false; editor.isAutomaticLinkDetectionEnabled = false
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textColor = .labelColor
        editor.backgroundColor = AppTheme.panel; editor.insertionPointColor = .systemBlue
        editor.textContainerInset = NSSize(width: 10, height: 12)
        editor.minSize = .zero; editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = 20; paragraph.maximumLineHeight = 20
        paragraph.defaultTabInterval = 31.2; paragraph.tabStops = []
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: editor.font!, .foregroundColor: editor.textColor!, .paragraphStyle: paragraph]
        editor.delegate = self; editor.textStorage?.delegate = self; documentView = editor
        editor.onInputSettled = { [weak self] in self?.publishInput() }
        numbers.clientView = editor; numbers.scrollView = self
        verticalRulerView = numbers; hasVerticalRuler = true; rulersVisible = true
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: contentView)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func scrolled() { editor.dismissCompletion(); numbers.needsDisplay = true; onScroll?() }
    func apply(text: String, language: SourceLanguage, editable: Bool, diffLines: [DiffLine], isDiff: Bool, baseline: String?) {
        // SwiftUI can echo the last committed binding while AppKit is composing
        // marked text. Replacing the buffer here cancels the input method session.
        guard !editor.hasMarkedText(), !editor.handlingInput else { return }
        let baselineChanged = self.baseline != baseline
        self.baseline = baseline
        let modeChanged = numbers.isDiff != isDiff || numbers.diffLines != diffLines
        if modeChanged {
            numbers.diffLines = diffLines; numbers.isDiff = isDiff
            editor.diffLines = diffLines
            numbers.updateLines(text); editor.needsDisplay = true
        }
        let textChanged = editor.string != text
        editor.isEditable = editable
        if !editable { editor.dismissCompletion() }
        let languageChanged = editor.language != language
        editor.language = language
        if textChanged {
            installing = true
            let selected = editor.selectedRange()
            editor.string = text
            let length = (text as NSString).length
            if let paragraph = editor.defaultParagraphStyle {
                editor.textStorage?.addAttributes([.font: editor.font!, .paragraphStyle: paragraph], range: NSRange(location: 0, length: length))
            }
            editor.setSelectedRange(NSRange(location: min(selected.location, length), length: 0))
            editor.undoManager?.removeAllActions()
            installing = false
            numbers.updateLines(text); editor.highlight(); editor.completionTextChanged()
        } else if languageChanged { editor.highlight() }
        if numbers.lineStarts.isEmpty { numbers.updateLines(text) }
        if baselineChanged || textChanged { updateMarkers() }
    }
    func useSingleDiffColumn() {
        numbers.singleDiffColumn = true
        numbers.updateLines(editor.string)
    }
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard !installing, editedMask.contains(.editedCharacters) else { return }
        numbers.applyEdit(textStorage.string, range: editedRange, delta: delta)
    }
    func textDidChange(_ notification: Notification) { publishInput() }
    private func publishInput() {
        guard !installing, !editor.hasMarkedText(), !editor.handlingInput else { return }
        updateMarkers()
        onChange?(editor.string)
        editor.highlight(); editor.completionTextChanged()
        updatePosition()
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        numbers.needsDisplay = true; editor.needsDisplay = true
        guard !installing, !editor.hasMarkedText(), !editor.handlingInput else { return }
        updatePosition()
    }
    private func updatePosition() {
        let location = editor.selectedRange().location
        let line = numbers.lineIndex(at: location)
        let start = numbers.lineStarts.isEmpty ? 0 : numbers.lineStarts[line]
        onPosition?(L("行 {0}，列 {1}", [String(describing: line + 1), String(describing: location - start + 1)]))
    }
}
final class HighlightTextView: CompletionTextView {
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); highlight() }
    var diffLines: [DiffLine] = []
    var onHighlight: (() -> Void)?
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layout = layoutManager else { return }
        let length = (string as NSString).length
        var start = 0
        for (index, line) in diffLines.enumerated() {
            if line.kind != .context, CGFloat(index + 2) * 20 >= rect.minY, CGFloat(index - 1) * 20 <= rect.maxY {
                let fragment = start < length ? layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: start), effectiveRange: nil) : layout.extraLineFragmentRect
                let row = NSRect(x: visibleRect.minX, y: fragment.minY + textContainerOrigin.y, width: visibleRect.width, height: 20)
                if row.intersects(rect) {
                    (line.kind == .added ? NSColor.systemGreen : NSColor.systemRed).withAlphaComponent(0.14).setFill(); row.fill()
                }
            }
            start += (line.text as NSString).length + 1
        }
        if diffLines.isEmpty, isEditable {
            let location = min(selectedRange().location, length)
            let fragment = location < length ? layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: location), effectiveRange: nil) : layout.extraLineFragmentRect
            if !fragment.isEmpty {
                NSColor.labelColor.withAlphaComponent(0.035).setFill()
                NSRect(x: visibleRect.minX, y: fragment.minY + textContainerOrigin.y, width: visibleRect.width, height: 20).fill()
            }
        }
    }
    private var pending: DispatchWorkItem?
    private var revision = 0
    func highlight() {
        revision += 1; let version = revision
        pending?.cancel()
        let source = string, grammar = language
        let work = DispatchWorkItem { [weak self] in
            let tokens = SyntaxHighlighter.tokens(source, language: grammar)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.revision == version, !self.hasMarkedText(), let layout = self.layoutManager else { return }
                let all = NSRange(location: 0, length: (source as NSString).length)
                layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
                for token in tokens { layout.addTemporaryAttribute(.foregroundColor, value: token.kind.color, forCharacterRange: token.range) }
                self.onHighlight?()
                self.needsDisplay = true
            }
        }
        pending = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.10, execute: work)
    }
    override func insertTab(_ sender: Any?) { insertText("    ", replacementRange: selectedRange()) }
    override func insertNewline(_ sender: Any?) {
        dismissCompletion()
        guard assistanceEnabled, !hasMarkedText() else { super.insertNewline(sender); return }
        let source = string as NSString
        let selection = selectedRange()
        let range = source.lineRange(for: NSRange(location: min(selection.location, source.length), length: 0))
        let prefix = source.substring(with: NSRange(location: range.location, length: max(0, selection.location - range.location)))
        let indent = String(prefix.prefix { $0 == " " || $0 == "\t" })
        let last = prefix.trimmingCharacters(in: .whitespaces).last
        let closers: [Character: Character] = ["{": "}", "[": "]", "(": ")"]
        let deeper = last.map { closers[$0] != nil || (language == .python && $0 == ":") } ?? false
        let next = NSMaxRange(selection) < source.length ? source.substring(with: NSRange(location: NSMaxRange(selection), length: 1)) : ""
        let splitPair = selection.length == 0 && last.flatMap { closers[$0] }.map { String($0) == next } == true
        let insertion = "\n" + indent + (deeper ? "    " : "")
        insertText(insertion + (splitPair ? "\n" + indent : ""), replacementRange: selection)
        if splitPair { setSelectedRange(NSRange(location: selection.location + (insertion as NSString).length, length: 0)) }
    }
}
final class LineNumberRuler: NSRulerView {
    var lineStarts: [Int] = []
    var diffLines: [DiffLine] = []
    var isDiff = false
    var singleDiffColumn = false
    var changeMarkers: [Int: [LineChange]] = [:]
    init() { super.init(scrollView: nil, orientation: .verticalRuler); ruleThickness = 50 }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func updateLines(_ text: String) {
        lineStarts = [0]
        for (index, unit) in text.utf16.enumerated() where unit == 10 { lineStarts.append(index + 1) }
        ruleThickness = isDiff && !singleDiffColumn ? max(92, CGFloat(String(lineStarts.count).count) * 16 + 36) : max(50, CGFloat(String(lineStarts.count).count) * 8 + 24)
        needsDisplay = true
    }
    func applyEdit(_ text: String, range: NSRange, delta: Int) {
        let source = text as NSString
        let oldEnd = NSMaxRange(range) - delta
        guard oldEnd >= range.location, NSMaxRange(range) <= source.length, !lineStarts.isEmpty else { updateLines(text); return }
        let before = lineStarts.filter { $0 <= range.location }
        let after = lineStarts.filter { $0 > oldEnd }.map { $0 + delta }
        var added: [Int] = []
        for offset in range.location..<NSMaxRange(range) where source.character(at: offset) == 10 { added.append(offset + 1) }
        lineStarts = before + added + after
        ruleThickness = isDiff && !singleDiffColumn ? max(92, CGFloat(String(lineStarts.count).count) * 16 + 36) : max(50, CGFloat(String(lineStarts.count).count) * 8 + 24)
        needsDisplay = true
    }
    func lineIndex(at location: Int) -> Int {
        guard !lineStarts.isEmpty else { return 0 }
        var low = 0, high = lineStarts.count
        while low < high { let mid = (low + high) / 2; if lineStarts[mid] <= location { low = mid + 1 } else { high = mid } }
        return max(0, low - 1)
    }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        AppTheme.subtle.setFill(); bounds.fill()
        guard let view = clientView as? NSTextView, let layout = view.layoutManager, let container = view.textContainer else { return }
        let length = (view.string as NSString).length
        var visible = view.visibleRect; visible.origin.y = max(0, visible.origin.y - view.textContainerInset.height)
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let first = lineIndex(at: chars.location)
        let last = min(lineStarts.count - 1, lineIndex(at: NSMaxRange(chars)) + 1)
        guard first <= last else { return }
        let activeLine = lineIndex(at: view.selectedRange().location)
        for index in first...last {
            let start = lineStarts[index]
            let fragment: NSRect
            if start >= length { fragment = layout.extraLineFragmentRect }
            else { fragment = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: start), effectiveRange: nil) }
            let point = convert(NSPoint(x: 0, y: fragment.minY + view.textContainerInset.height), from: view)
            if isDiff {
                guard index < diffLines.count else { continue }
                let line = diffLines[index]
                let color: NSColor = line.kind == .added ? .systemGreen : line.kind == .removed ? .systemRed : .tertiaryLabelColor
                if line.kind != .context {
                    color.withAlphaComponent(0.12).setFill()
                    NSRect(x: 0, y: point.y, width: ruleThickness, height: 20).fill()
                }
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: color]
                let columns: [(Int?, CGFloat)] = singleDiffColumn
                    ? [(line.kind == .added ? line.new : line.old ?? line.new, ruleThickness - 20)]
                    : [(line.old, ruleThickness / 2 - 12), (line.new, ruleThickness - 20)]
                for (value, edge) in columns {
                    if let value { let label = String(value) as NSString; label.draw(at: NSPoint(x: edge - label.size(withAttributes: attrs).width, y: point.y + 2), withAttributes: attrs) }
                }
                let marker = (line.kind == .added ? "+" : line.kind == .removed ? "−" : "") as NSString
                marker.draw(at: NSPoint(x: ruleThickness - 13, y: point.y + 2), withAttributes: attrs)
                continue
            }
            for marker in changeMarkers[index] ?? [] {
                let color: NSColor = marker.kind == .added ? .systemGreen : marker.kind == .modified ? .systemBlue : .systemRed
                color.setFill()
                if marker.kind == .deleted {
                    let y = point.y + (marker.afterLine ? 20 : 0)
                    let triangle = NSBezierPath()
                    triangle.move(to: NSPoint(x: ruleThickness - 7, y: y - 4))
                    triangle.line(to: NSPoint(x: ruleThickness - 1, y: y))
                    triangle.line(to: NSPoint(x: ruleThickness - 7, y: y + 4))
                    triangle.close(); triangle.fill()
                } else { NSRect(x: ruleThickness - 5, y: point.y, width: 3, height: 20).fill() }
            }
            let number = String(index + 1) as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: index == activeLine ? NSColor.labelColor : NSColor.tertiaryLabelColor]
            let size = number.size(withAttributes: attrs)
            number.draw(at: NSPoint(x: ruleThickness - size.width - 13, y: point.y + 2), withAttributes: attrs)
        }
    }
}
extension SyntaxKind {
    var color: NSColor { AppTheme.adaptive(lightColor, darkColor) }
    private var darkColor: NSColor {
        switch self {
        case .comment: return NSColor(red: 0.52, green: 0.66, blue: 0.48, alpha: 1)
        case .string: return NSColor(red: 0.90, green: 0.65, blue: 0.48, alpha: 1)
        case .keyword, .heading: return NSColor(red: 0.80, green: 0.60, blue: 0.94, alpha: 1)
        case .number: return .systemMint
        case .type: return .systemTeal
        case .function: return NSColor(red: 0.90, green: 0.82, blue: 0.55, alpha: 1)
        case .property, .tag: return NSColor(red: 0.48, green: 0.74, blue: 0.95, alpha: 1)
        case .insertion: return .systemGreen
        case .deletion: return .systemRed
        }
    }
    private var lightColor: NSColor {
        switch self {
        case .comment: return NSColor(red: 0.38, green: 0.49, blue: 0.39, alpha: 1)
        case .string: return NSColor(red: 0.65, green: 0.25, blue: 0.16, alpha: 1)
        case .keyword, .heading: return NSColor(red: 0.48, green: 0.22, blue: 0.68, alpha: 1)
        case .number: return NSColor(red: 0.08, green: 0.48, blue: 0.37, alpha: 1)
        case .type: return NSColor(red: 0.10, green: 0.46, blue: 0.50, alpha: 1)
        case .function: return NSColor(red: 0.48, green: 0.38, blue: 0.12, alpha: 1)
        case .property, .tag: return NSColor(red: 0.10, green: 0.36, blue: 0.66, alpha: 1)
        case .insertion: return .systemGreen
        case .deletion: return .systemRed
        }
    }
}

/// A scaled rendering of the actual text layout, sharing syntax colors with the editor.
final class CodeMinimap: NSView {
    var interactionEnabled = true
    weak var surface: EditorSurface?
    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = L("代码缩略图 · 点击定位，拖动滚动")
        setAccessibilityLabel(L("代码缩略图"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isFlipped: Bool { true }
    private let scale: CGFloat = 0.13
    private var dragOffset: CGFloat = 0
    private var geometry: (height: CGFloat, offset: CGFloat, thumb: NSRect) {
        guard let surface else { return (0, 0, .zero) }
        let total = max(surface.editor.bounds.height, surface.contentView.bounds.height)
        let viewport = surface.contentView.bounds.height
        let scroll = surface.contentView.bounds.minY
        let miniature = total * scale
        let ratio = scroll / max(1, total - viewport)
        let offset = max(0, miniature - bounds.height) * ratio
        let thumb = NSRect(x: 0, y: scroll * scale - offset, width: bounds.width, height: min(bounds.height, viewport * scale))
        return (total, offset, thumb)
    }
    override func draw(_ dirtyRect: NSRect) {
        AppTheme.panel.setFill(); bounds.fill()
        guard let surface, let layout = surface.editor.layoutManager, let container = surface.editor.textContainer,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let g = geometry
        context.saveGState(); context.clip(to: bounds)
        context.translateBy(x: 5, y: -g.offset)
        context.scaleBy(x: scale, y: scale)
        let rect = NSRect(x: 0, y: g.offset / scale, width: (bounds.width - 5) / scale, height: bounds.height / scale)
        let glyphs = layout.glyphRange(forBoundingRect: rect, in: container)
        layout.drawGlyphs(forGlyphRange: glyphs, at: surface.editor.textContainerOrigin)
        context.restoreGState()
        for (index, line) in surface.editor.diffLines.enumerated() where line.kind != .context {
            (line.kind == .added ? NSColor.systemGreen : NSColor.systemRed).withAlphaComponent(0.65).setFill()
            NSRect(x: bounds.width - 3, y: (CGFloat(index) * 20 + surface.editor.textContainerOrigin.y) * scale - g.offset, width: 3, height: 20 * scale).fill()
        }
        NSColor.labelColor.withAlphaComponent(0.07).setFill(); g.thumb.fill()
        NSColor.labelColor.withAlphaComponent(0.16).setStroke()
        NSBezierPath(rect: g.thumb.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let thumb = geometry.thumb
        dragOffset = thumb.contains(point) ? point.y - thumb.minY : thumb.height / 2
        navigate(point.y)
    }
    override func mouseDragged(with event: NSEvent) { navigate(convert(event.locationInWindow, from: nil).y) }
    private func navigate(_ y: CGFloat) {
        guard let surface else { return }
        let g = geometry
        let maximum = max(0, g.height - surface.contentView.bounds.height)
        let travel = max(1, min(bounds.height, g.height * scale) - g.thumb.height)
        let destination = min(maximum, max(0, (y - dragOffset) / travel * maximum))
        surface.contentView.scroll(to: NSPoint(x: surface.contentView.bounds.minX, y: destination))
        surface.reflectScrolledClipView(surface.contentView); needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) { surface?.scrollWheel(with: event) }
    override func resetCursorRects() { if interactionEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
}

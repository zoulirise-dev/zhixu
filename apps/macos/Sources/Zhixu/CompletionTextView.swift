import SwiftUI
import AppKit

private struct CompletionMenu: View {
    let items: [CodeSuggestion]
    let selected: Int
    let choose: (Int) -> Void
    var body: some View {
        VStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                Button { choose(index) } label: {
                    HStack {
                        Image(systemName: items[index].snippet ? "curlybraces" : "textformat.abc").foregroundStyle(.secondary).frame(width: 20)
                        Text(items[index].title).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                        Spacer()
                        if index == selected { Text("⇥").foregroundStyle(.secondary) }
                    }.padding(.horizontal, 8).frame(height: 27)
                        .background(index == selected ? Color.blue.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(CursorPlainButtonStyle())
            }
        }.padding(5).background(Color(nsColor: AppTheme.panel), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.15)))
    }
}

class CompletionTextView: NSTextView {
    var language = SourceLanguage.plain
    private var inputDepth = 0
    var handlingInput: Bool { inputDepth > 0 }
    var onInputSettled: (() -> Void)?
    private func finishInput() {
        inputDepth -= 1
        if inputDepth == 0 { onInputSettled?() }
    }
    var assistanceEnabled: Bool { UserDefaults.standard.object(forKey: "editorCompletion") as? Bool ?? true }
    private var words: [String] = []
    private var indexWork: DispatchWorkItem?
    private var indexRevision = 0
    private var suggestionWork: DispatchWorkItem?
    private var suggestions: [CodeSuggestion] = []
    private var suggestionRange = NSRange(location: 0, length: 0)
    private var selectedSuggestion = 0
    private var completionPanel: NSPanel?
    private var completing = false
    var hasSuggestions: Bool { !suggestions.isEmpty }
    func dismissCompletion() {
        suggestionWork?.cancel()
        suggestions = []
        if let panel = completionPanel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        completionPanel = nil
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        dismissCompletion()
        super.viewWillMove(toWindow: newWindow)
    }
    override func resignFirstResponder() -> Bool { dismissCompletion(); return super.resignFirstResponder() }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        dismissCompletion()
        inputDepth += 1; defer { finishInput() }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
    override func unmarkText() {
        inputDepth += 1; defer { finishInput() }
        super.unmarkText()
    }
    override func mouseDown(with event: NSEvent) { dismissCompletion(); super.mouseDown(with: event) }
    override func keyDown(with event: NSEvent) {
        if hasMarkedText() { dismissCompletion(); super.keyDown(with: event); return }
        if hasSuggestions {
            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                dismissCompletion(); super.keyDown(with: event); return
            }
            switch event.keyCode {
            case 53: dismissCompletion(); return
            case 125: selectedSuggestion = (selectedSuggestion + 1) % suggestions.count; showCompletion(); return
            case 126: selectedSuggestion = (selectedSuggestion + suggestions.count - 1) % suggestions.count; showCompletion(); return
            case 48, 36: acceptCompletion(selectedSuggestion); return
            case 123, 124: dismissCompletion()
            default: if event.modifierFlags.contains(.command) { dismissCompletion() }
            }
        }
        super.keyDown(with: event)
    }
    func completionTextChanged() {
        indexRevision += 1; let version = indexRevision
        indexWork?.cancel()
        guard assistanceEnabled, isEditable else { words = []; dismissCompletion(); return }
        let source = string
        let work = DispatchWorkItem { [weak self] in
            let result = CodeCompletion.words(source)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.indexRevision == version else { return }
                self.words = result
            }
        }
        indexWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    private func scheduleSuggestions() {
        dismissCompletion()
        guard assistanceEnabled, isEditable, !hasMarkedText(), !completing else { return }
        let selection = selectedRange()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isEditable, self.assistanceEnabled, !self.hasMarkedText(), self.window?.firstResponder === self,
                  self.selectedRange() == selection, let range = CodeCompletion.prefix(self.string, selection: selection) else { return }
            let text = self.string as NSString
            self.suggestionRange = range
            self.suggestions = CodeCompletion.candidates(prefix: text.substring(with: range), language: self.language, words: self.words)
            self.selectedSuggestion = 0
            if self.hasSuggestions { self.showCompletion() }
        }
        suggestionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    private func showCompletion() {
        guard let window, !suggestions.isEmpty else { dismissCompletion(); return }
        let panel = completionPanel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = true; panel.isReleasedWhenClosed = false
        let height = CGFloat(suggestions.count) * 29 + 8, width: CGFloat = 300
        panel.contentView = NSHostingView(rootView: CompletionMenu(items: suggestions, selected: selectedSuggestion) { [weak self] index in self?.acceptCompletion(index) })
        let caret = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        let screen = window.screen?.visibleFrame ?? window.frame
        let x = max(screen.minX, min(caret.minX, screen.maxX - width))
        let y = caret.minY - height >= screen.minY ? caret.minY - height : min(caret.maxY, screen.maxY - height)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil); completionPanel = panel
    }
    private func acceptCompletion(_ index: Int) {
        guard isEditable, assistanceEnabled, !hasMarkedText(), suggestions.indices.contains(index),
              selectedRange().location == NSMaxRange(suggestionRange), selectedRange().length == 0 else { dismissCompletion(); return }
        let source = string as NSString
        let line = source.lineRange(for: NSRange(location: suggestionRange.location, length: 0))
        let leading = source.substring(with: NSRange(location: line.location, length: suggestionRange.location - line.location))
        let indent = String(leading.prefix { $0 == " " || $0 == "\t" })
        var item = suggestions[index]
        if language == .html, item.snippet, suggestionRange.location > 0, source.character(at: suggestionRange.location - 1) == 60 {
            item = CodeSuggestion(title: item.title, text: String(item.text.dropFirst()))
        }
        let insertion = CodeCompletion.insertion(item, indent: indent), range = suggestionRange
        dismissCompletion(); completing = true
        breakUndoCoalescing()
        super.insertText(insertion.text, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + insertion.cursor, length: 0))
        breakUndoCoalescing()
        completing = false
    }
    override func insertText(_ value: Any, replacementRange: NSRange) {
        guard isEditable else { return }
        inputDepth += 1; defer { finishInput() }
        let typed = (value as? String) ?? (value as? NSAttributedString)?.string ?? ""
        let marked = hasMarkedText()
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        let source = string as NSString
        if assistanceEnabled, !marked, !completing, typed.count == 1, NSMaxRange(range) <= source.length {
            let pairs = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
            if let close = pairs[typed] {
                let quote = ["\"", "'", "`"].contains(typed)
                let previous = range.location > 0 ? source.substring(with: NSRange(location: range.location - 1, length: 1)) : ""
                let next = NSMaxRange(range) < source.length ? source.substring(with: NSRange(location: NSMaxRange(range), length: 1)) : ""
                if quote && range.length == 0 && next == typed && previous != "\\" {
                    dismissCompletion(); setSelectedRange(NSRange(location: range.location + 1, length: 0)); return
                }
                let quoteAllowed = !quote || (language != .plain && language != .markdown && previous != "\\" && previous.rangeOfCharacter(from: .alphanumerics) == nil)
                if quoteAllowed && (range.length > 0 || next.isEmpty || next.rangeOfCharacter(from: .whitespacesAndNewlines) != nil || [")", "]", "}", ";", ","].contains(next)) {
                    let selected = source.substring(with: range)
                    dismissCompletion(); super.insertText(typed + selected + close, replacementRange: range)
                    setSelectedRange(NSRange(location: range.location + (typed as NSString).length, length: range.length)); return
                }
            } else if [")", "]", "}"].contains(typed), range.length == 0, range.location < source.length, source.substring(with: NSRange(location: range.location, length: 1)) == typed {
                dismissCompletion(); setSelectedRange(NSRange(location: range.location + 1, length: 0)); return
            }
        }
        super.insertText(value, replacementRange: replacementRange)
        if !marked && typed.count == 1 { scheduleSuggestions() } else { dismissCompletion() }
    }
    override func paste(_ sender: Any?) {
        dismissCompletion(); completing = true
        super.paste(sender)
        completing = false
    }
    override func deleteBackward(_ sender: Any?) {
        dismissCompletion()
        let range = selectedRange(), source = string as NSString
        if assistanceEnabled, isEditable, !hasMarkedText(), range.length == 0, range.location > 0, range.location < source.length {
            let pair = source.substring(with: NSRange(location: range.location - 1, length: 2))
            if ["()", "[]", "{}", "\"\"", "''", "``"].contains(pair) {
                super.insertText("", replacementRange: NSRange(location: range.location - 1, length: 2)); return
            }
        }
        super.deleteBackward(sender)
    }
}

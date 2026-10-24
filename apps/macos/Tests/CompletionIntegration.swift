import Foundation
import AppKit

@main struct CompletionIntegration {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let old = UserDefaults.standard.object(forKey: "editorCompletion")
        UserDefaults.standard.set(true, forKey: "editorCompletion")
        defer { if let old { UserDefaults.standard.set(old, forKey: "editorCompletion") } else { UserDefaults.standard.removeObject(forKey: "editorCompletion") } }
        func check(_ condition: Bool, _ title: String) throws { guard condition else { throw GitFailure.message(title) }; print("PASS: " + title) }
        let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 600, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Zhixu Editor Tests"; window.isReleasedWhenClosed = false
        let surface = EditorSurface(); surface.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        window.contentView = surface
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        defer { surface.editor.dismissCompletion(); window.close() }
        let editor = surface.editor
        func load(_ text: String, language: SourceLanguage = .javascript, editable: Bool = true) {
            surface.apply(text: text, language: language, editable: editable, diffLines: [], isDiff: !editable, baseline: nil)
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0)); window.makeFirstResponder(editor)
        }
        func type(_ text: String) { editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0)) }
        load(""); type("(")
        try check(editor.string == "()" && editor.selectedRange().location == 1, "pair parentheses")
        type(")"); try check(editor.string == "()" && editor.selectedRange().location == 2, "skip existing closing bracket")
        load(""); type("["); editor.deleteBackward(nil)
        try check(editor.string.isEmpty, "paired deletion")
        load("hello"); editor.setSelectedRange(NSRange(location: 0, length: 5)); type("\"")
        try check(editor.string == "\"hello\"" && editor.selectedRange() == NSRange(location: 1, length: 5), "wrap selected text")
        load("{}"); editor.setSelectedRange(NSRange(location: 1, length: 0)); editor.insertNewline(nil)
        try check(editor.string == "{\n    \n}" && editor.selectedRange().location == 6, "newline expands paired braces with indentation")
        load("if ready:", language: .python); editor.insertNewline(nil)
        try check(editor.string == "if ready:\n    ", "Python indentation")
        load("don't", language: .markdown); type("'")
        try check(editor.string == "don't'", "prose does not pair apostrophes")
        load("readonly", editable: false); type("(")
        try check(editor.string == "readonly", "read-only editor cannot be changed by pairing")
        load(""); type("paste (not paired)")
        try check(editor.string == "paste (not paired)", "paste stays literal")
        load(""); editor.setMarkedText("中", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try check(editor.hasMarkedText() && !editor.hasSuggestions, "IME marked text suppresses suggestions")
        type("中文"); editor.unmarkText()
        try check(editor.string == "中文", "IME commit remains intact")
        load("// ")
        var committed = editor.string
        surface.onChange = { committed = $0 }
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try check(committed == "// ", "marked Pinyin does not overwrite committed binding")
        surface.apply(text: committed, language: .javascript, editable: true, diffLines: [], isDiff: false, baseline: nil)
        try check(editor.hasMarkedText() && editor.string == "// zhong", "SwiftUI stale binding preserves IME session")
        editor.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        surface.apply(text: committed, language: .javascript, editable: true, diffLines: [], isDiff: false, baseline: nil)
        try check(editor.hasMarkedText() && editor.string == "// zhongwen", "continued Pinyin composition survives view refresh")
        let candidateRect = editor.firstRect(forCharacterRange: editor.markedRange(), actualRange: nil)
        try check(candidateRect.height > 0 && candidateRect.minX.isFinite, "IME candidate anchor remains available")
        type("中文")
        try check(!editor.hasMarkedText() && editor.string == "// 中文" && committed == "// 中文", "confirmed Chinese updates binding once composition ends")
        editor.setMarkedText("ceshi", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        surface.apply(text: committed, language: .javascript, editable: true, diffLines: [], isDiff: false, baseline: nil)
        type("测试")
        try check(committed == "// 中文测试", "consecutive Chinese phrases commit normally")
        surface.onChange = nil
        UserDefaults.standard.set(false, forKey: "editorCompletion")
        load(""); type("{"); try check(editor.string == "{", "settings disables pairing")
        UserDefaults.standard.set(true, forKey: "editorCompletion")
        load(""); type("f"); type("u")
        try await Task.sleep(nanoseconds: 350_000_000)
        try check(editor.hasSuggestions, "typing opens completion list")
        if let view = window.childWindows?.first?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/.build/completion-menu.png"))
        }
        let tab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
        editor.keyDown(with: tab)
        try check(editor.string.contains("function name(") && !editor.string.contains("${cursor}"), "Tab accepts snippet and removes cursor marker")
        editor.undoManager?.undo()
        try check(editor.string == "fu", "completion can be undone as one insertion")
        let ruler = LineNumberRuler()
        var text = "👋one\ntwo\n三\n"; ruler.updateLines(text)
        var seed: UInt64 = 42
        for _ in 0..<300 {
            seed = seed &* 6364136223846793005 &+ 1
            let source = text as NSString
            // ASCII tail avoids splitting Unicode surrogate pairs.
            let start = 2 + Int(seed % UInt64(max(1, source.length - 1)))
            let length = min(Int((seed >> 8) % 3), source.length - start)
            let insert = ["x", "\n", "a\nb", "", "中文"][Int((seed >> 16) % 5)]
            text = source.replacingCharacters(in: NSRange(location: start, length: length), with: insert)
            ruler.applyEdit(text, range: NSRange(location: start, length: (insert as NSString).length), delta: (insert as NSString).length - length)
            let reference = LineNumberRuler(); reference.updateLines(text)
            try check(ruler.lineStarts == reference.lineStarts, "incremental line offsets")
        }
        for language in [SourceLanguage.java, .php, .html, .css, .json, .markdown, .javascript, .typescript, .python, .swift] {
            try check(!CodeCompletion.vocabulary(language).isEmpty || !CodeCompletion.templates(language).isEmpty, "language data: " + language.rawValue)
        }
        let large = String(repeating: "const repeatedVariable = otherVariable;\n", count: 5000)
        let start = Date(); let words = CodeCompletion.words(large); let elapsed = Date().timeIntervalSince(start)
        try check(words.contains("repeatedVariable"), "background word index")
        let matching = Date()
        for _ in 0..<1000 { _ = CodeCompletion.candidates(prefix: "re", language: .javascript, words: words) }
        print("BENCH: word index \(Int(elapsed * 1000))ms; 1000 candidate lookups \(Int(Date().timeIntervalSince(matching) * 1000))ms")
        try check(CodeCompletion.words(String(repeating: "a", count: 300_000)).isEmpty, "large file indexing limit")
        print("PASS: editor assistance suite complete")
    }
}

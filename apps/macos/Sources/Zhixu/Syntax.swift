import Foundation

enum SourceLanguage: String {
    case java = "Java", php = "PHP", html = "HTML", css = "CSS", json = "JSON", markdown = "Markdown"
    case javascript = "JavaScript", typescript = "TypeScript", swift = "Swift", python = "Python"
    case yaml = "YAML", sql = "SQL", shell = "Shell", c = "C / C++", rust = "Rust", go = "Go", plain = "Plain Text", diff = "Diff"
    static func detect(_ path: String) -> SourceLanguage {
        switch (path as NSString).pathExtension.lowercased() {
        case "java", "kt", "kts": return .java
        case "php", "phtml": return .php
        case "html", "htm", "xml", "svg", "vue", "svelte": return .html
        case "css", "scss", "sass", "less": return .css
        case "json", "jsonc": return .json
        case "md", "markdown", "mdx": return .markdown
        case "js", "jsx", "mjs", "cjs": return .javascript
        case "ts", "tsx": return .typescript
        case "swift": return .swift
        case "py": return .python
        case "yaml", "yml", "toml", "ini", "env": return .yaml
        case "sql": return .sql
        case "sh", "bash", "zsh": return .shell
        case "c", "h", "cpp", "hpp", "cs": return .c
        case "rs": return .rust
        case "go": return .go
        default: return .plain
        }
    }
}
enum SyntaxKind: String { case comment, string, keyword, number, type, function, property, tag, heading, insertion, deletion }
struct SyntaxToken { let range: NSRange; let kind: SyntaxKind }
enum SyntaxHighlighter {
    private static let keywords = "abstract|assert|async|await|as|break|case|catch|class|const|continue|debugger|default|defer|delete|do|else|enum|export|extends|false|final|finally|for|from|func|function|guard|if|implements|import|in|instanceof|interface|internal|is|let|new|nil|null|of|open|override|package|private|protected|public|readonly|record|return|self|static|struct|super|switch|synchronized|this|throw|throws|true|try|type|typeof|var|void|while|yield|def|elif|except|lambda|None|True|False|not|and|or|pass|with|raise|print|echo|namespace|use|include|require|require_once|include_once|foreach|endforeach|endif|isset|empty|fn|pub|impl|match|mut|trait|where|unsafe|mod|crate|go|range|select|chan|map|select|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|GROUP|BY|ORDER|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|AS|AND|OR|NOT|NULL|IS|DISTINCT|UNION"
    private static func rules(_ language: SourceLanguage) -> [(SyntaxKind, String)] {
        let strings = #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#
        if language == .plain { return [] }
        if language == .diff { return [(.insertion, #"(?m)^\+.*$"#), (.deletion, #"(?m)^-.*$"#), (.keyword, #"(?m)^@@.*$"#), (.comment, #"(?m)^(?:diff |index ).*$"#)] }
        if language == .markdown {
            return [(.string, #"(?ms)^```[^\n]*\n.*?^```[^\n]*|`[^`\n]+`"#), (.heading, #"(?m)^#{1,6}\s+.*$"#), (.comment, #"<!--[\s\S]*?-->"#), (.string, #"\[[^\]\n]+\]\([^\)\n]+\)"#), (.keyword, #"\*\*[^*\n]+\*\*|__[^_\n]+__|(?m)^\s*[-*>]\s"#)]
        }
        if language == .html { return [(.comment, #"<!--[\s\S]*?-->"#), (.string, strings), (.tag, #"</?[A-Za-z][\w:.-]*|/?>"#), (.property, #"[\w:-]+(?=\s*=)"#)] }
        if language == .json { return [(.comment, #"//[^\n]*|/\*[\s\S]*?\*/"#), (.property, #""(?:\\.|[^"\\])*"(?=\s*:)"#), (.string, strings), (.keyword, #"\b(?:true|false|null)\b"#), (.number, #"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#)] }
        var result: [(SyntaxKind, String)] = []
        if language == .python { result.append((.string, #"\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?'''"#)) }
        let comment: String
        switch language {
        case .python, .shell, .yaml: comment = #"(?m)#[^\n]*"#
        case .sql: comment = #"--[^\n]*|/\*[\s\S]*?\*/"#
        case .css: comment = #"/\*[\s\S]*?\*/"#
        case .php: comment = #"//[^\n]*|#[^\n]*|/\*[\s\S]*?\*/"#
        default: comment = #"//[^\n]*|/\*[\s\S]*?\*/"#
        }
        result += [(.comment, comment), (.string, strings)]
        if language == .css { result += [(.number, #"#[0-9a-fA-F]{3,8}\b|\b\d+(?:\.\d+)?(?:px|em|rem|vh|vw|s|ms|%)?"#), (.property, #"[\w-]+(?=\s*:)"#), (.tag, #"[.#][a-zA-Z_][\w-]*|@[\w-]+"#)] }
        if language == .yaml { result.append((.property, #"(?m)^\s*[\w.-]+(?=\s*[:=])"#)) }
        result += [(.keyword, "\\b(?:" + keywords + ")\\b"), (.number, #"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#), (.type, #"\b(?:String|Int|Integer|Boolean|Double|Float|Array|List|Map|Set|Optional|Object|bool|boolean|int|long|float|double|char|byte|short|[A-Z][A-Za-z0-9_]+)\b"#), (.function, #"\b[a-zA-Z_][\w]*(?=\s*\()"#)]
        if language == .php || language == .shell { result.append((.property, #"\$[a-zA-Z_][\w]*"#)) }
        return result
    }
    private struct Grammar { let expression: NSRegularExpression; let kinds: [SyntaxKind] }
    private static let grammars: [SourceLanguage: Grammar] = {
        let languages: [SourceLanguage] = [.java,.php,.html,.css,.json,.markdown,.javascript,.typescript,.swift,.python,.yaml,.sql,.shell,.c,.rust,.go,.plain,.diff]
        return Dictionary(uniqueKeysWithValues: languages.compactMap { language in
            let rules = rules(language)
            guard !rules.isEmpty else { return nil }
            let pattern = rules.enumerated().map { "(?<t\($0.offset)>\($0.element.1))" }.joined(separator: "|")
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (language, Grammar(expression: regex, kinds: rules.map(\.0)))
        })
    }()
    static func tokens(_ text: String, language: SourceLanguage) -> [SyntaxToken] {
        guard let grammar = grammars[language] else { return [] }
        let whole = NSRange(location: 0, length: (text as NSString).length)
        var result = grammar.expression.matches(in: text, range: whole).compactMap { match -> SyntaxToken? in
            for (index, kind) in grammar.kinds.enumerated() {
                let range = match.range(withName: "t\(index)")
                if range.location != NSNotFound { return SyntaxToken(range: range, kind: kind) }
            }
            return nil
        }
        if language == .html || language == .php {
            if language == .php { result = tokens(text, language: .html) }
            let embedded: [(String, SourceLanguage)] = language == .html
                ? [(#"(?is)<script\b[^>]*>(.*?)</script\s*>"#, .javascript), (#"(?is)<style\b[^>]*>(.*?)</style\s*>"#, .css)]
                : [(#"(?is)<\?(?:php|=)?(.*?)(?:\?>|\z)"#, .plain)]
            for (pattern, embeddedLanguage) in embedded {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                for match in regex.matches(in: text, range: whole) {
                    let range = match.range(at: 1), source = (text as NSString).substring(with: range)
                    result.removeAll { NSIntersectionRange($0.range, range).length > 0 }
                    let nested: [SyntaxToken]
                    if language == .php, let php = grammars[.php] {
                        nested = php.expression.matches(in: source, range: NSRange(location: 0, length: (source as NSString).length)).compactMap { match in
                            for (index, kind) in php.kinds.enumerated() { let r = match.range(withName: "t\(index)"); if r.location != NSNotFound { return SyntaxToken(range: r, kind: kind) } }; return nil
                        }
                    } else { nested = tokens(source, language: embeddedLanguage) }
                    result += nested.map { SyntaxToken(range: NSRange(location: range.location + $0.range.location, length: $0.range.length), kind: $0.kind) }
                }
            }
        }
        return result
    }
}

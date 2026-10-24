import Foundation

struct CodeSuggestion: Equatable {
    let title: String
    let text: String
    var snippet: Bool { text.contains("${cursor}") }
}
enum CodeCompletion {
    static let wordPattern = try! NSRegularExpression(pattern: #"[A-Za-z_$][A-Za-z0-9_$]{2,63}"#)
    static func words(_ source: String) -> [String] {
        let text = source as NSString
        // Large/minified documents keep language completion but skip file indexing.
        guard text.length <= 250_000 else { return [] }
        var words = Set<String>()
        wordPattern.enumerateMatches(in: source, range: NSRange(location: 0, length: text.length)) { match, _, stop in
            if let match { words.insert(text.substring(with: match.range)) }
            if words.count >= 3000 { stop.pointee = true }
        }
        return words.sorted()
    }
    static func prefix(_ source: String, selection: NSRange) -> NSRange? {
        let text = source as NSString
        guard selection.length == 0, selection.location <= text.length else { return nil }
        var start = selection.location
        while start > 0 && selection.location - start < 64 {
            let c = text.character(at: start - 1)
            if !(c >= 65 && c <= 90 || c >= 97 && c <= 122 || c >= 48 && c <= 57 || c == 95 || c == 36 || c == 45) { break }
            start -= 1
        }
        guard selection.location - start >= 2 else { return nil }
        return NSRange(location: start, length: selection.location - start)
    }
    static func candidates(prefix: String, language: SourceLanguage, words: [String]) -> [CodeSuggestion] {
        let key = prefix.lowercased()
        var seen = Set<String>()
        let snippets = templates(language).map { CodeSuggestion(title: $0.0, text: $0.1) }
        let keywords = vocabulary(language).split(separator: " ").map { CodeSuggestion(title: String($0), text: String($0)) }
        return Array((snippets + keywords + words.map { CodeSuggestion(title: $0, text: $0) }).filter {
            $0.title.lowercased().hasPrefix(key) && ($0.text != prefix) && seen.insert($0.title).inserted
        }.prefix(8))
    }
    static func insertion(_ item: CodeSuggestion, indent: String) -> (text: String, cursor: Int) {
        let text = item.text.replacingOccurrences(of: "\n", with: "\n" + indent)
        let range = (text as NSString).range(of: "${cursor}")
        return (text.replacingOccurrences(of: "${cursor}", with: ""), range.location == NSNotFound ? (text as NSString).length : range.location)
    }
    static func vocabulary(_ language: SourceLanguage) -> String {
        switch language {
        case .java: return "public private protected static final abstract class interface extends implements package import return new this super void int long boolean String List Map if else for while switch try catch finally throw throws null true false"
        case .php: return "function public private protected static class interface namespace use require require_once include include_once return echo foreach array isset empty count null true false if else elseif while try catch throw new"
        case .html: return "div span main section article header footer nav button input label form textarea select option ul li table tr td img link script style class id href src type placeholder disabled"
        case .css: return "display position width height margin padding color background background-color font-size font-weight border border-radius flex grid gap align-items justify-content overflow opacity transform transition relative absolute none block"
        case .json: return "true false null"
        case .markdown: return ""
        case .javascript, .typescript: return "const let var function return async await class extends import export default from new this null undefined true false if else for while switch try catch finally throw console document window interface type readonly implements"
        case .swift: return "let var func struct class enum protocol extension public private static return guard if else for in switch case import async await throws try self nil true false"
        case .python: return "def class import from return if elif else for while in with as try except finally raise pass break continue lambda True False None async await print"
        case .yaml: return "true false null"
        case .sql: return "SELECT FROM WHERE JOIN LEFT RIGHT INNER ON GROUP BY ORDER LIMIT INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE ALTER DROP DISTINCT NULL"
        case .shell: return "if then else elif fi for do done while case esac function echo export source return exit"
        case .c: return "int char void bool float double class struct public private return include static const if else for while switch case break null nullptr"
        case .rust: return "fn let mut pub struct enum impl trait use mod crate match if else for while return async await self Self Option Result"
        case .go: return "func package import type struct interface var const return if else for range switch case defer go chan map nil"
        case .plain, .diff: return ""
        }
    }
    static func templates(_ language: SourceLanguage) -> [(String, String)] {
        switch language {
        case .java: return [("main", "public static void main(String[] args) {\n    ${cursor}\n}"), ("sout", "System.out.println(${cursor});"), ("if", "if (${cursor}) {\n    \n}")]
        case .php: return [("function", "function name(${cursor}) {\n    \n}"), ("foreach", "foreach (${cursor} as $item) {\n    \n}")]
        case .javascript, .typescript: return [("function", "function name(${cursor}) {\n    \n}"), ("log", "console.log(${cursor});"), ("if", "if (${cursor}) {\n    \n}")]
        case .html: return [("div", "<div>${cursor}</div>"), ("span", "<span>${cursor}</span>"), ("button", "<button>${cursor}</button>")]
        case .css: return [("flex", "display: flex;\n${cursor}"), ("grid", "display: grid;\n${cursor}")]
        case .markdown: return [("link", "[${cursor}](https://)"), ("image", "![${cursor}](path)"), ("code", "```\n${cursor}\n```")]
        case .python: return [("def", "def name(${cursor}):\n    pass"), ("if", "if ${cursor}:\n    pass")]
        case .swift: return [("func", "func name(${cursor}) {\n    \n}")]
        case .go: return [("func", "func name(${cursor}) {\n    \n}")]
        case .rust: return [("fn", "fn name(${cursor}) {\n    \n}")]
        default: return []
        }
    }
}

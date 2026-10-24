import SwiftUI
import WebKit
import AppKit

struct MarkdownPreview: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let path: String
    let root: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.lastText != text || context.coordinator.lastPath != path || context.coordinator.dark != (colorScheme == .dark) else { return }
        context.coordinator.dark = colorScheme == .dark; context.coordinator.lastText = text; context.coordinator.lastPath = path
        view.loadHTMLString(MarkdownRenderer.render(text, path: path, root: root, dark: colorScheme == .dark), baseURL: nil)
    }
    class Coordinator: NSObject, WKNavigationDelegate {
        var dark = false; var lastText: String?; var lastPath: String?
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}
enum MarkdownRenderer {
    static func escape(_ source: String) -> String { source.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;") }
    static func inline(_ source: String) -> String {
        var result = escape(source)
        let patterns: [(String,String)] = [
            (#"`([^`]+)`"#, "<code>$1</code>"),
            (#"\[([^\]]+)\]\((https?://[^\s)]+|mailto:[^\s)]+)\)"#, "<a href=\"$2\">$1</a>"),
            (#"\*\*(.+?)\*\*|__(.+?)__"#, "<strong>$1$2</strong>"),
            (#"(?<!\*)\*([^*]+)\*(?!\*)"#, "<em>$1</em>"),
            (#"~~(.+?)~~"#, "<del>$1</del>")
        ]
        for (pattern, replacement) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: replacement)
        }
        return result
    }
    static func render(_ source: String, path: String = "", root: String = "", dark: Bool = false) -> String {
        let lines = source.components(separatedBy: .newlines)
        var body = "", paragraph: [String] = [], code: [String] = [], fence: String?, list: String?, index = 0
        func flush() { if !paragraph.isEmpty { body += "<p>" + paragraph.map(inline).joined(separator: "<br>") + "</p>"; paragraph = [] } }
        func closeList() { if let current = list { body += "</\(current)>"; list = nil } }
        func cells(_ row: String) -> [String] { row.trimmingCharacters(in: CharacterSet(charactersIn: " |\t")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
        while index < lines.count {
            let line = lines[index], trimmed = line.trimmingCharacters(in: .whitespaces); index += 1
            if let marker = fence {
                if trimmed.hasPrefix(marker) { body += "<pre><code>" + escape(code.joined(separator: "\n")) + "</code></pre>"; code = []; fence = nil }
                else { code.append(line) }; continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { flush(); closeList(); fence = String(trimmed.prefix(3)); continue }
            if trimmed.isEmpty { flush(); closeList(); continue }
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).hasPrefix(" ") { flush(); closeList(); body += "<h\(hashes)>" + inline(String(trimmed.dropFirst(hashes + 1))) + "</h\(hashes)>"; continue }
            if ["---", "***", "___"].contains(trimmed) { flush(); closeList(); body += "<hr>"; continue }
            if trimmed.hasPrefix(">") { flush(); closeList(); body += "<blockquote>" + inline(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)) + "</blockquote>"; continue }
            if trimmed.contains("|"), index < lines.count, lines[index].range(of: #"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$"#, options: .regularExpression) != nil {
                flush(); closeList(); body += "<table><thead><tr>" + cells(line).map { "<th>" + inline($0) + "</th>" }.joined() + "</tr></thead><tbody>"; index += 1
                while index < lines.count && lines[index].contains("|") { body += "<tr>" + cells(lines[index]).map { "<td>" + inline($0) + "</td>" }.joined() + "</tr>"; index += 1 }; body += "</tbody></table>"; continue
            }
            let bullet = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
            let orderedRange = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression)
            if bullet || orderedRange != nil {
                flush(); let kind = bullet ? "ul" : "ol"
                if list != kind { closeList(); list = kind; body += "<\(kind)>" }
                var item = bullet ? String(trimmed.dropFirst(2)) : String(trimmed[orderedRange!.upperBound...])
                var check = ""
                if item.hasPrefix("[ ] ") || item.lowercased().hasPrefix("[x] ") { check = item.lowercased().hasPrefix("[x]") ? "☑ " : "☐ "; item = String(item.dropFirst(4)) }
                body += "<li>" + check + inline(item) + "</li>"; continue
            }
            closeList(); paragraph.append(line)
        }
        flush(); closeList()
        if fence != nil { body += "<pre><code>" + escape(code.joined(separator: "\n")) + "</code></pre>" }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'">
        <style>body{font:14px/1.75 -apple-system,BlinkMacSystemFont,sans-serif;color:#252a34;background:#fff;max-width:820px;margin:auto;padding:26px 34px;overflow-wrap:anywhere}h1,h2,h3,h4{line-height:1.35;letter-spacing:-.02em;margin:1.4em 0 .55em}h1{font-size:28px;border-bottom:1px solid #e9edf2;padding-bottom:12px}h2{font-size:22px}p{margin:.9em 0}a{color:#2463eb}code{font:12px/1.65 ui-monospace,Menlo,monospace;background:#f1f3f6;border-radius:4px;padding:2px 5px;color:#a34b31}pre{background:#f7f8fa;border:1px solid #e9edf2;border-radius:8px;padding:16px;overflow:auto}pre code{padding:0;background:none;color:#303747}blockquote{border-left:3px solid #b8c9ed;margin:16px 0;padding:8px 16px;background:#f7f9fc;color:#687384}table{border-collapse:collapse;margin:16px 0;width:100%}td,th{border:1px solid #e3e7ed;text-align:left;padding:8px 12px}th{background:#f5f7fa}hr{border:0;border-top:1px solid #e3e7ed;margin:24px 0}li{margin:4px 0}\(dark ? "body{background:#252525;color:#e3e5e8}h1,td,th,pre,hr{border-color:#41444b}code{background:#34363c;color:#e6aa85}pre,blockquote,th{background:#2d3036}pre code{color:#dfe3ea}blockquote{color:#adb9ca}a{color:#8ab4ff}" : "")</style></head><body>\(body)</body></html>
        """
    }
}

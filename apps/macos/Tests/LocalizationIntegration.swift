import Foundation

@main struct LocalizationIntegration {
    static func main() throws {
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw NSError(domain: message, code: 1) }
            print("PASS: " + message)
        }
        for code in ["zh", "zh-CN", "zh-Hans-CN", "zh-Hant-TW", "zh_HK"] {
            try check(AppLanguage.detect([code]) == "zh-Hans", "Chinese system: " + code)
        }
        for languages in [["en-US"], ["ja-JP", "zh-Hans"], ["fr"], []] {
            try check(AppLanguage.detect(languages) == "en", "Non-Chinese primary language defaults to English")
        }
        let suite = "zhixu-language-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try check(AppLanguage.resolve(defaults: defaults, preferredLanguages: ["zh-Hant"]) == "zh-Hans", "First launch uses system language")
        defaults.set("en", forKey: AppLanguage.preferenceKey)
        try check(AppLanguage.resolve(defaults: defaults, preferredLanguages: ["zh-Hans"]) == "en", "Manual English choice survives a Chinese system")
        defaults.set("zh-Hans", forKey: AppLanguage.preferenceKey)
        try check(AppLanguage.resolve(defaults: defaults, preferredLanguages: ["en"]) == "zh-Hans", "Manual Chinese choice survives an English system")
        defaults.set("invalid", forKey: AppLanguage.preferenceKey)
        try check(AppLanguage.resolve(defaults: defaults, preferredLanguages: ["de"]) == "en", "Invalid preference falls back to system detection")
        try check(AppLanguage.text("提交并推送", language: "en") == "Commit & Push", "English action text")
        try check(AppLanguage.text("提交并推送", language: "zh-Hans") == "提交并推送", "Chinese action text")
        let path = "目录/{1}/name.swift"
        try check(AppLanguage.text("已保存 {0}", arguments: [path], language: "en") == "Saved " + path, "File names and placeholder-like user content stay verbatim")
        try check(AppLanguage.text("冲突 {0} · 第 {1} 行", arguments: ["2", "18"], language: "en") == "Conflict 2 · Line 18", "Multiple placeholders render correctly")
        let regex = try NSRegularExpression(pattern: #"\{[0-9]+\}"#)
        func placeholders(_ value: String) -> [String] {
            regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { (value as NSString).substring(with: $0.range) }.sorted()
        }
        for (key, value) in AppLanguage.english {
            try check(placeholders(key) == placeholders(value), "Translation placeholders: " + key.replacingOccurrences(of: "\n", with: " "))
        }
    }
}

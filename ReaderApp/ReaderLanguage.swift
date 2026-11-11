import Foundation

enum ReaderLanguage: String, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en"
    case traditionalChinese = "zh-Hant", japanese = "ja", korean = "ko"
    var id: String { rawValue }
    func resolved(preferred: [String] = Locale.preferredLanguages) -> String {
        if self != .system { return rawValue }
        for identifier in preferred {
            if let code = Self.code(for: identifier) { return code }
        }
        return "en"
    }
    var locale: Locale { Locale(identifier: resolved()) }
    private static func code(for identifier: String) -> String? {
        let value = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if value.hasPrefix("zh-hant") || ["zh-tw", "zh-hk", "zh-mo"].contains(where: { value == $0 || value.hasPrefix($0 + "-") }) { return "zh-Hant" }
        if value.hasPrefix("zh") { return "zh-Hans" }
        if value.hasPrefix("ja") { return "ja" }
        if value.hasPrefix("ko") { return "ko" }
        if value.hasPrefix("en") { return "en" }
        return nil
    }
    private static func table(for code: String, in bundle: Bundle) -> [String: String] {
        guard let url = bundle.resourceURL?.appendingPathComponent("\(code).lproj/Localizable.strings"),
              let data = try? Data(contentsOf: url),
              let table = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else { return [:] }
        return table
    }
    // Immutable Sendable values, initialized once by Swift's thread-safe static initialization.
    private static let mainTables = Dictionary(uniqueKeysWithValues:
        ["en", "zh-Hant", "ja", "ko"].map { ($0, table(for: $0, in: .main)) })
    static func message(_ message: String, locale: Locale, bundle: Bundle = .main) -> String {
        guard let code = code(for: locale.identifier), code != "zh-Hans" else { return message }
        let translations = bundle == .main ? (mainTables[code] ?? [:]) : table(for: code, in: bundle)
        func translated(_ key: String) -> String { translations[key] ?? key }
        return message.components(separatedBy: "\n").map { line in
            let exact = translated(line)
            if exact != line { return exact }
            let prefix = "无法保留文件夹授权："
            if line.hasPrefix(prefix) { return translated(prefix) + line.dropFirst(prefix.count) }
            let ratePrefix = "GitHub 访问额度暂不可用，请在 "
            let rateSuffix = " 后重试。"
            if line.hasPrefix(ratePrefix), line.hasSuffix(rateSuffix) {
                let time = String(line.dropFirst(ratePrefix.count).dropLast(rateSuffix.count))
                return translated("GitHub 访问额度暂不可用，请在 %@ 后重试。").replacingOccurrences(of: "%@", with: time)
            }
            if line.hasPrefix("GitHub 请求失败（"), line.hasSuffix("）。") {
                let status = String(line.dropFirst("GitHub 请求失败（".count).dropLast(2))
                return translated("GitHub 请求失败（%@）。").replacingOccurrences(of: "%@", with: status)
            }
            // System/file-provider descriptions remain in the system's language.
            return line
        }.joined(separator: "\n")
    }
}

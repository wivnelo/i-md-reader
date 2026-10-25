import Foundation

enum ReaderLanguage: String, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en"
    var id: String { rawValue }
    func resolved(preferred: [String] = Locale.preferredLanguages) -> String {
        if self != .system { return rawValue }
        for identifier in preferred {
            if identifier.lowercased().hasPrefix("zh") { return "zh-Hans" }
            if identifier.lowercased().hasPrefix("en") { return "en" }
        }
        return "en"
    }
    var locale: Locale { Locale(identifier: resolved()) }
    private static func englishTable(in bundle: Bundle) -> [String: String] {
        let url = bundle.bundleURL.appendingPathComponent("en.lproj/Localizable.strings")
        guard let data = try? Data(contentsOf: url),
              let table = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String] else { return [:] }
        return table
    }
    private static let mainEnglishTable = englishTable(in: .main)
    static func message(_ message: String, locale: Locale, bundle: Bundle = .main) -> String {
        guard locale.identifier.hasPrefix("en") else { return message }
        let table = bundle == .main ? mainEnglishTable : englishTable(in: bundle)
        func translated(_ key: String) -> String { table[key] ?? key }
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

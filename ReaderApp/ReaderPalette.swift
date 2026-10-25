import SwiftUI

/// Palette and appearance are independent: every palette has a light and dark set.
enum ReaderPalette: String, CaseIterable, Identifiable {
    case mist, mountain, moss, sand
    var id: String { rawValue }
    var name: String {
        switch self {
        case .mist: "雾蓝"
        case .mountain: "远山"
        case .moss: "青苔"
        case .sand: "暖砂"
        }
    }
    static func resolve(_ value: String) -> Self { Self(rawValue: value) ?? .mist }
    func colors(dark: Bool) -> ReaderColors {
        let values: [String]
        switch (self, dark) {
        case (.mist, false): values = ["fcfbf8", "30363b", "f2f4f5", "f7f7f5", "426b87", "e3ebf0", "eff2f3", "dce1e3", "66727a"]
        case (.mist, true): values = ["252628", "c7c9cc", "202326", "292d31", "94b6cf", "344652", "2e3338", "3b4146", "a2abb3"]
        case (.mountain, false): values = ["fcfbf8", "32363b", "f1f2f4", "f7f7f6", "596d87", "e6eaf0", "f0f1f3", "dfe1e5", "6e747e"]
        case (.mountain, true): values = ["252628", "c8c9cc", "222326", "2a2c31", "a3b3cd", "3b4353", "303239", "3d4048", "a7acb6"]
        case (.moss, false): values = ["fcfbf8", "2e332f", "f1f4f1", "f7f8f4", "3d6b59", "e2ece6", "eef2ed", "dce3dc", "69756c"]
        case (.moss, true): values = ["252628", "c7c7c9", "202123", "292d2c", "9db5a9", "34493f", "2e3230", "3b433e", "a4afa7"]
        case (.sand, false): values = ["fcfaf6", "3c3833", "f3f0eb", "f8f5ef", "80694e", "ece5da", "f0ece5", "e2dcd2", "7b7165"]
        case (.sand, true): values = ["282624", "cec8c1", "23211f", "2f2c29", "c1ad90", "4b4236", "35302b", "484039", "afa498"]
        }
        return ReaderColors(values: values)
    }
}

struct ReaderColors {
    let values: [String]
    var paper: Color { color(0) }
    var ink: Color { color(1) }
    var sidebar: Color { color(2) }
    var accent: Color { color(4) }
    var selection: Color { color(5) }
    var secondary: Color { color(8) }
    var cssVariables: String {
        zip(["paper", "ink", "sidebar", "chrome", "accent", "selection", "soft", "line", "secondary"], values)
            .map { "--\($0.0):#\($0.1)" }.joined(separator: ";")
    }
    private func color(_ index: Int) -> Color {
        let rgb = UInt32(values[index], radix: 16)!
        return Color(red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255)
    }
}

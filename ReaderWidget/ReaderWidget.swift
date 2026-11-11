import SwiftUI
import UIKit
import WidgetKit

/// Shared with the app through the App Group; written by ReaderWidgetFeed.
private let appGroup = "group.io.github.wivnelo.imdreader"

private struct ReadingItem: Codable, Hashable {
    let key: String
    let title: String
    let source: String
    let progress: Double

    /// Opens this document in the app at its saved position.
    var url: URL {
        var components = URLComponents()
        components.scheme = "imdreader"; components.host = "open"
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        return components.url!
    }
}

private struct ReadingTimelineEntry: TimelineEntry {
    let date: Date
    let items: [ReadingItem]
}

private struct ReadingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadingTimelineEntry {
        ReadingTimelineEntry(date: .now, items: [ReadingItem(key: "", title: text("为阅读留一点空间", "Make Room for Reading", "為閱讀留一點空間", "読書のためのひとときを", "독서를 위한 작은 여유"),
                                                           source: "iMDReader", progress: 0.4)])
    }
    func getSnapshot(in context: Context, completion: @escaping (ReadingTimelineEntry) -> Void) {
        completion(context.isPreview && Self.items().isEmpty ? placeholder(in: context) : ReadingTimelineEntry(date: .now, items: Self.items()))
    }
    // The app reloads the timeline whenever reading history changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingTimelineEntry>) -> Void) {
        completion(Timeline(entries: [ReadingTimelineEntry(date: .now, items: Self.items())], policy: .never))
    }
    private static func items() -> [ReadingItem] {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: "readingHistory") else { return [] }
        return (try? JSONDecoder().decode([ReadingItem].self, from: data)) ?? []
    }
}

/// Follows the system language; the widget has no in-app language override.
private func text(_ chinese: String, _ english: String, _ traditional: String, _ japanese: String, _ korean: String) -> String {
    let code = (Locale.preferredLanguages.first ?? "").replacingOccurrences(of: "_", with: "-").lowercased()
    if code.hasPrefix("zh-hant") || ["zh-tw", "zh-hk", "zh-mo"].contains(where: { code == $0 || code.hasPrefix($0 + "-") }) { return traditional }
    if code.hasPrefix("zh") { return chinese }
    if code.hasPrefix("ja") { return japanese }
    if code.hasPrefix("ko") { return korean }
    return english
}

/// The app's default mist palette, matching light and dark mode.
private enum Mist {
    static let paper = dynamic(0xfcfbf8, 0x252628)
    static let ink = dynamic(0x30363b, 0xc7c9cc)
    static let accent = dynamic(0x426b87, 0x94b6cf)
    static let secondary = dynamic(0x66727a, 0xa2abb3)
    private static func dynamic(_ light: Int, _ dark: Int) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }
    private static func rgb(_ value: Int) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

private struct ContinueReadingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReadingTimelineEntry

    /// How many documents fit without clipping the header.
    private var limit: Int {
        switch family { case .systemSmall: 1; case .systemMedium: 2; default: 5 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
            header
            if entry.items.isEmpty {
                Spacer(minLength: 0)
                Text(text("打开 iMDReader 开始阅读", "Open iMDReader to start reading", "打開 iMDReader 開始閱讀", "iMDReader を開いて読み始めましょう", "iMDReader를 열어 읽기를 시작하세요")).font(.callout).foregroundStyle(Mist.secondary)
            } else if family == .systemSmall, let first = entry.items.first {
                Spacer(minLength: 0)
                row(first, titleLines: 3)
            } else {
                ForEach(entry.items.prefix(limit), id: \.self) { item in Link(destination: item.url) { row(item, titleLines: 1) } }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(family == .systemSmall ? entry.items.first?.url : nil)
        .containerBackground(Mist.paper, for: .widget)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text").font(.caption.weight(.semibold))
            Text("iMDReader").font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            if family != .systemSmall { Text(text("继续阅读", "Continue Reading", "繼續閱讀", "続きを読む", "이어서 읽기")).font(.caption2).foregroundStyle(Mist.secondary) }
        }
        .foregroundStyle(Mist.accent)
        .lineLimit(1)
    }

    private func sourceName(_ item: ReadingItem) -> String {
        if item.key.hasPrefix("file:") { return text("单个文件", "Single File", "單一檔案", "単一ファイル", "단일 파일") }
        // Stable built-in sample source ID; user-created folder names stay verbatim.
        if item.key.hasPrefix("E4072B41-1284-4D82-82BE-846370D11759|") {
            return text("阅读示例", "Reading Samples", "閱讀範例", "サンプル", "읽기 예제")
        }
        return item.source
    }

    private func row(_ item: ReadingItem, titleLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Mist.ink).lineLimit(titleLines)
            HStack(spacing: 6) {
                Text(sourceName(item)).lineLimit(1)
                Spacer(minLength: 4)
                Text(min(1, max(0, item.progress)), format: .percent.precision(.fractionLength(0))).monospacedDigit()
            }.font(.caption2).foregroundStyle(Mist.secondary)
            ProgressView(value: min(1, max(0, item.progress))).tint(Mist.accent)
        }
    }
}

struct ContinueReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinueReading", provider: ReadingProvider()) { ContinueReadingView(entry: $0) }
            .configurationDisplayName(text("继续阅读", "Continue Reading", "繼續閱讀", "続きを読む", "이어서 읽기"))
            .description(text("回到最近阅读的文档。", "Return to the documents you read recently.", "回到最近閱讀的文件。", "最近読んだ書類に戻ります。", "최근에 읽은 문서로 돌아갑니다."))
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main struct ReaderWidgetBundle: WidgetBundle {
    var body: some Widget { ContinueReadingWidget() }
}

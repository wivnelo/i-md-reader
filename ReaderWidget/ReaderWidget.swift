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
        ReadingTimelineEntry(date: .now, items: [ReadingItem(key: "", title: text("为阅读留一点空间", "Make Room for Reading"),
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
private func text(_ chinese: String, _ english: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
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

    var body: some View {
        Group {
            if let first = entry.items.first {
                if family == .systemSmall { item(first, large: true).widgetURL(first.url) }
                else {
                    VStack(alignment: .leading, spacing: 8) {
                        header
                        ForEach(entry.items.prefix(3), id: \.self) { item in Link(destination: item.url) { self.item(item, large: false) } }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    Spacer(minLength: 0)
                    Text(text("打开 iMDReader 开始阅读", "Open iMDReader to start reading")).font(.callout).foregroundStyle(Mist.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Mist.paper, for: .widget)
    }

    private var header: some View {
        Label(text("继续阅读", "Continue Reading"), systemImage: "book").font(.caption.weight(.semibold)).foregroundStyle(Mist.accent)
    }

    private func item(_ item: ReadingItem, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: large ? 6 : 3) {
            if large { header; Spacer(minLength: 0) }
            Text(item.title).font(large ? .headline : .subheadline.weight(.semibold)).foregroundStyle(Mist.ink).lineLimit(large ? 3 : 1)
            HStack(spacing: 6) {
                Text(item.source).lineLimit(1)
                Spacer(minLength: 4)
                Text(item.progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
            }.font(.caption2).foregroundStyle(Mist.secondary)
            ProgressView(value: min(1, max(0, item.progress))).tint(Mist.accent)
        }
    }
}

struct ContinueReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinueReading", provider: ReadingProvider()) { ContinueReadingView(entry: $0) }
            .configurationDisplayName(text("继续阅读", "Continue Reading"))
            .description(text("回到最近阅读的文档。", "Return to the documents you read recently."))
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main struct ReaderWidgetBundle: WidgetBundle {
    var body: some Widget { ContinueReadingWidget() }
}

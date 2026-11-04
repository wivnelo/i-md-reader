import AppIntents
import Combine
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
#if os(iOS)
import WidgetKit
#endif

/// Requests from Spotlight and Shortcuts that the reader screen carries out.
@MainActor final class ReaderRouter: ObservableObject {
    static let shared = ReaderRouter()
    enum Request: Equatable { case continueReading, open(String) }
    @Published var request: Request?
}

/// Keeps the system Spotlight index in line with the reading history; the index stays on this device.
@MainActor final class ReaderSpotlight {
    private var indexed: [String: ReadingEntry] = [:]
    private var subscription: AnyCancellable?

    init(store: ReaderStore) {
        subscription = store.$readingHistory.sink { [weak self] history in self?.update(history) }
    }

    private func update(_ history: [ReadingEntry]) {
        let current = Dictionary(history.map { ($0.key, $0) }) { first, _ in first }
        // Progress changes while scrolling; only re-index what Spotlight shows.
        let changed = history.filter { entry in
            indexed[entry.key].map { $0.title != entry.title || $0.source != entry.source || $0.excerpt != entry.excerpt } ?? true
        }
        let removed = indexed.keys.filter { current[$0] == nil }
        indexed = current
        // Let Siri and Shortcuts offer the current documents as "Open Document" choices.
        if !changed.isEmpty || !removed.isEmpty { ReaderShortcuts.updateAppShortcutParameters() }
        if !removed.isEmpty { CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: removed) }
        guard !changed.isEmpty else { return }
        CSSearchableIndex.default().indexSearchableItems(changed.map { entry in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = entry.title
            attributes.displayName = entry.title
            attributes.contentDescription = entry.excerpt
            attributes.keywords = [entry.source]
            return CSSearchableItem(uniqueIdentifier: entry.key, domainIdentifier: "reading", attributeSet: attributes)
        })
    }
}

#if os(iOS)
/// Shares the reading history with the Continue Reading widget through the App Group.
@MainActor final class ReaderWidgetFeed {
    static let appGroup = "group.io.github.wivnelo.imdreader"
    private var shown = ""
    private var subscription: AnyCancellable?

    init(store: ReaderStore) {
        subscription = store.$readingHistory.sink { [weak self] history in self?.publish(history) }
    }

    private func publish(_ history: [ReadingEntry]) {
        guard let shared = UserDefaults(suiteName: Self.appGroup), let data = try? JSONEncoder().encode(Array(history.prefix(3))) else { return }
        shared.set(data, forKey: "readingHistory")
        // Scrolling changes progress constantly; refresh the widget only when what it shows changes visibly.
        let visible = history.prefix(3).map { "\($0.key)|\($0.title)|\(Int($0.progress * 20))" }.joined(separator: "\n")
        guard visible != shown else { return }
        shown = visible
        WidgetCenter.shared.reloadTimelines(ofKind: "ContinueReading")
    }
}
#endif

struct ReadingDocument: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "文档"
    static let defaultQuery = ReadingDocumentQuery()
    let id: String
    let title: String
    let source: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(source)") }
}

struct ReadingDocumentQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ReadingDocument] {
        Self.history().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [ReadingDocument] { Self.history() }
    private static func history() -> [ReadingDocument] {
        let entries = (try? JSONDecoder().decode([ReadingEntry].self, from: UserDefaults.standard.data(forKey: "readingHistory") ?? Data())) ?? []
        return entries.map { ReadingDocument(id: $0.key, title: $0.title, source: $0.source) }
    }
}

struct ContinueReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "继续阅读"
    static let description = IntentDescription("打开上次阅读的文档，回到上次的位置。")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        ReaderRouter.shared.request = .continueReading
        return .result()
    }
}

struct OpenReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "打开文档"
    static let description = IntentDescription("打开最近阅读过的一篇文档。")
    static let openAppWhenRun = true
    @Parameter(title: "文档") var document: ReadingDocument
    @MainActor func perform() async throws -> some IntentResult {
        ReaderRouter.shared.request = .open(document.id)
        return .result()
    }
}

struct ReaderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ContinueReadingIntent(),
                    phrases: ["在 \(.applicationName) 继续阅读", "Continue reading in \(.applicationName)"],
                    shortTitle: "继续阅读", systemImageName: "book")
        AppShortcut(intent: OpenReadingIntent(),
                    phrases: ["用 \(.applicationName) 打开文档", "Open a document in \(.applicationName)",
                              "用 \(.applicationName) 打开 \(\.$document)", "Open \(\.$document) in \(.applicationName)"],
                    shortTitle: "打开文档", systemImageName: "doc.text")
    }
}

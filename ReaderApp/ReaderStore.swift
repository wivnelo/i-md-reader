import SwiftUI
import UniformTypeIdentifiers
import ReaderCore

enum ReaderFontScale {
    // Separate slopes keep 17 at the center without losing the existing 26pt maximum.
    static func position(for size: Double) -> Double {
        let size = min(26, max(12, size))
        return size <= 17 ? (size - 12) / 10 : 0.5 + (size - 17) / 18
    }
    static func size(at position: Double) -> Double {
        let position = min(1, max(0, position))
        return (position <= 0.5 ? 12 + position * 10 : 17 + (position - 0.5) * 18).rounded()
    }
}

struct SavedSource: Codable, Identifiable {
    var id: UUID
    var name: String
    var bookmark: Data
}

final class ScopedAccess: @unchecked Sendable {
    let url: URL
    private let scoped: Bool
    init(_ url: URL) { self.url = url; scoped = url.startAccessingSecurityScopedResource() }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

struct SavedGitHubSource: Codable, Identifiable, Sendable {
    let id: UUID
    let url: String
    let reference: String?
    var resolvedReference: String? = nil
}

struct FolderSource: Identifiable {
    let id: UUID
    let name: String
    let access: ScopedAccess?
    let isSample: Bool
    var remote: SavedGitHubSource? = nil
    var url: URL? { access?.url }
}

struct SavedRecentFile: Codable, Identifiable {
    let id: UUID
    var name: String
    var bookmark: Data
}

struct RecentFile: Identifiable {
    let id: UUID
    let name: String
    let access: ScopedAccess?
    var key: String { "file:" + id.uuidString }
}

struct OpenDocument {
    let id = UUID()
    let key: String
    let url: URL
    let sourceID: UUID
    let access: ScopedAccess
    let rendered: RenderedDocument
    let initialProgress: Double
    var isStandalone = false
}

@MainActor final class ReaderStore: ObservableObject {
    @Published private(set) var sources: [FolderSource] = []
    @Published private(set) var recentFiles: [RecentFile] = []
    private var savedFiles: [SavedRecentFile] = []
    private var handledIncomingFile = false
    @Published private(set) var nodes: [String: [FileNode]] = [:]
    @Published private(set) var directoryErrors: [String: String] = [:]
    @Published private(set) var loadingDirectories: Set<String> = []
    @Published private(set) var refreshingSources: Set<UUID> = []
    @Published private(set) var sourceVersions: [UUID: UInt] = [:]
    @Published var expanded: Set<String>
    @Published private(set) var document: OpenDocument?
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published var progress: Double = 0
    @Published var selectedKey: String?
    @Published private var sourceOrder: [String]
    private var bookmarks: [SavedSource]
    private var readingTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let github: GitHubReader
    private var remoteLocations: [UUID: GitHubLocation] = [:]
    @Published private(set) var isAddingGitHub = false
    private var positions: [String: Double]
    private var directoryRequests: [String: UUID] = [:]
    private var refreshRequests: [UUID: UUID] = [:]
    static let sampleID = UUID(uuidString: "E4072B41-1284-4D82-82BE-846370D11759")!

    init(defaults: UserDefaults = .standard, github: GitHubReader = GitHubReader()) {
        self.defaults = defaults
        self.github = github
        sourceOrder = defaults.stringArray(forKey: "sourceOrder") ?? []
        expanded = Set(defaults.stringArray(forKey: "expanded") ?? [])
        positions = defaults.dictionary(forKey: "positions") as? [String: Double] ?? [:]
        bookmarks = (try? JSONDecoder().decode([SavedSource].self, from: defaults.data(forKey: "sources") ?? Data())) ?? []
        savedFiles = (try? JSONDecoder().decode([SavedRecentFile].self, from: defaults.data(forKey: "recentFiles") ?? Data())) ?? []
        for index in savedFiles.indices {
            let saved = savedFiles[index]
            var stale = false
            do {
                let url = try URL(resolvingBookmarkData: saved.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                let access = ScopedAccess(url)
                if stale { savedFiles[index].bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
                recentFiles.append(RecentFile(id: saved.id, name: url.lastPathComponent, access: access))
            } catch {
                // Keep recent records for temporary provider/network failures.
                recentFiles.append(RecentFile(id: saved.id, name: saved.name, access: nil))
            }
        }
        if let data = try? JSONEncoder().encode(savedFiles) { defaults.set(data, forKey: "recentFiles") }
        var refreshedBookmarks = false
        var deniedBookmarks: Set<UUID> = []
        for index in bookmarks.indices {
            let saved = bookmarks[index]
            var stale = false
            do {
                let url = try URL(resolvingBookmarkData: saved.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                let access = ScopedAccess(url)
                if stale {
                    bookmarks[index].bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                    refreshedBookmarks = true
                }
                sources.append(FolderSource(id: saved.id, name: saved.name, access: access, isSample: false))
            } catch {
                if Self.isExplicitPermissionDenial(error) { deniedBookmarks.insert(saved.id) }
                else { sources.append(FolderSource(id: saved.id, name: saved.name, access: nil, isSample: false)) }
            }
        }
        let remote = (try? JSONDecoder().decode([SavedGitHubSource].self, from: defaults.data(forKey: "githubSources") ?? Data())) ?? []
        for saved in remote {
            guard let link = try? GitHubLink(saved.url) else { continue }
            sources.append(Self.remoteSource(saved, link: link))
        }
        if let sample = Bundle.main.url(forResource: "Samples", withExtension: nil) {
            sources.append(FolderSource(id: Self.sampleID, name: "阅读示例", access: ScopedAccess(sample), isSample: true))
        }
        if !deniedBookmarks.isEmpty {
            bookmarks.removeAll { deniedBookmarks.contains($0.id) }
            expanded = expanded.filter { id in !deniedBookmarks.contains(where: { id.hasPrefix($0.uuidString + "|") }) }
            positions = positions.filter { item in !deniedBookmarks.contains(where: { item.key.hasPrefix($0.uuidString + "|") }) }
            defaults.set(positions, forKey: "positions")
            if let last = defaults.string(forKey: "lastDocument"), deniedBookmarks.contains(where: { last.hasPrefix($0.uuidString + "|") }) {
                defaults.removeObject(forKey: "lastDocument")
            }
            persistExpanded()
            error = "本地文件夹授权已失效，已移除 App 中的来源；原始文件未删除。"
        }
        if refreshedBookmarks || !deniedBookmarks.isEmpty { persistSources() }
    }

    // Only explicit permission denial is evidence of revoked local access.
    // Missing items, provider/network failures, and stale bookmarks alone are not.
    nonisolated static func isExplicitPermissionDenial(_ error: Error) -> Bool {
        let failure = error as NSError
        guard failure.domain == NSCocoaErrorDomain, failure.code == CocoaError.fileReadNoPermission.rawValue else { return false }
        if let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlying.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(underlying.code)
        }
        return true
    }

    @discardableResult
    func removeIfPermissionDenied(_ source: FolderSource, failure: Error, rootOperation: Bool) async -> Bool {
        guard !source.isSample, source.remote == nil, Self.isExplicitPermissionDenial(failure) else { return false }
        if let access = source.access {
            // Probe just the directory listing: child metadata may be denied while
            // the root grant remains valid. Never infer revocation from that child.
            let rootDenied = await Task.detached {
                do {
                    _ = try FileManager.default.contentsOfDirectory(at: access.url,
                        includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    return false
                } catch { return Self.isExplicitPermissionDenial(error) }
            }.value
            guard rootDenied else { return false }
        } else if !rootOperation { return false }
        guard !Task.isCancelled, sources.contains(where: { $0.id == source.id && $0.access === source.access }) else { return false }
        remove(source)
        error = "本地文件夹授权已失效，已移除 App 中的来源；原始文件未删除。"
        return true
    }

    func retryLocalSource(_ source: FolderSource) async {
        guard source.remote == nil, !source.isSample, source.access == nil,
              let saved = bookmarks.first(where: { $0.id == source.id }) else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: saved.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            let restored = FolderSource(id: saved.id, name: saved.name, access: ScopedAccess(url), isSample: false)
            guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
            sources[index] = restored
            await refresh(restored)
        } catch {
            if !(await removeIfPermissionDenied(source, failure: error, rootOperation: true)) {
                self.error = "文件夹暂时无法访问，已保留来源，请稍后重试。\n\(error.localizedDescription)"
            }
        }
    }

    var orderedSources: [FolderSource] {
        ranked(sources, order: sourceOrder, unknownFirst: true) { $0.id.uuidString }
    }

    private func ranked<T>(_ items: [T], order: [String], unknownFirst: Bool = false, id: (T) -> String) -> [T] {
        var ranks: [String: Int] = [:]
        for (index, value) in order.enumerated() where ranks[value] == nil { ranks[value] = index }
        return items.enumerated().sorted {
            let first = ranks[id($0.element)] ?? (unknownFirst ? -1 : order.count)
            let second = ranks[id($1.element)] ?? (unknownFirst ? -1 : order.count)
            return first == second ? $0.offset < $1.offset : first < second
        }.map(\.element)
    }

    private func rootOrderKey(_ source: FolderSource) -> String { source.id.uuidString + "|" }

    func canReorderSource(_ item: String, over target: String) -> Bool {
        let roots = Set(sources.map(rootOrderKey))
        return item != target && roots.contains(item) && roots.contains(target)
    }

    @discardableResult
    func reorderSource(_ item: String, over target: String, after: Bool? = nil) -> Bool {
        guard canReorderSource(item, over: target) else { return false }
        var order = orderedSources.map(rootOrderKey)
        guard let from = order.firstIndex(of: item), let to = order.firstIndex(of: target) else { return false }
        order.remove(at: from)
        guard let targetIndex = order.firstIndex(of: target) else { return false }
        order.insert(item, at: targetIndex + ((after ?? (from < to)) ? 1 : 0))
        sourceOrder = order.map { String($0.dropLast()) }
        defaults.set(sourceOrder, forKey: "sourceOrder")
        return true
    }

    func moveSource(_ item: String, direction: Int) {
        let order = orderedSources.map(rootOrderKey)
        guard direction == -1 || direction == 1, let index = order.firstIndex(of: item),
              order.indices.contains(index + direction) else { return }
        reorderSource(item, over: order[index + direction])
    }

    func key(source: FolderSource, url: URL) -> String {
        // Ordinary tree rows already share the root URL spelling; avoid filesystem work while laying out each row.
        let path: String
        if let root = source.url?.standardizedFileURL.path {
            let file = url.standardizedFileURL.path
            if file == root { path = "" }
            else if file.hasPrefix(root + "/") { path = String(file.dropFirst(root.count + 1)) }
            else { path = (try? LocalDocuments.relativePath(of: url, to: source.url!)) ?? "" }
        } else { path = "" }
        let relative = path.isEmpty ? "" : "/" + path
        return source.id.uuidString + "|" + relative
    }
    func persistExpanded() { defaults.set(Array(expanded), forKey: "expanded") }
    func hasExpandedSubdirectories(in source: FolderSource) -> Bool {
        expanded.contains { $0.hasPrefix(source.id.uuidString + "|/") }
    }

    func collapseSubdirectories(in source: FolderSource) {
        guard sources.contains(where: { $0.id == source.id }), source.url != nil else { return }
        let root = source.id.uuidString + "|"
        expanded = expanded.filter { !$0.hasPrefix(root + "/") }
        expanded.insert(root)
        persistExpanded()
    }

    func toggle(source: FolderSource, directory: URL) {
        let id = key(source: source, url: directory)
        if expanded.contains(id) { expanded.remove(id) }
        else { expanded.insert(id) }
        persistExpanded()
    }
    func loadChildren(source: FolderSource, directory: URL, reload: Bool = false) async {
        let id = key(source: source, url: directory)
        guard let access = source.access, directoryRequests[id] == nil, reload || nodes[id] == nil else { return }
        let request = UUID()
        directoryRequests[id] = request
        loadingDirectories.insert(id)
        directoryErrors[id] = nil
        do {
            let children: [FileNode]
            if source.remote != nil {
                let location = try await remoteLocation(source)
                children = try await remoteChildren(source, directory: directory, location: location)
            } else {
                children = try await Task.detached(priority: .userInitiated) {
                    try withExtendedLifetime(access) { try LocalDocuments.children(of: directory, root: access.url) }
                }.value
            }
            guard directoryRequests[id] == request, sources.contains(where: { $0.id == source.id && $0.access === access }) else { return }
            nodes[id] = children
        } catch {
            guard directoryRequests[id] == request else { return }
            if source.remote == nil, await removeIfPermissionDenied(source, failure: error, rootOperation: directory.standardizedFileURL == source.url?.standardizedFileURL) { return }
            guard directoryRequests[id] == request else { return }
            directoryErrors[id] = error.localizedDescription
        }
        if directoryRequests[id] == request {
            directoryRequests[id] = nil
            loadingDirectories.remove(id)
        }
    }

    /// Refresh only this source. Replace cached listings after a successful root scan;
    /// a failed refresh retains the previous snapshot and the current reading view.
    func refresh(_ source: FolderSource) async {
        if source.remote != nil { await refreshRemote(source); return }
        guard let access = source.access else { await retryLocalSource(source); return }
        guard !refreshingSources.contains(source.id) else { return }
        let request = UUID()
        let prefix = source.id.uuidString + "|"
        let rootKey = key(source: source, url: access.url)
        var directories: [String: URL] = [rootKey: access.url]
        for id in expanded where id.hasPrefix(prefix) && id != rootKey {
            let relative = String(id.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            directories[id] = access.url.appendingPathComponent(relative)
        }
        let requestedDirectories = directories
        refreshRequests[source.id] = request
        refreshingSources.insert(source.id)
        defer {
            if refreshRequests[source.id] == request {
                refreshRequests[source.id] = nil
                refreshingSources.remove(source.id)
            }
        }
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try withExtendedLifetime(access) {
                    var listings: [String: [FileNode]] = [:]
                    var failures: [String: String] = [:]
                    // The root must succeed before any cache replacement is allowed.
                    listings[rootKey] = try LocalDocuments.children(of: access.url, root: access.url)
                    for (id, directory) in requestedDirectories where id != rootKey {
                        do { listings[id] = try LocalDocuments.children(of: directory, root: access.url) }
                        catch { failures[id] = error.localizedDescription }
                    }
                    return (listings, failures)
                }
            }.value
            guard refreshRequests[source.id] == request,
                  sources.contains(where: { $0.id == source.id && $0.access === access }) else { return }
            invalidateDirectoryLoads(source.id)
            nodes = nodes.filter { !$0.key.hasPrefix(prefix) }.merging(snapshot.0) { _, new in new }
            directoryErrors = directoryErrors.filter { !$0.key.hasPrefix(prefix) }.merging(snapshot.1) { _, new in new }
            sourceVersions[source.id, default: 0] += 1
            // A user-initiated document switch wins over an in-flight source refresh.
            if let current = document, current.sourceID == source.id, selectedKey == current.key, !isLoading {
                positions[current.key] = progress
                open(current.url, source: source, isRefresh: true)
                let task = readingTask
                await task?.value
            }
        } catch {
            guard refreshRequests[source.id] == request else { return }
            if await removeIfPermissionDenied(source, failure: error, rootOperation: true) { return }
            guard refreshRequests[source.id] == request else { return }
            self.error = "刷新失败，已保留之前的内容。\n\(error.localizedDescription)"
        }
    }

    private func invalidateDirectoryLoads(_ sourceID: UUID) {
        let prefix = sourceID.uuidString + "|"
        directoryRequests = directoryRequests.filter { !$0.key.hasPrefix(prefix) }
        loadingDirectories = loadingDirectories.filter { !$0.hasPrefix(prefix) }
    }

    private func reveal(_ url: URL, source: FolderSource) {
        guard let root = source.url, let relative = try? LocalDocuments.relativePath(of: url, to: root) else { return }
        let previous = expanded
        var directory = root
        expanded.insert(key(source: source, url: root))
        for component in relative.split(separator: "/").dropLast() {
            directory.appendPathComponent(String(component))
            expanded.insert(key(source: source, url: directory))
        }
        if previous != expanded { persistExpanded() }
    }

    func addFolder(_ url: URL) {
        let access = ScopedAccess(url)
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            // Re-selecting the same location should not create duplicate roots.
            let existing = sources.first(where: { !$0.isSample && $0.url?.standardizedFileURL == url.standardizedFileURL })?.id
            let id = existing ?? UUID()
            let prefix = id.uuidString + "|"
            let sameFolder = sources.first(where: { $0.id == id })?.url?.standardizedFileURL == url.standardizedFileURL
            if !sameFolder {
                expanded = expanded.filter { !$0.hasPrefix(prefix) }
                positions = positions.filter { !$0.key.hasPrefix(prefix) }
                defaults.set(positions, forKey: "positions")
                if defaults.string(forKey: "lastDocument")?.hasPrefix(prefix) == true { defaults.removeObject(forKey: "lastDocument") }
            }
            if document?.sourceID == id || selectedKey?.hasPrefix(id.uuidString + "|") == true {
                readingTask?.cancel(); document = nil; selectedKey = nil; isLoading = false
            }
            refreshRequests[id] = nil; refreshingSources.remove(id)
            invalidateDirectoryLoads(id)
            let saved = SavedSource(id: id, name: url.lastPathComponent, bookmark: bookmark)
            bookmarks.removeAll { $0.id == id }; bookmarks.append(saved)
            sources.removeAll { $0.id == id }
            sources.insert(FolderSource(id: id, name: saved.name, access: access, isSample: false), at: 0)
            nodes = nodes.filter { !$0.key.hasPrefix(prefix) }
            directoryErrors = directoryErrors.filter { !$0.key.hasPrefix(prefix) }
            expanded.insert(id.uuidString + "|")
            sourceVersions[id, default: 0] += 1
            persistSources(); persistExpanded()
            if let current = document, current.isStandalone, selectedKey == current.key, !isLoading,
               (try? LocalDocuments.confined(current.url, to: url)) != nil,
               let source = sources.first(where: { $0.id == id }) {
                positions[key(source: source, url: current.url)] = progress
                defaults.set(positions, forKey: "positions")
                open(current.url, source: source)
            }
        } catch { self.error = "无法保留文件夹授权：\(error.localizedDescription)" }
    }
    func remove(_ source: FolderSource) {
        guard !source.isSample else { return }
        if document?.sourceID == source.id || selectedKey?.hasPrefix(source.id.uuidString + "|") == true {
            readingTask?.cancel(); isLoading = false
            selectedKey = document?.sourceID == source.id ? nil : document?.key
            if document?.sourceID == source.id { document = nil }
        }
        refreshRequests[source.id] = nil; refreshingSources.remove(source.id)
        invalidateDirectoryLoads(source.id)
        sources.removeAll { $0.id == source.id }
        remoteLocations[source.id] = nil
        persistRemoteSources()
        bookmarks.removeAll { $0.id == source.id }
        let prefix = source.id.uuidString + "|"
        nodes = nodes.filter { !$0.key.hasPrefix(prefix) }
        directoryErrors = directoryErrors.filter { !$0.key.hasPrefix(prefix) }
        sourceVersions[source.id] = nil
        sourceOrder.removeAll { $0 == source.id.uuidString }
        defaults.set(sourceOrder, forKey: "sourceOrder")
        expanded = expanded.filter { !$0.hasPrefix(prefix) }
        positions = positions.filter { !$0.key.hasPrefix(prefix) }
        if defaults.string(forKey: "lastDocument")?.hasPrefix(prefix) == true { defaults.removeObject(forKey: "lastDocument") }
        defaults.set(positions, forKey: "positions")
        persistSources(); persistExpanded()
    }
    private func persistSources() {
        if let data = try? JSONEncoder().encode(bookmarks) { defaults.set(data, forKey: "sources") }
    }

    func open(_ url: URL, source: FolderSource, isRefresh: Bool = false) {
        guard let access = source.access else { Task { await retryLocalSource(source) }; return }
        readingTask?.cancel()
        let id = key(source: source, url: url)
        selectedKey = id; isLoading = true; error = nil
        readingTask = Task {
            do {
                let rendered: RenderedDocument
                if source.remote != nil {
                    let location = try await remoteLocation(source)
                    let path = try remotePath(url, source: source, location: location)
                    let text = try await github.markdown(location, path: path)
                    rendered = await Task.detached(priority: .userInitiated) {
                        MarkdownRenderer().render(text, allowRelativeImages: false)
                    }.value
                } else {
                rendered = try await Task.detached(priority: .userInitiated) {
                    try withExtendedLifetime(access) {
                        // File coordination allows iCloud/file providers to materialize the document.
                        var coordinationError: NSError?
                        var result: Result<RenderedDocument, Error>?
                        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                            result = Result { MarkdownRenderer().render(try LocalDocuments.read(coordinatedURL, root: access.url)) }
                        }
                        if let coordinationError { throw coordinationError }
                        guard let result else { throw CocoaError(.fileReadUnknown) }
                        return try result.get()
                    }
                }.value
                }
                guard !Task.isCancelled, sources.contains(where: { $0.id == source.id && $0.access === access }) else { return }
                reveal(url, source: source)
                document = OpenDocument(key: id, url: url, sourceID: source.id, access: access, rendered: rendered, initialProgress: positions[id] ?? 0)
                progress = positions[id] ?? 0
                defaults.set(id, forKey: "lastDocument")
            } catch {
                guard !Task.isCancelled else { return }
                if source.remote == nil, await removeIfPermissionDenied(source, failure: error, rootOperation: false) { return }
                guard !Task.isCancelled, sources.contains(where: { $0.id == source.id && $0.access === access }) else { return }
                if isRefresh, let githubError = error as? GitHubReadError, githubError.isRateLimited {
                    self.error = githubError.localizedDescription + "\n当前文章仍可阅读。"
                } else {
                    self.error = isRefresh ? "文档刷新失败，仍显示上次打开的内容。\n\(error.localizedDescription)" : error.localizedDescription
                }
                selectedKey = document?.key
            }
            if !Task.isCancelled { isLoading = false }
        }
    }
    func restoreLastDocument() {
        guard !handledIncomingFile else { return }
        if let last = defaults.string(forKey: "lastDocument"), let recent = recentFiles.first(where: { $0.key == last }) {
            openRecent(recent)
            return
        }
        if let id = defaults.string(forKey: "lastDocument"), let separator = id.firstIndex(of: "|"),
           let source = sources.first(where: { $0.id.uuidString == String(id[..<separator]) }), let root = source.url {
            let relative = String(id[id.index(after: separator)...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            open(root.appendingPathComponent(relative), source: source)
        } else if let sample = sources.first(where: \.isSample), let root = sample.url {
            expanded.insert(key(source: sample, url: root)); persistExpanded()
            open(root.appendingPathComponent("为阅读留一点空间.md"), source: sample)
        }
    }
    private func persistRecentFiles() {
        if let data = try? JSONEncoder().encode(savedFiles) { defaults.set(data, forKey: "recentFiles") }
    }

    func openRecent(_ recent: RecentFile) {
        if let access = recent.access { openFileURL(access.url); return }
        guard let saved = savedFiles.first(where: { $0.id == recent.id }) else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: saved.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            openFileURL(url, existingID: saved.id)
        } catch { self.error = "文件暂时无法访问，记录已保留，请稍后重试。" }
    }

    func removeRecent(_ recent: RecentFile) {
        if selectedKey == recent.key {
            readingTask?.cancel(); isLoading = false
            selectedKey = document?.key == recent.key ? nil : document?.key
        }
        if document?.key == recent.key { document = nil }
        recentFiles.removeAll { $0.id == recent.id }
        savedFiles.removeAll { $0.id == recent.id }
        positions[recent.key] = nil
        if defaults.string(forKey: "lastDocument") == recent.key { defaults.removeObject(forKey: "lastDocument") }
        defaults.set(positions, forKey: "positions")
        persistRecentFiles()
    }

    /// Receive either a document picker grant or a system open-in-place URL.
    /// The security scope is held on the FILE, never its ungranted parent.
    func openFileURL(_ input: URL, existingID: UUID? = nil) {
        guard input.isFileURL, LocalDocuments.markdownExtensions.contains(input.pathExtension.lowercased()) else {
            error = "请选择 Markdown 文件（.md 或 .markdown）。"
            return
        }
        handledIncomingFile = true
        var components = URLComponents(url: input, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let url = components?.url ?? input
        let access = ScopedAccess(url)
        // Existing directory grants keep full relative-resource behavior.
        if let source = sources.first(where: {
            $0.remote == nil && $0.url != nil && (try? LocalDocuments.confined(url, to: $0.url!)) != nil
        }) {
            open(input, source: source)
            return
        }
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let previous = recentFiles.first { $0.access?.url.standardizedFileURL.resolvingSymlinksInPath() == canonical }
        let id = existingID ?? previous?.id ?? UUID()
        let key = "file:" + id.uuidString
        readingTask?.cancel()
        selectedKey = key; isLoading = true; error = nil
        readingTask = Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try withExtendedLifetime(access) {
                        var coordinationError: NSError?
                        var output: Result<(RenderedDocument, Data), Error>?
                        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
                            output = Result {
                                let text = try LocalDocuments.read(coordinated, root: coordinated)
                                let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                                return (MarkdownRenderer().render(text, allowRelativeImages: false), bookmark)
                            }
                        }
                        if let coordinationError { throw coordinationError }
                        guard let output else { throw CocoaError(.fileReadUnknown) }
                        return try output.get()
                    }
                }.value
                guard !Task.isCancelled else { return }
                savedFiles.removeAll { $0.id == id }
                savedFiles.insert(SavedRecentFile(id: id, name: url.lastPathComponent, bookmark: result.1), at: 0)
                recentFiles.removeAll { $0.id == id }
                recentFiles.insert(RecentFile(id: id, name: url.lastPathComponent, access: access), at: 0)
                for discarded in recentFiles.dropFirst(20) {
                    positions[discarded.key] = nil
                    savedFiles.removeAll { $0.id == discarded.id }
                }
                recentFiles = Array(recentFiles.prefix(20))
                defaults.set(positions, forKey: "positions")
                persistRecentFiles()
                document = OpenDocument(key: key, url: input, sourceID: id, access: access,
                                        rendered: result.0, initialProgress: positions[key] ?? 0, isStandalone: true)
                progress = positions[key] ?? 0
                defaults.set(key, forKey: "lastDocument")
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                selectedKey = document?.key
            }
            if !Task.isCancelled { isLoading = false }
        }
    }

    private static func remoteSource(_ saved: SavedGitHubSource, link: GitHubLink) -> FolderSource {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("iMDReader-GitHub", isDirectory: true)
            .appendingPathComponent(saved.id.uuidString, isDirectory: true)
        return FolderSource(id: saved.id, name: "\(link.owner)/\(link.repository)" + (link.kind == .repository ? "" : " · " + (link.components.last ?? "")), access: ScopedAccess(root), isSample: false, remote: saved)
    }

    private func persistRemoteSources() {
        if let data = try? JSONEncoder().encode(sources.compactMap(\.remote)) { defaults.set(data, forKey: "githubSources") }
    }

    @discardableResult func addGitHub(_ text: String, reference: String? = nil) async -> Bool {
        guard !isAddingGitHub else { return false }
        isAddingGitHub = true
        error = nil
        defer { isAddingGitHub = false }
        do {
            let link = try GitHubLink(text)
            let reference = reference?.trimmingCharacters(in: .whitespacesAndNewlines)
            let explicit = reference?.isEmpty == false ? reference : nil
            let location = try await github.resolve(link, explicitReference: explicit)
            // Validate accessibility before persisting a new source.
            let duplicate = sources.first { source in
                guard let saved = source.remote, let existing = try? GitHubLink(saved.url) else { return false }
                let previous = remoteLocations[source.id]
                return existing.owner.lowercased() == link.owner.lowercased() && existing.repository.lowercased() == link.repository.lowercased()
                    && existing.kind == link.kind && existing.components == link.components
                    && ((explicit == nil && saved.reference == nil) || (previous?.reference ?? saved.resolvedReference ?? saved.reference) == (explicit ?? location.reference))
            }
            if duplicate != nil { error = "这个 GitHub 来源已经添加。"; return false }
            let saved = SavedGitHubSource(id: UUID(), url: text.trimmingCharacters(in: .whitespacesAndNewlines), reference: explicit, resolvedReference: location.reference)
            let source = Self.remoteSource(saved, link: link)
            let root = source.url!
            let children = try await remoteChildren(source, directory: root, location: location)
            try Task.checkCancellation()
            sources.insert(source, at: 0)
            remoteLocations[source.id] = location
            nodes[key(source: source, url: root)] = children
            expanded.insert(key(source: source, url: root))
            persistExpanded(); persistRemoteSources()
            if link.kind == .document, let file = children.first { open(file.url, source: source) }
            return true
        } catch is CancellationError { return false }
        catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
            return false
        }
    }

    private func remoteLocation(_ source: FolderSource) async throws -> GitHubLocation {
        if let location = remoteLocations[source.id] { return location }
        guard let saved = source.remote, let access = source.access else { throw GitHubReadError.invalidURL }
        let location = try await github.resolve(GitHubLink(saved.url), explicitReference: saved.reference)
        guard sources.contains(where: { $0.id == source.id && $0.access === access }) else { throw CancellationError() }
        // A completed source refresh takes precedence over a slower initial lookup.
        if let newer = remoteLocations[source.id] { return newer }
        remoteLocations[source.id] = location
        return location
    }

    private func remoteBase(_ location: GitHubLocation) -> String {
        location.link.kind == .document ? (location.path as NSString).deletingLastPathComponent : location.path
    }

    private func remotePath(_ url: URL, source: FolderSource, location: GitHubLocation) throws -> String {
        guard let root = source.url else { throw GitHubReadError.invalidPath }
        let relative = try LocalDocuments.relativePath(of: url, to: root)
        let base = remoteBase(location)
        return [base, relative].filter { !$0.isEmpty }.joined(separator: "/")
    }

    private func remoteChildren(_ source: FolderSource, directory: URL, location: GitHubLocation) async throws -> [FileNode] {
        if location.link.kind == .document, directory == source.url {
            // Fetch the file to validate that the pasted link is readable.
            _ = try await github.markdown(location)
            return [FileNode(url: directory.appendingPathComponent((location.path as NSString).lastPathComponent), isDirectory: false)]
        }
        let path = try remotePath(directory, source: source, location: location)
        return try await github.children(location, path: path).map {
            FileNode(url: directory.appendingPathComponent($0.name, isDirectory: $0.isDirectory), isDirectory: $0.isDirectory)
        }
    }

    private func refreshRemote(_ source: FolderSource) async {
        guard let saved = source.remote, let access = source.access, !refreshingSources.contains(source.id) else { return }
        let request = UUID()
        refreshRequests[source.id] = request
        refreshingSources.insert(source.id)
        defer {
            if refreshRequests[source.id] == request { refreshRequests[source.id] = nil; refreshingSources.remove(source.id) }
        }
        do {
            let location = try await github.resolve(GitHubLink(saved.url), explicitReference: saved.reference)
            let prefix = source.id.uuidString + "|"
            let rootKey = key(source: source, url: access.url)
            // An unchanged immutable commit needs no directory/document refetch
            // or WebKit replacement. Failed directories still get a retry.
            if remoteLocations[source.id]?.commit == location.commit, nodes[rootKey] != nil,
               !directoryErrors.keys.contains(where: { $0.hasPrefix(prefix) }) {
                remoteLocations[source.id] = location
                return
            }
            var listings = [rootKey: try await remoteChildren(source, directory: access.url, location: location)]
            var failures: [String: String] = [:]
            let directories = expanded.filter { $0.hasPrefix(prefix) && $0 != rootKey }
            for id in directories {
                let relative = String(id.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                do { listings[id] = try await remoteChildren(source, directory: access.url.appendingPathComponent(relative), location: location) }
                catch { failures[id] = error.localizedDescription }
            }
            guard refreshRequests[source.id] == request, sources.contains(where: { $0.id == source.id && $0.access === access }) else { return }
            invalidateDirectoryLoads(source.id)
            remoteLocations[source.id] = location
            nodes = nodes.filter { !$0.key.hasPrefix(prefix) }.merging(listings) { _, new in new }
            directoryErrors = directoryErrors.filter { !$0.key.hasPrefix(prefix) }.merging(failures) { _, new in new }
            sourceVersions[source.id, default: 0] += 1
            if let current = document, current.sourceID == source.id, selectedKey == current.key, !isLoading {
                positions[current.key] = progress
                open(current.url, source: source, isRefresh: true)
                await readingTask?.value
            }
        } catch {
            guard refreshRequests[source.id] == request else { return }
            if let githubError = error as? GitHubReadError, githubError.isRateLimited {
                self.error = githubError.localizedDescription + "\n当前文章和目录已保留。"
            } else {
                self.error = "刷新失败，已保留之前的内容。\n\(error.localizedDescription)"
            }
        }
    }

    func recordProgress(_ value: Double, documentKey: String) {
        guard value.isFinite, document?.key == documentKey else { return }
        progress = min(1, max(0, value)); positions[documentKey] = progress
        if positions.count > 200 {
            for key in positions.keys.sorted().prefix(positions.count - 200) where key != documentKey { positions.removeValue(forKey: key) }
        }
        defaults.set(positions, forKey: "positions")
    }
}

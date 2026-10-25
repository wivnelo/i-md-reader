import Foundation
import Testing
import ReaderCore
@testable import ReaderStoreChecks

@Test @MainActor func collapseRootSubdirectoriesKeepsReadingOtherSourcesAndPersists() async throws {
    let remote = RemoteFixture()
    let fixture = try Fixture(github: remote.reader)
    defer { fixture.clean() }
    let store = fixture.store
    #expect(await store.addGitHub("https://github.com/test/repo/tree/main/docs", reference: "main"))
    let source = try #require(store.sources.first(where: { $0.remote != nil }))
    let root = try #require(source.url)
    store.open(root.appendingPathComponent("A/Deep/Nested/note.md"), source: source)
    try await fixture.waitForReading()
    let documentID = try #require(store.document?.id)
    let selected = try #require(store.selectedKey)
    store.recordProgress(0.37, documentKey: selected)
    let key = { (path: String) in store.key(source: source, url: root.appendingPathComponent(path)) }
    let otherKey = UUID().uuidString + "|/Keep"
    store.expanded.formUnion([key("AB"), key("AB/Keep"), otherKey])
    #expect(store.hasExpandedSubdirectories(in: source))
    store.collapseSubdirectories(in: source)
    #expect(store.expanded.contains(source.id.uuidString + "|"))
    #expect(!store.hasExpandedSubdirectories(in: source))
    #expect(store.expanded.contains(otherKey))
    #expect(store.document?.id == documentID)
    #expect(store.selectedKey == selected)
    #expect(store.progress == 0.37)
    #expect(ReaderStore(defaults: fixture.defaults, github: remote.reader).expanded == store.expanded)
    store.toggle(source: source, directory: root.appendingPathComponent("A"))
    #expect(store.expanded.contains(key("A")))
    #expect(!store.expanded.contains(key("A/Deep")))
    store.collapseSubdirectories(in: source)
    #expect(!store.hasExpandedSubdirectories(in: source))
}

@Test func localizedMessagesPreserveProviderDetailsAndRetryTime() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
    defer { try? FileManager.default.removeItem(at: root) }
    let english = root.appendingPathComponent("en.lproj")
    try FileManager.default.createDirectory(at: english, withIntermediateDirectories: true)
    let table = ["刷新失败，已保留之前的内容。": "Refresh failed. Previous content was kept.",
                 "无法保留文件夹授权：": "Unable to save folder access: ",
                 "GitHub 访问额度暂不可用，请在 %@ 后重试。": "Try again after %@.",
                 "GitHub 请求失败（%@）。": "GitHub request failed (%@)."]
    try PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0)
        .write(to: english.appendingPathComponent("Localizable.strings"))
    let bundle = try #require(Bundle(url: root))
    let en = Locale(identifier: "en")
    let original = "刷新失败，已保留之前的内容。\nProvider /文件夹/notes.md"
    #expect(ReaderLanguage.message(original, locale: en, bundle: bundle) == "Refresh failed. Previous content was kept.\nProvider /文件夹/notes.md")
    #expect(ReaderLanguage.message(original, locale: Locale(identifier: "zh-Hans"), bundle: bundle) == original)
    #expect(ReaderLanguage.message("GitHub 访问额度暂不可用，请在 15:30 后重试。", locale: en, bundle: bundle) == "Try again after 15:30.")
    #expect(ReaderLanguage.message("GitHub 请求失败（503）。", locale: en, bundle: bundle) == "GitHub request failed (503).")
    #expect(ReaderLanguage.message("无法保留文件夹授权：Provider detail", locale: en, bundle: bundle) == "Unable to save folder access: Provider detail")
}

@Test func interfaceLanguageResolvesExplicitSystemAndUnsupportedChoices() {
    #expect(ReaderLanguage.chinese.resolved(preferred: ["en-US"]) == "zh-Hans")
    #expect(ReaderLanguage.english.resolved(preferred: ["zh-CN"]) == "en")
    #expect(ReaderLanguage.system.resolved(preferred: ["zh-Hant-TW", "en"]) == "zh-Hans")
    #expect(ReaderLanguage.system.resolved(preferred: ["en-GB", "zh-Hans"]) == "en")
    #expect(ReaderLanguage.system.resolved(preferred: ["fr-FR", "en-US"]) == "en")
    #expect(ReaderLanguage.system.resolved(preferred: ["ja-JP"]) == "en")
}

@Test @MainActor func insertionLinePlacesSourceBeforeOrAfterTargetInEitherDirection() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let a = try fixture.add("A"), b = try fixture.add("B"), c = try fixture.add("C")
    let key = { (source: FolderSource) in source.id.uuidString + "|" }
    let store = fixture.store
    #expect(store.reorderSource(key(a), over: key(c), after: true))
    #expect(store.orderedSources.map(\.id) == [c.id, a.id, b.id])
    #expect(store.reorderSource(key(c), over: key(b), after: false))
    #expect(store.orderedSources.map(\.id) == [a.id, c.id, b.id])
    #expect(store.reorderSource(key(b), over: key(a), after: false))
    #expect(store.orderedSources.map(\.id) == [b.id, a.id, c.id])
    #expect(store.reorderSource(key(b), over: key(c), after: true))
    #expect(store.orderedSources.map(\.id) == [a.id, c.id, b.id])
    #expect(store.reorderSource(key(a), over: key(c), after: false))
    #expect(store.orderedSources.map(\.id) == [a.id, c.id, b.id])
    #expect(ReaderStore(defaults: fixture.defaults).orderedSources.map(\.id) == [a.id, c.id, b.id])
}

@Test @MainActor func sourceOrderPersistsAcrossMixedSourcesAndRemoval() async throws {
    let remote = RemoteFixture()
    let fixture = try Fixture(github: remote.reader)
    defer { fixture.clean() }
    let first = try fixture.add("First")
    let second = try fixture.add("Second")
    #expect(await fixture.store.addGitHub("https://github.com/test/repo/tree/main/docs", reference: "main"))
    let github = try #require(fixture.store.sources.first(where: { $0.remote != nil }))
    let rootKey = { (source: FolderSource) in source.id.uuidString + "|" }
    #expect(fixture.store.reorderSource(rootKey(first), over: rootKey(github)))
    #expect(fixture.store.orderedSources.map(\.id) == [first.id, github.id, second.id])
    let restored = ReaderStore(defaults: fixture.defaults, github: remote.reader)
    #expect(restored.orderedSources.map(\.id) == [first.id, github.id, second.id])
    restored.moveSource(rootKey(first), direction: 1)
    #expect(restored.orderedSources.map(\.id) == [github.id, first.id, second.id])
    restored.remove(github)
    #expect(ReaderStore(defaults: fixture.defaults).orderedSources.map(\.id) == [first.id, second.id])
}

@Test @MainActor func sourceReorderRejectsSubfoldersAndNeverChangesFiles() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let source = try fixture.add("Root")
    let other = try fixture.add("Other")
    let root = try #require(source.url)
    for name in ["A", "B"] {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    let file = root.appendingPathComponent("note.md")
    let data = Data("# Unchanged".utf8)
    try data.write(to: file)
    await fixture.store.loadChildren(source: source, directory: root)
    let key = { (name: String) in fixture.store.key(source: source, url: root.appendingPathComponent(name)) }
    #expect(!fixture.store.reorderSource(key("A"), over: key("B")))
    #expect(!fixture.store.reorderSource(key("A"), over: other.id.uuidString + "|"))
    #expect(!fixture.store.reorderSource(source.id.uuidString + "|", over: key("note.md")))
    #expect(fixture.store.reorderSource(source.id.uuidString + "|", over: other.id.uuidString + "|"))
    await fixture.store.refresh(source)
    #expect(fixture.store.nodes[fixture.store.key(source: source, url: root)]?.map(\.name) == ["A", "B", "note.md"])
    #expect(try Data(contentsOf: file) == data)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("A").path))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("B").path))
}

@Test func fontSliderCentersDefaultAndRetainsEveryExistingSize() {
    #expect(ReaderFontScale.position(for: 17) == 0.5)
    #expect(ReaderFontScale.size(at: 0) == 12)
    #expect(ReaderFontScale.size(at: 1) == 26)
    for size in 12...26 {
        #expect(ReaderFontScale.size(at: ReaderFontScale.position(for: Double(size))) == Double(size))
    }
}

@Test @MainActor func onlyExplicitRootPermissionFailureRemovesLocalSourceAndNeverFiles() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let source = try fixture.add("Denied")
    let root = try #require(source.url)
    let file = root.appendingPathComponent("keep.md")
    let data = Data("# Original content".utf8)
    try data.write(to: file)
    fixture.store.open(file, source: source)
    try await fixture.waitForReading()
    for failure in [CocoaError(.fileReadNoSuchFile) as Error, URLError(.notConnectedToInternet),
                    NSError(domain: "NSFileProviderErrorDomain", code: -1000),
                    NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoPermission.rawValue,
                            userInfo: [NSUnderlyingErrorKey: URLError(.timedOut)])] {
        #expect(!(await fixture.store.removeIfPermissionDenied(source, failure: failure, rootOperation: true)))
        #expect(fixture.store.sources.contains(where: { $0.id == source.id }))
    }
    // A single inaccessible document is not proof that the root grant was revoked.
    #expect(!(await fixture.store.removeIfPermissionDenied(source, failure: CocoaError(.fileReadNoPermission), rootOperation: false)))
    #expect(!(await fixture.store.removeIfPermissionDenied(source, failure: CocoaError(.fileReadNoPermission), rootOperation: true)))
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
    #expect(await fixture.store.removeIfPermissionDenied(source, failure: CocoaError(.fileReadNoPermission), rootOperation: true))
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    #expect(!fixture.store.sources.contains(where: { $0.id == source.id }))
    #expect(fixture.store.document == nil)
    #expect(fixture.defaults.string(forKey: "lastDocument") == nil)
    #expect(try Data(contentsOf: file) == data)
    let restored = ReaderStore(defaults: fixture.defaults)
    #expect(!restored.sources.contains(where: { $0.id == source.id }))
}

@Test @MainActor func unresolvedBookmarkIsRetainedWithoutReauthorization() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let saved = SavedSource(id: UUID(), name: "Temporarily unavailable", bookmark: Data([1, 2, 3]))
    fixture.defaults.set(try JSONEncoder().encode([saved]), forKey: "sources")
    let restored = ReaderStore(defaults: fixture.defaults)
    #expect(restored.sources.contains(where: { $0.id == saved.id }))
}

@MainActor private struct Fixture {
    let root: URL
    let defaults: UserDefaults
    let suite: String
    let store: ReaderStore

    init(github: GitHubReader = GitHubReader()) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "ReaderRefreshTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        store = ReaderStore(defaults: defaults, github: github)
    }

    func clean() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    func add(_ name: String) throws -> FolderSource {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        store.addFolder(url)
        return try #require(store.sources.first(where: { $0.name == name }))
    }

    func waitForReading() async throws {
        for _ in 0..<500 {
            if !store.isLoading { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Document read did not finish within five seconds")
    }
}

@Test @MainActor func refreshUpdatesCurrentDocumentAndOnlyItsSource() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let store = fixture.store
    let source = try fixture.add("First")
    let other = try fixture.add("Other")
    let root = try #require(source.url)
    let otherRoot = try #require(other.url)
    let folder = root.appendingPathComponent("Nested")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("note.md")
    try Data("# Original".utf8).write(to: file)
    try Data("# Other".utf8).write(to: otherRoot.appendingPathComponent("other.md"))
    await store.loadChildren(source: source, directory: root)
    await store.loadChildren(source: other, directory: otherRoot)
    store.open(file, source: source)
    try await fixture.waitForReading()
    #expect(store.document?.rendered.body.contains("Original") == true)
    let folderKey = store.key(source: source, url: folder)
    #expect(store.expanded.contains(folderKey))
    store.recordProgress(0.42, documentKey: try #require(store.document?.key))
    let previousExpanded = store.expanded
    let otherKey = store.key(source: other, url: otherRoot)
    let otherNames = store.nodes[otherKey]?.map(\.name)
    let changed = Data("# Updated externally".utf8)
    try changed.write(to: file)
    try Data("# Added".utf8).write(to: folder.appendingPathComponent("added.md"))

    async let first: Void = store.refresh(source)
    async let duplicate: Void = store.refresh(source)
    _ = await (first, duplicate)

    #expect(store.document?.rendered.body.contains("Updated externally") == true)
    #expect(store.document?.initialProgress == 0.42)
    #expect(store.expanded == previousExpanded)
    #expect(store.nodes[folderKey]?.map(\.name) == ["added.md", "note.md"])
    #expect(store.nodes[otherKey]?.map(\.name) == otherNames)
    #expect(store.sourceVersions[source.id] == 2) // Add and one accepted refresh.
    #expect(store.refreshingSources.isEmpty)
    #expect(try Data(contentsOf: file) == changed)
}

@Test @MainActor func refreshFailureKeepsDirectoryAndDocumentSnapshot() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let store = fixture.store
    let source = try fixture.add("Source")
    let root = try #require(source.url)
    let file = root.appendingPathComponent("note.md")
    try Data("# Keep reading".utf8).write(to: file)
    await store.loadChildren(source: source, directory: root)
    store.open(file, source: source)
    try await fixture.waitForReading()
    let documentID = store.document?.id
    let key = store.key(source: source, url: root)
    let names = store.nodes[key]?.map(\.name)
    try FileManager.default.removeItem(at: root)
    await store.refresh(source)
    #expect(store.error?.contains("已保留之前的内容") == true)
    #expect(store.document?.id == documentID)
    #expect(store.nodes[key]?.map(\.name) == names)
    #expect(store.refreshingSources.isEmpty)
}

@Test @MainActor func removingSourceDuringRefreshCannotRestoreItsState() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let store = fixture.store
    let source = try fixture.add("Source")
    let root = try #require(source.url)
    try Data("# Temporary".utf8).write(to: root.appendingPathComponent("note.md"))
    await store.loadChildren(source: source, directory: root)
    let refresh = Task { await store.refresh(source) }
    await Task.yield()
    store.remove(source)
    await refresh.value
    let prefix = source.id.uuidString + "|"
    #expect(!store.sources.contains(where: { $0.id == source.id }))
    #expect(!store.nodes.keys.contains(where: { $0.hasPrefix(prefix) }))
    #expect(!store.expanded.contains(where: { $0.hasPrefix(prefix) }))
    #expect(!store.refreshingSources.contains(source.id))
    #expect(store.sourceVersions[source.id] == nil)
}

@Test @MainActor func missingCurrentFileUpdatesTreeButKeepsReadableDocument() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let store = fixture.store
    let source = try fixture.add("Source")
    let root = try #require(source.url)
    let file = root.appendingPathComponent("note.md")
    try Data("# Still readable".utf8).write(to: file)
    store.open(file, source: source)
    try await fixture.waitForReading()
    let documentID = store.document?.id
    try FileManager.default.moveItem(at: file, to: root.appendingPathComponent("renamed.md"))
    await store.refresh(source)
    #expect(store.nodes[store.key(source: source, url: root)]?.map(\.name) == ["renamed.md"])
    #expect(store.document?.id == documentID)
    #expect(store.document?.rendered.body.contains("Still readable") == true)
    #expect(store.error?.contains("仍显示上次打开的内容") == true)
    #expect(store.selectedKey == store.document?.key)
    #expect(!store.isLoading)
    #expect(store.refreshingSources.isEmpty)
}

private actor RemoteFixture {
    var version = 1
    var fail = false
    var pause = false
    func change(version: Int? = nil, fail: Bool = false, pause: Bool = false) {
        if let version { self.version = version }
        self.fail = fail; self.pause = pause
    }
    func response(_ request: URLRequest) async throws -> GitHubReader.Response {
        if pause { try await Task.sleep(for: .milliseconds(100)) }
        if fail { return .init(data: Data(), status: 503) }
        let path = request.url!.path(percentEncoded: false)
        let sha = String(repeating: String(version), count: 40)
        var text: String
        if path == "/repos/test/repo" { text = "{\"default_branch\":\"main\"}" }
        else if path == "/repos/test/repo/commits/main" { text = "{\"sha\":\"\(sha)\"}" }
        else if path == "/repos/test/repo/contents/docs" {
            var entries: [[String: String]] = [
                ["name":"nested", "path":"docs/nested", "sha":"x", "type":"dir"],
                ["name":"readme.md", "path":"docs/readme.md", "sha":"x", "type":"file"]
            ]
            if version > 1 { entries.append(["name":"added.md", "path":"docs/added.md", "sha":"x", "type":"file"]) }
            return .init(data: try JSONSerialization.data(withJSONObject: entries), status: 200)
        } else if path.hasSuffix(".md") {
            let ref = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? ""
            text = "# Version \(ref.first.map(String.init) ?? "?")\n\n[Next](nested/linked.md)\n\n![Image](image.png)"
        } else if path == "/repos/test/repo/contents/docs/nested" {
            text = "[{\"name\":\"linked.md\",\"path\":\"docs/nested/linked.md\",\"sha\":\"x\",\"type\":\"file\"}]"
        } else { return .init(data: Data(), status: 404) }
        return .init(data: Data(text.utf8), status: 200)
    }
    nonisolated var reader: GitHubReader { GitHubReader { request, _ in try await self.response(request) } }
}

@Test @MainActor func githubSourcePersistsAndOpensRelativeDocuments() async throws {
    let remote = RemoteFixture()
    let fixture = try Fixture(github: remote.reader)
    defer { fixture.clean() }
    let store = fixture.store
    #expect(await store.addGitHub("https://github.com/test/repo/tree/main/docs", reference: "main"))
    let source = try #require(store.sources.first(where: { $0.remote != nil }))
    let root = try #require(source.url)
    store.open(root.appendingPathComponent("readme.md"), source: source)
    try await fixture.waitForReading()
    #expect(store.document?.rendered.body.contains("Version 1") == true)
    #expect(store.document?.rendered.body.contains("图片暂未加载") == true)
    #expect(store.document?.rendered.body.contains("<img") == false)
    store.open(root.appendingPathComponent("nested/linked.md"), source: source)
    try await fixture.waitForReading()
    #expect(store.expanded.contains(store.key(source: source, url: root.appendingPathComponent("nested"))))
    let restored = ReaderStore(defaults: fixture.defaults, github: remote.reader)
    #expect(restored.sources.contains(where: { $0.id == source.id && $0.remote != nil }))
    restored.restoreLastDocument()
    for _ in 0..<500 where restored.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    #expect(restored.document?.url.lastPathComponent == "linked.md")
    #expect(restored.document?.rendered.body.contains("Version 1") == true)
    #expect(!(await restored.addGitHub("https://github.com/test/repo/tree/main/docs", reference: "main")))
    #expect(restored.sources.filter { $0.remote != nil }.count == 1)
}

@Test @MainActor func githubRefreshPullsNewCommitAndRetainsSnapshotWhenOffline() async throws {
    let remote = RemoteFixture()
    let fixture = try Fixture(github: remote.reader)
    defer { fixture.clean() }
    let store = fixture.store
    #expect(await store.addGitHub("https://github.com/test/repo/tree/main/docs", reference: "main"))
    let source = try #require(store.sources.first)
    let root = try #require(source.url)
    store.open(root.appendingPathComponent("readme.md"), source: source)
    try await fixture.waitForReading()
    store.recordProgress(0.35, documentKey: try #require(store.document?.key))
    let expanded = store.expanded
    await remote.change(version: 2)
    await store.refresh(source)
    #expect(store.document?.rendered.body.contains("Version 2") == true)
    #expect(store.document?.initialProgress == 0.35)
    #expect(store.expanded == expanded)
    let rootKey = store.key(source: source, url: root)
    #expect(store.nodes[rootKey]?.map(\.name) == ["nested", "added.md", "readme.md"])
    let documentID = store.document?.id
    await remote.change(fail: true)
    await store.refresh(source)
    #expect(store.document?.id == documentID)
    #expect(store.nodes[rootKey]?.count == 3)
    #expect(store.error?.contains("已保留之前的内容") == true)
    #expect(store.refreshingSources.isEmpty)
}

@Test @MainActor func githubSingleDocumentOpensAndSourceRemovalWinsOverRefresh() async throws {
    let remote = RemoteFixture()
    let fixture = try Fixture(github: remote.reader)
    defer { fixture.clean() }
    let store = fixture.store
    #expect(await store.addGitHub("https://github.com/test/repo/blob/main/docs/readme.md", reference: "main"))
    try await fixture.waitForReading()
    let source = try #require(store.sources.first)
    let root = try #require(source.url)
    #expect(store.nodes[store.key(source: source, url: root)]?.map(\.name) == ["readme.md"])
    #expect(store.document?.url.lastPathComponent == "readme.md")
    await remote.change(pause: true)
    let task = Task { await store.refresh(source) }
    for _ in 0..<100 where !store.refreshingSources.contains(source.id) { await Task.yield() }
    #expect(store.refreshingSources.contains(source.id))
    store.remove(source)
    await task.value
    #expect(!store.sources.contains(where: { $0.id == source.id }))
    #expect(store.document == nil)
    #expect(!store.nodes.keys.contains(where: { $0.hasPrefix(source.id.uuidString + "|") }))
    #expect(store.refreshingSources.isEmpty)
    let restored = ReaderStore(defaults: fixture.defaults, github: remote.reader)
    #expect(!restored.sources.contains(where: { $0.id == source.id }))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["READER_GITHUB_LIVE"] == "1"))
@MainActor func githubAppStoreReadsPublicDocumentThroughRealAPI() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    #expect(await fixture.store.addGitHub("https://github.com/swiftlang/swift-markdown/blob/main/README.md", reference: "main"))
    try await fixture.waitForReading()
    #expect(fixture.store.error == nil)
    #expect(fixture.store.document?.rendered.body.contains("Markdown") == true)
    #expect(fixture.store.document?.url.lastPathComponent == "README.md")
    #expect(fixture.store.sources.first?.remote != nil)
}

@Test @MainActor func cancellingGitHubAdditionDoesNotPersistASource() async throws {
    let remote = RemoteFixture()
    await remote.change(pause: true)
    let fixture = try Fixture(github: remote.reader)
    defer { fixture.clean() }
    let store = fixture.store
    let task = Task { await store.addGitHub("https://github.com/test/repo/tree/main/docs", reference: "main") }
    for _ in 0..<100 where !store.isAddingGitHub { await Task.yield() }
    #expect(store.isAddingGitHub)
    task.cancel()
    #expect(!(await task.value))
    #expect(!store.sources.contains(where: { $0.remote != nil }))
    #expect(fixture.defaults.data(forKey: "githubSources") == nil)
    #expect(store.error == nil)
    #expect(!store.isAddingGitHub)
}

@Test @MainActor func standaloneFilesKeepExactFileScopeAndNeverModifyOriginals() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let store = fixture.store
    let file = fixture.root.appendingPathComponent("单独 文件.md")
    let sibling = fixture.root.appendingPathComponent("neighbor.md")
    let bytes = Data("# Standalone\n\n![private](image.png)\n\n[neighbor](neighbor.md)".utf8)
    try bytes.write(to: file)
    try Data("# Neighbor".utf8).write(to: sibling)
    store.openFileURL(file)
    try await fixture.waitForReading()
    let document = try #require(store.document)
    #expect(document.isStandalone)
    #expect(document.access.url == file)
    #expect(document.rendered.body.contains("<img") == false)
    #expect(throws: ReaderError.self) { try LocalDocuments.confined(sibling, to: document.access.url) }
    #expect(store.sources.isEmpty)
    #expect(store.recentFiles.count == 1)
    store.removeRecent(try #require(store.recentFiles.first))
    #expect(store.document == nil)
    #expect(store.recentFiles.isEmpty)
    #expect(try Data(contentsOf: file) == bytes)
    #expect(FileManager.default.fileExists(atPath: sibling.path))
}

@Test @MainActor func standaloneBookmarksReuseRecordsAndRestoreProgress() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let store = fixture.store
    let file = fixture.root.appendingPathComponent("recent.markdown")
    try Data("# Recent".utf8).write(to: file)
    store.openFileURL(file)
    try await fixture.waitForReading()
    let original = try #require(store.document)
    store.recordProgress(0.37, documentKey: original.key)
    store.openFileURL(file)
    try await fixture.waitForReading()
    #expect(store.recentFiles.count == 1)
    #expect(store.document?.key == original.key)
    #expect(store.document?.initialProgress == 0.37)
    let restored = ReaderStore(defaults: fixture.defaults)
    restored.restoreLastDocument()
    for _ in 0..<500 where restored.isLoading { try await Task.sleep(for: .milliseconds(10)) }
    #expect(restored.document?.isStandalone == true)
    #expect(restored.document?.key == original.key)
    #expect(restored.document?.initialProgress == 0.37)
}

@Test @MainActor func externalFilesReuseGrantedFoldersAndNewRequestsWin() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let store = fixture.store
    let source = try fixture.add("Existing")
    let file = try #require(source.url).appendingPathComponent("in-folder.md")
    try Data("# Existing folder".utf8).write(to: file)
    store.openFileURL(file)
    try await fixture.waitForReading()
    #expect(store.document?.sourceID == source.id)
    #expect(store.document?.isStandalone == false)
    #expect(store.recentFiles.isEmpty)
    let first = fixture.root.appendingPathComponent("first.md")
    let latest = fixture.root.appendingPathComponent("latest.md")
    try Data("# First".utf8).write(to: first)
    try Data("# Latest".utf8).write(to: latest)
    store.openFileURL(first)
    store.openFileURL(latest)
    store.restoreLastDocument() // A late startup task must not replace the external URL.
    try await fixture.waitForReading()
    #expect(store.document?.url == latest)
    #expect(store.document?.rendered.body.contains("Latest") == true)
    #expect(store.recentFiles.count == 1)
    store.openFileURL(URL(string: "https://example.com/remote.md")!)
    #expect(store.document?.url == latest)
    #expect(store.error != nil)
}

@Test @MainActor func missingStandaloneFilesRetainTheirRecentRecord() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let store = fixture.store
    let file = fixture.root.appendingPathComponent("moved.md")
    try Data("# Kept".utf8).write(to: file)
    store.openFileURL(file)
    try await fixture.waitForReading()
    let id = store.document?.id
    let recent = try #require(store.recentFiles.first)
    try FileManager.default.removeItem(at: file)
    store.openRecent(recent)
    try await fixture.waitForReading()
    #expect(store.recentFiles.count == 1)
    #expect(store.document?.id == id)
    #expect(store.error != nil)
}

@Test @MainActor func explicitlyAddingContainingFolderUpgradesTheOpenFileScope() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let store = fixture.store
    let file = fixture.root.appendingPathComponent("note.md")
    try Data("# Scope upgrade\n\n![picture](picture.png)".utf8).write(to: file)
    store.openFileURL(file)
    try await fixture.waitForReading()
    #expect(store.document?.isStandalone == true)
    store.recordProgress(0.23, documentKey: try #require(store.document?.key))
    store.addFolder(fixture.root)
    try await fixture.waitForReading()
    #expect(store.document?.isStandalone == false)
    #expect(store.document?.access.url == fixture.root)
    #expect(store.document?.initialProgress == 0.23)
    #expect(store.document?.rendered.body.contains("<img") == true)
}

@Test @MainActor func clearingRecentsPreservesReadingAndFilesButClearsPersistedHistory() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let store = fixture.store
    let first = fixture.root.appendingPathComponent("first.md")
    let second = fixture.root.appendingPathComponent("second.md")
    let bytes = Data("# Unchanged".utf8)
    try bytes.write(to: first)
    try bytes.write(to: second)
    store.openFileURL(first)
    try await fixture.waitForReading()
    store.openFileURL(second)
    try await fixture.waitForReading()
    let documentID = store.document?.id
    store.clearRecentFiles()
    #expect(store.recentFiles.isEmpty)
    #expect(store.document?.id == documentID)
    #expect(ReaderStore(defaults: fixture.defaults).recentFiles.isEmpty)
    #expect(fixture.defaults.string(forKey: "lastDocument") == nil)
    #expect(try Data(contentsOf: first) == bytes)
    #expect(try Data(contentsOf: second) == bytes)
    store.openFileURL(first)
    store.clearRecentFiles()
    try await Task.sleep(for: .milliseconds(100))
    #expect(store.recentFiles.isEmpty)
    #expect(store.document?.id == documentID)
}

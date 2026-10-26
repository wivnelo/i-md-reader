import Foundation
import Testing
@testable import ReaderCore

private actor OfflineServer {
    var offline = false
    var status = 200
    var conditional = false
    var requests: [URLRequest] = []
    func configure(offline: Bool = false, status: Int = 200, conditional: Bool = false) {
        self.offline = offline; self.status = status; self.conditional = conditional
    }
    func fetch(_ request: URLRequest) throws -> GitHubReader.Response {
        requests.append(request)
        if offline { throw URLError(.notConnectedToInternet) }
        if status != 200 { return .init(data: Data(), status: status) }
        if conditional && request.value(forHTTPHeaderField: "If-None-Match") == "test-etag" {
            return .init(data: Data(), status: 304)
        }
        let path = request.url!.path
        let text: String
        if path == "/repos/test/repo" { text = "{\"default_branch\":\"main\"}" }
        else if path.contains("/commits/") { text = "{\"sha\":\"" + String(repeating: "a", count: 40) + "\"}" }
        else if path.hasSuffix("/contents") { text = "[{\"name\":\"note.md\",\"path\":\"note.md\",\"type\":\"file\",\"sha\":\"x\"}]" }
        else if path.hasSuffix(".png") { return .init(data: Data([137, 80, 78, 71]), status: 200) }
        else { text = "# Private offline marker" }
        return .init(data: Data(text.utf8), status: 200, headers: ["ETag": "test-etag"])
    }
    nonisolated func reader(cache: GitHubOfflineCache, token: String? = nil) -> GitHubReader {
        GitHubReader(token: token, offlineCache: cache) { request, _ in try await self.fetch(request) }
    }
}

private func cacheRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
private func savedFiles(_ root: URL) -> [URL] {
    let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    return (items?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "cache" }
}

@Test func restartsOfflineWithPinnedArticleDirectoryAndImage() async throws {
    let root = cacheRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let server = OfflineServer()
    let online = server.reader(cache: GitHubOfflineCache(directory: root))
    let link = try GitHubLink("https://github.com/test/repo")
    let location = try await online.resolve(link)
    _ = try await online.children(location)
    let text = try await online.markdown(location, path: "note.md")
    let image = try await online.image(location, path: "image.png")
    await server.configure(offline: true)
    // New cache and reader instances represent a completely new app process.
    let reopened = server.reader(cache: GitHubOfflineCache(directory: root))
    let restored = try await reopened.resolve(link)
    #expect(restored.commit == location.commit)
    #expect(try await reopened.children(restored).first?.name == "note.md")
    #expect(try await reopened.markdown(restored, path: "note.md") == text)
    #expect(try await reopened.image(restored, path: "image.png") == image)
    #expect(await reopened.isUsingOfflineCache)
    await #expect(throws: GitHubReadError.offlineNotCached) { try await reopened.markdown(restored, path: "unread.md") }
}

@Test func privateDiskRecordsAreEncryptedIsolatedAndRemovedOnRevocation() async throws {
    let root = cacheRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let cache = GitHubOfflineCache(directory: root)
    let server = OfflineServer()
    let token = "github_pat_synthetic_offline_identity"
    let reader = server.reader(cache: cache, token: token)
    let link = try GitHubLink("https://github.com/test/repo")
    let location = try await reader.resolve(link)
    _ = try await reader.markdown(location, path: "note.md")
    let files = savedFiles(root)
    #expect(!files.isEmpty)
    for file in files {
        let bytes = try Data(contentsOf: file)
        #expect(bytes.range(of: Data("Private offline marker".utf8)) == nil)
        #expect(bytes.range(of: Data(token.utf8)) == nil)
        #expect(bytes.range(of: Data("test/repo".utf8)) == nil)
    }
    await server.configure(offline: true)
    let other = server.reader(cache: cache, token: "github_pat_synthetic_other_identity")
    await #expect(throws: GitHubReadError.offlineNotCached) { try await other.resolve(link) }
    #expect(await reader.invalidate())
    #expect(savedFiles(root).isEmpty)
    let sameTokenAgain = server.reader(cache: cache, token: token)
    await #expect(throws: GitHubReadError.offlineNotCached) { try await sameTokenAgain.resolve(link) }
}

@Test func metadataUsesConditionalRequestsButNeverFallsBackOnPermissionErrors() async throws {
    let root = cacheRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let cache = GitHubOfflineCache(directory: root)
    let server = OfflineServer()
    let link = try GitHubLink("https://github.com/test/repo")
    _ = try await server.reader(cache: cache).resolve(link)
    await server.configure(conditional: true)
    let refreshed = server.reader(cache: cache)
    _ = try await refreshed.resolve(link)
    #expect(!(await refreshed.isUsingOfflineCache))
    #expect(await server.requests.contains { $0.value(forHTTPHeaderField: "If-None-Match") == "test-etag" })
    await server.configure(status: 403)
    await #expect(throws: GitHubReadError.unauthorized) { try await server.reader(cache: cache).resolve(link) }
    await server.configure(status: 404)
    await #expect(throws: GitHubReadError.notFound) { try await server.reader(cache: cache).resolve(link) }
}

@Test func cacheEnforcesCapacityAndTreatsCorruptRecordsAsMissing() async throws {
    let root = cacheRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let cache = GitHubOfflineCache(directory: root, capacity: 1_500)
    let session = UUID()
    for index in 0..<10 {
        let key = "key-\(index)"
        let lookup = await cache.lookup(key, token: nil, session: session)
        await cache.store(.init(data: Data(repeating: 65, count: 400), status: 200), key: key, token: nil, session: session, revision: lookup.revision)
    }
    let usage = await cache.usage()
    #expect(usage.bytes <= 1_500)
    #expect(usage.count < 10 && usage.count > 0)
    #expect(await cache.lookup("key-0", token: nil, session: session).response == nil)
    for file in savedFiles(root) { try Data("broken".utf8).write(to: file) }
    #expect(await cache.lookup("key-9", token: nil, session: session).response == nil)
    await cache.setCapacity(0)
    #expect(await cache.usage().bytes == 0)
}

@Test func clearingCachePreventsSlowResponsesFromWritingAfterClear() async throws {
    actor Gate {
        var continuation: CheckedContinuation<Void, Never>?
        var started = false
        func fetch() async -> GitHubReader.Response {
            started = true
            await withCheckedContinuation { continuation = $0 }
            return .init(data: Data("old response".utf8), status: 200)
        }
        func release() { continuation?.resume(); continuation = nil }
    }
    let root = cacheRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let cache = GitHubOfflineCache(directory: root)
    let gate = Gate()
    let reader = GitHubReader(offlineCache: cache) { _, _ in await gate.fetch() }
    let location = GitHubLocation(link: try GitHubLink("https://github.com/test/repo"), reference: "main", commit: String(repeating: "a", count: 40), path: "")
    let task = Task { try await reader.markdown(location, path: "note.md") }
    while !(await gate.started) { await Task.yield() }
    try await reader.clearOfflineCache()
    await gate.release()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await cache.usage().bytes == 0)
}

@Test func repositoryRemovalAndRejectedTokenPurgePersistedContent() async throws {
    let root = cacheRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let cache = GitHubOfflineCache(directory: root)
    let server = OfflineServer()
    let link = try GitHubLink("https://github.com/test/repo")
    let reader = server.reader(cache: cache, token: "github_pat_synthetic_rejected_offline")
    let location = try await reader.resolve(link)
    _ = try await reader.markdown(location, path: "note.md")
    await reader.removeOfflineRepository(link)
    #expect(await cache.usage().bytes == 0)
    _ = try await reader.resolve(link)
    await server.configure(status: 401)
    await #expect(throws: GitHubReadError.credentialRejected) { try await reader.resolve(link) }
    #expect(await cache.usage().bytes == 0)
}

@Test func diskFailureDoesNotBreakSuccessfulOnlineReading() async throws {
    let root = cacheRoot(); defer { try? FileManager.default.removeItem(at: root) }
    try Data("not a directory".utf8).write(to: root)
    let server = OfflineServer()
    let reader = server.reader(cache: GitHubOfflineCache(directory: root))
    #expect(try await reader.resolve(GitHubLink("https://github.com/test/repo")).reference == "main")
}

@Test func rateLimitUsesSavedMetadataWithoutRepeatingRequestsDuringCooldown() async throws {
    let root = cacheRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let cache = GitHubOfflineCache(directory: root)
    let server = OfflineServer()
    let link = try GitHubLink("https://github.com/test/repo")
    _ = try await server.reader(cache: cache).resolve(link)
    await server.configure(status: 429)
    let limited = server.reader(cache: cache)
    _ = try await limited.resolve(link)
    #expect(await limited.isUsingOfflineCache)
    let count = await server.requests.count
    _ = try await limited.resolve(link)
    #expect(await server.requests.count == count)
}

@Test func oldCacheTicketsCannotWriteAfterRevocationOrGlobalClear() async throws {
    let root = cacheRoot(); defer { try? FileManager.default.removeItem(at: root) }
    let cache = GitHubOfflineCache(directory: root)
    let session = UUID()
    let token = "github_pat_synthetic_cache_ticket"
    let lookup = await cache.lookup("key", token: token, session: session)
    try await cache.revoke(token: token, session: session)
    await cache.store(.init(data: Data("private".utf8), status: 200), key: "key", token: token, session: session, revision: lookup.revision)
    #expect(await cache.usage().bytes == 0)
    let newSession = UUID()
    let beforeClear = await cache.lookup("key", token: nil, session: newSession)
    try await cache.clear()
    await cache.store(.init(data: Data("old".utf8), status: 200), key: "key", token: nil, session: newSession, revision: beforeClear.revision)
    #expect(await cache.usage().bytes == 0)
}

import Foundation
import Testing
@testable import ReaderCore

private actor RequestCounter {
    var count = 0
    let reset = Date().addingTimeInterval(300)
    func fetch(_ request: URLRequest) async throws -> GitHubReader.Response {
        count += 1
        try await Task.sleep(for: .milliseconds(20))
        if request.url!.path.contains("limited") {
            return .init(data: Data(), status: 403, headers: ["X-RateLimit-Remaining":"0", "X-RateLimit-Reset":String(Int(reset.timeIntervalSince1970))])
        }
        return .init(data: Data("# Cached".utf8), status: 200)
    }
    nonisolated var reader: GitHubReader { GitHubReader { request, _ in try await self.fetch(request) } }
}

private func requestLocation(_ sha: String = String(repeating: "a", count: 40)) throws -> GitHubLocation {
    GitHubLocation(link: try GitHubLink("https://github.com/test/repo"), reference: "main", commit: sha, path: "")
}

@Test func coalescesConcurrentReadsAndReusesOnlyThePinnedCommit() async throws {
    let counter = RequestCounter()
    let reader = counter.reader
    let location = try requestLocation()
    async let first = reader.markdown(location, path: "note.md")
    async let second = reader.markdown(location, path: "note.md")
    let texts = try await (first, second)
    #expect(texts.0 == "# Cached")
    #expect(texts.1 == texts.0)
    #expect(await counter.count == 1)
    _ = try await reader.markdown(location, path: "note.md")
    #expect(await counter.count == 1)
    _ = try await reader.markdown(requestLocation(String(repeating: "b", count: 40)), path: "note.md")
    #expect(await counter.count == 2)
}

@Test func rateLimitCooldownStopsRequestsButAllowsAlreadyReadContent() async throws {
    let counter = RequestCounter()
    let reader = counter.reader
    let location = try requestLocation()
    _ = try await reader.markdown(location, path: "note.md")
    for _ in 0..<2 {
        do {
            _ = try await reader.markdown(location, path: "limited.md")
            Issue.record("Expected rate limiting")
        } catch GitHubReadError.rateLimitedUntil(let date) {
            #expect(date.timeIntervalSinceNow > 200)
        }
    }
    #expect(await counter.count == 2)
    #expect(try await reader.markdown(location, path: "note.md") == "# Cached")
    #expect(await counter.count == 2)
}

@Test func immutableCacheEvictsResponsesAboveItsMemoryBudget() async throws {
    actor LargeCounter {
        var count = 0
        func fetch() -> GitHubReader.Response {
            count += 1
            return .init(data: Data(repeating: 65, count: 9 * 1_024 * 1_024), status: 200)
        }
    }
    let counter = LargeCounter()
    let reader = GitHubReader { _, _ in await counter.fetch() }
    let location = try requestLocation()
    for index in 0..<4 { _ = try await reader.markdown(location, path: "\(index).md") }
    #expect(await counter.count == 4)
    _ = try await reader.markdown(location, path: "0.md")
    #expect(await counter.count == 5)
}

@Test func authenticatedReadsStayOnGitHubAndSessionsDoNotShareContent() async throws {
    actor Recorder {
        var requests: [URLRequest] = []
        func fetch(_ request: URLRequest) -> GitHubReader.Response {
            requests.append(request)
            return .init(data: Data((request.value(forHTTPHeaderField: "Authorization") ?? "anonymous").utf8), status: 200)
        }
    }
    let log = Recorder()
    let first = GitHubReader(token: "github_pat_synthetic_first") { request, _ in await log.fetch(request) }
    let second = GitHubReader(token: "github_pat_synthetic_second") { request, _ in await log.fetch(request) }
    let anonymous = GitHubReader { request, _ in await log.fetch(request) }
    let location = try requestLocation()
    #expect(try await first.markdown(location, path: "note.md") == "Bearer github_pat_synthetic_first")
    #expect(try await second.markdown(location, path: "note.md") == "Bearer github_pat_synthetic_second")
    #expect(try await anonymous.markdown(location, path: "note.md") == "anonymous")
    let requests = await log.requests
    #expect(requests.count == 3)
    #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.host == "api.github.com" && $0.url?.scheme == "https" })
    #expect(requests.allSatisfy { $0.url?.absoluteString.contains("synthetic") == false })
    await first.invalidate()
    await #expect(throws: CancellationError.self) { try await first.markdown(location, path: "note.md") }
    #expect(await log.requests.count == 3)
}

@Test func invalidationRejectsUncooperativeInFlightResponsesAndImages() async throws {
    actor Gate {
        var started = false
        var continuation: CheckedContinuation<Void, Never>?
        func fetch() async -> GitHubReader.Response {
            started = true
            await withCheckedContinuation { continuation = $0 }
            return .init(data: Data("private response".utf8), status: 200)
        }
        func release() { continuation?.resume(); continuation = nil }
    }
    let gate = Gate()
    let reader = GitHubReader(token: "github_pat_synthetic_pending") { _, _ in await gate.fetch() }
    let location = try requestLocation()
    let request = Task { try await reader.markdown(location, path: "note.md") }
    while !(await gate.started) { await Task.yield() }
    await reader.invalidate()
    await gate.release()
    await #expect(throws: CancellationError.self) { try await request.value }
    await #expect(throws: CancellationError.self) { try await reader.image(location, path: "image.png") }
}

@Test func malformedCredentialNeverReachesTransport() async throws {
    let reader = GitHubReader(token: "bad\r\nheader") { _, _ in
        Issue.record("Malformed credentials must not be sent")
        return .init(data: Data(), status: 200)
    }
    await #expect(throws: GitHubReadError.unauthorized) { try await reader.markdown(requestLocation(), path: "note.md") }
}

@Test func clearingMemoryRemovesPrivateResponsesWithoutDroppingCredential() async throws {
    let counter = RequestCounter()
    let reader = counter.reader
    let location = try requestLocation()
    _ = try await reader.markdown(location, path: "note.md")
    await reader.clearMemoryCache()
    _ = try await reader.markdown(location, path: "note.md")
    #expect(await counter.count == 2)
}

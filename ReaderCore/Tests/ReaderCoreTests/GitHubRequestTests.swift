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

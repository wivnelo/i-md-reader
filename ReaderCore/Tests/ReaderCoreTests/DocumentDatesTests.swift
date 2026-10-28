import Foundation
import Testing
@testable import ReaderCore

@Test func fileDatesAreProviderValuesAndMissingDatesStayEmpty() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(DocumentDates.local(url) == DocumentDates())
    try Data("# Sample".utf8).write(to: url)
    let modified = Date(timeIntervalSince1970: 1_700_000_000)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    #expect(DocumentDates.local(url).modified == modified)
    #expect(DocumentDates().labels(language: "en").isEmpty)
}

@Test func datesLocalizeAndRespectTimeZoneAcrossMidnight() {
    let date = Date(timeIntervalSince1970: 0)
    let dates = DocumentDates(modified: date)
    let english = dates.labels(language: "en", timeZone: TimeZone(secondsFromGMT: -8 * 3600)!)
    let chinese = dates.labels(language: "zh-Hans", timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
    #expect(english[0].hasPrefix("Changed ·") && english[0].contains("Dec 31, 1969 16:00"))
    #expect(chinese[0].hasPrefix("变更时间 ·") && chinese[0].contains("1970年1月1日 08:00"))
    #expect(chinese.count == 1 && english.count == 1)
    let remote = DocumentDates(modified: Date(), committed: date)
    let remoteEN = remote.labels(language: "en", timeZone: TimeZone(secondsFromGMT: 0)!)
    let remoteZH = remote.labels(language: "zh-Hans", timeZone: TimeZone(secondsFromGMT: 0)!)
    #expect(remoteEN.count == 1 && remoteEN[0].hasPrefix("Changed (commit · current revision)"))
    #expect(remoteZH.count == 1 && remoteZH[0].hasPrefix("变更时间（提交 · 当前版本）"))
    #expect(remoteEN[0].contains("Jan 1, 1970")) // One authoritative value, never two rows.
}

private actor HistoryTransport {
    var calls = 0
    func response(_ request: URLRequest) throws -> GitHubReader.Response {
        calls += 1
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(query.first(where: { $0.name == "sha" })?.value == String(repeating: "a", count: 40))
        #expect(query.first(where: { $0.name == "path" })?.value == "notes/中文 & a.md")
        #expect(query.first(where: { $0.name == "per_page" })?.value == "1")
        return .init(data: Data(#"[{"commit":{"committer":{"date":"2026-10-28T23:30:00+08:00"}}}]"#.utf8), status: 200)
    }
}

@Test func historyUsesPinnedPathAndSurvivesOfflineRestart() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let cache = GitHubOfflineCache(directory: folder)
    let transport = HistoryTransport()
    let reader = GitHubReader(token: "test_token", offlineCache: cache) { request, _ in try await transport.response(request) }
    let location = GitHubLocation(link: try GitHubLink("https://github.com/test/repo"), reference: "main", commit: String(repeating: "a", count: 40), path: "")
    let expected = ISO8601DateFormatter().date(from: "2026-10-28T15:30:00Z")
    #expect(try await reader.latestCommitDate(location, path: "notes/中文 & a.md") == expected)
    #expect(try await reader.latestCommitDate(location, path: "notes/中文 & a.md") == expected)
    #expect(await transport.calls == 1)
    let offline = GitHubReader(token: "test_token", offlineCache: cache) { _, _ in throw URLError(.notConnectedToInternet) }
    #expect(try await offline.latestCommitDate(location, path: "notes/中文 & a.md") == expected)
}

@Test func missingMalformedAndRateLimitedHistoryNeverInventDates() async throws {
    let location = GitHubLocation(link: try GitHubLink("https://github.com/test/repo"), reference: "main", commit: String(repeating: "a", count: 40), path: "")
    let empty = GitHubReader { _, _ in .init(data: Data("[]".utf8), status: 200) }
    #expect(try await empty.latestCommitDate(location, path: "a.md") == nil)
    let malformed = GitHubReader { _, _ in .init(data: Data(#"[{"commit":{"committer":{"date":"bad"}}}]"#.utf8), status: 200) }
    await #expect(throws: GitHubReadError.invalidResponse) { try await malformed.latestCommitDate(location, path: "a.md") }
    let limited = GitHubReader { _, _ in .init(data: Data(), status: 429) }
    await #expect(throws: (any Error).self) { try await limited.latestCommitDate(location, path: "a.md") }
}

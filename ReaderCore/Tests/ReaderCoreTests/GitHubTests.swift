import Foundation
import Testing
@testable import ReaderCore

private let commitSHA = String(repeating: "a", count: 40)
private func response(_ value: String, status: Int = 200, headers: [String: String] = [:]) -> GitHubReader.Response {
    .init(data: Data(value.utf8), status: status, headers: headers)
}

@Test func acceptsOnlySupportedGitHubURLs() throws {
    let repo = try GitHubLink(" https://github.com/octocat/Hello-World.git/ ")
    #expect(repo.owner == "octocat")
    #expect(repo.repository == "Hello-World")
    #expect(repo.kind == .repository)
    let document = try GitHubLink("https://github.com/owner/repo/blob/feature/topic/中文%20笔记.md#标题")
    #expect(document.components == ["feature", "topic", "中文 笔记.md"])
    for invalid in [
        "http://github.com/o/r", "https://github.com.evil.example/o/r", "https://github.com@evil.example/o/r",
        "https://user:secret@github.com/o/r", "https://github.com:443/o/r", "https://github.com/o/r?token=secret",
        "https://github.com/o/r/issues/1", "https://github.com/o/r/blob/main/a.pdf", "https://github.com/o//r",
        "https://github.com/o/r/tree/main/%2e%2e", "https://github.com/o/r/tree/main/a%2fb", "https://github.com/o/r/tree/main/%00"
    ] { #expect(throws: GitHubReadError.self) { try GitHubLink(invalid) } }
}

@Test func resolvesSlashBranchAndDetectsAmbiguity() async throws {
    let link = try GitHubLink("https://github.com/o/r/blob/feature/topic/notes/a.md")
    let reader = GitHubReader { request, _ in
        #expect(request.httpMethod == "GET")
        #expect(request.url?.host == "api.github.com")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        if request.url?.path(percentEncoded: false) == "/repos/o/r/commits/feature/topic" {
            return response("{\"sha\":\"\(commitSHA)\"}")
        }
        return response("{}", status: 422)
    }
    let location = try await reader.resolve(link)
    #expect(location.reference == "feature/topic")
    #expect(location.path == "notes/a.md")
    #expect(location.commit == commitSHA)
    let ambiguous = GitHubReader { _, _ in response("{\"sha\":\"\(commitSHA)\"}") }
    await #expect(throws: GitHubReadError.ambiguousReference) { try await ambiguous.resolve(link) }
    let explicit = try await ambiguous.resolve(link, explicitReference: "feature/topic")
    #expect(explicit.path == "notes/a.md")
    let repositoryRef = try await ambiguous.resolve(GitHubLink("https://github.com/o/r"), explicitReference: "feature/topic")
    #expect(repositoryRef.reference == "feature/topic")
    #expect(repositoryRef.path.isEmpty)
    await #expect(throws: GitHubReadError.invalidPath) { try await ambiguous.resolve(link, explicitReference: "other") }
}

@Test func resolvesDefaultBranchAndReadsPinnedUTF8Markdown() async throws {
    let reader = GitHubReader { request, _ in
        let path = request.url!.path(percentEncoded: false)
        switch path {
        case "/repos/o/r": return response("{\"default_branch\":\"main\"}")
        case "/repos/o/r/commits/main": return response("{\"sha\":\"\(commitSHA)\"}")
        case "/repos/o/r/contents/中文 笔记.md":
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw+json")
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == commitSHA)
            return response("# 远程正文\n\nHello")
        default: Issue.record("Unexpected endpoint: \(path)"); return response("{}", status: 404)
        }
    }
    let location = try await reader.resolve(GitHubLink("https://github.com/o/r"))
    #expect(location.reference == "main")
    #expect(try await reader.markdown(location, path: "中文 笔记.md") == "# 远程正文\n\nHello")
    await #expect(throws: GitHubReadError.invalidPath) { try await reader.markdown(location, path: "../escape.md") }
}

@Test func listsOnlyMarkdownAndDirectoriesWithoutFollowingDownloadURLs() async throws {
    let reader = GitHubReader { request, _ in
        #expect(request.url?.host == "api.github.com")
        if request.url?.path.contains("commits") == true { return response("{\"sha\":\"\(commitSHA)\"}") }
        return response("""
        [
          {"name":"z.md","path":"docs/z.md","sha":"1","type":"file","download_url":"https://evil.example/file"},
          {"name":"A","path":"docs/A","sha":"2","type":"dir"},
          {"name":"photo.png","path":"docs/photo.png","sha":"3","type":"file"},
          {"name":"link.md","path":"docs/link.md","sha":"4","type":"symlink"},
          {"name":"module.md","path":"docs/module.md","sha":"5","type":"file","submodule_git_url":"https://example.com/git"}
        ]
        """)
    }
    let location = try await reader.resolve(GitHubLink("https://github.com/o/r/tree/main/docs"), explicitReference: "main")
    #expect(try await reader.children(location).map(\.name) == ["A", "photo.png", "z.md"])
    let invalid = GitHubReader { _, _ in response("[{\"name\":\"a.md\",\"path\":\"../a.md\",\"sha\":\"1\",\"type\":\"file\"}]") }
    await #expect(throws: GitHubReadError.invalidResponse) { try await invalid.children(location) }
}

@Test func classifiesGitHubErrorsWithoutIncludingResponseBodies() async throws {
    let location = GitHubLocation(link: try GitHubLink("https://github.com/o/r"), reference: "main", commit: commitSHA, path: "")
    let cases: [(Int, [String: String], GitHubReadError)] = [
        (401, [:], .unauthorized), (403, [:], .unauthorized), (404, [:], .notFound),
        (403, ["X-RateLimit-Remaining":"0"], .rateLimited), (403, ["Retry-After":"30"], .rateLimited),
        (429, [:], .rateLimited), (500, [:], .http(500)), (302, [:], .http(302))
    ]
    for (status, headers, expected) in cases {
        let reader = GitHubReader { _, _ in response("untrusted private error body", status: status, headers: headers) }
        do {
            _ = try await reader.children(location)
            Issue.record("Expected a GitHub error")
        } catch let actual as GitHubReadError {
            if expected.isRateLimited { #expect(actual.isRateLimited) }
            else { #expect(actual == expected) }
        }
        #expect(!expected.localizedDescription.contains("untrusted"))
    }
    let malformed = GitHubReader { _, _ in response("not json") }
    await #expect(throws: GitHubReadError.invalidResponse) { try await malformed.children(location) }
}

@Test func refusesOversizedResponsesAndPossiblyTruncatedDirectories() async throws {
    let location = GitHubLocation(link: try GitHubLink("https://github.com/o/r"), reference: "main", commit: commitSHA, path: "")
    let large = GitHubReader { _, limit in .init(data: Data(repeating: 0, count: limit + 1), status: 200) }
    await #expect(throws: GitHubReadError.responseTooLarge) { try await large.markdown(location, path: "large.md") }
    let entries = (0..<1_000).map { "{\"name\":\"\($0).md\",\"path\":\"\($0).md\",\"sha\":\"1\",\"type\":\"file\"}" }.joined(separator: ",")
    let crowded = GitHubReader { _, _ in response("[" + entries + "]") }
    await #expect(throws: GitHubReadError.directoryLimit) { try await crowded.children(location) }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["READER_GITHUB_LIVE"] == "1"))
func readsPublicGitHubThroughRealTransport() async throws {
    let reader = GitHubReader()
    let location = try await reader.resolve(GitHubLink("https://github.com/swiftlang/swift-markdown"))
    let entries = try await reader.children(location)
    #expect(!entries.isEmpty)
    let document = try await reader.resolve(GitHubLink("https://github.com/swiftlang/swift-markdown/blob/main/README.md"), explicitReference: "main")
    let directory = try await reader.resolve(GitHubLink("https://github.com/swiftlang/swift-markdown/tree/main/Sources"))
    #expect(directory.path == "Sources")
    let text = try await reader.markdown(document)
    #expect(text.contains("Markdown"))
}

@Test func repositoryImagesUsePinnedCommitAndBoundedRawRequest() async throws {
    let bytes = Data([137, 80, 78, 71, 13, 10, 26, 10])
    let reader = GitHubReader { request, limit in
        #expect(request.url?.host == "api.github.com")
        #expect(request.url?.path == "/repos/o/r/contents/docs/图.png")
        #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == commitSHA)
        #expect(limit == 8 * 1_024 * 1_024)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw+json")
        return .init(data: bytes, status: 200, headers: [:])
    }
    let location = GitHubLocation(link: try GitHubLink("https://github.com/o/r"), reference: "main", commit: commitSHA, path: "")
    #expect(try await reader.image(location, path: "docs/图.png") == bytes)
    for path in ["../secret.png", "a/../../secret.png", "a.svg", "a.md"] {
        await #expect(throws: (any Error).self) { try await reader.image(location, path: path) }
    }
}

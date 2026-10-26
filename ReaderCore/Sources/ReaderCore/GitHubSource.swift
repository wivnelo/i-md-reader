import Foundation

public enum GitHubReadError: LocalizedError, Equatable {
    case invalidURL, invalidPath, ambiguousReference, missingReference, directoryLimit
    case offlineNotCached, credentialRejected, unauthorized, notFound, rateLimited, responseTooLarge, invalidResponse, http(Int)
    case rateLimitedUntil(Date)
    public var isRateLimited: Bool {
        switch self { case .rateLimited, .rateLimitedUntil: true; default: false }
    }
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "请输入 github.com 的 HTTPS 仓库、目录或 Markdown 文件链接。"
        case .invalidPath: "仓库路径无效或包含不支持的路径段。"
        case .ambiguousReference: "链接的分支与路径有歧义，请明确指定分支或标签。"
        case .missingReference: "未找到链接对应的分支、标签或提交。"
        case .directoryLimit: "目录达到 GitHub Contents API 的 1,000 项上限，暂不能保证完整展示。"
        case .offlineNotCached: "网络不可用，且此内容尚未缓存。请联网打开一次后再离线阅读。"
        case .credentialRejected: "GitHub 授权已失效，请重新保存令牌。"
        case .unauthorized: "无法读取此仓库，请检查 GitHub 授权是否有效及所选仓库的读取权限。"
        case .notFound: "未找到仓库或文件，也可能没有访问权限。"
        case .rateLimited: "GitHub 请求过于频繁，请至少等待一分钟后再试。"
        case .rateLimitedUntil(let date):
            "GitHub 访问额度暂不可用，请在 \(date.formatted(date: .omitted, time: .shortened)) 后重试。"
        case .responseTooLarge: "远程内容超过原型的大小保护上限。"
        case .invalidResponse: "GitHub 返回了无法识别的内容。"
        case .http(let status): "GitHub 请求失败（\(status)）。"
        }
    }
}

/// Preserve unresolved ref/path components: a slash in a branch name must never
/// silently turn into a directory name. Resolution checks every possible split.
public struct GitHubLink: Sendable, Equatable {
    public enum Kind: Sendable { case repository, directory, document }
    public let owner: String
    public let repository: String
    public let kind: Kind
    public let components: [String]

    public init(_ text: String) throws {
        // Encode Unicode before Foundation parsing so mixed Unicode and existing
        // percent escapes are not double encoded. Decode each path segment once.
        let allowedURL = CharacterSet.urlFragmentAllowed.union(CharacterSet(charactersIn: "%#[]"))
        guard let encoded = text.trimmingCharacters(in: .whitespacesAndNewlines).addingPercentEncoding(withAllowedCharacters: allowedURL),
              let url = URLComponents(string: encoded),
              url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil else { throw GitHubReadError.invalidURL }
        let raw = url.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        var parts = Array(raw.dropFirst())
        if parts.last == "" { parts.removeLast() }
        let decoded = try parts.map { part -> String in
            guard let value = String(part).removingPercentEncoding, Self.validSegment(value) else { throw GitHubReadError.invalidPath }
            return value
        }
        guard decoded.count >= 2 else { throw GitHubReadError.invalidURL }
        owner = decoded[0]
        repository = decoded[1].hasSuffix(".git") ? String(decoded[1].dropLast(4)) : decoded[1]
        guard !repository.isEmpty else { throw GitHubReadError.invalidURL }
        if decoded.count == 2 { kind = .repository; components = []; return }
        guard decoded.count >= 4, ["tree", "blob"].contains(decoded[2]) else { throw GitHubReadError.invalidURL }
        kind = decoded[2] == "tree" ? .directory : .document
        components = Array(decoded.dropFirst(3))
        guard components.count <= 16 else { throw GitHubReadError.invalidPath }
        if kind == .document {
            guard components.count >= 2,
                  LocalDocuments.markdownExtensions.contains((components.last! as NSString).pathExtension.lowercased()) else {
                throw GitHubReadError.invalidURL
            }
        }
    }

    static func validSegment(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\") &&
        !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

public struct GitHubLocation: Sendable, Equatable {
    public let link: GitHubLink
    public let reference: String
    public let commit: String
    public let path: String
}

public struct GitHubEntry: Decodable, Sendable {
    public let name: String
    public let path: String
    public let sha: String
    public let type: String
    public let size: Int?
    let submoduleGitURL: String?
    enum CodingKeys: String, CodingKey { case name, path, sha, type, size; case submoduleGitURL = "submodule_git_url" }
    public var isDirectory: Bool { type == "dir" }
}

private final class NoGitHubRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// GET-only client with a credential-scoped, bounded memory cache.
public struct GitHubReader: Sendable {
    public struct Response: Sendable, Codable {
        public let data: Data
        public let status: Int
        public let headers: [String: String]
        public init(data: Data, status: Int, headers: [String: String] = [:]) {
            self.data = data; self.status = status
            self.headers = headers.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
        }
    }
    public typealias Transport = @Sendable (URLRequest, Int) async throws -> Response
    private let requests: GitHubRequests
    public init(token: String? = nil, offlineCache: GitHubOfflineCache? = nil, transport: @escaping Transport = GitHubReader.fetch) {
        requests = GitHubRequests(token: token, offlineCache: offlineCache, transport: transport)
    }

    /// Permanently disables this session, including copies held by image loaders.
    @discardableResult public func invalidate() async -> Bool { await requests.invalidate() }
    public var isUsingOfflineCache: Bool { get async { await requests.usingOfflineCache } }
    public func clearOfflineCache() async throws { try await requests.clearOfflineCache() }
    @discardableResult public func removeOfflineRepository(_ link: GitHubLink) async -> Bool { await requests.removeOfflineRepository(link) }

    public func clearMemoryCache() async { await requests.clearMemoryCache() }

    public func resolve(_ link: GitHubLink, explicitReference: String? = nil) async throws -> GitHubLocation {
        if link.kind == .repository {
            if let explicitReference {
                let parts = explicitReference.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                guard !parts.isEmpty, parts.allSatisfy(GitHubLink.validSegment) else { throw GitHubReadError.invalidPath }
                return GitHubLocation(link: link, reference: explicitReference,
                                      commit: try await commit(link, reference: explicitReference), path: "")
            }
            struct Repository: Decodable { let default_branch: String }
            let repo: Repository = try await json(link, endpoint: [], limit: 1_048_576)
            let sha = try await commit(link, reference: repo.default_branch)
            return GitHubLocation(link: link, reference: repo.default_branch, commit: sha, path: "")
        }
        if let explicitReference {
            let segments = explicitReference.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !segments.isEmpty, segments.allSatisfy(GitHubLink.validSegment), link.components.starts(with: segments),
                  link.kind != .document || segments.count < link.components.count else { throw GitHubReadError.invalidPath }
            let sha = try await commit(link, reference: explicitReference)
            return GitHubLocation(link: link, reference: explicitReference, commit: sha,
                                  path: link.components.dropFirst(segments.count).joined(separator: "/"))
        }
        var matches: [GitHubLocation] = []
        var offlineMiss = false
        let count = link.components.count - (link.kind == .document ? 1 : 0)
        for split in 1...count {
            try Task.checkCancellation()
            let ref = link.components.prefix(split).joined(separator: "/")
            do {
                let sha = try await commit(link, reference: ref)
                matches.append(GitHubLocation(link: link, reference: ref, commit: sha,
                                              path: link.components.dropFirst(split).joined(separator: "/")))
                if matches.count > 1 { throw GitHubReadError.ambiguousReference }
            } catch GitHubReadError.notFound { continue }
            catch GitHubReadError.offlineNotCached { offlineMiss = true; continue }
        }
        guard let location = matches.first else { throw offlineMiss ? GitHubReadError.offlineNotCached : GitHubReadError.missingReference }
        return location
    }

    public func children(_ location: GitHubLocation, path: String? = nil) async throws -> [GitHubEntry] {
        let path = path ?? location.path
        let entries: [GitHubEntry] = try await json(location.link, endpoint: ["contents"] + (try segments(path)), ref: location.commit)
        guard entries.count < 1_000 else { throw GitHubReadError.directoryLimit }
        // Skip explicit submodule/symlink entries and ignore untrusted download URLs.
        return try entries.filter { entry in
            guard entry.submoduleGitURL == nil, entry.type == "dir" || entry.type == "file" else { return false }
            let expected = (path.isEmpty ? "" : path + "/") + entry.name
            guard GitHubLink.validSegment(entry.name), entry.path == expected else { throw GitHubReadError.invalidResponse }
            return true
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func markdown(_ location: GitHubLocation, path: String? = nil) async throws -> String {
        let path = path ?? location.path
        guard LocalDocuments.markdownExtensions.contains((path as NSString).pathExtension.lowercased()) else { throw ReaderError.unsupportedFile }
        let data = try await request(location.link, endpoint: ["contents"] + (try segments(path)), ref: location.commit,
                                     accept: "application/vnd.github.raw+json", limit: 10 * 1_024 * 1_024)
        guard let text = String(data: data, encoding: .utf8) else { throw ReaderError.invalidEncoding }
        return text
    }

    /// Read raster assets from the same immutable commit as the document.
    public func image(_ location: GitHubLocation, path: String) async throws -> Data {
        guard ["png", "jpg", "jpeg", "gif", "webp"].contains((path as NSString).pathExtension.lowercased()) else {
            throw ReaderError.unsupportedFile
        }
        return try await request(location.link, endpoint: ["contents"] + (try segments(path)), ref: location.commit,
                                 accept: "application/vnd.github.raw+json", limit: 8 * 1_024 * 1_024)
    }

    private func segments(_ path: String) throws -> [String] {
        if path.isEmpty { return [] }
        let result = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard result.allSatisfy(GitHubLink.validSegment) else { throw GitHubReadError.invalidPath }
        return result
    }
    private func commit(_ link: GitHubLink, reference: String) async throws -> String {
        struct Commit: Decodable { let sha: String }
        let result: Commit
        do { result = try await json(link, endpoint: ["commits", reference], limit: 1_048_576) }
        // GitHub returns 422 for an unknown commit ref; only this lookup treats it
        // as a missing candidate, not a generic success or a global 404.
        catch GitHubReadError.http(422) { throw GitHubReadError.notFound }
        guard result.sha.count == 40, result.sha.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { throw GitHubReadError.invalidResponse }
        return result.sha
    }
    private func json<T: Decodable>(_ link: GitHubLink, endpoint: [String], ref: String? = nil, limit: Int = 8 * 1_024 * 1_024) async throws -> T {
        do { return try JSONDecoder().decode(T.self, from: try await request(link, endpoint: endpoint, ref: ref, limit: limit)) }
        catch is DecodingError { throw GitHubReadError.invalidResponse }
    }
    private func request(_ link: GitHubLink, endpoint: [String], ref: String? = nil,
                         accept: String = "application/vnd.github+json", limit: Int) async throws -> Data {
        var url = URLComponents()
        url.scheme = "https"; url.host = "api.github.com"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        url.percentEncodedPath = "/" + (["repos", link.owner, link.repository] + endpoint).map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
        if let ref { url.queryItems = [URLQueryItem(name: "ref", value: ref)] }
        guard let address = url.url else { throw GitHubReadError.invalidURL }
        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("iMDReader-Prototype", forHTTPHeaderField: "User-Agent")
        let response = try await requests.send(request, limit: limit, immutable: ref != nil)
        guard response.data.count <= limit else { throw GitHubReadError.responseTooLarge }
        switch response.status {
        case 200: return response.data
        case 401: throw GitHubReadError.credentialRejected
        case 403 where response.headers["x-ratelimit-remaining"] == "0" || response.headers["retry-after"] != nil: throw GitHubReadError.rateLimited
        case 403: throw GitHubReadError.unauthorized
        case 404: throw GitHubReadError.notFound
        case 429: throw GitHubReadError.rateLimited
        default: throw GitHubReadError.http(response.status)
        }
    }

    public static func fetch(_ request: URLRequest, limit: Int) async throws -> Response {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: NoGitHubRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw GitHubReadError.invalidResponse }
        if response.expectedContentLength > Int64(limit) { throw GitHubReadError.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw GitHubReadError.responseTooLarge }
            data.append(byte)
        }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields { if let key = key as? String, let value = value as? String { headers[key] = value } }
        return Response(data: data, status: response.statusCode, headers: headers)
    }
}

/// Per-reader coordination with bounded memory and optional persistent storage.
/// Mutable metadata uses conditional network reads with explicit offline fallback.
private actor GitHubRequests {
    let transport: GitHubReader.Transport
    let offlineCache: GitHubOfflineCache?
    private let session = UUID()
    var cached: [String: GitHubReader.Response] = [:]
    var order: [String] = []
    var cachedBytes = 0
    struct Flight { let id = UUID(); let task: Task<GitHubReader.Response, Error> }
    var flights: [String: Flight] = [:]
    var blockedUntil: Date?
    private var token: String?
    private var invalidated = false
    private var invalidationSucceeded: Bool?
    private var generation = UUID()
    private(set) var usingOfflineCache = false
    init(token: String?, offlineCache: GitHubOfflineCache?, transport: @escaping GitHubReader.Transport) {
        self.token = token; self.offlineCache = offlineCache; self.transport = transport
    }

    func invalidate() async -> Bool {
        if invalidated { return invalidationSucceeded ?? false }
        invalidated = true
        let previousToken = token
        token = nil
        clearMemoryCache()
        do {
            try await offlineCache?.revoke(token: previousToken, session: session)
            invalidationSucceeded = true
            return true
        } catch { invalidationSucceeded = false; return false }
    }
    func clearMemoryCache() {
        generation = UUID()
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll(); cached.removeAll(); order.removeAll(); cachedBytes = 0
    }
    func clearOfflineCache() async throws {
        clearMemoryCache()
        try await offlineCache?.clear()
    }
    func removeOfflineRepository(_ link: GitHubLink) async -> Bool {
        clearMemoryCache()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let owner = link.owner.addingPercentEncoding(withAllowedCharacters: allowed)!
        let repo = link.repository.addingPercentEncoding(withAllowedCharacters: allowed)!
        // Include the slash/query/key separator so repo names with a common prefix do not collide.
        do {
            for suffix in ["/", "?", "|"] {
                try await offlineCache?.removeRepository("https://api.github.com/repos/" + owner + "/" + repo + suffix, token: token)
            }
            return true
        } catch { return false }
    }
    private func remember(_ response: GitHubReader.Response, key: String) {
        guard cached[key] == nil else { return }
        cached[key] = response; order.append(key); cachedBytes += response.data.count
        while cachedBytes > 32 * 1_024 * 1_024 || order.count > 128 {
            let oldest = order.removeFirst()
            if let removed = cached.removeValue(forKey: oldest) { cachedBytes -= removed.data.count }
        }
    }
    private func canUseOffline(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code)
    }

    func send(_ request: URLRequest, limit: Int, immutable: Bool) async throws -> GitHubReader.Response {
        guard !invalidated else { throw CancellationError() }
        guard request.httpMethod == "GET", request.url?.scheme == "https", request.url?.host == "api.github.com" else {
            throw GitHubReadError.invalidURL
        }
        var authenticatedRequest = request
        if let token {
            guard !token.isEmpty, token.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 }) else {
                throw GitHubReadError.unauthorized
            }
            authenticatedRequest.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        let requestGeneration = generation
        let key = (request.url?.absoluteString ?? "") + "|" + (request.value(forHTTPHeaderField: "Accept") ?? "")
        if immutable, let response = cached[key] {
            guard response.data.count <= limit else { throw GitHubReadError.responseTooLarge }
            return response
        }
        let lookup = await offlineCache?.lookup(key, token: token, session: session)
        guard !invalidated, generation == requestGeneration else { throw CancellationError() }
        let saved = lookup?.response.flatMap { $0.data.count <= limit ? $0 : nil }
        if immutable, let saved { remember(saved, key: key); return saved }
        if let date = blockedUntil, date > Date() {
            if let saved { usingOfflineCache = true; return saved }
            throw GitHubReadError.rateLimitedUntil(date)
        }
        if let etag = saved?.headers["etag"] { authenticatedRequest.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        else if let modified = saved?.headers["last-modified"] { authenticatedRequest.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        let flight: Flight
        if let existing = flights[key] { flight = existing }
        else {
            let transport = self.transport
            let outgoing = authenticatedRequest
            flight = Flight(task: Task { try await transport(outgoing, limit) })
            flights[key] = flight
        }
        defer { if flights[key]?.id == flight.id { flights[key] = nil } }
        do {
            var response = try await flight.task.value
            guard !invalidated, generation == requestGeneration else { throw CancellationError() }
            try Task.checkCancellation()
            guard response.data.count <= limit else { throw GitHubReadError.responseTooLarge }
            if response.status == 304, let saved {
                response = .init(data: saved.data, status: 200, headers: saved.headers.merging(response.headers) { _, new in new })
            }
            if response.status == 429 || (response.status == 403 && (response.headers["x-ratelimit-remaining"] == "0" || response.headers["retry-after"] != nil)) {
                let now = Date()
                let retry: Date?
                if let seconds = response.headers["retry-after"].flatMap(TimeInterval.init), seconds.isFinite, seconds >= 0 {
                    retry = now.addingTimeInterval(min(seconds, 86_400))
                } else if let epoch = response.headers["x-ratelimit-reset"].flatMap(TimeInterval.init), epoch.isFinite {
                    retry = Date(timeIntervalSince1970: epoch)
                } else { retry = nil }
                let date = max(retry ?? now.addingTimeInterval(60), now.addingTimeInterval(1))
                blockedUntil = date
                if let saved { usingOfflineCache = true; return saved }
                if retry != nil { throw GitHubReadError.rateLimitedUntil(date) }
            }
            if [500, 502, 503, 504].contains(response.status), let saved { usingOfflineCache = true; return saved }
            // Permission failures, redirects, invalid responses and cancellation never use stale fallback.
            if response.status == 401 { _ = await invalidate(); return response }
            if response.status == 200 {
                usingOfflineCache = false
                if immutable { remember(response, key: key) }
                if let lookup {
                    await offlineCache?.store(response, key: key, token: token, session: session, revision: lookup.revision)
                    guard !invalidated, generation == requestGeneration else { throw CancellationError() }
                }
            }
            return response
        } catch {
            guard !invalidated, generation == requestGeneration else { throw CancellationError() }
            try Task.checkCancellation()
            if canUseOffline(error) {
                if let saved { usingOfflineCache = true; return saved }
                if offlineCache != nil { throw GitHubReadError.offlineNotCached }
            }
            throw error
        }
    }
}

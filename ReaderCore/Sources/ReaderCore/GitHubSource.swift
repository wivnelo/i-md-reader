import Foundation

public enum GitHubReadError: LocalizedError, Equatable {
    case invalidURL, invalidPath, ambiguousReference, missingReference, directoryLimit
    case unauthorized, notFound, rateLimited, responseTooLarge, invalidResponse, http(Int)
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
        case .unauthorized: "此仓库需要有效的只读授权；当前仅接入公开读取。"
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

/// Public GET-only client. Immutable commit responses are held in bounded memory;
/// authentication and persistent offline storage are not connected yet.
public struct GitHubReader: Sendable {
    public struct Response: Sendable {
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
    public init(transport: @escaping Transport = GitHubReader.fetch) { requests = GitHubRequests(transport: transport) }

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
        }
        guard let location = matches.first else { throw GitHubReadError.missingReference }
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
            return entry.isDirectory || LocalDocuments.markdownExtensions.contains((entry.name as NSString).pathExtension.lowercased())
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
        case 401: throw GitHubReadError.unauthorized
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

/// Per-reader request coordination. Only commit-pinned successful contents are
/// cached; ref resolution always goes to GitHub on an explicit refresh.
private actor GitHubRequests {
    let transport: GitHubReader.Transport
    var cached: [String: GitHubReader.Response] = [:]
    var order: [String] = []
    var cachedBytes = 0
    struct Flight { let id = UUID(); let task: Task<GitHubReader.Response, Error> }
    var flights: [String: Flight] = [:]
    var blockedUntil: Date?
    init(transport: @escaping GitHubReader.Transport) { self.transport = transport }

    func send(_ request: URLRequest, limit: Int, immutable: Bool) async throws -> GitHubReader.Response {
        let key = (request.url?.absoluteString ?? "") + "|" + (request.value(forHTTPHeaderField: "Accept") ?? "")
        if immutable, let response = cached[key] {
            guard response.data.count <= limit else { throw GitHubReadError.responseTooLarge }
            return response
        }
        if let date = blockedUntil, date > Date() { throw GitHubReadError.rateLimitedUntil(date) }
        let flight: Flight
        if let existing = flights[key] { flight = existing }
        else {
            let transport = self.transport
            flight = Flight(task: Task { try await transport(request, limit) })
            flights[key] = flight
        }
        defer { if flights[key]?.id == flight.id { flights[key] = nil } }
        do {
            let response = try await flight.task.value
            guard response.data.count <= limit else { throw GitHubReadError.responseTooLarge }
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
                // Preserve the generic classification when no server reset time
                // exists; subsequent attempts still honor a minimum cooldown.
                if retry != nil { throw GitHubReadError.rateLimitedUntil(date) }
            }
            if immutable && response.status == 200 && cached[key] == nil {
                cached[key] = response; order.append(key); cachedBytes += response.data.count
                while cachedBytes > 32 * 1_024 * 1_024 || order.count > 128 {
                    let oldest = order.removeFirst()
                    if let removed = cached.removeValue(forKey: oldest) { cachedBytes -= removed.data.count }
                }
            }
            return response
        } catch { throw error }
    }
}

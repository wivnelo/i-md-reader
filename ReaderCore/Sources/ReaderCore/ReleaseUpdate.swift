import Foundation

/// Only stable public releases from the application's own distribution channel.
public struct ReleaseUpdate: Sendable, Equatable {
    public let version: String
    public let downloadURL: URL

    public static func macRelease(from data: Data, currentVersion: String) throws -> Self? {
        struct Release: Decodable {
            let tag_name: String
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]
        }
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease,
              let latest = versionParts(release.tag_name), let current = versionParts(currentVersion),
              current.lexicographicallyPrecedes(latest) else { return nil }
        let version = latest.map(String.init).joined(separator: ".")
        // Never open an arbitrary URL supplied by release metadata.
        let prefix = "https://github.com/wivnelo/i-md-reader/releases/download/\(release.tag_name)/"
        for ext in ["dmg", "zip"] {
            let name = "iMDReader-\(version)-macOS-universal.\(ext)"
            if release.assets.contains(where: { $0.name == name && $0.browser_download_url == prefix + name }),
               let url = URL(string: prefix + name) {
                return Self(version: version, downloadURL: url)
            }
        }
        return nil
    }

    private static func versionParts(_ value: String) -> [Int]? {
        let raw = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
            return Int(part)
        }
        return numbers.count == 3 ? numbers : nil
    }
}

private final class UpdateRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// One attempt per process-owned checker, including offline/failure cases.
public actor StartupUpdateCheck {
    private var started = false
    private let fetch: @Sendable () async throws -> Data?
    public init() { fetch = Self.fetchMacMetadata }
    init(fetch: @escaping @Sendable () async throws -> Data?) { self.fetch = fetch }

    public func checkMac(currentVersion: String) async -> ReleaseUpdate? {
        guard !started else { return nil }
        started = true
        do {
            guard let data = try await fetch() else { return nil }
            return try ReleaseUpdate.macRelease(from: data, currentVersion: currentVersion)
        } catch { return nil }
    }

    private static func fetchMacMetadata() async throws -> Data? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: UpdateRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/wivnelo/i-md-reader/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("iMDReader-UpdateCheck", forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  response.expectedContentLength <= 262_144 else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 262_144 else { return nil }
                data.append(byte)
            }
            return data
        } catch { return nil } // Startup/offline errors must not interrupt reading.
    }
}

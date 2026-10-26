import Foundation
import CryptoKit

/// Shared by iOS, iPadOS and macOS. No UI or platform account APIs belong here.
public actor GitHubOfflineCache {
    public static let shared = GitHubOfflineCache(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("iMDReader/OfflineCache-v1", isDirectory: true))

    public struct Usage: Sendable {
        public let bytes: Int
        public let count: Int
        public let capacity: Int
    }
    struct Lookup: Sendable {
        let response: GitHubReader.Response?
        let revision: UUID
    }
    private struct Record: Codable {
        let key: String
        let response: GitHubReader.Response
    }
    private let directory: URL
    private var capacity: Int
    private var revision = UUID()
    private var revoked: Set<UUID> = []
    private let manager = FileManager.default

    public init(directory: URL, capacity: Int = 128 * 1_024 * 1_024) {
        self.directory = directory
        self.capacity = max(0, capacity)
    }

    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func folder(_ token: String?) -> URL {
        directory.appendingPathComponent(token.map { digest("iMDReader-cache-identity-v1|" + $0) } ?? "public", isDirectory: true)
    }
    private func fileName(_ key: String) -> String {
        let path = URL(string: String(key.split(separator: "|", maxSplits: 1).first ?? ""))?.pathComponents ?? []
        let metadata = path.dropFirst(4).first != "contents"
        return digest(key) + (metadata ? "-metadata.cache" : ".cache")
    }
    private func encryptionKey(_ token: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(("iMDReader-cache-encryption-v1|" + token).utf8)))
    }
    private func prepare(_ folder: URL) throws {
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        var root = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }
    private func decode(_ file: URL, token: String?) -> Record? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 24 * 1_024 * 1_024, let bytes = try? Data(contentsOf: file) else { return nil }
        let data: Data
        if let token {
            guard let box = try? AES.GCM.SealedBox(combined: bytes),
                  let opened = try? AES.GCM.open(box, using: encryptionKey(token)) else { return nil }
            data = opened
        } else { data = bytes }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    func lookup(_ key: String, token: String?, session: UUID) -> Lookup {
        guard !revoked.contains(session) else { return Lookup(response: nil, revision: revision) }
        let file = folder(token).appendingPathComponent(fileName(key))
        guard let record = decode(file, token: token), record.key == key, record.response.status == 200 else {
            try? manager.removeItem(at: file)
            return Lookup(response: nil, revision: revision)
        }
        try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return Lookup(response: record.response, revision: revision)
    }

    func store(_ response: GitHubReader.Response, key: String, token: String?, session: UUID, revision expected: UUID) {
        guard !revoked.contains(session), expected == revision, response.status == 200, capacity > 0 else { return }
        do {
            let safeHeaders = response.headers.filter { ["etag", "last-modified", "content-type"].contains($0.key) }
            let safe = GitHubReader.Response(data: response.data, status: 200, headers: safeHeaders)
            let data = try JSONEncoder().encode(Record(key: key, response: safe))
            let bytes = try token.map { try AES.GCM.seal(data, using: encryptionKey($0)).combined! } ?? data
            guard bytes.count <= capacity, bytes.count <= 24 * 1_024 * 1_024 else { return }
            let folder = folder(token)
            try prepare(folder)
            let file = folder.appendingPathComponent(fileName(key))
            #if os(iOS)
            try bytes.write(to: file, options: [.atomic, .completeFileProtection])
            #else
            try bytes.write(to: file, options: .atomic)
            #endif
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            trim()
        } catch {
            // Cache storage failure must not turn a successful read into an error.
        }
    }

    private func files() -> [URL] {
        let folders = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return folders.flatMap { (try? manager.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [] }
            .filter { $0.pathExtension == "cache" }
    }
    private func trim() {
        let entries = files().map { file in
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (file, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
        }.sorted {
            let firstMetadata = $0.0.lastPathComponent.hasSuffix("-metadata.cache")
            let secondMetadata = $1.0.lastPathComponent.hasSuffix("-metadata.cache")
            // Keep small ref metadata usable while evicting old article/image bodies.
            return firstMetadata == secondMetadata ? $0.2 < $1.2 : !firstMetadata
        }
        var size = entries.reduce(0) { $0 + $1.1 }
        var count = entries.count
        for (file, bytes, _) in entries where size > capacity || count > 512 {
            if (try? manager.removeItem(at: file)) != nil { size -= bytes; count -= 1 }
        }
    }
    public func usage() -> Usage {
        let entries = files()
        return Usage(bytes: entries.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }, count: entries.count, capacity: capacity)
    }
    public func setCapacity(_ bytes: Int) {
        capacity = max(0, bytes)
        revision = UUID()
        trim()
    }
    public func clear() throws {
        revision = UUID()
        if manager.fileExists(atPath: directory.path) { try manager.removeItem(at: directory) }
    }
    func revoke(token: String?, session: UUID) throws {
        revoked.insert(session)
        revision = UUID()
        // Public responses are not private account data and remain reusable.
        if token != nil, manager.fileExists(atPath: folder(token).path) { try manager.removeItem(at: folder(token)) }
    }
    func removeRepository(_ prefix: String, token: String?) throws {
        revision = UUID()
        guard manager.fileExists(atPath: folder(token).path) else { return }
        let files = try manager.contentsOfDirectory(at: folder(token), includingPropertiesForKeys: nil)
        for file in files where decode(file, token: token)?.key.hasPrefix(prefix) == true { try manager.removeItem(at: file) }
    }
}

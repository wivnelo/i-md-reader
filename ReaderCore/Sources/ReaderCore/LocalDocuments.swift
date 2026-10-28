import Foundation

public enum ReaderError: LocalizedError {
    case outsideRoot, unsupportedFile, tooLarge, invalidEncoding
    public var errorDescription: String? {
        switch self {
        case .outsideRoot: "链接超出已授权文件夹，请单独添加该文件夹。"
        case .unsupportedFile: "此版本只打开 Markdown 文档和本地图片。"
        case .tooLarge: "文档超过原型的 10 MB 保护上限。"
        case .invalidEncoding: "无法识别文档编码，请使用 UTF-8 或 UTF-16。"
        }
    }
}

/// Dates reported by the granted file provider, never import/cache timestamps.
public struct DocumentDates: Sendable, Equatable {
    public var modified: Date?
    public var committed: Date?
    public init(modified: Date? = nil, committed: Date? = nil) {
        self.modified = modified; self.committed = committed
    }
    public static func local(_ url: URL) -> Self {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return Self(modified: values?.contentModificationDate)
    }
    public func labels(language: String, timeZone: TimeZone = .current) -> [String] {
        let chinese = language.lowercased().hasPrefix("zh")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: chinese ? "zh_Hans_CN" : "en_US")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = chinese ? "yyyy年M月d日 HH:mm zzz" : "MMM d, yyyy HH:mm zzz"
        guard let date = committed ?? modified else { return [] }
        let label = committed != nil
            ? (chinese ? "变更时间（提交 · 当前版本）" : "Changed (commit · current revision)")
            : (chinese ? "变更时间" : "Changed")
        return [label + " · " + formatter.string(from: date)]
    }
}

public struct FileNode: Identifiable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var isMarkdown: Bool { !isDirectory && LocalDocuments.markdownExtensions.contains(url.pathExtension.lowercased()) }
    public init(url: URL, isDirectory: Bool) { self.url = url; self.isDirectory = isDirectory }
}

public enum LocalDocuments {
    public static let markdownExtensions: Set<String> = ["md", "markdown"]

    public static func relativePath(of url: URL, to root: URL) throws -> String {
        let canonicalRoot = try confined(root, to: root)
        let canonicalFile = try confined(url, to: root)
        if canonicalFile.path == canonicalRoot.path { return "" }
        return String(canonicalFile.path.dropFirst(canonicalRoot.path.count + 1))
    }

    public static func resourceURL(_ request: URL, root: URL) throws -> URL {
        guard request.scheme == "reader-resource", request.host == "local",
              request.user == nil, request.password == nil, request.port == nil else { throw ReaderError.outsideRoot }
        // Custom schemes can retain percent escapes in `.path`; decode exactly once.
        let path = String(request.path(percentEncoded: false).drop(while: { $0 == "/" }))
        return try confined(root.appendingPathComponent(path), to: root)
    }

    /// Resolve symlinks before checking the component boundary, never just a string prefix.
    public static func confined(_ url: URL, to root: URL) throws -> URL {
        guard url.isFileURL, root.isFileURL else { throw ReaderError.outsideRoot }
        let root = canonical(root)
        let url = canonical(url)
        guard url.isFileURL, url.path == root.path || url.path.hasPrefix(root.path + "/") else {
            throw ReaderError.outsideRoot
        }
        return url
    }

    // Foundation may leave ancestor symlinks unresolved when the final file is missing.
    private static func canonical(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            missing.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        for component in missing.reversed() { resolved.appendPathComponent(component) }
        return resolved.standardizedFileURL
    }

    public static func children(of directory: URL, root: URL) throws -> [FileNode] {
        let directory = try confined(directory, to: root)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [])
            .compactMap { url -> FileNode? in
                guard !url.lastPathComponent.hasPrefix(".") else { return nil }
                let values = try url.resourceValues(forKeys: keys)
                // Do not recurse into symlinks; this also prevents directory cycles.
                guard values.isSymbolicLink != true else { return nil }
                if values.isDirectory == true { return FileNode(url: url, isDirectory: true) }
                guard values.isRegularFile == true else { return nil }
                return FileNode(url: url, isDirectory: false)
            }.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    public static func read(_ url: URL, root: URL) throws -> String {
        let url = try confined(url, to: root)
        guard markdownExtensions.contains(url.pathExtension.lowercased()) else { throw ReaderError.unsupportedFile }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 10 * 1024 * 1024 else { throw ReaderError.tooLarge }
        // A bounded stream also handles a file growing between the size check and read.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 10 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 10 * 1024 * 1024 else { throw ReaderError.tooLarge }
        if let text = String(data: data, encoding: .utf8) { return text }
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]),
           let text = String(data: data, encoding: .utf16) { return text }
        throw ReaderError.invalidEncoding
    }
}

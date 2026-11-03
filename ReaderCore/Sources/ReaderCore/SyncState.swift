import Foundation

/// When and where a synced value last changed. Equal times fall back to the device
/// so every device independently picks the same winner.
public struct SyncStamp: Codable, Sendable, Hashable, Comparable {
    public var time: Date
    public var device: String
    public init(time: Date, device: String) { self.time = time; self.device = device }
    /// Pre-sync local data loses to anything recorded after sync was enabled.
    public static func legacy(device: String) -> SyncStamp { SyncStamp(time: Date(timeIntervalSince1970: 0), device: device) }
    public static func < (a: SyncStamp, b: SyncStamp) -> Bool { (a.time, a.device) < (b.time, b.device) }
}

public struct Stamped<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public var value: Value
    public var stamp: SyncStamp
    public init(_ value: Value, _ stamp: SyncStamp) { self.value = value; self.stamp = stamp }
    func newer(_ other: Self) -> Self { other.stamp > stamp ? other : self }
}

public struct SyncSource: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: Codable, Sendable, Equatable {
        case github(url: String, reference: String?)
        /// Container plus container-relative path, e.g. `com~apple~CloudDocs/Notes`.
        case cloudFolder(path: String)
    }
    public let id: UUID
    public var kind: Kind
    public var name: String
    public var addedAt: Date
    public var stamp: SyncStamp
    public init(id: UUID, kind: Kind, name: String, addedAt: Date, stamp: SyncStamp) {
        self.id = id; self.kind = kind; self.name = name; self.addedAt = addedAt; self.stamp = stamp
    }

    /// Sources that point at the same content, whichever device added them.
    var identity: String? {
        switch kind {
        case let .github(url, reference):
            guard let link = try? GitHubLink(url) else { return nil }
            let kind = switch link.kind { case .repository: "repo"; case .directory: "tree"; case .document: "blob" }
            return (["github", link.owner.lowercased(), link.repository.lowercased(), kind] + link.components).joined(separator: "/")
                + "@" + (reference ?? "")
        case let .cloudFolder(path):
            return "icloud/" + path
        }
    }
}

/// The state every device shares. Local-only data (bookmarks, expanded rows, cache) stays out.
public struct SyncState: Codable, Sendable, Equatable {
    public static let positionLimit = 200

    public var sources: [UUID: SyncSource] = [:]
    public var removed: [UUID: SyncStamp] = [:]
    public var pinned: Stamped<[UUID]>
    public var order: Stamped<[UUID]>
    public var sampleRemoved: Stamped<Bool>
    public var palette: Stamped<String?>
    /// Keyed like ReaderStore positions: `<source UUID>|/<relative path>`.
    public var positions: [String: Stamped<Double>] = [:]

    public init(stamp: SyncStamp) {
        pinned = Stamped([], stamp); order = Stamped([], stamp)
        sampleRemoved = Stamped(false, stamp); palette = Stamped(nil, stamp)
    }

    public var activeSources: [SyncSource] {
        sources.values.filter { source in removed[source.id].map { source.stamp > $0 } ?? true }
    }

    public mutating func add(_ source: SyncSource) { sources[source.id] = source }
    public mutating func remove(_ id: UUID, at stamp: SyncStamp) {
        removed[id] = max(removed[id] ?? stamp, stamp)
        normalize()
    }
    public mutating func setPosition(_ value: Double, for key: String, at stamp: SyncStamp) {
        guard value.isFinite else { return }
        positions[key] = Stamped(min(1, max(0, value)), stamp)
        trimPositions()
    }

    public struct Merge: Sendable, Equatable {
        public var state: SyncState
        /// Duplicate source IDs folded into the surviving ID; callers move local bookmarks along.
        public var remapped: [UUID: UUID]
    }

    /// Commutative: merging A into B and B into A yields the same state.
    public static func merge(_ a: SyncState, _ b: SyncState) -> Merge {
        var state = a
        for (id, source) in b.sources {
            state.sources[id] = state.sources[id].map { $0.stamp >= source.stamp ? $0 : source } ?? source
        }
        state.removed.merge(b.removed) { max($0, $1) }
        state.pinned = a.pinned.newer(b.pinned)
        state.order = a.order.newer(b.order)
        state.sampleRemoved = a.sampleRemoved.newer(b.sampleRemoved)
        state.palette = a.palette.newer(b.palette)
        state.positions.merge(b.positions) { $0.newer($1) }
        let remapped = state.foldDuplicates()
        state.normalize()
        return Merge(state: state, remapped: remapped)
    }

    /// Keeps the earliest-added source per identity and moves pins, order and positions onto it.
    mutating func foldDuplicates() -> [UUID: UUID] {
        let groups = Dictionary(grouping: activeSources.filter { $0.identity != nil }) { $0.identity! }
        var remapped: [UUID: UUID] = [:]
        for group in groups.values where group.count > 1 {
            let sorted = group.sorted { ($0.addedAt, $0.id.uuidString) < ($1.addedAt, $1.id.uuidString) }
            for loser in sorted.dropFirst() {
                remapped[loser.id] = sorted[0].id
                removed[loser.id] = max(removed[loser.id] ?? loser.stamp, loser.stamp)
            }
        }
        guard !remapped.isEmpty else { return remapped }
        let swap: ([UUID]) -> [UUID] = { ids in
            var seen = Set<UUID>()
            return ids.map { remapped[$0] ?? $0 }.filter { seen.insert($0).inserted }
        }
        pinned.value = swap(pinned.value)
        order.value = swap(order.value)
        for (key, position) in positions {
            guard let (id, path) = Self.split(key), let target = remapped[id] else { continue }
            positions[key] = nil
            let moved = target.uuidString + "|" + path
            positions[moved] = positions[moved].map { $0.newer(position) } ?? position
        }
        return remapped
    }

    /// Drops references to removed sources. The sample and standalone files are not sources here.
    mutating func normalize() {
        let gone = Set(removed.keys).subtracting(activeSources.map(\.id))
        pinned.value.removeAll(where: gone.contains)
        order.value.removeAll(where: gone.contains)
        positions = positions.filter { key, _ in Self.split(key).map { !gone.contains($0.0) } ?? true }
        trimPositions()
    }

    mutating func trimPositions() {
        guard positions.count > Self.positionLimit else { return }
        let oldest = positions.sorted { ($0.value.stamp, $0.key) < ($1.value.stamp, $1.key) }
        for (key, _) in oldest.prefix(positions.count - Self.positionLimit) { positions[key] = nil }
    }

    static func split(_ key: String) -> (UUID, String)? {
        guard let bar = key.firstIndex(of: "|"), let id = UUID(uuidString: String(key[..<bar])) else { return nil }
        return (id, String(key[key.index(after: bar)...]))
    }
}

public enum CloudDrivePath {
    /// The device-independent location of an item inside iCloud Drive or an app's
    /// iCloud container, or nil when the URL lives elsewhere (On My iPad, external drives).
    public static func identity(of url: URL) -> String? {
        let parts = url.standardizedFileURL.pathComponents
        guard let index = parts.firstIndex(of: "Mobile Documents"), index > 0, index + 1 < parts.count,
              parts[index - 1] == "Library" else { return nil }
        return parts[(index + 1)...].joined(separator: "/").precomposedStringWithCanonicalMapping
    }
}

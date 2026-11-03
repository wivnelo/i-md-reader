import CloudKit
import CryptoKit
import Foundation

/// What the app currently holds for synced data, without stamps.
public struct SyncSnapshot: Sendable, Equatable {
    public struct Source: Sendable, Equatable {
        public var kind: SyncSource.Kind
        public var name: String
        public init(kind: SyncSource.Kind, name: String) { self.kind = kind; self.name = name }
    }
    public var sources: [UUID: Source]
    /// Only syncable IDs; device-local sources are kept out by the caller.
    public var pinned: [UUID]
    public var order: [UUID]
    public var sampleRemoved: Bool
    public var positions: [String: Double]
    public init(sources: [UUID: Source] = [:], pinned: [UUID] = [], order: [UUID] = [], sampleRemoved: Bool = false,
                positions: [String: Double] = [:]) {
        self.sources = sources; self.pinned = pinned; self.order = order
        self.sampleRemoved = sampleRemoved; self.positions = positions
    }
}

extension SyncState {
    /// Stamps every field that differs from `snapshot`. Positions absent from the
    /// snapshot are left alone: the app trims locally and the state trims itself.
    public mutating func absorb(_ snapshot: SyncSnapshot, at stamp: SyncStamp, now: Date) {
        let active = Dictionary(uniqueKeysWithValues: activeSources.map { ($0.id, $0) })
        for (id, item) in snapshot.sources {
            if var existing = active[id] {
                guard existing.kind != item.kind || existing.name != item.name else { continue }
                existing.kind = item.kind; existing.name = item.name; existing.stamp = stamp
                sources[id] = existing
            } else {
                sources[id] = SyncSource(id: id, kind: item.kind, name: item.name, addedAt: now, stamp: stamp)
            }
        }
        for id in active.keys where snapshot.sources[id] == nil { removed[id] = max(removed[id] ?? stamp, stamp) }
        if pinned.value != snapshot.pinned { pinned = Stamped(snapshot.pinned, stamp) }
        if order.value != snapshot.order { order = Stamped(snapshot.order, stamp) }
        if sampleRemoved.value != snapshot.sampleRemoved { sampleRemoved = Stamped(snapshot.sampleRemoved, stamp) }
        for (key, raw) in snapshot.positions {
            guard let value = Self.position(raw), positions[key]?.value != value else { continue }
            positions[key] = Stamped(value, stamp)
        }
        normalize()
    }

    /// Positions whose source is shared across devices (synced sources plus fixed IDs such as the sample).
    public func syncablePositionKey(_ key: String, fixed: Set<UUID>) -> Bool {
        guard let (id, _) = Self.split(key) else { return false }
        return fixed.contains(id) || activeSources.contains { $0.id == id }
    }
}

/// Puts `remote` (syncable IDs only) in charge while keeping device-local IDs near their previous neighbours.
public func mergeSyncedOrder(local: [UUID], remote: [UUID], isLocalOnly: (UUID) -> Bool) -> [UUID] {
    var result = remote
    var anchor: UUID?
    for id in local {
        if isLocalOnly(id) {
            let index = anchor.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            if !result.contains(id) { result.insert(id, at: index) }
            anchor = id
        } else if remote.contains(id) { anchor = id }
    }
    return result
}

/// Maps SyncState to CloudKit records: one per source, one layout, one per reading position.
public enum SyncRecords {
    public static let zoneID = CKRecordZone.ID(zoneName: "ReaderState", ownerName: CKCurrentUserDefaultName)
    static let layoutName = "layout"

    public static func recordType(for name: String) -> CKRecord.RecordType {
        name == layoutName ? "Layout" : name.hasPrefix("source.") ? "Source" : "Position"
    }
    public static func sourceName(_ id: UUID) -> String { "source." + id.uuidString }
    public static func positionName(_ key: String) -> String {
        "position." + SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Record names that must be saved or deleted to move the cloud from `old` to `new`.
    public static func changes(from old: SyncState, to new: SyncState) -> (save: Set<String>, delete: Set<String>) {
        var save = Set<String>(), delete = Set<String>()
        for id in Set(old.sources.keys).union(new.sources.keys).union(old.removed.keys).union(new.removed.keys)
        where old.sources[id] != new.sources[id] || old.removed[id] != new.removed[id] {
            save.insert(sourceName(id))
        }
        if old.pinned != new.pinned || old.order != new.order || old.sampleRemoved != new.sampleRemoved {
            save.insert(layoutName)
        }
        for (key, value) in new.positions where old.positions[key] != value { save.insert(positionName(key)) }
        for key in old.positions.keys where new.positions[key] == nil { delete.insert(positionName(key)) }
        return (save, delete)
    }

    /// Fills `record` (fresh or carrying cached system fields) from `state`; nil when nothing is left to save.
    public static func fill(_ record: CKRecord, from state: SyncState) -> CKRecord? {
        let name = record.recordID.recordName
        if name == layoutName {
            // Comma-joined strings: CloudKit cannot infer a field type from an empty list.
            record["pinned"] = state.pinned.value.map(\.uuidString).joined(separator: ",")
            record["order"] = state.order.value.map(\.uuidString).joined(separator: ",")
            record["sampleRemoved"] = state.sampleRemoved.value as NSNumber
            for (field, stamp) in [("pinned", state.pinned.stamp), ("order", state.order.stamp),
                                   ("sampleRemoved", state.sampleRemoved.stamp)] {
                write(stamp, field, record)
            }
            return record
        }
        if let id = sourceID(name) {
            guard state.sources[id] != nil || state.removed[id] != nil else { return nil }
            if let source = state.sources[id] {
                switch source.kind {
                case let .github(url, reference): record["kind"] = "github"; record["url"] = url; record["reference"] = reference
                case let .cloudFolder(path): record["kind"] = "cloudFolder"; record["path"] = path
                }
                record["name"] = source.name
                record["addedAt"] = source.addedAt as NSDate
                write(source.stamp, "source", record)
            }
            if let stamp = state.removed[id] { write(stamp, "removed", record) }
            return record
        }
        guard let (key, position) = state.positions.first(where: { positionName($0.key) == name }) else { return nil }
        record["key"] = key
        record["value"] = position.value as NSNumber
        write(position.stamp, "value", record)
        return record
    }

    /// The part of the state a fetched record describes; everything else stays at the oldest possible stamp.
    public static func fragment(_ record: CKRecord) -> SyncState {
        var state = SyncState(stamp: SyncStamp(time: .distantPast, device: ""))
        let name = record.recordID.recordName
        if name == layoutName {
            let ids = { (field: String) in (record[field] as? String)?.split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
            if let value = ids("pinned"), let stamp = read("pinned", record) { state.pinned = Stamped(value, stamp) }
            if let value = ids("order"), let stamp = read("order", record) { state.order = Stamped(value, stamp) }
            if let value = record["sampleRemoved"] as? Bool, let stamp = read("sampleRemoved", record) {
                state.sampleRemoved = Stamped(value, stamp)
            }
        } else if let id = sourceID(name) {
            if let stamp = read("source", record), let kind = kind(record),
               let name = record["name"] as? String, let added = record["addedAt"] as? Date {
                state.sources[id] = SyncSource(id: id, kind: kind, name: name, addedAt: added, stamp: stamp)
            }
            if let stamp = read("removed", record) { state.removed[id] = stamp }
        } else if let key = record["key"] as? String, let value = record["value"] as? Double, let stamp = read("value", record) {
            state.positions[key] = Stamped(value, stamp)
        }
        return state
    }

    /// True when the record already says what `state` holds, so saving it again would only echo.
    public static func matches(_ record: CKRecord, _ state: SyncState) -> Bool {
        let other = fragment(record), name = record.recordID.recordName
        if name == layoutName {
            return other.pinned == state.pinned && other.order == state.order
                && other.sampleRemoved == state.sampleRemoved
        }
        if let id = sourceID(name) { return other.sources[id] == state.sources[id] && other.removed[id] == state.removed[id] }
        return other.positions.allSatisfy { state.positions[$0.key] == $0.value } && !other.positions.isEmpty
    }

    /// Server deletion of a position record; its key is recovered by hashing known keys.
    public static func positionKey(forDeleted name: String, in state: SyncState) -> String? {
        state.positions.keys.first { positionName($0) == name }
    }

    static func sourceID(_ name: String) -> UUID? {
        name.hasPrefix("source.") ? UUID(uuidString: String(name.dropFirst(7))) : nil
    }
    static func kind(_ record: CKRecord) -> SyncSource.Kind? {
        switch record["kind"] as? String {
        case "github": (record["url"] as? String).map { .github(url: $0, reference: record["reference"] as? String) }
        case "cloudFolder": (record["path"] as? String).map { .cloudFolder(path: $0) }
        default: nil
        }
    }
    static func write(_ stamp: SyncStamp, _ field: String, _ record: CKRecord) {
        record[field + "At"] = stamp.time as NSDate
        record[field + "By"] = stamp.device as NSString
    }
    static func read(_ field: String, _ record: CKRecord) -> SyncStamp? {
        guard let time = record[field + "At"] as? Date, let device = record[field + "By"] as? String else { return nil }
        return SyncStamp(time: time, device: device)
    }
}

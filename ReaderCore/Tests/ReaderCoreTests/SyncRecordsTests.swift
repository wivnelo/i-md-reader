import CloudKit
import Foundation
import Testing
@testable import ReaderCore

private func stamp(_ seconds: TimeInterval, _ device: String = "mac") -> SyncStamp {
    SyncStamp(time: Date(timeIntervalSince1970: seconds), device: device)
}
private func record(_ name: String) -> CKRecord {
    CKRecord(recordType: "Item", recordID: CKRecord.ID(recordName: name, zoneID: SyncRecords.zoneID))
}

@Test func absorbStampsOnlyChangedFieldsAndTombstonesMissingSources() {
    let id = UUID(), sample = UUID()
    let repo = SyncSnapshot.Source(kind: .github(url: "https://github.com/test/repo", reference: nil), name: "test/repo")
    var state = SyncState(stamp: .legacy(device: "mac"))
    state.absorb(SyncSnapshot(sources: [id: repo], pinned: [id], positions: [id.uuidString + "|/a.md": 0.3]),
                 at: stamp(10), now: Date(timeIntervalSince1970: 10))
    #expect(state.sources[id]?.stamp == stamp(10) && state.pinned.stamp == stamp(10))
    #expect(state.order.stamp == .legacy(device: "mac") && state.palette.stamp == .legacy(device: "mac"))

    let before = state
    state.absorb(SyncSnapshot(sources: [id: repo], pinned: [id], positions: [id.uuidString + "|/a.md": 0.3]),
                 at: stamp(20), now: Date(timeIntervalSince1970: 20))
    #expect(state == before)

    state.absorb(SyncSnapshot(sampleRemoved: true, positions: [sample.uuidString + "|/x.md": 0.5]), at: stamp(30), now: Date())
    #expect(state.activeSources.isEmpty && state.removed[id] == stamp(30))
    #expect(state.pinned.value.isEmpty && state.sampleRemoved == Stamped(true, stamp(30)))
    #expect(state.positions.keys.sorted() == [sample.uuidString + "|/x.md"])
    #expect(state.syncablePositionKey(sample.uuidString + "|/x.md", fixed: [sample]))
    #expect(!state.syncablePositionKey(UUID().uuidString + "|/x.md", fixed: [sample]))
}

@Test func recordsRoundTripAndRecognizeEchoes() throws {
    let source = SyncSource(id: UUID(), kind: .github(url: "https://github.com/test/repo", reference: "dev"),
                            name: "test/repo", addedAt: Date(timeIntervalSince1970: 5), stamp: stamp(5))
    let folder = SyncSource(id: UUID(), kind: .cloudFolder(path: "com~apple~CloudDocs/Notes"),
                            name: "Notes", addedAt: Date(timeIntervalSince1970: 6), stamp: stamp(6))
    var state = SyncState(stamp: stamp(1)); state.add(source); state.add(folder)
    state.pinned = Stamped([source.id], stamp(7)); state.order = Stamped([folder.id, source.id], stamp(8))
    state.sampleRemoved = Stamped(true, stamp(9)); state.palette = Stamped("sand", stamp(10, "phone"))
    let key = source.id.uuidString + "|/a.md"
    state.setPosition(0.42, for: key, at: stamp(11))
    state.remove(folder.id, at: stamp(12))

    var rebuilt = SyncState(stamp: SyncStamp(time: .distantPast, device: ""))
    for name in [SyncRecords.layoutName, SyncRecords.sourceName(source.id), SyncRecords.sourceName(folder.id), SyncRecords.positionName(key)] {
        let filled = try #require(SyncRecords.fill(record(name), from: state))
        #expect(SyncRecords.matches(filled, state))
        rebuilt = SyncState.merge(rebuilt, SyncRecords.fragment(filled)).state
    }
    #expect(rebuilt.sources == state.sources && rebuilt.removed == state.removed)
    #expect(rebuilt.pinned == state.pinned && rebuilt.order.value == [source.id])
    #expect(rebuilt.sampleRemoved == state.sampleRemoved && rebuilt.palette == state.palette)
    #expect(rebuilt.positions == state.positions)

    // A newer local value no longer matches what the server holds.
    let server = try #require(SyncRecords.fill(record(SyncRecords.positionName(key)), from: state))
    state.setPosition(0.9, for: key, at: stamp(20))
    #expect(!SyncRecords.matches(server, state))
    #expect(SyncRecords.positionKey(forDeleted: SyncRecords.positionName(key), in: state) == key)
    #expect(SyncRecords.fill(record(SyncRecords.positionName("missing")), from: state) == nil)
    #expect(SyncRecords.fill(record(SyncRecords.sourceName(UUID())), from: state) == nil)
}

@Test func changesListOnlyTouchedRecords() {
    let id = UUID()
    var old = SyncState(stamp: stamp(1))
    old.add(SyncSource(id: id, kind: .github(url: "https://github.com/test/repo", reference: nil), name: "r",
                       addedAt: Date(), stamp: stamp(1)))
    old.setPosition(0.1, for: id.uuidString + "|/a.md", at: stamp(2))
    old.setPosition(0.2, for: id.uuidString + "|/b.md", at: stamp(2))
    var new = old
    new.setPosition(0.5, for: id.uuidString + "|/a.md", at: stamp(3))
    new.positions[id.uuidString + "|/b.md"] = nil
    let delta = SyncRecords.changes(from: old, to: new)
    #expect(delta.save == [SyncRecords.positionName(id.uuidString + "|/a.md")])
    #expect(delta.delete == [SyncRecords.positionName(id.uuidString + "|/b.md")])

    var removed = old; removed.remove(id, at: stamp(4))
    let removal = SyncRecords.changes(from: old, to: removed)
    #expect(removal.save.contains(SyncRecords.sourceName(id)) && removal.delete.count == 2)
    #expect(SyncRecords.changes(from: old, to: old) == ([], []))
}

@Test func remoteOrderKeepsDeviceLocalItemsNearTheirNeighbours() {
    let a = UUID(), b = UUID(), c = UUID(), local1 = UUID(), local2 = UUID()
    let localOnly: Set<UUID> = [local1, local2]
    // Local: local1 first, local2 after b. Remote reorders synced items to c, b, a.
    let merged = mergeSyncedOrder(local: [local1, a, b, local2, c], remote: [c, b, a]) { localOnly.contains($0) }
    #expect(merged == [local1, c, b, local2, a])
    // The syncable subsequence always equals the remote list, so applying it does not echo.
    #expect(merged.filter { !localOnly.contains($0) } == [c, b, a])
    #expect(mergeSyncedOrder(local: [], remote: [a]) { _ in false } == [a])
}

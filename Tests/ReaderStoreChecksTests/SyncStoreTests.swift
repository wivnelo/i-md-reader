import Foundation
import Testing
import ReaderCore
@testable import ReaderStoreChecks

/// One simulated device: isolated defaults, a sample folder and no network or Keychain access.
@MainActor private struct Device {
    let suite = "ReaderSyncTests." + UUID().uuidString
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let store: ReaderStore
    init() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sample"), withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suite)!
        store = ReaderStore(defaults: defaults, github: GitHubReader(), sampleURL: root.appendingPathComponent("Sample"))
    }
    func clean() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
}

private func stamp(_ seconds: TimeInterval, _ device: String) -> SyncStamp {
    SyncStamp(time: Date(timeIntervalSince1970: seconds), device: device)
}

@Test @MainActor func appliedStateReachesAnotherStoreWithoutEcho() throws {
    let mac = try Device(), phone = try Device()
    defer { mac.clean(); phone.clean() }
    let repo = UUID()
    var state = SyncState(stamp: stamp(0, "mac"))
    state.add(SyncSource(id: repo, kind: .github(url: "https://github.com/test/repo/tree/main/docs", reference: "main"),
                         name: "test/repo · docs", addedAt: Date(), stamp: stamp(1, "mac")))
    mac.store.applySynced(state)
    let added = try #require(mac.store.sources.first { $0.id == repo })
    mac.store.togglePin(added)
    mac.defaults.set("sand", forKey: "readerPalette")
    let key = repo.uuidString + "|/readme.md", sampleKey = ReaderStore.sampleID.uuidString + "|/a.md"
    mac.defaults.set([key: 0.6, sampleKey: 0.2, UUID().uuidString + "|/local.md": 0.9], forKey: "positions")
    let macStore = ReaderStore(defaults: mac.defaults, github: GitHubReader(), sampleURL: mac.root.appendingPathComponent("Sample"))
    state.absorb(macStore.syncSnapshot(), at: stamp(10, "mac"), now: Date())
    #expect(state.pinned.value == [repo] && state.palette.value == "sand")
    #expect(Set(state.positions.keys) == [key, sampleKey])

    phone.store.applySynced(state)
    #expect(phone.store.sources.contains { $0.id == repo && $0.remote?.reference == "main" })
    #expect(phone.store.orderedSources.first?.id == repo)
    #expect(phone.defaults.string(forKey: "readerPalette") == "sand")
    #expect((phone.defaults.dictionary(forKey: "positions") as? [String: Double])?[key] == 0.6)
    // Phone now reports exactly the synced state, so absorbing its snapshot changes nothing.
    let before = state
    state.absorb(phone.store.syncSnapshot(), at: stamp(20, "phone"), now: Date())
    #expect(state == before)
    // The state survives a restart of the receiving store.
    let restarted = ReaderStore(defaults: phone.defaults, github: GitHubReader(), sampleURL: phone.root.appendingPathComponent("Sample"))
    #expect(restarted.syncSnapshot() == phone.store.syncSnapshot())
}

@Test @MainActor func remoteChangesKeepDeviceLocalFoldersAndRemoveSyncedSources() throws {
    let phone = try Device()
    defer { phone.clean() }
    let folder = phone.root.appendingPathComponent("Local")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    phone.store.addFolder(folder)
    let local = try #require(phone.store.sources.first { $0.url?.standardizedFileURL == folder.standardizedFileURL })
    phone.store.togglePin(local)

    let a = UUID(), b = UUID()
    var state = SyncState(stamp: stamp(0, "mac"))
    for id in [a, b] {
        state.add(SyncSource(id: id, kind: .github(url: "https://github.com/test/\(id.uuidString.prefix(4))", reference: nil),
                             name: "r", addedAt: Date(), stamp: stamp(1, "mac")))
    }
    state.pinned = Stamped([b, a], stamp(2, "mac"))
    phone.store.applySynced(state)
    // The device-only folder stays pinned in front; the synced pins follow the remote order.
    #expect(phone.store.orderedSources.prefix(3).map(\.id) == [local.id, b, a])
    #expect(phone.store.syncSnapshot().pinned == [b, a])

    phone.defaults.set([a.uuidString + "|/x.md": 0.5], forKey: "positions")
    let reloaded = ReaderStore(defaults: phone.defaults, github: GitHubReader(), sampleURL: phone.root.appendingPathComponent("Sample"))
    state.remove(a, at: stamp(3, "mac"))
    reloaded.applySynced(state)
    #expect(!reloaded.sources.contains { $0.id == a })
    #expect(reloaded.sources.contains { $0.id == local.id })
    #expect(reloaded.syncSnapshot().positions.isEmpty && reloaded.syncSnapshot().pinned == [b])
}

@Test @MainActor func sampleRemovalFollowsTheSyncedFlagBothWays() throws {
    let phone = try Device()
    defer { phone.clean() }
    #expect(phone.store.sources.contains { $0.isSample })
    var state = SyncState(stamp: stamp(0, "mac"))
    state.sampleRemoved = Stamped(true, stamp(1, "mac"))
    phone.store.applySynced(state)
    #expect(!phone.store.sources.contains { $0.isSample } && phone.store.syncSnapshot().sampleRemoved)
    state.sampleRemoved = Stamped(false, stamp(2, "ipad"))
    phone.store.applySynced(state)
    #expect(phone.store.sources.contains { $0.isSample } && !phone.store.syncSnapshot().sampleRemoved)
}

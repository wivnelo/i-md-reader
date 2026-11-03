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

/// A folder laid out like iCloud Drive inside the device's temporary root.
@MainActor private func cloudFolder(_ device: Device, _ name: String) throws -> URL {
    let url = device.root.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/" + name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test @MainActor func cloudFolderWaitsForAuthorizationAndKeepsProgress() throws {
    let mac = try Device(), phone = try Device()
    defer { mac.clean(); phone.clean() }
    mac.store.addFolder(try cloudFolder(mac, "Notes"))
    let snapshot = mac.store.syncSnapshot()
    let (id, item) = try #require(snapshot.sources.first)
    #expect(item.kind == .cloudFolder(path: "com~apple~CloudDocs/Notes") && item.name == "Notes")

    var state = SyncState(stamp: stamp(0, "mac"))
    state.absorb(snapshot, at: stamp(1, "mac"), now: Date())
    state.setPosition(0.7, for: id.uuidString + "|/a.md", at: stamp(2, "mac"))
    phone.store.applySynced(state)
    let pending = try #require(phone.store.sources.first { $0.id == id })
    #expect(pending.url == nil && phone.store.isAwaitingAuthorization(pending))
    // Waiting here must not read as a removal when this device's snapshot is absorbed.
    #expect(phone.store.syncSnapshot().sources[id] == item)
    let restarted = ReaderStore(defaults: phone.defaults, github: GitHubReader(), sampleURL: nil)
    #expect(restarted.sources.contains { $0.id == id && restarted.isAwaitingAuthorization($0) })

    phone.store.authorizeCloudFolder(pending, url: try cloudFolder(phone, "Other"))
    #expect(phone.store.error != nil && phone.store.isAwaitingAuthorization(pending))
    phone.store.error = nil
    phone.store.authorizeCloudFolder(pending, url: try cloudFolder(phone, "Notes"))
    let bound = try #require(phone.store.sources.first { $0.id == id })
    #expect(bound.url != nil && !phone.store.isAwaitingAuthorization(bound) && phone.store.error == nil)
    #expect(phone.store.syncSnapshot().positions[id.uuidString + "|/a.md"] == 0.7)
    #expect(phone.store.syncSnapshot().sources[id] == item)
}

@Test @MainActor func independentlyAddedCloudFolderRebindsToTheSyncedID() throws {
    let mac = try Device(), phone = try Device()
    defer { mac.clean(); phone.clean() }
    mac.store.addFolder(try cloudFolder(mac, "Shared"))
    phone.store.addFolder(try cloudFolder(phone, "Shared"))
    let macID = try #require(mac.store.syncSnapshot().sources.keys.first)
    let phoneID = try #require(phone.store.syncSnapshot().sources.keys.first)
    phone.store.togglePin(try #require(phone.store.sources.first { $0.id == phoneID }))
    phone.defaults.set([phoneID.uuidString + "|/b.md": 0.4], forKey: "positions")
    let reloaded = ReaderStore(defaults: phone.defaults, github: GitHubReader(), sampleURL: nil)

    var macState = SyncState(stamp: stamp(0, "mac")); macState.absorb(mac.store.syncSnapshot(), at: stamp(1, "mac"), now: Date(timeIntervalSince1970: 1))
    var phoneState = SyncState(stamp: stamp(0, "phone")); phoneState.absorb(reloaded.syncSnapshot(), at: stamp(5, "phone"), now: Date(timeIntervalSince1970: 5))
    let merged = SyncState.merge(phoneState, macState)
    #expect(merged.remapped == [phoneID: macID])
    reloaded.applySynced(merged.state)
    let source = try #require(reloaded.sources.first { $0.id == macID })
    #expect(source.url != nil && !reloaded.sources.contains { $0.id == phoneID })
    #expect(reloaded.isPinned(source))
    #expect(reloaded.syncSnapshot().positions[macID.uuidString + "|/b.md"] == 0.4)
}

@Test @MainActor func unavailableCloudFolderStaysSyncedWhileLocalFoldersDoNot() throws {
    let phone = try Device()
    defer { phone.clean() }
    let cloud = try cloudFolder(phone, "Gone")
    let local = phone.root.appendingPathComponent("Local")
    try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
    phone.store.addFolder(cloud); phone.store.addFolder(local)
    #expect(phone.store.syncSnapshot().sources.count == 1)
    try FileManager.default.removeItem(at: cloud)
    let restarted = ReaderStore(defaults: phone.defaults, github: GitHubReader(), sampleURL: nil)
    // Missing on disk is not a removal: the source stays synced so other devices keep it.
    #expect(restarted.syncSnapshot().sources.values.map(\.kind) == [.cloudFolder(path: "com~apple~CloudDocs/Gone")])
}

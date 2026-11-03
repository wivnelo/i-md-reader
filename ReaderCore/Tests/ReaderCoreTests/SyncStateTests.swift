import Foundation
import Testing
@testable import ReaderCore

private func stamp(_ seconds: TimeInterval, _ device: String = "mac") -> SyncStamp {
    SyncStamp(time: Date(timeIntervalSince1970: seconds), device: device)
}
private func github(_ url: String, id: UUID = UUID(), added: TimeInterval = 10, at time: SyncStamp = stamp(10)) -> SyncSource {
    SyncSource(id: id, kind: .github(url: url, reference: nil), name: "repo", addedAt: Date(timeIntervalSince1970: added), stamp: time)
}

@Test func mergeIsOrderIndependentAndNewestFieldWins() {
    let source = github("https://github.com/test/repo")
    var mac = SyncState(stamp: stamp(0, "mac")); mac.add(source)
    mac.pinned = Stamped([source.id], stamp(20, "mac"))
    mac.palette = Stamped("mist", stamp(5, "mac"))
    mac.setPosition(0.4, for: source.id.uuidString + "|/a.md", at: stamp(30, "mac"))
    var phone = SyncState(stamp: stamp(0, "phone"))
    phone.palette = Stamped("sand", stamp(25, "phone"))
    phone.setPosition(0.9, for: source.id.uuidString + "|/a.md", at: stamp(40, "phone"))

    let one = SyncState.merge(mac, phone).state, two = SyncState.merge(phone, mac).state
    #expect(one == two)
    #expect(one.palette.value == "sand" && one.pinned.value == [source.id])
    #expect(one.positions[source.id.uuidString + "|/a.md"]?.value == 0.9)
    // Same time: the device name breaks the tie identically everywhere.
    #expect(stamp(5, "ipad") < stamp(5, "mac"))
}

@Test func firstEnableKeepsRemoteProgressOverLegacyLocalData() {
    let source = github("https://github.com/test/repo")
    let key = source.id.uuidString + "|/guide.md"
    var local = SyncState(stamp: .legacy(device: "ipad"))
    local.add(source)
    local.setPosition(0.1, for: key, at: .legacy(device: "ipad"))
    local.setPosition(0.3, for: "file-only|x", at: .legacy(device: "ipad"))
    var cloud = SyncState(stamp: stamp(0, "mac")); cloud.add(source)
    cloud.setPosition(0.7, for: key, at: stamp(100, "mac"))

    let merged = SyncState.merge(local, cloud).state
    #expect(merged.positions[key]?.value == 0.7)
    // Data only the local device had is uploaded, not dropped.
    #expect(merged.positions["file-only|x"]?.value == 0.3)
}

@Test func removalPropagatesAndClearsReferencesButNewerEditsSurvive() {
    let kept = github("https://github.com/test/kept"), gone = github("https://github.com/test/gone")
    var mac = SyncState(stamp: stamp(0)); mac.add(kept); mac.add(gone)
    mac.pinned = Stamped([gone.id, kept.id], stamp(10))
    mac.order = Stamped([kept.id, gone.id], stamp(10))
    mac.setPosition(0.5, for: gone.id.uuidString + "|/a.md", at: stamp(10))
    var phone = mac
    phone.remove(gone.id, at: stamp(50, "phone"))

    let merged = SyncState.merge(mac, phone).state
    #expect(merged.activeSources.map(\.id) == [kept.id])
    #expect(merged.pinned.value == [kept.id] && merged.order.value == [kept.id])
    #expect(merged.positions.isEmpty)
    // A pin written later on another device cannot resurrect the removed source.
    var late = mac; late.pinned = Stamped([gone.id], stamp(60, "ipad"))
    #expect(SyncState.merge(merged, late).state.pinned.value.isEmpty)
    // Re-adding the same content after removal yields a fresh source.
    var readded = phone; readded.add(github("https://github.com/test/gone", added: 70, at: stamp(70)))
    #expect(SyncState.merge(merged, readded).state.activeSources.count == 2)
}

@Test func duplicateSourcesFoldIntoEarliestAndMoveReferences() {
    let early = github("https://github.com/Test/Repo/tree/main/docs", added: 10)
    let late = github("https://github.com/test/repo.git/tree/main/docs/", added: 20, at: stamp(20, "phone"))
    // Same path on an explicit other reference is different content and stays separate.
    let otherBranch = SyncSource(id: UUID(), kind: .github(url: "https://github.com/test/repo/tree/main/docs", reference: "dev"),
                                 name: "dev", addedAt: Date(timeIntervalSince1970: 5), stamp: stamp(5))
    var mac = SyncState(stamp: stamp(0)); mac.add(early); mac.add(otherBranch)
    mac.setPosition(0.2, for: early.id.uuidString + "|/a.md", at: stamp(15))
    var phone = SyncState(stamp: stamp(0, "phone")); phone.add(late)
    phone.pinned = Stamped([late.id], stamp(25, "phone"))
    phone.order = Stamped([late.id, early.id], stamp(25, "phone"))
    phone.setPosition(0.8, for: late.id.uuidString + "|/a.md", at: stamp(30, "phone"))
    phone.setPosition(0.6, for: late.id.uuidString + "|/b.md", at: stamp(30, "phone"))

    let result = SyncState.merge(mac, phone)
    #expect(result.remapped == [late.id: early.id])
    #expect(Set(result.state.activeSources.map(\.id)) == [early.id, otherBranch.id])
    #expect(result.state.pinned.value == [early.id] && result.state.order.value == [early.id])
    #expect(result.state.positions[early.id.uuidString + "|/a.md"]?.value == 0.8)
    #expect(result.state.positions[early.id.uuidString + "|/b.md"]?.value == 0.6)
    #expect(result.state.positions.keys.allSatisfy { !$0.hasPrefix(late.id.uuidString) })
    // Both devices converge regardless of merge direction.
    #expect(SyncState.merge(phone, mac).state == result.state)
}

@Test func cloudFoldersFoldByPathAndOtherLocationsAreNotSynced() throws {
    let mac = URL(fileURLWithPath: "/Users/someone/Library/Mobile Documents/com~apple~CloudDocs/Notes/Project")
    let phone = URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Notes/Project/")
    let path = try #require(CloudDrivePath.identity(of: mac))
    #expect(path == "com~apple~CloudDocs/Notes/Project" && CloudDrivePath.identity(of: phone) == path)
    // Decomposed and precomposed spellings of the same name match.
    let nfd = URL(fileURLWithPath: "/Users/a/Library/Mobile Documents/com~apple~CloudDocs/Cafe\u{301}")
    #expect(CloudDrivePath.identity(of: nfd) == "com~apple~CloudDocs/Caf\u{E9}")
    #expect(CloudDrivePath.identity(of: URL(fileURLWithPath: "/Users/a/Documents/Notes")) == nil)
    #expect(CloudDrivePath.identity(of: URL(fileURLWithPath: "/Mobile Documents/x")) == nil)

    let a = SyncSource(id: UUID(), kind: .cloudFolder(path: path), name: "Project", addedAt: Date(timeIntervalSince1970: 1), stamp: stamp(1))
    let b = SyncSource(id: UUID(), kind: .cloudFolder(path: path), name: "Project", addedAt: Date(timeIntervalSince1970: 2), stamp: stamp(2, "phone"))
    var one = SyncState(stamp: stamp(0)); one.add(a)
    var two = SyncState(stamp: stamp(0, "phone")); two.add(b)
    #expect(SyncState.merge(one, two).remapped == [b.id: a.id])
}

@Test func positionLimitEvictsLeastRecentlyReadNotAlphabetical() {
    var state = SyncState(stamp: stamp(0))
    let first = "00000000-0000-0000-0000-000000000000|/recent.md"
    for index in 0..<SyncState.positionLimit {
        state.setPosition(0.5, for: UUID().uuidString + "|/\(index).md", at: stamp(Double(index + 1)))
    }
    // Alphabetically first key, but the newest read: it must survive the trim.
    state.setPosition(0.5, for: first, at: stamp(10_000))
    #expect(state.positions.count == SyncState.positionLimit)
    #expect(state.positions[first] != nil)
    #expect(!state.positions.values.contains { $0.stamp == stamp(1) })
    state.setPosition(.nan, for: first, at: stamp(20_000))
    #expect(state.positions[first]?.value == 0.5)
}

@Test func stateRoundTripsThroughCodable() throws {
    var state = SyncState(stamp: stamp(1)); state.add(github("https://github.com/test/repo"))
    state.remove(UUID(), at: stamp(2))
    state.setPosition(0.25, for: UUID().uuidString + "|/a.md", at: stamp(3))
    let decoded = try JSONDecoder().decode(SyncState.self, from: JSONEncoder().encode(state))
    #expect(decoded == state)
}

@Test func blockAnchorsSurviveWhileLegacyRatiosStayClamped() {
    #expect(SyncState.position(14.3) == 14.3 && SyncState.position(2) == 2)
    #expect(SyncState.position(1.5) == 1 && SyncState.position(-1) == 0 && SyncState.position(.infinity) == nil)
    var state = SyncState(stamp: stamp(0))
    state.setPosition(7.25, for: "k", at: stamp(1))
    state.absorb(SyncSnapshot(positions: ["k": 7.25, "old": 0.4]), at: stamp(2), now: Date())
    #expect(state.positions["k"] == Stamped(7.25, stamp(1)) && state.positions["old"]?.value == 0.4)
}

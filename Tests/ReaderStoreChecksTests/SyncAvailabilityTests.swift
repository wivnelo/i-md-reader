import CloudKit
import Foundation
import ReaderCore
import Testing
@testable import ReaderStoreChecks

@MainActor private struct AvailabilityDevice {
    let suite = "SyncAvailabilityTests." + UUID().uuidString
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let store: ReaderStore

    init() throws {
        let sample = root.appendingPathComponent("Sample")
        try FileManager.default.createDirectory(at: sample, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suite)!
        store = ReaderStore(defaults: defaults, github: GitHubReader(), sampleURL: sample)
    }

    func clean() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

// The synchronous database closure is Sendable, so its probe uses a lock rather than actor state.
private final class BackendProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    func record() { lock.lock(); defer { lock.unlock() }; calls += 1 }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
}

private enum AccountFailure: Error { case unavailable }

@Test @MainActor func deniedCloudKitNeverCreatesBackendOrChangesPreference() throws {
    for verdict in [CloudKitGate.Verdict.disabledByArgument, .missingEntitlement] {
        // Include an absent preference to check that the default-on case stays absent.
        let preferences: [Bool?] = [nil, true, false]
        for preference in preferences {
            let device = try AvailabilityDevice()
            defer { device.clean() }
            if let preference { device.defaults.set(preference, forKey: "iCloudSyncEnabled") }
            var backendCalls = 0
            let sync = ReaderSync(store: device.store, defaults: device.defaults, directory: device.root,
                                  verdict: verdict, makeBackend: {
                backendCalls += 1
                return CloudKitBackend(accountStatus: { throw AccountFailure.unavailable },
                                       database: { fatalError("A denied verdict must never access CloudKit") })
            })
            #expect(backendCalls == 0)
            #expect(sync.status == .off && !sync.isAvailable && !sync.isEnabled)
            sync.setEnabled(true)
            #expect(backendCalls == 0)
            #expect(sync.status == .off && !sync.isAvailable && !sync.isEnabled)
            #expect(device.defaults.object(forKey: "iCloudSyncEnabled") as? Bool == preference)
        }
    }
}

@Test @MainActor func unavailableAccountsNeverCreateDatabaseOrEngine() async throws {
    for restricted in [false, true] {
        let device = try AvailabilityDevice()
        defer { device.clean() }
        device.defaults.set(true, forKey: "iCloudSyncEnabled")
        let databaseCalls = BackendProbe()
        let accountCalls = BackendProbe()
        var backendCalls = 0
        let sync = ReaderSync(store: device.store, defaults: device.defaults, directory: device.root,
                              verdict: .allowed, makeBackend: {
            backendCalls += 1
            return CloudKitBackend(accountStatus: {
                accountCalls.record()
                if restricted { return .restricted }
                throw AccountFailure.unavailable
            }, database: {
                databaseCalls.record()
                fatalError("Unavailable accounts must never request a database")
            })
        })
        #expect(sync.status == .syncing)
        for _ in 0..<300 {
            if !sync.isAvailable { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(backendCalls == 1 && accountCalls.count == 1)
        #expect(!sync.isAvailable && !sync.isEnabled && sync.status == .off)
        #expect(databaseCalls.count == 0)
        sync.setEnabled(true)
        #expect(!sync.isEnabled && backendCalls == 1)
        #expect(device.defaults.bool(forKey: "iCloudSyncEnabled"))
    }
}

@Test @MainActor func allowedButDisabledPreferenceNeverCreatesBackend() throws {
    let device = try AvailabilityDevice()
    defer { device.clean() }
    device.defaults.set(false, forKey: "iCloudSyncEnabled")
    var backendCalls = 0
    let sync = ReaderSync(store: device.store, defaults: device.defaults, directory: device.root,
                          verdict: .allowed, makeBackend: {
        backendCalls += 1
        return CloudKitBackend(accountStatus: { .available }, database: { fatalError("A disabled preference must never request a database") })
    })
    #expect(backendCalls == 0)
    #expect(sync.isAvailable && !sync.isEnabled && sync.status == .off)
}

private actor PendingAccount {
    private var continuation: CheckedContinuation<CKAccountStatus, any Error>?
    var isWaiting: Bool { continuation != nil }
    func status() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func fail() {
        continuation?.resume(throwing: AccountFailure.unavailable)
        continuation = nil
    }
}

@Test @MainActor func disablingSyncInvalidatesPendingAccountCheck() async throws {
    let device = try AvailabilityDevice()
    defer { device.clean() }
    let pending = PendingAccount()
    let databaseCalls = BackendProbe()
    let sync = ReaderSync(store: device.store, defaults: device.defaults, directory: device.root,
                          verdict: .allowed, makeBackend: {
        CloudKitBackend(accountStatus: { try await pending.status() }, database: {
            databaseCalls.record()
            fatalError("A stopped startup must never request a database")
        })
    })
    for _ in 0..<300 {
        if await pending.isWaiting { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    let waiting = await pending.isWaiting
    #expect(waiting)
    sync.setEnabled(false)
    await pending.fail()
    // Give the resumed preflight task an opportunity to report its stale failure.
    for _ in 0..<20 { await Task.yield() }
    #expect(sync.isAvailable && !sync.isEnabled && sync.status == .off)
    #expect(databaseCalls.count == 0)
    #expect(device.defaults.object(forKey: "iCloudSyncEnabled") as? Bool == false)
}

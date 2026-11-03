import CloudKit
import Foundation
import ReaderCore
import os
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Mirrors ReaderStore's shared data into the user's private CloudKit database.
/// Local data stays the source of truth for the UI; any CloudKit failure leaves the app working as before.
@MainActor final class ReaderSync: ObservableObject, CKSyncEngineDelegate {
    static let containerID = "iCloud.io.github.wivnelo.imdreader"
    enum Status { case off, signedOut, syncing, synced, retrying }
    @Published private(set) var status: Status = .off
    @Published private(set) var isEnabled: Bool
    private struct Persisted: Codable {
        var state: SyncState
        var systemFields: [String: Data] = [:]
        var engine: CKSyncEngine.State.Serialization?
    }
    private let store: ReaderStore
    private let container: CKContainer
    private let database: CKDatabase
    private let defaults: UserDefaults
    /// A save failed during the current exchange; the engine retries on its own schedule.
    private var failedThisRound = false
    private let fileURL: URL
    private let device: String
    private var persisted: Persisted
    private var engine: CKSyncEngine?
    private var capturing: Task<Void, Never>?
    private var uploading: Task<Void, Never>?
    /// Records seen during the first fetch; identical ones are not uploaded again.
    private var firstFetch: [String: CKRecord]?
    private var observers: [NSObjectProtocol] = []
    private let log = Logger(subsystem: "iMDReader", category: "sync")

    init(store: ReaderStore, defaults: UserDefaults = .standard, directory: URL? = nil,
         container: CKContainer = CKContainer(identifier: containerID)) {
        self.store = store
        self.container = container
        self.defaults = defaults
        database = container.privateCloudDatabase
        isEnabled = defaults.object(forKey: "iCloudSyncEnabled") as? Bool ?? true
        let folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sync", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("state.json")
        if let saved = defaults.string(forKey: "syncDeviceID") { device = saved }
        else { device = UUID().uuidString; defaults.set(device, forKey: "syncDeviceID") }
        persisted = (try? JSONDecoder().decode(Persisted.self, from: Data(contentsOf: fileURL)))
            ?? Persisted(state: SyncState(stamp: .legacy(device: device)))
        if isEnabled { start() }
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCapture() }
        })
        #if os(macOS)
        let resign = NSApplication.willResignActiveNotification
        #else
        let resign = UIApplication.willResignActiveNotification
        #endif
        observers.append(NotificationCenter.default.addObserver(forName: resign, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.capture() }
        })
    }

    /// Existing local data predates sync, so any value already in iCloud wins over it.
    private static func legacy(_ store: ReaderStore, device: String) -> Persisted {
        var state = SyncState(stamp: .legacy(device: device))
        state.absorb(store.syncSnapshot(), at: .legacy(device: device), now: Date(timeIntervalSince1970: 0))
        return Persisted(state: state)
    }

    private func start() {
        let fresh = persisted.engine == nil
        if fresh { persisted = Self.legacy(store, device: device) }
        status = .syncing
        startEngine(fresh: fresh)
        Task { [weak self] in
            guard let self, let account = try? await self.container.accountStatus(), self.engine != nil else { return }
            if account != .available { self.status = .signedOut }
        }
    }

    /// Turning sync off stops all CloudKit traffic but keeps local data, the iCloud copy and sync bookkeeping,
    /// so turning it back on continues where it left off.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: "iCloudSyncEnabled")
        if enabled {
            start()
            Task { [weak self] in await self?.syncNow() }
        } else {
            capturing?.cancel(); capturing = nil
            uploading?.cancel(); uploading = nil
            engine = nil
            status = .off
            save()
        }
    }

    private func startEngine(fresh: Bool) {
        let engine = CKSyncEngine(.init(database: database, stateSerialization: persisted.engine, delegate: self))
        self.engine = engine
        guard fresh else { return }
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecords.zoneID))])
        save()
        firstFetch = [:]
        // Merge what iCloud already has before uploading, so stale local values never flash on other devices.
        uploading = Task { [weak self] in
            try? await engine.fetchChanges()
            guard let self, self.engine === engine else { return }
            var delta = SyncRecords.changes(from: SyncState(stamp: .legacy(device: self.device)), to: self.persisted.state)
            let seen = self.firstFetch ?? [:]
            delta.save = delta.save.filter { name in seen[name].map { !SyncRecords.matches($0, self.persisted.state) } ?? true }
            self.firstFetch = nil
            self.enqueue(delta); self.save()
        }
    }

    /// Account switch or zone loss: forget sync bookkeeping, keep every local item, start over.
    private func reset() {
        uploading?.cancel(); uploading = nil
        persisted = Self.legacy(store, device: device)
        startEngine(fresh: true)
    }

    private func scheduleCapture() {
        guard engine != nil else { return }
        capturing?.cancel()
        // Reading progress changes continuously; upload once scrolling settles.
        capturing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.capture() }
        }
    }

    /// Records local edits and exchanges changes now instead of waiting for the engine's schedule.
    func syncNow() async {
        while let task = uploading {
            await task.value
            if uploading == task { uploading = nil }
        }
        capture()
        do {
            try await engine?.sendChanges()
            try await engine?.fetchChanges()
        } catch { log.error("Sync now failed: \(error.localizedDescription)") }
    }

    private func capture() {
        capturing?.cancel(); capturing = nil
        guard engine != nil else { return }
        let old = persisted.state
        persisted.state.absorb(store.syncSnapshot(), at: SyncStamp(time: .now, device: device), now: .now)
        let delta = SyncRecords.changes(from: old, to: persisted.state)
        guard !delta.save.isEmpty || !delta.delete.isEmpty else { return }
        enqueue(delta); save()
    }

    private func enqueue(_ delta: (save: Set<String>, delete: Set<String>)) {
        let id = { CKRecord.ID(recordName: $0, zoneID: SyncRecords.zoneID) }
        engine?.state.add(pendingRecordZoneChanges: delta.save.sorted().map { .saveRecord(id($0)) }
                          + delta.delete.sorted().map { .deleteRecord(id($0)) })
    }

    private func save() {
        do { try JSONEncoder().encode(persisted).write(to: fileURL, options: .atomic) }
        catch { log.error("Saving sync state failed: \(error.localizedDescription)") }
    }

    /// Merges server records, applies the result locally, and re-sends only what the server lacks.
    private func receive(_ records: [CKRecord], deleted: [String] = []) {
        capture()
        let old = persisted.state
        var incoming: [String: CKRecord] = [:]
        for record in records {
            let name = record.recordID.recordName
            persisted.systemFields[name] = Self.systemFields(record)
            incoming[name] = record
            firstFetch?[name] = record
            persisted.state = SyncState.merge(persisted.state, SyncRecords.fragment(record)).state
        }
        for name in deleted {
            persisted.systemFields[name] = nil
            if let key = SyncRecords.positionKey(forDeleted: name, in: persisted.state) { persisted.state.positions[key] = nil }
        }
        store.applySynced(persisted.state)
        var delta = SyncRecords.changes(from: old, to: persisted.state)
        delta.save = delta.save.filter { name in incoming[name].map { !SyncRecords.matches($0, persisted.state) } ?? true }
        delta.delete.subtract(deleted)
        enqueue(delta); save()
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine else { return } // A stopped or replaced engine may still report.
        switch event {
        case .willFetchChanges, .willSendChanges:
            if status != .signedOut { status = .syncing }
        case .didFetchChanges, .didSendChanges:
            if status != .signedOut { status = failedThisRound ? .retrying : .synced }
            failedThisRound = false
        case .stateUpdate(let update):
            persisted.engine = update.stateSerialization; save()
        case .accountChange(let change):
            switch change.changeType {
            case .signIn: status = .syncing
            case .signOut: status = .signedOut; reset()
            case .switchAccounts: reset()
            @unknown default: break
            }
        case .fetchedDatabaseChanges(let changes):
            // A zone deleted before this device ever synced needs no reset; the pending zone save recreates it.
            if !persisted.systemFields.isEmpty, changes.deletions.contains(where: { $0.zoneID == SyncRecords.zoneID }) { reset() }
        case .fetchedRecordZoneChanges(let changes):
            receive(changes.modifications.map(\.record), deleted: changes.deletions.map(\.recordID.recordName))
        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords { persisted.systemFields[record.recordID.recordName] = Self.systemFields(record) }
            var retry: [CKRecord] = []
            for failure in sent.failedRecordSaves {
                let name = failure.record.recordID.recordName
                switch failure.error.code {
                case .serverRecordChanged:
                    if let server = failure.error.serverRecord { retry.append(server) }
                case .zoneNotFound:
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecords.zoneID))])
                    enqueue(([name], []))
                case .unknownItem:
                    persisted.systemFields[name] = nil
                    enqueue(([name], []))
                default:
                    failedThisRound = true
                    log.error("Sync save failed: \(failure.error.localizedDescription)")
                }
            }
            if !retry.isEmpty {
                receive(retry)
                // The server copy is now cached; resend our merged value on top of it.
                enqueue((Set(retry.map(\.recordID.recordName).filter { name in
                    !SyncRecords.matches(retry.first { $0.recordID.recordName == name }!, persisted.state)
                }), []))
            }
            save()
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === engine else { return nil }
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in await self.record(for: id) }
    }

    private func record(for id: CKRecord.ID) -> CKRecord? {
        let name = id.recordName
        let base = persisted.systemFields[name].flatMap(Self.restore)
            ?? CKRecord(recordType: SyncRecords.recordType(for: name), recordID: id)
        return SyncRecords.fill(base, from: persisted.state)
    }

    private static func systemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        return coder.encodedData
    }
    private static func restore(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        return CKRecord(coder: coder)
    }
}

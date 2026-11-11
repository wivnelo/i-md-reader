import Foundation
import Testing
@testable import ReaderCore

@MainActor
private final class PendingPurchaseResponse {
    var continuation: CheckedContinuation<Int, Never>?
    var calls = 0

    func value() async -> Int {
        calls += 1
        // Deliberately ignores cancellation, like a system authentication flow.
        return await withCheckedContinuation { continuation = $0 }
    }

    func complete(_ value: Int) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@Test @MainActor func purchaseDeadlineReturnsSuccessAndOriginalError() async throws {
    let value = try await withPurchaseDeadline(.seconds(1)) { 42 }
    #expect(value == 42)
    enum Failure: Error { case unavailable }
    await #expect(throws: Failure.unavailable) {
        try await withPurchaseDeadline(.seconds(1)) { () -> Int in throw Failure.unavailable }
    }
}

@Test @MainActor func purchaseDeadlineReturnsWithoutWaitingForUncooperativeOperation() async {
    let response = PendingPurchaseResponse()
    await #expect(throws: PurchaseRequestError.timedOut) {
        try await withPurchaseDeadline(.milliseconds(30)) { await response.value() }
    }
    #expect(response.calls == 1)
    #expect(response.continuation != nil)
    response.complete(1)
    await Task.yield() // A late completion must not resume the caller twice.
}

@Test @MainActor func purchaseDeadlineRetryIsIndependentOfLateCatalogResponse() async throws {
    let oldResponse = PendingPurchaseResponse()
    await #expect(throws: PurchaseRequestError.timedOut) {
        try await withPurchaseDeadline(.milliseconds(30)) { await oldResponse.value() }
    }
    let latest = try await withPurchaseDeadline(.seconds(1)) { 2 }
    oldResponse.complete(1)
    await Task.yield()
    #expect(latest == 2)
}

@Test @MainActor func purchaseDeadlineCancellationReturnsBeforeSystemOperationFinishes() async {
    let response = PendingPurchaseResponse()
    let caller = Task { try await withPurchaseDeadline(.seconds(60)) { await response.value() } }
    while response.continuation == nil { await Task.yield() }
    caller.cancel()
    await #expect(throws: CancellationError.self) { try await caller.value }
    response.complete(1)
    await Task.yield()
}

@Test @MainActor func purchaseRestoreRetryKeepsOneUnderlyingAuthentication() async throws {
    let response = PendingPurchaseResponse()
    let underlying = Task { await response.value() }
    await #expect(throws: PurchaseRequestError.timedOut) {
        try await withPurchaseDeadline(.milliseconds(30)) { await underlying.value }
    }
    #expect(!underlying.isCancelled)
    let retry = Task { try await withPurchaseDeadline(.seconds(1)) { await underlying.value } }
    response.complete(7)
    #expect(try await retry.value == 7)
    #expect(response.calls == 1)
}

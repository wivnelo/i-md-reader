import Foundation

public enum PurchaseRequestError: Error, Equatable, Sendable {
    case timedOut
}

/// Bounds the caller's wait even if a framework operation ignores cancellation.
/// A timeout is not proof that an Apple transaction was cancelled. Transaction
/// callers must keep their underlying task and reconcile its eventual result.
@MainActor
public func withPurchaseDeadline<Value: Sendable>(
    _ duration: Duration,
    operation: @escaping @MainActor @Sendable () async throws -> Value
) async throws -> Value {
    let race = PurchaseDeadlineRace<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.start(continuation, duration: duration, operation: operation)
            if Task.isCancelled { race.finish(.failure(CancellationError())) }
        }
    } onCancel: {
        Task { @MainActor in race.finish(.failure(CancellationError())) }
    }
}

@MainActor
private final class PurchaseDeadlineRace<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, any Error>?
    private var work: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    func start(_ continuation: CheckedContinuation<Value, any Error>, duration: Duration,
               operation: @escaping @MainActor @Sendable () async throws -> Value) {
        self.continuation = continuation
        work = Task {
            do {
                try Task.checkCancellation()
                self.finish(.success(try await operation()))
            }
            catch { self.finish(.failure(error)) }
        }
        timer = Task {
            do { try await Task.sleep(for: duration) }
            catch { return }
            self.finish(.failure(PurchaseRequestError.timedOut))
        }
    }

    func finish(_ result: Result<Value, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        work?.cancel()
        timer?.cancel()
        work = nil
        timer = nil
        continuation.resume(with: result)
    }
}

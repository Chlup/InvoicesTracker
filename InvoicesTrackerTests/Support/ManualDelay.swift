import Foundation
import os
@testable import InvoicesTracker

/// The wait before a save, for the tests that say when it is over: no wait of it ends by itself. `fire()` ends the one
/// that was started last and still waits, as the end of the delay would; one that is cancelled ends with a
/// `CancellationError`, as `Task.sleep` does. The counts say how many waits were started, how many of them were
/// cancelled, and how many are still waiting, so that a test can see that each key of a text started the wait again.
final class ManualDelay: Sendable {
    private struct State {
        var nextID = 0
        var started = 0
        var cancelled = 0
        var waiting: [Int: CheckedContinuation<Void, any Error>] = [:]
        var cancelledBeforeWaiting: Set<Int> = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// The wait as the model takes it. It ignores the length of the delay.
    var wait: @Sendable (Duration) async throws -> Void {
        { [self] _ in try await waitUntilFired() }
    }

    /// How many waits were started.
    var started: Int {
        state.withLock { $0.started }
    }

    /// How many of them were cancelled.
    var cancelled: Int {
        state.withLock { $0.cancelled }
    }

    /// How many of them are waiting: started, and neither cancelled nor ended.
    var armed: Int {
        state.withLock { $0.waiting.count }
    }

    /// Ends the wait that was started last and still waits, as its delay would. Returns false when none waits.
    @discardableResult
    func fire() -> Bool {
        let continuation = state.withLock { state -> CheckedContinuation<Void, any Error>? in
            guard let id = state.waiting.keys.max() else { return nil }
            return state.waiting.removeValue(forKey: id)
        }
        continuation?.resume()
        return continuation != nil
    }

    private func waitUntilFired() async throws {
        let id = state.withLock { state -> Int in
            state.nextID += 1
            state.started += 1
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // A task that was cancelled before the wait was set up ends it at once.
                let cancelledAlready = state.withLock { state -> Bool in
                    if state.cancelledBeforeWaiting.remove(id) != nil {
                        return true
                    }
                    state.waiting[id] = continuation
                    return false
                }
                if cancelledAlready {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let continuation = state.withLock { state -> CheckedContinuation<Void, any Error>? in
                state.cancelled += 1
                if let continuation = state.waiting.removeValue(forKey: id) {
                    return continuation
                }
                state.cancelledBeforeWaiting.insert(id)
                return nil
            }
            continuation?.resume(throwing: CancellationError())
        }
    }
}

/// A wait that does not notice that its task was cancelled, as a timer does that has run out in the moment the next key
/// replaced it: it ends when the test fires it, whatever happened to its task. `fireOldest()` ends the wait that was
/// started first and still waits, which is the one of the timer that was replaced.
final class StubbornDelay: Sendable {
    private let continuations = OSAllocatedUnfairLock(initialState: [CheckedContinuation<Void, Never>]())

    /// The wait as the model takes it. It ignores the length of the delay.
    var wait: @Sendable (Duration) async throws -> Void {
        { [self] _ in
            await withCheckedContinuation { continuation in
                continuations.withLock { $0.append(continuation) }
            }
        }
    }

    /// How many waits were started and have not ended.
    var armed: Int {
        continuations.withLock { $0.count }
    }

    /// Ends the wait that was started first and still waits. Returns false when none waits.
    @discardableResult
    func fireOldest() -> Bool {
        let continuation = continuations.withLock { waiting -> CheckedContinuation<Void, Never>? in
            waiting.isEmpty ? nil : waiting.removeFirst()
        }
        continuation?.resume()
        return continuation != nil
    }
}

/// Returns once the jobs that wait for the main actor now have run, as far as they run without waiting for anything
/// themselves: what a wait that was just ended lets its task do next.
@MainActor
func letWaitingJobsRun() async {
    await Task { @MainActor in }.value
}

/// The limit of what the app bounds with a wait (`AppDependencies.sleep`), for a test that sets something up first: the
/// wait lasts until its task is cancelled, until the test says with `runOut()` that the limit is over; from then on
/// every wait ends as soon as it is asked for. `asked` counts the waits, so that a test can see that a wait was not
/// asked for again.
final class LimitSwitch: Sendable {
    private struct State {
        var isOver = false
        var asked = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// How many waits were asked for.
    var asked: Int {
        state.withLock { $0.asked }
    }

    /// The limit is over: the waits that are asked for, and those that wait now, end.
    func runOut() {
        state.withLock { $0.isOver = true }
    }

    /// The wait as the app takes it. It ignores the length it is given.
    var wait: @Sendable (Duration) async throws -> Void {
        { [self] _ in
            state.withLock { $0.asked += 1 }
            while !state.withLock({ $0.isOver }) {
                try await Task.sleep(for: .milliseconds(2))
            }
        }
    }
}

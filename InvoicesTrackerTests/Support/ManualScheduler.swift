import Foundation
import os
@testable import InvoicesTracker

/// A `RefreshScheduler` for tests: it sets no real timer. It remembers every wake it was asked for, with its tolerance,
/// in the order of the requests, and which of them were cancelled. `fire()` runs the wake that is still armed, when the
/// test says so, and `untilAWakeIsAsked()` waits for the first request.
final class ManualScheduler: RefreshScheduler {
    /// One request to wake at `date`, `tolerance` seconds later at the most.
    struct Wake: Sendable, Hashable {
        let date: Date
        let tolerance: TimeInterval
    }

    private struct Entry: Sendable {
        let wake: Wake
        let fire: @Sendable () -> Void
        var cancelled = false
        var fired = false
    }

    /// The wakes asked for, and the callers that wait for the first of them: both under one lock, so that a request
    /// never comes between a caller seeing that there is none and its waiting.
    private struct State: Sendable {
        var entries: [Entry] = []
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func schedule(
        at date: Date, tolerance: TimeInterval, _ fire: @escaping @Sendable () -> Void
    ) -> any RefreshCancellable {
        let (index, waiting) = state.withLock { state in
            state.entries.append(Entry(wake: Wake(date: date, tolerance: tolerance), fire: fire))
            let waiting = state.waiting
            state.waiting = []
            return (state.entries.count - 1, waiting)
        }
        for continuation in waiting {
            continuation.resume()
        }
        return ManualCancellation(scheduler: self, index: index)
    }

    /// Every wake asked for so far, in order, cancelled or not.
    var wakes: [Wake] {
        state.withLock { $0.entries.map(\.wake) }
    }

    /// The dates of the wakes that are armed: asked for, and neither cancelled nor fired.
    var armed: [Date] {
        state.withLock { $0.entries.filter { !$0.cancelled && !$0.fired }.map(\.wake.date) }
    }

    /// Fires the latest armed wake, as its timer would at its date. Returns false when no wake is armed.
    @discardableResult
    func fire() -> Bool {
        let fire = state.withLock { state -> (@Sendable () -> Void)? in
            guard let index = state.entries.lastIndex(where: { !$0.cancelled && !$0.fired }) else { return nil }
            state.entries[index].fired = true
            return state.entries[index].fire
        }
        fire?()
        return fire != nil
    }

    /// Returns once a wake has been asked for: at once when one was already, otherwise when the first one is. This is
    /// for what the refresh does in a task of its own, such as the launch that starting it makes, which asks for its
    /// wake as the last step of its run. Nothing limits the wait but the limit of the test.
    func untilAWakeIsAsked() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let asked = state.withLock { state -> Bool in
                if !state.entries.isEmpty {
                    return true
                }
                state.waiting.append(continuation)
                return false
            }
            if asked {
                continuation.resume()
            }
        }
    }

    fileprivate func cancel(_ index: Int) {
        state.withLock { $0.entries[index].cancelled = true }
    }
}

/// Cancels one wake of a `ManualScheduler`.
private final class ManualCancellation: RefreshCancellable {
    let scheduler: ManualScheduler
    let index: Int

    init(scheduler: ManualScheduler, index: Int) {
        self.scheduler = scheduler
        self.index = index
    }

    func cancel() {
        scheduler.cancel(index)
    }
}

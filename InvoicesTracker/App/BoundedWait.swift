import Foundation
import os

/// Waiting for work that may never end, for no longer than a limit: a backup to a disk or a share that does not
/// answer, the saves of a quit.
@MainActor
enum BoundedWait {
    /// What `work` gives, or nil when `limit` ran out first, which `sleep` counts (`AppDependencies.sleep`). `work` is
    /// not stopped when the limit runs out: it goes on, and what it gives is dropped. Both start at once, up to their
    /// first wait, so the limit is asked for before `work` begins.
    static func result<T: Sendable>(
        of work: @escaping @MainActor () async -> T, within limit: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            // Whichever of the two ends first goes on; the other one is left to end by itself.
            let answered = OSAllocatedUnfairLock(initialState: false)
            let goOn: @Sendable (T?) -> Void = { value in
                let isFirst = answered.withLock { flag -> Bool in
                    let wasSet = flag
                    flag = true
                    return !wasSet
                }
                if isFirst {
                    continuation.resume(returning: value)
                }
            }
            let timer = Task.immediate {
                try? await sleep(limit)
                goOn(nil)
            }
            Task.immediate {
                let value = await work()
                timer.cancel()
                goOn(value)
            }
        }
    }
}

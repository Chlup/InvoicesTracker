import Foundation
import Testing
import os
@testable import InvoicesTracker

/// The timer of the app, with the real clock: it fires at its date, at once for a date that has passed, and not at all
/// when it is cancelled.
struct TimerSchedulerTests {
    @Test(.hangGuard)
    func aTimerFiresAtItsDateAndNotBefore() async throws {
        let start = Date()
        let firedAt = OSAllocatedUnfairLock<Date?>(initialState: nil)
        var timer: (any RefreshCancellable)?
        await withCheckedContinuation { continuation in
            timer = TimerScheduler().schedule(at: start.addingTimeInterval(0.2), tolerance: 0) {
                firedAt.withLock { $0 = Date() }
                continuation.resume()
            }
        }
        timer?.cancel()
        let fired = try #require(firedAt.withLock { $0 })
        #expect(fired.timeIntervalSince(start) >= 0.19)
    }

    @Test(.hangGuard)
    func aTimerForADateThatHasPassedFiresAtOnce() async {
        var timer: (any RefreshCancellable)?
        await withCheckedContinuation { continuation in
            timer = TimerScheduler().schedule(at: Date().addingTimeInterval(-60), tolerance: 0) {
                continuation.resume()
            }
        }
        timer?.cancel()
    }

    @Test func aCancelledTimerDoesNotFire() async throws {
        let fired = OSAllocatedUnfairLock(initialState: false)
        let timer = TimerScheduler().schedule(at: Date().addingTimeInterval(0.1), tolerance: 0) {
            fired.withLock { $0 = true }
        }
        timer.cancel()
        try await Task.sleep(for: .milliseconds(400))
        #expect(!fired.withLock { $0 })
    }
}

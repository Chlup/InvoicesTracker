import Foundation
import Testing
@testable import InvoicesTracker

/// The wait before a save of the screens that save what is typed a moment after the last key.
@MainActor
struct DebounceTimerTests {
    /// The saves the timer ran, in order.
    @MainActor
    private final class Saves {
        var made: [String] = []
    }

    /// Every restart starts the wait again and only the last one saves, also when a replaced wait ends all the same (a
    /// timer that ran out as the next key came); a stop saves nothing, and no delay at all is no wait.
    @Test(.hangGuard)
    func onlyTheLastWaitSavesOnceItHasRunOut() async throws {
        let saves = Saves()
        let delay = StubbornDelay()
        let timer = DebounceTimer(wait: delay.wait)

        timer.restart(after: .milliseconds(500)) { saves.made.append("first key") }
        try await waitUntil { delay.armed == 1 }
        timer.restart(after: .milliseconds(500)) { saves.made.append("second key") }
        try await waitUntil { delay.armed == 2 }

        // The replaced wait ends anyway: it saves nothing.
        #expect(delay.fireOldest())
        await letWaitingJobsRun()
        #expect(saves.made.isEmpty)
        // The wait of the last key saves.
        #expect(delay.fireOldest())
        try await waitUntil { saves.made == ["second key"] }

        // A wait that is stopped saves nothing when it ends.
        timer.restart(after: .milliseconds(500)) { saves.made.append("stopped") }
        try await waitUntil { delay.armed == 1 }
        timer.cancel()
        #expect(delay.fireOldest())
        await letWaitingJobsRun()
        #expect(saves.made == ["second key"])

        // No delay at all saves without a wait.
        timer.restart(after: .zero) { saves.made.append("at once") }
        try await waitUntil { saves.made == ["second key", "at once"] }
        #expect(delay.armed == 0)
    }
}

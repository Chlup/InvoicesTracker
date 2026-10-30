import Foundation
import Testing
@testable import InvoicesTracker

/// The two ways a test waits for what the app does in a task of its own: `waitUntil(_:)`, which looks at a condition,
/// and `ManualScheduler.untilAWakeIsAsked()`, which waits for the first wake of the refresh.
@MainActor
struct WaitingHelperTests {
    @Test func timeThatALookWaitedForItsTurnIsNotTimeThatTheConditionDidNotHold() async throws {
        var looks = 0

        // Each look is held up for a third of a second, as a busy process holds up a look in a full run of the suite,
        // and the condition holds at the fifth: after more than the second it is given.
        try await waitUntil(timeout: .seconds(1)) {
            looks += 1
            try await Task.sleep(for: .milliseconds(300))
            return looks == 5
        }

        #expect(looks == 5)
    }

    @Test func aConditionThatNeverHoldsIsGivenUpOnWithAnIssueOnceItsTimeIsUp() async throws {
        var looks = 0

        await withKnownIssue("The condition never holds.") {
            try await waitUntil(timeout: .milliseconds(100)) {
                looks += 1
                return false
            }
        }

        #expect(looks > 1)
    }

    @Test func aConditionThatHoldsAtOnceIsLookedAtOnce() async throws {
        var looks = 0

        try await waitUntil {
            looks += 1
            return true
        }

        #expect(looks == 1)
    }

    @Test func theSchedulerTellsOfTheFirstWakeWhenItIsAskedForAndAtOnceAfterIt() async {
        let scheduler = ManualScheduler()
        // The wait has begun when its task is made.
        let waiting = Task.immediate { await scheduler.untilAWakeIsAsked() }

        _ = scheduler.schedule(at: date("2026-10-17T12:35:00Z"), tolerance: 60) {}
        await waiting.value
        // A wake that was asked for already is no wait.
        await scheduler.untilAWakeIsAsked()

        #expect(scheduler.wakes.count == 1)
    }
}

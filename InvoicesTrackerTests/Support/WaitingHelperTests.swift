import Foundation
import Testing
@testable import InvoicesTracker

/// The ways a test waits for what the app does in a task of its own: `waitUntil(_:)`, which looks at a condition and
/// records an issue when it never holds, `holdsWithin(_:every:_:)`, the same wait that tells whether the condition
/// held, and `ManualScheduler.untilAWakeIsAsked()`, which waits for the first wake of the refresh.
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

    /// A condition that never holds is given up on after its time, and the wait says so by its answer, not by an issue:
    /// the test that waits decides what to say.
    @Test func aConditionThatNeverHoldsIsReportedAsNotHoldingWithoutAnIssue() async throws {
        var looks = 0

        let held = try await holdsWithin(.milliseconds(100)) {
            looks += 1
            return false
        }

        #expect(!held)
        #expect(looks > 1)
    }

    /// A condition that holds at a look is reported as holding, and is not looked at again.
    @Test func aConditionThatHoldsAtTheThirdLookIsReportedAsHoldingAndNotLookedAtAgain() async throws {
        var looks = 0

        let held = try await holdsWithin(.seconds(1), every: .milliseconds(1)) {
            looks += 1
            return looks == 3
        }

        #expect(held)
        #expect(looks == 3)
    }

    /// The time a look waited for its turn is not time the condition did not hold, as it is not for `waitUntil`.
    @Test func timeThatALookWaitedForItsTurnDoesNotCountAgainstTheTimeOfAConditionThatHolds() async throws {
        var looks = 0

        // Each look is held up for a third of a second, and the condition holds at the fifth: after more than the
        // second it is given.
        let held = try await holdsWithin(.seconds(1)) {
            looks += 1
            try await Task.sleep(for: .milliseconds(300))
            return looks == 5
        }

        #expect(held)
    }

    /// The looks are as far apart as `every:` says: a condition that holds at the third look, 100 milliseconds apart,
    /// is found no sooner than 200 milliseconds after the first, where looks at the default of 5 milliseconds would
    /// find it in a tenth of that.
    @Test func theLooksAreAsFarApartAsTheyAreToldToBe() async throws {
        let clock = ContinuousClock()
        var looks = 0
        let started = clock.now

        let held = try await holdsWithin(.seconds(5), every: .milliseconds(100)) {
            looks += 1
            return looks == 3
        }

        #expect(held)
        #expect(clock.now - started >= .milliseconds(200), "The third look came after \(clock.now - started)")
    }

    /// A look is charged at most 50 milliseconds, or its interval where that is longer. Looks 200 milliseconds apart
    /// use up a second at the sixth, and a condition that would hold at the seventh is given up on; a charge of 50
    /// milliseconds for each would have let it be found.
    @Test func aLookIsChargedItsIntervalWhereThatIsLongerThanFiftyMilliseconds() async throws {
        var looks = 0

        let held = try await holdsWithin(.seconds(1), every: .milliseconds(200)) {
            looks += 1
            return looks == 7
        }

        #expect(!held)
        #expect(looks == 6, "The condition was looked at \(looks) times")
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

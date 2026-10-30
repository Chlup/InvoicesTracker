import Foundation
import Testing
@testable import InvoicesTracker

/// The pure plan of the refresh: the ČNB declaration the cache should have by now, what is due, and when to wake next.
/// The times are UTC instants. Prague is UTC+2 until 25 October 2026 at 03:00 and UTC+1 after it; it goes back to UTC+2
/// on 28 March 2027.
struct RefreshPlannerTests {
    // MARK: Helpers

    private let prague = CzechCalendar.prague

    private var newYork: TimeZone {
        guard let zone = TimeZone(identifier: "America/New_York") else {
            preconditionFailure("The time zone America/New_York is missing.")
        }
        return zone
    }

    /// A state whose cache has ČNB rates up to `newest`, or none.
    private func state(newest: String?) -> RefreshState {
        var state = RefreshState()
        state.newestCNBDeclaration = newest.map(civilDate)
        return state
    }

    /// A state whose cache has rates up to `newest` and whose finished year `year` has no uniform rate.
    private func state(newest: String, finished year: Int) -> RefreshState {
        var state = state(newest: newest)
        state.finishedYearsWithoutUniformRate = [year]
        return state
    }

    private func actions(at now: String, _ state: RefreshState) -> [RefreshAction] {
        RefreshPlanner.actionsDue(now: date(now), state: state)
    }

    private func wake(
        at now: String, _ state: RefreshState, followsToday: Bool = false, in zone: TimeZone? = nil
    ) -> Date {
        RefreshPlanner.nextWake(
            now: date(now), state: state, followsToday: followsToday, localTimeZone: zone ?? prague)
    }

    private func days(_ isos: String...) -> [CivilDate] {
        isos.map(civilDate)
    }

    // MARK: The newest declaration that should exist

    @Test(arguments: [
        // Friday 14:00 in Prague: the rates of the day are not declared yet.
        ("2026-10-16T12:00:00Z", "2026-10-15"),
        // Friday 14:31.
        ("2026-10-16T12:31:00Z", "2026-10-16"),
        // Saturday.
        ("2026-10-17T09:00:00Z", "2026-10-16"),
        // Wednesday 28 October, a public holiday, 14:00 in winter time.
        ("2026-10-28T13:00:00Z", "2026-10-27"),
        // New Year's Day: the last business day of the year before.
        ("2026-01-01T09:00:00Z", "2025-12-31"),
        // Friday 2 January 15:00, the first fixing of the year.
        ("2026-01-02T14:00:00Z", "2026-01-02"),
    ])
    func theNewestDeclarationIsTodaysFrom1430OnABusinessDayElseThePreviousBusinessDays(
        _ now: String, _ expected: String
    ) {
        #expect(RefreshPlanner.expectedNewestDeclaration(now: date(now)) == civilDate(expected))
    }

    @Test func theRatesOfTheDayAreExpectedFrom1430InPragueInSummerAndInWinterTime() {
        // 14:30 in Prague is 12:30 UTC in summer time and 13:30 UTC in winter time.
        #expect(RefreshPlanner.expectedNewestDeclaration(now: date("2026-10-23T12:29:59Z")) == civilDate("2026-10-22"))
        #expect(RefreshPlanner.expectedNewestDeclaration(now: date("2026-10-23T12:30:00Z")) == civilDate("2026-10-23"))
        #expect(RefreshPlanner.expectedNewestDeclaration(now: date("2026-10-26T13:29:59Z")) == civilDate("2026-10-23"))
        #expect(RefreshPlanner.expectedNewestDeclaration(now: date("2026-10-26T13:30:00Z")) == civilDate("2026-10-26"))
    }

    // MARK: ČNB rates due

    @Test func twoMissingBusinessDaysAreFetchedDayByDay() {
        let due = actions(at: "2026-10-16T13:00:00Z", state(newest: "2026-10-14"))
        #expect(due == [.fetchCNBDays(days("2026-10-15", "2026-10-16"))])
    }

    @Test func aGapOfMoreThanTenBusinessDaysIsFetchedAsTheYearlyFile() {
        let due = actions(at: "2026-10-16T13:00:00Z", state(newest: "2026-09-01"))
        #expect(due == [.fetchCNBYears([2026])])
    }

    @Test func tenMissingBusinessDaysAreStillFetchedDayByDayButElevenAreNot() {
        // From Friday 2 October to Friday 16 October there are ten business days, from Thursday 1 October eleven.
        let ten = actions(at: "2026-10-16T13:00:00Z", state(newest: "2026-10-02"))
        #expect(
            ten == [
                .fetchCNBDays(
                    days(
                        "2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-12",
                        "2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16"))
            ])
        #expect(actions(at: "2026-10-16T13:00:00Z", state(newest: "2026-10-01")) == [.fetchCNBYears([2026])])
    }

    @Test func weekendsAndHolidaysAreNotMissingDays() {
        // 24, 25 and 26 December are holidays and the 27th is a Sunday: only Monday the 28th is missing.
        let due = actions(at: "2026-12-28T15:00:00Z", state(newest: "2026-12-23"))
        #expect(due == [.fetchCNBDays(days("2026-12-28"))])
    }

    @Test func anEmptyCacheInJanuaryFetchesTheYearAndTheYearBefore() {
        #expect(actions(at: "2026-01-05T13:00:00Z", state(newest: nil)) == [.fetchCNBYears([2025, 2026])])
    }

    @Test func inJanuaryTheYearBeforeIsFetchedOnlyWhileItsLastDeclarationIsMissing() {
        // The cache has the last declaration of 2026, so only 2027 is fetched.
        #expect(actions(at: "2027-01-05T14:00:00Z", state(newest: "2026-12-31")) == [.fetchCNBYears([2027])])
        // It has not, so 2026 is fetched too.
        #expect(actions(at: "2027-01-05T14:00:00Z", state(newest: "2026-12-30")) == [.fetchCNBYears([2026, 2027])])
        // And an empty cache in January gets both.
        #expect(actions(at: "2026-01-05T13:00:00Z", state(newest: nil)) == [.fetchCNBYears([2025, 2026])])
    }

    @Test func anEmptyCacheLaterInTheYearFetchesTheYearOnly() {
        #expect(actions(at: "2026-10-16T13:00:00Z", state(newest: nil)) == [.fetchCNBYears([2026])])
    }

    @Test func aGapIntoANewYearIsFetchedAsTheYearlyFiles() {
        // Two business days are missing, but one of them is in the new year.
        let due = actions(at: "2026-01-02T14:00:00Z", state(newest: "2025-12-30"))
        #expect(due == [.fetchCNBYears([2025, 2026])])
        // In February the years involved are the year of the gap and the current one.
        #expect(actions(at: "2026-02-10T13:00:00Z", state(newest: "2025-12-15")) == [.fetchCNBYears([2025, 2026])])
    }

    @Test func aCurrentCacheOnSaturdayNeedsNothing() {
        #expect(actions(at: "2026-10-17T09:00:00Z", state(newest: "2026-10-16")) == [])
    }

    @Test func aCurrentCacheOnAHolidayNeedsNothing() {
        #expect(actions(at: "2026-10-28T13:00:00Z", state(newest: "2026-10-27")) == [])
    }

    @Test func afterAFailureTheNextAttemptWaitsHalfAnHourThenAnHourThenOnlyForTheNextTrigger() {
        var failed = state(newest: "2026-10-15")
        let dueAgain: [RefreshAction] = [.fetchCNBDays(days("2026-10-16"))]

        failed.cnbFailureCount = 1
        failed.lastCNBFailure = date("2026-10-16T12:35:00Z")
        #expect(actions(at: "2026-10-16T12:50:00Z", failed) == [])
        #expect(actions(at: "2026-10-16T13:05:00Z", failed) == dueAgain)

        failed.cnbFailureCount = 2
        failed.lastCNBFailure = date("2026-10-16T13:05:00Z")
        #expect(actions(at: "2026-10-16T14:04:00Z", failed) == [])
        #expect(actions(at: "2026-10-16T14:05:00Z", failed) == dueAgain)

        // After the third failure the timer waits for the next 14:35, and any trigger may try.
        failed.cnbFailureCount = 3
        failed.lastCNBFailure = date("2026-10-16T14:05:00Z")
        #expect(actions(at: "2026-10-16T14:06:00Z", failed) == dueAgain)
    }

    // MARK: The years that provisional payments wait for

    /// A state whose cache has rates up to `newest`, or none, and whose provisional payments of the days `paidOn` have
    /// no rate the cache can tell.
    private func state(newest: String?, paymentsWaitingOn paidOn: String...) -> RefreshState {
        var state = state(newest: newest)
        state.provisionalPaymentDays = paidOn.map(civilDate)
        return state
    }

    @Test func aProvisionalPaymentOfAYearTheCacheDoesNotHoldFetchesThatYear() {
        // Friday 15:00 in Prague with the rates of the day: the newest rates need nothing.
        let due = actions(at: "2026-10-16T13:00:00Z", state(newest: "2026-10-16", paymentsWaitingOn: "2025-03-20"))
        #expect(due == [.fetchCNBYearsForPayments([2025])])
    }

    @Test func eachYearIsAskedForOnceHoweverManyPaymentsWaitForIt() {
        let due = actions(
            at: "2026-10-16T13:00:00Z",
            state(newest: "2026-10-16", paymentsWaitingOn: "2022-06-30", "2025-03-20", "2025-11-03", "2022-01-14"))
        #expect(due == [.fetchCNBYearsForPayments([2022, 2025])])
    }

    @Test func thePaymentYearsComeAfterTheNewestRates() {
        let due = actions(at: "2026-10-16T13:00:00Z", state(newest: "2026-10-14", paymentsWaitingOn: "2025-03-20"))
        #expect(due == [.fetchCNBDays(days("2026-10-15", "2026-10-16")), .fetchCNBYearsForPayments([2025])])
    }

    @Test func aYearThatTheNewestRatesFetchAnywayIsNotFetchedTwice() {
        // The cache ends in December 2025, so the plan fetches the yearly files of 2025 and 2026 anyway.
        let due = actions(
            at: "2026-10-16T13:00:00Z", state(newest: "2025-12-10", paymentsWaitingOn: "2025-03-20", "2026-02-02"))
        #expect(due == [.fetchCNBYears([2025, 2026])])
        // An empty cache fetches the current year.
        #expect(
            actions(at: "2026-10-16T13:00:00Z", state(newest: nil, paymentsWaitingOn: "2026-02-02", "2025-03-20"))
                == [.fetchCNBYears([2026]), .fetchCNBYearsForPayments([2025])])
    }

    @Test func aPaymentAfterTheNewestCachedRatesWaitsForTheNewestRatesNotForTheYearlyFile() {
        // The daily files of 15 and 16 October bring the rate of the payment of the 15th.
        let due = actions(at: "2026-10-16T13:00:00Z", state(newest: "2026-10-14", paymentsWaitingOn: "2026-10-15"))
        #expect(due == [.fetchCNBDays(days("2026-10-15", "2026-10-16"))])
        // Its rates are not out yet: nothing more is fetched for it.
        #expect(actions(at: "2026-10-16T13:00:00Z", state(newest: "2026-10-16", paymentsWaitingOn: "2026-10-19")) == [])
    }

    @Test func aPaymentWhoseRateIsNotDeclaredYetFetchesNothing() {
        // Friday 12:00 in Prague: the rates of the day come after 14:30, and those of a later day later still.
        let due = actions(
            at: "2026-10-16T10:00:00Z", state(newest: "2026-10-15", paymentsWaitingOn: "2026-10-16", "2026-10-30"))
        #expect(due == [])
    }

    @Test func aPaymentAtTheStartOfAYearAlsoFetchesTheYearBefore() {
        // New Year's Day 2025 takes the last rate of 2024; Thursday 2 January 2025 is the first fixing of 2025, which
        // the last declaration of 2024 tells apart from a day the ČNB skipped.
        #expect(
            actions(at: "2026-10-16T13:00:00Z", state(newest: "2026-10-16", paymentsWaitingOn: "2025-01-01"))
                == [.fetchCNBYearsForPayments([2024])])
        #expect(
            actions(at: "2026-10-16T13:00:00Z", state(newest: "2026-10-16", paymentsWaitingOn: "2025-01-02"))
                == [.fetchCNBYearsForPayments([2024, 2025])])
    }

    @Test func thePaymentYearsWaitOutTheBackOffAfterAFailedRequest() {
        var failed = state(newest: "2026-10-16", paymentsWaitingOn: "2025-03-20")
        failed.cnbFailureCount = 1
        failed.lastCNBFailure = date("2026-10-16T13:00:00Z")

        #expect(actions(at: "2026-10-16T13:29:00Z", failed) == [])
        #expect(actions(at: "2026-10-16T13:30:00Z", failed) == [.fetchCNBYearsForPayments([2025])])
    }

    // MARK: The uniform rate due

    @Test func aFinishedYearIsCheckedFrom2JanuaryOnceADay() {
        var finished = state(newest: "2026-12-31", finished: 2026)
        #expect(actions(at: "2027-01-02T09:00:00Z", finished).contains(.checkUniformRate(2026)))
        #expect(actions(at: "2027-01-02T09:00:00Z", finished) == [.checkUniformRate(2026)])

        finished.lastUniformCheck = civilDate("2027-01-02")
        #expect(!actions(at: "2027-01-02T09:00:00Z", finished).contains(.checkUniformRate(2026)))
        #expect(actions(at: "2027-01-02T20:00:00Z", finished) == [])
        // The next day it is checked again.
        #expect(actions(at: "2027-01-03T09:00:00Z", finished) == [.checkUniformRate(2026)])
    }

    @Test func onNewYearsDayAFinishedYearIsNotCheckedYet() {
        #expect(actions(at: "2027-01-01T09:00:00Z", state(newest: "2026-12-31", finished: 2026)) == [])
    }

    @Test func on31MarchTheCheckComesWithAReminder() {
        let due = actions(at: "2027-03-31T08:00:00Z", state(newest: "2027-03-30", finished: 2026))
        #expect(due == [.checkUniformRate(2026), .uniformRateReminder(2026)])
    }

    @Test func aYearGivenUpOnIsNotCheckedAfter31March() {
        var givenUp = state(newest: "2027-03-31", finished: 2026)
        givenUp.gaveUpUniform = [2026]
        #expect(actions(at: "2027-04-01T08:00:00Z", givenUp) == [])
    }

    @Test func aYearNotGivenUpOnBy31MarchIsCheckedWithTheReminderAtTheNextChance() {
        // The app did not run on 31 March, so the reminder is still owed.
        let due = actions(at: "2027-04-02T08:00:00Z", state(newest: "2027-04-01", finished: 2026))
        #expect(due == [.checkUniformRate(2026), .uniformRateReminder(2026)])
    }

    /// Rates entered by hand stand in for the official uniform rates of a finished year: those are not looked for while
    /// they are stored, not even on 31 March, and are looked for again once they are removed.
    @Test func aYearWithAManualUniformRateIsNotSearched() {
        var manual = state(newest: "2027-01-29", finished: 2026)
        manual.finishedYearsWithManualUniformRate = [2026]
        #expect(actions(at: "2027-02-01T09:00:00Z", manual) == [])
        manual.newestCNBDeclaration = civilDate("2027-03-30")
        #expect(actions(at: "2027-03-31T08:00:00Z", manual) == [])

        // Removed, the year has no uniform rate at all: it is looked for, and on 31 March the reminder comes with it.
        manual.finishedYearsWithManualUniformRate = []
        #expect(actions(at: "2027-03-31T08:00:00Z", manual) == [.checkUniformRate(2026), .uniformRateReminder(2026)])
    }

    @Test func theRatesComeFirstAndTheUniformCheckAfterThem() {
        let due = actions(at: "2027-01-04T14:00:00Z", state(newest: "2026-12-31", finished: 2026))
        #expect(due == [.fetchCNBYears([2027]), .checkUniformRate(2026)])
    }

    // MARK: The next wake

    @Test func onABusinessDayBeforeTheRatesTheWakeIs1435InPrague() {
        #expect(wake(at: "2026-10-16T08:00:00Z", state(newest: "2026-10-15")) == date("2026-10-16T12:35:00Z"))
    }

    @Test func ratesThatAreNotOutYetAreTriedAgainAt1500And1530And1630ThenOnTheNextBusinessDay() {
        // Each run got only the declaration of Thursday 15 October.
        var notOut = state(newest: "2026-10-15")
        let friday = civilDate("2026-10-16")
        notOut.cnbRetrySlotsUsed = [friday: 1]
        #expect(wake(at: "2026-10-16T12:35:00Z", notOut) == date("2026-10-16T13:00:00Z"))
        notOut.cnbRetrySlotsUsed = [friday: 2]
        #expect(wake(at: "2026-10-16T13:00:00Z", notOut) == date("2026-10-16T13:30:00Z"))
        notOut.cnbRetrySlotsUsed = [friday: 3]
        #expect(wake(at: "2026-10-16T13:30:00Z", notOut) == date("2026-10-16T14:30:00Z"))
        notOut.cnbRetrySlotsUsed = [friday: 4]
        #expect(wake(at: "2026-10-16T14:30:00Z", notOut) == date("2026-10-19T12:35:00Z"))
    }

    @Test func afterTheClockChangeTheWakeOfMondayIs1435WinterTime() {
        // Saturday 24 October with the rates of Friday 23 October, not following today.
        #expect(wake(at: "2026-10-24T10:00:00Z", state(newest: "2026-10-23")) == date("2026-10-26T13:35:00Z"))
    }

    @Test func overEaster2027AndTheClockChangeTheNextFixingIsOnTuesdayInSummerTime() {
        // Good Friday 26 March and Easter Monday 29 March are holidays; summer time begins on 28 March.
        #expect(wake(at: "2027-03-25T14:00:00Z", state(newest: "2027-03-25")) == date("2027-03-30T12:35:00Z"))
    }

    @Test func noRatesAreAskedForOnAHolidayTheWakeIsTheNextBusinessDay() {
        // Wednesday 28 October is a holiday; the next fixing is on Thursday 29 October at 14:35 winter time.
        #expect(wake(at: "2026-10-28T09:00:00Z", state(newest: "2026-10-27")) == date("2026-10-29T13:35:00Z"))
    }

    @Test func whileFollowingTodayTheLocalMidnightIsAWake() {
        let current = state(newest: "2026-10-16")
        #expect(wake(at: "2026-10-17T10:00:00Z", current, followsToday: true) == date("2026-10-17T22:00:00Z"))
        // Without following, the next wake is the fixing of Monday.
        #expect(wake(at: "2026-10-17T10:00:00Z", current) == date("2026-10-19T12:35:00Z"))
    }

    @Test func theMidnightsAroundTheClockChangeAreLocalMidnights() {
        // Saturday 24 October still ends in summer time, Sunday 25 October in winter time.
        let current = state(newest: "2026-10-23")
        #expect(wake(at: "2026-10-24T10:00:00Z", current, followsToday: true) == date("2026-10-24T22:00:00Z"))
        #expect(wake(at: "2026-10-25T10:00:00Z", current, followsToday: true) == date("2026-10-25T23:00:00Z"))
    }

    @Test func failuresBackOffHalfAnHourThenAnHourThenUntilTheNextFixing() {
        var failed = state(newest: "2026-10-15")
        failed.cnbFailureCount = 1
        failed.lastCNBFailure = date("2026-10-16T12:35:00Z")
        #expect(wake(at: "2026-10-16T12:35:00Z", failed) == date("2026-10-16T13:05:00Z"))

        failed.cnbFailureCount = 2
        failed.lastCNBFailure = date("2026-10-16T13:05:00Z")
        #expect(wake(at: "2026-10-16T13:05:00Z", failed) == date("2026-10-16T14:05:00Z"))

        // Friday 16:05 in Prague: the next fixing is on Monday.
        failed.cnbFailureCount = 3
        failed.lastCNBFailure = date("2026-10-16T14:05:00Z")
        #expect(wake(at: "2026-10-16T14:05:00Z", failed) == date("2026-10-19T12:35:00Z"))
    }

    @Test func aThirdFailureOnAWeekdayWaitsForTheFixingOfTheNextDay() {
        var failed = state(newest: "2026-10-13")
        failed.cnbFailureCount = 3
        failed.lastCNBFailure = date("2026-10-14T14:05:00Z")
        #expect(wake(at: "2026-10-14T14:05:00Z", failed) == date("2026-10-15T12:35:00Z"))
    }

    @Test func aCurrentCacheIsNotHeldBackByOldFailures() {
        var current = state(newest: "2026-10-16")
        current.cnbFailureCount = 2
        current.lastCNBFailure = date("2026-10-16T13:05:00Z")
        #expect(wake(at: "2026-10-16T15:00:00Z", current) == date("2026-10-19T12:35:00Z"))
    }

    @Test func anOverdueWakeComesAMinuteAfterNowNeverEarlier() {
        // The fixing of 14:35 passed while nothing ran: the wake is due at once, which is a minute from now.
        let missed = state(newest: "2026-10-15")
        #expect(wake(at: "2026-10-16T13:10:00Z", missed) == date("2026-10-16T13:11:00Z"))
    }

    @Test func theWakesOfTheCNBStayInPragueTimeWhenTheMacIsInNewYork() {
        // Friday 04:00 in New York: the fixing at 14:35 in Prague comes before the midnight in New York.
        let behind = state(newest: "2026-10-15")
        let fixing = wake(at: "2026-10-16T08:00:00Z", behind, followsToday: true, in: newYork)
        #expect(fixing == date("2026-10-16T12:35:00Z"))
        // Saturday 06:00 in New York, the cache current: the next wake is the midnight in New York.
        let current = state(newest: "2026-10-16")
        let midnight = wake(at: "2026-10-17T10:00:00Z", current, followsToday: true, in: newYork)
        #expect(midnight == date("2026-10-18T04:00:00Z"))
    }

    @Test func everyWakeHasAToleranceOfAtLeastAMinute() {
        #expect(RefreshPlanner.wakeTolerance >= 60)
    }

    // MARK: The state

    @Test func theStateIsKeptAsJSONAndReadBack() throws {
        var state = RefreshState()
        state.newestCNBDeclaration = civilDate("2026-10-16")
        state.cnbFailureCount = 2
        state.lastCNBFailure = date("2026-10-16T13:05:00Z")
        state.cnbRetrySlotsUsed = [civilDate("2026-10-16"): 3]
        state.finishedYearsWithoutUniformRate = [2025]
        state.finishedYearsWithManualUniformRate = [2025]
        state.lastUniformCheck = civilDate("2026-01-15")
        state.checkedIssues = [2025: [webURL("https://mf.gov.cz/cs/dane-a-ucetnictvi/financni-zpravodaj/2026/x")]]
        state.gaveUpUniform = [2024]
        state.provisionalPaymentDays = [civilDate("2025-03-20")]
        let json = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(RefreshState.self, from: json) == state)
    }

    @Test func aStateWrittenWithFewerFieldsIsReadWithTheDefaultsOfTheOthers() throws {
        let stored = Data(#"{"newestCNBDeclaration":"2026-10-16","cnbFailureCount":1}"#.utf8)
        var expected = RefreshState()
        expected.newestCNBDeclaration = civilDate("2026-10-16")
        expected.cnbFailureCount = 1
        #expect(try JSONDecoder().decode(RefreshState.self, from: stored) == expected)
        #expect(try JSONDecoder().decode(RefreshState.self, from: Data("{}".utf8)) == RefreshState())
    }
}

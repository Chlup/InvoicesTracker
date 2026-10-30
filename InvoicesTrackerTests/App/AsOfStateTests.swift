import Foundation
import Testing
@testable import InvoicesTracker

/// The automatic reporting cutoff and the internal API for selecting another reporting day.
struct AsOfStateTests {
    private let today = civilDate("2026-10-28")

    // MARK: Launch and the year menu

    @Test func theAppOpensOnMonthEndOfTheCurrentYearAndFollowsIt() {
        let state = AsOfState.launch(today: today)

        #expect(state.year == 2026)
        #expect(state.asOf == civilDate("2026-10-31"))
        #expect(state.followsToday)
    }

    @Test func anotherYearShowsItsLastDayAndDoesNotFollowToday() {
        var state = AsOfState.launch(today: today)

        state.selectYear(2025, today: today)

        #expect(state.year == 2025)
        #expect(state.asOf == civilDate("2025-12-31"))
        #expect(!state.followsToday)
    }

    @Test func theCurrentYearShowsMonthEndAndFollowsItAgain() {
        var state = AsOfState.launch(today: today)
        state.selectYear(2025, today: today)

        state.selectYear(2026, today: today)

        #expect(state.year == 2026)
        #expect(state.asOf == civilDate("2026-10-31"))
        #expect(state.followsToday)
    }

    @Test func aYearThatIsNotOverYetStillShowsItsLastDayWhenItIsNotTheCurrentOne() {
        var state = AsOfState.launch(today: today)

        state.selectYear(2027, today: today)

        #expect(state.year == 2027)
        #expect(state.asOf == civilDate("2027-12-31"))
        #expect(!state.followsToday)
    }

    // MARK: Picking a day

    @Test func pickingADayStopsFollowingAndPickingMonthEndFollowsAgain() {
        var state = AsOfState.launch(today: today)

        state.pick(civilDate("2026-09-30"), today: today)

        #expect(state.year == 2026)
        #expect(state.asOf == civilDate("2026-09-30"))
        #expect(!state.followsToday)

        state.pick(civilDate("2026-10-31"), today: today)

        #expect(state.asOf == civilDate("2026-10-31"))
        #expect(state.followsToday)
    }

    @Test func aDayBeforeTheSelectedYearIsClampedToItsFirstDay() {
        var state = AsOfState.launch(today: today)

        state.pick(civilDate("2025-03-01"), today: today)

        #expect(state.year == 2026)
        #expect(state.asOf == civilDate("2026-01-01"))
        #expect(!state.followsToday)
    }

    @Test func aDayAfterTheSelectedYearIsClampedToItsLastDay() {
        var state = AsOfState.launch(today: today)

        state.pick(civilDate("2027-02-01"), today: today)

        #expect(state.year == 2026)
        #expect(state.asOf == civilDate("2026-12-31"))
        #expect(!state.followsToday)
    }

    @Test func todayPickedWhileAnotherYearIsSelectedIsNotTodayAndDoesNotFollow() {
        var state = AsOfState.launch(today: today)
        state.selectYear(2025, today: today)

        state.pick(civilDate("2026-10-28"), today: today)

        #expect(state.year == 2025)
        #expect(state.asOf == civilDate("2025-12-31"))
        #expect(!state.followsToday)
    }

    @Test func clampingToTheLastDayOfTheYearThatIsTodayFollowsIt() {
        // Today is the last day of the year: a day after it clamps to today, and the as-of day is today.
        let newYearsEve = civilDate("2026-12-31")
        var state = AsOfState.launch(today: newYearsEve)
        state.pick(civilDate("2026-06-01"), today: newYearsEve)

        state.pick(civilDate("2027-01-15"), today: newYearsEve)

        #expect(state.asOf == newYearsEve)
        #expect(state.followsToday)
    }

    @Test func returningToTheCurrentYearRestoresItsAutomaticMonthEnd() {
        var state = AsOfState.launch(today: today)
        state.selectYear(2024, today: today)

        state.goToday(today)

        #expect(state.year == 2026)
        #expect(state.asOf == civilDate("2026-10-31"))
        #expect(state.followsToday)
    }

    // MARK: The day changes while the app runs

    @Test func aFollowingCutoffMovesToTheEndOfTheNewMonth() {
        var state = AsOfState.launch(today: today)

        let change = state.dayChanged(to: civilDate("2026-11-01"))

        #expect(change == DayChange.moved)
        #expect(state.asOf == civilDate("2026-11-30"))
        #expect(state.year == 2026)
        #expect(state.followsToday)
    }

    @Test func aDayThatDoesNotFollowStaysWhereItIs() {
        var state = AsOfState.launch(today: today)
        state.pick(civilDate("2026-09-30"), today: today)
        let before = state

        let change = state.dayChanged(to: civilDate("2026-11-01"))

        #expect(change == DayChange.none)
        #expect(state == before)
    }

    @Test func theSameDayAgainChangesNothing() {
        var state = AsOfState.launch(today: today)
        let before = state

        let change = state.dayChanged(to: today)

        #expect(change == DayChange.none)
        #expect(state == before)
    }

    @Test func atNewYearAFollowingStateMovesToTheNewYear() {
        var state = AsOfState.launch(today: civilDate("2026-12-31"))

        let change = state.dayChanged(to: civilDate("2027-01-01"))

        #expect(change == DayChange.newYear(finished: 2026))
        #expect(state.year == 2027)
        #expect(state.asOf == civilDate("2027-01-31"))
        #expect(state.followsToday)
    }

    @Test func atNewYearAStateThatDoesNotFollowStaysInItsYear() {
        var state = AsOfState.launch(today: civilDate("2026-12-31"))
        state.pick(civilDate("2026-03-31"), today: civilDate("2026-12-31"))
        let before = state

        let change = state.dayChanged(to: civilDate("2027-01-01"))

        #expect(change == DayChange.none)
        #expect(state == before)
    }

    @Test func aFollowingStateThatWasOnAnEarlierYearMovesToTheNewYearToo() {
        // A state that follows today is always on the current year, so this only matters for a state that was not
        // made by the methods above. The year that finished is still reported.
        var state = AsOfState(year: 2025, asOf: civilDate("2025-12-31"), followsToday: true)

        let change = state.dayChanged(to: civilDate("2026-10-28"))

        #expect(change == DayChange.newYear(finished: 2025))
        #expect(state == AsOfState(year: 2026, asOf: civilDate("2026-10-31"), followsToday: true))
    }

    @Test func aClockSetBackMovesAFollowingStateBackWithoutCallingItANewYear() {
        var state = AsOfState.launch(today: civilDate("2027-01-02"))

        let change = state.dayChanged(to: civilDate("2026-12-30"))

        #expect(change == DayChange.moved)
        #expect(state.year == 2026)
        #expect(state.asOf == civilDate("2026-12-31"))
        #expect(state.followsToday)
    }

    // MARK: The time zone of the Mac

    /// The day in Prague at an instant.
    private func pragueDay(_ instant: String) -> CivilDate {
        CivilDate.today(now: date(instant), timeZone: CzechCalendar.prague)
    }

    @Test func theReportingCutoffStaysAtMonthEndAcrossTheAutumnClockChange() {
        // 25. 10. 2026 has 25 hours: summer time ends at 03:00, so midnight is at 22:00 UTC before it and at 23:00 UTC
        // after it.
        #expect(pragueDay("2026-10-24T21:59:00Z") == civilDate("2026-10-24"))
        #expect(pragueDay("2026-10-24T22:00:00Z") == civilDate("2026-10-25"))
        #expect(pragueDay("2026-10-25T22:59:00Z") == civilDate("2026-10-25"))
        #expect(pragueDay("2026-10-25T23:00:00Z") == civilDate("2026-10-26"))
        var state = AsOfState.launch(today: pragueDay("2026-10-24T21:59:00Z"))
        #expect(state.asOf == civilDate("2026-10-31"))

        #expect(state.dayChanged(to: pragueDay("2026-10-24T22:00:00Z")) == DayChange.none)
        #expect(state.asOf == civilDate("2026-10-31"))
        // Both 02:30s of the day, 00:30 UTC and 01:30 UTC, and 23:59 are still the same day.
        #expect(state.dayChanged(to: pragueDay("2026-10-25T00:30:00Z")) == DayChange.none)
        #expect(state.dayChanged(to: pragueDay("2026-10-25T01:30:00Z")) == DayChange.none)
        #expect(state.dayChanged(to: pragueDay("2026-10-25T22:59:00Z")) == DayChange.none)
        #expect(state.dayChanged(to: pragueDay("2026-10-25T23:00:00Z")) == DayChange.none)
        #expect(state.asOf == civilDate("2026-10-31"))
    }

    @Test func theReportingCutoffStaysAtMonthEndAcrossTheSpringClockChange() {
        // 28. 3. 2027 has 23 hours: summer time begins at 02:00, so midnight is at 23:00 UTC before it and at 22:00 UTC
        // after it.
        #expect(pragueDay("2027-03-27T22:59:00Z") == civilDate("2027-03-27"))
        #expect(pragueDay("2027-03-27T23:00:00Z") == civilDate("2027-03-28"))
        #expect(pragueDay("2027-03-28T21:59:00Z") == civilDate("2027-03-28"))
        #expect(pragueDay("2027-03-28T22:00:00Z") == civilDate("2027-03-29"))
        var state = AsOfState.launch(today: pragueDay("2027-03-27T22:59:00Z"))
        #expect(state.asOf == civilDate("2027-03-31"))

        #expect(state.dayChanged(to: pragueDay("2027-03-27T23:00:00Z")) == DayChange.none)
        #expect(state.asOf == civilDate("2027-03-31"))
        #expect(state.dayChanged(to: pragueDay("2027-03-28T21:59:00Z")) == DayChange.none)
        #expect(state.dayChanged(to: pragueDay("2027-03-28T22:00:00Z")) == DayChange.none)
        #expect(state.asOf == civilDate("2027-03-31"))
    }

    @Test func midnightInTheZoneOfTheMacDecidesWhenTheYearChanges() {
        // 1 January 2027 begins at 05:00 UTC in New York. Until then it is still 31 December 2026 there.
        let newYork = TimeZone(identifier: "America/New_York")!
        var state = AsOfState.launch(today: civilDate("2026-12-31"))

        let beforeMidnight = CivilDate.today(now: date("2027-01-01T04:30:00Z"), timeZone: newYork)
        #expect(beforeMidnight == civilDate("2026-12-31"))
        #expect(state.dayChanged(to: beforeMidnight) == DayChange.none)
        #expect(state.year == 2026)
        #expect(state.asOf == civilDate("2026-12-31"))

        let atMidnight = CivilDate.today(now: date("2027-01-01T05:00:00Z"), timeZone: newYork)
        #expect(atMidnight == civilDate("2027-01-01"))
        #expect(state.dayChanged(to: atMidnight) == DayChange.newYear(finished: 2026))
        #expect(state.year == 2027)
        #expect(state.asOf == civilDate("2027-01-31"))
    }

    // MARK: A year that is over

    @Test func aYearBeforeTheCurrentOneIsOverOnlyOnItsLastDay() {
        #expect(AsOfState.isFinishedYear(asOf: civilDate("2025-12-31"), today: today))
        // Any other day of it is the year as it was that day, with the rest of it still to come.
        #expect(!AsOfState.isFinishedYear(asOf: civilDate("2025-12-30"), today: today))
        #expect(!AsOfState.isFinishedYear(asOf: civilDate("2025-06-30"), today: today))
        #expect(!AsOfState.isFinishedYear(asOf: civilDate("2025-01-01"), today: today))
    }

    @Test func theCurrentYearAndTheFutureOnesAreNeverOver() {
        #expect(!AsOfState.isFinishedYear(asOf: today, today: today))
        #expect(!AsOfState.isFinishedYear(asOf: civilDate("2026-12-31"), today: today))
        #expect(!AsOfState.isFinishedYear(asOf: civilDate("2027-12-31"), today: today))
        // On the last day of the year the year is still the current one.
        #expect(!AsOfState.isFinishedYear(asOf: civilDate("2026-12-31"), today: civilDate("2026-12-31")))
        // A day later it is over.
        #expect(AsOfState.isFinishedYear(asOf: civilDate("2026-12-31"), today: civilDate("2027-01-01")))
    }

    @Test func theStateShowsAYearThatIsOverUntilADayInItIsPicked() {
        var state = AsOfState.launch(today: today)
        #expect(!state.showsFinishedYear(today: today))

        state.selectYear(2025, today: today)
        #expect(state.showsFinishedYear(today: today))

        state.pick(civilDate("2025-06-30"), today: today)
        #expect(!state.showsFinishedYear(today: today))

        state.pick(civilDate("2025-12-31"), today: today)
        #expect(state.showsFinishedYear(today: today))
    }
}

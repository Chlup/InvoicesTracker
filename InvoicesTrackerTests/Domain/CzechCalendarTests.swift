import Foundation
import Testing
@testable import InvoicesTracker

struct CzechCalendarTests {
    // MARK: Easter

    @Test func easterSundays() {
        let expected = [
            (2022, "2022-04-17"), (2023, "2023-04-09"), (2024, "2024-03-31"), (2025, "2025-04-20"),
            (2026, "2026-04-05"), (2027, "2027-03-28"),
        ]
        for (year, iso) in expected {
            #expect(CzechCalendar.easterSunday(year: year).iso == iso, "Easter \(year)")
        }
    }

    /// Dates from published Gregorian Easter tables.
    @Test(arguments: [
        // The years around the ones the app handles.
        (2016, "2016-03-27"), (2017, "2017-04-16"), (2018, "2018-04-01"), (2019, "2019-04-21"), (2020, "2020-04-12"),
        (2021, "2021-04-04"), (2028, "2028-04-16"), (2029, "2029-04-01"), (2030, "2030-04-21"), (2031, "2031-04-13"),
        (2032, "2032-03-28"), (2033, "2033-04-17"), (2034, "2034-04-09"), (2035, "2035-03-25"), (2036, "2036-04-13"),
        (2037, "2037-04-05"), (2038, "2038-04-25"), (2039, "2039-04-10"), (2040, "2040-04-01"),
        // The earliest possible Easter (22 March) and the latest (25 April).
        (1818, "1818-03-22"), (2285, "2285-03-22"), (1886, "1886-04-25"), (1943, "1943-04-25"),
        // In these years the algorithm's correction term moves the date back by a week.
        (1954, "1954-04-18"), (1981, "1981-04-19"), (2049, "2049-04-18"), (2076, "2076-04-19"),
        // Century years, and years in the centuries where the lunar corrections of the algorithm change the date.
        (1700, "1700-04-11"), (1750, "1750-03-29"), (1900, "1900-04-15"), (2000, "2000-04-23"),
        (2100, "2100-03-28"), (2106, "2106-04-18"), (2150, "2150-04-12"), (2200, "2200-04-06"), (2400, "2400-04-16"),
    ])
    func easterSundayInOtherYears(_ year: Int, _ iso: String) {
        #expect(CzechCalendar.easterSunday(year: year).iso == iso)
    }

    /// Whatever the exact date, Easter is a Sunday between 22 March and 25 April. A wrong lunar correction can still
    /// give such a Sunday, so this guards the weekday arithmetic and the table above guards the dates.
    @Test func easterIsAlwaysASundayBetween22MarchAnd25April() {
        let wrong = (1583...9999).filter { year in
            let easter = CzechCalendar.easterSunday(year: year)
            let monthAndDay = easter.month * 100 + easter.day
            return easter.year != year || easter.weekday != 7 || !(322...425).contains(monthAndDay)
        }
        #expect(wrong.isEmpty, "Easter is not a Sunday between 22 March and 25 April in \(wrong.prefix(5))")
    }

    // MARK: Public holidays

    @Test func publicHolidaysOf2026() {
        let expected = Set(
            [
                "2026-01-01", "2026-04-03", "2026-04-06", "2026-05-01", "2026-05-08", "2026-07-05", "2026-07-06",
                "2026-09-28", "2026-10-28", "2026-11-17", "2026-12-24", "2026-12-25", "2026-12-26",
            ].map { CivilDate(iso: $0)! })
        #expect(CzechCalendar.publicHolidays(year: 2026).count == 13)
        #expect(CzechCalendar.publicHolidays(year: 2026) == expected)
    }

    @Test func everyYearHasThirteenHolidaysAndAllOfThemFallInThatYear() {
        for year in 2016...2040 {
            let holidays = CzechCalendar.publicHolidays(year: year)
            #expect(holidays.count == 13, "Holidays of \(year)")
            #expect(holidays.allSatisfy { $0.year == year }, "Holidays of \(year)")
        }
    }

    @Test func goodFridayAndEasterMondayMoveWithEaster() {
        #expect(CzechCalendar.isPublicHoliday(CivilDate(iso: "2026-04-03")!))  // Good Friday
        #expect(CzechCalendar.isPublicHoliday(CivilDate(iso: "2026-04-06")!))  // Easter Monday
        let expected = [
            (2022, "2022-04-15", "2022-04-18"), (2023, "2023-04-07", "2023-04-10"), (2024, "2024-03-29", "2024-04-01"),
            (2025, "2025-04-18", "2025-04-21"), (2026, "2026-04-03", "2026-04-06"), (2027, "2027-03-26", "2027-03-29"),
        ]
        for (year, goodFriday, easterMonday) in expected {
            let holidays = CzechCalendar.publicHolidays(year: year)
            #expect(holidays.contains(CivilDate(iso: goodFriday)!), "Good Friday \(year)")
            #expect(holidays.contains(CivilDate(iso: easterMonday)!), "Easter Monday \(year)")
        }
    }

    @Test func fixedHolidaysFallOnTheSameDateEveryYear() {
        let fixed = [(1, 1), (5, 1), (5, 8), (7, 5), (7, 6), (9, 28), (10, 28), (11, 17), (12, 24), (12, 25), (12, 26)]
        for year in 2022...2027 {
            let holidays = CzechCalendar.publicHolidays(year: year)
            for (month, day) in fixed {
                let holiday = CivilDate(year: year, month: month, day: day)!
                #expect(holidays.contains(holiday), "\(holiday)")
                #expect(CzechCalendar.isPublicHoliday(holiday), "\(holiday)")
            }
        }
    }

    /// The neighbours of holidays, Easter Sunday itself, and days that are holidays elsewhere but not in Czechia.
    @Test func otherDaysAreNotPublicHolidays() {
        let ordinary = [
            "2026-01-02", "2026-01-06", "2026-04-02", "2026-04-05", "2026-04-07", "2026-05-07", "2026-05-09",
            "2026-08-15", "2026-10-17", "2026-10-27", "2026-10-29", "2026-11-01", "2026-12-06", "2026-12-23",
            "2026-12-27", "2026-12-31",
        ]
        for iso in ordinary {
            #expect(!CzechCalendar.isPublicHoliday(CivilDate(iso: iso)!), "\(iso)")
        }
    }

    // MARK: Business days

    @Test func businessDays() {
        #expect(CzechCalendar.isBusinessDay(CivilDate(iso: "2026-10-16")!))
        #expect(!CzechCalendar.isBusinessDay(CivilDate(iso: "2026-10-17")!))
        #expect(!CzechCalendar.isBusinessDay(CivilDate(iso: "2026-10-28")!))
    }

    @Test func businessDaysAroundWeekendsAndHolidays() {
        let expected: [(String, Bool)] = [
            ("2026-10-12", true),  // Monday
            ("2026-10-16", true),  // Friday
            ("2026-10-17", false),  // Saturday
            ("2026-10-18", false),  // Sunday
            ("2026-10-19", true),  // Monday
            ("2026-04-03", false),  // Good Friday
            ("2026-04-06", false),  // Easter Monday
            ("2026-04-07", true),
            ("2026-05-01", false),
            ("2026-12-23", true),
            ("2026-12-24", false),
            ("2026-12-25", false),
            ("2026-12-26", false),  // a Saturday, and a holiday
            ("2026-12-28", true),
            ("2026-12-31", true),
            ("2027-01-01", false),
            ("2027-01-04", true),
        ]
        for (iso, isBusinessDay) in expected {
            #expect(CzechCalendar.isBusinessDay(CivilDate(iso: iso)!) == isBusinessDay, "\(iso)")
        }
    }

    /// 261 weekdays in 2026, less 11 holidays that fall on one (5 July and 26 December are a Sunday and a Saturday).
    @Test func thereAre250BusinessDaysIn2026() {
        let businessDays = days(from: "2026-01-01", through: "2026-12-31").filter(CzechCalendar.isBusinessDay)
        #expect(businessDays.count == 250)
    }

    @Test(arguments: [
        ("2026-10-16", "2026-10-16"),  // a business day is its own answer
        ("2026-10-19", "2026-10-19"),
        ("2026-10-17", "2026-10-16"),  // Saturday
        ("2026-10-18", "2026-10-16"),  // Sunday
        ("2026-10-28", "2026-10-27"),  // a holiday in the middle of the week
        ("2026-01-01", "2025-12-31"),  // across the new year
        ("2028-01-01", "2027-12-31"),
        ("2026-04-06", "2026-04-02"),  // Easter Monday, back over the weekend and Good Friday
        ("2026-05-10", "2026-05-07"),  // the Sunday after the Friday holiday of 8 May
        ("2026-12-26", "2026-12-23"),  // Christmas
        ("2026-12-27", "2026-12-23"),
    ])
    func previousBusinessDaySkipsWeekendsAndHolidays(_ iso: String, _ expected: String) {
        #expect(CzechCalendar.previousBusinessDay(onOrBefore: CivilDate(iso: iso)!).iso == expected)
    }

    @Test(arguments: [
        ("2026-10-16", "2026-10-16"),  // a business day is its own answer
        ("2026-12-31", "2026-12-31"),
        ("2026-10-17", "2026-10-19"),  // Saturday
        ("2026-10-18", "2026-10-19"),  // Sunday
        ("2026-10-28", "2026-10-29"),  // a holiday in the middle of the week
        ("2026-01-01", "2026-01-02"),
        ("2027-01-01", "2027-01-04"),  // across a holiday and a weekend
        ("2028-01-01", "2028-01-03"),
        ("2026-04-03", "2026-04-07"),  // Good Friday, the weekend and Easter Monday
        ("2026-05-08", "2026-05-11"),
        ("2026-12-24", "2026-12-28"),  // Christmas Eve to the Monday after Christmas
        ("2026-07-05", "2026-07-07"),  // a Sunday followed by the holiday of 6 July
    ])
    func nextBusinessDaySkipsWeekendsAndHolidays(_ iso: String, _ expected: String) {
        #expect(CzechCalendar.nextBusinessDay(onOrAfter: CivilDate(iso: iso)!).iso == expected)
    }

    // MARK: Exchange-rate declaration day

    @Test func rateDeclarationDay() {
        #expect(CzechCalendar.rateDeclarationDay(for: CivilDate(iso: "2026-01-01")!).iso == "2025-12-31")
        #expect(CzechCalendar.rateDeclarationDay(for: CivilDate(iso: "2026-10-18")!).iso == "2026-10-16")
        #expect(CzechCalendar.rateDeclarationDay(for: CivilDate(iso: "2026-04-06")!).iso == "2026-04-02")
    }

    @Test(arguments: [
        ("2026-10-16", "2026-10-16"),  // a business day declares its own rate
        ("2026-10-19", "2026-10-19"),
        ("2026-10-17", "2026-10-16"),
        ("2026-05-10", "2026-05-07"),  // the Friday before is the holiday of 8 May
        ("2026-12-26", "2026-12-23"),
        ("2027-01-01", "2026-12-31"),
        ("2022-01-01", "2021-12-31"),  // a Saturday
        ("2022-01-02", "2021-12-31"),
        ("2022-01-03", "2022-01-03"),
    ])
    func rateDeclarationDayAroundWeekendsAndHolidays(_ iso: String, _ expected: String) {
        #expect(CzechCalendar.rateDeclarationDay(for: CivilDate(iso: iso)!).iso == expected)
    }

    /// For every day from 2022 to 2027 the answer is a business day that is not after the date, and every day after it
    /// up to the date is a weekend or a holiday.
    @Test func rateDeclarationDayIsTheLatestBusinessDayNotAfterTheDate() {
        let wrong = days(from: "2022-01-01", through: "2027-12-31").filter { day in
            let declared = CzechCalendar.rateDeclarationDay(for: day)
            guard declared <= day, CzechCalendar.isBusinessDay(declared) else { return true }
            let laterDays = (0..<day.days(since: declared)).map { declared.adding(days: $0 + 1) }
            return laterDays.contains(where: CzechCalendar.isBusinessDay)
        }
        #expect(wrong.isEmpty, "Wrong rate declaration day for \(wrong.prefix(5))")
    }

    // MARK: VAT filing deadline

    @Test func vatFilingDue() {
        #expect(CzechCalendar.vatFilingDue(year: 2026, month: 9).iso == "2026-10-26")
        #expect(CzechCalendar.vatFilingDue(year: 2026, month: 11).iso == "2026-12-28")
        #expect(CzechCalendar.vatFilingDue(year: 2026, month: 12).iso == "2027-01-25")
    }

    /// The 25th of the following month, moved to the next business day: 25 April and 25 July 2026 are Saturdays, 25
    /// October a Sunday and 25 December a holiday on a Friday.
    @Test func vatFilingDueForEveryMonthOf2026() {
        let expected = [
            "2026-02-25", "2026-03-25", "2026-04-27", "2026-05-25", "2026-06-25", "2026-07-27",
            "2026-08-25", "2026-09-25", "2026-10-26", "2026-11-25", "2026-12-28", "2027-01-25",
        ]
        for month in 1...12 {
            #expect(CzechCalendar.vatFilingDue(year: 2026, month: month).iso == expected[month - 1], "month \(month)")
        }
    }

    @Test(arguments: [
        (2025, 12, "2026-01-26"),  // December: January of the next year, and the 25th is a Sunday
        (2016, 2, "2016-03-29"),  // the 25th is Good Friday, then a weekend and Easter Monday
        (2027, 11, "2027-12-27"),  // the 25th is a Saturday, then Sunday 26 December
        (2028, 11, "2028-12-27"),  // the 25th and the 26th are holidays on a Monday and a Tuesday
        (2022, 12, "2023-01-25"),  // a Wednesday
    ])
    func vatFilingDueAcrossTheYearEndAndLongHolidays(_ year: Int, _ month: Int, _ expected: String) {
        #expect(CzechCalendar.vatFilingDue(year: year, month: month).iso == expected)
    }

    // MARK: Prague time

    @Test func pragueIsEuropePrague() {
        #expect(CzechCalendar.prague.identifier == "Europe/Prague")
    }

    /// 14:35 in Prague is 12:35 UTC in summer time and 13:35 UTC in winter time.
    @Test func pragueTimeFollowsDaylightSavingTime() {
        #expect(
            CzechCalendar.pragueTime(CivilDate(iso: "2026-10-23")!, hour: 14, minute: 35)
                == date("2026-10-23T12:35:00Z"))
        #expect(
            CzechCalendar.pragueTime(CivilDate(iso: "2026-10-26")!, hour: 14, minute: 35)
                == date("2026-10-26T13:35:00Z"))
        #expect(
            CzechCalendar.pragueTime(CivilDate(iso: "2027-03-29")!, hour: 14, minute: 35)
                == date("2027-03-29T12:35:00Z"))
    }

    @Test(arguments: [
        ("2026-03-28", "2026-03-28T13:35:00Z"),  // winter time, UTC+1
        ("2026-03-29", "2026-03-29T12:35:00Z"),  // the clocks went forward at 02:00 that morning
        ("2026-10-24", "2026-10-24T12:35:00Z"),  // summer time, UTC+2
        ("2026-10-25", "2026-10-25T13:35:00Z"),  // the clocks went back at 03:00 that morning
        ("2027-03-27", "2027-03-27T13:35:00Z"),
        ("2027-03-28", "2027-03-28T12:35:00Z"),  // the clocks went forward at 02:00 that morning
    ])
    func pragueTimeOnTheDaysTheClocksChange(_ day: String, _ expected: String) {
        #expect(CzechCalendar.pragueTime(CivilDate(iso: day)!, hour: 14, minute: 35) == date(expected))
    }

    @Test(arguments: [
        ("2026-10-17", 0, 0, "2026-10-16T22:00:00Z"),  // midnight in summer time
        ("2026-10-17", 9, 5, "2026-10-17T07:05:00Z"),
        ("2026-12-31", 23, 59, "2026-12-31T22:59:00Z"),  // the last minute of the year, in winter time
        ("2027-01-01", 0, 0, "2026-12-31T23:00:00Z"),  // midnight in winter time
    ])
    func pragueTimeIsExactToTheMinute(_ day: String, _ hour: Int, _ minute: Int, _ expected: String) {
        #expect(CzechCalendar.pragueTime(CivilDate(iso: day)!, hour: hour, minute: minute) == date(expected))
    }

    /// The hour a clock change repeats or skips has no single wall-clock meaning. `Calendar` takes the first of two
    /// occurrences, and reads a time that does not exist with the offset from before the change.
    @Test func pragueTimeInTheHourAClockChangeRepeatsOrSkips() {
        // 25 Oct 2026: 02:30 happens twice, first in summer time (UTC+2) and then in winter time (UTC+1).
        #expect(
            CzechCalendar.pragueTime(CivilDate(iso: "2026-10-25")!, hour: 2, minute: 30)
                == date("2026-10-25T00:30:00Z"))
        // 28 Mar 2027: 02:30 does not exist, the clocks jump from 02:00 to 03:00.
        #expect(
            CzechCalendar.pragueTime(CivilDate(iso: "2027-03-28")!, hour: 2, minute: 30)
                == date("2027-03-28T01:30:00Z"))
    }

    /// A day is 24 hours long, except 23 hours when the clocks go forward and 25 when they go back.
    @Test func daysAreTwentyFourHoursLongExceptWhenTheClocksChange() {
        let twentyThreeHours: Set<String> = ["2026-03-29", "2027-03-28"]
        let twentyFiveHours: Set<String> = ["2026-10-25", "2027-10-31"]
        let wrong = days(from: "2026-01-01", through: "2027-12-31").filter { day in
            let start = CzechCalendar.pragueTime(day, hour: 0, minute: 0)
            let nextStart = CzechCalendar.pragueTime(day.adding(days: 1), hour: 0, minute: 0)
            let hours = twentyThreeHours.contains(day.iso) ? 23.0 : (twentyFiveHours.contains(day.iso) ? 25.0 : 24.0)
            return nextStart.timeIntervalSince(start) != hours * 3600
        }
        #expect(wrong.isEmpty, "Wrong day length on \(wrong.prefix(5))")
    }

    // MARK: Prague date

    @Test func pragueDateIsTheDateOnTheWallClocksInPrague() {
        #expect(CzechCalendar.pragueDate(date("2026-10-16T22:30:00Z")).iso == "2026-10-17")
        // Summer time, UTC+2: Prague midnight on 17 Oct is 22:00 UTC.
        #expect(CzechCalendar.pragueDate(date("2026-10-16T21:59:59Z")).iso == "2026-10-16")
        #expect(CzechCalendar.pragueDate(date("2026-10-16T22:00:00Z")).iso == "2026-10-17")
        // Winter time, UTC+1: Prague midnight on 1 Jan is 23:00 UTC.
        #expect(CzechCalendar.pragueDate(date("2026-12-31T22:59:59Z")).iso == "2026-12-31")
        #expect(CzechCalendar.pragueDate(date("2026-12-31T23:00:00Z")).iso == "2027-01-01")
    }

    @Test func pragueDateAndPragueTimeAgreeOnEveryDayOf2026And2027() {
        let wrong = days(from: "2026-01-01", through: "2027-12-31").filter { day in
            let midnight = CzechCalendar.pragueTime(day, hour: 0, minute: 0)
            let lastMinute = CzechCalendar.pragueTime(day, hour: 23, minute: 59)
            return CzechCalendar.pragueDate(midnight) != day
                || CzechCalendar.pragueDate(midnight.addingTimeInterval(-1)) != day.adding(days: -1)
                || CzechCalendar.pragueDate(lastMinute) != day
        }
        #expect(wrong.isEmpty, "Prague date and time disagree on \(wrong.prefix(5))")
    }

    // MARK: Helpers

    /// Every day from `first` to `last`, both included.
    private func days(from first: String, through last: String) -> [CivilDate] {
        let start = CivilDate(iso: first)!
        let count = CivilDate(iso: last)!.days(since: start) + 1
        return (0..<count).map { start.adding(days: $0) }
    }
}

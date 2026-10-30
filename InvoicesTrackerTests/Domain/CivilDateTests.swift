import Foundation
import Testing
@testable import InvoicesTracker

struct CivilDateTests {
    private static var prague: TimeZone { TimeZone(identifier: "Europe/Prague")! }

    // MARK: Validation and parsing

    @Test func rejectsDatesThatDoNotExist() {
        #expect(CivilDate(iso: "2026-02-29") == nil)
        #expect(CivilDate(iso: "2024-02-29") != nil)
        #expect(CivilDate(year: 2026, month: 4, day: 31) == nil)
        #expect(CivilDate(year: 2026, month: 4, day: 30) != nil)
    }

    @Test(arguments: [
        (0, 1, 1), (-5, 6, 1), (10_000, 1, 1), (2026, 0, 10), (2026, 13, 10), (2026, 1, 0), (2026, 1, 32),
        (2026, 4, 31), (2026, 6, 31), (2026, 9, 31), (2026, 11, 31), (2026, 2, 29), (2100, 2, 29), (1900, 2, 29),
    ])
    func rejectsOutOfRangeComponents(_ year: Int, _ month: Int, _ day: Int) {
        #expect(CivilDate(year: year, month: month, day: day) == nil)
    }

    @Test func acceptsTheFirstAndLastSupportedDay() {
        #expect(CivilDate(year: 1, month: 1, day: 1) != nil)
        #expect(CivilDate(year: 9999, month: 12, day: 31) != nil)
    }

    @Test func leapYearsFollowTheGregorianRule() {
        let years: [(Int, Bool)] = [
            (1900, false), (2000, true), (2023, false), (2024, true), (2026, false), (2028, true), (2100, false),
            (2400, true),
        ]
        for (year, isLeap) in years {
            #expect(CivilDate.daysInMonth(year: year, month: 2) == (isLeap ? 29 : 28), "February \(year)")
            #expect((CivilDate(year: year, month: 2, day: 29) != nil) == isLeap, "29 February \(year)")
        }
    }

    @Test func daysInMonthForEveryMonth() {
        let ordinary = (1...12).map { CivilDate.daysInMonth(year: 2026, month: $0) }
        #expect(ordinary == [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])
        let leap = (1...12).map { CivilDate.daysInMonth(year: 2024, month: $0) }
        #expect(leap == [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])
    }

    @Test func parsesIsoDates() {
        let parsed = CivilDate(iso: "2026-10-17")
        #expect(parsed?.year == 2026)
        #expect(parsed?.month == 10)
        #expect(parsed?.day == 17)
        #expect(parsed == CivilDate(year: 2026, month: 10, day: 17))
        #expect(CivilDate(iso: "0001-01-01") != nil)
        #expect(CivilDate(iso: "9999-12-31") != nil)
    }

    @Test(arguments: [
        "", "2026-1-5", "2026-10-7", "26-10-17", "2026/10/17", "2026.10.17", "20261017", " 2026-10-17",
        "2026-10-17 ", "2026-10-17\n", "2026-10-17T00:00:00Z", "2026-10-170", "+026-10-17", "-026-10-17",
        "2026-+1-17", "2026-10--7", "abcd-ef-gh", "2026-13-01", "2026-00-10", "2026-10-00", "2026-10-32",
        "0000-01-01", "\u{FF12}\u{FF10}\u{FF12}\u{FF16}-10-17",  // fullwidth digits
        "2026-1\u{0660}-17",  // Arabic-Indic zero
    ])
    func rejectsMalformedIsoStrings(_ text: String) {
        #expect(CivilDate(iso: text) == nil)
    }

    @Test func isoIsZeroPadded() {
        #expect(CivilDate(year: 2026, month: 3, day: 5)!.iso == "2026-03-05")
        #expect(CivilDate(year: 5, month: 3, day: 9)!.iso == "0005-03-09")
        #expect(CivilDate(year: 2026, month: 10, day: 17)!.iso == "2026-10-17")
        #expect(CivilDate(year: 2026, month: 10, day: 17)!.description == "2026-10-17")
        #expect("\(CivilDate(year: 2026, month: 1, day: 2)!)" == "2026-01-02")
    }

    // MARK: Day arithmetic

    @Test func addingDaysCrossesMonthYearAndLeapBoundaries() {
        #expect(CivilDate(iso: "2026-12-31")!.adding(days: 1) == CivilDate(iso: "2027-01-01"))
        #expect(CivilDate(iso: "2027-01-01")!.adding(days: -1) == CivilDate(iso: "2026-12-31"))
        #expect(CivilDate(iso: "2024-02-28")!.adding(days: 1) == CivilDate(iso: "2024-02-29"))
        #expect(CivilDate(iso: "2024-02-29")!.adding(days: 1) == CivilDate(iso: "2024-03-01"))
        #expect(CivilDate(iso: "2026-02-28")!.adding(days: 1) == CivilDate(iso: "2026-03-01"))
        #expect(CivilDate(iso: "2026-10-17")!.adding(days: 0) == CivilDate(iso: "2026-10-17"))
        #expect(CivilDate(iso: "2026-01-31")!.adding(days: 30) == CivilDate(iso: "2026-03-02"))
        #expect(CivilDate(iso: "2026-10-17")!.adding(days: 30) == CivilDate(iso: "2026-11-16"))
        #expect(CivilDate(iso: "2026-10-17")!.adding(days: -17) == CivilDate(iso: "2026-09-30"))
        #expect(CivilDate(iso: "2024-01-01")!.adding(days: 366) == CivilDate(iso: "2025-01-01"))
        #expect(CivilDate(iso: "2026-01-01")!.adding(days: 365) == CivilDate(iso: "2027-01-01"))
    }

    @Test func addingDaysReachesBothEndsOfTheSupportedRange() {
        #expect(CivilDate(iso: "0001-01-01")!.adding(days: 3_652_058) == CivilDate(iso: "9999-12-31"))
        #expect(CivilDate(iso: "9999-12-31")!.adding(days: -3_652_058) == CivilDate(iso: "0001-01-01"))
    }

    @Test func daysSinceCountsCalendarDays() {
        let today = CivilDate(iso: "2026-10-17")!
        #expect(today.days(since: CivilDate(iso: "2026-10-10")!) == 7)
        #expect(CivilDate(iso: "2026-10-10")!.days(since: today) == -7)
        #expect(today.days(since: today) == 0)
        #expect(CivilDate(iso: "2027-01-01")!.days(since: CivilDate(iso: "2026-01-01")!) == 365)
        #expect(CivilDate(iso: "2025-01-01")!.days(since: CivilDate(iso: "2024-01-01")!) == 366)
        // The clocks change on 29 Mar 2026, but a calendar day is still one day.
        #expect(CivilDate(iso: "2026-03-30")!.days(since: CivilDate(iso: "2026-03-28")!) == 2)
    }

    @Test func weekdayIsIsoNumbered() {
        #expect(CivilDate(iso: "2026-10-17")!.weekday == 6)  // Saturday
        #expect(CivilDate(iso: "2026-10-18")!.weekday == 7)  // Sunday
        #expect(CivilDate(iso: "2026-10-19")!.weekday == 1)  // Monday
        #expect(CivilDate(iso: "2026-10-25")!.weekday == 7)  // the Sunday the clocks go back
        #expect(CivilDate(iso: "1970-01-01")!.weekday == 4)  // Thursday
        #expect(CivilDate(iso: "1969-12-31")!.weekday == 3)  // Wednesday, before the epoch
        #expect(CivilDate(iso: "2000-01-01")!.weekday == 6)
        #expect(CivilDate(iso: "2024-02-29")!.weekday == 4)
        #expect(CivilDate(iso: "0001-01-01")!.weekday == 1)
        #expect(CivilDate(iso: "9999-12-31")!.weekday == 5)
    }

    @Test func monthBoundaries() {
        #expect(CivilDate(iso: "2026-02-10")!.endOfMonth == CivilDate(iso: "2026-02-28"))
        #expect(CivilDate(iso: "2024-02-10")!.endOfMonth == CivilDate(iso: "2024-02-29"))
        #expect(CivilDate(iso: "2026-04-01")!.endOfMonth == CivilDate(iso: "2026-04-30"))
        #expect(CivilDate(iso: "2026-12-15")!.endOfMonth == CivilDate(iso: "2026-12-31"))
        #expect(CivilDate(iso: "2026-10-31")!.endOfMonth == CivilDate(iso: "2026-10-31"))
        #expect(CivilDate(iso: "2026-10-17")!.startOfMonth == CivilDate(iso: "2026-10-01"))
        #expect(CivilDate(iso: "2026-10-01")!.startOfMonth == CivilDate(iso: "2026-10-01"))
        #expect(CivilDate(iso: "2026-12-31")!.startOfMonth == CivilDate(iso: "2026-12-01"))
    }

    /// Every day from 1900 to 2200 (leap years, the non-leap centuries 1900 and 2100, the leap century 2000)
    /// is compared with Foundation's Gregorian calendar.
    @Test func agreesWithTheSystemCalendarFrom1900To2200() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = CivilDate(iso: "1900-01-01")!
        let last = CivilDate(iso: "2200-12-31")!
        let firstInstant = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1))!
        var mismatches: [String] = []
        for offset in 0...last.days(since: first) {
            let instant = firstInstant.addingTimeInterval(Double(offset) * 86_400)
            let expected = calendar.dateComponents([.year, .month, .day, .weekday], from: instant)
            let actual = first.adding(days: offset)
            let isoWeekday = (expected.weekday! + 5) % 7 + 1  // Foundation counts Sunday as 1
            let matchesCalendar = actual.year == expected.year!
                && actual.month == expected.month!
                && actual.day == expected.day!
                && actual.weekday == isoWeekday
            let isConsistent = actual.days(since: first) == offset
                && CivilDate(iso: actual.iso) == actual
                && actual.startOfMonth <= actual
                && actual <= actual.endOfMonth
                && actual.endOfMonth.day == CivilDate.daysInMonth(year: actual.year, month: actual.month)
            if !matchesCalendar || !isConsistent {
                mismatches.append("\(actual.iso) (+\(offset))")
            }
        }
        #expect(mismatches.isEmpty, "Mismatches: \(mismatches.prefix(5))")
    }

    // MARK: Ordering and hashing

    @Test func ordersChronologically() {
        let dates = ["2026-10-17", "2025-12-31", "2026-02-01", "2026-10-02", "2026-10-17"].map { CivilDate(iso: $0)! }
        #expect(dates.sorted().map(\.iso) == ["2025-12-31", "2026-02-01", "2026-10-02", "2026-10-17", "2026-10-17"])
        #expect(CivilDate(iso: "2026-10-17")! < CivilDate(iso: "2026-10-18")!)
        #expect(CivilDate(iso: "2026-10-31")! < CivilDate(iso: "2026-11-01")!)
        #expect(CivilDate(iso: "2026-12-31")! < CivilDate(iso: "2027-01-01")!)
        #expect(!(CivilDate(iso: "2026-10-17")! < CivilDate(iso: "2026-10-17")!))
        #expect(!(CivilDate(iso: "2026-10-18")! < CivilDate(iso: "2026-10-17")!))
        #expect(Set(dates).count == 4)
    }

    // MARK: Codable

    @Test func isCodedAsAnIsoString() throws {
        let encoded = try JSONEncoder().encode(CivilDate(iso: "2026-10-17")!)
        #expect(String(decoding: encoded, as: UTF8.self) == "\"2026-10-17\"")
        #expect(try JSONDecoder().decode(CivilDate.self, from: encoded) == CivilDate(iso: "2026-10-17"))

        struct Holder: Codable, Equatable {
            var issued: CivilDate
        }
        let holder = Holder(issued: CivilDate(iso: "2026-10-17")!)
        let data = try JSONEncoder().encode(holder)
        #expect(String(decoding: data, as: UTF8.self) == "{\"issued\":\"2026-10-17\"}")
        #expect(try JSONDecoder().decode(Holder.self, from: data) == holder)
    }

    @Test(arguments: ["\"2026-02-29\"", "\"2026-10-7\"", "\"\"", "20261017", "null", "[]", "{\"iso\":\"2026-10-17\"}"])
    func decodingRejectsAnythingButAValidIsoString(_ json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CivilDate.self, from: Data(json.utf8))
        }
    }

    // MARK: today(now:timeZone:)

    @Test func todayIsTheCivilDateInTheGivenZone() {
        let prague = Self.prague
        let utc = TimeZone(identifier: "UTC")!
        // 22:30 UTC on 16 Oct is already 00:30 on the 17th in Prague (UTC+2, summer time).
        #expect(CivilDate.today(now: date("2026-10-16T22:30:00Z"), timeZone: prague) == CivilDate(iso: "2026-10-17"))
        #expect(CivilDate.today(now: date("2026-10-16T12:00:00Z"), timeZone: prague) == CivilDate(iso: "2026-10-16"))
        #expect(CivilDate.today(now: date("2026-10-16T22:30:00Z"), timeZone: utc) == CivilDate(iso: "2026-10-16"))
    }

    @Test func todayChangesExactlyAtLocalMidnight() {
        let prague = Self.prague
        // Prague midnight on 17 Oct 2026 is 22:00 UTC on the 16th.
        #expect(CivilDate.today(now: date("2026-10-16T21:59:59Z"), timeZone: prague) == CivilDate(iso: "2026-10-16"))
        #expect(CivilDate.today(now: date("2026-10-16T22:00:00Z"), timeZone: prague) == CivilDate(iso: "2026-10-17"))
        #expect(CivilDate.today(now: date("2026-10-17T21:59:59Z"), timeZone: prague) == CivilDate(iso: "2026-10-17"))
        #expect(CivilDate.today(now: date("2026-10-17T22:00:00Z"), timeZone: prague) == CivilDate(iso: "2026-10-18"))
    }

    @Test func todayFollowsDaylightSavingChanges() {
        let prague = Self.prague
        // Summer time ends on 25 Oct 2026 at 01:00 UTC: Prague is UTC+2 before and UTC+1 after.
        #expect(CivilDate.today(now: date("2026-10-24T21:59:59Z"), timeZone: prague) == CivilDate(iso: "2026-10-24"))
        #expect(CivilDate.today(now: date("2026-10-24T22:00:00Z"), timeZone: prague) == CivilDate(iso: "2026-10-25"))
        #expect(CivilDate.today(now: date("2026-10-25T22:59:59Z"), timeZone: prague) == CivilDate(iso: "2026-10-25"))
        #expect(CivilDate.today(now: date("2026-10-25T23:00:00Z"), timeZone: prague) == CivilDate(iso: "2026-10-26"))
        // Summer time begins on 28 Mar 2027 at 01:00 UTC.
        #expect(CivilDate.today(now: date("2027-03-27T22:59:59Z"), timeZone: prague) == CivilDate(iso: "2027-03-27"))
        #expect(CivilDate.today(now: date("2027-03-27T23:00:00Z"), timeZone: prague) == CivilDate(iso: "2027-03-28"))
        #expect(CivilDate.today(now: date("2027-03-28T21:59:59Z"), timeZone: prague) == CivilDate(iso: "2027-03-28"))
        #expect(CivilDate.today(now: date("2027-03-28T22:00:00Z"), timeZone: prague) == CivilDate(iso: "2027-03-29"))
    }

    @Test func todayWorksInOtherZones() {
        let newYork = TimeZone(identifier: "America/New_York")!  // UTC-4 on 17 Oct 2026
        #expect(CivilDate.today(now: date("2026-10-17T03:59:59Z"), timeZone: newYork) == CivilDate(iso: "2026-10-16"))
        #expect(CivilDate.today(now: date("2026-10-17T04:00:00Z"), timeZone: newYork) == CivilDate(iso: "2026-10-17"))
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!  // UTC+9
        #expect(CivilDate.today(now: date("2026-10-16T14:59:59Z"), timeZone: tokyo) == CivilDate(iso: "2026-10-16"))
        #expect(CivilDate.today(now: date("2026-10-16T15:00:00Z"), timeZone: tokyo) == CivilDate(iso: "2026-10-17"))
        let india = TimeZone(secondsFromGMT: 5 * 3600 + 1800)!  // UTC+5:30
        #expect(CivilDate.today(now: date("2026-10-16T18:29:59Z"), timeZone: india) == CivilDate(iso: "2026-10-16"))
        #expect(CivilDate.today(now: date("2026-10-16T18:30:00Z"), timeZone: india) == CivilDate(iso: "2026-10-17"))
    }

    @Test func todayRoundsDownBeforeTheEpoch() {
        let utc = TimeZone(identifier: "UTC")!
        func today(atEpochSecond second: TimeInterval) -> CivilDate {
            CivilDate.today(now: Date(timeIntervalSince1970: second), timeZone: utc)
        }
        #expect(today(atEpochSecond: 0) == CivilDate(iso: "1970-01-01"))
        #expect(today(atEpochSecond: -1) == CivilDate(iso: "1969-12-31"))
        #expect(today(atEpochSecond: -86_400) == CivilDate(iso: "1969-12-31"))
        #expect(today(atEpochSecond: -86_401) == CivilDate(iso: "1969-12-30"))
    }
}

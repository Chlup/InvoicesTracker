import Foundation

/// The Czech business calendar: public holidays, business days, the day an exchange rate is declared on, the VAT
/// filing deadline, and wall-clock time in Prague.
///
/// The ČNB declares exchange rates on business days only, so a weekend or a holiday keeps the rate of the business day
/// before it. Every function depends only on its arguments, never on the time zone the Mac is set to.
nonisolated enum CzechCalendar {
    /// Europe/Prague: the zone the ČNB publishes in and Czech deadlines are counted in.
    static let prague = TimeZone(identifier: "Europe/Prague")!

    /// The holidays with a fixed date, as month and day: 1 Jan, 1 May, 8 May, 5 Jul, 6 Jul, 28 Sep, 28 Oct, 17 Nov and
    /// 24, 25 and 26 Dec.
    private static let fixedHolidays: [(month: Int, day: Int)] = [
        (1, 1), (5, 1), (5, 8), (7, 5), (7, 6), (9, 28), (10, 28), (11, 17), (12, 24), (12, 25), (12, 26),
    ]

    /// A Gregorian calendar set to Prague time, which turns a wall-clock time into an instant.
    private static let pragueCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = prague
        return calendar
    }()

    // MARK: Public holidays

    /// Easter Sunday of `year` by the anonymous Gregorian algorithm (Meeus, Jones and Butcher), whose letters are used
    /// below. Traps unless `year` is 1 to 9999.
    static func easterSunday(year: Int) -> CivilDate {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return civilDate(year: year, month: month, day: day)
    }

    /// The 13 public holidays of `year` (zákon č. 245/2000 Sb., § 1 and § 2): 1 January, Good Friday, Easter Monday,
    /// 1 May, 8 May, 5 July, 6 July, 28 September, 28 October, 17 November, and 24, 25 and 26 December.
    ///
    /// Good Friday has been a holiday since 2016 (zákon č. 359/2015 Sb. added it to § 2). The app only handles 2016 and
    /// later, so the set does not switch on the year.
    static func publicHolidays(year: Int) -> Set<CivilDate> {
        let easter = easterSunday(year: year)
        let goodFridayAndEasterMonday = [easter.adding(days: -2), easter.adding(days: 1)]
        let fixed = fixedHolidays.map { civilDate(year: year, month: $0.month, day: $0.day) }
        return Set(goodFridayAndEasterMonday + fixed)
    }

    /// Whether `d` is one of the public holidays of its year, whatever the day of the week.
    static func isPublicHoliday(_ d: CivilDate) -> Bool {
        publicHolidays(year: d.year).contains(d)
    }

    // MARK: Business days

    /// Monday to Friday, and not a public holiday. These are the days on which the ČNB declares exchange rates.
    static func isBusinessDay(_ d: CivilDate) -> Bool {
        d.weekday <= 5 && !isPublicHoliday(d)
    }

    /// `d` itself when it is a business day, otherwise the closest business day before it.
    static func previousBusinessDay(onOrBefore d: CivilDate) -> CivilDate {
        var day = d
        while !isBusinessDay(day) {
            day = day.adding(days: -1)
        }
        return day
    }

    /// `d` itself when it is a business day, otherwise the closest business day after it.
    static func nextBusinessDay(onOrAfter d: CivilDate) -> CivilDate {
        var day = d
        while !isBusinessDay(day) {
            day = day.adding(days: 1)
        }
        return day
    }

    /// The day whose ČNB rate is the one valid on `d`: `d` itself when the ČNB declared rates that day, otherwise the
    /// business day before it. A rate declared on a Friday therefore covers the weekend, and one declared before a
    /// holiday covers the holiday.
    static func rateDeclarationDay(for d: CivilDate) -> CivilDate {
        previousBusinessDay(onOrBefore: d)
    }

    // MARK: VAT

    /// The deadline for the VAT return of `month` (1 to 12) of `year`: the 25th of the following month (zákon č.
    /// 235/2004 Sb., § 101), moved to the next business day when that is a weekend or a holiday (zákon č. 280/2009 Sb.,
    /// § 33 odst. 4). December is due in January of the next year. Traps when the deadline would be after the year
    /// 9999.
    static func vatFilingDue(year: Int, month: Int) -> CivilDate {
        precondition((1...12).contains(month), "A month is 1 to 12.")
        let dueYear = month == 12 ? year + 1 : year
        let dueMonth = month == 12 ? 1 : month + 1
        return nextBusinessDay(onOrAfter: civilDate(year: dueYear, month: dueMonth, day: 25))
    }

    // MARK: Prague time

    /// The date on the wall clocks in Prague at `instant`.
    static func pragueDate(_ instant: Date) -> CivilDate {
        CivilDate.today(now: instant, timeZone: prague)
    }

    /// The instant at which the wall clock in Prague shows `hour`:`minute` on `d`, with daylight-saving time counted:
    /// 14:35 is 12:35 UTC in summer time (UTC+2) and 13:35 UTC in winter time (UTC+1). Traps unless `hour` is 0 to 23
    /// and `minute` is 0 to 59.
    ///
    /// The hour a clock change repeats has two instants, and the first is returned. The hour it skips does not exist,
    /// and is read with the offset from before the change, so 02:30 lands at 03:30. Dates before 15 October 1582 are
    /// not supported, because Foundation's Gregorian calendar is the Julian one until then.
    static func pragueTime(_ d: CivilDate, hour: Int, minute: Int) -> Date {
        precondition((0...23).contains(hour) && (0...59).contains(minute), "A time of day is 00:00 to 23:59.")
        let components = DateComponents(year: d.year, month: d.month, day: d.day, hour: hour, minute: minute)
        guard let instant = pragueCalendar.date(from: components) else {
            preconditionFailure("Prague has no instant for \(d) \(hour):\(minute).")
        }
        return instant
    }

    // MARK: Helpers

    /// For dates that exist whenever `year` is 1 to 9999. Traps otherwise.
    private static func civilDate(year: Int, month: Int, day: Int) -> CivilDate {
        guard let date = CivilDate(year: year, month: month, day: day) else {
            preconditionFailure("\(year)-\(month)-\(day) is not a date in the years 1 to 9999.")
        }
        return date
    }
}

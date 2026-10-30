import Foundation

/// What the refresh remembers between its runs and across launches, kept as JSON under `refresh_state` in
/// `app_settings`. The newest ČNB declaration, the finished years without an official uniform rate, those of them whose
/// rates were entered by hand, and the days of the provisional payments that wait for a rate are read from the database
/// at the start of every run; the rest is the refresh's own bookkeeping.
nonisolated struct RefreshState: Sendable, Hashable, Codable {
    /// The newest day the cache has ČNB rates of, or nil when it has none.
    var newestCNBDeclaration: CivilDate?

    /// How many runs in a row had a failed ČNB request. A run counts once, however many of its requests succeeded
    /// before the one that failed, and only a run whose requests all succeed sets it back to zero.
    var cnbFailureCount = 0

    /// When the request of the latest of those runs failed.
    var lastCNBFailure: Date?

    /// When the latest download that moved the newest cached declaration ended: the "staženo" time of the status.
    var lastCNBDownload: Date?

    /// For a Prague business day whose rates are not out yet: how many of the day's fetch times (14:35, 15:00, 15:30
    /// and 16:30) have come by the latest fetch. The timer is set for the next of them.
    var cnbRetrySlotsUsed: [CivilDate: Int] = [:]

    /// The finished years that have no official uniform rate stored (shipped with the app, or fetched and confirmed):
    /// those with no uniform rate at all, and those whose rates were all entered by hand
    /// (`finishedYearsWithManualUniformRate`).
    var finishedYearsWithoutUniformRate: [Int] = []

    /// The finished years whose uniform rates were all entered by hand. They stand in for the official ones, which the
    /// app does not look for while they are stored; once they are removed, it looks for them again.
    var finishedYearsWithManualUniformRate: [Int] = []

    /// The Prague day of the latest search for a uniform rate that got an answer or failed at the server. There is one
    /// such search a day at the most; a search without a connection does not count.
    var lastUniformCheck: CivilDate?

    /// By year, the issues of the Finanční zpravodaj known not to announce the uniform rates of the year, so that no
    /// search asks for them again.
    var checkedIssues: [Int: Set<URL>] = [:]

    /// The years whose uniform rate is no longer looked for: a search on or after 31 March of the next year did not
    /// find it.
    var gaveUpUniform: Set<Int> = []

    /// By year, the page or the PDF of the Finanční zpravodaj that the latest search could not read. It is shown with
    /// its address until a later search of the year gets another answer.
    var unreadableUniformPages: [Int: URL] = [:]

    /// The days of the provisional payments in a foreign currency whose ČNB rate the cache cannot tell
    /// (`RateLookupResult.notYetAvailable`), oldest first, each once: their rates are not declared yet, or the rows
    /// that hold them were never stored (an import or a payment recorded while the yearly file could not be fetched).
    var provisionalPaymentDays: [CivilDate] = []
}

nonisolated extension RefreshState {
    /// Reads a state written by this or an earlier version of the app. A field the stored JSON does not have takes its
    /// default, so a field added later never makes a stored state unreadable.
    init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        newestCNBDeclaration = try values.decodeIfPresent(CivilDate.self, forKey: .newestCNBDeclaration)
        cnbFailureCount = try values.decodeIfPresent(Int.self, forKey: .cnbFailureCount) ?? cnbFailureCount
        lastCNBFailure = try values.decodeIfPresent(Date.self, forKey: .lastCNBFailure)
        lastCNBDownload = try values.decodeIfPresent(Date.self, forKey: .lastCNBDownload)
        cnbRetrySlotsUsed =
            try values.decodeIfPresent([CivilDate: Int].self, forKey: .cnbRetrySlotsUsed) ?? cnbRetrySlotsUsed
        finishedYearsWithoutUniformRate =
            try values.decodeIfPresent([Int].self, forKey: .finishedYearsWithoutUniformRate)
            ?? finishedYearsWithoutUniformRate
        finishedYearsWithManualUniformRate =
            try values.decodeIfPresent([Int].self, forKey: .finishedYearsWithManualUniformRate)
            ?? finishedYearsWithManualUniformRate
        lastUniformCheck = try values.decodeIfPresent(CivilDate.self, forKey: .lastUniformCheck)
        checkedIssues = try values.decodeIfPresent([Int: Set<URL>].self, forKey: .checkedIssues) ?? checkedIssues
        gaveUpUniform = try values.decodeIfPresent(Set<Int>.self, forKey: .gaveUpUniform) ?? gaveUpUniform
        unreadableUniformPages =
            try values.decodeIfPresent([Int: URL].self, forKey: .unreadableUniformPages) ?? unreadableUniformPages
        provisionalPaymentDays =
            try values.decodeIfPresent([CivilDate].self, forKey: .provisionalPaymentDays) ?? provisionalPaymentDays
    }

    /// The finished years whose official uniform rate the refresh looks for: those without it
    /// (`finishedYearsWithoutUniformRate`), but for those whose rates entered by hand stand in for it.
    var finishedYearsLookedForUniformRate: [Int] {
        finishedYearsWithoutUniformRate.filter { !finishedYearsWithManualUniformRate.contains($0) }
    }
}

/// Something the refresh has to do now.
nonisolated enum RefreshAction: Sendable, Hashable {
    /// Download the daily ČNB file of each of these business days, oldest first.
    case fetchCNBDays([CivilDate])

    /// Download the yearly ČNB file of each of these years, oldest first.
    case fetchCNBYears([Int])

    /// Download the yearly ČNB file of each of these years, oldest first, for the provisional payments that wait for
    /// its rates: years behind the newest cached declaration, which the fetches of the newest rates never reach.
    case fetchCNBYearsForPayments([Int])

    /// Look for the uniform rates of this finished year in the Finanční zpravodaj.
    case checkUniformRate(Int)

    /// Remind the person to enter the uniform rate of this year by hand, if it is still not found: the search ends.
    case uniformRateReminder(Int)
}

/// Decides what the refresh has to do and when it has to wake next. It only reads its arguments: the time, the state
/// and, for the midnight of "today", the time zone of the Mac. Everything about the ČNB is counted in Prague time, so
/// it is the same wherever the Mac is.
///
/// - The ČNB declares the rates of a business day after 14:30 Prague time, for that day and the days without a
///   declaration that follow it. The cache should therefore hold the rates of today from 14:30 on a business day, and
///   otherwise those of the business day before today.
/// - A business day whose rates are not cached yet is fetched at 14:35, and again at 15:00, 15:30 and 16:30 while they
///   are not out. Nothing is fetched on weekends and holidays, unless the cache is behind (after a sleep, say).
/// - A provisional payment whose rate the ČNB has declared but the cache does not hold (a year that an import could not
///   fetch) gets the yearly file of its year at every run, until its rate is there.
/// - A failed request is tried again 30 minutes later, then an hour later; after a third failure, at the next fixing
///   at 14:35 or at any trigger before it.
/// - The uniform rates of a finished year that has no official ones stored are looked for once a day from 2 January of
///   the next year (`UniformRateSearch`). From 31 March a search that does not find them ends the search, with a
///   reminder to enter the rates by hand; rates that are found are offered, and looked for again while they are not
///   stored. While rates entered by hand stand in for them, they are not looked for at all; once those are removed,
///   they are looked for again.
nonisolated enum RefreshPlanner {
    /// How late a wake may come, in seconds. A minute lets the system group the timer with other work.
    static let wakeTolerance: TimeInterval = 60

    /// The most business days that are fetched day by day. A longer gap is fetched as yearly files.
    static let maxDailyFetches = 10

    /// When the ČNB declares the rates of a business day, Prague time.
    private static let declarationTime = (hour: 14, minute: 30)

    /// When the rates of a business day are fetched, Prague time: the first fetch, and the retries while the rates are
    /// not out.
    private static let fetchTimes = [
        (hour: 14, minute: 35), (hour: 15, minute: 0), (hour: 15, minute: 30), (hour: 16, minute: 30),
    ]

    /// How long the refresh waits after the first and after the second failed request in a row.
    private static let backOff: [TimeInterval] = [30 * 60, 60 * 60]

    /// The shortest time from now to a wake. A wake that is already due comes after it, so that a run that cannot do
    /// what is due never repeats at once.
    private static let shortestWait: TimeInterval = 60

    // MARK: ČNB

    /// The newest declaration the cache should have at `now`: today in Prague when it is a business day and it is 14:30
    /// or later there, otherwise the business day before today.
    static func expectedNewestDeclaration(now: Date) -> CivilDate {
        let today = CzechCalendar.pragueDate(now)
        if CzechCalendar.isBusinessDay(today), now >= pragueTime(today, declarationTime) {
            return today
        }
        return CzechCalendar.previousBusinessDay(onOrBefore: today.adding(days: -1))
    }

    /// How many of the fetch times of the Prague day of `now` (14:35, 15:00, 15:30, 16:30) have come by `now`: the
    /// retries of the day that a fetch at `now` has used up. Meant for a business day whose rates are not cached.
    static func fetchTimesPassed(at now: Date) -> Int {
        let today = CzechCalendar.pragueDate(now)
        return fetchTimes.filter { pragueTime(today, $0) <= now }.count
    }

    // MARK: What is due

    /// What has to be done at `now`, in order: the missing ČNB rates first, then the yearly files that provisional
    /// payments wait for, then the searches for uniform rates and the reminders that end them.
    ///
    /// The ČNB part compares the newest cached declaration with the one that should exist. Up to ten missing business
    /// days of the same year are fetched day by day; a longer gap, a gap into a new year or an empty cache is fetched
    /// as the yearly files of the years involved. In January the year before is fetched too while the cache does not
    /// hold its last declaration (for money received on 1 or 2 January, before the first fixing of the year). After a
    /// failed request nothing is fetched until the back-off ends: neither these files nor those of the payments.
    ///
    /// The missing days are counted with `CzechCalendar`, so a business day on which the ČNB declared nothing after all
    /// is asked for, and its file says an earlier day. It can never be cached, however many days are skipped: the
    /// coordinator takes such a day as done for the run, and the plan moves past it once a later day is cached.
    static func actionsDue(now: Date, state: RefreshState) -> [RefreshAction] {
        cnbActions(now: now, state: state) + uniformActions(now: now, state: state)
    }

    private static func cnbActions(now: Date, state: RefreshState) -> [RefreshAction] {
        guard !isBackingOff(now: now, state: state) else { return [] }
        let newest = newestRatesActions(now: now, state: state)
        let fetchedAnyway = Set(
            newest.flatMap { action -> [Int] in
                guard case .fetchCNBYears(let years) = action else { return [] }
                return years
            })
        let paymentYears = yearsForProvisionalPayments(now: now, state: state).filter { !fetchedAnyway.contains($0) }
        return paymentYears.isEmpty ? newest : newest + [.fetchCNBYearsForPayments(paymentYears)]
    }

    /// The files that bring the cache up to the newest declaration that should exist: nothing for a cache that is
    /// current, otherwise the missing days or the yearly files of the years involved.
    private static func newestRatesActions(now: Date, state: RefreshState) -> [RefreshAction] {
        let expected = expectedNewestDeclaration(now: now)
        if let newest = state.newestCNBDeclaration, newest >= expected {
            return []
        }
        let today = CzechCalendar.pragueDate(now)
        let previousYear = today.year - 1
        let needsPreviousYear =
            today.month == 1 && lacksLastDeclaration(of: previousYear, newest: state.newestCNBDeclaration)
        let previousYearInJanuary = needsPreviousYear ? [previousYear] : []
        guard let newest = state.newestCNBDeclaration else {
            return [.fetchCNBYears(Array(Set([expected.year] + previousYearInJanuary)).sorted())]
        }
        if newest.year == expected.year {
            let missing = businessDays(after: newest, through: expected)
            if missing.count <= maxDailyFetches {
                return [.fetchCNBDays(missing)]
            }
        }
        let years = Array(newest.adding(days: 1).year...expected.year) + previousYearInJanuary
        return [.fetchCNBYears(Array(Set(years)).sorted())]
    }

    /// Whether a failed request is too recent for the next one: within 30 minutes of the first failure in a row, or
    /// within an hour of the second. After a third failure any trigger may try again. A failure that is later than
    /// `now` (the clock was set back) holds nothing back.
    private static func isBackingOff(now: Date, state: RefreshState) -> Bool {
        guard backOff.indices.contains(state.cnbFailureCount - 1), let failure = state.lastCNBFailure else {
            return false
        }
        return failure <= now && now < failure + backOff[state.cnbFailureCount - 1]
    }

    /// Whether the cache does not hold the last declaration of `year`: it is empty, or its newest declaration is
    /// earlier than the last business day of `year`.
    private static func lacksLastDeclaration(of year: Int, newest: CivilDate?) -> Bool {
        guard let newest else { return true }
        guard let lastDay = CivilDate(year: year, month: 12, day: 31) else { return false }
        return newest < CzechCalendar.previousBusinessDay(onOrBefore: lastDay)
    }

    /// The yearly files that the provisional payments of `state.provisionalPaymentDays` wait for, oldest first, each
    /// once. A day counts when the ČNB has declared its rate by `now` (the declaration of the day is not after the
    /// newest one that should exist) and the declaration is not after the newest cached one: the fetches of the newest
    /// rates bring what comes after that, and a day whose rate is not declared yet (today before 14:30, a later day)
    /// waits for them. Each day needs the years that would fill the hole in front of its rate, as for the rate of a
    /// DUZP (`InvoiceRateFixing.yearsToFetch`): its year, also the year before for the first fixing of a year, and only
    /// the year before for the days before that fixing, such as New Year's Day.
    private static func yearsForProvisionalPayments(now: Date, state: RefreshState) -> [Int] {
        let expected = expectedNewestDeclaration(now: now)
        var years: Set<Int> = []
        for day in state.provisionalPaymentDays {
            let declaration = CzechCalendar.rateDeclarationDay(for: day)
            guard declaration <= expected else { continue }
            if let newest = state.newestCNBDeclaration, declaration > newest {
                continue
            }
            years.formUnion(InvoiceRateFixing.yearsToFetch(duzp: day, expectedNewestDeclaration: expected))
        }
        return years.sorted()
    }

    private static func uniformActions(now: Date, state: RefreshState) -> [RefreshAction] {
        // The days of the search are Prague days, like its start on 2 January and its end on 31 March: the GFŘ
        // publishes in Czech time and the deadline is a Czech date, wherever the Mac is. The once-a-day rule counts
        // the same days.
        let today = CzechCalendar.pragueDate(now)
        guard state.lastUniformCheck != today else { return [] }
        var actions: [RefreshAction] = []
        // A year whose rates were entered by hand is not in the list, and is looked for again once they are removed.
        for year in state.finishedYearsLookedForUniformRate.sorted() where !state.gaveUpUniform.contains(year) {
            guard let first = UniformRateSearch.firstDay(of: year),
                let last = UniformRateSearch.lastDay(of: year),
                today >= first
            else {
                continue
            }
            actions.append(.checkUniformRate(year))
            if today >= last {
                actions.append(.uniformRateReminder(year))
            }
        }
        return actions
    }

    // MARK: The next wake

    /// When the refresh has to run next, if no trigger comes first: the next fetch of the ČNB (14:35 and its retries on
    /// a business day whose rates are not cached, otherwise 14:35 of the next business day; after a failure, the time
    /// the back-off ends), or the next midnight in `localTimeZone` while "K datu" follows today, whichever is earlier.
    /// The result is never less than a minute from `now`. The timer may come up to `wakeTolerance` later.
    static func nextWake(now: Date, state: RefreshState, followsToday: Bool, localTimeZone: TimeZone) -> Date {
        var wake = cnbWake(now: now, state: state)
        if followsToday {
            wake = min(wake, nextMidnight(after: now, in: localTimeZone))
        }
        return max(wake, now + shortestWait)
    }

    private static func cnbWake(now: Date, state: RefreshState) -> Date {
        let today = CzechCalendar.pragueDate(now)
        let newest = state.newestCNBDeclaration
        let isBehind = newest.map { $0 < expectedNewestDeclaration(now: now) } ?? true
        if isBehind, state.cnbFailureCount > 0 {
            let failure = min(state.lastCNBFailure ?? now, now)
            if backOff.indices.contains(state.cnbFailureCount - 1) {
                return failure + backOff[state.cnbFailureCount - 1]
            }
            return firstFetch(after: failure)
        }
        let hasTodaysRates = newest.map { $0 >= today } ?? false
        if CzechCalendar.isBusinessDay(today), !hasTodaysRates {
            let used = max(0, state.cnbRetrySlotsUsed[today] ?? 0)
            if used < fetchTimes.count {
                return pragueTime(today, fetchTimes[used])
            }
        }
        return pragueTime(CzechCalendar.nextBusinessDay(onOrAfter: today.adding(days: 1)), fetchTimes[0])
    }

    /// The first fetch at 14:35 Prague time on a business day that is later than `instant`.
    private static func firstFetch(after instant: Date) -> Date {
        let day = CzechCalendar.nextBusinessDay(onOrAfter: CzechCalendar.pragueDate(instant))
        let fetch = pragueTime(day, fetchTimes[0])
        if fetch > instant {
            return fetch
        }
        return pragueTime(CzechCalendar.nextBusinessDay(onOrAfter: day.adding(days: 1)), fetchTimes[0])
    }

    /// The start of the day after the one of `now`, in `timeZone`. On a day of a clock change it is 23 or 25 hours
    /// from the start of the day.
    private static func nextMidnight(after now: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let day = calendar.dateInterval(of: .day, for: now) else {
            preconditionFailure("The Gregorian calendar has no day around \(now).")
        }
        return day.end
    }

    // MARK: Helpers

    /// The business days after `start`, up to and including `end`, oldest first.
    private static func businessDays(after start: CivilDate, through end: CivilDate) -> [CivilDate] {
        var days: [CivilDate] = []
        var day = start.adding(days: 1)
        while day <= end {
            if CzechCalendar.isBusinessDay(day) {
                days.append(day)
            }
            day = day.adding(days: 1)
        }
        return days
    }

    private static func pragueTime(_ day: CivilDate, _ time: (hour: Int, minute: Int)) -> Date {
        CzechCalendar.pragueTime(day, hour: time.hour, minute: time.minute)
    }
}

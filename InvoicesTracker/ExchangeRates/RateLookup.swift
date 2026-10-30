import Foundation

/// The answer to the question which ČNB rate is valid on a day.
nonisolated enum RateLookupResult: Sendable, Hashable {
    /// The rate, and the business day the ČNB declared it on. For crowns that is the day asked about.
    case declared(ExchangeRate, declaredOn: CivilDate)

    /// The rows cannot tell the rate yet: the ČNB has not declared it, or the rows that hold it, or the ones around
    /// the day that would show the ČNB skipped it, have not been loaded. The caller loads more rates and asks again.
    case notYetAvailable

    /// There is no rate to use: the ČNB declared rates for the day but none for this currency, or, on a day it
    /// skipped, the currency had no earlier rate.
    case notPublished
}

/// The one rule that decides which ČNB rate is valid on a day, whatever stores the rates.
///
/// The ČNB declares rates on business days, and a rate stays valid until the next declaration. So money that arrives
/// on a business day is converted at the rate declared that day, and money that arrives on a Saturday, a Sunday or a
/// holiday at the rate of the business day before it. That makes the last rate of the year before the rate for
/// 1 January and for the weekend days that follow it, until the first business day of the year brings its own rate:
/// 2 January, or the Monday after it when 2 January is a weekend day.
///
/// The rule fails closed: it answers with an older rate only when the rows show that nothing was declared in between.
/// A business day without any rate counts as a day the ČNB skipped only if the business day before it and the one
/// after it both have rates. Any other stretch without rates may be a hole in the rows, such as a year or a file that
/// has not been loaded or a download that failed, and an older rate would then be a silently wrong conversion. So the
/// answer is `.notYetAvailable`, and the caller loads more rates.
///
/// The rule does not read the rates itself. The caller finds out the facts below, in memory (`RateTable`) or with
/// queries on the database, and passes them in. They are all stated against the _expected day_,
/// `CzechCalendar.rateDeclarationDay(for: day)`: `day` itself when it is a business day, otherwise the business day
/// before it. That is the day whose declaration should hold the rate.
nonisolated enum RateLookup {
    /// - Parameters:
    ///   - currency: The currency to convert from.
    ///   - day: The day the money arrived.
    ///   - rowOnExpectedDay: The rate of `currency` declared on the expected day, if there is one.
    ///   - anyRowOnExpectedDay: Whether a rate of any currency was declared on the expected day.
    ///   - anyRowOnPreviousBusinessDay: Whether a rate of any currency was declared on the business day directly
    ///     before the expected day, `CzechCalendar.previousBusinessDay(onOrBefore: expectedDay.adding(days: -1))`.
    ///   - anyRowOnNextBusinessDay: Whether a rate of any currency was declared on the first business day after `day`,
    ///     `CzechCalendar.nextBusinessDay(onOrAfter: day.adding(days: 1))`.
    ///   - latestRowOnOrBeforeDay: The latest rate of `currency` declared on or before `day`, if there is one.
    /// - Returns: In this order:
    ///   1. Crowns are worth one crown: rate 1 for an amount of 1, declared on `day`.
    ///   2. The rate of `currency` on the expected day is the one.
    ///   3. Other currencies have a rate on the expected day but `currency` has none: `.notPublished`. The ČNB does
    ///      not quote it that day, like the ruble after 1 March 2022.
    ///   4. Nothing is declared on the expected day, but there are rates on the business day before it and on the
    ///      first business day after `day`: the ČNB skipped a day that our calendar counts as a business day, and the
    ///      rate before it stays valid. The latest rate of `currency` on or before `day` is the one, or
    ///      `.notPublished` if it has none.
    ///   5. Otherwise `.notYetAvailable`: the day is after the newest declaration, which may not have been made yet,
    ///      or it lies in or next to a stretch of rows that is not loaded. Even a currency that has an earlier rate
    ///      waits, because that rate may not be the valid one.
    static func resolve(
        currency: CurrencyCode,
        day: CivilDate,
        rowOnExpectedDay: CNBRateRow?,
        anyRowOnExpectedDay: Bool,
        anyRowOnPreviousBusinessDay: Bool,
        anyRowOnNextBusinessDay: Bool,
        latestRowOnOrBeforeDay: CNBRateRow?
    ) -> RateLookupResult {
        if currency.isCZK {
            return .declared(ExchangeRate(currency: .czk, amount: 1, rate: 1), declaredOn: day)
        }
        if let row = rowOnExpectedDay {
            return .declared(row.exchangeRate, declaredOn: row.declaredOn)
        }
        if anyRowOnExpectedDay {
            return .notPublished
        }
        if anyRowOnPreviousBusinessDay && anyRowOnNextBusinessDay {
            guard let row = latestRowOnOrBeforeDay else { return .notPublished }
            return .declared(row.exchangeRate, declaredOn: row.declaredOn)
        }
        return .notYetAvailable
    }
}

/// ČNB rates held in memory. It answers with `RateLookup.resolve` and only finds out the facts that rule asks for, so
/// it agrees with the database, which finds the same facts with queries.
///
/// A hole in the rows, for example a year that has not been loaded, gives `.notYetAvailable` and never an older rate: a
/// day without rates is read as one the ČNB skipped only between two business days that have rates.
nonisolated struct RateTable: Sendable {
    /// The rows of each currency in ascending order of day, one row for each day.
    private let rowsByCurrency: [CurrencyCode: [CNBRateRow]]

    /// The days with at least one row.
    private let declaredDays: Set<CivilDate>

    /// The latest day the ČNB declared rates on, or nil if there are no rows.
    let newestDeclaration: CivilDate?

    /// The rows may come in any order, from any number of files. If several are for the same currency and day, the last
    /// one counts, as a stored row is replaced by a newer one.
    init(rows: [CNBRateRow]) {
        var lastRowOfEachSlot: [Slot: CNBRateRow] = [:]
        for row in rows {
            lastRowOfEachSlot[Slot(currency: row.currency, day: row.declaredOn)] = row
        }
        let uniqueRows = lastRowOfEachSlot.values
        rowsByCurrency = Dictionary(grouping: uniqueRows, by: \.currency).mapValues { currencyRows in
            currencyRows.sorted { $0.declaredOn < $1.declaredOn }
        }
        let days = Set(uniqueRows.map(\.declaredOn))
        declaredDays = days
        newestDeclaration = days.max()
    }

    /// The rate of `currency` that is valid on `day`.
    func lookup(_ currency: CurrencyCode, on day: CivilDate) -> RateLookupResult {
        let expectedDay = CzechCalendar.rateDeclarationDay(for: day)
        let previousBusinessDay = CzechCalendar.previousBusinessDay(onOrBefore: expectedDay.adding(days: -1))
        let nextBusinessDay = CzechCalendar.nextBusinessDay(onOrAfter: day.adding(days: 1))
        let rows = rowsByCurrency[currency] ?? []
        // rows[..<start] were declared before the expected day, rows[..<end] on or before `day`.
        let start = Self.firstIndex(in: rows) { $0.declaredOn >= expectedDay }
        let end = Self.firstIndex(in: rows) { $0.declaredOn > day }
        var rowOnExpectedDay: CNBRateRow?
        if rows.indices.contains(start), rows[start].declaredOn == expectedDay {
            rowOnExpectedDay = rows[start]
        }
        let latestRowOnOrBeforeDay = end > 0 ? rows[end - 1] : nil
        return RateLookup.resolve(
            currency: currency,
            day: day,
            rowOnExpectedDay: rowOnExpectedDay,
            anyRowOnExpectedDay: declaredDays.contains(expectedDay),
            anyRowOnPreviousBusinessDay: declaredDays.contains(previousBusinessDay),
            anyRowOnNextBusinessDay: declaredDays.contains(nextBusinessDay),
            latestRowOnOrBeforeDay: latestRowOnOrBeforeDay
        )
    }

    /// The index of the first row for which `isLater` is true, or `rows.count` if there is none. `isLater` has to be
    /// false for the first rows and true for the rest, as it is for a comparison of the day in a list in day order.
    private static func firstIndex(in rows: [CNBRateRow], where isLater: (CNBRateRow) -> Bool) -> Int {
        var low = 0
        var high = rows.count
        while low < high {
            let middle = (low + high) / 2
            if isLater(rows[middle]) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }

    /// The place of a rate: one currency on one day.
    private nonisolated struct Slot: Hashable {
        let currency: CurrencyCode
        let day: CivilDate
    }
}

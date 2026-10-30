import Foundation
import Testing
@testable import InvoicesTracker

struct RateLookupTests {
    // MARK: Helpers

    private func table(_ years: [Int]) throws -> RateTable {
        try RateTable(rows: cnbYearlyRows(years))
    }

    /// The same without the rows declared on `days`, as if the ČNB had skipped them or they had not been loaded.
    private func table(_ years: [Int], without days: [String]) throws -> RateTable {
        let removed = Set(days.map(civilDate))
        return try RateTable(rows: cnbYearlyRows(years).filter { !removed.contains($0.declaredOn) })
    }

    /// `amount` units of `code` cost `rate` crowns, the rate as plain POSIX text.
    private func quote(_ code: String, _ amount: Int, _ rate: String) -> ExchangeRate {
        ExchangeRate(currency: CurrencyCode(code)!, amount: amount, rate: decimal(rate))
    }

    /// The answer for a rate of `code` that the ČNB declared on `declaredOn`.
    private func declared(_ code: String, _ amount: Int, _ rate: String, on declaredOn: String) -> RateLookupResult {
        .declared(quote(code, amount, rate), declaredOn: civilDate(declaredOn))
    }

    private func usdRow(_ day: String, _ rate: String = "21.622") -> CNBRateRow {
        CNBRateRow(declaredOn: civilDate(day), currency: .usd, amount: 1, rate: decimal(rate))
    }

    private func eurRow(_ day: String, _ rate: String = "24.325") -> CNBRateRow {
        CNBRateRow(declaredOn: civilDate(day), currency: .eur, amount: 1, rate: decimal(rate))
    }

    private func lookup(_ table: RateTable, _ currency: CurrencyCode, _ day: String) -> RateLookupResult {
        table.lookup(currency, on: civilDate(day))
    }

    // MARK: The day a rate is valid on

    @Test func aBusinessDayUsesItsOwnRate() throws {
        let table = try table([2025, 2026])
        #expect(lookup(table, .usd, "2026-10-16") == declared("USD", 1, "21.622", on: "2026-10-16"))
        #expect(lookup(table, .eur, "2026-10-16") == declared("EUR", 1, "24.325", on: "2026-10-16"))
        #expect(lookup(table, .usd, "2026-09-30") == declared("USD", 1, "21.522", on: "2026-09-30"))
        #expect(lookup(table, .usd, "2026-01-02") == declared("USD", 1, "20.611", on: "2026-01-02"))
        #expect(lookup(table, .usd, "2025-12-31") == declared("USD", 1, "20.632", on: "2025-12-31"))
    }

    @Test func aWeekendUsesTheRateOfTheFridayBefore() throws {
        let table = try table([2025, 2026])
        #expect(lookup(table, .usd, "2026-01-03") == declared("USD", 1, "20.611", on: "2026-01-02"))  // Saturday
        #expect(lookup(table, .usd, "2026-01-04") == declared("USD", 1, "20.611", on: "2026-01-02"))  // Sunday
        #expect(lookup(table, .usd, "2026-10-17") == declared("USD", 1, "21.622", on: "2026-10-16"))  // Saturday
        #expect(lookup(table, .usd, "2026-10-18") == declared("USD", 1, "21.622", on: "2026-10-16"))  // Sunday
    }

    /// Good Friday (3 April) and Easter Monday (6 April) 2026 have no declaration, so the rate of Thursday the 2nd
    /// is valid through the long weekend.
    @Test func aHolidayUsesTheRateOfTheBusinessDayBefore() throws {
        let table = try table([2025, 2026])
        for day in ["2026-04-03", "2026-04-04", "2026-04-05", "2026-04-06"] {
            #expect(lookup(table, .usd, day) == declared("USD", 1, "21.291", on: "2026-04-02"), "\(day)")
        }
        #expect(lookup(table, .usd, "2026-04-07") == declared("USD", 1, "21.230", on: "2026-04-07"))
    }

    /// Money received on 1 January is converted at the last rate of the year before.
    @Test func newYearsDayUsesTheLastRateOfTheYearBefore() throws {
        let table = try table([2025, 2026])
        #expect(lookup(table, .usd, "2026-01-01") == declared("USD", 1, "20.632", on: "2025-12-31"))
        #expect(lookup(table, .eur, "2026-01-01") == declared("EUR", 1, "24.245", on: "2025-12-31"))
    }

    /// For every day from 1 January to the Saturday after the newest declaration, the rate is the latest one that was
    /// declared on or before the day.
    @Test func everyDayUsesTheLatestDeclarationOnOrBeforeIt() throws {
        let all = try cnbYearlyRows([2025, 2026])
        let table = RateTable(rows: all)
        let usdRows = all.filter { $0.currency == .usd }
        let first = civilDate("2026-01-01")
        for offset in 0...civilDate("2026-10-17").days(since: first) {
            let day = first.adding(days: offset)
            let latest = try #require(usdRows.last { $0.declaredOn <= day })
            #expect(
                table.lookup(.usd, on: day) == .declared(latest.exchangeRate, declaredOn: latest.declaredOn), "\(day)")
        }
    }

    // MARK: Rates that are not there

    @Test func aBusinessDayAfterTheNewestDeclarationIsNotYetAvailable() throws {
        let table = try table([2025, 2026])
        for day in ["2026-10-19", "2026-10-20", "2026-10-24", "2026-10-28", "2026-12-31", "2027-01-04"] {
            #expect(lookup(table, .usd, day) == .notYetAvailable, "\(day)")
        }
    }

    @Test func theFirstDaysOfAYearAreNotYetAvailableWithoutTheYearBefore() throws {
        let table = try table([2026])
        #expect(lookup(table, .usd, "2025-12-31") == .notYetAvailable)
        #expect(lookup(table, .usd, "2026-01-01") == .notYetAvailable)
        #expect(lookup(table, .usd, "2026-01-02") == declared("USD", 1, "20.611", on: "2026-01-02"))
        #expect(lookup(table, .usd, "2026-01-03") == declared("USD", 1, "20.611", on: "2026-01-02"))
    }

    @Test func anEmptyTableHasNoRatesYet() {
        let table = RateTable(rows: [])
        #expect(lookup(table, .usd, "2026-10-16") == .notYetAvailable)
        #expect(lookup(table, .usd, "2026-10-17") == .notYetAvailable)
        #expect(table.newestDeclaration == nil)
    }

    @Test func theRubleIsNotPublishedAfterItsRowsEnd() throws {
        let table = try table([2022])
        let rub = CurrencyCode("RUB")!
        #expect(lookup(table, rub, "2022-01-03") == declared("RUB", 100, "29.362", on: "2022-01-03"))
        #expect(lookup(table, rub, "2022-03-01") == declared("RUB", 100, "22.877", on: "2022-03-01"))
        #expect(lookup(table, rub, "2022-03-04") == .notPublished)
        // Saturday: the rates of Friday are valid, and they have no ruble.
        #expect(lookup(table, rub, "2022-03-05") == .notPublished)
        #expect(lookup(table, .usd, "2022-03-04") == declared("USD", 1, "23.549", on: "2022-03-04"))
    }

    @Test func aCurrencyTheCNBNeverQuotedIsNotPublished() throws {
        let table = try table([2022])
        let unknown = CurrencyCode("XYZ")!
        #expect(lookup(table, unknown, "2022-06-01") == .notPublished)
        #expect(lookup(table, unknown, "2022-06-04") == .notPublished)  // Saturday
    }

    // MARK: A business day the ČNB skipped

    /// A business day without any rate between two business days that have rates (here Wednesday 14 October 2026, with
    /// the 13th and the 15th) is read as a day the ČNB skipped, so the rate before it stays valid. That is the only
    /// kind of missing day that is bridged, as the tests below show.
    @Test func aBusinessDayBetweenTwoDaysWithRatesUsesTheLatestEarlierRate() throws {
        let skipped = civilDate("2026-10-14")
        let table = try RateTable(rows: cnbYearlyRows([2026]).filter { $0.declaredOn != skipped })
        #expect(lookup(table, .usd, "2026-10-14") == declared("USD", 1, "21.788", on: "2026-10-13"))
        #expect(lookup(table, .eur, "2026-10-14") == declared("EUR", 1, "24.375", on: "2026-10-13"))
        #expect(lookup(table, .usd, "2026-10-13") == declared("USD", 1, "21.788", on: "2026-10-13"))
        #expect(lookup(table, .usd, "2026-10-15") == declared("USD", 1, "21.732", on: "2026-10-15"))
    }

    @Test func aSkippedDayIsNotPublishedForACurrencyWithoutEarlierRates() {
        // Tuesday the 13th and Thursday the 15th have a rate for the euro, only the 15th also for the dollar. Wednesday
        // has none.
        let table = RateTable(rows: [eurRow("2026-10-13"), eurRow("2026-10-15"), usdRow("2026-10-15")])
        #expect(lookup(table, .usd, "2026-10-14") == .notPublished)
        #expect(
            lookup(table, .eur, "2026-10-14")
                == .declared(eurRow("2026-10-13").exchangeRate, declaredOn: civilDate("2026-10-13")))
    }

    /// The days next to a skipped one are the business days around it, not the calendar days: over a weekend, and over
    /// the holidays of Easter 2026 (Good Friday 3 April and Easter Monday 6 April).
    @Test(arguments: [
        // A skipped Friday has the Thursday before it and the Monday after it.
        ("2026-10-09", ["2026-10-09", "2026-10-10", "2026-10-11"], "21.811", "2026-10-08"),
        // A skipped Monday has the Friday before it, over the weekend.
        ("2026-10-12", ["2026-10-12"], "21.745", "2026-10-09"),
        // The Thursday before Good Friday has the Tuesday after Easter Monday as the next business day.
        ("2026-04-02", ["2026-04-02", "2026-04-03", "2026-04-04", "2026-04-05", "2026-04-06"], "21.129", "2026-04-01"),
        // The Tuesday after Easter Monday has the Thursday before Good Friday as the previous business day.
        ("2026-04-07", ["2026-04-07"], "21.291", "2026-04-02"),
    ])
    func theDaysAroundASkippedDayAreBusinessDays(
        _ skipped: String, _ days: [String], _ rate: String, _ declaredOn: String
    ) throws {
        let table = try table([2026], without: [skipped])
        for day in days {
            #expect(lookup(table, .usd, day) == declared("USD", 1, rate, on: declaredOn), "\(day)")
        }
    }

    // MARK: A hole in the rows is not a skipped day

    /// Rows for all of 2025 but for 2026 only the last day: March 2026 is a hole in the rows, not a run of days the
    /// ČNB skipped. The rate of 31 December 2025 must not stand in for the real one of 10 March (20,941).
    @Test func aHoleAfterTheRowsOfTheYearBeforeIsNotASkippedDay() throws {
        let lastDay = civilDate("2026-10-16")
        let lastDayOf2026 = try cnbYearlyRows([2026]).filter { $0.declaredOn == lastDay }
        let table = try RateTable(rows: cnbYearlyRows([2025]) + lastDayOf2026)
        for day in ["2026-01-02", "2026-01-03", "2026-03-10", "2026-03-14", "2026-10-15"] {
            #expect(lookup(table, .usd, day) == .notYetAvailable, "\(day)")
        }
        // Still covered by rows: 1 January by the last day of 2025, and 16 October by its own.
        #expect(lookup(table, .usd, "2026-01-01") == declared("USD", 1, "20.632", on: "2025-12-31"))
        #expect(lookup(table, .usd, "2026-10-16") == declared("USD", 1, "21.622", on: "2026-10-16"))
    }

    /// 2022 and 2026 are loaded and 2023 to 2025 are not: no day in between, on a weekend or not, gets a rate of 2022.
    @Test func aHoleOfYearsIsNotASkippedDay() throws {
        let table = try table([2022, 2026])
        for day in ["2023-01-02", "2024-06-07", "2024-06-08", "2024-06-09", "2024-06-10", "2025-12-31"] {
            #expect(lookup(table, .usd, day) == .notYetAvailable, "\(day)")
        }
        // The last declaration of 2022 stays valid until the first one of 2023.
        #expect(lookup(table, .usd, "2022-12-31") == declared("USD", 1, "22.616", on: "2022-12-30"))
        #expect(lookup(table, .usd, "2023-01-01") == declared("USD", 1, "22.616", on: "2022-12-30"))
    }

    /// A missing day is a skipped one only with rates on the business days on both sides of it. With rows on one side
    /// only it may be the edge of a hole, and two missing business days in a row are not bridged either.
    @Test func rowsOnOnlyOneSideOfAMissingDayAreNotEnough() throws {
        // The 14th and the 15th are missing: the day before the 14th has rows, the day after it has none.
        let missingAfter = try table([2026], without: ["2026-10-14", "2026-10-15"])
        #expect(lookup(missingAfter, .usd, "2026-10-14") == .notYetAvailable)
        #expect(lookup(missingAfter, .usd, "2026-10-15") == .notYetAvailable)
        // The 13th and the 14th are missing: the day after the 14th has rows, the day before it has none.
        let missingBefore = try table([2026], without: ["2026-10-13", "2026-10-14"])
        #expect(lookup(missingBefore, .usd, "2026-10-13") == .notYetAvailable)
        #expect(lookup(missingBefore, .usd, "2026-10-14") == .notYetAvailable)
    }

    // MARK: Newest declaration, row order, duplicates

    @Test func newestDeclarationIsTheLatestDayWithRates() throws {
        #expect(try table([2025, 2026]).newestDeclaration == civilDate("2026-10-16"))
        #expect(try table([2026, 2025]).newestDeclaration == civilDate("2026-10-16"))
        #expect(try table([2022]).newestDeclaration == civilDate("2022-12-30"))
        #expect(RateTable(rows: []).newestDeclaration == nil)
    }

    @Test func theOrderOfTheRowsDoesNotMatter() throws {
        let ordered = try cnbYearlyRows([2025, 2026])
        let forward = RateTable(rows: ordered)
        let backward = RateTable(rows: ordered.reversed())
        #expect(backward.newestDeclaration == civilDate("2026-10-16"))
        for day in ["2025-12-31", "2026-01-01", "2026-01-03", "2026-04-05", "2026-10-14", "2026-10-17", "2026-10-19"] {
            for currency in [CurrencyCode.usd, .eur, .czk] {
                #expect(lookup(forward, currency, day) == lookup(backward, currency, day), "\(currency) \(day)")
            }
        }
    }

    @Test func ofTwoRowsForTheSameCurrencyAndDayTheLastOneWins() {
        let day = civilDate("2026-10-16")
        let stale = usdRow("2026-10-16", "21.000")
        let current = usdRow("2026-10-16", "21.622")
        #expect(
            RateTable(rows: [stale, current]).lookup(.usd, on: day) == .declared(current.exchangeRate, declaredOn: day))
        #expect(
            RateTable(rows: [current, stale]).lookup(.usd, on: day) == .declared(stale.exchangeRate, declaredOn: day))
    }

    // MARK: Crowns

    @Test func crownsAreWorthOneCrownOnEveryDay() throws {
        let one = ExchangeRate(currency: .czk, amount: 1, rate: 1)
        let table = try table([2025, 2026])
        for day in ["2021-01-01", "2026-01-01", "2026-10-16", "2026-10-17", "2026-10-19", "2030-06-30"] {
            #expect(lookup(table, .czk, day) == .declared(one, declaredOn: civilDate(day)), "\(day)")
        }
        #expect(lookup(RateTable(rows: []), .czk, "2026-10-17") == .declared(one, declaredOn: civilDate("2026-10-17")))
    }

    // MARK: The rule

    /// Calls the rule with the facts that are not stated taken as false or absent.
    private func resolve(
        _ currency: CurrencyCode = .usd,
        on day: String = "2026-10-14",
        rowOnExpectedDay: CNBRateRow? = nil,
        anyRowOnExpectedDay: Bool = false,
        anyRowOnPreviousBusinessDay: Bool = false,
        anyRowOnNextBusinessDay: Bool = false,
        latestRowOnOrBeforeDay: CNBRateRow? = nil
    ) -> RateLookupResult {
        RateLookup.resolve(
            currency: currency,
            day: civilDate(day),
            rowOnExpectedDay: rowOnExpectedDay,
            anyRowOnExpectedDay: anyRowOnExpectedDay,
            anyRowOnPreviousBusinessDay: anyRowOnPreviousBusinessDay,
            anyRowOnNextBusinessDay: anyRowOnNextBusinessDay,
            latestRowOnOrBeforeDay: latestRowOnOrBeforeDay
        )
    }

    @Test func ruleGivesCrownsTheRateOneWhateverElseIsKnown() {
        let one = RateLookupResult.declared(
            ExchangeRate(currency: .czk, amount: 1, rate: 1), declaredOn: civilDate("2026-10-17"))
        #expect(resolve(.czk, on: "2026-10-17") == one)
        #expect(resolve(.czk, on: "2026-10-17", anyRowOnExpectedDay: true, anyRowOnPreviousBusinessDay: true) == one)
        #expect(
            resolve(.czk, on: "2026-10-17", rowOnExpectedDay: usdRow("2026-10-16"), anyRowOnExpectedDay: true) == one)
    }

    @Test func ruleUsesTheRowOfTheExpectedDay() {
        let row = usdRow("2026-10-14", "21.754")
        let earlier = usdRow("2026-10-13", "21.788")
        let result = RateLookupResult.declared(row.exchangeRate, declaredOn: civilDate("2026-10-14"))
        #expect(resolve(rowOnExpectedDay: row, anyRowOnExpectedDay: true) == result)
        #expect(
            resolve(
                rowOnExpectedDay: row, anyRowOnExpectedDay: true, anyRowOnPreviousBusinessDay: true,
                anyRowOnNextBusinessDay: true, latestRowOnOrBeforeDay: earlier) == result)
    }

    @Test(arguments: [(false, false), (true, false), (false, true), (true, true)])
    func ruleSaysNotPublishedWhenOnlyOtherCurrenciesHaveARowOnTheExpectedDay(_ previous: Bool, _ next: Bool) {
        let result = resolve(
            anyRowOnExpectedDay: true, anyRowOnPreviousBusinessDay: previous, anyRowOnNextBusinessDay: next,
            latestRowOnOrBeforeDay: usdRow("2026-10-13"))
        #expect(result == .notPublished)
    }

    @Test func ruleUsesTheLatestRowWhenBothNeighbouringBusinessDaysHaveRows() {
        let latest = usdRow("2026-10-13", "21.788")
        let result = resolve(
            anyRowOnPreviousBusinessDay: true, anyRowOnNextBusinessDay: true, latestRowOnOrBeforeDay: latest)
        #expect(result == .declared(latest.exchangeRate, declaredOn: civilDate("2026-10-13")))
    }

    @Test func ruleSaysNotPublishedWhenTheCurrencyHasNoRowBeforeASkippedDay() {
        let result = resolve(anyRowOnPreviousBusinessDay: true, anyRowOnNextBusinessDay: true)
        #expect(result == .notPublished)
    }

    /// Unless both neighbouring business days have rates, the day may not have been declared yet or may lie in a hole
    /// in the rows, even if the currency has an earlier rate. That rate may not be the valid one.
    @Test(arguments: [(false, false), (true, false), (false, true)])
    func ruleSaysNotYetAvailableUnlessBothNeighbouringBusinessDaysHaveRows(_ previous: Bool, _ next: Bool) {
        let withEarlierRate = resolve(
            anyRowOnPreviousBusinessDay: previous, anyRowOnNextBusinessDay: next,
            latestRowOnOrBeforeDay: usdRow("2026-10-13"))
        let withoutEarlierRate = resolve(anyRowOnPreviousBusinessDay: previous, anyRowOnNextBusinessDay: next)
        #expect(withEarlierRate == .notYetAvailable)
        #expect(withoutEarlierRate == .notYetAvailable)
    }
}

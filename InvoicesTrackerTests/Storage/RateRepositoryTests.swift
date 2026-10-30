import Foundation
import Testing
@testable import InvoicesTracker

/// The ČNB rates in the database: inserting them, the lookup of the rate valid on a day (which has to give what the
/// in-memory `RateTable` gives for the same rows) and the latest rate of a currency. The rows are the real ČNB files
/// in the test fixtures.
struct RateRepositoryTests {
    // MARK: Helpers

    /// The rows of the yearly fixtures of `years` except those declared on `days`, as if the ČNB had skipped them or
    /// they had not been loaded.
    private func rows(_ years: [Int], without days: [String] = []) throws -> [CNBRateRow] {
        let removed = Set(days.map(civilDate))
        return try cnbYearlyRows(years).filter { !removed.contains($0.declaredOn) }
    }

    /// A new database that holds `rows`. Pair it with `removeTemporaryDirectory(_:)`.
    private func databaseHolding(_ rows: [CNBRateRow]) async throws -> (Database, URL) {
        let (database, directory) = try makeDatabase()
        do {
            try await database.insertCNBRates(rows)
        } catch {
            removeTemporaryDirectory(directory)
            throw error
        }
        return (database, directory)
    }

    private func row(_ day: String, _ currency: CurrencyCode, amount: Int = 1, _ rate: String) -> CNBRateRow {
        CNBRateRow(declaredOn: civilDate(day), currency: currency, amount: amount, rate: decimal(rate))
    }

    /// The answer for a rate of `code` that the ČNB declared on `declaredOn`.
    private func declared(_ code: String, _ amount: Int, _ rate: String, on declaredOn: String) -> RateLookupResult {
        let quote = ExchangeRate(currency: CurrencyCode(code)!, amount: amount, rate: decimal(rate))
        return .declared(quote, declaredOn: civilDate(declaredOn))
    }

    private func storedRate(_ code: CurrencyCode, _ rate: String, declaredOn day: String) -> StoredRate {
        StoredRate(rate: ExchangeRate(currency: code, amount: 1, rate: decimal(rate)), declaredOn: civilDate(day))
    }

    private func days(from first: String, to last: String) -> [CivilDate] {
        let start = civilDate(first)
        return (0...civilDate(last).days(since: start)).map { start.adding(days: $0) }
    }

    private func count(in database: Database) async throws -> Int64 {
        try await database.integer("SELECT count(*) FROM cnb_rate")
    }

    private func lookup(
        _ database: Database, _ currency: CurrencyCode, _ day: String
    ) async throws -> RateLookupResult {
        try await database.cnbRate(currency, on: civilDate(day))
    }

    // MARK: Inserting rows

    @Test func insertedRowsAreStoredAsExactTextWithTheDayAsISOText() async throws {
        let (database, directory) = try await databaseHolding(rows([2026]))
        defer { removeTemporaryDirectory(directory) }

        let stored = try await database.read { connection in
            try connection.query(
                """
                SELECT declared_on, currency, amount, rate FROM cnb_rate
                WHERE declared_on = '2026-10-16' AND currency IN ('USD', 'JPY') ORDER BY currency
                """
            )
        }

        #expect(stored.map { [$0.text(0), $0.text(1), String($0.int64(2)), $0.text(3)] }
            == [["2026-10-16", "JPY", "100", "13.686"], ["2026-10-16", "USD", "1", "21.622"]])
        #expect(try await count(in: database) == 200 * 30)
    }

    @Test func aRowForTheSameDayAndCurrencyReplacesTheStoredOne() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let yen = CurrencyCode("JPY")!
        try await database.insertCNBRates([
            row("2026-10-16", .usd, "21.000"), row("2026-10-16", .eur, "24.325"),
            row("2026-10-16", yen, amount: 100, "13.6"),
        ])

        try await database.insertCNBRates([
            row("2026-10-16", .usd, "21.622"), row("2026-10-16", yen, amount: 1000, "136"),
        ])

        #expect(try await count(in: database) == 3)
        #expect(try await lookup(database, .usd, "2026-10-16") == declared("USD", 1, "21.622", on: "2026-10-16"))
        #expect(try await lookup(database, .eur, "2026-10-16") == declared("EUR", 1, "24.325", on: "2026-10-16"))
        #expect(try await lookup(database, yen, "2026-10-16") == declared("JPY", 1000, "136", on: "2026-10-16"))
    }

    /// The same rule as `RateTable`: of two rows for one currency and day, the last one counts.
    @Test func ofTwoRowsForTheSameDayAndCurrencyInOneCallTheLastOneWins() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let stale = row("2026-10-16", .usd, "21.000")
        let current = row("2026-10-16", .usd, "21.622")

        try await database.insertCNBRates([stale, current])
        #expect(try await lookup(database, .usd, "2026-10-16") == declared("USD", 1, "21.622", on: "2026-10-16"))

        try await database.insertCNBRates([current, stale])
        #expect(try await lookup(database, .usd, "2026-10-16") == declared("USD", 1, "21.000", on: "2026-10-16"))
        #expect(try await count(in: database) == 1)
    }

    @Test func insertingTheSameRowsAgainChangesNothing() async throws {
        let (database, directory) = try await databaseHolding(rows([2025]))
        defer { removeTemporaryDirectory(directory) }
        let rowsBefore = try await count(in: database)
        let answerBefore = try await lookup(database, .usd, "2025-06-10")

        try await database.insertCNBRates(rows([2025]))

        #expect(try await count(in: database) == rowsBefore)
        #expect(try await lookup(database, .usd, "2025-06-10") == answerBefore)
    }

    @Test func insertingNoRowsIsNotAWrite() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        try await database.insertCNBRates([])

        #expect(await database.writeCount == 0)
        #expect(try await database.newestCNBDeclaration() == nil)
    }

    @Test func rowsThatCannotBeStoredAreRefusedAndNoneOfTheBatchIsKept() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let good = row("2026-10-16", .usd, "21.622")
        let zeroAmount = row("2026-10-16", .eur, amount: 0, "24.325")
        let zeroRate = row("2026-10-16", .eur, "0")
        let negativeRate = row("2026-10-16", .eur, "-24.325")

        for bad in [zeroAmount, zeroRate, negativeRate] {
            await #expect { try await database.insertCNBRates([good, bad]) } throws: { isConstraintViolation($0) }
            await #expect { try await database.insertCNBRates([bad, good]) } throws: { isConstraintViolation($0) }
        }

        #expect(try await count(in: database) == 0)
        #expect(await database.writeCount == 0)
    }

    // MARK: Newest declaration and currencies

    @Test func theNewestDeclarationIsTheLatestDayWithRates() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        #expect(try await database.newestCNBDeclaration() == nil)

        try await database.insertCNBRates(rows([2025]))
        #expect(try await database.newestCNBDeclaration() == civilDate("2025-12-31"))

        // Rows of an earlier year do not move it back, whatever the order they are inserted in.
        try await database.insertCNBRates(rows([2026]))
        try await database.insertCNBRates(rows([2022]))
        #expect(try await database.newestCNBDeclaration() == civilDate("2026-10-16"))
    }

    @Test func theCurrenciesAreThoseWithAtLeastOneRow() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        #expect(try await database.cnbCurrencies().isEmpty)
        let ruble = try #require(CurrencyCode("RUB"))
        let all = try rows([2022, 2026])

        try await database.insertCNBRates(all)

        let currencies = try await database.cnbCurrencies()
        #expect(currencies == Set(all.map(\.currency)))
        // The ruble is only in the file of 2022, the crown is never quoted.
        #expect(currencies.contains(ruble))
        #expect(currencies.contains(.usd) && currencies.contains(.eur))
        #expect(!currencies.contains(.czk))
    }

    // MARK: The rate valid on a day

    @Test func aBusinessDayHasItsOwnRateAndAWeekendTheRateOfTheFridayBefore() async throws {
        let (database, directory) = try await databaseHolding(rows([2025, 2026]))
        defer { removeTemporaryDirectory(directory) }

        let cases: [(CurrencyCode, String, RateLookupResult)] = [
            (.usd, "2026-10-16", declared("USD", 1, "21.622", on: "2026-10-16")),
            (.eur, "2026-10-16", declared("EUR", 1, "24.325", on: "2026-10-16")),
            (.usd, "2026-10-17", declared("USD", 1, "21.622", on: "2026-10-16")),
            (.usd, "2026-10-18", declared("USD", 1, "21.622", on: "2026-10-16")),
            (.usd, "2026-09-30", declared("USD", 1, "21.522", on: "2026-09-30")),
            (.usd, "2026-01-02", declared("USD", 1, "20.611", on: "2026-01-02")),
            // Good Friday and Easter Monday 2026 take the rate of the Thursday before.
            (.usd, "2026-04-03", declared("USD", 1, "21.291", on: "2026-04-02")),
            (.usd, "2026-04-06", declared("USD", 1, "21.291", on: "2026-04-02")),
            (.usd, "2026-04-07", declared("USD", 1, "21.230", on: "2026-04-07")),
        ]
        for (currency, day, expected) in cases {
            #expect(try await database.cnbRate(currency, on: civilDate(day)) == expected, "\(currency) \(day)")
        }
    }

    /// Money received on 1 January is converted at the last rate of the year before, if its rows are loaded.
    @Test func newYearsDayUsesTheLastRateOfTheYearBeforeWhenItsRowsAreThere() async throws {
        let (database, directory) = try await databaseHolding(rows([2025, 2026]))
        defer { removeTemporaryDirectory(directory) }

        #expect(try await lookup(database, .usd, "2026-01-01") == declared("USD", 1, "20.632", on: "2025-12-31"))
        #expect(try await lookup(database, .eur, "2026-01-01") == declared("EUR", 1, "24.245", on: "2025-12-31"))
    }

    @Test func newYearsDayIsNotYetAvailableWithoutTheRowsOfTheYearBefore() async throws {
        let (database, directory) = try await databaseHolding(rows([2026]))
        defer { removeTemporaryDirectory(directory) }

        #expect(try await lookup(database, .usd, "2025-12-31") == .notYetAvailable)
        #expect(try await lookup(database, .usd, "2026-01-01") == .notYetAvailable)
        #expect(try await lookup(database, .usd, "2026-01-02") == declared("USD", 1, "20.611", on: "2026-01-02"))
        #expect(try await lookup(database, .usd, "2026-01-03") == declared("USD", 1, "20.611", on: "2026-01-02"))
    }

    @Test func aBusinessDayAfterTheNewestDeclarationIsNotYetAvailable() async throws {
        let (database, directory) = try await databaseHolding(rows([2025, 2026]))
        defer { removeTemporaryDirectory(directory) }

        for day in ["2026-10-19", "2026-10-20", "2026-10-24", "2026-10-28", "2026-12-31", "2027-01-04"] {
            #expect(try await database.cnbRate(.usd, on: civilDate(day)) == .notYetAvailable, "\(day)")
        }
    }

    @Test func crownsAreWorthOneCrownOnEveryDayWithOrWithoutRates() async throws {
        let (full, fullDirectory) = try await databaseHolding(rows([2025, 2026]))
        defer { removeTemporaryDirectory(fullDirectory) }
        let (empty, emptyDirectory) = try makeDatabase()
        defer { removeTemporaryDirectory(emptyDirectory) }
        let one = ExchangeRate(currency: .czk, amount: 1, rate: 1)

        for day in ["2021-01-01", "2026-01-01", "2026-10-16", "2026-10-17", "2026-10-19", "2030-06-30"] {
            let expected = RateLookupResult.declared(one, declaredOn: civilDate(day))
            #expect(try await full.cnbRate(.czk, on: civilDate(day)) == expected, "\(day)")
            #expect(try await empty.cnbRate(.czk, on: civilDate(day)) == expected, "\(day) without rates")
        }
    }

    @Test func aDatabaseWithoutRatesHasNoRateYet() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        #expect(try await lookup(database, .usd, "2026-10-16") == .notYetAvailable)
        #expect(try await lookup(database, .usd, "2026-10-17") == .notYetAvailable)
    }

    @Test func theRubleIsNotPublishedAfterItsRowsEnd() async throws {
        let (database, directory) = try await databaseHolding(rows([2022]))
        defer { removeTemporaryDirectory(directory) }
        let ruble = try #require(CurrencyCode("RUB"))
        let unknown = try #require(CurrencyCode("XYZ"))

        #expect(try await lookup(database, ruble, "2022-03-01") == declared("RUB", 100, "22.877", on: "2022-03-01"))
        #expect(try await lookup(database, ruble, "2022-03-04") == .notPublished)
        // Saturday: the rates of Friday are valid, and they have no ruble.
        #expect(try await lookup(database, ruble, "2022-03-05") == .notPublished)
        #expect(try await lookup(database, .usd, "2022-03-04") == declared("USD", 1, "23.549", on: "2022-03-04"))
        // A currency the ČNB never quoted.
        #expect(try await lookup(database, unknown, "2022-06-01") == .notPublished)
        #expect(try await lookup(database, unknown, "2022-06-04") == .notPublished)
    }

    /// A business day without any rate between two business days that have rates is a day the ČNB skipped.
    @Test func aBusinessDayTheCNBSkippedUsesTheLatestEarlierRate() async throws {
        let (database, directory) = try await databaseHolding(rows([2026], without: ["2026-10-14"]))
        defer { removeTemporaryDirectory(directory) }

        #expect(try await lookup(database, .usd, "2026-10-14") == declared("USD", 1, "21.788", on: "2026-10-13"))
        #expect(try await lookup(database, .eur, "2026-10-14") == declared("EUR", 1, "24.375", on: "2026-10-13"))
        #expect(try await lookup(database, .usd, "2026-10-15") == declared("USD", 1, "21.732", on: "2026-10-15"))
    }

    /// 2025 is loaded but of 2026 only the last day: March 2026 is a hole, not a run of days the ČNB skipped.
    @Test func aHoleInTheRowsIsNotASkippedDay() async throws {
        let lastDay = civilDate("2026-10-16")
        let onlyLastDayOf2026 = try rows([2026]).filter { $0.declaredOn == lastDay }
        let (database, directory) = try await databaseHolding(rows([2025]) + onlyLastDayOf2026)
        defer { removeTemporaryDirectory(directory) }

        for day in ["2026-01-02", "2026-01-03", "2026-03-10", "2026-03-14", "2026-10-15"] {
            #expect(try await database.cnbRate(.usd, on: civilDate(day)) == .notYetAvailable, "\(day)")
        }
        #expect(try await lookup(database, .usd, "2026-01-01") == declared("USD", 1, "20.632", on: "2025-12-31"))
        #expect(try await lookup(database, .usd, "2026-10-16") == declared("USD", 1, "21.622", on: "2026-10-16"))
    }

    // MARK: The database and the in-memory table agree

    /// What the lookup asks about is the same, so the answer must be the same: for every currency and day of the
    /// windows, the database gives what a `RateTable` of the same rows gives.
    private struct Scenario {
        let name: String
        let rows: [CNBRateRow]
        let windows: [(first: String, last: String)]
    }

    @Test func theDatabaseAnswersLikeARateTableOfTheSameRows() async throws {
        let lastDayOf2026 = civilDate("2026-10-16")
        let scenarios = [
            // Every day of the two years, with the year ends and the Easter of 2026 inside.
            Scenario(name: "2025 and 2026", rows: try rows([2025, 2026]), windows: [("2024-12-20", "2026-11-10")]),
            Scenario(
                name: "2026 without the year before", rows: try rows([2026]),
                windows: [("2025-12-20", "2026-01-12"), ("2026-04-01", "2026-04-09"), ("2026-10-10", "2026-10-25")]),
            Scenario(
                name: "a skipped Wednesday", rows: try rows([2026], without: ["2026-10-14"]),
                windows: [("2026-10-08", "2026-10-20")]),
            Scenario(
                name: "two skipped days in a row", rows: try rows([2026], without: ["2026-10-14", "2026-10-15"]),
                windows: [("2026-10-08", "2026-10-20")]),
            Scenario(
                name: "a skipped Friday", rows: try rows([2026], without: ["2026-10-09"]),
                windows: [("2026-10-05", "2026-10-15")]),
            Scenario(
                name: "the Thursday before Good Friday skipped", rows: try rows([2026], without: ["2026-04-02"]),
                windows: [("2026-03-30", "2026-04-10")]),
            Scenario(
                name: "a hole after 2025",
                rows: try rows([2025]) + rows([2026]).filter { $0.declaredOn == lastDayOf2026 },
                windows: [("2025-12-20", "2026-01-12"), ("2026-03-08", "2026-03-16"), ("2026-10-10", "2026-10-20")]),
            Scenario(
                name: "2022 and 2026", rows: try rows([2022, 2026]),
                windows: [
                    ("2022-02-25", "2022-03-08"), ("2022-12-24", "2023-01-08"), ("2024-06-01", "2024-06-12"),
                    ("2025-12-28", "2026-01-06"), ("2026-10-12", "2026-10-22"),
                ]),
            Scenario(name: "no rows", rows: [], windows: [("2026-10-10", "2026-10-20")]),
        ]
        let currencies = ["USD", "EUR", "CZK", "JPY", "RUB", "XYZ"].map { CurrencyCode($0)! }

        for scenario in scenarios {
            let (database, directory) = try await databaseHolding(scenario.rows)
            defer { removeTemporaryDirectory(directory) }
            let table = RateTable(rows: scenario.rows)
            var mismatches: [String] = []
            var compared = 0
            for window in scenario.windows {
                for day in days(from: window.first, to: window.last) {
                    for currency in currencies {
                        let fromDatabase = try await database.cnbRate(currency, on: day)
                        let fromTable = table.lookup(currency, on: day)
                        compared += 1
                        if fromDatabase != fromTable {
                            mismatches.append("\(currency) \(day): database \(fromDatabase), table \(fromTable)")
                        }
                    }
                }
            }
            #expect(compared > 0, "\(scenario.name)")
            #expect(mismatches.isEmpty, "\(scenario.name): \(mismatches.prefix(5))")
        }
    }

    // MARK: The latest rate of a currency

    @Test func theLatestRateIsTheNewestOneOnOrBeforeTheDay() async throws {
        let (database, directory) = try await databaseHolding(rows([2025, 2026]))
        defer { removeTemporaryDirectory(directory) }
        let latest = storedRate(.usd, "21.622", declaredOn: "2026-10-16")

        // The Sunday after the newest declaration, the day itself, and days that have no declaration yet.
        #expect(try await database.latestCNBRate(.usd, onOrBefore: civilDate("2026-10-18")) == latest)
        #expect(try await database.latestCNBRate(.usd, onOrBefore: civilDate("2026-10-16")) == latest)
        #expect(try await database.latestCNBRate(.usd, onOrBefore: civilDate("2026-10-19")) == latest)
        #expect(try await database.latestCNBRate(.usd, onOrBefore: civilDate("2030-01-01")) == latest)
        // The day before it, and the first day of the year, which still has the last rate of the year before.
        #expect(
            try await database.latestCNBRate(.usd, onOrBefore: civilDate("2026-10-15"))
                == storedRate(.usd, "21.732", declaredOn: "2026-10-15"))
        #expect(
            try await database.latestCNBRate(.usd, onOrBefore: civilDate("2026-01-01"))
                == storedRate(.usd, "20.632", declaredOn: "2025-12-31"))
        #expect(
            try await database.latestCNBRate(.eur, onOrBefore: civilDate("2026-10-18"))
                == storedRate(.eur, "24.325", declaredOn: "2026-10-16"))
    }

    @Test func thereIsNoLatestRateBeforeTheFirstRowOrForACurrencyWithoutRows() async throws {
        let (database, directory) = try await databaseHolding(rows([2025]))
        defer { removeTemporaryDirectory(directory) }
        let unknown = try #require(CurrencyCode("XYZ"))

        #expect(try await database.latestCNBRate(.usd, onOrBefore: civilDate("2024-12-31")) == nil)
        #expect(try await database.latestCNBRate(.usd, onOrBefore: civilDate("2025-01-01")) == nil)
        #expect(try await database.latestCNBRate(.usd, onOrBefore: civilDate("2025-01-02")) != nil)
        #expect(try await database.latestCNBRate(unknown, onOrBefore: civilDate("2025-06-01")) == nil)
        // Crowns are never quoted, so there is no row for them.
        #expect(try await database.latestCNBRate(.czk, onOrBefore: civilDate("2025-06-01")) == nil)
    }

    @Test func theLatestRateKeepsTheQuotedAmount() async throws {
        let (database, directory) = try await databaseHolding(rows([2022]))
        defer { removeTemporaryDirectory(directory) }
        let ruble = try #require(CurrencyCode("RUB"))

        let latest = try #require(try await database.latestCNBRate(ruble, onOrBefore: civilDate("2022-12-31")))

        // The last day the ruble was quoted.
        #expect(latest.declaredOn == civilDate("2022-03-01"))
        #expect(latest.rate == ExchangeRate(currency: ruble, amount: 100, rate: decimal("22.877")))
    }

    // MARK: Indexes

    /// The statements of the lookup find their rows in an index, so a lookup costs the same with one year of rates
    /// and with ten.
    @Test func theLookupStatementsSearchAnIndex() async throws {
        let (database, directory) = try await databaseHolding(rows([2026]))
        defer { removeTemporaryDirectory(directory) }
        let statements: [(name: String, sql: String, arguments: [SQLValue])] = [
            ("rate of a day", CNBRateQueries.rate, [.day(civilDate("2026-10-16")), .currency(.usd)]),
            ("any rate of a day", CNBRateQueries.anyRateOnDay, [.day(civilDate("2026-10-16"))]),
            ("latest rate", CNBRateQueries.latestRate, [.currency(.usd), .day(civilDate("2026-10-16"))]),
            (
                "rates of a year", CNBRateQueries.ratesBetween,
                [.currency(.usd), .day(civilDate("2026-01-01")), .day(civilDate("2026-12-31"))]
            ),
        ]

        for statement in statements {
            let plan = try await database.read { connection in
                try connection.query("EXPLAIN QUERY PLAN " + statement.sql, statement.arguments).map { $0.text(3) }
            }
            #expect(!plan.isEmpty, "\(statement.name)")
            #expect(
                plan.allSatisfy { $0.hasPrefix("SEARCH cnb_rate USING") && $0.contains("INDEX") },
                "\(statement.name): \(plan)")
        }
    }

    // MARK: The currencies a year was paid in

    /// Stores an invoice in `code` issued on `issued` with a payment on `paid` (none when nil), converted as
    /// `conversion` says, of `status` and with a review flag when `inReview`.
    private func storePaid(
        _ number: String, _ code: String, issued: String, paid: String?, conversion: PaymentConversion = .cnbDaily,
        status: InvoiceStatus = .issued, inReview: Bool = false, in database: Database
    ) async throws {
        let currency = CurrencyCode(code)!
        var invoice = Invoice.fixture(
            number: number, currency: currency, duzp: issued, dueDate: issued, items: [.fixture("1", at: 100_000)],
            vatMode: .outsideCountry, status: status, review: inReview ? ReviewFlag(reason: "ke kontrole") : nil)
        if let paid {
            let rate = ExchangeRate(currency: currency, amount: 1, rate: 2)
            let stored: StoredRate? =
                currency.isCZK || conversion == .bankCZK ? nil : StoredRate(rate: rate, declaredOn: civilDate(paid))
            invoice.payment = Payment(
                date: civilDate(paid), conversion: currency.isCZK ? .czk : conversion, czkNetHalere: 200_000,
                czkVatHalere: 0, rate: stored, bankCZKTotalHalere: conversion == .bankCZK ? 200_000 : nil)
        }
        try await database.saveInvoice(invoice)
    }

    /// The currencies a year was paid in are those its income has to be converted from: of every payment dated in the
    /// year, whatever the state of its invoice and whatever year it was issued in, but crowns and amounts the bank
    /// credited in crowns, which need no rate.
    @Test func theCurrenciesPaidInAYearAreThoseOfItsPaymentsThatAreConvertedAtARate() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await storePaid("20260301", "USD", issued: "2026-03-01", paid: "2026-03-02", in: database)
        try await storePaid("20260302", "USD", issued: "2026-03-01", paid: "2026-04-02", in: database)
        try await storePaid(
            "20260501", "EUR", issued: "2026-05-01", paid: "2026-05-05", conversion: .bankCZK, in: database)
        try await storePaid("20260601", "GBP", issued: "2026-06-01", paid: "2026-06-01", status: .draft, in: database)
        try await storePaid("20260701", "CHF", issued: "2026-07-01", paid: "2026-07-01", inReview: true, in: database)
        try await storePaid("20251201", "HUF", issued: "2025-12-01", paid: "2026-01-02", in: database)
        try await storePaid("20261201", "JPY", issued: "2026-12-01", paid: "2027-01-04", in: database)
        try await storePaid("20260801", "PLN", issued: "2026-08-01", paid: nil, in: database)
        try await storePaid("20260901", "CZK", issued: "2026-09-01", paid: "2026-09-02", in: database)

        let codes = { (year: Int) in try await database.paidForeignCurrencies(year: year).map(\.code) }

        #expect(try await codes(2026) == ["CHF", "GBP", "HUF", "USD"])
        #expect(try await codes(2027) == ["JPY"])
        #expect(try await codes(2025) == [])
    }

    /// The statement finds the payments of the year in the index of their days, so it costs the same with one year of
    /// payments and with ten.
    @Test func theCurrenciesPaidInAYearAreFoundInAnIndex() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let year: [SQLValue] = [.day(civilDate("2026-01-01")), .day(civilDate("2026-12-31"))]

        let plan = try await database.read { connection in
            try connection.query("EXPLAIN QUERY PLAN " + UniformRateQueries.paidForeignCurrencies, year).map {
                $0.text(3)
            }
        }

        #expect(plan.contains { $0.hasPrefix("SEARCH payment USING INDEX payment_date") }, "\(plan)")
        for table in ["invoice", "payment"] {
            #expect(!plan.contains { $0.hasPrefix("SCAN \(table)") }, "\(plan)")
        }
    }
}

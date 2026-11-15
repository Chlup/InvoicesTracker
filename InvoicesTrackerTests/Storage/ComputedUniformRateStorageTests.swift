import Foundation
import Testing
@testable import InvoicesTracker

/// The uniform rate the app computes from ČNB rates: it is stored with the months it averages, only where the year has
/// no official or typed rate, and a confirmed rate replaces it. The data is invented.
struct ComputedUniformRateStorageTests {
    // MARK: Invented data

    private static func computed(
        _ currency: CurrencyCode, _ rate: String, months: Int? = 9, year: Int = 2026
    ) -> UniformRate {
        UniformRate(
            year: year, currency: currency, amount: 1, rate: decimal(rate), instruction: "", origin: .computed,
            computedMonths: months
        )
    }

    private static func other(
        _ currency: CurrencyCode, _ rate: String, origin: UniformRateOrigin, year: Int = 2026
    ) -> UniformRate {
        UniformRate(
            year: year, currency: currency, amount: 1, rate: decimal(rate), instruction: "GFŘ-D-99", origin: origin
        )
    }

    // MARK: The migration

    @Test func aVersion4DatabaseMigratesWithItsUniformRatesWithoutMonths() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileURL = directory.appending(path: "old.sqlite")
        let key = randomKey()
        let old = try SQLiteConnection(path: fileURL.path(percentEncoded: false), key: key)
        try Migrator.migrate(old, searchIndex: .plain, upTo: 4)
        #expect(try old.userVersion() == 4)
        old.close()

        let database = try Database(fileURL: fileURL, key: key)

        #expect(Schema.latestVersion == 5)
        #expect(try await database.schemaVersion() == 5)
        let rates = try await database.uniformRates(year: 2025)
        #expect(!rates.isEmpty)
        #expect(rates.allSatisfy { $0.origin == .builtIn && $0.computedMonths == nil })
    }

    // MARK: Storing a row

    @Test func aComputedRateIsStoredAndReadWithItsMonths() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let usd = Self.computed(.usd, "21.35")

        try await database.saveUniformRates([usd], year: 2026)

        #expect(try await database.uniformRates(year: 2026) == [usd])
        #expect(usd.isComputed)
        #expect(UniformRateOrigin.computed.rawValue == "computed")
    }

    @Test func aComputedRateWithoutMonthsIsRefused() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let kept = Self.other(.usd, "21.90", origin: .manual)
        try await database.saveUniformRates([kept], year: 2026)

        for months in [nil, 0, 13] {
            await #expect(throws: SQLiteError.self) {
                try await database.saveUniformRates([Self.computed(.usd, "21.35", months: months)], year: 2026)
            }
        }

        #expect(try await database.uniformRates(year: 2026) == [kept])
    }

    @Test func aRateOfAnotherOriginWithMonthsIsRefused() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let kept = Self.other(.usd, "21.90", origin: .manual)
        try await database.saveUniformRates([kept], year: 2026)
        var withMonths = Self.other(.usd, "21.35", origin: .fetched)
        withMonths.computedMonths = 9

        await #expect(throws: SQLiteError.self) {
            try await database.saveUniformRates([withMonths], year: 2026)
        }

        #expect(try await database.uniformRates(year: 2026) == [kept])
    }

    // MARK: Storing the computed rates

    @Test(arguments: [UniformRateOrigin.manual, .fetched])
    func computedRatesAreNotStoredOverAnOfficialOrTypedRate(origin: UniformRateOrigin) async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let official = Self.other(.usd, "21.90", origin: origin)
        try await database.saveUniformRates([official], year: 2026)

        let change = try await database.storeComputedUniformRates([Self.computed(.usd, "21.35")], year: 2026)

        #expect(change == .notStored)
        #expect(try await database.uniformRates(year: 2026) == [official])
    }

    @Test func computedRatesAreStoredInAYearWithNoRates() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let rates = [Self.computed(.eur, "24.60"), Self.computed(.usd, "21.35")]

        let change = try await database.storeComputedUniformRates(rates, year: 2026)

        #expect(change == .changed(before: [], after: rates))
        #expect(try await database.uniformRates(year: 2026) == rates)
    }

    @Test func storingTheSameComputedRatesAgainChangesNothing() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let rates = [Self.computed(.eur, "24.60"), Self.computed(.usd, "21.35")]
        _ = try await database.storeComputedUniformRates(rates, year: 2026)

        let change = try await database.storeComputedUniformRates(rates, year: 2026)

        #expect(change == .unchanged)
        #expect(try await database.uniformRates(year: 2026) == rates)
    }

    @Test func storingNewComputedRatesReportsTheRowsBeforeAndAfter() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let nine = [Self.computed(.eur, "24.60", months: 9), Self.computed(.usd, "21.35", months: 9)]
        let ten = [Self.computed(.eur, "24.55", months: 10), Self.computed(.usd, "21.40", months: 10)]
        _ = try await database.storeComputedUniformRates(nine, year: 2026)

        let change = try await database.storeComputedUniformRates(ten, year: 2026)

        #expect(change == .changed(before: nine, after: ten))
        #expect(try await database.uniformRates(year: 2026) == ten)
    }

    @Test func storingNoComputedRatesDeletesThem() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let rates = [Self.computed(.eur, "24.60"), Self.computed(.usd, "21.35")]
        _ = try await database.storeComputedUniformRates(rates, year: 2026)

        let change = try await database.storeComputedUniformRates([], year: 2026)

        #expect(change == .changed(before: rates, after: []))
        #expect(try await database.uniformRates(year: 2026).isEmpty)
    }

    // MARK: Storing the confirmed rates

    @Test func confirmedRatesReplaceComputedOnesAndReturnThem() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let rates = [Self.computed(.eur, "24.60"), Self.computed(.usd, "21.35")]
        _ = try await database.storeComputedUniformRates(rates, year: 2026)
        let fetched = [Self.other(.eur, "24.50", origin: .fetched), Self.other(.usd, "21.30", origin: .fetched)]

        let replaced = try await database.storeUniformRatesIfNone(fetched, year: 2026)

        #expect(replaced == rates)
        #expect(try await database.uniformRates(year: 2026) == fetched)
    }

    @Test func confirmedRatesInAYearWithNoRatesReplaceNothing() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let fetched = [Self.other(.usd, "21.30", origin: .fetched)]

        let replaced = try await database.storeUniformRatesIfNone(fetched, year: 2026)

        #expect(replaced == [])
        #expect(try await database.uniformRates(year: 2026) == fetched)
    }

    @Test func confirmedRatesAreNotStoredOverTypedOnes() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let typed = Self.other(.usd, "21.90", origin: .manual)
        try await database.saveUniformRates([typed], year: 2026)

        let replaced = try await database.storeUniformRatesIfNone(
            [Self.other(.usd, "21.30", origin: .fetched)], year: 2026)

        #expect(replaced == nil)
        #expect(try await database.uniformRates(year: 2026) == [typed])
    }
}

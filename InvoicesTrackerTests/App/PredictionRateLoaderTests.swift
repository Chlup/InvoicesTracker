import Foundation
import Testing
@testable import InvoicesTracker

/// Daily prediction conversions use the repository rule and share historical retrieval across screen reloads.
@MainActor
struct PredictionRateLoaderTests {
    /// Builds a requested currency/day slot without changing the original invoice date.
    private func key(_ currency: CurrencyCode, _ day: String) -> PredictionRateKey {
        PredictionRateKey(currency: currency, day: civilDate(day))
    }

    /// A stored declaration with an invented rate, independent of yearly fixture values.
    private func row(_ day: String, _ currency: CurrencyCode = .usd, rate: Decimal = 20) -> CNBRateRow {
        CNBRateRow(declaredOn: civilDate(day), currency: currency, amount: 1, rate: rate)
    }

    /// Exact days, weekends, holidays and the January boundary retain their valid declaration, while holes fail closed.
    @Test func historicalKeysUseTheirValidDeclaration() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let loader = PredictionRateLoader()
        let keys: Set = [key(.usd, "2026-10-12"), key(.usd, "2026-10-17"), key(.usd, "2026-01-01"),
                         key(.usd, "2026-10-14"), key(.usd, "2026-09-01")]
        var fetched: [[Int]] = []
        let rates = try await loader.load(keys: keys, database: database, today: civilDate("2026-10-28")) { years in
            fetched.append(years)
            if years == [2025] {
                try! await database.insertCNBRates([row("2025-12-31", rate: 19)])
            } else {
                try! await database.insertCNBRates([
                    row("2026-10-12", rate: 21), row("2026-10-13", rate: 22),
                    row("2026-10-15", rate: 23), row("2026-10-16", rate: 24),
                ])
            }
            return true
        }
        #expect(rates[key(.usd, "2026-10-12")] == storedRate("USD", "21", declaredOn: "2026-10-12"))
        #expect(rates[key(.usd, "2026-10-17")] == storedRate("USD", "24", declaredOn: "2026-10-16"))
        #expect(rates[key(.usd, "2026-01-01")] == storedRate("USD", "19", declaredOn: "2025-12-31"))
        #expect(rates[key(.usd, "2026-10-14")] == storedRate("USD", "22", declaredOn: "2026-10-13"))
        #expect(rates[key(.usd, "2026-09-01")] == nil)
        #expect(fetched.sorted { $0[0] < $1[0] } == [[2025], [2026]])
    }

    /// A later exact cached declaration cannot leak into an invoice whose future day is capped at real today.
    @Test func futureKeysCannotUseCachedFutureRates() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.insertCNBRates([row("2026-10-27", rate: 21), row("2026-11-02", rate: 99)])
        let future = key(.usd, "2026-11-02")
        let rates = try await PredictionRateLoader().load(
            keys: [future], database: database, today: civilDate("2026-10-28"), fetchYears: { _ in false })
        #expect(rates[future] == storedRate("USD", "21", declaredOn: "2026-10-27"))
    }

    /// Today's unpublished declaration can provisionally use the newest earlier row, unless the currency is unquoted.
    @Test func todayCanUseAProvisionalRate() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.insertCNBRates([row("2026-10-27", rate: 21)])
        let today = key(.usd, "2026-10-29")
        let loader = PredictionRateLoader()
        let rates = try await loader.load(
            keys: [today], database: database, today: today.day, fetchYears: { _ in false })
        #expect(rates[today] == storedRate("USD", "21", declaredOn: "2026-10-27"))
        try await database.insertCNBRates([row("2026-10-29", .eur)])
        let unavailable = try await loader.load(
            keys: [today], database: database, today: today.day, fetchYears: { _ in false })
        #expect(unavailable[today] == nil)
    }

    /// A reload raised by storage during a fetch joins the original retrieval instead of fetching the year again.
    @Test func concurrentLoadsShareHistoricalFetches() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let loader = PredictionRateLoader()
        let requested = key(.usd, "2026-09-01")
        let gate = Gate()
        var calls = 0
        var reload: Task<[PredictionRateKey: StoredRate], Error>?
        var reloadStarted = false
        let fetch: @MainActor ([Int]) async -> Bool = { years in
            #expect(years == [2026])
            calls += 1
            if calls == 1 {
                reload = Task { @MainActor in
                    reloadStarted = true
                    return try await loader.load(
                        keys: [requested], database: database, today: civilDate("2026-10-28"),
                        fetchYears: { _ in
                            calls += 1
                            return true
                        })
                }
                await gate.pass()
            }
            return true
        }
        let original = Task {
            try await loader.load(
                keys: [requested], database: database, today: civilDate("2026-10-28"), fetchYears: fetch)
        }
        await gate.untilARequestWaits()
        try await waitUntil { reloadStarted }
        // Let the database reads of the callback reload settle before the shared fetch completes.
        for _ in 0..<20 { await Task.yield() }
        await gate.open()
        #expect(try await original.value.isEmpty)
        #expect(try await #require(reload).value.isEmpty)
        #expect(calls == 1)
    }

    /// Successful incomplete years are attempted once, while every reload still sees new database rows.
    @Test func completedMissingKeysDoNotTriggerReloadLoops() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let loader = PredictionRateLoader()
        let missing = key(.usd, "2026-09-01")
        let unquoted = key(CurrencyCode("XYZ")!, "2026-10-13")
        var calls = 0
        let fetch: @MainActor ([Int]) async -> Bool = { years in
            #expect(years == [2026])
            calls += 1
            try! await database.insertCNBRates([row("2026-10-13", .eur)])
            return true
        }
        for _ in 0..<3 {
            let result = try await loader.load(
                keys: [missing, unquoted], database: database, today: civilDate("2026-10-28"), fetchYears: fetch)
            #expect(result.isEmpty)
        }
        #expect(calls == 1)
        try await database.insertCNBRates([row("2026-09-01", rate: 23)])
        let recovered = try await loader.load(
            keys: [missing], database: database, today: civilDate("2026-10-28"), fetchYears: fetch)
        #expect(recovered[missing] == storedRate("USD", "23", declaredOn: "2026-09-01"))
        #expect(calls == 1)
    }

    /// An offline attempt creates no recursive retry and leaves a subsequent independent load free to recover.
    @Test func failedFetchCanRecoverOnALaterLoad() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let loader = PredictionRateLoader()
        let requested = key(.usd, "2026-09-01")
        var calls = 0
        let fetch: @MainActor ([Int]) async -> Bool = { years in
            #expect(years == [2026])
            calls += 1
            if calls == 1 { return false }
            try! await database.insertCNBRates([row("2026-09-01", rate: 23)])
            return true
        }
        let failed = try await loader.load(
            keys: [requested], database: database, today: civilDate("2026-10-28"), fetchYears: fetch)
        #expect(failed.isEmpty)
        #expect(calls == 1)
        let recovered = try await loader.load(
            keys: [requested], database: database, today: civilDate("2026-10-28"), fetchYears: fetch)
        #expect(recovered[requested] == storedRate("USD", "23", declaredOn: "2026-09-01"))
        #expect(calls == 2)
    }

    /// Replacing the vault or moving to another real day starts fresh work and rejects the older load's publication.
    @Test(arguments: [false, true])
    func changingDatabaseOrDayCannotPublishStaleResults(changeDay: Bool) async throws {
        let (originalDatabase, originalDirectory) = try makeDatabase()
        defer { removeTemporaryDirectory(originalDirectory) }
        let (otherDatabase, otherDirectory) = try makeDatabase()
        defer { removeTemporaryDirectory(otherDirectory) }
        let database = changeDay ? originalDatabase : otherDatabase
        let today = civilDate("2026-10-28")
        let newToday = changeDay ? today.adding(days: 1) : today
        let loader = PredictionRateLoader()
        let requested = key(.usd, "2026-09-01")
        let gate = Gate()
        let original = Task {
            try await loader.load(keys: [requested], database: originalDatabase, today: today) { _ in
                await gate.pass()
                try! await originalDatabase.insertCNBRates([row("2026-09-01", rate: 21)])
                return true
            }
        }
        await gate.untilARequestWaits()
        var newCalls = 0
        let current = try await loader.load(keys: [requested], database: database, today: newToday) { _ in
            newCalls += 1
            try! await database.insertCNBRates([row("2026-09-01", rate: 25)])
            return true
        }
        #expect(current[requested] == storedRate("USD", "25", declaredOn: "2026-09-01"))
        #expect(newCalls == 1)
        await gate.open()
        await #expect(throws: CancellationError.self) { try await original.value }
    }

    /// Canceling the obsolete caller never cancels the shared operation that a current screen still needs.
    @Test func cancellingAScreenLoadKeepsTheSharedFetchUseful() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let loader = PredictionRateLoader()
        let requested = key(.usd, "2026-09-01")
        let today = civilDate("2026-10-28")
        let gate = Gate()
        var calls = 0
        var fetchWasCancelled = false
        let fetch: @MainActor ([Int]) async -> Bool = { _ in
            calls += 1
            await gate.pass()
            fetchWasCancelled = Task.isCancelled
            try! await database.insertCNBRates([row("2026-09-01", rate: 23)])
            return true
        }
        let obsolete = Task {
            try await loader.load(keys: [requested], database: database, today: today, fetchYears: fetch)
        }
        await gate.untilARequestWaits()
        let current = Task {
            try await loader.load(keys: [requested], database: database, today: today, fetchYears: fetch)
        }
        obsolete.cancel()
        for _ in 0..<20 { await Task.yield() }
        await gate.open()
        let rates = try await current.value
        #expect(rates[requested] == storedRate("USD", "23", declaredOn: "2026-09-01"))
        #expect(calls == 1)
        #expect(!fetchWasCancelled)
        await #expect(throws: CancellationError.self) { try await obsolete.value }
    }

    /// Success belongs to each one-year call, so an unavailable neighboring declaration year can retry independently.
    @Test func aFailedYearRetriesWithoutRefetchingASuccessfulNeighbor() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let loader = PredictionRateLoader()
        let requested = key(.usd, "2026-01-01")
        let today = civilDate("2026-10-28")
        var calls: [[Int]] = []
        let fetch: @MainActor ([Int]) async -> Bool = { years in
            calls.append(years)
            if years == [2025] { return false }
            try! await database.insertCNBRates([row("2026-01-02")])
            return true
        }
        #expect(try await loader.load(
            keys: [requested], database: database, today: today, fetchYears: fetch).isEmpty)
        #expect(try await loader.load(
            keys: [requested], database: database, today: today, fetchYears: fetch).isEmpty)
        #expect(calls == [[2025], [2026], [2025]])
    }

    /// The attempt cache does not keep an unlocked vault alive after its owning app releases it.
    @Test func bookkeepingDoesNotRetainAnObsoleteDatabase() async throws {
        let loader = PredictionRateLoader()
        var database: Database?
        let directory: URL
        (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        weak let observed = database
        _ = try await loader.load(
            keys: [], database: try #require(database), today: civilDate("2026-10-28"), fetchYears: { _ in false })
        database = nil
        #expect(observed == nil)
    }

    /// Callers already loading when an offline attempt finishes share that failure, while a later load can retry.
    @Test func concurrentFailedLoadsShareOneAttemptBeforeAnIndependentRetry() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let loader = PredictionRateLoader()
        let requested = key(.usd, "2026-09-01")
        let today = civilDate("2026-10-28")
        let gate = Gate()
        var calls = 0
        let fetch: @MainActor ([Int]) async -> Bool = { _ in
            calls += 1
            if calls == 1 {
                await gate.pass()
                return false
            }
            return false
        }
        let first = Task {
            try await loader.load(keys: [requested], database: database, today: today, fetchYears: fetch)
        }
        await gate.untilARequestWaits()
        var secondStarted = false
        let second = Task {
            secondStarted = true
            let keys = Set((0..<100).map {
                PredictionRateKey(currency: .usd, day: requested.day.adding(days: -$0))
            })
            return try await loader.load(keys: keys, database: database, today: today, fetchYears: fetch)
        }
        try await waitUntil { secondStarted }
        await gate.open()
        #expect(try await first.value.isEmpty)
        #expect(try await second.value.isEmpty)
        #expect(calls == 1)
        #expect(try await loader.load(
            keys: [requested], database: database, today: today, fetchYears: fetch).isEmpty)
        #expect(calls == 2)
    }
}

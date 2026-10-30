import Foundation
import Testing
@testable import InvoicesTracker

/// Both screens preserve their prior presentation when a shared historical lookup is canceled.
@Suite(.settlesBackups)
@MainActor
struct PredictionPresentationReloadTests {
    /// Cancellation during historical retrieval preserves either the displayed data or an existing load error.
    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)], [false, true])
    func canceledSharedLookupPreservesBothScreens(_ state: (Bool, Bool), isOverview: Bool) async throws {
        let (startsWithError, changesDay) = state
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        let app = makeAppModel(in: directory, http: GatedHTTPClient(base: StubHTTPClient(), gate: gate))
        let prediction = PredictionModel(app: app)
        let overview = OverviewModel(app: app)
        if startsWithError {
            await prediction.load()
            await overview.load()
        }
        try await startFresh(app)
        try await PredictionSample.store(in: app)
        if !startsWithError {
            await prediction.load()
            await overview.load()
        }
        let beforePage = prediction.page
        let beforeData = overview.data
        let beforePredictionError = prediction.errorText
        let beforeOverviewError = overview.errorText
        let database = try #require(app.database)
        try await database.execute("DELETE FROM cnb_rate")
        let load = Task {
            if isOverview { await overview.load() } else { await prediction.load() }
        }
        await gate.untilARequestWaits()
        if changesDay {
            app.handleDayChanged(civilDate("2026-10-18"))
        } else {
            load.cancel()
        }
        await gate.open()
        await load.value
        #expect(prediction.page == beforePage)
        #expect(overview.data == beforeData)
        #expect(prediction.errorText == beforePredictionError)
        #expect(overview.errorText == beforeOverviewError)
    }

    /// Reopening and changing a historical rate recompute the shared outcome without rewriting invoice payments.
    @Test func bothScreensRecomputeFromFreshHistoricalRatesAndInvoiceData() async throws {
        try await PredictionSample.withStoredSample { app in
            let database = try #require(app.database)
            let invoicesBefore = try await database.predictionInvoices(year: 2026)
            let first = PredictionModel(app: app)
            let overview = OverviewModel(app: app)
            await first.load()
            await overview.load()
            #expect(first.page?.incomeTotal == "2\u{00A0}743\u{00A0}157\u{00A0}Kč")
            try await database.insertCNBRates([
                CNBRateRow(declaredOn: civilDate("2026-07-07"), currency: .usd, amount: 1, rate: 30)
            ])
            let reopened = PredictionModel(app: app)
            await reopened.load()
            await overview.load()
            #expect(reopened.page?.incomeTotal == "2\u{00A0}773\u{00A0}855\u{00A0}Kč")
            #expect(overview.data?.prediction?.stats[0].value == "≈\u{00A0}2\u{00A0}773\u{00A0}855\u{00A0}Kč")
            #expect(reopened.page?.activeRows[0].how.contains("316\u{00A0}391\u{00A0}Kč") == true)
            #expect(try await database.predictionInvoices(year: 2026) == invoicesBefore)
            var invoice = try #require(invoicesBefore.first { $0.number == "20260601" })
            invoice.items[0].unitPriceMinor = 9_000
            try await database.saveInvoice(invoice)
            await app.didWriteAndBackUp()
            await reopened.load()
            await overview.load()
            #expect(reopened.page?.activeRows[0].how.contains("345\u{00A0}791\u{00A0}Kč") == true)
            let outcome = try await app.predictionOutcome(year: 2026)
            #expect(reopened.page == PredictionBuilder.page(outcome))
            var card = try #require(overview.data?.prediction)
            card.chart = []
            #expect(card == PredictionBuilder.card(outcome))
        }
    }

    /// A callback reload joins a pending historical lookup and only the newest screen loads publish its result.
    @Test func aSharedFetchFinishingDuringReloadPublishesTheFreshOutcomeOnBothScreens() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        let yearly = Data("Datum|1 USD\n07.07.2026|30\n07.08.2026|20,870\n09.09.2026|21,010\n"
            .appending("02.10.2026|21,305\n16.10.2026|21,320\n").utf8)
        let app = makeAppModel(
            in: directory, http: GatedHTTPClient(
                base: StubHTTPClient([CNBEndpoints.yearly(2026): yearly]), gate: gate))
        try await startFresh(app)
        try await PredictionSample.store(in: app)
        let database = try #require(app.database)
        try await database.execute("DELETE FROM cnb_rate WHERE substr(declared_on, 1, 4) = '2026'")
        let prediction = PredictionModel(app: app)
        let overview = OverviewModel(app: app)
        let older = Task { await prediction.load() }
        await gate.untilARequestWaits()
        let newer = Task { await prediction.load() }
        let overviewLoad = Task { await overview.load() }
        await gate.open()
        await older.value
        await newer.value
        await overviewLoad.value
        #expect(prediction.errorText == nil)
        #expect(overview.errorText == nil)
        #expect(prediction.page?.incomeTotal == "2\u{00A0}773\u{00A0}855\u{00A0}Kč")
        #expect(overview.data?.prediction?.stats[0].value == "≈\u{00A0}2\u{00A0}773\u{00A0}855\u{00A0}Kč")
    }
}

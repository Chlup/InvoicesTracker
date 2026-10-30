import Foundation
import Testing
@testable import InvoicesTracker

/// A day of the prediction and the day of the rates it names when it uses no ČNB rate: the day itself, or on a weekend
/// the Friday before it. Saturday 17. 10. 2026, Sunday 18. 10. and Monday 19. 10.
private let daysOfTheRatesWithoutRates: [(String, String)] = [
    ("2026-10-17", "2026-10-16"), ("2026-10-18", "2026-10-16"), ("2026-10-19", "2026-10-19"),
]

/// The prediction of a year loaded from the data of an app model: the clients, the issued invoices of every year and
/// the drafts of the year, the templates, the person's choices of months, the year's receipts, and the rates that turn
/// the amounts expected in other currencies into crowns. The data is the prediction sample stored in a temporary
/// database, with the app as of Saturday 17. 10. 2026. The incomes, the levies and what is owed are those of the same
/// sample in `PredictionGoldenTests`, which were worked out by a separate implementation.
@Suite(.settlesBackups)
@MainActor
struct AppModelPredictionTests {
    // MARK: Helpers

    /// Runs `body` with an app model on a new folder, its clock at noon of 17. 10. 2026 unless given, and the sample
    /// stored in its data.
    private func withSample(
        clock: ManualClock = ManualClock(localNoon(2026, 10, 17)), _ body: (AppModel) async throws -> Void
    ) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory, clock: clock)
        try await startFresh(app)
        try await PredictionSample.store(in: app)
        try await body(app)
    }

    /// Checks the income of `outcome` in haléře, which the prediction and the engine count alike, its levies in whole
    /// Kč (the net tax and the two insurances), and what is owed with the returns.
    private func expectFigures(
        _ outcome: PredictionOutcome, income: Int64, tax: Int64, social: Int64, health: Int64, owed: Int64,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(outcome.prediction.incomeHalere == income, "income", sourceLocation: sourceLocation)
        #expect(outcome.result.incomeHalere == income, "the engine's income", sourceLocation: sourceLocation)
        #expect(outcome.result.netTax == tax, "tax", sourceLocation: sourceLocation)
        #expect(outcome.result.social.insurance == social, "social insurance", sourceLocation: sourceLocation)
        #expect(outcome.result.health.insurance == health, "health insurance", sourceLocation: sourceLocation)
        #expect(outcome.owedTotal == owed, "owed with the returns", sourceLocation: sourceLocation)
    }

    /// Runs `body` with an app model on a new folder, its clock at noon of `today` (`YYYY-MM-DD`), and `client` as the
    /// only thing stored in its data.
    private func withClient(
        _ client: Client, on today: String, _ body: (AppModel) async throws -> Void
    ) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory, clock: ManualClock(noon(of: today)))
        try await startFresh(app)
        let database = try #require(app.database)
        try await database.saveClient(client)
        try await body(app)
    }

    /// Stores an invoice of 4 500,00 Kč for Sierra issued on `issued` (`YYYY-MM-DD`) and due the same day, and returns
    /// its id.
    @discardableResult
    private func storeInvoice(
        _ number: String, issued: String, status: InvoiceStatus = .issued, review: ReviewFlag? = nil,
        payment: Payment? = nil, in database: Database
    ) async throws -> Int64 {
        var invoice = Invoice.fixture(
            number: number, issued: issued, duzp: issued, dueDate: issued, status: status, review: review,
            payment: payment)
        invoice.clientID = PredictionSample.sierra.id
        return try await database.saveInvoice(invoice)
    }

    /// Deletes every ČNB rate stored, as a cache that has none yet.
    private nonisolated func deleteCNBRates(in database: Database) async throws {
        try await database.write { connection in
            try connection.run("DELETE FROM cnb_rate")
        }
    }

    private func row(_ id: Int64, in prediction: IncomePrediction) throws -> ClientPrediction {
        try #require(prediction.clients.first { $0.id == id }, "No client \(id)")
    }

    /// Noon of `day` in the Mac's time zone, which an app model of the tests takes as its clock.
    private func noon(of day: String) -> Date {
        let date = civilDate(day)
        return localNoon(date.year, date.month, date.day)
    }

    /// Daily payment-day FX trains the mean while stored bank and uniform receipts remain authoritative income.
    @Test(arguments: [PaymentConversion.bankCZK, PaymentConversion.uniform])
    func annualMeanDoesNotReplaceStoredPaymentConversion(_ conversion: PaymentConversion) async throws {
        try await withClient(PredictionSample.foxtrot, on: "2026-10-17") { app in
            let database = try #require(app.database)
            var invoice = Invoice.fixture(
                number: "DAILY", currency: .usd, issued: "2026-09-30", duzp: "2026-09-30",
                dueDate: "2026-10-30", items: [.fixture("1", at: 10_000)], vatMode: .none,
                payment: Payment(
                    date: civilDate("2026-10-02"), conversion: conversion, czkNetHalere: 123_456,
                    czkVatHalere: 0, rate: storedRate("USD", "12.3456", declaredOn: "2026-10-02")))
            invoice.clientID = 1
            try await database.saveInvoice(invoice)
            try await database.insertCNBRates([
                CNBRateRow(declaredOn: civilDate("2026-10-02"), currency: .usd, amount: 1, rate: 20),
                CNBRateRow(declaredOn: civilDate("2026-10-16"), currency: .usd, amount: 1, rate: 30),
            ])
            try await database.setExpectedInvoiceMonth(year: 2026, clientID: 1, month: 11, expected: true)
            let outcome = try await app.predictionOutcome(year: 2026)
            let client = try row(1, in: outcome.prediction)
            #expect(client.averageSampleCount == 1)
            #expect(client.nextAmountHalere == 200_000)
            #expect(client.months[10].amountHalere == 200_000)
            #expect(outcome.prediction.receivedHalere == 123_456)
            #expect(outcome.result.incomeHalere == 323_456)
            #expect(outcome.input.receipts.first { $0.source != .synthetic }?.czkNetHalere == 123_456)
        }
    }

    /// The original future issue key resolves at real today, even if a later daily declaration is already cached.
    @Test func aFutureIssueTrainsWithTodaysRateWithoutChangingItsKey() async throws {
        try await withClient(PredictionSample.foxtrot, on: "2026-10-17") { app in
            let database = try #require(app.database)
            var invoice = Invoice.fixture(
                number: "FUTURE", currency: .usd, issued: "2026-11-02", duzp: "2026-11-02",
                dueDate: "2026-12-02", items: [.fixture("1", at: 10_000)], vatMode: .none)
            invoice.clientID = 1
            try await database.saveInvoice(invoice)
            try await database.insertCNBRates([
                CNBRateRow(declaredOn: civilDate("2026-10-16"), currency: .usd, amount: 1, rate: 20),
                CNBRateRow(declaredOn: civilDate("2026-11-02"), currency: .usd, amount: 1, rate: 99),
            ])
            let outcome = try await app.predictionOutcome(year: 2026)
            #expect(try row(1, in: outcome.prediction).nextAmountHalere == 200_000)
            #expect(try row(1, in: outcome.prediction).averageSampleCount == 1)
        }
    }

    /// A rate fetch from an earlier real day or locked vault cannot publish its captured prediction afterward.
    @Test(arguments: [false, true])
    func aScopeChangeDuringHistoricalFetchCancelsTheOldPrediction(lockVault: Bool) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        let app = makeAppModel(
            in: directory, http: GatedHTTPClient(base: StubHTTPClient(), gate: gate))
        try await startFresh(app)
        let database = try #require(app.database)
        let clientID = try await database.saveClient(Client(name: "Alfa", currency: .usd))
        var invoice = Invoice.fixture(
            number: "SCOPE", currency: .usd, issued: "2026-09-30", duzp: "2026-09-30", dueDate: "2026-10-30",
            items: [.fixture("1", at: 10_000)], vatMode: .none,
            payment: Payment.fixture(on: "2026-10-02", net: 200_000, vat: 0))
        invoice.clientID = clientID
        try await database.saveInvoice(invoice)
        let load = Task { try await app.predictionOutcome(year: 2026) }
        await gate.untilARequestWaits()
        if lockVault {
            app.lockAfterFailedChange(
                .newCode(number: 2, created: civilDate("2026-10-17"), replacedLabel: nil, replacedNumber: nil))
        } else {
            app.handleDayChanged(civilDate("2026-10-18"))
        }
        await gate.open()
        await #expect(throws: CancellationError.self) { try await load.value }
    }

    /// A historical fetch also refreshes ordinary draft/waiting quotes in the very same returned outcome.
    @Test func historicalFetchRefreshesForecastRatesBeforeReturning() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let yearly = Data("Datum|1 USD\n02.10.2026|20\n12.10.2026|25\n16.10.2026|30\n".utf8)
        let app = makeAppModel(in: directory, http: StubHTTPClient([CNBEndpoints.yearly(2026): yearly]))
        try await startFresh(app)
        let database = try #require(app.database)
        let clientID = try await database.saveClient(Client(name: "Alfa", currency: .usd))
        var paid = Invoice.fixture(
            number: "FETCH-1", currency: .usd, issued: "2026-09-30", duzp: "2026-09-30",
            dueDate: "2026-10-14", items: [.fixture("1", at: 10_000)], vatMode: .none,
            payment: Payment(
                date: civilDate("2026-10-02"), conversion: .bankCZK, czkNetHalere: 111_111,
                czkVatHalere: 0, rate: nil))
        paid.clientID = clientID
        var waiting = Invoice.fixture(
            number: "FETCH-2", currency: .usd, issued: "2026-10-12", duzp: "2026-10-12",
            dueDate: "2026-10-26", items: [.fixture("1", at: 10_000)], vatMode: .none)
        waiting.clientID = clientID
        var draft = Invoice.fixture(
            number: "FETCH-3", currency: .usd, issued: "2026-11-01", duzp: "2026-11-01",
            dueDate: "2026-11-15", items: [.fixture("1", at: 10_000)], vatMode: .none, status: .draft)
        draft.clientID = clientID
        for invoice in [paid, waiting, draft] {
            try await database.saveInvoice(invoice)
        }
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2026-10-15"), currency: .usd, amount: 1, rate: 10)
        ])
        let outcome = try await app.predictionOutcome(year: 2026)
        let client = try row(clientID, in: outcome.prediction)
        #expect(client.nextAmountHalere == 225_000)
        #expect(client.months[10].amountHalere == 300_000)
        #expect(outcome.prediction.waitingHalere == 300_000)
        #expect(outcome.prediction.rateDay == civilDate("2026-10-16"))
        #expect(outcome.prediction.receivedHalere == 111_111)
        #expect(outcome.prediction.incomeHalere == 711_111)
        #expect(outcome.prediction.isComplete)
    }

    // MARK: The sample

    /// Stored and in-memory inputs produce the same independent annual prediction: 2 743 156,99 Kč of income,
    /// tax 114 786 Kč, social 247 832 Kč, health 104 164 Kč, and 198 702 Kč owed after advances.
    @Test func theStoredSampleGivesTheGoldenPrediction() async throws {
        try await withSample { app in
            let outcome = try await app.predictionOutcome(year: 2026)

            expectFigures(outcome, income: 274_315_699, tax: 114_786, social: 247_832, health: 104_164, owed: 198_702)
            #expect(outcome.overpaidTotal == 0)
            #expect(outcome.prediction.now == civilDate("2026-10-17"))
            #expect(!outcome.prediction.isClosed)
            #expect(!outcome.prediction.usesUniformRate)
            #expect(outcome.prediction.rateDay == civilDate("2026-10-16"))
            #expect(outcome.prediction.receivedHalere == 219_177_135)
            #expect(outcome.prediction.receivedCount == 11)
            #expect(outcome.prediction.expectedHalere == 55_138_564)
            #expect(outcome.prediction.nextYearHalere == 29_019_284)
            #expect(outcome.prediction.clients.map(\.name) == ["Foxtrot, Inc.", "Tango s.r.o.", "Sierra, SE"])

            let sample = try PredictionOutcome.make(
                prediction: IncomePrediction.make(PredictionSample.input(year: 2026)),
                yearInput: PredictionSample.yearInput(year: 2026))
            #expect(outcome.prediction == sample.prediction)
            #expect(outcome.result == sample.result)
        }
    }

    /// The prediction is made from today's data, so moving "K datu" within the year changes nothing.
    @Test func thePredictionDoesNotDependOnKDatu() async throws {
        try await withSample { app in
            let atToday = try await app.predictionOutcome(year: 2026)

            app.pickAsOf(civilDate("2026-07-15"))
            let atJuly = try await app.predictionOutcome(year: 2026)

            #expect(app.asOf.asOf == civilDate("2026-07-15"))
            #expect(app.today == civilDate("2026-10-17"))
            #expect(atJuly == atToday)
            #expect(atJuly.prediction.now == civilDate("2026-10-17"))
        }
    }

    /// The choices of months stored for the year: Foxtrot's November switched off, and Sierra's November and December
    /// on. Sierra's 208 000 Kč of November count, its December's are paid in January.
    @Test func aStoredMonthChangeMovesThePrediction() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            try await database.setExpectedInvoiceMonth(
                year: 2026, clientID: PredictionSample.foxtrot.id, month: 11, expected: false)
            for month in [11, 12] {
                try await database.setExpectedInvoiceMonth(
                    year: 2026, clientID: PredictionSample.sierra.id, month: month, expected: true)
            }

            let outcome = try await app.predictionOutcome(year: 2026)

            expectFigures(outcome, income: 266_546_415, tax: 103_131, social: 235_354, health: 98_919, owed: 169_324)
            #expect(outcome.prediction.nextYearHalere == 49_819_284)
            let foxtrot = try row(PredictionSample.foxtrot.id, in: outcome.prediction)
            #expect(foxtrot.months[10].kind == .notExpected)
            #expect(foxtrot.isEdited)
            let sierra = try row(PredictionSample.sierra.id, in: outcome.prediction)
            #expect(sierra.months[10...].map(\.kind) == [.expected, .expectedNextYear])
            #expect(sierra.isActive)
        }
    }

    /// A past year is predicted as of its last day, whatever today is: nothing is expected, and the figures are final.
    /// 2025 has 2 931 159,89 Kč from 16 payments. Its latest cached daily declaration is 9. 12. 2025.
    @Test func aPastYearIsComputedAsOfItsLastDay() async throws {
        try await withSample { app in
            let outcome = try await app.predictionOutcome(year: 2025)

            #expect(outcome.prediction.isClosed)
            #expect(outcome.prediction.now == civilDate("2025-12-31"))
            #expect(outcome.result.asOf == civilDate("2025-12-31"))
            expectFigures(outcome, income: 293_115_989, tax: 142_986, social: 278_025, health: 116_854, owed: 330_065)
            #expect(outcome.overpaidTotal == 0)
            #expect(outcome.prediction.receivedCount == 16)
            #expect(outcome.prediction.expectedHalere == 0)
            #expect(outcome.prediction.waitingHalere == 0)
            #expect(outcome.prediction.syntheticReceipts.isEmpty)
            #expect(outcome.prediction.rateDay == civilDate("2025-12-09"))
        }
    }

    /// 2024: Sierra's December invoice is paid on 5. 1. 2025, so the 207 500,00 Kč are not the year's money but the
    /// next year's, though the invoice is loaded with its payment.
    @Test func aPaymentAfterTheEndOfAPastYearIsMoneyOfTheNextYear() async throws {
        try await withSample { app in
            let outcome = try await app.predictionOutcome(year: 2024)

            expectFigures(outcome, income: 237_250_000, tax: 73_056, social: 188_304, health: 79_144, owed: 152_704)
            #expect(outcome.prediction.receivedCount == 11)
            #expect(outcome.prediction.nextYearHalere == 20_750_000)
            #expect(outcome.prediction.syntheticReceipts.isEmpty)
        }
    }

    // MARK: What counts

    /// The prediction and the engine are given the receipts of the year from the same rows, so they agree on the money
    /// received, and the money of an income adjustment dated by today is in both. Adjustments of −50 000 Kč on
    /// 10. 3. 2026 and of +100 000 Kč on 10. 11. 2026: only the first is dated by today. It is among the money
    /// received, though not one of the 11 payments.
    @Test func incomeAdjustmentsCountAsMoneyReceivedUpToToday() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            try await database.saveAdjustment(
                IncomeAdjustment(date: civilDate("2026-03-10"), amountHalere: -5_000_000, description: "Dobropis"))
            try await database.saveAdjustment(
                IncomeAdjustment(date: civilDate("2026-11-10"), amountHalere: 10_000_000, description: "Mimo faktury"))

            let outcome = try await app.predictionOutcome(year: 2026)

            expectFigures(outcome, income: 269_315_699, tax: 107_286, social: 239_802, health: 100_789, owed: 179_797)
            #expect(outcome.prediction.receivedHalere == 214_177_135)
            #expect(outcome.prediction.receivedCount == 11)
            #expect(outcome.prediction.includesAdjustments)
        }
    }

    /// An invoice in review is not income until it is resolved: neither one unpaid, which would be expected to be
    /// paid, nor one paid, which would be money received, changes the prediction or the levies.
    @Test func anInvoiceInReviewCountsNowhere() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            let before = try await app.predictionOutcome(year: 2026)

            let review = ReviewFlag(reason: "Zrušeno ve Fakturoidu")
            try await storeInvoice("20260990", issued: "2026-09-30", review: review, in: database)
            try await storeInvoice(
                "20260991", issued: "2026-09-30", review: review, payment: Payment.fixture(on: "2026-10-01"),
                in: database)
            let after = try await app.predictionOutcome(year: 2026)

            #expect(after == before)
            #expect(after.prediction.receivedCount == 11)
        }
    }

    // MARK: Rates

    /// The year converts its income at the uniform rate of 21,500 Kč for a dollar: the invoices expected in dollars
    /// are converted at it too, Foxtrot's October draft (12 040,00 USD) and its November (16 000,00 USD).
    @Test func theUniformRateOfTheYearConvertsTheExpectedInvoices() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
            try await database.saveUniformRates(
                [
                    UniformRate(
                        year: 2026, currency: .usd, amount: 1, rate: decimal("21.5"), instruction: "", sourceURL: nil,
                        confirmedAt: nil, origin: .manual)
                ], year: 2026)

            let outcome = try await app.predictionOutcome(year: 2026)

            let foxtrot = try row(PredictionSample.foxtrot.id, in: outcome.prediction)
            #expect(foxtrot.months[9...].map(\.amountHalere) == [25_886_000, 28_569_284, 28_569_284])
            #expect(outcome.prediction.usesUniformRate)
            #expect(outcome.prediction.rateDay == nil)
            // Stored receipts remain 2 191 771,35 Kč. Only the draft uses the uniform rate; the annual mean stays
            // daily-CZK, so expected income adds 640 627,80 Kč of Foxtrot and 9 000 Kč of Tango.
            #expect(outcome.prediction.receivedHalere == 219_177_135)
            #expect(outcome.prediction.incomeHalere == 274_532_419)
            #expect(outcome.result.incomeHalere == 274_532_419)
        }
    }

    /// The uniform rate is chosen for 2026, but the year does not have it yet: it converts at the ČNB rates, and so
    /// does the prediction, whose rate is the dollar's of 16. 10. 2026.
    @Test func aUniformRateThatTheYearDoesNotHaveYetIsNotUsed() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            let before = try await app.predictionOutcome(year: 2026)

            try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
            let after = try await app.predictionOutcome(year: 2026)

            #expect(!after.prediction.usesUniformRate)
            #expect(after.prediction.rateDay == civilDate("2026-10-16"))
            #expect(after == before)
        }
    }

    /// Without a ČNB rate for the dollar (and no uniform rate), Foxtrot's expected invoices have an unknown amount: its
    /// months are still expected, but they add nothing, and the day of the rates is the Friday before today, which is a
    /// Saturday. Tango, in crowns, is not affected.
    @Test func anExpectedInvoiceInACurrencyWithoutARateHasAnUnknownAmount() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            try await deleteCNBRates(in: database)

            let outcome = try await app.predictionOutcome(year: 2026)

            let foxtrot = try row(PredictionSample.foxtrot.id, in: outcome.prediction)
            #expect(foxtrot.months[9...].map(\.kind) == [.expected, .expected, .expectedNextYear])
            #expect(foxtrot.months[9...].map(\.amountHalere) == [0, 0, 0])
            #expect(outcome.prediction.expectedHalere == 900_000)
            #expect(outcome.prediction.incomeHalere == 220_077_135)
            #expect(outcome.result.incomeHalere == 220_077_135)
            #expect(!outcome.prediction.usesUniformRate)
            #expect(outcome.prediction.rateDay == civilDate("2026-10-16"))
        }
    }

    /// Each currency of the clients and the invoices has its own latest rate, and the prediction names the newest day
    /// of them. Pounds declared on Friday 16. 10., euros on Wednesday 14. 10. and dollars on Thursday 15. 10.: the
    /// newest is neither the first nor the last of them by their codes (EUR, GBP, USD).
    @Test func theNewestDeclarationOfTheCurrenciesNamesTheDayOfTheRates() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            let pound = try #require(CurrencyCode("GBP"))
            try await database.saveClient(Client(name: "Euro s.r.o.", currency: .eur))
            try await database.saveClient(Client(name: "Pound Ltd.", currency: pound))
            try await deleteCNBRates(in: database)
            try await database.insertCNBRates([
                CNBRateRow(declaredOn: civilDate("2026-10-14"), currency: .eur, amount: 1, rate: decimal("24.3")),
                CNBRateRow(declaredOn: civilDate("2026-10-16"), currency: pound, amount: 1, rate: decimal("28.1")),
                CNBRateRow(declaredOn: civilDate("2026-10-15"), currency: .usd, amount: 1, rate: decimal("21.3")),
            ])

            let outcome = try await app.predictionOutcome(year: 2026)

            #expect(outcome.prediction.rateDay == civilDate("2026-10-16"))
            // A latest dollar quote does not repair missing historical daily conversions for the annual mean.
            let foxtrot = try row(PredictionSample.foxtrot.id, in: outcome.prediction)
            #expect(foxtrot.months[10].hasUnknownAmount)
            #expect(foxtrot.nextAmountHalere == nil)
            #expect(!outcome.prediction.isComplete)
        }
    }

    /// With no currency other than crowns, no amount needs a rate, and the day of the rates the page names is the day
    /// of the prediction, or the Friday before it on a weekend.
    @Test(arguments: daysOfTheRatesWithoutRates)
    func withoutForeignCurrenciesTheDayOfTheRatesIsTheLastWeekday(today: String, rateDay: String) async throws {
        try await withClient(PredictionSample.tango, on: today) { app in
            let outcome = try await app.predictionOutcome(year: 2026)

            #expect(outcome.prediction.now == civilDate(today))
            #expect(outcome.prediction.rateDay == civilDate(rateDay))
            #expect(!outcome.prediction.usesUniformRate)
        }
    }

    /// A client in dollars and no ČNB rate stored (and no uniform rate): its amounts are unknown, but the prediction
    /// still names a day of the rates, as it does with no foreign currency: the day of the prediction, or the Friday
    /// before it on a weekend.
    @Test(arguments: daysOfTheRatesWithoutRates)
    func aForeignClientWithoutAStoredRateStillHasADayOfTheRates(today: String, rateDay: String) async throws {
        try await withClient(PredictionSample.foxtrot, on: today) { app in
            let outcome = try await app.predictionOutcome(year: 2026)

            #expect(outcome.prediction.rateDay == civilDate(rateDay))
            #expect(!outcome.prediction.usesUniformRate)
        }
    }

    /// Wednesday 28. 10. 2026 is a public holiday, on which the ČNB declares no rates. With a client in dollars and no
    /// ČNB rate stored (and no uniform rate), the day of the rates is the business day before it, Tuesday 27. 10.
    @Test func onAHolidayTheDayOfTheRatesIsTheBusinessDayBeforeIt() async throws {
        try await withClient(PredictionSample.foxtrot, on: "2026-10-28") { app in
            let outcome = try await app.predictionOutcome(year: 2026)

            #expect(outcome.prediction.now == civilDate("2026-10-28"))
            #expect(outcome.prediction.rateDay == civilDate("2026-10-27"))
            #expect(!outcome.prediction.usesUniformRate)
        }
    }

    /// The year converts with its uniform rates, which it has for the dollar (21,500 Kč) but not for the euro.
    /// Foxtrot's invoices in dollars are converted at the uniform rate, and the invoice expected of a client in euros
    /// at the latest ČNB rate of the euro, 24,300 Kč declared on 16. 10. 2026: its November, from the 10 hours at
    /// 100,00 EUR of its template, is 24 300,00 Kč. The year is still one of the uniform rate, which the page names.
    @Test func aUniformYearConvertsACurrencyWithoutAUniformRateAtTheCNBRate() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
            try await database.saveUniformRates(
                [
                    UniformRate(
                        year: 2026, currency: .usd, amount: 1, rate: decimal("21.5"), instruction: "", sourceURL: nil,
                        confirmedAt: nil, origin: .manual)
                ], year: 2026)
            let euroID = try await database.saveClient(Client(name: "Euro s.r.o.", currency: .eur))
            let consulting = TemplateItem(
                description: "Konzultace", quantity: decimal("10"), unit: "hod", unitPriceMinor: 10_000)
            try await database.saveTemplate(
                InvoiceTemplate(
                    name: "Konzultace", clientID: euroID, items: [consulting], vatMode: .outsideCountry, dueDays: 14))
            try await database.insertCNBRates([
                CNBRateRow(declaredOn: civilDate("2026-10-16"), currency: .eur, amount: 1, rate: decimal("24.3"))
            ])
            try await database.setExpectedInvoiceMonth(year: 2026, clientID: euroID, month: 11, expected: true)

            let outcome = try await app.predictionOutcome(year: 2026)

            let euro = try row(euroID, in: outcome.prediction)
            #expect(euro.months[10].kind == .expected)
            #expect(euro.months[10].amountHalere == 2_430_000)
            let foxtrot = try row(PredictionSample.foxtrot.id, in: outcome.prediction)
            #expect(foxtrot.months[10].amountHalere == 28_569_284)
            #expect(outcome.prediction.usesUniformRate)
            #expect(outcome.prediction.rateDay == nil)
        }
    }

    // MARK: The invoices

    /// The invoices of a prediction are the issued ones of every year, whatever their state, and the drafts issued in
    /// the year, the first and the last day of it included. A draft issued the day before the year or the day after it
    /// is not among them.
    @Test func theInvoicesOfAPredictionAreTheIssuedOnesOfEveryYearAndTheDraftsOfItsYear() async throws {
        try await withSample { app in
            let database = try #require(app.database)
            let draftBefore = try await storeInvoice("20251299", issued: "2025-12-31", status: .draft, in: database)
            let draftFirst = try await storeInvoice("20260199", issued: "2026-01-01", status: .draft, in: database)
            let draftLast = try await storeInvoice("20261299", issued: "2026-12-31", status: .draft, in: database)
            let draftAfter = try await storeInvoice("20270199", issued: "2027-01-01", status: .draft, in: database)
            let inReview = try await storeInvoice(
                "20260999", issued: "2026-09-30", review: ReviewFlag(reason: "Zrušeno ve Fakturoidu"), in: database)
            // The sample's 39 invoices are 1 to 39, and its draft of October 2026 is 12.
            let sampleDraft: Int64 = 12
            let issued = Set(Int64(1)...39).subtracting([sampleDraft]).union([inReview])

            let of2026 = try await database.predictionInvoices(year: 2026)
            let of2025 = try await database.predictionInvoices(year: 2025)
            let of2027 = try await database.predictionInvoices(year: 2027)

            #expect(Set(of2026.map(\.id)) == issued.union([sampleDraft, draftFirst, draftLast]))
            #expect(Set(of2025.map(\.id)) == issued.union([draftBefore]))
            #expect(Set(of2027.map(\.id)) == issued.union([draftAfter]))
            #expect(of2026.count == Set(of2026.map(\.id)).count)
            // An invoice comes with its items and its payment: Foxtrot's of June, 13 720,00 USD paid in July.
            let june = try #require(of2026.first { $0.number == "20260601" })
            #expect(june.netMinor == 1_372_000)
            #expect(june.payment?.date == civilDate("2026-07-07"))
            #expect(june.payment?.czkNetHalere == 28_880_600)
        }
    }

    // MARK: What cannot be loaded

    @Test func aYearOutsideTheCalendarHasNoPrediction() async throws {
        try await withSample { app in
            await #expect(throws: ComputationError.invalidYear(0)) { try await app.predictionOutcome(year: 0) }
            await #expect(throws: ComputationError.invalidYear(10_000)) {
                try await app.predictionOutcome(year: 10_000)
            }
        }
    }

    @Test func lockedDataHasNoPrediction() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)

        await #expect(throws: VaultError.locked) { try await app.predictionOutcome(year: 2026) }
    }
}

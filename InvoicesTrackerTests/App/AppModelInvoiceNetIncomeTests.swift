import Foundation
import Testing
@testable import InvoicesTracker

/// The nets of invoices loaded from the data of an app model (`AppModel.invoiceNetIncomes(of:asOf:)`): the rate of each
/// invoice that is not paid, the year each net is worked out in, and what is left out when the data cannot be read. The
/// data is the prediction sample stored in a temporary database, with the app as of Saturday 17. 10. 2026. The figures
/// are those of the golden table in `InvoiceNetIncomeTests`, which a separate implementation worked out.
@Suite(.settlesBackups)
@MainActor
struct AppModelInvoiceNetIncomeTests {
    // MARK: Helpers

    /// Saturday 17 October 2026, the day of the sample.
    private let today = PredictionSample.sampleToday

    /// The nets in haléře of the eleven payments of 2026, the invoices 1 to 11 of the sample, in that order.
    private let paymentNets: [Int64?] = [
        25_340_100, 17_752_100, 19_299_200, 19_083_900, 19_084_000, 26_188_500, 22_815_460, 381_900, 23_716_800,
        21_701_275, 279_800,
    ]

    /// The invoices of the stored sample with the ids `ids`, in that order, as the database holds them.
    private func stored(_ ids: [Int64], in app: AppModel) async throws -> [Invoice] {
        let database = try #require(app.database)
        var invoices: [Invoice] = []
        for id in ids {
            invoices.append(try #require(try await database.invoice(id: id)))
        }
        return invoices
    }

    /// Writes an income adjustment dated 30. 2. 2025, a day that does not exist, as a change of the data outside the
    /// app could write it. The year 2025 finds it by its dates, so the receipts of 2025 cannot be read, and no other
    /// year finds it.
    private nonisolated func storeAnAdjustmentOfADayThatIsNone(in database: Database) async throws {
        try await database.write { connection in
            try connection.run(
                "INSERT INTO income_adjustment(date, amount_halere, description) VALUES (?, ?, ?)",
                [.text("2025-02-30"), .integer(5_000_000), .text("Mimo faktury")])
        }
    }

    /// Writes a rate of the dollar declared on 32. 10. 2026, a day that does not exist, as a change of the data outside
    /// the app could write it. From 1. 11. on it is the latest rate of the dollar that the lookup finds, and it cannot
    /// read it. The lookups of other currencies, and of the dollar up to 31. 10., do not find it.
    private nonisolated func storeARateOfADayThatIsNone(in database: Database) async throws {
        try await database.write { connection in
            try connection.run(
                "INSERT INTO cnb_rate(declared_on, currency, amount, rate) VALUES (?, ?, ?, ?)",
                [.text("2026-10-32"), .text("USD"), .integer(1), .text("21.5")])
        }
    }

    /// Deletes every ČNB rate stored, as a cache that has none yet.
    private nonisolated func deleteCNBRates(in database: Database) async throws {
        try await database.write { connection in
            try connection.run("DELETE FROM cnb_rate")
        }
    }

    // MARK: The nets

    @Test func theStoredSampleHasTheNetsWorkedOutSeparately() async throws {
        try await PredictionSample.withStoredSample { app in
            let invoices = try await stored(Array(1...12), in: app)

            let nets = await app.invoiceNetIncomes(of: invoices, asOf: today)

            #expect(nets.count == 12)
            #expect((1...11).map { nets[Int64($0)]?.netHalere } == paymentNets)
            #expect((1...11).compactMap { nets[Int64($0)]?.netHalere }.reduce(0, +) == 195_643_035)
            #expect((1...11).allSatisfy { nets[Int64($0)]?.isEstimate == false })
            // The draft is expected on its due date and worth its dollars at the rate stored: 21,320 Kč, which the ČNB
            // declared on Friday 16. 10. 2026.
            let draft = try #require(nets[12])
            #expect(draft.isEstimate)
            #expect(!draft.isProvisional)
            #expect(draft.day == civilDate("2026-11-30"))
            #expect(draft.incomeHalere == 25_669_280)
            #expect(draft.effect.total == 97_057)
            #expect(draft.netHalere == 15_963_580)
        }
    }

    /// The invoice is of 2024, issued on 31. 12., and its payment came on 5. 1. 2025: its levies are those of 2025,
    /// whatever the day shown.
    @Test func aDecemberInvoicePaidInJanuaryIsWorkedOutInTheYearOfItsPayment() async throws {
        try await PredictionSample.withStoredSample { app in
            let december = try #require(try await app.database?.invoice(id: 24))
            let payment = try #require(december.payment)
            #expect(december.issueDate == civilDate("2024-12-31"))
            #expect(payment.date == civilDate("2025-01-05"))

            let nets = await app.invoiceNetIncomes(of: [december], asOf: civilDate("2024-12-31"))

            let net = try #require(nets[24])
            #expect(net.day == civilDate("2025-01-05"))
            #expect(!net.isEstimate)
            let receipt = Receipt(
                day: payment.date, czkNetHalere: payment.czkNetHalere, czkVatHalere: payment.czkVatHalere,
                source: .invoice(24))
            let input2025 = try await app.yearInput(for: 2025).input
            let expected = TaxEngine.effect(of: receipt, in: input2025)
            #expect(net.effect == expected)
            // The levies of 2024 would have been none: the receipt is not of that year.
            #expect(expected.total != 0)
            #expect(net.netHalere == payment.czkNetHalere - expected.total * 100)
        }
    }

    /// A dollar invoice is worth the latest rate of the dollar up to the day its money is expected, so one that is due
    /// earlier has an earlier rate, and an invoice in euros has the rate of the euro.
    @Test func eachInvoiceIsWorthTheLatestRateOfItsCurrencyKnownUpToTheDayItsMoneyIsExpected() async throws {
        try await PredictionSample.withStoredSample { app in
            let database = try #require(app.database)
            // The ČNB declared the dollar at 22,000 Kč on 20. 11., and the euro at 24,500 Kč on 16. 10.
            try await database.insertCNBRates([
                CNBRateRow(declaredOn: civilDate("2026-11-20"), currency: .usd, amount: 1, rate: decimal("22")),
                CNBRateRow(declaredOn: PredictionSample.rateDay, currency: .eur, amount: 1, rate: decimal("24.5")),
            ])
            let draft = try #require(try await database.invoice(id: 12))
            var earlier = draft
            earlier.id = 1_001
            earlier.dueDate = civilDate("2026-11-10")
            var inEuros = draft
            inEuros.id = 1_002
            inEuros.currency = .eur

            let nets = await app.invoiceNetIncomes(of: [draft, earlier, inEuros], asOf: today)

            // 12 040,00 USD at 22,000 Kč, the latest rate up to 30. 11., and at 21,320 Kč, the latest up to 10. 11.
            #expect(nets[12]?.day == civilDate("2026-11-30"))
            #expect(nets[12]?.incomeHalere == 26_488_000)
            #expect(nets[1_001]?.day == civilDate("2026-11-10"))
            #expect(nets[1_001]?.incomeHalere == 25_669_280)
            // 12 040,00 EUR at 24,500 Kč.
            #expect(nets[1_002]?.incomeHalere == 29_498_000)
        }
    }

    @Test func anInvoiceThatTheCNBHasNoRateForIsWorthItsOwnRateOrNothing() async throws {
        try await PredictionSample.withStoredSample { app in
            let database = try #require(app.database)
            var draft = try #require(try await database.invoice(id: 12))
            draft.invoiceRate = storedRate("USD", "20.5", declaredOn: "2026-10-30")

            // The rate of the ČNB counts when there is one, though the invoice has a rate of its own.
            let withCNBRate = await app.invoiceNetIncomes(of: [draft], asOf: today)
            #expect(withCNBRate[12]?.incomeHalere == 25_669_280)

            try await deleteCNBRates(in: database)
            let withOwnRate = await app.invoiceNetIncomes(of: [draft], asOf: today)
            #expect(withOwnRate[12]?.incomeHalere == 24_682_000)
            #expect(withOwnRate[12]?.isEstimate == true)

            draft.invoiceRate = nil
            let withoutRate = await app.invoiceNetIncomes(of: [draft], asOf: today)
            #expect(withoutRate.isEmpty)
        }
    }

    // MARK: What cannot be loaded

    @Test func anInvoiceOfAYearThatCannotBeReadHasNoneAndTheOthersStay() async throws {
        try await PredictionSample.withStoredSample { app in
            try await storeAnAdjustmentOfADayThatIsNone(in: try #require(app.database))
            await #expect(throws: (any Error).self) { try await app.yearInput(for: 2025) }
            let invoices = try await stored([25, 1], in: app)
            #expect(invoices[0].payment?.date == civilDate("2025-02-05"))

            let nets = await app.invoiceNetIncomes(of: invoices, asOf: today)

            #expect(nets[25] == nil)
            #expect(nets[1]?.netHalere == 25_340_100)
            #expect(nets.count == 1)
        }
    }

    @Test func anInvoiceWhoseRateCannotBeReadHasNoneAndTheOthersStay() async throws {
        try await PredictionSample.withStoredSample { app in
            let database = try #require(app.database)
            try await database.insertCNBRates([
                CNBRateRow(declaredOn: PredictionSample.rateDay, currency: .eur, amount: 1, rate: decimal("24.5"))
            ])
            try await storeARateOfADayThatIsNone(in: database)
            var invoices = try await stored(Array(1...12), in: app)
            // The rate of its own that the draft has is no stand-in for the rate of the ČNB that cannot be read.
            invoices[11].invoiceRate = storedRate("USD", "20.5", declaredOn: "2026-10-30")
            var inEuros = invoices[11]
            inEuros.id = 1_002
            inEuros.currency = .eur

            let nets = await app.invoiceNetIncomes(of: invoices + [inEuros], asOf: today)

            // The draft in dollars needs the latest rate of the dollar up to 30. 11., which cannot be read.
            #expect(nets[12] == nil)
            #expect(nets[1_002]?.incomeHalere == 29_498_000)
            #expect((1...11).map { nets[Int64($0)]?.netHalere } == paymentNets)
            #expect(nets.count == 12)
        }
    }

    /// The work away from the main actor (`AppModel.invoiceNetIncomes(of:asOf:in:)`) hands back what it could not read
    /// instead of logging it: one failure for the year and one for the rate, the rate once though two invoices need it.
    /// The invoice that is left is worked out as before.
    @Test func theYearAndTheRateThatCannotBeReadAreHandedBackAsFailuresOnceEach() async throws {
        try await PredictionSample.withStoredSample { app in
            let database = try #require(app.database)
            try await storeAnAdjustmentOfADayThatIsNone(in: database)
            try await storeARateOfADayThatIsNone(in: database)
            var invoices = try await stored([25, 1, 12], in: app)
            var again = invoices[2]
            again.id = 1_001
            invoices.append(again)

            let worked = await AppModel.invoiceNetIncomes(of: invoices, asOf: today, in: database)

            #expect(worked.nets.keys.sorted() == [1])
            #expect(worked.nets[1]?.netHalere == 25_340_100)
            #expect(worked.failures.count == 2)
        }
    }

    @Test func lockedDataHasNoNets() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)

        let nets = await app.invoiceNetIncomes(of: PredictionSample.invoices, asOf: today)

        #expect(nets.isEmpty)
    }
}

// MARK: - A year of invoices

/// With a year of 500 invoices, the nets of all of them take under half a second, with the rates and the years that
/// they are worked out with read once for all of them. Like the performance test of the list, it works on a raw
/// database and away from the main actor (`AppModel.invoiceNetIncomes(of:asOf:in:)`): in a full run the main actor is
/// busy with the window tests, and a test that waits for it times them.
struct InvoiceNetIncomePerformanceTests {
    private let limit = Duration.milliseconds(500)

    @Test func theNetsOfAYearOfFiveHundredInvoicesTakeUnderHalfASecond() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let rates = try cnbYearlyRows([2025, 2026]).filter { $0.currency == .usd || $0.currency == .eur }
        try await database.insertCNBRates(rates)
        try await database.insertGeneratedInvoices(years: 2025...2026, perYear: 500)
        let asOf = civilDate("2026-10-17")
        let source = try await database.invoiceListSource(scope: .issued, year: 2026, asOf: asOf, searchText: "")
        let clock = ContinuousClock()

        let start = clock.now
        let worked = await AppModel.invoiceNetIncomes(of: source.invoices, asOf: asOf, in: database)
        let time = clock.now - start

        #expect(time < limit, "the nets took \(time)")
        #expect(source.invoices.count == 500)
        #expect(worked.nets.count == 500)
        #expect(worked.failures.isEmpty)
    }
}

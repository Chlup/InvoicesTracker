import Foundation
import Testing
@testable import InvoicesTracker

/// How a year converts its income in other currencies: what it can use (`fxState(year:)`), the choice
/// (`setFXMethod(_:year:)`), and the payments converted again whenever the method a year uses may have changed — a
/// payment recorded or removed, an invoice edited or deleted, an import. The data is invented, the ČNB rates of dollars
/// and euros are those of the fixtures of 2025 and 2026, and the clock is at noon of 17. 10. 2026: 2026 is the current
/// year, whose uniform rate is not published yet, and 2025 has the uniform rates that ship with the app (1 USD =
/// 21,84 Kč, 1 EUR = 24,66 Kč). In every expected string `\u{00A0}` is the no-break space.
@Suite(.settlesBackups)
@MainActor
struct AppModelFXTests {
    /// The page of an invoice is measured in the font it is set in, so the fonts are registered before any test, as the
    /// app does at its launch.
    init() {
        InvoiceFonts.register()
    }

    // MARK: Helpers

    /// An app model that has gone through the first launch, with the ČNB rates of dollars and euros of 2025 and 2026.
    private func makeApp(in directory: URL) async throws -> AppModel {
        let app = makeAppModel(in: directory)
        try await startFresh(app)
        try await storeRates(in: try #require(app.database))
        return app
    }

    private func storeRates(in database: Database) async throws {
        let rows = try cnbYearlyRows([2025, 2026]).filter { $0.currency == .usd || $0.currency == .eur }
        try await database.insertCNBRates(rows)
    }

    /// An invoice of `amountMinor` hundredths of `currency` without VAT, supplied and issued on `issued`.
    private func invoice(
        _ number: String, _ currency: CurrencyCode, _ amountMinor: Int64, issued: String,
        vatMode: VatMode = .outsideCountry
    ) -> Invoice {
        Invoice.fixture(
            number: number, currency: currency, duzp: issued, dueDate: issued, items: [.fixture("1", at: amountMinor)],
            vatMode: vatMode)
    }

    /// Stores `invoice` without a payment, and returns it as stored.
    private func storeUnpaid(_ invoice: Invoice, in app: AppModel) async throws -> Invoice {
        var stored = invoice
        stored.id = try await #require(app.database).saveInvoice(invoice)
        return stored
    }

    /// Stores `invoice` paid on `day` at the ČNB rate of that day, as the app converts a payment in a year that
    /// converts at the daily rates, and returns it as stored.
    @discardableResult
    private func storePaid(_ invoice: Invoice, on day: String, in app: AppModel) async throws -> Invoice {
        let database = try #require(app.database)
        var paid = invoice
        paid.payment = try await app.convert(invoice, paidOn: civilDate(day), method: .cnbDaily, in: database)
        #expect(paid.payment?.conversion == .cnbDaily && paid.payment?.provisional == false)
        paid.id = try await database.saveInvoice(paid)
        return paid
    }

    /// Records the payment of `invoice` received on `day` in the sheet "Označit jako uhrazenou", by the method of the
    /// year, and returns the sheet.
    @discardableResult
    private func recordPayment(of invoice: Invoice, on day: String, in app: AppModel) async throws
        -> PaymentSheetModel
    {
        let sheet = PaymentSheetModel(app: app, invoice: invoice)
        sheet.date = civilDate(day)
        await sheet.recompute()
        try await sheet.save()
        return sheet
    }

    private func payment(of id: Int64, in app: AppModel) async throws -> Payment {
        let database = try #require(app.database)
        return try #require(try await database.invoice(id: id)?.payment)
    }

    /// Takes the uniform rate of euros out of the table of `year` that ships with the app, as for a year that has the
    /// rate of dollars only.
    private func takeOutTheEuroRate(of year: Int, in app: AppModel) async throws {
        try await #require(app.database).execute(
            "DELETE FROM uniform_rate WHERE year = \(year) AND currency = '\(CurrencyCode.eur.code)'")
    }

    /// The ČNB rates of dollars of the fixture of 2022, and those of 15. 6. 2023 and 14. 6. 2024 (invented ones, 21,900
    /// and 23,100 Kč), the days the dollars of those years arrive on.
    private func storeDollarRatesOf2022To2024(in database: Database) async throws {
        try await database.insertCNBRates(try cnbYearlyRows([2022]).filter { $0.currency == .usd })
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2023-06-15"), currency: .usd, amount: 1, rate: decimal("21.900")),
            CNBRateRow(declaredOn: civilDate("2024-06-14"), currency: .usd, amount: 1, rate: decimal("23.100")),
        ])
    }

    /// Stores 10 000,00 USD paid in each of `years`, on 15. 6. 2022, 15. 6. 2023, 14. 6. 2024 and 2. 10. 2025, at the
    /// ČNB rates of those days, and returns the invoices as stored, by year.
    private func storeDollarsPaid(in years: [Int], in app: AppModel) async throws -> [Int: Invoice] {
        let days = [2022: "2022-06-15", 2023: "2023-06-15", 2024: "2024-06-14", 2025: "2025-10-02"]
        var paid: [Int: Invoice] = [:]
        for year in years {
            let day = try #require(days[year])
            let unpaid = invoice("\(year)0601", .usd, 1_000_000, issued: "\(year)-06-01")
            paid[year] = try await storePaid(unpaid, on: day, in: app)
        }
        return paid
    }

    /// Výpočet of `year` as it loads: the line of the payments received, and the assumption of the conversion.
    private func computation(of year: Int, in app: AppModel) async throws -> (received: String, conversion: String) {
        app.selectYear(year)
        let model = ComputationModel(app: app)
        await model.load()
        let income = try #require(model.sections.first { $0.title == "Příjmy a zisk" })
        let received = try #require(income.rows.first { $0.label == "Přijaté platby" })
        return (received.value, try #require(model.page?.assumptions.items[3]))
    }

    /// A paid invoice in euros of the export of Fakturoid, for a client outside the EU, paid on 10. 11. 2025.
    private func paidEuroRow() -> FakturoidCSV.Row {
        FakturoidCSV.row([
            "Id": "20251105", "Number": "20251105", "Variable symbol": "20251105", "Client name": "Delta AG",
            "Client registration no": "", "Client vat no": "", "Client country": "CH", "Currency": "EUR",
            "Exchange rate": "24.3", "Vat": "0.0", "Status": "paid", "Issued on": "2025-11-03",
            "Taxable fulfillment due": "2025-11-03", "Due on": "2025-11-17", "Paid on": "2025-11-10",
            "Subtotal": "2000,0", "Total": "2000,0", "Language": "en",
        ])
    }

    // MARK: Switching

    /// A year switched to the uniform rate and back has every payment exactly as before, to the haléř: the dollars of
    /// 2. 10. and of 15. 11. 2025 (a Saturday, so at the rate of the Friday) at the ČNB rates of their days.
    @Test func switchingToUniformAndBackRestoresEveryAmountExactly() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let first = try await storePaid(
            invoice("20251001", .usd, 1_000_000, issued: "2025-09-30"), on: "2025-10-02", in: app)
        let second = try await storePaid(
            invoice("20251101", .usd, 500_000, issued: "2025-10-31"), on: "2025-11-15", in: app)
        // At 20,618 Kč and 20,786 Kč: 206 180,00 Kč and 103 930,00 Kč.
        #expect(first.payment?.rate == storedRate("USD", "20.618", declaredOn: "2025-10-02"))
        #expect(second.payment?.rate == storedRate("USD", "20.786", declaredOn: "2025-11-14"))
        #expect([first.payment?.czkNetHalere, second.payment?.czkNetHalere] == [20_618_000, 10_393_000])
        let receipts = try await database.receipts(year: 2025)

        #expect(await app.setFXMethod(.uniform, year: 2025) == .saved)

        // 10 000,00 USD and 5 000,00 USD at 21,84 Kč.
        let uniform = [try await payment(of: first.id, in: app), try await payment(of: second.id, in: app)]
        #expect(uniform.map(\.conversion) == [.uniform, .uniform])
        #expect(uniform.map(\.czkNetHalere) == [21_840_000, 10_920_000])
        #expect(uniform.allSatisfy { $0.rate == storedRate("USD", "21.84", declaredOn: "2025-12-31") })
        #expect(try await database.yearSettings(2025).incomeFXMethod == .uniform)

        #expect(await app.setFXMethod(.cnbDaily, year: 2025) == .saved)

        let daily = [try await payment(of: first.id, in: app), try await payment(of: second.id, in: app)]
        #expect(daily.map(\.czkNetHalere) == [first.payment?.czkNetHalere, second.payment?.czkNetHalere])
        #expect(daily == [first.payment, second.payment])
        #expect(try await database.receipts(year: 2025) == receipts)
        #expect(try await database.yearSettings(2025).incomeFXMethod == .cnbDaily)
    }

    @Test func theVATOfAPaymentComesBackExactlyToo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // 1 234,57 EUR and 259,26 EUR of VAT.
        let euros = try await storePaid(
            invoice("20250901", .eur, 123_457, issued: "2025-09-01", vatMode: .domestic21), on: "2025-09-03",
            in: app)

        #expect(await app.setFXMethod(.uniform, year: 2025) == .saved)
        let uniform = try await payment(of: euros.id, in: app)
        // At 24,66 Kč: 30 444,50 Kč and 6 393,35 Kč.
        #expect(uniform.czkNetHalere == 3_044_450 && uniform.czkVatHalere == 639_335)

        #expect(await app.setFXMethod(.cnbDaily, year: 2025) == .saved)
        #expect(try await payment(of: euros.id, in: app) == euros.payment)
    }

    @Test func aBankAmountInCrownsStaysWhenTheMethodSwitches() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        // The year has no uniform rate of euros, and the money of the invoice in euros came in crowns.
        try await takeOutTheEuroRate(of: 2025, in: app)
        let dollars = try await storePaid(
            invoice("20251001", .usd, 1_000_000, issued: "2025-09-30"), on: "2025-10-02", in: app)
        var bank = invoice("20251102", .eur, 300_000, issued: "2025-11-03")
        bank.payment = Payment(
            date: civilDate("2025-11-10"), conversion: .bankCZK, czkNetHalere: 7_312_345, czkVatHalere: 0,
            bankCZKTotalHalere: 7_312_345)
        bank.id = try await database.saveInvoice(bank)

        // An amount in crowns needs no uniform rate, so the year can take its rate although it has none of euros.
        #expect(try await app.fxState(year: 2025).uniform.isReady)
        #expect(await app.setFXMethod(.uniform, year: 2025) == .saved)

        #expect(try await payment(of: bank.id, in: app) == bank.payment)
        #expect(try await payment(of: dollars.id, in: app).conversion == .uniform)

        #expect(await app.setFXMethod(.cnbDaily, year: 2025) == .saved)

        #expect(try await payment(of: bank.id, in: app) == bank.payment)
        #expect(try await payment(of: dollars.id, in: app) == dollars.payment)
    }

    // MARK: What a year can use

    @Test func theCurrentYearCannotUseTheUniformRateYet() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let dollars = try await storePaid(
            invoice("20261001", .usd, 1_000_000, issued: "2026-09-30"), on: "2026-10-02", in: app)

        #expect(
            try await app.fxState(year: 2026)
                == YearFXState(
                    year: 2026, chosen: .cnbDaily, effective: .cnbDaily, uniform: .notPublishedYet(year: 2026),
                    hasForeignPayments: true))
        // The uniform rate cannot be chosen: nothing is stored, and nothing is converted.
        let version = app.dataVersion
        #expect(await app.setFXMethod(.uniform, year: 2026) == .unchanged)
        #expect(try await database.yearSettings(2026).incomeFXMethod == .cnbDaily)
        #expect(try await payment(of: dollars.id, in: app) == dollars.payment)
        #expect(app.dataVersion == version)

        // A year that is over, and that the app has no uniform rate of, does not have it in the app.
        try await database.execute("DELETE FROM uniform_rate WHERE year = 2024")
        #expect(try await app.fxState(year: 2024).uniform == .notInApp(year: 2024))
    }

    /// On 15. 2. 2026 the app looks for the uniform rate of 2025, which the GFŘ publishes in January: the year is
    /// looked for rather than lacking its rate.
    @Test func theYearJustOverIsLookedForWhileTheAppSearchesForItsRate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory, clock: ManualClock(localNoon(2026, 2, 15)))
        try await startFresh(app)
        try await #require(app.database).execute("DELETE FROM uniform_rate WHERE year = 2025")

        #expect(try await app.fxState(year: 2025).uniform == .searchedFor(year: 2025))
    }

    @Test func aYearWithoutTheEuroRateStaysOnDailyRates() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await takeOutTheEuroRate(of: 2025, in: app)
        let dollars = try await storePaid(
            invoice("20251001", .usd, 1_000_000, issued: "2025-09-30"), on: "2025-10-02", in: app)
        #expect(await app.setFXMethod(.uniform, year: 2025) == .saved)
        #expect(try await payment(of: dollars.id, in: app).conversion == .uniform)

        // Money in euros comes, and the year has no uniform rate of euros.
        let euros = try await storeUnpaid(invoice("20251101", .eur, 200_000, issued: "2025-11-03"), in: app)
        let sheet = PaymentSheetModel(app: app, invoice: euros)
        sheet.date = civilDate("2025-11-10")
        await sheet.recompute()
        #expect(
            sheet.notice
                == "Jednotný kurz 2025: chybí jednotný kurz EUR – zadáte ho v Nastavení › Rok 2025. Platba i celý rok"
                + " 2025 se proto zatím přepočtou kurzem ČNB ke dni přijetí.")
        try await sheet.save()

        let state = try await app.fxState(year: 2025)
        #expect(state.chosen == .uniform)
        #expect(state.effective == .cnbDaily)
        #expect(state.uniform == .missingCurrency(.eur))
        #expect(state.hasForeignPayments)
        // The whole year is converted at the ČNB rates of the days: the dollars exactly as before, the euros at the
        // rate of their day.
        #expect(try await payment(of: dollars.id, in: app) == dollars.payment)
        let expected = try await app.convert(euros, paidOn: civilDate("2025-11-10"), method: .cnbDaily, in: database)
        #expect(try await payment(of: euros.id, in: app) == expected)
        #expect(expected.conversion == .cnbDaily && !expected.provisional)
    }

    @Test func recordingAPaymentInAUniformYearUsesTheUniformRate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // Nothing is paid in 2025 yet, and the year has its uniform rates.
        #expect(await app.setFXMethod(.uniform, year: 2025) == .saved)
        let unpaid = try await storeUnpaid(invoice("20251201", .usd, 1_000_000, issued: "2025-12-01"), in: app)

        let sheet = PaymentSheetModel(app: app, invoice: unpaid)
        sheet.date = civilDate("2025-12-10")
        await sheet.recompute()
        #expect(
            sheet.methodOption
                == PaymentOption(
                    title: "Jednotný kurz za rok 2025", detail: "21,840\u{00A0}Kč/USD · přepočet zvolený pro rok 2025",
                    value: "218\u{00A0}400,00\u{00A0}Kč"))
        #expect(sheet.notice == nil)
        try await sheet.save()

        #expect(
            try await payment(of: unpaid.id, in: app)
                == Payment(
                    date: civilDate("2025-12-10"), conversion: .uniform, czkNetHalere: 21_840_000, czkVatHalere: 0,
                    rate: storedRate("USD", "21.84", declaredOn: "2025-12-31")))
        #expect(try await app.fxState(year: 2025).effective == .uniform)
    }

    // MARK: Converting again when the payments of a year change

    @Test func deletingTheOnlyInvoiceOfACurrencyWithoutTheRateBringsTheYearBackToTheUniformRate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await takeOutTheEuroRate(of: 2025, in: app)
        let dollars = try await storePaid(
            invoice("20251001", .usd, 1_000_000, issued: "2025-09-30"), on: "2025-10-02", in: app)
        #expect(await app.setFXMethod(.uniform, year: 2025) == .saved)
        let euros = try await storeUnpaid(invoice("20251101", .eur, 200_000, issued: "2025-11-03"), in: app)
        try await recordPayment(of: euros, on: "2025-11-10", in: app)
        #expect(try await payment(of: dollars.id, in: app) == dollars.payment)

        #expect(try await InvoicesModel(app: app).delete(euros.id, typed: euros.number))

        // The year has the rate of every currency it was paid in again, and is converted at it by itself: the choice
        // was kept.
        let state = try await app.fxState(year: 2025)
        #expect(state.effective == .uniform && state.chosen == .uniform)
        let converted = try await payment(of: dollars.id, in: app)
        #expect(converted.conversion == .uniform && converted.czkNetHalere == 21_840_000)
    }

    /// The year set to the uniform rate has the rate of dollars and not of euros, so the payment in euros turned it to
    /// the ČNB rates of the days. Once that payment is removed, the year has the rate of every currency it is paid in
    /// again and is converted at it by itself, both payments in dollars included: the choice was kept.
    @Test func removingTheLastPaymentInACurrencyTurnsTheYearBackToTheUniformRate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await takeOutTheEuroRate(of: 2025, in: app)
        let first = try await storePaid(
            invoice("20251001", .usd, 1_000_000, issued: "2025-09-30"), on: "2025-10-02", in: app)
        let second = try await storePaid(
            invoice("20251101", .usd, 500_000, issued: "2025-10-31"), on: "2025-11-14", in: app)
        #expect(await app.setFXMethod(.uniform, year: 2025) == .saved)
        let euros = try await storeUnpaid(invoice("20251102", .eur, 200_000, issued: "2025-11-03"), in: app)
        try await recordPayment(of: euros, on: "2025-11-10", in: app)
        #expect(try await app.fxState(year: 2025).effective == .cnbDaily)
        #expect(try await payment(of: first.id, in: app) == first.payment)
        #expect(try await payment(of: second.id, in: app) == second.payment)

        #expect(try await InvoicesModel(app: app).removePayment(euros.id, typed: euros.number))

        #expect(try await database.invoice(id: euros.id)?.payment == nil)
        let state = try await app.fxState(year: 2025)
        #expect(state.effective == .uniform && state.chosen == .uniform)
        // 10 000,00 USD and 5 000,00 USD at 21,84 Kč.
        let converted = [try await payment(of: first.id, in: app), try await payment(of: second.id, in: app)]
        #expect(converted.map(\.conversion) == [.uniform, .uniform])
        #expect(converted.map(\.czkNetHalere) == [21_840_000, 10_920_000])
        #expect(converted.allSatisfy { $0.rate == storedRate("USD", "21.84", declaredOn: "2025-12-31") })
    }

    @Test func anInvoiceEditedIntoACurrencyWithoutTheRateTurnsItsYearToDailyRates() async throws {
        try await EditorFixture.with { f in
            let app = f.app
            try await takeOutTheEuroRate(of: 2025, in: app)
            let delta = Client(
                name: "Delta AG", city: "Zürich", country: "CH", currency: .eur, vatMode: .outsideCountry,
                language: .en)
            let deltaID = try await f.database.saveClient(delta)
            let first = try await storePaid(
                invoice("20251001", .usd, 1_000_000, issued: "2025-09-30"), on: "2025-10-02", in: app)
            let second = try await storePaid(
                invoice("20251101", .usd, 500_000, issued: "2025-10-31"), on: "2025-11-14", in: app)
            #expect(await app.setFXMethod(.uniform, year: 2025) == .saved)
            #expect(try await payment(of: first.id, in: app).conversion == .uniform)

            // The second invoice was for a client in euros after all.
            let editor = try await f.editor(editing: second.id)
            editor.pickClient(deltaID)
            try await editor.saveChanges()

            let edited = try await f.stored(second.id)
            #expect(edited.currency == .eur)
            let state = try await app.fxState(year: 2025)
            #expect(state.effective == .cnbDaily && state.uniform == .missingCurrency(.eur))
            #expect(try await payment(of: first.id, in: app) == first.payment)
            let expected = try await app.convert(
                edited, paidOn: civilDate("2025-11-14"), method: .cnbDaily, in: f.database)
            #expect(edited.payment == expected)
            #expect(expected.conversion == .cnbDaily)
        }
    }

    @Test func anImportOfAPaymentInACurrencyWithoutTheRateTurnsItsYearToDailyRates() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await takeOutTheEuroRate(of: 2025, in: app)
        let dollars = try await storePaid(
            invoice("20251001", .usd, 1_000_000, issued: "2025-09-30"), on: "2025-10-02", in: app)
        #expect(await app.setFXMethod(.uniform, year: 2025) == .saved)
        let url = try writeCSV(FakturoidCSV.text([paidEuroRow()]), named: "export.csv", in: directory)
        let model = ImportModel(app: app)

        await model.importFiles([url])

        #expect(model.failure == nil && model.summary?.added == 1 && model.summary?.needsReview == 0)
        let state = try await app.fxState(year: 2025)
        #expect(state.effective == .cnbDaily && state.uniform == .missingCurrency(.eur))
        #expect(try await payment(of: dollars.id, in: app) == dollars.payment)
        let imported = try #require(try await database.invoice(numberDigits: "20251105", currency: .eur))
        let expected = try await app.convert(
            imported, paidOn: civilDate("2025-11-10"), method: .cnbDaily, in: database)
        #expect(imported.payment == expected)
        #expect(expected.conversion == .cnbDaily && !expected.provisional)
    }

    /// The choice of a year is kept while the year lacks a rate: once the rate of every currency is there, the year is
    /// converted at the uniform rate again without being chosen again.
    @Test func aYearSetToTheUniformRateTakesItAgainOnceItHasTheRateOfEveryCurrency() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let dollars = try await storePaid(
            invoice("20261001", .usd, 1_000_000, issued: "2026-09-30"), on: "2026-10-02", in: app)
        let year = YearTabModel(app: app)
        await year.load()
        #expect(await year.saveManualUniformRates(usd: "21,50", eur: "", instruction: ""))
        await year.setFXMethod(.uniform)
        #expect(year.saveFailure == nil)
        #expect(try await payment(of: dollars.id, in: app).czkNetHalere == 21_500_000)

        let euros = try await storeUnpaid(invoice("20261002", .eur, 200_000, issued: "2026-10-05"), in: app)
        try await recordPayment(of: euros, on: "2026-10-07", in: app)
        #expect(try await app.fxState(year: 2026).uniform == .missingCurrency(.eur))
        #expect(try await payment(of: dollars.id, in: app) == dollars.payment)

        #expect(await year.saveManualUniformRates(usd: "21,50", eur: "24,50", instruction: ""))

        #expect(try await app.fxState(year: 2026).effective == .uniform)
        #expect(try await payment(of: dollars.id, in: app).czkNetHalere == 21_500_000)
        let converted = try await payment(of: euros.id, in: app)
        // 2 000,00 EUR at 24,50 Kč.
        #expect(converted.conversion == .uniform && converted.czkNetHalere == 4_900_000)
    }

    /// A year that converts at the daily ČNB rates is converted again too when its payments change, as every year is,
    /// by the method it uses: a payment of it that was converted otherwise meanwhile, here at a rate that is not the
    /// ČNB rate of its day, takes that rate. One that was converted at it stays exactly as it is.
    @Test func aYearSetToTheDailyRatesIsConvertedAgainWhenAPaymentIsRecorded() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        var earlier = invoice("20261001", .usd, 1_000_000, issued: "2026-09-30")
        earlier.payment = Payment(
            date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 21_000_000, czkVatHalere: 0,
            rate: storedRate("USD", "21.000", declaredOn: "2026-10-02"))
        earlier.id = try await database.saveInvoice(earlier)
        let daily = try await storePaid(
            invoice("20261003", .usd, 300_000, issued: "2026-09-30"), on: "2026-10-05", in: app)
        let later = try await storeUnpaid(invoice("20261002", .usd, 500_000, issued: "2026-10-05"), in: app)

        try await recordPayment(of: later, on: "2026-10-07", in: app)

        let atTheRateOfItsDay = try await app.convert(
            earlier, paidOn: civilDate("2026-10-02"), method: .cnbDaily, in: database)
        #expect(atTheRateOfItsDay != earlier.payment)
        #expect(try await payment(of: earlier.id, in: app) == atTheRateOfItsDay)
        #expect(try await payment(of: daily.id, in: app) == daily.payment)
    }

    // MARK: The years that inherit the choice

    /// A year without settings of its own takes the choices of the nearest earlier year that has them. The later years
    /// that take the choice of a year switch with it, and their payments are converted with them, so what their texts
    /// say is what their amounts are.
    @Test func theLaterYearsThatInheritTheChoiceAreConvertedWithIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await storeDollarRatesOf2022To2024(in: database)
        // Settings of 2022 alone: 2023 and the years after it take its choices.
        try await database.saveYearSettings(YearSettings(year: 2022))
        #expect(try await database.storedSettingsYears() == [2022])
        let paid = try await storeDollarsPaid(in: [2022, 2023, 2024], in: app)

        #expect(await app.setFXMethod(.uniform, year: 2022) == .saved)

        // 10 000,00 USD at the uniform rates of 2022, 2023 and 2024: 23,41, 22,14 and 23,28 Kč.
        let uniformRates = [2022: "23.41", 2023: "22.14", 2024: "23.28"]
        for (year, invoice) in paid {
            let payment = try await payment(of: invoice.id, in: app)
            #expect(payment.conversion == .uniform, "\(year)")
            #expect(payment.rate == storedRate("USD", uniformRates[year] ?? "", declaredOn: "\(year)-12-31"), "\(year)")
            let state = try await app.fxState(year: year)
            #expect(state.chosen == .uniform && state.effective == .uniform, "\(year)")
        }
        #expect(
            try await computation(of: 2023, in: app)
                == ("221\u{00A0}400,00", "Cizí měny v Kč jednotným kurzem 2023 (pokyn GFŘ-D-63)"))

        #expect(await app.setFXMethod(.cnbDaily, year: 2022) == .saved)

        for (year, invoice) in paid {
            #expect(try await payment(of: invoice.id, in: app) == invoice.payment, "\(year)")
            #expect(try await app.fxState(year: year).effective == .cnbDaily, "\(year)")
        }
        // 10 000,00 USD at 21,900 Kč.
        #expect(
            try await computation(of: 2023, in: app)
                == ("219\u{00A0}000,00", "Cizí měny v Kč kurzem ČNB ke dni přijetí platby"))
        // No year took settings of its own.
        #expect(try await database.storedSettingsYears() == [2022])
    }

    @Test func aLaterYearWithSettingsOfItsOwnKeepsItsChoiceAndItsPayments() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await storeDollarRatesOf2022To2024(in: database)
        // 2024 has settings of its own, and 2025 takes them.
        try await database.saveYearSettings(YearSettings(year: 2022))
        try await database.saveYearSettings(YearSettings(year: 2024))
        let inheriting = try #require(try await storeDollarsPaid(in: [2023], in: app)[2023])
        // The dollars of 2024 and 2025 as they were converted when they came, at rates that are not the ones stored
        // now: a conversion of them would show.
        var leftAlone: [Int: Invoice] = [:]
        for (year, day) in [(2024, "2024-06-14"), (2025, "2025-10-02")] {
            var paid = invoice("\(year)0601", .usd, 1_000_000, issued: "\(year)-06-01")
            paid.payment = Payment(
                date: civilDate(day), conversion: .cnbDaily, czkNetHalere: 20_000_000, czkVatHalere: 0,
                rate: storedRate("USD", "20.000", declaredOn: day))
            paid.id = try await database.saveInvoice(paid)
            leftAlone[year] = paid
        }

        #expect(await app.setFXMethod(.uniform, year: 2022) == .saved)

        #expect(try await payment(of: inheriting.id, in: app).conversion == .uniform)
        for (year, paid) in leftAlone {
            #expect(try await payment(of: paid.id, in: app) == paid.payment, "\(year)")
            #expect(try await app.fxState(year: year).chosen == .cnbDaily, "\(year)")
        }
    }

    // MARK: Opening the data

    /// Earlier versions of the app stored the payment of a year set to the uniform rate that did not have it as a
    /// provisional stand-in: `.uniform` at the ČNB rate of its day. Such a year is converted at the ČNB rates of the
    /// days now, so when the app opens its data the stand-in becomes the daily payment it stood in for, at once rather
    /// than with the next ČNB rates. A payment that waits for the ČNB rate of its day is left to them.
    @Test func storedStandInsOfAUniformRateBecomeDailyPaymentsWhenTheAppOpensItsData() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let before = try await makeApp(in: directory)
        let database = try #require(before.database)
        try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
        var standIn = invoice("20261001", .usd, 1_000_000, issued: "2026-09-30")
        let daily = try await before.convert(standIn, paidOn: civilDate("2026-10-02"), method: .cnbDaily, in: database)
        var stored = daily
        stored.conversion = .uniform
        stored.provisional = true
        standIn.payment = stored
        standIn.id = try await database.saveInvoice(standIn)
        // The rate of 19. 10. 2026 is not declared yet: the payment waits at the rate of its invoice.
        var waiting = invoice("20261002", .usd, 500_000, issued: "2026-09-30")
        waiting.invoiceRate = storedRate("USD", "21.359", declaredOn: "2026-09-30")
        waiting.payment = Payment(
            date: civilDate("2026-10-19"), conversion: .cnbDaily, czkNetHalere: 10_679_500, czkVatHalere: 0,
            rate: waiting.invoiceRate, provisional: true)
        waiting.id = try await database.saveInvoice(waiting)
        await database.close()

        let app = makeAppModel(in: directory)
        await app.launch()

        #expect(app.phase == .ready)
        let converted = try await payment(of: standIn.id, in: app)
        #expect(converted == daily)
        #expect(converted.conversion == .cnbDaily && !converted.provisional)
        #expect(converted.czkNetHalere == stored.czkNetHalere)
        #expect(try await payment(of: waiting.id, in: app) == waiting.payment)
    }

    // MARK: One conversion at a time

    /// New ČNB rates convert the provisional payments of a year set to the uniform rate while the year is switched to
    /// the daily ČNB rates. The two conversions take turns, so neither converts a payment by what the other one has
    /// changed meanwhile: the year ends with every payment at the ČNB rate of its day, whichever of them came first.
    @Test func newRatesAndASwitchToTheDailyRatesAtOnceLeaveEveryPaymentAtTheRateOfItsDay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await database.updateYearSettings(2025) { $0.incomeFXMethod = .uniform }
        // Twelve payments of 2. 10. 2025 converted for now at the rate of their invoice, 20,500 Kč, as before the ČNB
        // rates of their day were stored: the new rates convert them again.
        for month in 1...12 {
            let number = "2025" + (month < 10 ? "0" : "") + "\(month)01"
            var dollars = invoice(number, .usd, 100_000 * Int64(month), issued: "2025-09-30")
            dollars.invoiceRate = storedRate("USD", "20.500", declaredOn: "2025-09-30")
            dollars.payment = PaymentConverter.convert(
                invoice: dollars, date: civilDate("2025-10-02"), requested: .cnbDaily, bankCZKTotalHalere: nil,
                cnbRate: .notYetAvailable, uniformRate: nil)
            #expect(dollars.payment?.provisional == true)
            try await database.saveInvoice(dollars)
        }

        async let converted: Void = app.ratesUpdated()
        async let choice = app.setFXMethod(.cnbDaily, year: 2025)
        await converted
        #expect(await choice == .saved)

        let paid = try await database.paidInvoices(year: 2025)
        #expect(paid.count == 12)
        for invoice in paid {
            let payment = try #require(invoice.payment)
            let daily = try await app.convert(invoice, paidOn: payment.date, method: .cnbDaily, in: database)
            #expect(daily.conversion == .cnbDaily && !daily.provisional)
            #expect(payment == daily, "\(invoice.number)")
        }
    }

    /// A choice asked for while another conversion runs waits for its turn. A backup restored meanwhile replaces the
    /// data it was asked for, so when its turn comes it does nothing: it never stores the choice, or converts payments,
    /// in the data that is open then.
    @Test(.hangGuard)
    func aChoiceWhoseTurnComesAfterARestoreChangesNothingInTheRestoredData() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let before = try #require(app.database)
        let dollars = try await storePaid(
            invoice("20251001", .usd, 1_000_000, issued: "2025-09-30"), on: "2025-10-02", in: app)
        await app.didWriteAndBackUp()
        let backup = try #require(try app.backups.localBackups().first)
        // A conversion that takes long holds the turns.
        let gate = Gate()
        let running = Task { await app.convertPaymentsInTurn { _ in await gate.pass() } }
        await gate.untilARequestWaits()
        let runningTurn = app.latestConversion
        let choice = Task { await app.setFXMethod(.uniform, year: 2025) }
        try await waitUntil { app.latestConversion != runningTurn }

        let restore = Task { try await app.restoreWhileOpen(from: backup.url, recoveryCode: nil) }
        try await waitUntil { app.database !== before }
        let restored = try #require(app.database)
        await gate.open()

        #expect(await choice.value == .notSaved)
        _ = try await restore.value
        _ = await running.value
        #expect(app.database === restored)
        #expect(try await restored.yearSettings(2025).incomeFXMethod == .cnbDaily)
        #expect(try await restored.invoice(id: dollars.id)?.payment == dollars.payment)
    }

    /// An import converts its payments by the method their year uses before it writes them. A year switched to the
    /// daily ČNB rates in between has its payments converted by the switch, which cannot see the imported ones yet:
    /// the conversion after the import converts them by the method the year uses then, also the daily rates.
    @Test func anImportWhoseYearSwitchesToTheDailyRatesBeforeItWritesLeavesNoUniformPaymentInTheYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        #expect(await app.setFXMethod(.uniform, year: 2025) == .saved)
        let url = try writeCSV(FakturoidCSV.text([paidEuroRow()]), named: "export.csv", in: directory)
        let importer = FakturoidImporter(database: database, fetcher: nil, clock: app.dependencies.clock)
        _ = try await importer.importFiles([url]) { _ in }
        let imported = try #require(try await database.invoice(numberDigits: "20251105", currency: .eur))
        // At the uniform rate of 2025, which the year used when the import converted the payment.
        #expect(imported.payment?.conversion == .uniform)
        // The switch to the daily rates, stored after the import converted its payments: the switch converted the
        // payments of the year before the import wrote its own, so it found none of them.
        try await database.updateYearSettings(2025) { $0.incomeFXMethod = .cnbDaily }

        // What the import does once it has written its payments (`ImportModel.importFiles(_:)`).
        await app.recomputePaymentsAfterChanges(inYears: importer.yearsOfChangedPayments)

        #expect(importer.yearsOfChangedPayments == [2025])
        let converted = try #require(try await database.invoice(id: imported.id))
        #expect(
            converted.payment
                == (try await app.convert(imported, paidOn: civilDate("2025-11-10"), method: .cnbDaily, in: database)))
        #expect(converted.payment?.conversion == .cnbDaily)
        #expect(try await database.paidInvoices(year: 2025).allSatisfy { $0.payment?.conversion != .uniform })
    }

    /// Nastavení › Rok saves a uniform rate entered by hand while it still shows the year at the daily rates it last
    /// read, though the year was switched to the uniform rate in the menu of the toolbar meanwhile: the app converts
    /// the year by the method it uses then, so its payments take the rate that is saved.
    @Test func aRateSavedInTheRokTabConvertsTheYearByTheMethodItUsesNotByWhatTheTabLastRead() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let dollars = try await storePaid(
            invoice("20261001", .usd, 1_000_000, issued: "2026-09-30"), on: "2026-10-02", in: app)
        let year = YearTabModel(app: app)
        await year.load()
        #expect(await year.saveManualUniformRates(usd: "21,50", eur: "", instruction: ""))
        #expect(await app.setFXMethod(.uniform, year: 2026) == .saved)
        // 10 000,00 USD at 21,50 Kč, and the tab has not loaded since.
        #expect(try await payment(of: dollars.id, in: app).czkNetHalere == 21_500_000)
        #expect(year.settings?.incomeFXMethod == .cnbDaily)

        #expect(await year.saveManualUniformRates(usd: "22,00", eur: "", instruction: ""))

        // 10 000,00 USD at 22,00 Kč.
        let converted = try await payment(of: dollars.id, in: app)
        #expect(converted.conversion == .uniform && converted.czkNetHalere == 22_000_000)
    }

    // MARK: The choice

    @Test func aChoiceThatCannotBeStoredChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let dollars = try await storePaid(
            invoice("20251001", .usd, 1_000_000, issued: "2025-09-30"), on: "2025-10-02", in: app)
        try await setDatabaseReadOnly(true, database)

        #expect(await app.setFXMethod(.uniform, year: 2025) == .notSaved)

        try await setDatabaseReadOnly(false, database)
        #expect(try await database.yearSettings(2025).incomeFXMethod == .cnbDaily)
        #expect(try await payment(of: dollars.id, in: app) == dollars.payment)
    }

    @Test func aChoiceWhosePaymentsCannotBeConvertedIsStoredAndSaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let id = try await database.saveInvoice(paidDollarInvoiceOf2025())
        try await database.makeUnreadable(paymentOf: id)

        #expect(await app.setFXMethod(.uniform, year: 2025) == .paymentsNotConverted(year: 2025))

        #expect(try await database.yearSettings(2025).incomeFXMethod == .uniform)
    }

    /// The payments of a later year that takes the choice cannot be converted: what the choice says names that year,
    /// not the year chosen, whose payments are converted, as are those of the years after the one that failed.
    @Test func aChoiceWhoseLaterYearCannotBeConvertedNamesThatYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await storeDollarRatesOf2022To2024(in: database)
        // Settings of 2022 alone: 2023 and the years after it take its choices.
        try await database.saveYearSettings(YearSettings(year: 2022))
        let paid = try await storeDollarsPaid(in: [2022, 2023, 2024], in: app)
        try await database.makeUnreadable(paymentOf: try #require(paid[2023]).id)

        #expect(await app.setFXMethod(.uniform, year: 2022) == .paymentsNotConverted(year: 2023))

        #expect(try await database.yearSettings(2022).incomeFXMethod == .uniform)
        #expect(try await payment(of: try #require(paid[2022]).id, in: app).conversion == .uniform)
        #expect(try await payment(of: try #require(paid[2024]).id, in: app).conversion == .uniform)

        // Nastavení › Rok of 2022 says so when the year is switched back there.
        app.selectYear(2022)
        let year = YearTabModel(app: app)
        await year.load()

        await year.setFXMethod(.cnbDaily)

        #expect(year.saveFailure == "Změna je uložená, platby roku 2023 se ale nepodařilo přepočítat.")
        #expect(try await database.yearSettings(2022).incomeFXMethod == .cnbDaily)
        #expect(try await payment(of: try #require(paid[2022]).id, in: app) == paid[2022]?.payment)
        #expect(try await payment(of: try #require(paid[2024]).id, in: app) == paid[2024]?.payment)
    }

    /// Two choices for a year made at once, as in the menu of the toolbar and in Nastavení, are made one after the
    /// other: the year ends with the choice made last, and every payment of it converted by that choice.
    @Test func choicesMadeAtOnceAreMadeOneAfterTheOther() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        // Twelve payments, so that converting them takes long enough for the two choices to meet.
        for month in 1...12 {
            let number = "2025" + (month < 10 ? "0" : "") + "\(month)01"
            let dollars = invoice(number, .usd, 100_000 * Int64(month), issued: "2025-09-30")
            try await storePaid(dollars, on: "2025-10-02", in: app)
        }

        let first = Task { await app.setFXMethod(.uniform, year: 2025) }
        let second = Task { await app.setFXMethod(.cnbDaily, year: 2025) }
        let changes = [await first.value, await second.value]

        #expect(changes == [.saved, .saved])
        #expect(try await database.yearSettings(2025).incomeFXMethod == .cnbDaily)
        let conversions = try await database.paidInvoices(year: 2025).compactMap { $0.payment?.conversion }
        #expect(conversions == Array(repeating: .cnbDaily, count: 12))
    }

    @Test func choosingWhatTheYearHasChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let version = app.dataVersion

        #expect(await app.setFXMethod(.cnbDaily, year: 2025) == .unchanged)

        #expect(app.dataVersion == version)
        #expect(try await #require(app.database).storedSettingsYears().contains(2025) == false)
    }

    // MARK: The levies with each conversion

    /// The menu of the rate capsule shows the levies of the year with each conversion. Each is what Výpočet shows once
    /// the year converts that way, whichever way it converts now, and working them out stores nothing.
    @Test func theLevyComparisonIsWhatTheYearComputesWithEachConversion() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let stored = try await storeForeignIncomeOf2025(in: app)
        app.selectYear(2025)
        let version = app.dataVersion

        let comparison = try #require(try await app.levyComparison(year: 2025))

        // Nothing is stored: the year still converts at the daily rates, and its payments are as they were.
        #expect(app.dataVersion == version)
        #expect(try await database.yearSettings(2025).incomeFXMethod == .cnbDaily)
        for invoice in stored {
            #expect(try await payment(of: invoice.id, in: app) == invoice.payment, "\(invoice.number)")
        }
        #expect(comparison.daily == (try await app.computeSelectedYear().liabilityTotal))
        // The dollars at 21,84 Kč rather than 20,618 Kč, and the euros at 24,66 Kč: more income, and more levies.
        #expect(comparison.uniform > comparison.daily)

        #expect(await app.setFXMethod(.uniform, year: 2025) == .saved)

        #expect(comparison.uniform == (try await app.computeSelectedYear().liabilityTotal))
        let onUniform = try #require(try await app.levyComparison(year: 2025))
        #expect(onUniform.daily == comparison.daily)
        #expect(onUniform.uniform == comparison.uniform)
    }

    /// The levies are those of the day shown: on 30. 9. 2025 no money in another currency has come yet, so both
    /// conversions give the levies Výpočet shows on that day.
    @Test func theLevyComparisonIsAsOfTheDayShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await storeForeignIncomeOf2025(in: app)
        app.selectYear(2025)
        app.pickAsOf(civilDate("2025-09-30"))

        let comparison = try #require(try await app.levyComparison(year: 2025))

        let levies = try await app.computeSelectedYear().liabilityTotal
        #expect(comparison.daily == levies)
        #expect(comparison.uniform == levies)
    }

    @Test func thereIsNoLevyComparisonUnlessTheYearCanUseBothConversions() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await storePaid(invoice("20261001", .usd, 1_000_000, issued: "2026-09-30"), on: "2026-10-02", in: app)
        try await takeOutTheEuroRate(of: 2025, in: app)
        try await storePaid(invoice("20251101", .eur, 200_000, issued: "2025-11-03"), on: "2025-11-10", in: app)

        // 2026 is paid in dollars, but has no uniform rate yet.
        #expect(try await app.levyComparison(year: 2026) == nil)
        // 2025 is paid in euros, and has no uniform rate of euros.
        #expect(try await app.levyComparison(year: 2025) == nil)
        // 2024 has its uniform rates, but no money came in it.
        #expect(try await app.fxState(year: 2024).uniform.isReady)
        #expect(try await app.levyComparison(year: 2024) == nil)
    }

    // MARK: The year shown

    @Test func theYearShownKnowsHowItConvertsItsIncomeInOtherCurrencies() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        #expect(app.shownYearFX == nil)
        #expect(app.shownYearFXMethod == .cnbDaily)

        await app.loadShownYearFX()
        #expect(app.shownYearFX?.year == 2026)
        #expect(app.shownYearFX?.uniform == .notPublishedYet(year: 2026))

        #expect(await app.setFXMethod(.uniform, year: 2025) == .saved)
        app.selectYear(2025)
        // What was read is of another year.
        #expect(app.shownYearFXMethod == .cnbDaily)

        await app.loadShownYearFX()
        #expect(app.shownYearFX?.year == 2025)
        #expect(app.shownYearFXMethod == .uniform)
        #expect(
            Screen.invoices.header(
                year: 2025, asOf: app.asOf.asOf, today: app.today, incomeFX: app.shownYearFXMethod
            ).subtitle == "Rok 2025 · částky bez DPH, v Kč jednotným kurzem")
    }
}

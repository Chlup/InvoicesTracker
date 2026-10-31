import Foundation
import Testing
@testable import InvoicesTracker

/// The sheet that records a payment: the income in crowns by the year's method of converting it, or by the amount the
/// bank credited; what it adds to the levies of its year; and saving it. The data is the sample year 2026 with invented
/// clients, in a temporary database; the app is as of 17. 10. 2026, and the ČNB rates are those of the fixtures, which
/// end on 16. 10. 2026. In every expected string `\u{00A0}` is the no-break space.
@Suite(.settlesBackups)
@MainActor
struct PaymentSheetModelTests {
    // MARK: Helpers

    /// An app model on a new folder with the sample year stored, as of noon of 17. 10. 2026 unless `clock` says
    /// otherwise, whose server answers what `http` says.
    private func makeApp(
        in directory: URL, clock: ManualClock = ManualClock(localNoon(2026, 10, 17)),
        http: StubHTTPClient = StubHTTPClient()
    ) async throws -> AppModel {
        let app = makeAppModel(in: directory, clock: clock, http: http)
        try await startFresh(app)
        let database = try #require(app.database)
        try await SampleYear2026.store(in: database)
        await app.didWriteAndBackUp()
        return app
    }

    /// The invoice `id` of the sample year, as it is stored, but not paid: its payment is taken away in the database
    /// too, so that the sheet records it again.
    private func unpaidInvoice(_ id: Int64, in app: AppModel) async throws -> Invoice {
        let database = try #require(app.database)
        var invoice = try #require(try await database.invoice(id: id))
        invoice.payment = nil
        try await database.saveInvoice(invoice)
        return invoice
    }

    /// An invoice of 205 hours at 70,00 USD (14 350,00 USD) that is issued and imported from Fakturoid, not changed in
    /// the app since, and paid with `payment`, or not paid when it is nil.
    private func importedDollarInvoice(
        in app: AppModel, duzp: String = "2026-09-30", invoiceRate: StoredRate? = nil,
        review: ReviewFlag? = nil, payment: Payment? = nil
    ) async throws -> Invoice {
        var invoice = Invoice.fixture(
            number: "Z20260930", currency: .usd, duzp: duzp, dueDate: "2026-10-30",
            items: [InvoiceItem(description: "Software development", quantity: decimal("205"), unit: "h", unitPriceMinor: 7_000)],
            vatMode: .outsideCountry, invoiceRate: invoiceRate, review: review, payment: payment)
        invoice.client = SampleYear2026.bravo
        invoice.source = .imported(fakturoidID: "F-1", fingerprint: "row-1", changedInApp: false)
        let database = try #require(app.database)
        invoice.id = try await database.saveInvoice(invoice)
        return invoice
    }

    /// The payment of the imported invoice in dollars as it was stored: the 14 350,00 USD came on 2. 10. 2026 and were
    /// converted at 21,305 Kč, which is not the rate of that day in the fixtures (21,795 Kč), so that a sheet that
    /// converted the payment again would show another one: 305 726,75 Kč.
    private let storedDollarPayment = Payment(
        date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 30_572_675, czkVatHalere: 0,
        rate: storedRate("USD", "21.305", declaredOn: "2026-10-02"))

    /// The Hungarian forint, which the ČNB and the GFŘ quote for 100 units.
    private let forint = CurrencyCode("HUF")!

    /// An invoice of 1 000 000,00 HUF that is issued and not paid, imported from Fakturoid, supplied on `duzp`.
    private func importedForintInvoice(in app: AppModel, duzp: String = "2026-09-30") async throws -> Invoice {
        var invoice = Invoice.fixture(
            number: "F" + duzp.replacingOccurrences(of: "-", with: ""), currency: forint, duzp: duzp,
            dueDate: "2026-12-30", items: [.fixture("1", at: 100_000_000)], vatMode: .outsideCountry)
        invoice.client = SampleYear2026.bravo
        invoice.source = .imported(fakturoidID: "F-2", fingerprint: "row-2", changedInApp: false)
        let database = try #require(app.database)
        invoice.id = try await database.saveInvoice(invoice)
        return invoice
    }

    private func setMethod(_ method: IncomeFXMethod, year: Int = 2026, in app: AppModel) async throws {
        let database = try #require(app.database)
        var settings = try await database.yearSettings(year)
        settings.incomeFXMethod = method
        try await database.saveYearSettings(settings)
    }

    /// The uniform rate of 1 unit of `currency` in 2026, `rate` crowns (an invented one), entered by hand without an
    /// instruction.
    private func manualRate(_ currency: CurrencyCode, _ rate: String) -> UniformRate {
        UniformRate(year: 2026, currency: currency, amount: 1, rate: decimal(rate), instruction: "", origin: .manual)
    }

    /// Money in euros that came in 2026: an invoice of 2 000,00 EUR paid on 5. 10. 2026 at the ČNB rate of that day, as
    /// a year that converts at the daily rates has it. The year was paid in euros, so it needs the uniform rate of
    /// euros to convert at the uniform rate.
    private func storeEurosPaidIn2026(in app: AppModel) async throws {
        let database = try #require(app.database)
        var euros = Invoice.fixture(
            number: "20260903", currency: .eur, duzp: "2026-09-30", dueDate: "2026-10-30",
            items: [.fixture("1", at: 200_000)], vatMode: .outsideCountry)
        euros.payment = try await app.convert(euros, paidOn: civilDate("2026-10-05"), method: .cnbDaily, in: database)
        #expect(euros.payment?.conversion == .cnbDaily && euros.payment?.rate != nil)
        try await database.saveInvoice(euros)
    }

    /// Money in pounds that came in 2026: an invoice of 2 000,00 GBP paid on 5. 10. 2026 at the ČNB rate of that day,
    /// as a year that converts at the daily rates has it. The sample year stores the ČNB rates of dollars and euros
    /// only, so those of pounds are stored from the fixtures here. The year was paid in pounds, so it needs the uniform
    /// rate of pounds to convert at the uniform rate, which Nastavení › Rok cannot take.
    private func storePoundsPaidIn2026(in app: AppModel) async throws {
        let database = try #require(app.database)
        let currency = try #require(CurrencyCode("GBP"))
        try await database.insertCNBRates(try cnbYearlyRows([2026]).filter { $0.currency == currency })
        var pounds = Invoice.fixture(
            number: "20260904", currency: currency, duzp: "2026-09-30", dueDate: "2026-10-30",
            items: [.fixture("1", at: 200_000)], vatMode: .outsideCountry)
        pounds.payment = try await app.convert(pounds, paidOn: civilDate("2026-10-05"), method: .cnbDaily, in: database)
        #expect(pounds.payment?.conversion == .cnbDaily && pounds.payment?.rate != nil)
        try await database.saveInvoice(pounds)
    }

    // MARK: The income in crowns

    @Test func dollarsPaidOn2October2026AreConvertedAtTheRateOfThatDay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")

        await model.recompute()

        // 14 350,00 USD at the ČNB rate 21,795 of the fixture: 312 758,25 Kč.
        let preview = try #require(model.preview)
        #expect(preview.czkNetHalere == 31_275_825)
        #expect(preview.czkVatHalere == 0)
        #expect(preview.conversion == .cnbDaily)
        #expect(preview.provisional == false)
        #expect(preview.date == civilDate("2026-10-02"))
        #expect(preview.rate == storedRate("USD", "21.795", declaredOn: "2026-10-02"))
        #expect(model.method == .cnbDaily)
        #expect(model.notice == nil)
        #expect(model.effect != nil)
    }

    @Test func theAmountTheBankCreditedIsTheIncomeInstead() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")
        model.useBankCZK = true
        model.bankCZKText = "306 000"

        await model.recompute()

        let preview = try #require(model.preview)
        #expect(preview.czkNetHalere == 30_600_000)
        #expect(preview.conversion == .bankCZK)
        #expect(preview.bankCZKTotalHalere == 30_600_000)
        #expect(preview.rate == nil)
        #expect(preview.provisional == false)
        #expect(model.notice == nil)
    }

    @Test func anAmountThatIsMissingOrNotAnAmountGivesNoPaymentToSave() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")
        model.useBankCZK = true

        // Nothing typed yet.
        await model.recompute()
        #expect(model.preview == nil)
        #expect(model.effect == nil)
        #expect(model.bankCZKError == nil)

        // A text that is not an amount says how an amount is written.
        model.bankCZKText = "1.234,50"
        await model.recompute()
        #expect(model.preview == nil)
        #expect(model.bankCZKError == "Zadejte částku ve tvaru 13 340 nebo 13 340,50.")

        // Neither is nothing at all an amount to record.
        model.bankCZKText = "0"
        await model.recompute()
        #expect(model.preview == nil)

        model.bankCZKText = "13 340,50"
        await model.recompute()
        #expect(model.preview?.czkNetHalere == 1_334_050)
        #expect(model.bankCZKError == nil)

        // The amount of the bank is only for money that came in dollars; a switch back uses the year's method.
        model.useBankCZK = false
        await model.recompute()
        #expect(model.preview?.conversion == .cnbDaily)
    }

    @Test func aYearThatConvertsByTheUniformRateOfAnUnpublishedYearUsesTheRateOfTheDayForNow() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await setMethod(.uniform, in: app)
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")

        await model.recompute()

        #expect(
            model.notice
                == "Jednotný kurz 2026: zatím nevyšel – GFŘ ho zveřejní v lednu 2027. Platba i celý rok 2026 se proto"
                + " zatím přepočtou kurzem ČNB ke dni přijetí.")
        // The year is computed at the ČNB rates of the days until it has its uniform rate: the payment is one at the
        // rate of its day, and waits for nothing.
        let preview = try #require(model.preview)
        #expect(preview.provisional == false)
        #expect(preview.conversion == .cnbDaily)
        #expect(preview.czkNetHalere == 31_275_825)
        #expect(preview.rate == storedRate("USD", "21.795", declaredOn: "2026-10-02"))
        #expect(model.method == .cnbDaily)
    }

    /// What the notice says of a year set to the uniform rate that lacks it follows where the search of the app for it
    /// stands on the day of the app, in the words of the menu of the rate capsule: on 15. 2. 2026 the app looks for the
    /// rate of 2025 once a day, and on 17. 10. 2026 it no longer looks for the rate of 2022.
    @Test func theNoticeOfAMissingUniformRateSaysWhereTheSearchForItStands() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let looking = try await makeApp(
            in: directory.appending(path: "Looking", directoryHint: .isDirectory),
            clock: ManualClock(localNoon(2026, 2, 15)))
        try await #require(looking.database).execute("DELETE FROM uniform_rate WHERE year = 2025")
        try await setMethod(.uniform, year: 2025, in: looking)
        let invoice = try await unpaidInvoice(10, in: looking)
        let sheet = PaymentSheetModel(app: looking, invoice: invoice)
        sheet.date = civilDate("2025-10-07")

        await sheet.recompute()

        let reason = "zatím nevyšel – aplikace ho jednou denně hledá"
        #expect(
            sheet.notice
                == "Jednotný kurz 2025: \(reason). Platba i celý rok 2025 se proto zatím přepočtou kurzem ČNB ke dni"
                + " přijetí.")
        // The menu of the rate capsule says the same of the year on the same day.
        let state = try await looking.fxState(year: 2025)
        #expect(RateMenuBuilder.content(state: state, comparison: nil).items[1].detail == reason)

        let over = try await makeApp(in: directory.appending(path: "Over", directoryHint: .isDirectory))
        let database = try #require(over.database)
        try await database.insertCNBRates(try cnbYearlyRows([2022]).filter { $0.currency == .usd })
        try await database.execute("DELETE FROM uniform_rate WHERE year = 2022")
        try await setMethod(.uniform, year: 2022, in: over)
        var old = Invoice.fixture(
            number: "20220601", currency: .usd, duzp: "2022-06-01", dueDate: "2022-06-15",
            items: [.fixture("10", at: 10_000)], vatMode: .outsideCountry)
        old.id = try await database.saveInvoice(old)
        let late = PaymentSheetModel(app: over, invoice: old)
        late.date = civilDate("2022-06-15")

        await late.recompute()

        #expect(
            late.notice
                == "Jednotný kurz 2022: v aplikaci není – zadáte ho v Nastavení › Rok 2022. Platba i celý rok 2022 se"
                + " proto zatím přepočtou kurzem ČNB ke dni přijetí.")
    }

    /// The year is set to the uniform rate and has the rate of dollars, but money in euros came in it already and the
    /// year lacks their rate: the whole year, this payment in dollars too, is converted at the ČNB rates of the days
    /// until the rate of euros is entered, which the notice says by naming the currency.
    @Test func theNoticeNamesAnotherPaidCurrencyWhoseUniformRateIsMissing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await #require(app.database).saveUniformRates([manualRate(.usd, "21.7")], year: 2026)
        try await setMethod(.uniform, in: app)
        try await storeEurosPaidIn2026(in: app)
        let state = try await app.fxState(year: 2026)
        #expect(state.chosen == .uniform && state.effective == .cnbDaily)
        #expect(state.uniform == .missingCurrency(.eur))
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")

        await model.recompute()

        #expect(
            model.notice
                == "Jednotný kurz 2026: chybí jednotný kurz EUR – zadáte ho v Nastavení › Rok 2026. Platba i celý rok"
                + " 2026 se proto zatím přepočtou kurzem ČNB ke dni přijetí.")
        // The year has the rate of dollars, yet the payment is one at the rate of its day, as the year is.
        let preview = try #require(model.preview)
        #expect(preview.conversion == .cnbDaily)
        #expect(preview.czkNetHalere == 31_275_825)
        #expect(preview.rate == storedRate("USD", "21.795", declaredOn: "2026-10-02"))
        #expect(model.method == .cnbDaily)
    }

    /// The year is set to the uniform rate and has the rates of dollars and euros, which are all that Nastavení › Rok
    /// takes, but money in pounds came in it already and the year lacks their rate: the notice says that the rate of
    /// pounds cannot be typed, rather than send the person to type it.
    @Test func theNoticeSaysTheRateOfAnotherPaidCurrencyCannotBeTyped() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let pounds = try #require(CurrencyCode("GBP"))
        try await #require(app.database).saveUniformRates(
            [manualRate(.usd, "21.7"), manualRate(.eur, "24.5")], year: 2026)
        try await setMethod(.uniform, in: app)
        try await storePoundsPaidIn2026(in: app)
        #expect(try await app.fxState(year: 2026).uniform == .missingCurrency(pounds))
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")

        await model.recompute()

        #expect(
            model.notice
                == "Jednotný kurz 2026: chybí jednotný kurz GBP – ručně ho zadat nelze. Platba i celý rok 2026 se proto"
                + " zatím přepočtou kurzem ČNB ke dni přijetí.")
    }

    @Test func aUniformYearWithEveryRateItNeedsShowsNoNotice() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await #require(app.database).saveUniformRates(
            [manualRate(.usd, "21.7"), manualRate(.eur, "24.5")], year: 2026)
        try await setMethod(.uniform, in: app)
        try await storeEurosPaidIn2026(in: app)
        let state = try await app.fxState(year: 2026)
        #expect(state.chosen == .uniform && state.effective == .uniform)
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")

        await model.recompute()

        #expect(model.notice == nil)
        // 14 350,00 USD at the uniform rate, 21,70 Kč: 378 448,00 Kč.
        let preview = try #require(model.preview)
        #expect(preview.conversion == .uniform)
        #expect(preview.czkNetHalere == 31_139_500)
        #expect(preview.rate?.rate.rate == decimal("21.7"))
        #expect(model.method == .uniform)
    }

    /// A year that is not set to the uniform rate converts at the ČNB rates of the days whatever uniform rates it has,
    /// so what it lacks of them is no reason to say anything.
    @Test func aYearOnTheDailyRatesSaysNothingOfTheUniformRateOfAnotherCurrency() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await #require(app.database).saveUniformRates([manualRate(.usd, "21.7")], year: 2026)
        try await storeEurosPaidIn2026(in: app)
        let state = try await app.fxState(year: 2026)
        #expect(state.chosen == .cnbDaily)
        #expect(state.uniform == .missingCurrency(.eur))
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")

        await model.recompute()

        #expect(model.notice == nil)
        let preview = try #require(model.preview)
        #expect(preview.conversion == .cnbDaily)
        #expect(preview.czkNetHalere == 31_275_825)
        #expect(model.method == .cnbDaily)
    }

    @Test func aPaymentOfAYearWaitingForItsUniformRateIsStoredAtTheRateOfItsDay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await setMethod(.uniform, in: app)
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")

        try await model.save()

        let database = try #require(app.database)
        let stored = try #require(try await database.invoice(id: 10)?.payment)
        #expect(stored.conversion == .cnbDaily)
        #expect(stored.provisional == false)
        #expect(stored.czkNetHalere == 31_275_825)
    }

    @Test func aYearThatConvertsByAPublishedUniformRateUsesIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await setMethod(.uniform, year: 2025, in: app)
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        // The uniform rate of 2025 is published: 21,84 Kč for a dollar.
        model.date = civilDate("2025-12-20")

        await model.recompute()

        #expect(model.notice == nil)
        let preview = try #require(model.preview)
        #expect(preview.provisional == false)
        #expect(preview.conversion == .uniform)
        #expect(preview.czkNetHalere == 31_340_400)
        #expect(preview.rate?.rate.rate == decimal("21.84"))
    }

    @Test func theMethodOfTheYearOfThePaymentDecidesNotTheYearShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // 2025 converts by the uniform rate, 2026 by the rate of the day.
        try await setMethod(.uniform, year: 2025, in: app)
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)

        model.date = civilDate("2026-01-02")
        await model.recompute()
        #expect(model.preview?.conversion == .cnbDaily)

        model.date = civilDate("2025-12-31")
        await model.recompute()
        #expect(model.preview?.conversion == .uniform)
    }

    @Test func aCrownInvoiceIsIncomeAtItsOwnAmounts() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-15")

        await model.recompute()

        let preview = try #require(model.preview)
        #expect(preview.conversion == .czk)
        #expect(preview.czkNetHalere == 450_000)
        #expect(preview.czkVatHalere == 94_500)
        #expect(preview.rate == nil)
        #expect(model.notice == nil)
    }

    // MARK: What the payment adds to the levies

    @Test func thePaymentOf15OctoberAddsWhatTheEngineSaysToEachAuthority() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // The last receipt of the regression year: the other ten are stored, this one is the preview.
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-15")

        await model.recompute()

        let effect = try #require(model.effect)
        #expect(effect.tax == 675)
        #expect(effect.social == 723)
        #expect(effect.health == 304)
        #expect(effect.total == 1_702)
        #expect(effect.receipt.source == .invoice(11))
        #expect(effect.receipt.day == civilDate("2026-10-15"))
        #expect(effect.receipt.czkNetHalere == 450_000)
        #expect(model.effectHeading == "Odvody za rok 2026 vzrostou o")
        #expect(model.effectTotalText == "+1\u{00A0}702\u{00A0}Kč")
        // The income of the year is past the cap of the flat-rate expenses before 15. 10., so all of the payment is.
        #expect(
            model.effectShareText
                == "37,8\u{00A0}% z příjmu 4\u{00A0}500,00\u{00A0}Kč."
                + " Celá platba je nad stropem paušálu (příjmy 2\u{00A0}mil.\u{00A0}Kč), kde je celý další příjem ziskem.")
        #expect(model.effectRows.map(\.title) == ["Daň z příjmů", "Sociální pojištění", "Zdravotní pojištění"])
        #expect(model.effectRows.map(\.value) == ["+675", "+723", "+304"])
    }

    @Test func aStoredPaymentThatIsEditedIsNotCountedTwice() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // Invoice 11 keeps its stored payment: the preview replaces the receipt of the same invoice.
        let database = try #require(app.database)
        let stored = try #require(try await database.invoice(id: 11))
        let model = PaymentSheetModel(app: app, invoice: stored)
        #expect(model.date == civilDate("2026-10-15"))

        await model.recompute()

        // The payment as it is stored, which adds to the levies what the detail says it does.
        #expect(model.preview == stored.payment)
        #expect(model.effect?.total == 1_702)
        #expect(model.effect?.receipt.source == .invoice(11))
    }

    @Test func aPaymentOfAnotherYearAddsToTheLeviesOfThatYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        // 2025 has no receipts and no settings of its own in this database.
        model.date = civilDate("2025-12-30")

        await model.recompute()

        #expect(model.effect?.receipt.day == civilDate("2025-12-30"))
        #expect(model.effectHeading == "Odvody za rok 2025 vzrostou o")
    }

    // MARK: The date

    @Test func theDateStartsAtTheDayShownOrTheDayOfIssueWhenThatIsLater() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(11, in: app)

        // The day shown, 17. 10. 2026, is after the day of issue, 30. 9. 2026.
        #expect(PaymentSheetModel(app: app, invoice: invoice).date == civilDate("2026-10-17"))

        // As of 1. 6. the invoice is not issued yet: the money cannot come before it.
        app.pickAsOf(civilDate("2026-06-01"))
        #expect(PaymentSheetModel(app: app, invoice: invoice).date == civilDate("2026-09-30"))
    }

    // MARK: A rate that is not there yet

    @Test func anImportedInvoiceWithoutARateUsesTheLatestRateOfItsDUZPUntilTheDayIsDeclared() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await importedDollarInvoice(in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        // The ČNB has not declared the rate of 30. 10. 2026 yet: the rates in the database end on 16. 10.
        model.date = civilDate("2026-10-30")

        await model.recompute()

        // The latest rate on or before the DUZP, 30. 9. 2026, is 21,522: 14 350,00 USD are 308 840,70 Kč, never nothing.
        let preview = try #require(model.preview)
        #expect(preview.provisional == true)
        #expect(preview.conversion == .cnbDaily)
        #expect(preview.rate == storedRate("USD", "21.522", declaredOn: "2026-09-30"))
        #expect(preview.czkNetHalere == 30_884_070)
        // The stand-in is not the rate of the invoice: the invoice keeps none.
        #expect(invoice.invoiceRate == nil)
    }

    @Test func withoutAnyRateAtAllThereIsNoPaymentToSave() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        try await startFresh(app)
        let database = try #require(app.database)
        // No ČNB rate is stored at all.
        var invoice = Invoice.fixture(
            number: "20260930", currency: .usd, duzp: "2026-09-30", dueDate: "2026-10-30",
            items: [InvoiceItem(description: "Software development", quantity: decimal("205"), unit: "h", unitPriceMinor: 7_000)],
            vatMode: .outsideCountry)
        invoice.client = SampleYear2026.bravo
        invoice.id = try await database.saveInvoice(invoice)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")

        await model.recompute()

        #expect(model.preview == nil)
        #expect(model.effect == nil)
        #expect(model.notice == "Kurz ČNB ke dni přijetí zatím není k dispozici – bez něj nejde příjem přepočítat. Počkejte na stažení kurzů nebo zadejte částku v Kč podle banky.")
        await #expect(throws: PaymentSheetError.noPayment) {
            try await model.save()
        }
    }

    // MARK: The texts of the options

    @Test func theOptionsNameTheMethodOfTheYearAndTheAmountOfTheBank() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")
        await model.recompute()

        #expect(
            model.methodOption
                == PaymentOption(
                    title: "Kurz ČNB ke dni přijetí", detail: "2.\u{00A0}10.\u{00A0}2026 · 21,795\u{00A0}Kč/USD",
                    value: "312\u{00A0}758,25\u{00A0}Kč"))
        #expect(
            model.bankOption
                == PaymentOption(title: "Částka v Kč podle banky", detail: "jen když peníze přišly přímo v Kč", value: "—"))

        model.useBankCZK = true
        model.bankCZKText = "306 000"
        await model.recompute()

        // The option of the method keeps its value while the bank's amount is chosen.
        #expect(model.methodOption?.value == "312\u{00A0}758,25\u{00A0}Kč")
        #expect(model.bankOption?.value == "306\u{00A0}000,00\u{00A0}Kč")
    }

    @Test func theOptionOfAnUnpublishedUniformRateStillNamesTheRateOfTheDay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await setMethod(.uniform, in: app)
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")

        await model.recompute()

        // The rate of the day is declared; only the uniform rate is not. The notice says so under the options.
        #expect(
            model.methodOption
                == PaymentOption(
                    title: "Kurz ČNB ke dni přijetí", detail: "2.\u{00A0}10.\u{00A0}2026 · 21,795\u{00A0}Kč/USD",
                    value: "312\u{00A0}758,25\u{00A0}Kč"))
        #expect(model.usesStandInRate == false)
    }

    @Test func theOptionOfARateThatStandsInSaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await importedDollarInvoice(in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-30")

        await model.recompute()

        #expect(model.usesStandInRate == true)
        #expect(
            model.methodOption?.detail == "30.\u{00A0}10.\u{00A0}2026 · kurz zatím nevyhlášen, předběžně 21,522\u{00A0}Kč/USD")
    }

    @Test func aRateNotDeclaredYetOnTheDayItselfSaysSoAndFetchesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient()
        // Monday 19. 10. 2026 at 10:00 in Prague: the rates of the day come after 14:30.
        let app = try await makeApp(in: directory, clock: ManualClock(date("2026-10-19T08:00:00Z")), http: server)
        let invoice = try await importedDollarInvoice(in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-19")

        await model.recompute()

        #expect(model.usesStandInRate)
        #expect(
            model.methodOption?.detail == "19.\u{00A0}10.\u{00A0}2026 · kurz zatím nevyhlášen, předběžně 21,522\u{00A0}Kč/USD")
        #expect(server.requests.isEmpty)
    }

    /// The dollars of an invoice imported with the rate of its export, paid on 20. 3. 2025, when the database holds no
    /// rate of 2025: an app whose server answers `http`.
    private func paymentOfAYearNotDownloaded(
        http: StubHTTPClient, in directory: URL
    ) async throws -> (app: AppModel, model: PaymentSheetModel) {
        let app = try await makeApp(in: directory, http: http)
        let database = try #require(app.database)
        try await database.execute("DELETE FROM cnb_rate WHERE declared_on < '2026-01-01'")
        let invoice = try await importedDollarInvoice(
            in: app, duzp: "2025-03-03", invoiceRate: storedRate("USD", "23.5", declaredOn: "2025-03-03"))
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2025-03-20")
        return (app, model)
    }

    @Test func aRateDeclaredButNotDownloadedIsFetchedOnceAndSaysSoWhileItIsMissing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        // The yearly file of 2025 cannot be had: the server answers nothing.
        let server = StubHTTPClient()
        let (_, model) = try await paymentOfAYearNotDownloaded(http: server, in: directory)

        await model.recompute()

        #expect(server.requests == [CNBEndpoints.yearly(2025)])
        #expect(model.usesStandInRate)
        #expect(
            model.methodOption?.detail
                == "20.\u{00A0}3.\u{00A0}2025 · kurz ČNB zatím není stažený, předběžně 23,500\u{00A0}Kč/USD")
        #expect(model.preview?.provisional == true)

        // Another day of the same year asks no more.
        model.date = civilDate("2025-03-21")
        await model.recompute()
        #expect(server.requests == [CNBEndpoints.yearly(2025)])
    }

    @Test func aRateDeclaredButNotDownloadedIsFetchedAndTheSheetShowsIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient([
            CNBEndpoints.yearly(2025): try Data(contentsOf: fixtureURL("cnb_rok_2025", "txt"))
        ])
        let (_, model) = try await paymentOfAYearNotDownloaded(http: server, in: directory)

        await model.recompute()

        #expect(server.requests == [CNBEndpoints.yearly(2025)])
        let rate = try #require(
            try cnbYearlyRows([2025]).first { $0.currency == .usd && $0.declaredOn == civilDate("2025-03-20") })
        #expect(model.usesStandInRate == false)
        #expect(
            model.methodOption?.detail == "20.\u{00A0}3.\u{00A0}2025 · \(CzechFormat.rate(rate.rate))\u{00A0}Kč/USD")
        let preview = try #require(model.preview)
        #expect(preview.provisional == false)
        #expect(preview.rate == StoredRate(rate: rate.exchangeRate, declaredOn: civilDate("2025-03-20")))
    }

    // MARK: The day the money arrived

    @Test func aSheetOpenedWhileTheDayShownIsAfterTodayStartsOnToday() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        app.pickAsOf(civilDate("2026-12-31"))
        #expect(app.asOf.asOf == civilDate("2026-12-31"))
        let invoice = try await unpaidInvoice(11, in: app)

        let model = PaymentSheetModel(app: app, invoice: invoice)

        #expect(model.date == civilDate("2026-10-17"))
        #expect(model.dateError == nil)
    }

    @Test func aSheetOfAnInvoiceIssuedAfterTodayStartsOnToday() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        var invoice = Invoice.fixture(number: "20261101", duzp: "2026-11-02", dueDate: "2026-11-16")
        invoice.id = try await database.saveInvoice(invoice)

        let model = PaymentSheetModel(app: app, invoice: invoice)

        #expect(model.date == civilDate("2026-10-17"))
        #expect(model.dateError == nil)
    }

    @Test func theDayCanBeTodayButNotLater() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)

        model.date = civilDate("2026-10-17")
        #expect(model.dateError == nil)

        model.date = civilDate("2026-10-18")
        #expect(model.dateError == "Datum přijetí nemůže být později než dnes.")
        await model.recompute()
        #expect(model.preview != nil)
        await #expect(throws: PaymentSheetError.dateOutOfRange("Datum přijetí nemůže být později než dnes.")) {
            try await model.save()
        }
        #expect(try await #require(app.database).invoice(id: 11)?.payment == nil)

        model.date = civilDate("2026-10-17")
        try await model.save()
        #expect(try await #require(app.database).invoice(id: 11)?.payment?.date == civilDate("2026-10-17"))
    }

    @Test func theDayCanBeAYearBeforeTheInvoiceWasIssuedButNotEarlier() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // Issued on 30. 9. 2026.
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)

        model.date = civilDate("2025-09-30")
        #expect(model.dateError == nil)
        model.date = civilDate("2026-03-01")
        #expect(model.dateError == nil)

        model.date = civilDate("2025-09-29")
        #expect(model.dateError == "Datum přijetí je víc než rok před vystavením faktury.")
        await model.recompute()
        await #expect(throws: PaymentSheetError.dateOutOfRange("Datum přijetí je víc než rok před vystavením faktury.")) {
            try await model.save()
        }
        #expect(try await #require(app.database).invoice(id: 11)?.payment == nil)
    }

    @Test func aYearBeforeTheDayOfIssueIsTheSameDayAYearEarlierOrThe28thOfFebruary() {
        #expect(PaymentSheetModel.earliestDay(issuedOn: civilDate("2026-12-15")) == civilDate("2025-12-15"))
        #expect(PaymentSheetModel.earliestDay(issuedOn: civilDate("2028-02-29")) == civilDate("2027-02-28"))
        #expect(PaymentSheetModel.earliestDay(issuedOn: civilDate("2027-03-01")) == civilDate("2026-03-01"))
        #expect(PaymentSheetModel.earliestDay(issuedOn: civilDate("2026-01-01")) == civilDate("2025-01-01"))
    }

    @Test func theUniformOptionNamesTheRateAndTheYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await setMethod(.uniform, year: 2025, in: app)
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2025-12-20")

        await model.recompute()

        #expect(
            model.methodOption
                == PaymentOption(
                    title: "Jednotný kurz za rok 2025", detail: "21,840\u{00A0}Kč/USD · přepočet zvolený pro rok 2025",
                    value: "313\u{00A0}404,00\u{00A0}Kč"))
    }

    @Test func theUniformOptionOfACurrencyQuotedForManyUnitsNamesTheQuantity() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // The table of 2025 that comes with the app has 6,22 Kč for 100 HUF.
        let database = try #require(app.database)
        #expect(
            try await database.uniformRate(forint, year: 2025)?.exchangeRate
                == ExchangeRate(currency: forint, amount: 100, rate: decimal("6.22")))
        try await setMethod(.uniform, year: 2025, in: app)
        let invoice = try await importedForintInvoice(in: app, duzp: "2025-11-28")
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2025-12-20")

        await model.recompute()

        // 1 000 000,00 HUF are 62 200,00 Kč at 6,22 Kč for 100 HUF.
        #expect(
            model.methodOption
                == PaymentOption(
                    title: "Jednotný kurz za rok 2025",
                    detail: "6,220\u{00A0}Kč/100 HUF · přepočet zvolený pro rok 2025",
                    value: "62\u{00A0}200,00\u{00A0}Kč"))
    }

    @Test func theOptionsOfACurrencyQuotedForManyUnitsNameTheQuantityOfTheRateOfTheDayAndOfOneThatStandsIn()
        async throws
    {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await #require(app.database).insertCNBRates(try cnbYearlyRows([2026]).filter { $0.currency == forint })
        let invoice = try await importedForintInvoice(in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)

        // The rate of the day is declared: 6,626 Kč for 100 HUF on 2. 10. 2026.
        model.date = civilDate("2026-10-02")
        await model.recompute()

        #expect(model.usesStandInRate == false)
        #expect(
            model.methodOption
                == PaymentOption(
                    title: "Kurz ČNB ke dni přijetí", detail: "2.\u{00A0}10.\u{00A0}2026 · 6,626\u{00A0}Kč/100 HUF",
                    value: "66\u{00A0}260,00\u{00A0}Kč"))

        // The rate of 30. 10. 2026 is not declared yet: the latest rate up to the DUZP, 30. 9. 2026, stands in.
        model.date = civilDate("2026-10-30")
        await model.recompute()

        #expect(model.usesStandInRate)
        #expect(
            model.methodOption?.detail
                == "30.\u{00A0}10.\u{00A0}2026 · kurz zatím nevyhlášen, předběžně 6,674\u{00A0}Kč/100 HUF")
    }

    @Test func theSheetOfAnInvoiceThatIsPaidChangesItsPayment() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try #require(try await app.database?.invoice(id: 11))
        let model = PaymentSheetModel(app: app, invoice: invoice)

        #expect(invoice.payment != nil)
        #expect(model.title == "Upravit platbu")
        #expect(model.date == invoice.payment?.date)
    }

    @Test func editingSaysUlozitPlatbuAndNamesTheImpactOfThePayment() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try #require(try await app.database?.invoice(id: 11))
        let model = PaymentSheetModel(app: app, invoice: invoice)

        #expect(model.isEditing)
        #expect(model.title == "Upravit platbu")
        #expect(model.saveTitle == "Uložit platbu")
        #expect(model.effectHeading == "Dopad platby na odvody 2026")

        // The year is that of the day in the sheet.
        model.date = civilDate("2025-12-30")
        #expect(model.effectHeading == "Dopad platby na odvody 2025")
    }

    @Test func aNewPaymentSaysOznacitJakoUhrazenou() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)

        #expect(model.isEditing == false)
        #expect(model.title == "Označit jako uhrazenou")
        #expect(model.saveTitle == "Označit jako uhrazenou")
        #expect(model.effectHeading == "Odvody za rok 2026 vzrostou o")
    }

    @Test func aCrownInvoiceHasNoOptionsAndSaysWhatTheIncomeIs() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-15")
        await model.recompute()

        #expect(model.methodOption == nil)
        #expect(model.bankOption == nil)
        #expect(
            model.crownText
                == "Příjem 4\u{00A0}500,00\u{00A0}Kč, DPH 945,00\u{00A0}Kč patří do přiznání k DPH za září.")
        #expect(model.title == "Označit jako uhrazenou")
        #expect(model.subtitle == "Faktura 20260902 · Cetus Data s.r.o. · 5\u{00A0}445,00\u{00A0}Kč")
    }

    // MARK: Saving

    /// The detail of the invoice shows what was saved; no banner says so (`savingANewPaymentShowsNoBanner`).
    @Test func savingStoresThePaymentTellsOfTheWriteAndOpensTheDetail() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        app.screen = .invoices
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-15")
        await model.recompute()
        let versionBefore = app.dataVersion
        let changesBefore = app.changeCount

        try await model.save()

        let database = try #require(app.database)
        let stored = try #require(try await database.invoice(id: 11))
        #expect(stored.payment?.date == civilDate("2026-10-15"))
        #expect(stored.payment?.czkNetHalere == 450_000)
        #expect(stored.payment?.conversion == .czk)
        #expect(app.dataVersion > versionBefore)
        #expect(app.changeCount > changesBefore)
        #expect(app.pendingDetailInvoiceID == 11)
        // The payment counts as income: it is among the receipts of the year.
        let receipts = try await database.receipts(year: 2026)
        #expect(receipts.contains { $0.source == .invoice(11) && $0.czkNetHalere == 450_000 })
    }

    @Test func savingANewPaymentShowsNoBanner() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        app.screen = .invoices
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-15")
        await model.recompute()

        try await model.save()

        #expect(try await #require(app.database).invoice(id: 11)?.payment?.date == civilDate("2026-10-15"))
        #expect(app.banner == nil)
    }

    /// Nothing in the window picks a day any more, and the sheet never moves the day shown, not even for money that
    /// came after it, which only a test can show.
    @Test func aPaymentAfterTheDayShownLeavesTheDayShownAlone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        app.pickAsOf(civilDate("2026-10-01"))
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-15")
        await model.recompute()

        try await model.save()

        #expect(try await #require(app.database).invoice(id: 11)?.payment?.date == civilDate("2026-10-15"))
        #expect(app.asOf.asOf == civilDate("2026-10-01"))
        #expect(app.asOf.year == 2026)
    }

    @Test func aPaymentOfAnotherYearLeavesTheDayShownAlone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        app.selectYear(2025)
        app.pickAsOf(civilDate("2025-06-30"))
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        // Money that came after the day shown, but in a later year than the one shown.
        model.date = civilDate("2026-10-15")
        await model.recompute()

        try await model.save()

        #expect(app.asOf.asOf == civilDate("2025-06-30"))
    }

    @Test func savingAnImportedInvoiceMarksItChangedInTheApp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await importedDollarInvoice(in: app, invoiceRate: storedRate("USD", "21.522", declaredOn: "2026-09-30"))
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")
        await model.recompute()

        try await model.save()

        let database = try #require(app.database)
        let stored = try #require(try await database.invoice(id: invoice.id))
        #expect(stored.source == .imported(fakturoidID: "F-1", fingerprint: "row-1", changedInApp: true))
        #expect(stored.payment?.czkNetHalere == 31_275_825)
    }

    @Test func savingAnInvoiceCreatedInTheAppKeepsItsSource() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-15")
        await model.recompute()

        try await model.save()

        let database = try #require(app.database)
        #expect(try await database.invoice(id: 11)?.source == .app)
    }

    @Test func recordingAPaymentResolvesAnInvoiceToCheck() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await importedDollarInvoice(
            in: app, invoiceRate: storedRate("USD", "21.522", declaredOn: "2026-09-30"),
            review: ReviewFlag(reason: "neznámý stav faktury"))
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")
        await model.recompute()
        #expect(model.effect != nil)

        try await model.save()

        let database = try #require(app.database)
        let stored = try #require(try await database.invoice(id: invoice.id))
        #expect(stored.review == nil)
        #expect(stored.source == .imported(fakturoidID: "F-1", fingerprint: "row-1", changedInApp: true))
        // It counts now.
        let receipts = try await database.receipts(year: 2026)
        #expect(receipts.contains { $0.source == .invoice(invoice.id) })
    }

    @Test func aProvisionalPaymentIsStoredAsSuchSoThatTheRefreshWorksItOutAgain() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        // Monday 19. 10. 2026 at 10:00 in Prague: the rates of the day come after 14:30.
        let app = try await makeApp(in: directory, clock: ManualClock(date("2026-10-19T08:00:00Z")))
        let invoice = try await importedDollarInvoice(in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-19")
        await model.recompute()

        try await model.save()

        let database = try #require(app.database)
        let stored = try #require(try await database.invoice(id: invoice.id))
        #expect(stored.payment?.provisional == true)
        #expect(try await database.provisionalPayments().map(\.id) == [invoice.id])
    }

    @Test func aPaymentThatCannotBeWorkedOutIsNotSaved() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(10, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-02")
        model.useBankCZK = true
        await model.recompute()

        await #expect(throws: PaymentSheetError.noPayment) {
            try await model.save()
        }

        let database = try #require(app.database)
        #expect(try await database.invoice(id: 10)?.payment == nil)
    }

    @Test func anInvoiceDeletedWhileTheSheetWasOpenIsNotBroughtBack() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-15")
        await model.recompute()
        let database = try #require(app.database)
        try await database.deleteInvoice(id: 11)

        await #expect(throws: InvoiceError.notFound) {
            try await model.save()
        }

        #expect(try await database.invoice(id: 11) == nil)
        #expect(app.banner == nil)
        #expect(app.pendingDetailInvoiceID == nil)
        #expect(PaymentSheetModel.failureText(for: InvoiceError.notFound) == "Faktura mezitím byla smazána.")
    }

    @Test func anInvoiceChangedWhileTheSheetWasOpenIsNotOverwritten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await unpaidInvoice(11, in: app)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-15")
        await model.recompute()
        // Another change of the invoice is saved meanwhile.
        let database = try #require(app.database)
        var changed = invoice
        changed.note = "Změněná poznámka"
        try await database.saveInvoice(changed)

        await #expect(throws: PaymentSheetError.invoiceChanged) {
            try await model.save()
        }

        let stored = try #require(try await database.invoice(id: 11))
        #expect(stored.note == "Změněná poznámka")
        #expect(stored.payment == nil)
        #expect(
            PaymentSheetModel.failureText(for: PaymentSheetError.invoiceChanged)
                == "Faktura se mezitím změnila. Zavřete toto okno a zkuste to znovu.")
    }

    // MARK: Changing a stored payment

    /// While the day and the way of converting are as stored, the sheet shows the payment as it is stored, with its
    /// rate, and saving it writes nothing: the invoice stays as the import left it, and the app is told of no write.
    @Test func openingAndSavingAStoredPaymentChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await importedDollarInvoice(in: app, payment: storedDollarPayment)
        let changesBefore = app.changeCount
        let versionBefore = app.dataVersion
        let model = PaymentSheetModel(app: app, invoice: invoice)

        await model.recompute()

        #expect(model.preview == storedDollarPayment)
        #expect(
            model.methodOption
                == PaymentOption(
                    title: "Kurz ČNB ke dni přijetí", detail: "2.\u{00A0}10.\u{00A0}2026 · 21,305\u{00A0}Kč/USD",
                    value: "305\u{00A0}726,75\u{00A0}Kč"))
        // What the stored payment adds to the levies, as the detail of the invoice says it.
        #expect(model.effect?.receipt.czkNetHalere == 30_572_675)

        try await model.save()

        let database = try #require(app.database)
        let stored = try #require(try await database.invoice(id: invoice.id))
        #expect(stored == invoice)
        #expect(stored.source == .imported(fakturoidID: "F-1", fingerprint: "row-1", changedInApp: false))
        #expect(app.banner == nil)
        #expect(app.changeCount == changesBefore)
        #expect(app.dataVersion == versionBefore)
        #expect(app.pendingDetailInvoiceID == nil)
    }

    /// A payment stored at a rate that stood in for the rate of its day is kept with that rate as well, also once the
    /// rate of the day is there: only another day or another way of converting works it out again. The app converts
    /// it again when the rates come (`AppModel.ratesUpdated()`), not the sheet.
    @Test func aProvisionalStoredPaymentIsKeptWhileNothingChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // Stored while the rate of 2. 10. 2026 was not there yet, at the latest rate up to the DUZP, 21,522 Kč of
        // 30. 9. 2026: 308 840,70 Kč. The rate of 2. 10., 21,795 Kč, has come since.
        let provisional = Payment(
            date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 30_884_070, czkVatHalere: 0,
            rate: storedRate("USD", "21.522", declaredOn: "2026-09-30"), provisional: true)
        let invoice = try await importedDollarInvoice(in: app, payment: provisional)
        let model = PaymentSheetModel(app: app, invoice: invoice)

        await model.recompute()

        #expect(model.preview == provisional)
        #expect(model.usesStandInRate)
        // The rate of the day is not why the payment stands in any more: the option says only that it does.
        #expect(
            model.methodOption
                == PaymentOption(
                    title: "Kurz ČNB ke dni přijetí",
                    detail: "2.\u{00A0}10.\u{00A0}2026 · předběžně 21,522\u{00A0}Kč/USD",
                    value: "308\u{00A0}840,70\u{00A0}Kč"))

        // Another day is worked out afresh, at the rate of that day; the stored day brings the stored payment back.
        model.date = civilDate("2026-10-05")
        await model.recompute()
        #expect(model.preview?.provisional == false)
        #expect(model.preview?.rate == storedRate("USD", "21.834", declaredOn: "2026-10-05"))
        model.date = civilDate("2026-10-02")
        await model.recompute()
        #expect(model.preview == provisional)

        let changesBefore = app.changeCount
        try await model.save()

        let database = try #require(app.database)
        #expect(try await database.invoice(id: invoice.id) == invoice)
        #expect(try await database.provisionalPayments().map(\.id) == [invoice.id])
        #expect(app.changeCount == changesBefore)
    }

    /// A provisional payment of a year whose rates are not downloaded is kept as it is too, and says why its rate
    /// stands in. The sheet asks for no yearly file for it: the payment needs no rate, and the rates would make the app
    /// convert the stored payment under the open sheet. The refresh fetches the files that provisional payments wait
    /// for.
    @Test func aKeptPaymentWaitingForARateThatIsNotDownloadedAsksForNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let server = StubHTTPClient([
            CNBEndpoints.yearly(2025): try Data(contentsOf: fixtureURL("cnb_rok_2025", "txt"))
        ])
        let app = try await makeApp(in: directory, http: server)
        let database = try #require(app.database)
        try await database.execute("DELETE FROM cnb_rate WHERE declared_on < '2026-01-01'")
        // 14 350,00 USD received on 20. 3. 2025 at the rate of the invoice, 23,5 Kč, until the rate of the day comes.
        let provisional = Payment(
            date: civilDate("2025-03-20"), conversion: .cnbDaily, czkNetHalere: 33_722_500, czkVatHalere: 0,
            rate: storedRate("USD", "23.5", declaredOn: "2025-03-03"), provisional: true)
        let invoice = try await importedDollarInvoice(
            in: app, duzp: "2025-03-03", invoiceRate: storedRate("USD", "23.5", declaredOn: "2025-03-03"),
            payment: provisional)
        let model = PaymentSheetModel(app: app, invoice: invoice)

        await model.recompute()

        #expect(model.preview == provisional)
        #expect(
            model.methodOption?.detail
                == "20.\u{00A0}3.\u{00A0}2025 · kurz ČNB zatím není stažený, předběžně 23,500\u{00A0}Kč/USD")
        #expect(server.requests.isEmpty)
        #expect(try await database.invoice(id: invoice.id) == invoice)
    }

    /// Another day is a new payment: it is converted at the rate of that day, and saving it writes it, which makes the
    /// imported invoice one changed in the app. No banner says so; the detail of the invoice shows it.
    @Test func changingTheDateDerivesTheConversionAfresh() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await importedDollarInvoice(in: app, payment: storedDollarPayment)
        let changesBefore = app.changeCount
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.date = civilDate("2026-10-05")

        await model.recompute()

        // 14 350,00 USD at the ČNB rate of 5. 10. 2026 in the fixtures, 21,834 Kč: 313 317,90 Kč.
        let preview = try #require(model.preview)
        #expect(preview.date == civilDate("2026-10-05"))
        #expect(preview.conversion == .cnbDaily)
        #expect(preview.rate == storedRate("USD", "21.834", declaredOn: "2026-10-05"))
        #expect(preview.czkNetHalere == 31_331_790)
        #expect(model.methodOption?.detail == "5.\u{00A0}10.\u{00A0}2026 · 21,834\u{00A0}Kč/USD")

        try await model.save()

        let database = try #require(app.database)
        let stored = try #require(try await database.invoice(id: invoice.id))
        #expect(stored.payment == preview)
        #expect(stored.source == .imported(fakturoidID: "F-1", fingerprint: "row-1", changedInApp: true))
        #expect(app.changeCount > changesBefore)
        #expect(app.pendingDetailInvoiceID == invoice.id)
        #expect(app.banner == nil)
    }

    /// The option of the rate goes on showing the payment as it is stored while the amount from the bank is chosen, as
    /// it is what choosing the rate again keeps.
    @Test func choosingTheAmountOfTheBankAndTheRateAgainKeepsTheStoredPayment() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let invoice = try await importedDollarInvoice(in: app, payment: storedDollarPayment)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        model.useBankCZK = true
        model.bankCZKText = "306 000"

        await model.recompute()

        #expect(model.preview?.conversion == .bankCZK)
        #expect(model.preview?.bankCZKTotalHalere == 30_600_000)
        #expect(model.methodOption?.detail == "2.\u{00A0}10.\u{00A0}2026 · 21,305\u{00A0}Kč/USD")
        #expect(model.methodOption?.value == "305\u{00A0}726,75\u{00A0}Kč")

        model.useBankCZK = false
        await model.recompute()

        #expect(model.preview == storedDollarPayment)
    }

    /// An amount from the bank is kept while the amount typed is the one stored, however it is written, as it is
    /// stored and not split again; another amount, or the rate of the year, is a new payment.
    @Test func aStoredAmountFromTheBankIsKeptUntilAnotherAmountIsTyped() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // Stored with a split the sheet would not make now (an invoice without VAT is all net), so that a sheet that
        // split the amount again would show another payment.
        let fromTheBank = Payment(
            date: civilDate("2026-10-02"), conversion: .bankCZK, czkNetHalere: 30_599_900, czkVatHalere: 100,
            bankCZKTotalHalere: 30_600_000)
        let invoice = try await importedDollarInvoice(in: app, payment: fromTheBank)
        let model = PaymentSheetModel(app: app, invoice: invoice)
        #expect(model.useBankCZK)
        #expect(model.bankCZKText == "306\u{00A0}000,00")

        await model.recompute()
        #expect(model.preview == fromTheBank)

        model.bankCZKText = "306000"
        await model.recompute()
        #expect(model.preview == fromTheBank)

        model.bankCZKText = "305 000"
        await model.recompute()
        #expect(model.preview?.bankCZKTotalHalere == 30_500_000)
        #expect(model.preview?.czkNetHalere == 30_500_000)

        model.bankCZKText = "306 000"
        model.useBankCZK = false
        await model.recompute()
        #expect(model.preview?.conversion == .cnbDaily)
        #expect(model.preview?.rate == storedRate("USD", "21.795", declaredOn: "2026-10-02"))

        let changesBefore = app.changeCount
        model.useBankCZK = true
        try await model.save()

        #expect(try await #require(app.database).invoice(id: invoice.id) == invoice)
        #expect(app.changeCount == changesBefore)
    }
}

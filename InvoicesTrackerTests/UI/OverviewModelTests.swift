import Foundation
import Testing
@testable import InvoicesTracker

/// The model of Přehled: what it loads from the database of an app model — the levies of the selected year as of the
/// day shown, the newest payments with what each adds to them, the invoices of the chart, the net income of each year
/// of the chart by years and of each month of the chart by months, the VAT, the uniform rates and the advance plan —
/// and what it keeps of the choices on the screen. The data is the sample year of the engine's regression test with
/// invented clients, stored in a temporary database, except where a test says it is the prediction sample; the app is
/// as of 17. 10. 2026. In every expected string `\u{00A0}` is the no-break space.
@Suite(.settlesBackups)
@MainActor
struct OverviewModelTests {
    // MARK: Helpers

    /// An app model on a new folder with the sample year stored, and one invoice of 2025 (4 500,00 Kč and 945,00 Kč
    /// VAT, paid on 10. 10. 2025), so that the years to choose from are 2026 and 2025.
    private func makeApp(in directory: URL) async throws -> AppModel {
        let app = makeAppModel(in: directory)
        try await startFresh(app)
        let database = try #require(app.database)
        try await SampleYear2026.store(in: database)
        try await database.saveInvoice(SearchFixtures.earlierCrownInvoice())
        await app.didWriteAndBackUp()
        return app
    }

    /// A model of `app` that has loaded.
    private func loadedModel(of app: AppModel) async -> OverviewModel {
        let model = OverviewModel(app: app)
        await model.load()
        return model
    }

    /// Writes the months of 2026 without the health insurance minimum as the text the table keeps them in, which is how
    /// the data is changed outside the app.
    private nonisolated func storeHealthExemptMonths(_ text: String, in database: Database) async throws {
        try await database.write { connection in
            try connection.run(
                "UPDATE year_settings SET health_exempt_months = ? WHERE year = ?", [.text(text), .integer(2026)])
        }
    }

    /// Writes an income adjustment dated 30. 2. 2025, a day that does not exist, as a change of the data outside the
    /// app could write it. The year 2025 finds it by its dates, so the receipts of 2025 cannot be read. Nothing else of
    /// Přehled reads the adjustments of a year other than the selected one.
    private nonisolated func storeAnAdjustmentOfADayThatIsNone(in database: Database) async throws {
        try await database.write { connection in
            try connection.run(
                "INSERT INTO income_adjustment(date, amount_halere, description) VALUES (?, ?, ?)",
                [.text("2025-02-30"), .integer(5_000_000), .text("Mimo faktury")])
        }
    }

    /// The column of `year` in the chart of `model`, which is the chart by years.
    private func column(ofYear year: Int, in model: OverviewModel) throws -> ChartColumn {
        try #require(model.data?.columns.first { $0.label == String(year) })
    }

    /// Month and year chart loads use the injected real day even though the reporting cutoff is month end.
    @Test func futureIssueRatesAreCappedAtRealTodayInBothChartModes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory, clock: ManualClock(localNoon(2026, 10, 28)))
        try await startFresh(app)
        let database = try #require(app.database)
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2026-10-27"), currency: .usd, amount: 1, rate: decimal("20")),
            CNBRateRow(declaredOn: civilDate("2026-10-29"), currency: .usd, amount: 1, rate: decimal("30")),
            CNBRateRow(declaredOn: civilDate("2026-10-30"), currency: .usd, amount: 1, rate: decimal("40")),
        ])
        try await database.saveInvoice(
            Invoice.fixture(
                currency: .usd, issued: "2026-10-31", duzp: "2026-10-31",
                items: [InvoiceItem.fixture("1", at: 10_000)], vatMode: .outsideCountry))
        await app.didWriteAndBackUp()
        #expect(app.today == civilDate("2026-10-28"))
        #expect(app.asOf.asOf == civilDate("2026-10-31"))
        let model = await loadedModel(of: app)
        let october = try #require(model.data?.columns[9])
        #expect(october.issuedNetHalere == 200_000)
        #expect(october.issuedIsApproximate)
        #expect(october.receivedNetHalere == 0)

        await model.setChartMode(.years)
        let year = try column(ofYear: 2026, in: model)
        #expect(year.issuedNetHalere == 200_000)
        #expect(year.issuedIsApproximate)
        #expect(year.receivedNetHalere == 0)
    }

    // MARK: The headline

    @Test func headlineFromDatabase() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        #expect(app.years == [2026, 2025])
        let model = OverviewModel(app: app)
        #expect(model.data == nil)

        await model.load()

        let data = try #require(model.data)
        #expect(data.keyFigure.eyebrow == "Zbývá zaplatit")
        #expect(data.keyFigure.figure == CzechFormat.wholeKc(110_844))
        #expect(data.levies.total == CzechFormat.wholeKc(320_664))
        #expect(model.rulesWarning == nil)
        #expect(model.errorText == nil)

        // The five newest payments of the year, each with what the engine says it adds to the levies on its day.
        let latest = data.latestReceipts
        #expect(latest.count == 5)
        #expect(latest.first?.effect == "+1\u{00A0}702\u{00A0}Kč")
        #expect(
            latest.map(\.effect) == [
                "+1\u{00A0}702\u{00A0}Kč", "+88\u{00A0}714\u{00A0}Kč", "+42\u{00A0}265\u{00A0}Kč",
                "+681\u{00A0}Kč", "+40\u{00A0}651\u{00A0}Kč",
            ])
        #expect(latest.map(\.number) == ["20260902", "20260901", "20260802", "20260801", "20260701"])
        #expect(
            latest.map(\.client) == [
                "Cetus Data s.r.o.", "Bravo Labs, Inc.", "Bravo Labs, Inc.", "Cetus Data s.r.o.", "Bravo Labs, Inc.",
            ])
        #expect(
            latest.map(\.date) == ["15.\u{00A0}10.", "2.\u{00A0}10.", "9.\u{00A0}9.", "26.\u{00A0}8.", "7.\u{00A0}8."])
        #expect(latest.map(\.invoiceID) == [11, 10, 9, 8, 7])

        // The chart starts by months: the twelve of the selected year, whatever other years there are.
        #expect(data.columns.count == 12)

        await model.setChartMode(.years)

        let years = try #require(model.data).columns
        #expect(years.count == app.years.count)
        #expect(years.map(\.label) == ["2025", "2026"])
        #expect(years.map(\.isCurrent) == [false, true])
        // 2026 is the eleven payments of the sample year, issued and received by the day shown.
        #expect(years.map(\.issuedNetHalere) == [450_000, 219_177_135])
        #expect(years.map(\.receivedNetHalere) == [450_000, 219_177_135])

        // At New Year the app moves to 2027, whose rules the app does not have yet.
        app.handleDayChanged(civilDate("2027-01-01"))
        await model.load()

        #expect(
            model.rulesWarning == "Pravidla pro rok 2027 zatím nejsou v aplikaci – výpočet je odhad podle roku 2026.")
    }

    /// Přehled and Výpočet show one bar of the levies: loaded from the same app, in a year in progress, in a year that
    /// is over and with "K datu" on another day, the two models have equal data for it.
    @Test func theLevyBarIsTheOneThatVypocetShowsForTheSameApp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let overview = OverviewModel(app: app)
        let computation = ComputationModel(app: app)

        @MainActor func expectTheSameBar(_ comment: String) async throws {
            await overview.load()
            await computation.load()
            let levies = try #require(overview.data).levies
            let page = try #require(computation.page)
            #expect(levies == page.levies, "\(comment)")
        }

        try await expectTheSameBar("2026 as of 17. 10.")
        #expect(try #require(overview.data).levies.header == "Odvody z příjmů do 17.\u{00A0}10.")

        app.pickAsOf(civilDate("2026-03-31"))
        try await expectTheSameBar("2026 as of 31. 3.")
        #expect(try #require(overview.data).levies.header == "Odvody z příjmů do 31.\u{00A0}3.")

        app.selectYear(2025)
        try await expectTheSameBar("2025")
        #expect(try #require(overview.data).levies.header == "Odvody za rok 2025")
    }

    @Test func theNewYearIsAnEstimateWithTheRulesOfTheYearBeforeIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        #expect(model.rulesWarning == nil)

        app.handleDayChanged(civilDate("2027-01-01"))
        await model.load()

        #expect(
            model.rulesWarning == "Pravidla pro rok 2027 zatím nejsou v aplikaci – výpočet je odhad podle roku 2026.")
        let data = try #require(model.data)
        #expect(data.levies.header == "Odvody z příjmů do 1.\u{00A0}1.")
        #expect(data.latestReceipts.isEmpty)
    }

    @Test func aYearBeforeTheFirstRulesIsAnEstimateWithTheRulesOfTheFirstYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = OverviewModel(app: app)

        app.selectYear(2021)
        await model.load()

        #expect(
            model.rulesWarning == "Pravidla pro rok 2021 zatím nejsou v aplikaci – výpočet je odhad podle roku 2022.")
        #expect(model.data != nil)

        app.selectYear(2022)
        await model.load()

        #expect(model.rulesWarning == nil)
    }

    // MARK: Income converted provisionally

    private let provisionalLine =
        "Část příjmů je zatím přepočtená předběžným kurzem. Přepočte se sama, až budou kurzy ČNB k dispozici."

    @Test func aProvisionalReceiptUpToTheDayShownBringsTheLineThatTheIncomeIsProvisional() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        // The dollars that arrived on 2. 10. 2026 wait for the rate of their day.
        try await #require(app.database).markPaymentProvisional(ofInvoice: 10)

        app.pickAsOf(civilDate("2026-10-01"))
        let before = await loadedModel(of: app)
        #expect(before.provisionalNotice == nil)

        app.pickAsOf(civilDate("2026-10-02"))
        let on = await loadedModel(of: app)
        #expect(on.provisionalNotice == provisionalLine)
        #expect(on.rulesWarning == nil)

        // A past year has none of them.
        app.selectYear(2025)
        await on.load()
        #expect(on.provisionalNotice == nil)
    }

    @Test func aProvisionalPaymentThatIsNoReceiptBringsNoLine() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        #expect(await loadedModel(of: app).provisionalNotice == nil)

        // An invoice to check is not income until it is resolved, whatever its payment.
        var held = try await database.markPaymentProvisional(ofInvoice: 10)
        held.review = ReviewFlag(reason: "zrušeno ve Fakturoidu")
        try await database.saveInvoice(held)

        #expect(await loadedModel(of: app).provisionalNotice == nil)
    }

    // MARK: The latest receipts

    @Test func theLatestReceiptsAreThoseUpToTheDayShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = OverviewModel(app: app)

        app.pickAsOf(civilDate("2026-10-10"))
        await model.load()

        let data = try #require(model.data)
        #expect(data.latestReceipts.map(\.number) == ["20260901", "20260802", "20260801", "20260701", "20260601"])
        #expect(
            data.latestReceipts.map(\.date) == [
                "2.\u{00A0}10.", "9.\u{00A0}9.", "26.\u{00A0}8.", "7.\u{00A0}8.", "7.\u{00A0}7.",
            ])
        #expect(data.levies.header == "Odvody z příjmů do 10.\u{00A0}10.")
    }

    @Test func anIncomeAdjustmentCountsInTheLeviesButIsNoReceiptInTheList() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let before = await loadedModel(of: app)

        try await database.saveAdjustment(
            IncomeAdjustment(date: civilDate("2026-10-16"), amountHalere: 5_000_000, description: "Mimo faktury"))
        let after = await loadedModel(of: app)

        let withoutAdjustment = try #require(before.data)
        let withAdjustment = try #require(after.data)
        let leviesWithout = withoutAdjustment.levies.parts.map(\.weight).reduce(0, +)
        let leviesWith = withAdjustment.levies.parts.map(\.weight).reduce(0, +)
        #expect(leviesWith > leviesWithout)
        #expect(withAdjustment.latestReceipts == withoutAdjustment.latestReceipts)
        #expect(withAdjustment.latestReceipts.first?.number == "20260902")
    }

    @Test func aPastYearShowsItsOwnInvoicesAndNoUpcomingPayments() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = OverviewModel(app: app)

        app.selectYear(2025)
        await model.load()

        let data = try #require(model.data)
        #expect(data.levies.header == "Odvody za rok 2025")
        #expect(data.upcoming.isEmpty)
        #expect(data.latestReceipts.map(\.number) == ["20250901"])
        #expect(data.latestReceipts.map(\.date) == ["10.\u{00A0}10."])
        #expect(data.latestReceipts.map(\.original) == ["5\u{00A0}445,00\u{00A0}Kč vč. DPH 945,00"])
        // Only the invoices of 2025 are in the chart of 2025.
        #expect(data.columns.map(\.issuedNetHalere).reduce(0, +) == 450_000)
        #expect(data.columns[8].issuedNetHalere == 450_000)
        #expect(data.columns[9].receivedNetHalere == 450_000)
    }

    // MARK: Upcoming payments and the uniform rate

    @Test func theUpcomingPaymentsAreTheAdvancesOfTheLaterMonthsAndTheVATOfTheMonthsNotDueYet() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)

        let model = await loadedModel(of: app)

        let upcoming = try #require(model.data).upcoming
        #expect(
            upcoming.map(\.title) == [
                "DPH za září", "Zálohy za listopad", "DPH za říjen", "Zálohy za prosinec",
            ])
        #expect(
            upcoming.map(\.date) == [
                civilDate("2026-10-26"), civilDate("2026-11-01"), civilDate("2026-11-25"), civilDate("2026-12-01"),
            ])
        // The VAT of September is that of the one crown invoice with VAT; the invoice of October is a draft.
        #expect(
            upcoming.map(\.amount) == [
                "945,00\u{00A0}Kč", "17\u{00A0}630\u{00A0}Kč", "0\u{00A0}Kč", "40\u{00A0}630\u{00A0}Kč",
            ])
        #expect(
            upcoming.map(\.subtitle) == [
                "přiznání a kontrolní hlášení · mimo odvody z příjmů",
                "sociální 12\u{00A0}150 · zdravotní 5\u{00A0}480",
                "podat přiznání · nic k úhradě",
                "sociální 12\u{00A0}150 · zdravotní 5\u{00A0}480 · daň 23\u{00A0}000",
            ])
        #expect(upcoming.map(\.isVAT) == [true, false, true, false])
    }

    @Test func theVATOfAMonthLeavesOutAnInvoiceToCheckAndSaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        // The one crown invoice with VAT of September is to be checked.
        var held = try #require(try await database.invoice(id: 11))
        held.review = ReviewFlag(reason: "zrušeno ve Fakturoidu")
        try await database.saveInvoice(held)

        let model = await loadedModel(of: app)

        let september = try #require(model.data?.upcoming.first { $0.title == "DPH za září" })
        #expect(september.amount == "0\u{00A0}Kč")
        #expect(september.subtitle == "faktury ke kontrole nejsou započtené")
    }

    @Test func theUniformRateLineAppearsWhenTheRateOfTheYearIsKnownAndNamesTheMethodOfTheYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        let withoutRate = try #require(model.data)
        #expect(withoutRate.uniformLine == nil)

        let rate = UniformRate(
            year: 2026, currency: .usd, amount: 1, rate: decimal("21.84"), instruction: "GFŘ-D-75", sourceURL: nil,
            confirmedAt: nil, origin: .builtIn)
        try await database.saveUniformRates([rate], year: 2026)
        await model.load()

        let line = try #require(model.data?.uniformLine)
        #expect(line.title == "Jednotný kurz za rok 2026")
        #expect(line.rates == ["1\u{00A0}USD = 21,84\u{00A0}Kč"])
        #expect(line.source == "pokyn GFŘ-D-75 · příjmy se přepočítávají denním kurzem ČNB")

        var settings = try await database.yearSettings(2026)
        settings.incomeFXMethod = .uniform
        try await database.saveYearSettings(settings)
        await model.load()

        let uniform = try #require(model.data?.uniformLine)
        #expect(uniform.source == "pokyn GFŘ-D-75 · příjmy se přepočítávají jednotným kurzem")
    }

    /// What Přehled says of the conversion of the income in other currencies follows the method each year uses: the
    /// uniform rate only once the year has it, whatever is chosen.
    @Test func theTextsOfTheConversionFollowTheMethodEachYearUses() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
        let model = await loadedModel(of: app)
        let unpaid = ", nezaplacené kurzem ČNB ke dni vystavení · podrobnosti po najetí myší"

        // 2026 does not have its uniform rate yet: it is computed at the daily rates.
        #expect(
            try #require(model.data).chartSubtitle
                == "Rok 2026 po měsících · v Kč bez DPH · cizí měny kurzem ČNB ke dni platby" + unpaid)

        // The rate of dollars, the only foreign currency of the sample year, is entered by hand.
        try await database.saveUniformRates(
            [
                UniformRate(
                    year: 2026, currency: .usd, amount: 1, rate: decimal("21.5"), instruction: "GFŘ-D-99",
                    origin: .manual)
            ], year: 2026)
        await model.load()

        #expect(
            try #require(model.data).chartSubtitle
                == "Rok 2026 po měsících · v Kč bez DPH · přijaté v cizí měně jednotným kurzem 2026" + unpaid)
        #expect(
            try #require(model.data?.uniformLine).source
                == "pokyn GFŘ-D-99, zadáno ručně · příjmy se přepočítávají jednotným kurzem")

        await model.setChartMode(.years)

        #expect(
            try #require(model.data).chartSubtitle
                == "Po letech · v Kč bez DPH · přijaté v cizí měně přepočtem zvoleným pro svůj rok" + unpaid)
    }

    // MARK: The choices of the chart

    @Test func theChartModeAndTheVATChoiceAreKeptInTheSettingsAndShownAtOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        let conversion = " · cizí měny kurzem ČNB ke dni platby, nezaplacené kurzem ČNB ke dni vystavení"
        let hover = " · podrobnosti po najetí myší"
        #expect(try #require(model.data).chartSubtitle == "Rok 2026 po měsících · v Kč bez DPH" + conversion + hover)

        await model.setChartMode(.years)

        #expect(app.appSettings.chartMode == .years)
        #expect(try await database.appSettings().chartMode == .years)
        let years = try #require(model.data)
        #expect(years.columns.count == 2)
        #expect(years.chartSubtitle == "Po letech · v Kč bez DPH" + conversion + hover)

        await model.setChartWithVAT(true)

        #expect(app.appSettings.chartWithVAT)
        #expect(try await database.appSettings().chartWithVAT)
        #expect(try #require(model.data).chartSubtitle == "Po letech · v Kč s DPH" + conversion + hover)

        // A screen that is opened later starts with the choices made.
        let later = await loadedModel(of: app)
        #expect(try #require(later.data).columns.count == 2)

        await later.setChartMode(.months)
        await later.setChartWithVAT(false)

        #expect(try #require(later.data).columns.count == 12)
        #expect(try #require(later.data).chartSubtitle == "Rok 2026 po měsících · v Kč bez DPH" + conversion + hover)
        #expect(try await database.appSettings().chartMode == .months)
        #expect(try await database.appSettings().chartWithVAT == false)
    }

    // MARK: The net income of each year of the chart

    /// The chart by years has the net income of every year it shows: the year of the page as of the day shown, which is
    /// the figure of the strip above the chart, and any other year as the engine works it out from that year's own
    /// data on the day its net income is counted to.
    @Test func theYearsChartHasTheNetIncomeOfEveryYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = OverviewModel(app: app)

        await model.setChartMode(.years)

        // 2026 as of 17. 10.: the income of 2 191 771 Kč less the levies of 320 664 Kč leaves 1 871 107 Kč.
        #expect(try column(ofYear: 2026, in: model).netIncomeHalere == 187_110_700)
        #expect(try #require(model.data).netIncome.yearValue == "1\u{00A0}871\u{00A0}107\u{00A0}Kč")
        // 2025 is over, so it is counted to its last day.
        let lastYear = try AppModel.compute(try await app.yearInput(for: 2025).input, asOf: civilDate("2025-12-31"))
        #expect(try column(ofYear: 2025, in: model).netIncomeHalere == (lastYear.P - lastYear.liabilityTotal) * 100)
        #expect(try column(ofYear: 2025, in: model).netAverage != nil)
        #expect(model.errorText == nil)
    }

    /// A column of the chart by months has the net income of the invoices paid in its month: the sum of what each of
    /// those payments leaves after the levies it adds on its own day, as the engine works them out from the data of
    /// the year. The figures for the prediction sample were worked out by a separate implementation. A day shown
    /// earlier in the year leaves the months after it with nothing, and the months before it as they were.
    @Test func theMonthsChartHasTheNetIncomeOfTheInvoicesPaidInEachMonth() async throws {
        try await PredictionSample.withStoredSample { app in
            let model = await loadedModel(of: app)

            let columns = try #require(model.data).columns
            #expect(columns.count == 12)
            #expect(columns[1].netIncomeHalere == 25_340_100)
            #expect(columns[1].netIncomeText == "253\u{00A0}401\u{00A0}Kč")
            #expect(columns[1].netIncomeNote == "součet za faktury zaplacené v měsíci")
            #expect(
                columns.map(\.netIncomeHalere) == [
                    0, 25_340_100, 17_752_100, 38_383_100, 19_084_000, 0, 26_188_500, 23_197_360, 23_716_800,
                    21_981_075, 0, 0,
                ])
            #expect(model.errorText == nil)

            app.pickAsOf(civilDate("2026-03-31"))
            await model.load()

            let untilMarch = try #require(model.data).columns
            #expect(untilMarch.map(\.netIncomeHalere) == [0, 25_340_100, 17_752_100, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            #expect(untilMarch[3].netIncomeText == "0\u{00A0}Kč")
        }
    }

    /// An income adjustment is no payment of an invoice, so no month has a net income for it, although it counts in
    /// the levies that the payments after it add. One dated after the last payment changes no month.
    @Test func anIncomeAdjustmentIsNoPaymentOfAnInvoiceInTheMonths() async throws {
        try await PredictionSample.withStoredSample { app in
            let database = try #require(app.database)
            let modelBefore = await loadedModel(of: app)
            let before = try #require(modelBefore.data).columns.map(\.netIncomeHalere)

            try await database.saveAdjustment(
                IncomeAdjustment(date: civilDate("2026-10-16"), amountHalere: 5_000_000, description: "Mimo faktury"))
            let modelAfter = await loadedModel(of: app)
            let after = try #require(modelAfter.data).columns.map(\.netIncomeHalere)

            #expect(before[1] == 25_340_100)
            #expect(after == before)
        }
    }

    /// A year that begins after the day shown has no net income yet, and a year that the day is in is counted to it.
    @Test func aYearAfterTheCutHasNoPoint() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = OverviewModel(app: app)
        app.selectYear(2025)
        app.pickAsOf(civilDate("2025-06-30"))

        await model.setChartMode(.years)

        #expect(try column(ofYear: 2026, in: model).netIncomeHalere == nil)
        #expect(try column(ofYear: 2026, in: model).netAverage == nil)
        let input = try await app.yearInput(for: 2025).input
        let midYear = try AppModel.compute(input, asOf: civilDate("2025-06-30"))
        let yearEnd = try AppModel.compute(input, asOf: civilDate("2025-12-31"))
        #expect(try column(ofYear: 2025, in: model).netIncomeHalere == (midYear.P - midYear.liabilityTotal) * 100)
        // The two days leave different figures, so the column cannot have come from the wrong day.
        #expect(midYear.P - midYear.liabilityTotal != yearEnd.P - yearEnd.liabilityTotal)
    }

    /// A year that is over and shown as of its last day is not the end of the chart: the money received since is in
    /// it, counted to today, so the year after it is worked out to today as well.
    @Test func aFinishedYearShownAsOfItsLastDayLeavesTheLaterYearCountedToToday() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = OverviewModel(app: app)
        app.selectYear(2025)

        await model.setChartMode(.years)

        #expect(app.asOf.asOf == civilDate("2025-12-31"))
        let thisYear = try AppModel.compute(try await app.yearInput(for: 2026).input, asOf: app.today)
        #expect(try column(ofYear: 2026, in: model).netIncomeHalere == (thisYear.P - thisYear.liabilityTotal) * 100)
        let lastYear = try AppModel.compute(try await app.yearInput(for: 2025).input, asOf: civilDate("2025-12-31"))
        #expect(try column(ofYear: 2025, in: model).netIncomeHalere == (lastYear.P - lastYear.liabilityTotal) * 100)
    }

    /// A year whose data the computation cannot take has no point in the chart by years, and the rest of the page
    /// loads as it does without the line. The damage is one that only the levies of 2025 read: months of its settings
    /// that no form saves would keep the whole page from loading, as the settings of every year of the chart are read
    /// for the conversion of its income too.
    @Test func aYearWhoseDataTheComputationRefusesHasNoPoint() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await storeAnAdjustmentOfADayThatIsNone(in: try #require(app.database))
        let model = OverviewModel(app: app)
        await #expect(throws: (any Error).self) { try await app.yearInput(for: 2025) }

        await model.setChartMode(.years)

        #expect(model.errorText == nil)
        #expect(try column(ofYear: 2025, in: model).netIncomeHalere == nil)
        #expect(try column(ofYear: 2025, in: model).netAverage == nil)
        #expect(try column(ofYear: 2026, in: model).netIncomeHalere == 187_110_700)
        #expect(try #require(model.data).keyFigure.figure == CzechFormat.wholeKc(110_844))
    }

    /// A year before the oldest the app has rules for, 2021, has its point in the chart by years like any other, but
    /// its hover box marks its net income and its average as an estimate and says that the engine used the rules of
    /// 2022. The banner of the page stays away, as the selected year has rules of its own, so the column is the only
    /// warning. 2026, which has rules of its own, is not marked.
    @Test func aYearWithoutRulesOfItsOwnIsMarkedInTheChartByYears() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        // An invoice shaped like the crown invoice of 2025 that `makeApp(in:)` stores, but of 2021 and paid in it.
        try await database.saveInvoice(
            Invoice.fixture(
                number: "20210901", duzp: "2021-09-30", dueDate: "2021-10-14", payment: .fixture(on: "2021-10-10")))
        await app.didWriteAndBackUp()
        #expect(app.years.contains(2021))
        let model = OverviewModel(app: app)

        await model.setChartMode(.years)

        let marked = try column(ofYear: 2021, in: model)
        #expect(marked.netAverage?.note == RulesWarning.message(year: 2021, rulesYear: 2022))
        #expect(marked.netIncomeHalere != nil)
        #expect(marked.netIncomeText?.hasPrefix("≈\u{00A0}") == true, "\(marked)")
        #expect(marked.netAverage?.value.hasPrefix("≈\u{00A0}") == true, "\(marked)")
        #expect(try column(ofYear: 2026, in: model).netAverage?.note == nil)
        #expect(model.rulesWarning == nil)
        #expect(model.errorText == nil)
    }

    // MARK: The estimate of the whole year

    /// The card of the estimate on the prediction sample, as the app is as of Saturday 17. 10. 2026: the card the
    /// builder makes from the sample's prediction. It has no chart, which the page's builder adds from the invoices and
    /// payments in the data (`theCardHasTheChartOfTheYear`).
    private func sampleCard() throws -> PredictionCardData {
        PredictionBuilder.card(try PredictionSample.outcome(year: 2026))
    }

    @Test func theCardShowsOnlyForTheCurrentYear() async throws {
        try await PredictionSample.withStoredSample { app in
            let model = OverviewModel(app: app)
            await model.load()
            let card = try #require(model.data?.prediction)
            let expected = try sampleCard()
            var withoutChart = card
            withoutChart.chart = []
            #expect(withoutChart == expected)
            #expect(card.head == "Odhad za celý rok 2026")

            // 2025 is over: its page is there, and it has no card.
            app.selectYear(2025)
            await model.load()
            #expect(model.data?.levies.header == "Odvody za rok 2025")
            #expect(model.data?.prediction == nil)

            app.selectYear(2026)
            await model.load()
            #expect(model.data?.prediction == card)

            // On the last day of the year nothing is expected any more, and there is no estimate to show.
            app.handleDayChanged(civilDate("2026-12-31"))
            await model.load()
            #expect(model.data?.levies.header == "Odvody z příjmů do 31.\u{00A0}12.")
            #expect(model.data?.prediction == nil)
            #expect(model.errorText == nil)
        }
    }

    /// "K datu" leaves the estimate as of real today. The levies follow an earlier reporting day but stop at today
    /// when the reporting day has yet to come.
    @Test func theCardIgnoresKDatu() async throws {
        try await PredictionSample.withStoredSample { app in
            let model = OverviewModel(app: app)
            await model.load()
            let card = try #require(model.data?.prediction)

            app.pickAsOf(civilDate("2026-03-31"))
            await model.load()
            #expect(model.data?.levies.header == "Odvody z příjmů do 31.\u{00A0}3.")
            #expect(model.data?.prediction == card)

            app.pickAsOf(civilDate("2026-11-30"))
            await model.load()
            #expect(model.data?.levies.header == "Odvody z příjmů do 17.\u{00A0}10.")
            #expect(model.data?.prediction == card)
            #expect(card.sub == "z faktur do 17.\u{00A0}10.\u{00A0}2026 · co ještě do 31.\u{00A0}12. přijde")
        }
    }

    /// The card has the chart of the year, twelve months of the actual figures up to today from the invoices and
    /// payments in the data and of the estimate from the prediction and the payments it expects, which were worked out
    /// for the same data by a separate implementation. "K datu" moves nothing in it: the chart is cut at today, whether
    /// the day shown is earlier in the year or has yet to come.
    @Test func theCardHasTheChartOfTheYear() async throws {
        try await PredictionSample.withStoredSample { app in
            let model = OverviewModel(app: app)
            await model.load()
            let chart = try #require(model.data?.prediction?.chart)

            try #require(chart.count == 12)
            let september = chart[8]
            #expect(september.issuedActualText == "310\u{00A0}227\u{00A0}Kč")
            #expect(september.receivedActualText == "279\u{00A0}433\u{00A0}Kč")
            #expect(september.netActualText == "237\u{00A0}168\u{00A0}Kč")
            let october = chart[9]
            #expect(october.title == "Říjen 2026 · do 17.\u{00A0}10. skutečnost, dál odhad")
            #expect(october.issuedEstimateText == "261\u{00A0}193\u{00A0}Kč")
            #expect(october.receivedActualText == "310\u{00A0}227\u{00A0}Kč")
            #expect(october.netActualText == "219\u{00A0}811\u{00A0}Kč")
            let november = chart[10]
            #expect(november.title == "Listopad 2026 · odhad")
            #expect(november.issuedEstimateText == "290\u{00A0}193\u{00A0}Kč")
            #expect(november.receivedEstimateText == "261\u{00A0}193\u{00A0}Kč")
            #expect(november.netEstimateText == "162\u{00A0}434\u{00A0}Kč")
            #expect(november.netActualText == "—")

            for day in ["2026-07-15", "2026-11-30"] {
                app.pickAsOf(civilDate(day))
                await model.load()
                #expect(model.data?.prediction?.chart == chart, "The day shown is \(day).")
            }
        }
    }

    /// The card counts the invoices up to today: when the day changes while "K datu" is on another day, the next load
    /// has the card for the new day.
    @Test func theCardIsMadeForTodayWhateverDayIsShown() async throws {
        try await PredictionSample.withStoredSample { app in
            app.pickAsOf(civilDate("2026-07-15"))
            let model = OverviewModel(app: app)
            await model.load()
            #expect(model.data?.prediction?.sub.hasPrefix("z faktur do 17.\u{00A0}10.\u{00A0}2026 ·") == true)

            app.handleDayChanged(civilDate("2026-10-18"))
            await model.load()

            #expect(app.asOf.asOf == civilDate("2026-07-15"))
            #expect(model.data?.prediction?.sub.hasPrefix("z faktur do 18.\u{00A0}10.\u{00A0}2026 ·") == true)
        }
    }

    /// The card is an extra on the page: an estimate that cannot be made leaves it out, and the rest of the page loads
    /// as it does without it.
    @Test func aCardThatCannotBeMadeIsLeftOutAndTheRestOfThePageStays() async throws {
        try await PredictionSample.withStoredSample { app in
            let database = try #require(app.database)
            let model = OverviewModel(app: app)
            await model.load()
            #expect(model.data?.prediction != nil)

            // The choices of the months cannot be read, which the estimate needs and the other cards do not.
            try await database.execute("DROP TABLE expected_invoice_month")
            await model.load()

            let data = try #require(model.data)
            #expect(data.prediction == nil)
            #expect(model.errorText == nil)
            #expect(data.keyFigure.eyebrow == "Zbývá zaplatit")
            #expect(data.latestReceipts.count == 5)
            #expect(data.columns.count == 12)
        }
    }

    // MARK: Loads that overlap

    @Test func aReloadKeepsTheDataOfTheLastLoadUntilItsOwnIsThere() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        let before = try #require(model.data)

        // The reload has started and waits for the data when its task is made.
        let reload = Task.immediate { await model.load() }

        #expect(model.data == before)

        await reload.value

        #expect(model.data == before)
    }

    @Test func aLoadThatFinishesAfterANewerOneDoesNotShowItsOlderResult() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = OverviewModel(app: app)

        // The first load is for 2026, which has five receipts to read. It has taken what it is about and waits for the
        // data when the day moves into 2027, which has nothing to read, so the second load can finish first.
        let older = Task.immediate { await model.load() }
        app.handleDayChanged(civilDate("2027-01-01"))
        let newer = Task { await model.load() }
        await older.value
        await newer.value

        #expect(model.data?.levies.header == "Odvody z příjmů do 1.\u{00A0}1.")
        #expect(model.data?.latestReceipts.isEmpty == true)
        #expect(model.rulesWarning != nil)
    }

    // MARK: When the data cannot be loaded

    @Test func aYearThatCannotBeLoadedShowsTheLineInsteadOfTheContentAndALaterLoadRecovers() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        #expect(model.data != nil)

        // A month that no form saves: the data was changed outside the app.
        try await storeHealthExemptMonths("13", in: database)
        await model.load()

        #expect(model.data == nil)
        #expect(model.rulesWarning == nil)
        #expect(model.errorText == "Přehled se nepodařilo načíst.")

        try await storeHealthExemptMonths("", in: database)
        await model.load()

        #expect(model.data?.keyFigure.figure == CzechFormat.wholeKc(110_844))
        #expect(model.errorText == nil)
    }

    @Test func aScreenWhoseDataIsLockedShowsTheLine() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        let model = OverviewModel(app: app)

        await model.load()

        #expect(model.data == nil)
        #expect(model.errorText == "Přehled se nepodařilo načíst.")
    }
}

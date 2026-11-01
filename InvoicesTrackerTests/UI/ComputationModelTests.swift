import Foundation
import Testing
@testable import InvoicesTracker

/// The model of Výpočet: what it loads from the database of an app model — the selected year with its settings and
/// receipts, as of the day shown — and turns into the sections of the breakdown. The data is the sample year of the
/// engine's regression test with invented clients, stored in a temporary database; the app is as of 17. 10. 2026. In
/// every expected string `\u{00A0}` is the no-break space.
@Suite(.settlesBackups)
@MainActor
struct ComputationModelTests {
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
    private func loadedModel(of app: AppModel) async -> ComputationModel {
        let model = ComputationModel(app: app)
        await model.load()
        return model
    }

    /// Writes the months of `year` without the health insurance minimum as the text the table keeps them in, which is
    /// how the data is changed outside the app.
    private nonisolated func storeHealthExemptMonths(
        _ text: String, year: Int = 2026, in database: Database
    ) async throws {
        try await database.write { connection in
            try connection.run(
                "UPDATE year_settings SET health_exempt_months = ? WHERE year = ?",
                [.text(text), .integer(Int64(year))])
        }
    }

    /// Stores for 2026 the family of the engine's family tests: Anna (3. 9. 2019) and Tomáš (12. 4. 2024), the first
    /// and the second child, and a spouse without income of her own, claimed the whole year.
    private nonisolated func storeTheSampleFamily(in database: Database) async throws {
        for (order, child) in [("Anna", "2019-09-03"), ("Tomáš", "2024-04-12")].enumerated() {
            try await database.saveChild(
                Child(id: nil, name: child.0, birthDate: civilDate(child.1)), year: 2026,
                childYear: ChildYear(
                    household: MonthRange.wholeYear, claimant: .me, order: order + 1, ztpp: nil, studies: nil))
        }
        try await database.saveSpouse(
            SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil), year: 2026)
    }

    private func row(_ label: String, in title: String, of model: ComputationModel) throws -> ComputationRow {
        let section = try #require(model.sections.first { $0.title == title }, "No section \(title)")
        return try #require(section.rows.first { $0.label == label }, "No row \(label) in \(title)")
    }

    private let titles = ["Příjmy a zisk", "Daň z příjmů", "Sociální pojištění", "Zdravotní pojištění", "Čistý příjem"]

    // MARK: The sample year

    @Test func theBreakdownOfTheSampleYearHasTheValuesOfTheReturn() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = ComputationModel(app: app)
        #expect(model.sections.isEmpty)

        await model.load()

        #expect(model.sections.map(\.title) == titles)
        #expect(model.warning == nil)
        #expect(model.errorText == nil)
        let rows = model.sections.flatMap(\.rows)
        // The income, the expenses with a note that the 60 % cap applied, the rounded base, the social base and the
        // two insurances.
        #expect(rows.contains { $0.value == "2\u{00A0}191\u{00A0}771,00" })
        #expect(
            rows.contains {
                $0.value == "\u{2212}1\u{00A0}200\u{00A0}000,00" && $0.note?.contains("60\u{00A0}%") == true
                    && $0.note?.contains("použije se strop") == true
            })
        #expect(rows.contains { $0.value == "835\u{00A0}200" })
        #expect(rows.contains { $0.value == "545\u{00A0}475" })
        #expect(rows.contains { $0.value == "159\u{00A0}279" })
        #expect(rows.contains { $0.value == "66\u{00A0}945" })
        // The tax and what is left to pay are those of the overview.
        #expect(try row("Daň z dosavadních příjmů", in: "Daň z příjmů", of: model).value == "94\u{00A0}440")
        #expect(try row("Zbývá", in: "Daň z příjmů", of: model).value == "71\u{00A0}440\u{00A0}Kč")
        #expect(try row("Zbývá", in: "Sociální pojištění", of: model).value == "33\u{00A0}019\u{00A0}Kč")
        #expect(try row("Zbývá", in: "Zdravotní pojištění", of: model).value == "6\u{00A0}385\u{00A0}Kč")
        let keyFigure = try #require(model.page?.keyFigure)
        #expect(keyFigure.figure == "110\u{00A0}844\u{00A0}Kč")
        #expect(keyFigure.sentence?.contains("53\u{00A0}685\u{00A0}Kč") == true)
        #expect(keyFigure.sentence?.contains("57\u{00A0}159\u{00A0}Kč") == true)
        // The net income so far: the income less the tax of 94 440 and the two insurances, 1 871 107, which over the
        // ten months to the day shown is 187 111 a month.
        let netIncome = try #require(model.sections.last)
        #expect(netIncome.tag == "do 17.\u{00A0}10.")
        #expect(try row("Čistý příjem", in: "Čistý příjem", of: model).value == "1\u{00A0}871\u{00A0}107")
        #expect(try row("Průměrně za měsíc", in: "Čistý příjem", of: model).value == "187\u{00A0}111\u{00A0}Kč")
    }

    @Test func theRowsComeFromTheSavedSettingsOfTheYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        #expect(try row("Výdajový paušál 60\u{00A0}%", in: "Příjmy a zisk", of: model).note?.isEmpty == false)

        var settings = try await database.yearSettings(2026)
        settings.expensePercent = 80
        settings.incomeFXMethod = .uniform
        settings.taxpayerCredit = false
        try await database.saveYearSettings(settings)
        await app.didWrite()
        await model.load()

        // 80 % of 2 191 771 Kč is 1 753 417 Kč, over the cap of 1 600 000 Kč.
        let expenses = try row("Výdajový paušál 80\u{00A0}%", in: "Příjmy a zisk", of: model)
        #expect(expenses.value == "\u{2212}1\u{00A0}600\u{00A0}000,00")
        #expect(
            expenses.note
                == "80\u{00A0}% je 1\u{00A0}753\u{00A0}416,00 → použije se strop 1\u{00A0}600\u{00A0}000")
        #expect(try row("Sleva na poplatníka", in: "Daň z příjmů", of: model).note == "neuplatňuje se")
        // The uniform rate is chosen, but 2026 does not have it yet: the year is computed at the daily rates.
        #expect(
            try row("Přijaté platby", in: "Příjmy a zisk", of: model).note?.hasSuffix(
                "cizí měny v Kč ke dni přijetí") == true)
    }

    /// The texts that name the conversion of the income in other currencies follow the method the year uses: the
    /// uniform rate only once the year has it, whatever is chosen.
    @Test func theConversionTextsFollowTheMethodTheYearUses() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        try await database.updateYearSettings(2026) { $0.incomeFXMethod = .uniform }
        let model = await loadedModel(of: app)

        #expect(
            try row("Přijaté platby", in: "Příjmy a zisk", of: model).note
                == "1.\u{00A0}1. – 17.\u{00A0}10. · cizí měny v Kč ke dni přijetí")
        #expect(model.page?.assumptions.items[3] == "Cizí měny v Kč kurzem ČNB ke dni přijetí platby")

        // The rate of dollars, the only foreign currency of the sample year, is entered by hand.
        try await database.saveUniformRates(
            [
                UniformRate(
                    year: 2026, currency: .usd, amount: 1, rate: decimal("21.5"), instruction: "GFŘ-D-99",
                    origin: .manual)
            ], year: 2026)
        await model.load()

        #expect(
            try row("Přijaté platby", in: "Příjmy a zisk", of: model).note
                == "1.\u{00A0}1. – 17.\u{00A0}10. · cizí měny v Kč jednotným kurzem 2026")
        #expect(
            model.page?.assumptions.items[3] == "Cizí měny v Kč jednotným kurzem 2026 (pokyn GFŘ-D-99, zadáno ručně)")
    }

    // MARK: Income adjustments

    @Test func anIncomeAdjustmentOfMinusAThousandCrownsAddsItsRow() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        #expect(model.sections.flatMap(\.rows).contains { $0.label == "Úpravy příjmů" } == false)
        #expect(
            try row("Příjmy z podnikání (§ 7)", in: "Příjmy a zisk", of: model).value == "2\u{00A0}191\u{00A0}771,00")

        try await database.saveAdjustment(
            IncomeAdjustment(date: civilDate("2026-10-16"), amountHalere: -100_000, description: "Vratka"))
        await app.didWrite()
        await model.load()

        let adjustment = try row("Úpravy příjmů", in: "Příjmy a zisk", of: model)
        #expect(adjustment.value == "\u{2212}1\u{00A0}000,00")
        #expect(adjustment.sign == .plus)
        #expect(try row("Příjmy bez DPH", in: "Příjmy a zisk", of: model).value == "2\u{00A0}190\u{00A0}771,35")
        #expect(
            try row("Příjmy z podnikání (§ 7)", in: "Příjmy a zisk", of: model).value == "2\u{00A0}190\u{00A0}771,00")
        // The adjustment is not a payment: the eleven payments are still eleven.
        #expect(model.sections.first?.tag == "11\u{00A0}plateb")
    }

    // MARK: The day shown and the year

    @Test func theBreakdownFollowsTheDayShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = ComputationModel(app: app)

        // Without the payment of 15. 10. (520,00 Kč with 109,20 Kč of VAT): ten payments.
        app.pickAsOf(civilDate("2026-10-10"))
        await model.load()

        #expect(model.sections.first?.tag == "10\u{00A0}plateb")
        #expect(
            try row("Přijaté platby", in: "Příjmy a zisk", of: model).note
                == "1.\u{00A0}1. – 10.\u{00A0}10. · cizí měny v Kč ke dni přijetí")
        #expect(try row("Přijaté platby", in: "Příjmy a zisk", of: model).value == "2\u{00A0}406\u{00A0}616,35")
        #expect(
            try row("DPH z přijatých plateb", in: "Příjmy a zisk", of: model).value == "\u{2212}219\u{00A0}345,00")
        #expect(
            try row("Příjmy z podnikání (§ 7)", in: "Příjmy a zisk", of: model).value == "2\u{00A0}187\u{00A0}271,00")
    }

    @Test func aPastYearIsComputedAsOfItsLastDayAndLeavesOutWhatOnlyAYearInProgressHas() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = ComputationModel(app: app)

        app.selectYear(2025)
        await model.load()

        #expect(model.warning == nil)
        #expect(model.sections.map(\.title) == titles)
        #expect(try row("Příjmy z podnikání (§ 7)", in: "Příjmy a zisk", of: model).value == "4\u{00A0}500,00")
        #expect(try row("Daň za rok 2025", in: "Daň z příjmů", of: model).value == "0")
        #expect(try row("Doplatek", in: "Sociální pojištění", of: model).value == "57\u{00A0}098\u{00A0}Kč")
        #expect(try row("Doplatek", in: "Zdravotní pojištění", of: model).value == "37\u{00A0}712\u{00A0}Kč")
        #expect(model.page?.keyFigure.figure == "94\u{00A0}810\u{00A0}Kč")
        let labels = model.sections.flatMap(\.rows).map(\.label)
        #expect(!labels.contains("Zbývá"))
        // Shown as of its last day, the year is a whole one for the net income too.
        #expect(model.sections.last?.tag == "za rok 2025")
        let months = try row("12\u{00A0}měsíců", in: "Čistý příjem", of: model)
        #expect(months.value == "12")
        #expect(months.note == "celý rok")
    }

    @Test func aPastYearPickedAsOfAMidYearDayIsComputedAsOfThatDayLikeAYearInProgress() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = ComputationModel(app: app)

        app.selectYear(2025)
        app.pickAsOf(civilDate("2025-06-30"))
        await model.load()

        let page = try #require(model.page)
        #expect(page.banner.hasPrefix("Počítáno jen ze skutečně přijatých plateb od 1.\u{00A0}1. do 30.\u{00A0}6."))
        #expect(page.keyFigure.eyebrow == "Zbývá zaplatit k 30.\u{00A0}6.\u{00A0}2025")
        #expect(page.levies.header == "Odvody z příjmů do 30.\u{00A0}6.")
        #expect(
            try row("Přijaté platby", in: "Příjmy a zisk", of: model).note
                == "1.\u{00A0}1. – 30.\u{00A0}6. · cizí měny v Kč ke dni přijetí")
        #expect(try row("Zbývá", in: "Sociální pojištění", of: model).value.hasSuffix("Kč"))
        #expect(!model.sections.flatMap(\.rows).map(\.label).contains("Doplatek"))
        // The net income is that of the six months to the day.
        #expect(model.sections.last?.tag == "do 30.\u{00A0}6.")
        #expect(try row("6\u{00A0}měsíců", in: "Čistý příjem", of: model).note == "leden–červen")
    }

    @Test func theNewYearIsAnEstimateWithTheRulesOfTheYearBeforeIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        #expect(model.warning == nil)

        app.handleDayChanged(civilDate("2027-01-01"))
        await model.load()

        #expect(
            model.warning == "Pravidla pro rok 2027 zatím nejsou v aplikaci – výpočet je odhad podle roku 2026.")
        // The template of Přehled.
        #expect(model.warning == RulesWarning.message(year: 2027, rulesYear: 2026))
        #expect(model.errorText == nil)
        #expect(model.sections.map(\.title) == titles)
        let bands = try row("Sazba 15\u{00A0}%", in: "Daň z příjmů", of: model)
        #expect(bands.note?.hasSuffix("pravidla 2026 · ověřeno 20.\u{00A0}10.\u{00A0}2026") == true)
        // Nothing is received yet in the new year.
        #expect(try row("Příjmy z podnikání (§ 7)", in: "Příjmy a zisk", of: model).value == "0,00")
    }

    @Test func aYearBeforeTheFirstRulesIsAnEstimateWithTheRulesOfTheFirstYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = ComputationModel(app: app)

        app.selectYear(2021)
        await model.load()

        #expect(
            model.warning == "Pravidla pro rok 2021 zatím nejsou v aplikaci – výpočet je odhad podle roku 2022.")
        #expect(model.sections.count == titles.count)

        app.selectYear(2022)
        await model.load()

        #expect(model.warning == nil)
    }

    // MARK: Income converted provisionally

    @Test func aProvisionalReceiptUpToTheDayShownBringsTheLineThatTheIncomeIsProvisional() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let line =
            "Část příjmů je zatím přepočtená předběžným kurzem. Přepočte se sama, až budou kurzy ČNB k dispozici."
        #expect(await loadedModel(of: app).provisionalNotice == nil)
        // The dollars that arrived on 2. 10. 2026 wait for the rate of their day.
        try await #require(app.database).markPaymentProvisional(ofInvoice: 10)

        app.pickAsOf(civilDate("2026-10-01"))
        #expect(await loadedModel(of: app).provisionalNotice == nil)

        app.pickAsOf(civilDate("2026-10-17"))
        let model = await loadedModel(of: app)
        #expect(model.provisionalNotice == line)
        #expect(model.warning == nil)

        // Follow the automatic cutoff again, so New Year selects the new year rather than keeping the picked day.
        app.goToday()
        // In the new year, which is an estimate, the line of 2026 is not about the year shown.
        app.handleDayChanged(civilDate("2027-01-01"))
        await model.load()
        #expect(model.warning != nil)
        #expect(model.provisionalNotice == nil)
    }

    // MARK: The page

    @Test func theModelHasTheWholePageOfTheSampleYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = ComputationModel(app: app)
        #expect(model.page == nil)

        await model.load()

        let page = try #require(model.page)
        #expect(model.sections == page.sections)
        #expect(
            page.banner.hasPrefix(
                "Počítáno jen ze skutečně přijatých plateb od 1.\u{00A0}1. do 17.\u{00A0}10.\u{00A0}2026."))
        #expect(page.keyFigure.eyebrow == "Zbývá zaplatit k 17.\u{00A0}10.\u{00A0}2026")
        #expect(page.keyFigure.figure == "110\u{00A0}844\u{00A0}Kč")
        #expect(page.levies.header == "Odvody z příjmů do 17.\u{00A0}10.")
        #expect(page.levies.total == "320\u{00A0}664\u{00A0}Kč")
        #expect(page.marginal.total == "37,8\u{00A0}%")
        #expect(page.thresholds.heading == "Hranice roku 2026")
        #expect(page.thresholds.bars.map(\.value).first == "dosažen 2.\u{00A0}10.")
        #expect(page.assumptions.items.count == 5)
    }

    // MARK: The result

    @Test func theKeyFigureSaysWhatIsLeftAndThatOnlyPositiveBalancesAddUp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        let page = try #require(model.page)
        #expect(page.keyFigure.figure == "110\u{00A0}844\u{00A0}Kč")
        #expect(page.keyFigure.eyebrow == "Zbývá zaplatit k 17.\u{00A0}10.\u{00A0}2026")
        let sentence = try #require(page.keyFigure.sentence)
        #expect(sentence.contains("53\u{00A0}685\u{00A0}Kč odejde naplánovanými zálohami"))
        #expect(sentence.hasSuffix("nezaplatí dluh u jiného."))
        #expect(
            sentence.hasSuffix(
                " Sčítají se jen kladné zůstatky – přeplatek u jednoho úřadu nezaplatí dluh u jiného."))
    }

    @Test func theLevyBarIsThatOfPrehled() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)

        let result = try await app.computeSelectedYear()
        let page = try #require(model.page)
        #expect(
            page.levies
                == LevyBarBuilder.balances(
                    of: result, kind: .toDate(isOver: false), header: "Odvody z příjmů do 17.\u{00A0}10.",
                    showsTotal: true))
    }

    @Test func aPastYearIsADoplatek() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = ComputationModel(app: app)

        app.selectYear(2025)
        await model.load()

        let page = try #require(model.page)
        #expect(page.keyFigure.eyebrow == "Doplatek za rok 2025")
        #expect(page.levies.header == "Odvody za rok 2025")
        // The levies of a year that is over are those of the year, and the last row of each is its Doplatek.
        let labels = page.levies.parts.map { $0.rows.map(\.label) }
        #expect(labels.allSatisfy { $0 == ["Odvody za rok", "Zaplaceno zálohami", "Doplatek"] })
    }

    @Test func aTaxBonusTakesNoPartOfTheLevyBarAndComesBackInGreen() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        // With the sample family stored, the income of 220 000 Kč of the first month is past six minimum wages as of
        // 28. 2. 2026, the deductions take the whole profit, and the children's 37 524 Kč are a bonus: the tax is
        // below zero.
        try await storeTheSampleFamily(in: database)
        await app.didWriteAndBackUp()
        app.pickAsOf(civilDate("2026-02-28"))
        let model = await loadedModel(of: app)

        let page = try #require(model.page)
        let tax = try #require(page.levies.parts.first { $0.authority == .tax }, "The bar has no part of the tax")
        #expect(tax.weight < 0)
        #expect(tax.legendValue == "bonus 37\u{00A0}524\u{00A0}Kč")
        #expect(tax.rows.last?.label == "Vrátí se")
        #expect(tax.rows.last?.style == .positive)
        #expect(page.keyFigure.eyebrow == "Zbývá zaplatit k 28.\u{00A0}2.\u{00A0}2026")
    }

    @Test func thePageFollowsTheYearShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = ComputationModel(app: app)

        app.selectYear(2025)
        await model.load()

        let past = try #require(model.page)
        #expect(
            past.banner == "Rok 2025 celý: všechny přijaté platby, všechny zálohy, odpočty a slevy za celý rok.")
        #expect(past.keyFigure.eyebrow == "Doplatek za rok 2025")
        #expect(past.levies.header == "Odvody za rok 2025")
        #expect(past.thresholds.heading == "Hranice roku 2025")

        app.selectYear(2027)
        await model.load()

        // 2027 is an estimate with the rules of 2026, whose band starts at 1 762 812 Kč.
        let estimate = try #require(model.page)
        #expect(estimate.thresholds.heading == "Hranice roku 2027")
        #expect(estimate.thresholds.bars[1].value == "zbývá 1\u{00A0}762\u{00A0}812")
        #expect(model.warning != nil)
    }

    @Test func aFailedLoadTakesTheWholePageAway() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        #expect(model.page != nil)

        try await storeHealthExemptMonths("13", in: database)
        await model.load()

        #expect(model.page == nil)
        #expect(model.sections.isEmpty)
    }

    // MARK: Loads that overlap

    @Test func aReloadKeepsTheSectionsOfTheLastLoadUntilItsOwnAreThere() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        let before = model.sections

        // The reload has started and waits for the data when its task is made.
        let reload = Task.immediate { await model.load() }

        #expect(model.sections == before)

        await reload.value

        #expect(model.sections == before)
    }

    @Test func loadsThatOverlapEndWithTheResultOfTheNewerOne() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = ComputationModel(app: app)

        // The first load is for 2026. It has taken what it is about and waits for the data when the day moves into
        // 2027 and a second load starts. What the model shows is all of 2027, whichever load ends last.
        let older = Task.immediate { await model.load() }
        app.handleDayChanged(civilDate("2027-01-01"))
        let newer = Task { await model.load() }
        await older.value
        await newer.value

        #expect(
            model.warning == "Pravidla pro rok 2027 zatím nejsou v aplikaci – výpočet je odhad podle roku 2026.")
        #expect(try row("Příjmy z podnikání (§ 7)", in: "Příjmy a zisk", of: model).value == "0,00")
        #expect(try row("Daň z dosavadních příjmů", in: "Daň z příjmů", of: model).value == "0")
    }

    // MARK: When the year cannot be computed

    @Test func aYearThatCannotBeComputedShowsTheLineInsteadOfTheSectionsAndALaterLoadRecovers() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        #expect(!model.sections.isEmpty)

        // A month that no form saves: the data was changed outside the app.
        try await storeHealthExemptMonths("13", in: database)
        await model.load()

        #expect(model.sections.isEmpty)
        #expect(model.warning == nil)
        #expect(model.errorText == "Výpočet se nepodařilo načíst.")

        try await storeHealthExemptMonths("", in: database)
        await model.load()

        #expect(model.sections.map(\.title) == titles)
        #expect(model.errorText == nil)
    }

    @Test func anEstimateWhoseStoredYearCannotBeComputedShowsNoWarningEither() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = ComputationModel(app: app)
        app.handleDayChanged(civilDate("2027-01-01"))
        await model.load()
        #expect(model.warning != nil)

        // The settings of 2027 are stored with a month that no form saves.
        try await database.saveYearSettings(YearSettings(year: 2027))
        try await storeHealthExemptMonths("13", year: 2027, in: database)
        await model.load()

        #expect(model.sections.isEmpty)
        #expect(model.warning == nil)
        #expect(model.errorText == "Výpočet se nepodařilo načíst.")
    }

    @Test func aScreenWhoseDataIsLockedShowsTheLine() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        let model = ComputationModel(app: app)

        await model.load()

        #expect(model.sections.isEmpty)
        #expect(model.warning == nil)
        #expect(model.errorText == "Výpočet se nepodařilo načíst.")
    }
}

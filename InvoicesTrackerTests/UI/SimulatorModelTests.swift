import Foundation
import Testing
@testable import InvoicesTracker

/// The model of the Simulátor: the inputs as the person has them, where they start, how a typed amount or number of
/// months is read, the page the engine works out for what is taken, the rate that the settings of the year prefill, the
/// copy of the deductions and family of the year, the family the simulation keeps in memory, starting again, the model
/// the app keeps, and that nothing of it is stored. The data is the sample year 2026 stored in a temporary database
/// (60 %, mortgage interest of 219 000 Kč, life insurance of 6 480 Kč and the taxpayer credit), with the sample family
/// where a test stores it; the app is as of 17. 10. 2026. The typing pause of a model ends only when a test fires its
/// wait (`ManualDelay`), or the test reads the texts itself, as Return does. The amounts of the family were worked out
/// by hand. In every expected string `\u{00A0}` is the no-break space and `\u{2212}` the minus.
@Suite(.settlesBackups)
@MainActor
struct SimulatorModelTests {
    // MARK: Helpers

    /// What the line says when the settings of the year cannot be read.
    private let readFailureText = "Simulátor nemůže načíst nastavení roku."

    /// The fields of the deductions as a simulation starts: nothing in them but the twelve months of interest.
    private let startingTexts: [DeductionField: String] = [
        .mortgageInterest: "", .mortgageMonths: "12", .lifeInsurance: "", .pensionSavings: "", .dip: "",
        .longTermCare: "", .gifts: "",
    ]

    /// An app model on a new folder with the sample year 2026 stored.
    private func makeApp(in directory: URL) async throws -> AppModel {
        let app = makeAppModel(in: directory)
        try await startFresh(app)
        let database = try #require(app.database)
        try await SampleYear2026.store(in: database)
        await app.didWriteAndBackUp()
        return app
    }

    /// A model of `app` that has loaded, whose typing pause ends only when `delay` is fired.
    private func loadedModel(of app: AppModel, delay: ManualDelay = ManualDelay()) async -> SimulatorModel {
        let model = SimulatorModel(app: app, typingDelay: .milliseconds(500), wait: delay.wait)
        await model.load()
        return model
    }

    /// The choices a simulation of 2026 starts with — the rate of the sample year, the main activity for the whole
    /// year with the switch of the health minimum off, no deductions, the taxpayer credit and no family — unless one
    /// says otherwise. A family is that of the simulated year: its children and its spouse.
    private func choose(
        year: Int = 2026, income: Int64 = 0, percent: Int = 60, activity: SimulatorActivity = .main,
        healthMinimumExempt: Bool = false, months: Int = 12, deductions: Deductions = Deductions(),
        credit: Bool = true, family: FamilyYear? = nil
    ) -> SimulatorInput {
        SimulatorInput(
            year: year, incomeKc: income, expensePercent: percent, activity: activity,
            healthMinimumExempt: healthMinimumExempt, months: months, deductions: deductions, taxpayerCredit: credit,
            family: FamilyYear(year: year, children: family?.children ?? [], spouse: family?.spouse))
    }

    /// Stores for `year`, 2026 unless given, the sample family: Anna (3. 9. 2019) and Tomáš (12. 4. 2024), the first
    /// and the second child in the household the whole year and claimed by me, and a spouse without income of her own,
    /// claimed for the whole year. Gives the family of that year as the data holds it.
    @discardableResult
    private func storeTheSampleFamily(in app: AppModel, year: Int = 2026) async throws -> FamilyYear {
        let database = try #require(app.database)
        for (order, child) in [("Anna", "2019-09-03"), ("Tomáš", "2024-04-12")].enumerated() {
            try await database.saveChild(
                Child(id: nil, name: child.0, birthDate: civilDate(child.1)), year: year,
                childYear: ChildYear(
                    household: MonthRange.wholeYear, claimant: .me, order: order + 1, ztpp: nil, studies: nil))
        }
        try await database.saveSpouse(
            SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil), year: year)
        await app.didWriteAndBackUp()
        return try await database.family(year: year)
    }

    /// A model of `app` that has copied the deductions and the family of 2026, with the income `income` taken.
    private func modelWithTheFamily(of app: AppModel, income: String) async -> SimulatorModel {
        let model = await loadedModel(of: app)
        await model.copyDeductionsAndFamily()
        model.setIncomeText(income)
        model.readTypedTexts()
        return model
    }

    /// The row of the card of the tax with `label`.
    private func taxRow(_ label: String, of model: SimulatorModel) throws -> ComputationRow {
        let tax = try #require(model.page?.sections.first)
        return try #require(tax.rows.first { $0.label == label }, "No row \(label)")
    }

    /// The health insurance of the simulation, in the last line of its result card.
    private func healthLevy(of model: SimulatorModel) -> String? {
        model.page?.summary.lines.last?.amount
    }

    /// The page the builder makes for `choices` from what the engine works out for them: the whole year, as of its
    /// last day.
    private func page(for choices: SimulatorInput, rateFromSettings: Bool) throws -> SimulatorPage {
        let result = try AppModel.compute(SimulatorBuilder.input(choices), asOf: civilDate("\(choices.year)-12-31"))
        return SimulatorBuilder.page(result, choices: choices, rateFromSettings: rateFromSettings)
    }

    /// What the screen shows of a model: the inputs with their messages, the page, and what is said of the data.
    private struct Shown: Equatable {
        var year: Int
        var expensePercent: Int
        var rateFromSettings: Bool
        var activity: SimulatorActivity
        var healthMinimumExempt: Bool
        var taxpayerCredit: Bool
        var mortgageCap: MortgageCap
        var incomeText: String
        var monthsText: String
        var deductionTexts: [DeductionField: String]
        var incomeError: String?
        var monthsError: String?
        var deductionErrors: [DeductionField: String]
        var page: SimulatorPage?
        var canCopyDeductionsAndFamily: Bool
        var errorText: String?
        var family: FamilyYear?
        var spouseIncomeText: String
        var spouseIncomeError: String?
    }

    private func shown(_ model: SimulatorModel) -> Shown {
        Shown(
            year: model.year, expensePercent: model.expensePercent, rateFromSettings: model.rateFromSettings,
            activity: model.activity, healthMinimumExempt: model.healthMinimumExempt,
            taxpayerCredit: model.taxpayerCredit, mortgageCap: model.mortgageCap, incomeText: model.incomeText,
            monthsText: model.monthsText, deductionTexts: model.deductionTexts, incomeError: model.incomeError,
            monthsError: model.monthsError, deductionErrors: model.deductionErrors, page: model.page,
            canCopyDeductionsAndFamily: model.canCopyDeductionsAndFamily, errorText: model.errorText,
            family: model.family, spouseIncomeText: model.spouseIncomeText, spouseIncomeError: model.spouseIncomeError)
    }

    // MARK: Where a simulation starts

    @Test func itStartsOnTheSelectedYearWithTheRateOfItsSettingsAndNoIncome() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = SimulatorModel(app: app, typingDelay: .milliseconds(500), wait: ManualDelay().wait)

        // Before the settings are read, the page of the starting values is there, and the copy is not on offer yet.
        #expect(model.page?.summary.total == "99\u{00A0}720\u{00A0}Kč")
        #expect(!model.canCopyDeductionsAndFamily)

        await model.load()

        #expect(model.year == 2026)
        #expect(model.expensePercent == 60)
        #expect(model.rateFromSettings)
        #expect(model.incomeText == "")
        // With no income the levies are the minimum insurance of the main activity for twelve months.
        #expect(model.page?.summary.total == "99\u{00A0}720\u{00A0}Kč")
        #expect(model.page?.summary.subline == "Zadejte příjem")
        #expect(
            model.page?.expenseNote
                == "Paušál 0\u{00A0}Kč, strop 1\u{00A0}200\u{00A0}000\u{00A0}Kč."
                + " Předvyplněno podle Nastavení roku 2026.")
        #expect(model.canCopyDeductionsAndFamily)
        // The rest of the starting values: the main activity all year, with the switch of the health minimum off, no
        // deductions with twelve months of interest under the limit of 150 000 Kč, the taxpayer credit, and no message.
        #expect(model.activity == .main)
        #expect(!model.healthMinimumExempt)
        #expect(model.monthsText == "12")
        #expect(model.deductionTexts == startingTexts)
        #expect(model.mortgageCap == .after2021)
        #expect(model.taxpayerCredit)
        #expect(model.incomeError == nil)
        #expect(model.monthsError == nil)
        #expect(model.deductionErrors.isEmpty)
        #expect(model.errorText == nil)
        #expect(try page(for: choose(), rateFromSettings: true) == model.page)
    }

    @Test func aYearWithoutRulesStartsOnTheNearestOne() async throws {
        #expect(SimulatorModel.startingYear(for: 2027) == 2026)
        #expect(SimulatorModel.startingYear(for: 2021) == 2022)
        #expect(SimulatorModel.startingYear(for: 2024) == 2024)
        #expect(SimulatorModel.years == [2026, 2025, 2024, 2023, 2022])

        // A model starts on the year the app shows, or the nearest one with rules, and is not moved to one without.
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory, clock: ManualClock(localNoon(2027, 3, 1)))
        let model = SimulatorModel(app: app)
        #expect(model.year == 2026)
        #expect(model.page?.summary.heading == "Zaplatíte za rok 2026")
        app.selectYear(2021)
        #expect(SimulatorModel(app: app).year == 2022)

        await model.selectYear(2027)

        #expect(model.year == 2026)
        #expect(model.errorText == nil)
    }

    // MARK: Typed text

    @Test func anAmountTypedKeyByKeyIsReadOnlyWhenTheTypingStops() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let delay = ManualDelay()
        let model = await loadedModel(of: app, delay: delay)

        // Each key starts the wait again. The beginning of the amount, "1 2", is no amount, and it is never read.
        model.setIncomeText("1 2")
        try await waitUntil { delay.started == 1 && delay.armed == 1 }
        model.setIncomeText("2 500 000")
        try await waitUntil { delay.started == 2 && delay.cancelled == 1 && delay.armed == 1 }
        #expect(model.incomeText == "2 500 000")
        #expect(model.incomeError == nil)
        #expect(model.page?.summary.total == "99\u{00A0}720\u{00A0}Kč")

        // When the wait is over the text is read, and the page is that of the whole amount.
        #expect(delay.fire())

        try await waitUntil { model.page?.summary.total == "460\u{00A0}690\u{00A0}Kč" }
        #expect(model.incomeError == nil)
        #expect(try page(for: choose(income: 2_500_000), rateFromSettings: true) == model.page)
    }

    @Test func unreadableTextShowsTheMessageAndTheResultsKeepTheLastAcceptedValue() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.setIncomeText("2 500 000")
        model.readTypedTexts()
        #expect(model.page?.summary.total == "460\u{00A0}690\u{00A0}Kč")

        // Text that is no amount, haléře, or an amount below zero: the message under the field, the text stays, and the
        // page keeps the income that was taken.
        for text in ["2 5x", "2 500 000,50", "-2 500 000"] {
            model.setIncomeText(text)
            model.readTypedTexts()
            #expect(model.incomeError == AdvancesModel.wholeKcMessage, "\(text)")
            #expect(model.incomeError == advancesWholeKcMessage, "\(text)")
            #expect(model.incomeText == text)
            #expect(model.page?.summary.total == "460\u{00A0}690\u{00A0}Kč", "\(text)")
        }

        // The deductions are read as in Zálohy a odpočty: whole crowns, and 0 to 12 months of interest.
        let taken = Deductions(mortgageInterestPaid: 100_000, mortgageMonths: 6, gifts: 20_000)
        model.setDeductionText(.mortgageInterest, "100 000")
        model.setDeductionText(.mortgageMonths, "6")
        model.setDeductionText(.gifts, "20 000")
        model.readTypedTexts()
        #expect(model.deductionErrors.isEmpty)
        #expect(try page(for: choose(income: 2_500_000, deductions: taken), rateFromSettings: true) == model.page)

        model.setDeductionText(.mortgageMonths, "13")
        model.setDeductionText(.gifts, "20 000,50")
        model.readTypedTexts()
        #expect(
            model.deductionErrors == [
                .mortgageMonths: "Zadejte počet měsíců od 0 do 12.", .gifts: advancesWholeKcMessage,
            ])
        #expect(model.deductionTexts[.mortgageMonths] == "13")
        #expect(model.deductionTexts[.gifts] == "20 000,50")
        #expect(try page(for: choose(income: 2_500_000, deductions: taken), rateFromSettings: true) == model.page)

        // A field with nothing in it is zero, and no mistake: the message goes.
        model.setIncomeText("")
        model.readTypedTexts()
        #expect(model.incomeError == nil)
        #expect(model.page?.summary.total == "99\u{00A0}720\u{00A0}Kč")
    }

    @Test func monthsOfActivityAreOneToTwelve() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        #expect(SimulatorModel.activityMonthsMessage == "Zadejte počet měsíců od 1 do 12.")

        // No month, more than twelve, a part of a month or no number: the message, and the page keeps twelve months.
        for text in ["0", "13", "6,5", "abc"] {
            model.setMonthsText(text)
            model.readTypedTexts()
            #expect(model.monthsError == SimulatorModel.activityMonthsMessage, "\(text)")
            #expect(model.monthsText == text)
            #expect(try page(for: choose(), rateFromSettings: true) == model.page, "\(text)")
        }

        // Six months are taken: the engine gets the activity of January to June, and the minimums count six months.
        model.setMonthsText("6")
        model.readTypedTexts()

        #expect(model.monthsError == nil)
        #expect(try page(for: choose(months: 6), rateFromSettings: true) == model.page)
        #expect(model.page?.summary.total == "49\u{00A0}860\u{00A0}Kč")

        // Nothing at all counts as no month, which is refused like any number outside 1 to 12: the field stays empty
        // with the message under it, and the page keeps the six months that were taken.
        model.setMonthsText("")
        model.readTypedTexts()
        #expect(model.monthsError == SimulatorModel.activityMonthsMessage)
        #expect(model.monthsText == "")
        #expect(try page(for: choose(months: 6), rateFromSettings: true) == model.page)
    }

    // MARK: The health minimum of a secondary activity

    /// A secondary activity of one month in 2026 on an income of 5 000 Kč with expenses at 60 % has a profit of
    /// 2 000 Kč and a base of the health insurance of 1 000 Kč, which is 135 Kč of insurance. With the minimum of the
    /// month, 24 483,50 Kč, it is 3 306 Kč (13,5 % of it, rounded up). The switch takes the minimum off at once, and
    /// puts it back.
    @Test func theSwitchChangesTheHealthOfVedlejsiActivity() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.setIncomeText("5 000")
        model.setMonthsText("1")
        model.readTypedTexts()

        // A secondary activity alone pays the minimum of its month, as a main one does.
        model.setActivity(.secondary)

        #expect(!model.healthMinimumExempt)
        #expect(healthLevy(of: model) == "3\u{00A0}306\u{00A0}Kč")
        let paying = choose(income: 5_000, activity: .secondary, months: 1)
        #expect(try page(for: paying, rateFromSettings: true) == model.page)

        model.setHealthMinimumExempt(true)

        #expect(model.healthMinimumExempt)
        #expect(healthLevy(of: model) == "135\u{00A0}Kč")
        let exempt = choose(income: 5_000, activity: .secondary, healthMinimumExempt: true, months: 1)
        #expect(try page(for: exempt, rateFromSettings: true) == model.page)

        model.setHealthMinimumExempt(false)

        #expect(!model.healthMinimumExempt)
        #expect(healthLevy(of: model) == "3\u{00A0}306\u{00A0}Kč")
    }

    /// The switch is for a secondary activity: a main one pays the minimum whatever it says, and the switch keeps its
    /// value meanwhile, so that it applies again when the secondary activity comes back.
    @Test func theSwitchKeepsItsValueWhileHlavniIsChosen() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.setIncomeText("5 000")
        model.setMonthsText("1")
        model.readTypedTexts()
        model.setActivity(.secondary)
        model.setHealthMinimumExempt(true)
        #expect(healthLevy(of: model) == "135\u{00A0}Kč")

        model.setActivity(.main)

        #expect(model.healthMinimumExempt)
        #expect(healthLevy(of: model) == "3\u{00A0}306\u{00A0}Kč")
        #expect(try page(for: choose(income: 5_000, months: 1), rateFromSettings: true) == model.page)

        model.setActivity(.secondary)

        #expect(model.healthMinimumExempt)
        #expect(healthLevy(of: model) == "135\u{00A0}Kč")
    }

    // MARK: The settings of the year

    @Test func copyingTheStoredDeductionsFillsTheFieldsAndChangesNothingStored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        let versionBefore = app.dataVersion
        // What the copy replaces: an amount that was taken, a text that was refused, and choices that differ.
        model.setIncomeText("2 500 000")
        model.setDeductionText(.gifts, "5 000")
        model.setDeductionText(.pensionSavings, "abc")
        model.readTypedTexts()
        model.setTaxpayerCredit(false)
        model.setMortgageCap(.before2021)
        #expect(model.deductionErrors[.pensionSavings] == advancesWholeKcMessage)

        await model.copyDeductionsAndFamily()

        // The fields show the deductions of 2026 as Zálohy a odpočty keeps them; a deduction of zero is an empty field.
        #expect(model.deductionTexts[.mortgageInterest] == "219\u{00A0}000")
        #expect(model.deductionTexts[.lifeInsurance] == "6\u{00A0}480")
        #expect(
            model.deductionTexts == [
                .mortgageInterest: "219\u{00A0}000", .mortgageMonths: "12", .lifeInsurance: "6\u{00A0}480",
                .pensionSavings: "", .dip: "", .longTermCare: "", .gifts: "",
            ])
        #expect(model.deductionErrors.isEmpty)
        #expect(model.mortgageCap == .after2021)
        #expect(model.taxpayerCredit)
        // The tax counts them: the interest up to its limit of 150 000 Kč and the life insurance take 156 480 Kč off.
        let tax = try #require(model.page?.sections.first)
        #expect(try #require(tax.rows.first { $0.label == "Odpočty" }).value == "\u{2212}156\u{00A0}480,00")
        #expect(model.page?.summary.lines.first?.amount == "140\u{00A0}685\u{00A0}Kč")
        #expect(model.page?.hints.mortgageOverLimit == "69\u{00A0}000\u{00A0}Kč")
        let stored = SampleYear2026.yearSettings.deductions
        #expect(try page(for: choose(income: 2_500_000, deductions: stored), rateFromSettings: true) == model.page)

        // Nothing stored changed, and the app was told of no write.
        #expect(app.dataVersion == versionBefore)
        #expect(try await database.yearSettings(2026) == SampleYear2026.yearSettings)
    }

    @Test func theRateFollowsTheYearUntilThePersonPicksOne() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        var earlier = YearSettings(year: 2025)
        earlier.expensePercent = 40
        try await storeYear(earlier, in: app)
        let model = await loadedModel(of: app)
        #expect(model.expensePercent == 60)

        await model.selectYear(2025)

        #expect(model.year == 2025)
        #expect(model.expensePercent == 40)
        #expect(model.rateFromSettings)
        #expect(try page(for: choose(year: 2025, percent: 40), rateFromSettings: true) == model.page)

        // A rate the person picks stays, whichever year comes; one that is not offered is not taken.
        model.setExpensePercent(80)
        model.setExpensePercent(50)
        #expect(model.expensePercent == 80)
        #expect(!model.rateFromSettings)

        await model.selectYear(2026)

        #expect(model.year == 2026)
        #expect(model.expensePercent == 80)
        #expect(!model.rateFromSettings)
        #expect(model.page?.expenseNote == "Paušál 0\u{00A0}Kč, strop 1\u{00A0}600\u{00A0}000\u{00A0}Kč.")
        #expect(try page(for: choose(percent: 80), rateFromSettings: false) == model.page)
    }

    /// The copy takes what Zálohy a odpočty shows for the year, also for a year without settings of its own. That
    /// screen gives such a year the choices of the nearest earlier year that has settings, no deductions as any new
    /// year starts, the children carried from the earlier years and no spouse, which is never carried. Here 2025 is the
    /// only year with settings, not the sample year 2026 the other tests store: the taxpayer credit off, something in
    /// every field of the deductions, Anna and Tomáš with rows for 2025 and a spouse who is claimed. The Simulátor on
    /// 2026 offers the copy and makes the children, the credit that 2026 inherits and the empty deductions its own, in
    /// place of what it had, and it takes nothing else of 2025. 2026 stays a year without settings.
    @Test func aYearWithoutItsOwnSettingsCopiesWhatZálohyShows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        try await startFresh(app)
        let database = try #require(app.database)
        var earlier = YearSettings(year: 2025)
        earlier.taxpayerCredit = false
        earlier.deductions = Deductions(
            mortgageInterestPaid: 100_000, mortgageMonths: 6, mortgageCap: .before2021, lifeInsurance: 5_000,
            pensionSavings: 12_000, dip: 24_000, longTermCare: 2_000, gifts: 3_000)
        try await storeYear(earlier, in: app)
        try await storeTheSampleFamily(in: app, year: 2025)
        #expect(try await database.storedSettingsYears() == [2025])
        let versionBefore = app.dataVersion
        let model = await loadedModel(of: app)
        // What the copy replaces: a gift that was typed, the other limit on the interest, and a spouse.
        model.setDeductionText(.gifts, "5 000")
        model.readTypedTexts()
        model.setMortgageCap(.before2021)
        try await model.setSpouse(SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil))
        #expect(model.taxpayerCredit)
        #expect(model.family?.spouse != nil)

        // 2026 has no settings of its own, and its copy is on offer all the same.
        #expect(model.year == 2026)
        #expect(model.canCopyDeductionsAndFamily)
        await model.copyDeductionsAndFamily()

        // The children of 2025 carried to 2026, which has no row of its own for them, and no spouse.
        #expect(model.family?.children.map(\.child.name) == ["Anna", "Tomáš"])
        #expect(model.family?.children.map(\.year.order) == [1, 2])
        #expect(model.family?.children.map(\.isStored) == [false, false])
        #expect(model.family?.spouse == nil)
        #expect(model.spouseIncomeText == "")
        // The choice of the taxpayer credit that 2026 inherits, and the deductions it starts with: none of 2025's.
        #expect(!model.taxpayerCredit)
        #expect(model.deductionTexts == startingTexts)
        #expect(model.mortgageCap == .after2021)
        #expect(model.deductionErrors.isEmpty)
        #expect(model.errorText == nil)
        let carried = try #require(model.family)
        #expect(try page(for: choose(credit: false, family: carried), rateFromSettings: true) == model.page)

        // Nothing was written: 2026 is still a year without settings of its own, and the app was told of no write.
        #expect(try await database.storedSettingsYears() == [2025])
        #expect(app.dataVersion == versionBefore)

        // It is what Zálohy a odpočty shows for 2026.
        let advances = await loadedAdvancesModel(of: app)
        #expect(advances.year == 2026)
        #expect(advances.settings?.taxpayerCredit == false)
        #expect(advances.settings?.deductions == Deductions())
        #expect(advances.settings?.spouse == nil)
        #expect(advances.loadedFamily == carried)
    }

    @Test func settingsThatCannotBeReadAreSaidAndTheInputsStay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        var earlier = YearSettings(year: 2025)
        earlier.expensePercent = 40
        try await storeYear(earlier, in: app)
        let database = try #require(app.database)
        let model = await loadedModel(of: app)
        model.setIncomeText("2 500 000")
        model.readTypedTexts()
        let before = shown(model)

        // The data cannot be read: the copy changes nothing, and the line says why.
        app.database = nil
        await model.copyDeductionsAndFamily()

        var expected = before
        expected.errorText = readFailureText
        #expect(shown(model) == expected)

        // Another year is chosen all the same, with the rate there was; it has not been read, so its copy is not on
        // offer.
        await model.selectYear(2025)

        #expect(model.errorText == readFailureText)
        #expect(model.year == 2025)
        #expect(model.expensePercent == 60)
        #expect(!model.canCopyDeductionsAndFamily)
        #expect(try page(for: choose(year: 2025, income: 2_500_000), rateFromSettings: true) == model.page)

        // Once the data can be read, the next load reads the year, and the line goes.
        app.database = database
        await model.load()

        #expect(model.errorText == nil)
        #expect(model.expensePercent == 40)
        #expect(model.canCopyDeductionsAndFamily)
    }

    // MARK: The family

    /// The simulation starts without a family, as it starts without deductions, also when the year has one stored:
    /// the cards of the family have no child and no claimed spouse.
    @Test func theSimulatorStartsWithoutAFamily() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await storeTheSampleFamily(in: app)

        let model = await loadedModel(of: app)

        #expect(model.family == FamilyYear(year: 2026, children: [], spouse: nil))
        #expect(model.spouseIncomeText == "")
        #expect(model.spouseIncomeError == nil)
        let cards = try #require(model.page?.family)
        #expect(cards.children.rows.isEmpty)
        #expect(cards.children.total == nil)
        #expect(cards.spouse.total == nil)
        #expect(cards.spouse.result == nil)
        #expect(try page(for: choose(), rateFromSettings: true) == model.page)
    }

    /// "Převzít ze Záloh a odpočtů 2026" copies the family of 2026 with the deductions: the children, each with what
    /// the year says about it and in the order of the year, and the spouse. With 2 500 000 Kč the deductions leave
    /// 140 685 Kč of tax after the taxpayer credit; the spouse takes 24 840 Kč off it and the children 37 524 Kč, to
    /// 78 321 Kč. Nothing is written.
    @Test func copyingTakesTheYearsFamily() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let stored = try await storeTheSampleFamily(in: app)
        let versionBefore = app.dataVersion

        let model = await modelWithTheFamily(of: app, income: "2 500 000")

        #expect(model.family == stored)
        #expect(model.family?.children.map(\.child.name) == ["Anna", "Tomáš"])
        // The spouse has no income of her own: the field is empty, as a deduction of nothing is.
        #expect(model.spouseIncomeText == "")
        let cards = try #require(model.page?.family)
        #expect(cards.spouse.total == "24\u{00A0}840\u{00A0}Kč za rok")
        #expect(cards.children.total == "37\u{00A0}524\u{00A0}Kč za rok")
        #expect(cards.children.rows.map(\.status) == ["1. dítě · 12\u{00A0}měsíců", "2. dítě · 12\u{00A0}měsíců"])
        #expect(try taxRow("Sleva na manžela / manželku", of: model).value == "\u{2212}24\u{00A0}840")
        #expect(try taxRow("Daňové zvýhodnění na děti", of: model).value == "\u{2212}37\u{00A0}524")
        #expect(try taxRow("Daň z příjmů", of: model).value == "78\u{00A0}321\u{00A0}Kč")
        #expect(model.page?.summary.lines.first?.amount == "78\u{00A0}321\u{00A0}Kč")
        // The bar shares what is paid: the tax after the family's credits, 78 321 Kč, the social insurance, 208 780 Kč,
        // and the health insurance, 87 750 Kč, of 374 851 Kč.
        let shares = try #require(model.page?.summary.shares)
        #expect(shares.map(\.authority) == [.tax, .social, .health])
        for (share, expected) in zip(shares, [0.208939, 0.556968, 0.234093]) {
            #expect(abs(share.fraction - expected) < 0.000001, "\(share.authority): \(share.fraction)")
        }
        let deductions = SampleYear2026.yearSettings.deductions
        #expect(
            try page(for: choose(income: 2_500_000, deductions: deductions, family: stored), rateFromSettings: true)
                == model.page)

        // Nothing stored changed, and the app was told of no write.
        #expect(app.dataVersion == versionBefore)
        #expect(try await database.family(year: 2026) == stored)
    }

    /// Ema, born 15. 6. 2026 and added in the dialog of the simulation, counts from June, the month of her birth, as
    /// the third child: 7 months at 2 320 Kč, 16 240 Kč. She has an id of her own and comes after Anna and Tomáš. The
    /// data keeps the family as it was, and a new copy takes the family of the year again, without her.
    @Test func aChildAddedInTheSimulationIsNotStored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let stored = try await storeTheSampleFamily(in: app)
        let versionBefore = app.dataVersion
        let model = await modelWithTheFamily(of: app, income: "2 500 000")
        let dialog = ChildDialogModel(editing: model, year: 2026, child: nil, mode: .simulation)
        dialog.name = "Ema"
        dialog.birthDateText = "15. 6. 2026"
        #expect(dialog.order == 3)
        #expect(
            dialog.liveResult
                == ChildDialogResult(
                    text: "V roce 2026: 7\u{00A0}měsíců jako 3. a další dítě · 16\u{00A0}240\u{00A0}Kč", counts: true))

        #expect(await dialog.save())

        let children = try #require(model.family?.children)
        #expect(children.map(\.child.name) == ["Anna", "Tomáš", "Ema"])
        #expect(children.map(\.year.order) == [1, 2, 3])
        let ids = children.compactMap(\.child.id)
        #expect(ids.count == 3)
        #expect(Set(ids).count == 3)
        #expect(Array(ids.prefix(2)) == stored.children.compactMap(\.child.id))
        let ema = try #require(model.page?.family.children.rows.last)
        #expect(ema.status == "3. a další dítě · 7\u{00A0}měsíců")
        #expect(ema.amount == "16\u{00A0}240\u{00A0}Kč")
        #expect(model.page?.family.children.total == "53\u{00A0}764\u{00A0}Kč za rok")
        // 78 321 Kč less Ema's 16 240 Kč.
        #expect(try taxRow("Daň z příjmů", of: model).value == "62\u{00A0}081\u{00A0}Kč")

        // Nothing is stored.
        #expect(app.dataVersion == versionBefore)
        #expect(try await database.family(year: 2026) == stored)

        // A new copy replaces the family of the simulation with the family of the year.
        await model.copyDeductionsAndFamily()
        #expect(model.family == stored)
    }

    /// 150 000 Kč with the family of 2026: the deductions take the whole profit of 60 000 Kč, so there is no tax, and
    /// the children's 37 524 Kč are all a bonus, as the income has reached six minimum wages (134 400 Kč). The tax
    /// reads as the bonus, what the year costs is the minimum insurance less it, and the bar leaves it out.
    @Test func income150000PaysABonus() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let stored = try await storeTheSampleFamily(in: app)

        let model = await modelWithTheFamily(of: app, income: "150 000")

        let summary = try #require(model.page?.summary)
        #expect(summary.lines.first?.amount == "bonus 37\u{00A0}524\u{00A0}Kč")
        #expect(summary.total == "62\u{00A0}196\u{00A0}Kč")
        #expect(summary.shares.first?.fraction == 0)
        let tax = try taxRow("Daň z příjmů", of: model)
        #expect(tax.value == "\u{2212}37\u{00A0}524\u{00A0}Kč")
        #expect(tax.note == "záporná daň je daňový bonus – vyplatí ho finanční úřad")
        #expect(
            try taxRow("Daňové zvýhodnění na děti", of: model).note
                == "Anna 15\u{00A0}204 · Tomáš 22\u{00A0}320 · z toho daňový bonus 37\u{00A0}524")
        #expect(
            model.page?.family.children.hint
                == "Zvýhodnění převyšuje daň o 37\u{00A0}524\u{00A0}Kč – tolik vám finanční úřad vyplatí jako daňový"
                + " bonus.")
        let deductions = SampleYear2026.yearSettings.deductions
        #expect(
            try page(for: choose(income: 150_000, deductions: deductions, family: stored), rateFromSettings: true)
                == model.page)
    }

    /// 100 000 Kč is less than six minimum wages of 2026, 6 × 22 400 = 134 400 Kč: what the children's benefit leaves
    /// is not paid as a bonus, so the tax is nothing, and the card of the children and the row of the children say
    /// why. A simulation is of a whole year, whose income does not grow any more: the bonus is not paid, not "not
    /// yet".
    @Test func income100000PaysNoBonusAndSaysWhy() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await storeTheSampleFamily(in: app)

        let model = await modelWithTheFamily(of: app, income: "100 000")

        #expect(model.page?.summary.lines.first?.amount == "0\u{00A0}Kč")
        #expect(model.page?.summary.total == "99\u{00A0}720\u{00A0}Kč")
        #expect(
            model.page?.family.children.hint
                == "Zvýhodnění převyšuje daň o 37\u{00A0}524\u{00A0}Kč, bonus se ale nevyplatí: příjmy roku"
                + " nedosáhly 6× minimální mzdy (134\u{00A0}400\u{00A0}Kč).")
        let children = try taxRow("Daňové zvýhodnění na děti", of: model)
        #expect(children.value == "0")
        #expect(
            children.note
                == "Anna 15\u{00A0}204 · Tomáš 22\u{00A0}320 · bonus 37\u{00A0}524 se nevyplatí:"
                + " příjmy pod 6× minimální mzdu (134\u{00A0}400)")
        let tax = try taxRow("Daň z příjmů", of: model)
        #expect(tax.value == "0\u{00A0}Kč")
        #expect(tax.note == nil)
    }

    /// The family stays when the year changes. 2023 asks no child under three for the spouse credit, so the spouse
    /// counts the whole year; Tomáš, born in 2024, is not born yet, and Anna is the only child, the first. With
    /// 2 500 000 Kč the tax after the taxpayer credit is 140 685 Kč, less 24 840 Kč for the spouse and 15 204 Kč for
    /// Anna: 100 641 Kč.
    @Test func year2023AppliesTheSpouseCreditWithoutTheChildCondition() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let stored = try await storeTheSampleFamily(in: app)
        let model = await modelWithTheFamily(of: app, income: "2 500 000")

        await model.selectYear(2023)

        #expect(model.year == 2023)
        #expect(model.family == FamilyYear(year: 2023, children: stored.children, spouse: stored.spouse))
        let cards = try #require(model.page?.family)
        #expect(cards.children.rows.map(\.name) == ["Anna", "Tomáš"])
        #expect(
            cards.children.rows.map(\.status) == [
                "1. dítě · 12\u{00A0}měsíců", "narodí se až 12.\u{00A0}4.\u{00A0}2024",
            ])
        #expect(cards.children.rows.map(\.countsInNoMonth) == [false, true])
        #expect(cards.children.rows.map(\.amount) == ["15\u{00A0}204\u{00A0}Kč", "—"])
        #expect(cards.spouse.youngChild == nil)
        #expect(cards.spouse.result == "Sleva za 12\u{00A0}měsíců: 24\u{00A0}840\u{00A0}Kč")
        let spouse = try taxRow("Sleva na manžela / manželku", of: model)
        #expect(spouse.value == "\u{2212}24\u{00A0}840")
        #expect(spouse.note == "12\u{00A0}měsíců")
        #expect(try taxRow("Daňové zvýhodnění na děti", of: model).note == "Anna 15\u{00A0}204")
        #expect(try taxRow("Daň z příjmů", of: model).value == "100\u{00A0}641\u{00A0}Kč")
        let deductions = SampleYear2026.yearSettings.deductions
        #expect(
            try page(
                for: choose(year: 2023, income: 2_500_000, deductions: deductions, family: stored),
                rateFromSettings: true) == model.page)
    }

    /// The children are listed as `Database.family(year:)` lists them, by the date of birth and then by id, so the
    /// engine settles a tie of the orders as in Zálohy a odpočty. Petr and Pavel, twins of 2. 2. 2020, both have the
    /// first place stored for 2026: Petr, saved first, ranks first, and with ZTP/P he brings twice the first child's
    /// 15 204 Kč, and Pavel the second child's 22 320 Kč. A twin added in the simulation comes after them.
    @Test func theChildrenRankAsInZálohyAOdpočty() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        for (name, ztpp) in [("Petr", MonthRange.wholeYear), ("Pavel", nil)] {
            try await database.saveChild(
                Child(id: nil, name: name, birthDate: civilDate("2020-02-02")), year: 2026,
                childYear: ChildYear(
                    household: MonthRange.wholeYear, claimant: .me, order: 1, ztpp: ztpp, studies: nil))
        }
        await app.didWriteAndBackUp()
        let advances = await loadedAdvancesModel(of: app)

        let model = await modelWithTheFamily(of: app, income: "2 500 000")

        let rows = try #require(model.page?.family.children.rows)
        #expect(rows.map(\.name) == ["Petr", "Pavel"])
        #expect(rows.map(\.amount) == ["30\u{00A0}408\u{00A0}Kč", "22\u{00A0}320\u{00A0}Kč"])
        #expect(rows.map(\.amount) == advances.familyCards?.children.rows.map(\.amount))
        #expect(rows.map(\.status) == advances.familyCards?.children.rows.map(\.status))

        let dialog = ChildDialogModel(editing: model, year: 2026, child: nil, mode: .simulation)
        dialog.name = "Pepa"
        dialog.birthDateText = "2. 2. 2020"
        #expect(await dialog.save())
        let children = try #require(model.family?.children)
        #expect(children.map(\.child.name) == ["Petr", "Pavel", "Pepa"])
        try #require(children.count == 3)
        #expect(try #require(children[2].child.id) > (try #require(children[1].child.id)))
    }

    /// The own income of the spouse is typed as the other amounts are: read when the typing stops, in whole crowns, and
    /// nothing for none; a text that is refused keeps its message, and the income its value. Over 68 000 Kč the credit
    /// goes. Without a spouse there is no field.
    @Test func theSpousesOwnIncomeIsReadWhenTheTypingStops() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let delay = ManualDelay()
        let model = await loadedModel(of: app, delay: delay)
        model.setSpouseIncomeText("1 000")
        #expect(model.spouseIncomeText == "")
        try await model.setSpouse(SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil))

        model.setSpouseIncomeText("70 000")
        try await waitUntil { delay.armed == 1 }
        #expect(model.family?.spouse?.ownIncomeKc == 0)
        #expect(delay.fire())

        try await waitUntil { model.family?.spouse?.ownIncomeKc == 70_000 }
        #expect(model.spouseIncomeError == nil)
        #expect(model.page?.family.spouse.incomeStatus == "nad limitem 68\u{00A0}000\u{00A0}Kč – slevu nejde uplatnit")

        model.setSpouseIncomeText("70 000,50")
        model.readTypedTexts()
        #expect(model.spouseIncomeError == advancesWholeKcMessage)
        #expect(model.spouseIncomeText == "70 000,50")
        #expect(model.family?.spouse?.ownIncomeKc == 70_000)

        model.setSpouseIncomeText("")
        model.readTypedTexts()
        #expect(model.spouseIncomeError == nil)
        #expect(model.family?.spouse?.ownIncomeKc == 0)
        #expect(model.page?.family.spouse.incomeStatus == "do limitu 68\u{00A0}000\u{00A0}Kč")
    }

    /// Every change of the family is made whole or not at all, as one write of Zálohy a odpočty is. An entry of the
    /// orders of the other children that cannot apply — for a child that is not among them, for the child that is saved
    /// or removed itself, or an order below 1 — makes the whole change throw `FamilyEditingError.refused`, and so does a
    /// child or a spouse the engine would not take: the family and the page stay as they were, also the entries of the
    /// change that could apply. A change that is made gives the other children their orders with it.
    @Test func aChangeOfTheFamilyIsMadeWholeOrNotAtAll() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let stored = try await storeTheSampleFamily(in: app)
        let model = await modelWithTheFamily(of: app, income: "2 500 000")
        let anna = try #require(stored.children[0].child.id)
        let tomas = try #require(stored.children[1].child.id)
        let ema = Child(id: nil, name: "Ema", birthDate: civilDate("2026-06-15"))
        func year(order: Int, household: MonthRange? = MonthRange.wholeYear) -> ChildYear {
            ChildYear(household: household, claimant: .me, order: order, ztpp: nil, studies: nil)
        }
        let before = shown(model)

        let refused: [(name: String, change: @MainActor () async throws -> Void)] = [
            (
                "a save with an order for a child that is not there",
                { try await model.saveChild(ema, childYear: year(order: 1), otherOrders: [anna: 2, 999: 3]) }
            ),
            (
                "a save with an order for the child that is saved",
                {
                    try await model.saveChild(
                        stored.children[0].child, childYear: year(order: 2), otherOrders: [tomas: 1, anna: 1])
                }
            ),
            (
                "a save with an order below 1",
                { try await model.saveChild(ema, childYear: year(order: 1), otherOrders: [anna: 2, tomas: 0]) }
            ),
            (
                "a child whose order is below 1",
                { try await model.saveChild(ema, childYear: year(order: 0), otherOrders: [:]) }
            ),
            (
                "a child whose months run backwards",
                {
                    try await model.saveChild(
                        ema, childYear: year(order: 3, household: MonthRange(from: 9, to: 3)), otherOrders: [:])
                }
            ),
            (
                "a removal with an order for a child that is not there",
                { try await model.removeChild(id: anna, otherOrders: [tomas: 1, 999: 2]) }
            ),
            (
                "a removal with an order for the child that is removed",
                { try await model.removeChild(id: anna, otherOrders: [tomas: 1, anna: 2]) }
            ),
            (
                "a removal with an order below 1",
                { try await model.removeChild(id: anna, otherOrders: [tomas: 0]) }
            ),
            (
                "a spouse whose months run backwards",
                {
                    try await model.setSpouse(
                        SpouseYear(claim: true, months: MonthRange(from: 12, to: 1), ownIncomeKc: 0, ztpp: nil))
                }
            ),
            (
                "a spouse with an income below zero",
                {
                    try await model.setSpouse(
                        SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: -1, ztpp: nil))
                }
            ),
        ]
        for (name, change) in refused {
            await #expect(throws: FamilyEditingError.refused, "\(name)") {
                try await change()
            }
            #expect(shown(model) == before, "\(name)")
        }

        // Ema takes the first place, and Anna and Tomáš move down with her, in one change.
        try await model.saveChild(ema, childYear: year(order: 1), otherOrders: [anna: 2, tomas: 3])
        #expect(model.family?.children.map(\.child.name) == ["Anna", "Tomáš", "Ema"])
        #expect(model.family?.children.map(\.year.order) == [2, 3, 1])
        // Anna is the first child until May and the second from June, Tomáš the second and then the third, and Ema the
        // first from June, the month of her birth: 5 × 1 267 + 7 × 1 860, 5 × 1 860 + 7 × 2 320 and 7 × 1 267 Kč.
        #expect(
            model.page?.family.children.rows.map(\.amount) == [
                "19\u{00A0}355\u{00A0}Kč", "25\u{00A0}540\u{00A0}Kč", "8\u{00A0}869\u{00A0}Kč",
            ])

        // Anna goes, and Tomáš and Ema take her place in the same change.
        try await model.removeChild(id: anna, otherOrders: [tomas: 2])
        #expect(model.family?.children.map(\.child.name) == ["Tomáš", "Ema"])
        #expect(model.family?.children.map(\.year.order) == [2, 1])
    }

    // MARK: Starting again

    /// "Začít znovu" clears the family with every other input: no child, no spouse, and no text of the spouse's income,
    /// neither one that was refused nor one that is still being typed.
    @Test func začítZnovuClearsTheFamily() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await storeTheSampleFamily(in: app)
        let delay = ManualDelay()
        let model = await loadedModel(of: app, delay: delay)
        let start = shown(model)
        await model.copyDeductionsAndFamily()
        try await model.setSpouse(
            SpouseYear(claim: true, months: MonthRange(from: 3, to: 12), ownIncomeKc: 0, ztpp: nil))
        model.setSpouseIncomeText("abc")
        model.readTypedTexts()
        #expect(model.spouseIncomeError == advancesWholeKcMessage)
        model.setSpouseIncomeText("50 000")
        try await waitUntil { delay.armed == 1 }
        #expect(model.family?.children.count == 2)

        await model.reset()

        #expect(model.family == FamilyYear(year: 2026, children: [], spouse: nil))
        #expect(model.spouseIncomeText == "")
        #expect(model.spouseIncomeError == nil)
        #expect(model.page?.family.children.rows.isEmpty == true)
        #expect(shown(model) == start)
        try await waitUntil { delay.armed == 0 }
    }

    @Test func startingAgainRestoresTheStartingValues() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let delay = ManualDelay()
        let model = await loadedModel(of: app, delay: delay)
        let start = shown(model)
        await model.selectYear(2024)
        model.setExpensePercent(30)
        model.setActivity(.secondary)
        model.setHealthMinimumExempt(true)
        model.setTaxpayerCredit(false)
        model.setMortgageCap(.before2021)
        model.setIncomeText("1 000 000")
        model.setMonthsText("13")
        model.setDeductionText(.lifeInsurance, "5 000")
        model.setDeductionText(.gifts, "abc")
        model.readTypedTexts()
        // A text that is still being typed, whose wait runs.
        model.setIncomeText("777")
        try await waitUntil { delay.armed == 1 }
        #expect(shown(model) != start)

        await model.reset()

        // The starting values of the first test, and every other input as a simulation starts.
        #expect(model.year == 2026)
        #expect(model.expensePercent == 60)
        #expect(model.rateFromSettings)
        #expect(model.incomeText == "")
        #expect(model.page?.summary.total == "99\u{00A0}720\u{00A0}Kč")
        #expect(model.canCopyDeductionsAndFamily)
        #expect(shown(model) == start)
        // The text that was being typed went with the rest, and so did the wait for it.
        try await waitUntil { delay.armed == 0 }
    }

    /// Starting again leaves the switch of the health minimum off. A secondary activity chosen again pays the minimum
    /// of the twelve months of a simulation, 24 483,50 Kč a month: 39 664 Kč of insurance, where the switch would
    /// leave none.
    @Test func startingAgainTurnsTheSwitchOff() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let model = await loadedModel(of: app)
        model.setActivity(.secondary)
        model.setHealthMinimumExempt(true)
        #expect(model.healthMinimumExempt)
        #expect(healthLevy(of: model) == "0\u{00A0}Kč")

        await model.reset()

        #expect(!model.healthMinimumExempt)
        model.setActivity(.secondary)
        #expect(!model.healthMinimumExempt)
        #expect(healthLevy(of: model) == "39\u{00A0}664\u{00A0}Kč")
        #expect(try page(for: choose(activity: .secondary), rateFromSettings: true) == model.page)
    }

    // MARK: The model of the app

    @Test func theAppKeepsOneSimulatorWhileScreensChange() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        app.screen = .simulator
        let model = app.simulatorModel
        model.setIncomeText("2 500 000")
        model.readTypedTexts()

        app.screen = .computation
        #expect(app.simulatorModel === model)
        app.screen = .simulator

        #expect(app.simulatorModel === model)
        #expect(app.simulatorModel.incomeText == "2 500 000")
    }

    /// Data that is opened, other data or the same data again after it was locked, starts a simulation of its own: the
    /// inputs of the one before go, and its family with them.
    @Test func otherDataStartsASimulationOfItsOwn() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await storeTheSampleFamily(in: app)
        let model = app.simulatorModel
        model.setIncomeText("2 500 000")
        model.readTypedTexts()
        await model.load()
        await model.copyDeductionsAndFamily()
        #expect(model.family?.children.count == 2)

        await app.open(try #require(app.database))

        #expect(app.simulatorModel !== model)
        #expect(app.simulatorModel.incomeText == "")
        #expect(app.simulatorModel.family == FamilyYear(year: 2026, children: [], spouse: nil))
    }

    /// A new recovery code that fails after the vault has locked the data locks the app. What was entered for a
    /// simulation, the names and the days of birth of its children with it, goes with the data at once, not with the
    /// next unlock: the app no longer holds it.
    @Test func theSimulationGoesWhenTheDataLocks() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        try await storeTheSampleFamily(in: app)
        weak var entered: SimulatorModel?
        do {
            let model = app.simulatorModel
            model.setIncomeText("2 500 000")
            model.readTypedTexts()
            await model.load()
            await model.copyDeductionsAndFamily()
            #expect(model.family?.children.map(\.child.name) == ["Anna", "Tomáš"])
            entered = model
        }
        let trap = try VaultStepTrap.failingRekey(of: app)
        await #expect(throws: SQLiteError.self) {
            _ = try await app.commitNewRecoveryCode(try app.vault.prepareNewRecoveryCode())
        }
        trap.release()

        #expect(app.phase == .locked)
        #expect(entered == nil)
        #expect(app.simulatorModel.incomeText == "")
        #expect(app.simulatorModel.family == FamilyYear(year: 2026, children: [], spouse: nil))
    }

    @Test func theAppIsNotKeptAliveByTheSimulatorItHolds() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        weak var released: AppModel?
        var held: SimulatorModel?
        do {
            let app = try await makeApp(in: directory)
            held = app.simulatorModel
            // A typing pause that runs does not hold the app either.
            held?.setIncomeText("2 500 000")
            released = app
            await app.database?.close()
        }

        // The app and its data go when nothing else holds them.
        #expect(released == nil)
        // What is left of the simulation has no data to read, and says so.
        let orphan = try #require(held)
        await orphan.load()
        #expect(orphan.errorText == readFailureText)
        orphan.readTypedTexts()
    }

    // MARK: Nothing is stored

    @Test func nothingTheSimulatorDoesIsWritten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let familyBefore = try await storeTheSampleFamily(in: app)
        let storedBefore = try await database.yearSettings(2026)
        let versionBefore = app.dataVersion
        let delay = ManualDelay()
        let model = SimulatorModel(app: app, typingDelay: .milliseconds(500), wait: delay.wait)

        let steps: [(name: String, run: @MainActor () async throws -> Void)] = [
            ("load", { await model.load() }),
            ("a year without settings", { await model.selectYear(2023) }),
            ("the year of the sample", { await model.selectYear(2026) }),
            ("a rate", { model.setExpensePercent(40) }),
            ("an activity", { model.setActivity(.secondary) }),
            ("the health switch", { model.setHealthMinimumExempt(true) }),
            ("the credit", { model.setTaxpayerCredit(false) }),
            ("the limit of the interest", { model.setMortgageCap(.before2021) }),
            (
                "typing",
                {
                    model.setIncomeText("1 000 000")
                    model.setMonthsText("6")
                    for field in DeductionField.allCases {
                        model.setDeductionText(field, field.isMonthCount ? "6" : "1 000")
                    }
                    // What is typed waits for the typing to stop, and a quit does not wait for it: there is nothing to
                    // save.
                    #expect(!app.hasUnsavedInput)
                }
            ),
            (
                "the end of the wait",
                {
                    let unread = model.page
                    try await waitUntil { delay.armed == 1 }
                    #expect(delay.fire())
                    try await waitUntil { model.page != unread }
                }
            ),
            (
                "Return",
                {
                    model.setIncomeText("2 000 000")
                    model.readTypedTexts()
                }
            ),
            ("the copy", { await model.copyDeductionsAndFamily() }),
            (
                "a child",
                {
                    let dialog = ChildDialogModel(editing: model, year: 2026, child: nil, mode: .simulation)
                    dialog.name = "Ema"
                    dialog.birthDateText = "15. 6. 2026"
                    #expect(await dialog.save())
                }
            ),
            (
                "the spouse",
                {
                    try await model.setSpouse(
                        SpouseYear(
                            claim: true, months: MonthRange(from: 2, to: 12), ownIncomeKc: 0,
                            ztpp: MonthRange(from: 5, to: 6)))
                    model.setSpouseIncomeText("50 000")
                    model.readTypedTexts()
                }
            ),
            (
                "a removal",
                {
                    let anna = try #require(model.family?.children.first)
                    let dialog = ChildDialogModel(editing: model, year: 2026, child: anna, mode: .simulation)
                    #expect(await dialog.remove())
                }
            ),
            ("another year with the family", { await model.selectYear(2023) }),
            ("starting again", { await model.reset() }),
            (
                "the copy for a year without settings of its own",
                {
                    // 2023 has no settings and no rows of its own: the copy brings Anna, born in 2019, with the year a
                    // child starts with, as Zálohy a odpočty shows her for 2023, and not Tomáš, who is not born yet.
                    await model.selectYear(2023)
                    await model.copyDeductionsAndFamily()
                    let shownForTheYear = try await database.family(year: 2023)
                    #expect(shownForTheYear.children.map(\.child.name) == ["Anna"])
                    #expect(shownForTheYear.children.map(\.isStored) == [false])
                    #expect(model.family == shownForTheYear)
                }
            ),
        ]
        for step in steps {
            try await step.run()
            #expect(app.dataVersion == versionBefore, "\(step.name)")
        }

        #expect(try await database.yearSettings(2026) == storedBefore)
        #expect(try await database.storedSettingsYears() == [2026])
        #expect(try await database.family(year: 2026) == familyBefore)
    }
}

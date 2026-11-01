import Foundation
import Testing
@testable import InvoicesTracker

/// What the Simulátor shows for a simulation, as the builder makes it from the choices and from the result the tax
/// engine works out for them: the input of the engine, the result card (the key figure, the bar of the levies with the
/// rows of its popovers, the net income and the marginal levy), the four cards of the breakdown, the hints under the
/// deduction fields and the cards of the family. The worked example is 2026 with an income of 2 500 000 Kč, expenses at
/// 60 %, a main activity for the whole year, no deductions, the taxpayer credit and no family. Its levies, and those of
/// the other cases below, were worked out for the same data by a separate implementation of the rules (exact
/// fractions, run in Python); those with the family by hand. In every expected string `\u{00A0}` is the no-break space
/// and `\u{2212}` the minus.
struct SimulatorBuilderTests {
    // MARK: Helpers

    /// A row as the screen shows it: the texts, the sign in front of it and how it is set.
    private struct Shown: Equatable {
        var label: String
        var value: String
        var note: String?
        var sign: ComputationSign
        var style: ComputationRowStyle

        init(
            _ label: String, _ value: String, _ note: String? = nil, _ sign: ComputationSign = .blank,
            _ style: ComputationRowStyle = .plain
        ) {
            self.label = label
            self.value = value
            self.note = note
            self.sign = sign
            self.style = style
        }
    }

    private func shown(_ section: ComputationSection) -> [Shown] {
        section.rows.map { Shown($0.label, $0.value, $0.note, $0.sign, $0.style) }
    }

    private func row(_ label: String, in section: ComputationSection) throws -> ComputationRow {
        try #require(section.rows.first { $0.label == label }, "No row \(label) in \(section.title)")
    }

    /// The worked example unless a choice says otherwise. The switch of the health minimum is off, and the family is
    /// the one of the simulated year, as the model gives it: none unless `family` gives its children and its spouse.
    private func choose(
        year: Int = 2026, income: Int64 = 2_500_000, percent: Int = 60, activity: SimulatorActivity = .main,
        healthMinimumExempt: Bool = false, months: Int = 12, deductions: Deductions = Deductions(),
        credit: Bool = true, family: FamilyYear? = nil
    ) -> SimulatorInput {
        SimulatorInput(
            year: year, incomeKc: income, expensePercent: percent, activity: activity,
            healthMinimumExempt: healthMinimumExempt, months: months, deductions: deductions, taxpayerCredit: credit,
            family: FamilyYear(year: year, children: family?.children ?? [], spouse: family?.spouse))
    }

    /// The sample family: Anna (3. 9. 2019) and Tomáš (12. 4. 2024), the first and the second child, in the household
    /// the whole year and claimed by me, and a spouse without income of her own claimed for the whole year.
    private static let sampleFamily = FamilyYear(
        year: 2026,
        children: [
            FamilyChild(
                child: Child(id: 1, name: "Anna", birthDate: civilDate("2019-09-03")),
                year: ChildYear(household: MonthRange.wholeYear, claimant: .me, order: 1, ztpp: nil, studies: nil),
                isStored: true),
            FamilyChild(
                child: Child(id: 2, name: "Tomáš", birthDate: civilDate("2024-04-12")),
                year: ChildYear(household: MonthRange.wholeYear, claimant: .me, order: 2, ztpp: nil, studies: nil),
                isStored: true),
        ],
        spouse: SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil))

    /// The page for `choices`, built from what the engine works out for them.
    private func build(_ choices: SimulatorInput, rateFromSettings: Bool = false) throws -> SimulatorPage {
        SimulatorBuilder.page(try compute(choices), choices: choices, rateFromSettings: rateFromSettings)
    }

    private func isClose(_ actual: Double, _ expected: Double) -> Bool {
        abs(actual - expected) < 1e-9
    }

    private let titles = ["Daň z příjmů", "Sociální pojištění", "Zdravotní pojištění", "Čistý příjem"]

    /// What the net income says under its amount about the expenses of the business.
    private static let notSubtracted = "skutečné výdaje podnikání tu odečtené nejsou"

    /// The net income of the result card with `amount` a month and `year` for the whole year, both as written.
    private func netIncome(_ amount: String, year: String) -> SimulatorNetIncome {
        SimulatorNetIncome(
            label: "Čistý příjem průměrně za měsíc", amount: amount, sub: "za rok \(year) · \(Self.notSubtracted)")
    }

    /// The legend of the levy bar of `summary`: what each authority is paid, as its part writes it.
    private func legend(_ summary: SimulatorSummary) -> [String] {
        summary.levyBar.parts.map(\.legendValue)
    }

    /// The notes under the rows of the popovers of the levy bar of `summary`, tax first.
    private func notes(_ summary: SimulatorSummary) -> [String?] {
        summary.levyBar.parts.map(\.note)
    }

    /// A row of a popover of the Simulátor: "Za rok" is set strong, the other two muted.
    private func popoverRows(_ year: String, _ month: String, _ share: String) -> [LevyPopoverRow] {
        [
            LevyPopoverRow(label: "Za rok", value: year, style: .strong),
            LevyPopoverRow(label: "Měsíčně", value: month, style: .muted),
            LevyPopoverRow(label: "Z příjmu", value: share, style: .muted),
        ]
    }

    // MARK: The input of the engine

    @Test func theInputOfASimulationIsOneReceiptOnTheLastDayOfTheYear() {
        let input = SimulatorBuilder.input(choose())

        #expect(input.year == 2026)
        #expect(
            input.receipts == [
                Receipt(day: civilDate("2026-12-31"), czkNetHalere: 250_000_000, czkVatHalere: 0, source: .synthetic)
            ])
        #expect(input.months == [MonthActivity](repeating: .main, count: 12))
        #expect(input.healthExemptMonths.isEmpty)
        #expect(input.advances == .empty)
        #expect(input.taxpayerCredit)
        #expect(input.expensePercent == 60)
        #expect(input.deductions == Deductions())
    }

    @Test func theYearThePercentageTheDeductionsAndTheCreditGoToTheEngineAsTheyAre() {
        let deductions = Deductions(
            mortgageInterestPaid: 1, mortgageMonths: 7, mortgageCap: .before2021, lifeInsurance: 2, pensionSavings: 3,
            dip: 4, longTermCare: 5, gifts: 6)
        let input = SimulatorBuilder.input(
            choose(year: 2024, income: 10, percent: 30, deductions: deductions, credit: false))

        #expect(input.year == 2024)
        #expect(input.receipts.map(\.day) == [civilDate("2024-12-31")])
        #expect(input.receipts.map(\.czkNetHalere) == [1_000])
        #expect(input.receipts.map(\.czkVatHalere) == [0])
        #expect(input.expensePercent == 30)
        #expect(input.deductions == deductions)
        #expect(!input.taxpayerCredit)
    }

    @Test func aSecondaryActivityRunsFromJanuaryAndIsExemptFromTheHealthMinimumWithTheSwitchOn() {
        let input = SimulatorBuilder.input(choose(activity: .secondary, healthMinimumExempt: true, months: 5))

        #expect(
            input.months
                == [MonthActivity](repeating: .secondary, count: 5) + [MonthActivity](repeating: .inactive, count: 7))
        #expect(input.healthExemptMonths == Set(1...5))
    }

    /// A secondary activity alone grants no exemption: its months are those of a secondary activity all the same, and
    /// each of them has the health minimum.
    @Test func aSecondaryActivityWithoutTheSwitchHasNoExemptMonths() {
        let input = SimulatorBuilder.input(choose(activity: .secondary, months: 5))

        #expect(
            input.months
                == [MonthActivity](repeating: .secondary, count: 5) + [MonthActivity](repeating: .inactive, count: 7))
        #expect(input.healthExemptMonths.isEmpty)
    }

    @Test func aMainActivityRunsFromJanuaryAndHasNoExemptMonths() {
        let input = SimulatorBuilder.input(choose(months: 5))

        #expect(
            input.months
                == [MonthActivity](repeating: .main, count: 5) + [MonthActivity](repeating: .inactive, count: 7))
        #expect(input.healthExemptMonths.isEmpty)
    }

    /// The switch is for a secondary activity: the model keeps it while the main activity is chosen, and the engine
    /// is not told of it then.
    @Test func aMainActivityHasNoExemptMonthsWhateverTheSwitchSays() {
        let input = SimulatorBuilder.input(choose(healthMinimumExempt: true, months: 5))

        #expect(
            input.months
                == [MonthActivity](repeating: .main, count: 5) + [MonthActivity](repeating: .inactive, count: 7))
        #expect(input.healthExemptMonths.isEmpty)
    }

    /// The family goes to the engine as Zálohy a odpočty gives it: its children in their order, each with what the
    /// year says about it, and its spouse. Without one the engine gets an empty family.
    @Test func theFamilyGoesToTheEngineWithItsChildrenInTheirOrder() {
        let input = SimulatorBuilder.input(choose(family: Self.sampleFamily))

        #expect(input.family == FamilyFacts(Self.sampleFamily))
        #expect(input.family == TaxEngineFamilyTests.sampleFamily)
        #expect(input.family.children.map(\.label) == ["Anna", "Tomáš"])
        #expect(SimulatorBuilder.input(choose()).family == FamilyFacts())
    }

    // MARK: The result card

    @Test func theWorkedExampleOf2026() throws {
        let page = try build(choose(), rateFromSettings: true)
        let summary = page.summary

        // The key figure: the eyebrow with the year, the levies together, their share of the income right beside them
        // and the month under them, with no "≈" and no "z příjmů".
        #expect(
            summary.keyFigure
                == KeyFigureData(
                    eyebrow: "Odvody za rok 2026", figure: "460\u{00A0}690\u{00A0}Kč", share: "18,4\u{00A0}%",
                    sentence: "38\u{00A0}391\u{00A0}Kč měsíčně"))
        #expect(summary.keyFigure.sentenceEmphasis == nil)
        // The income less the levies is 2 039 310 Kč, which over the twelve months is 169 942,50 Kč, rounded away from
        // zero.
        #expect(
            summary.netIncome
                == SimulatorNetIncome(
                    label: "Čistý příjem průměrně za měsíc", amount: "169\u{00A0}943\u{00A0}Kč",
                    sub: "za rok 2\u{00A0}039\u{00A0}310\u{00A0}Kč · skutečné výdaje podnikání tu odečtené nejsou"))
        #expect(summary.marginal.total == "37,8\u{00A0}%")
        #expect(
            page.expenseNote
                == "Paušál je na stropu 1\u{00A0}200\u{00A0}000\u{00A0}Kč. Předvyplněno podle Nastavení roku 2026.")
        #expect(page.incomePerMonth == "≈ 208\u{00A0}333\u{00A0}Kč měsíčně")
    }

    /// The bar of the levies of the worked example: its header names what it shows and it has no total, as the key
    /// figure beside it is the total; each part is as heavy as its levy and has the legend of the amount; and the
    /// popover of each part has the levy of the year, the month and the share of the income, the shares being those of
    /// `IncomeShares`, so that they add up to the 18,4 % of the key figure (6,6 + 8,3 + 3,5), where the shares each
    /// rounded on its own would add up to 18,5.
    @Test func theBarOfTheWorkedExampleSaysTheYearTheMonthAndTheShareOfTheIncomeOfEachLevy() throws {
        let bar = try build(choose()).summary.levyBar

        #expect(bar.header == "Odvody podle úřadů")
        #expect(bar.total == nil)
        #expect(bar.totalShare == nil)
        #expect(bar.parts.map(\.authority) == [.tax, .social, .health])
        #expect(bar.parts.map(\.id) == [.tax, .social, .health])
        #expect(bar.parts.map(\.weight) == [164_160, 208_780, 87_750])
        #expect(
            bar.parts.map(\.legendValue) == [
                "164\u{00A0}160\u{00A0}Kč", "208\u{00A0}780\u{00A0}Kč", "87\u{00A0}750\u{00A0}Kč",
            ])
        #expect(
            bar.parts[0].rows == popoverRows("164\u{00A0}160\u{00A0}Kč", "13\u{00A0}680\u{00A0}Kč", "6,6\u{00A0}%"))
        // The social insurance is 8,3 % of the income, where the prototype's own rounding would say 8,4 %.
        #expect(
            bar.parts[1].rows == popoverRows("208\u{00A0}780\u{00A0}Kč", "17\u{00A0}398\u{00A0}Kč", "8,3\u{00A0}%"))
        // 87 750 Kč over twelve months is 7 312,50 Kč, rounded away from zero.
        #expect(
            bar.parts[2].rows == popoverRows("87\u{00A0}750\u{00A0}Kč", "7\u{00A0}313\u{00A0}Kč", "3,5\u{00A0}%"))
        #expect(bar.parts.map(\.shareLine) == [String?](repeating: nil, count: 3))
        #expect(bar.parts.map(\.note) == [String?](repeating: nil, count: 3))
    }

    /// VoiceOver reads the bar as a picture named by its header and the full names of the three authorities with their
    /// legends, and each item of the legend as the rows of its popover, and its note where there is one.
    @Test func theBarAndEachItemOfItsLegendAreReadAsWhatTheyShow() throws {
        let bar = try build(choose()).summary.levyBar

        #expect(
            bar.accessibilityLabel
                == "Odvody podle úřadů: Daň z příjmů 164\u{00A0}160\u{00A0}Kč,"
                + " Sociální pojištění 208\u{00A0}780\u{00A0}Kč, Zdravotní pojištění 87\u{00A0}750\u{00A0}Kč")
        #expect(
            bar.parts.map(\.accessibilityLabel) == [
                "Daň z příjmů: za rok 164\u{00A0}160\u{00A0}Kč, měsíčně 13\u{00A0}680\u{00A0}Kč,"
                    + " z příjmu 6,6\u{00A0}%",
                "Sociální pojištění: za rok 208\u{00A0}780\u{00A0}Kč, měsíčně 17\u{00A0}398\u{00A0}Kč,"
                    + " z příjmu 8,3\u{00A0}%",
                "Zdravotní pojištění: za rok 87\u{00A0}750\u{00A0}Kč, měsíčně 7\u{00A0}313\u{00A0}Kč,"
                    + " z příjmu 3,5\u{00A0}%",
            ])
        // The note is the only place the conditions are told, so VoiceOver reads it after the rows.
        let minimum = try build(choose(income: 0)).summary.levyBar
        #expect(
            minimum.parts[1].accessibilityLabel
                == "Sociální pojištění: za rok 60\u{00A0}056\u{00A0}Kč, měsíčně 5\u{00A0}005\u{00A0}Kč,"
                + " z příjmu —, platíte minimum")
    }

    /// The minimum insurance of the whole year, 99 720 Kč, is all the levies, so the year leaves −99 720 Kč, which over
    /// the twelve months is −8 310 Kč. Both are shown with the minus sign. There is no income for the levies to be a
    /// share of: the key figure has no share and asks for the income, and no popover has a share.
    @Test func withoutIncomeTheMinimumInsuranceIsShownAndTheLeviesAreOverTheIncome() throws {
        let page = try build(choose(income: 0))
        let summary = page.summary

        #expect(
            summary.keyFigure
                == KeyFigureData(
                    eyebrow: "Odvody za rok 2026", figure: "99\u{00A0}720\u{00A0}Kč", share: nil,
                    sentence: "zadejte příjem"))
        #expect(legend(summary) == ["0\u{00A0}Kč", "60\u{00A0}056\u{00A0}Kč", "39\u{00A0}664\u{00A0}Kč"])
        #expect(notes(summary) == [nil, "platíte minimum", "platíte minimum"])
        #expect(summary.levyBar.parts.map(\.weight) == [0, 60_056, 39_664])
        #expect(
            summary.levyBar.parts.map(\.rows) == [
                popoverRows("0\u{00A0}Kč", "0\u{00A0}Kč", "—"),
                popoverRows("60\u{00A0}056\u{00A0}Kč", "5\u{00A0}005\u{00A0}Kč", "—"),
                popoverRows("39\u{00A0}664\u{00A0}Kč", "3\u{00A0}305\u{00A0}Kč", "—"),
            ])
        #expect(
            summary.netIncome
                == SimulatorNetIncome(
                    label: "Čistý příjem průměrně za měsíc", amount: "\u{2212}8\u{00A0}310\u{00A0}Kč",
                    sub: "za rok \u{2212}99\u{00A0}720\u{00A0}Kč · skutečné výdaje podnikání tu odečtené nejsou"))
        #expect(page.incomePerMonth == nil)
    }

    @Test func whenTheLeviesEqualTheIncomeNothingIsLeftAndNothingIsOver() throws {
        // An income of 99 720 Kč pays no tax and the minimum insurance, which is 99 720 Kč.
        let summary = try build(choose(income: 99_720)).summary

        #expect(summary.keyFigure.figure == "99\u{00A0}720\u{00A0}Kč")
        #expect(summary.netIncome == netIncome("0\u{00A0}Kč", year: "0\u{00A0}Kč"))
        #expect(summary.keyFigure.share == "100,0\u{00A0}%")
        #expect(summary.keyFigure.sentence == "8\u{00A0}310\u{00A0}Kč měsíčně")
    }

    /// An income of 99 715 Kč pays no tax and the minimum insurance of 99 720 Kč, so the year leaves −5 Kč. That is
    /// below zero, and its average per month, −0,42 Kč, rounds to 0 Kč.
    @Test func aYearBelowZeroByAFewCrownsLeavesAnAverageThatRoundsToZero() throws {
        let summary = try build(choose(income: 99_715)).summary

        #expect(summary.keyFigure.figure == "99\u{00A0}720\u{00A0}Kč")
        #expect(summary.netIncome == netIncome("0\u{00A0}Kč", year: "\u{2212}5\u{00A0}Kč"))
    }

    @Test func aSecondaryActivityBelowTheDecisiveAmountPaysNoSocialInsurance() throws {
        // The health insurance is that of the profit alone, as the activity is exempt from the health minimum.
        let page = try build(choose(income: 100_000, activity: .secondary, healthMinimumExempt: true))
        let parts = page.summary.levyBar.parts

        #expect(parts[1].legendValue == "0\u{00A0}Kč")
        #expect(parts[1].note == "vedlejší činnost pod rozhodnou částkou – neplatí se")
        #expect(parts[2].legendValue == "2\u{00A0}700\u{00A0}Kč")
        #expect(parts[2].note == nil)
        #expect(page.summary.keyFigure.figure == "2\u{00A0}700\u{00A0}Kč")
        #expect(
            shown(page.sections[1]) == [
                Shown("Zisk", "40\u{00A0}000,00"),
                Shown("55\u{00A0}% zisku", "0", ComputationBuilder.secondaryNotInsured, .times),
                Shown("Minimální vyměřovací základ", "0"),
                Shown(
                    "Vyměřovací základ", "0",
                    "zisk 40\u{00A0}000 nedosáhl snížené rozhodné částky 117\u{00A0}521 – nic se nevyměřuje", .equals,
                    .strong),
                Shown("29,2\u{00A0}%", "0", "zaokrouhleno na celé koruny nahoru", .times),
                Shown("Sociální pojištění", "0\u{00A0}Kč", nil, .equals, .total),
            ])
    }

    /// A secondary activity whose profit is below the decisive amount (117 521 Kč in 2026, 40 000 Kč here) pays no
    /// social insurance. The popover of the social insurance says so under its rows: that is the only place the
    /// condition is told, and VoiceOver reads it after the rows of the item of the legend.
    @Test func aSideActivityBelowTheDecisiveAmountNotesThatItIsNotPaid() throws {
        let bar = try build(choose(income: 100_000, activity: .secondary, healthMinimumExempt: true)).summary.levyBar
        let social = bar.parts[1]

        #expect(social.authority == .social)
        #expect(social.note == "vedlejší činnost pod rozhodnou částkou – neplatí se")
        #expect(social.rows == popoverRows("0\u{00A0}Kč", "0\u{00A0}Kč", "0,0\u{00A0}%"))
        #expect(
            social.accessibilityLabel
                == "Sociální pojištění: za rok 0\u{00A0}Kč, měsíčně 0\u{00A0}Kč, z příjmu 0,0\u{00A0}%,"
                + " vedlejší činnost pod rozhodnou částkou – neplatí se")
        // A part of nothing is not drawn.
        #expect(social.weight == 0)
        #expect(bar.parts[0].note == nil)
        #expect(bar.parts[2].note == nil)
    }

    /// The share of the profit of a secondary activity that is not insured is nothing. It says why, in the words that
    /// Výpočet uses for the same row.
    @Test func theShareOfTheProfitOfAnUninsuredSecondaryActivitySaysItIsNotInsured() throws {
        let page = try build(choose(income: 100_000, activity: .secondary))
        let share = try row("55\u{00A0}% zisku", in: page.sections[1])

        #expect(share.value == "0")
        #expect(share.note == "vedlejší činnost není pojištěná")
        #expect(share.note == ComputationBuilder.secondaryNotInsured)
    }

    @Test func aHighIncomeReachesTheMaximumBaseAndThe23PercentBand() throws {
        let page = try build(choose(income: 6_000_000))

        #expect(notes(page.summary) == [nil, "dosažen maximální vyměřovací základ", nil])
        let high = try row("Daň 23\u{00A0}%", in: page.sections[0])
        #expect(high.sign == .plus)
        #expect(high.value == "698\u{00A0}553,24")
        #expect(high.note == "z 3\u{00A0}037\u{00A0}188 základu (pásmo nad 1\u{00A0}762\u{00A0}812)")
    }

    @Test func aSocialBaseExactlyAtTheMaximumReadsAsReached() throws {
        // From an income of 2 000 000 Kč on, the expenses at 60 % stay at their cap of 1 200 000 Kč. An income of
        // 5 473 482 Kč has a profit of 4 273 482 Kč, 55 % of which is 2 350 415,10 Kč, and that rounds up to the
        // maximum base of 2026, 2 350 416 Kč, exactly. So does the profit of the income a crown higher.
        let reached = "dosažen maximální vyměřovací základ"
        for income: Int64 in [5_473_482, 5_473_483] {
            let choices = choose(income: income)
            let social = try compute(choices).social
            #expect(social.computedBase == 2_350_416, "\(income)")
            #expect(social.maximumBase == 2_350_416, "\(income)")
            #expect(try build(choices).summary.levyBar.parts[1].note == reached, "\(income)")
        }
        // A crown less of income is a base a crown short of the maximum, without the note. A crown more than those two
        // is a base over the maximum, with it.
        let short = choose(income: 5_473_481)
        #expect(try compute(short).social.computedBase == 2_350_415)
        #expect(try build(short).summary.levyBar.parts[1].note == nil)
        let over = choose(income: 5_473_484)
        #expect(try compute(over).social.computedBase == 2_350_417)
        #expect(try build(over).summary.levyBar.parts[1].note == reached)
    }

    /// Each part of the bar weighs what its authority is paid, so the bar draws it as wide as its levy
    /// (`LevyBarLayout.partWidths`): the shares of the parts are those of the levies, and a levy of nothing is no part.
    @Test func theBarIsSplitByTheLevyOfEachAuthorityAndAZeroLevyIsNoPart() throws {
        let bar = try build(choose()).summary.levyBar
        let widths = LevyBarLayout.partWidths(weights: bar.parts.map(\.weight), width: 404)

        #expect(bar.parts.map(\.weight) == [164_160, 208_780, 87_750])
        // Two gaps of 2 points leave 400 for the three parts, shared as 164 160 : 208 780 : 87 750.
        #expect(abs(widths[0] - 400 * 164_160 / 460_690) < 0.001)
        #expect(abs(widths[1] - 400 * 208_780 / 460_690) < 0.001)
        #expect(abs(widths[2] - 400 * 87_750 / 460_690) < 0.001)
        // With no tax, the bar is the two insurances.
        let minimum = try build(choose(income: 0)).summary.levyBar
        #expect(minimum.parts.map(\.weight) == [0, 60_056, 39_664])
        let minimumWidths = LevyBarLayout.partWidths(weights: minimum.parts.map(\.weight), width: 402)
        #expect(minimumWidths[0] == 0)
        #expect(abs(minimumWidths[1] - 400 * 60_056 / 99_720) < 0.001)
    }

    /// 150 000 Kč with the sample family: the taxpayer credit takes the tax of 9 000 Kč, so the children's 37 524 Kč
    /// are all a bonus, as the income has reached six minimum wages (134 400 Kč). The tax reads as the bonus, what the
    /// year costs is the minimum insurance less the bonus, and the bar is of the insurance alone: a bonus is no part of
    /// it. Its popover reads the bonus, a month of it and its share of the income with the minus sign (U+2212).
    @Test func aNegativeTaxReadsAsBonusAndTheLevyBarLeavesItOut() throws {
        let page = try build(choose(income: 150_000, family: Self.sampleFamily))
        let summary = page.summary

        #expect(summary.levyBar.parts.map(\.authority) == [.tax, .social, .health])
        #expect(
            legend(summary) == ["bonus 37\u{00A0}524\u{00A0}Kč", "60\u{00A0}056\u{00A0}Kč", "39\u{00A0}664\u{00A0}Kč"])
        #expect(notes(summary) == [nil, "platíte minimum", "platíte minimum"])
        #expect(
            summary.levyBar.parts[0].rows
                == popoverRows(
                    "bonus 37\u{00A0}524\u{00A0}Kč", "\u{2212}3\u{00A0}127\u{00A0}Kč", "\u{2212}25,0\u{00A0}%")
        )
        // The shares of the three add up to the 41,5 % of the key figure, as the tax of −25,0 % is part of them.
        #expect(
            summary.levyBar.parts.map { $0.rows[2].value } == [
                "\u{2212}25,0\u{00A0}%", "40,0\u{00A0}%", "26,5\u{00A0}%",
            ])
        // 60 056 + 39 664 − 37 524 Kč.
        #expect(
            summary.keyFigure
                == KeyFigureData(
                    eyebrow: "Odvody za rok 2026", figure: "62\u{00A0}196\u{00A0}Kč", share: "41,5\u{00A0}%",
                    sentence: "5\u{00A0}183\u{00A0}Kč měsíčně"))
        // The income less the levies, 150 000 − 62 196 Kč, is 87 804 Kč, which is 7 317 Kč a month.
        #expect(summary.netIncome == netIncome("7\u{00A0}317\u{00A0}Kč", year: "87\u{00A0}804\u{00A0}Kč"))
        // The bar is that of the minimum insurance alone, as without income: a bonus is no part of it.
        #expect(summary.levyBar.parts.map(\.weight) == [-37_524, 60_056, 39_664])
        let widths = LevyBarLayout.partWidths(weights: summary.levyBar.parts.map(\.weight), width: 402)
        #expect(widths[0] == 0)
        #expect(abs(widths[1] - 400 * 60_056 / 99_720) < 0.001)
        #expect(abs(widths[2] - 400 * 39_664 / 99_720) < 0.001)

        // The card of the tax goes through the steps of the family to the negative tax.
        #expect(
            shown(page.sections[0]).suffix(6) == [
                Shown("Daň 15\u{00A0}%", "9\u{00A0}000", "z 60\u{00A0}000 základu (pásmo do 1\u{00A0}762\u{00A0}812)"),
                Shown(
                    "Sleva na poplatníka", "\u{2212}9\u{00A0}000",
                    "roční sleva 30\u{00A0}840 se uplatní nejvýše do výše daně", .minus),
                Shown(
                    "Sleva na manžela / manželku", "0",
                    "12\u{00A0}měsíců s dítětem do 3 let · daň už je nulová, sleva se neprojeví", .minus),
                Shown("Daň po slevách", "0", "slevy snižují daň nejvýš na nulu", .equals, .strong),
                Shown(
                    "Daňové zvýhodnění na děti", "\u{2212}37\u{00A0}524",
                    "Anna 15\u{00A0}204 · Tomáš 22\u{00A0}320 · z toho daňový bonus 37\u{00A0}524", .minus),
                Shown(
                    "Daň z příjmů", "\u{2212}37\u{00A0}524\u{00A0}Kč",
                    "záporná daň je daňový bonus – vyplatí ho finanční úřad", .equals, .total),
            ])
        // The card of the children says the bonus is paid, without what the return asks for.
        #expect(page.family.children.proofHint == nil)
        #expect(
            page.family.children.hint
                == "Zvýhodnění převyšuje daň o 37\u{00A0}524\u{00A0}Kč – tolik vám finanční úřad vyplatí jako daňový"
                + " bonus.")
    }

    /// The worked example with the sample family: after the taxpayer credit the spouse credit takes 24 840 Kč off the
    /// tax of 164 160 Kč and the children 37 524 Kč more, Anna 15 204 Kč as the first child and Tomáš 22 320 Kč as the
    /// second. The rows of the family are those of Výpočet for the same result, and the cards of the family show the
    /// family as Zálohy a odpočty does, without what the return asks for.
    @Test func theTaxCardHasTheStepsOfTheFamilyAsVýpočetHasThem() throws {
        let choices = choose(family: Self.sampleFamily)
        let result = try compute(choices)
        // The engine computed the family: a credit for each of its children, which the cards take.
        try #require(result.family.children.count == 2)
        let page = SimulatorBuilder.page(result, choices: choices, rateFromSettings: false)
        let tax = page.sections[0]

        #expect(
            shown(tax).suffix(5) == [
                Shown("Sleva na poplatníka", "\u{2212}30\u{00A0}840", "celá roční částka", .minus),
                Shown(
                    "Sleva na manžela / manželku", "\u{2212}24\u{00A0}840", "12\u{00A0}měsíců s dítětem do 3 let",
                    .minus),
                Shown("Daň po slevách", "139\u{00A0}320", "slevy snižují daň nejvýš na nulu", .equals, .strong),
                Shown(
                    "Daňové zvýhodnění na děti", "\u{2212}37\u{00A0}524", "Anna 15\u{00A0}204 · Tomáš 22\u{00A0}320",
                    .minus),
                Shown("Daň z příjmů", "101\u{00A0}796\u{00A0}Kč", nil, .equals, .total),
            ])
        let vypocet = ComputationBuilder.build(
            result, input: SimulatorBuilder.input(choices), today: civilDate("2026-12-31"), incomeFXMethod: .cnbDaily)
        let familyLabels = ["Sleva na manžela / manželku", "Daň po slevách", "Daňové zvýhodnění na děti"]
        let vypocetTax = try #require(vypocet.first { $0.title == "Daň z příjmů" })
        #expect(
            tax.rows.filter { familyLabels.contains($0.label) }
                == vypocetTax.rows.filter { familyLabels.contains($0.label) })
        #expect(page.summary.levyBar.parts[0].legendValue == "101\u{00A0}796\u{00A0}Kč")
        #expect(page.summary.keyFigure.figure == "398\u{00A0}326\u{00A0}Kč")

        #expect(
            page.family
                == FamilyCardsBuilder.content(
                    family: choices.family, result: result, mode: .simulation, isWholeYear: true))
        #expect(page.family.children.total == "37\u{00A0}524\u{00A0}Kč za rok")
        #expect(page.family.children.rows.map(\.name) == ["Anna", "Tomáš"])
        #expect(page.family.children.hint == nil)
        #expect(page.family.spouse.total == "24\u{00A0}840\u{00A0}Kč za rok")
    }

    /// Without a family the cards of the family have no child and no claimed spouse, and the tax card no step of it.
    @Test func withoutAFamilyTheCardsAreEmptyAndTheTaxCardHasNoStepOfIt() throws {
        let page = try build(choose())

        #expect(page.family.children.rows.isEmpty)
        #expect(page.family.children.total == nil)
        #expect(page.family.children.hint == nil)
        #expect(page.family.spouse.total == nil)
        #expect(page.family.spouse.result == nil)
        #expect(
            !page.sections[0].rows.map(\.label).contains { label in
                ["Sleva na manžela / manželku", "Daň po slevách", "Daňové zvýhodnění na děti"].contains(label)
            })
    }

    @Test func aSecondaryActivityExemptFromTheHealthMinimumWithoutIncomeHasNothingToPayAndAnEmptyBar() throws {
        let summary = try build(choose(income: 0, activity: .secondary, healthMinimumExempt: true)).summary

        #expect(
            summary.keyFigure
                == KeyFigureData(
                    eyebrow: "Odvody za rok 2026", figure: "0\u{00A0}Kč", share: nil, sentence: "zadejte příjem"))
        // No part of the bar is drawn: the track stays empty.
        #expect(summary.levyBar.parts.map(\.weight) == [0, 0, 0])
        #expect(summary.netIncome == netIncome("0\u{00A0}Kč", year: "0\u{00A0}Kč"))
        // Nothing is paid on such a secondary activity without income: no minimum, and the social insurance says why.
        #expect(legend(summary) == ["0\u{00A0}Kč", "0\u{00A0}Kč", "0\u{00A0}Kč"])
        #expect(notes(summary) == [nil, "vedlejší činnost pod rozhodnou částkou – neplatí se", nil])
        #expect(summary.levyBar.parts.allSatisfy { $0.rows[2].value == "—" })
    }

    @Test func theMonthlyFiguresAreRoundedHalfUp() throws {
        // 6 Kč a year is exactly half a crown a month, which is 1 Kč; 30 Kč is 2,50 Kč, which is 3 Kč; 5 Kč is 0,42 Kč.
        #expect(try build(choose(income: 6)).incomePerMonth == "≈ 1\u{00A0}Kč měsíčně")
        #expect(try build(choose(income: 30)).incomePerMonth == "≈ 3\u{00A0}Kč měsíčně")
        #expect(try build(choose(income: 5)).incomePerMonth == "≈ 0\u{00A0}Kč měsíčně")
        // Seven months of main activity on 100 000 Kč pay the minimum insurances and no tax: 58 170 Kč, which is
        // 4 847,50 Kč a month.
        let key = try build(choose(income: 100_000, months: 7)).summary.keyFigure
        #expect(key.sentence == "4\u{00A0}848\u{00A0}Kč měsíčně")
        #expect(key.share == "58,2\u{00A0}%")
    }

    // MARK: The breakdown

    @Test func theBreakdownOfTheTaxNamesEachStep() throws {
        let sections = try build(choose()).sections
        let tax = sections[0]

        #expect(sections.map(\.title) == titles)
        #expect(sections.map(\.authority) == [.tax, .social, .health, nil])
        #expect(sections.map(\.tag) == [nil, nil, nil, nil])
        // The net income is the last card, about no authority, and it stands on the right with the two insurances.
        #expect(sections.map(\.isNetIncome) == [false, false, false, true])
        #expect(sections.map(\.standsRight) == [false, true, true, true])
        #expect(tax.title == "Daň z příjmů")
        #expect(tax.authority == .tax)
        #expect(
            tax.rows.map(\.label) == [
                "Příjmy", "Výdaje paušálem 60\u{00A0}%", "Zisk", "Odpočty", "Základ daně", "Daň 15\u{00A0}%",
                "Sleva na poplatníka", "Daň z příjmů",
            ])
        #expect(tax.rows.map(\.sign) == [.blank, .minus, .equals, .minus, .equals, .blank, .minus, .equals])
        #expect(tax.rows.last?.style == .total)
    }

    @Test func theCardsOfTheWorkedExampleShowEachStepWithItsValueAndNote() throws {
        let sections = try build(choose()).sections

        #expect(
            shown(sections[0]) == [
                Shown("Příjmy", "2\u{00A0}500\u{00A0}000,00"),
                Shown(
                    "Výdaje paušálem 60\u{00A0}%", "\u{2212}1\u{00A0}200\u{00A0}000,00",
                    "60\u{00A0}% je 1\u{00A0}500\u{00A0}000,00 → použije se strop 1\u{00A0}200\u{00A0}000", .minus),
                Shown("Zisk", "1\u{00A0}300\u{00A0}000,00", nil, .equals, .strong),
                Shown("Odpočty", "0,00", "úroky · spoření · dary", .minus),
                Shown("Základ daně", "1\u{00A0}300\u{00A0}000", "zaokrouhlený dolů na stovky", .equals, .strong),
                Shown(
                    "Daň 15\u{00A0}%", "195\u{00A0}000",
                    "z 1\u{00A0}300\u{00A0}000 základu (pásmo do 1\u{00A0}762\u{00A0}812)"),
                Shown("Sleva na poplatníka", "\u{2212}30\u{00A0}840", "celá roční částka", .minus),
                Shown("Daň z příjmů", "164\u{00A0}160\u{00A0}Kč", nil, .equals, .total),
            ])
        #expect(
            shown(sections[1]) == [
                Shown("Zisk", "1\u{00A0}300\u{00A0}000,00"),
                Shown("55\u{00A0}% zisku", "715\u{00A0}000", "zaokrouhleno nahoru", .times),
                Shown("Minimální vyměřovací základ", "205\u{00A0}668", "17\u{00A0}139 × 12\u{00A0}měsíců"),
                Shown(
                    "Vyměřovací základ", "715\u{00A0}000",
                    "vyšší z obou · max. 2\u{00A0}350\u{00A0}416 (roční strop, nekrátí se)", .equals, .strong),
                Shown("29,2\u{00A0}%", "208\u{00A0}780", "zaokrouhleno na celé koruny nahoru", .times),
                Shown("Sociální pojištění", "208\u{00A0}780\u{00A0}Kč", nil, .equals, .total),
            ])
        #expect(
            shown(sections[2]) == [
                Shown("Zisk", "1\u{00A0}300\u{00A0}000,00"),
                Shown("50\u{00A0}% zisku", "650\u{00A0}000,00", nil, .times),
                Shown("Minimální vyměřovací základ", "293\u{00A0}802,00", "24\u{00A0}483,50 × 12\u{00A0}měsíců"),
                Shown(
                    "Vyměřovací základ", "650\u{00A0}000,00", "vyšší z obou · bez maxima, nezaokrouhluje se", .equals,
                    .strong),
                Shown("13,5\u{00A0}%", "87\u{00A0}750", "zaokrouhleno na celé koruny nahoru", .times),
                Shown("Zdravotní pojištění", "87\u{00A0}750\u{00A0}Kč", nil, .equals, .total),
            ])
    }

    @Test func theSocialMultiplierNamesTheShareOfTheProfitOfTheYear() throws {
        // 50 % of the profit before 2024, 55 % from then on; the health insurance is always half.
        for (year, share) in [(2022, "50"), (2023, "50"), (2024, "55"), (2025, "55"), (2026, "55")] {
            let sections = try build(choose(year: year, income: 1_000_000)).sections

            #expect(sections[1].rows[1].label == "\(share)\u{00A0}% zisku", "\(year)")
            #expect(sections[2].rows[1].label == "50\u{00A0}% zisku", "\(year)")
        }
    }

    @Test func aSecondaryActivityAboveTheDecisiveAmountIsAssessedAtItsOwnMinimum() throws {
        let page = try build(choose(income: 1_000_000, activity: .secondary, healthMinimumExempt: true))

        #expect(
            legend(page.summary) == ["29\u{00A0}160\u{00A0}Kč", "64\u{00A0}240\u{00A0}Kč", "27\u{00A0}000\u{00A0}Kč"])
        #expect(notes(page.summary) == [String?](repeating: nil, count: 3))
        #expect(
            shown(page.sections[1]) == [
                Shown("Zisk", "400\u{00A0}000,00"),
                Shown("55\u{00A0}% zisku", "220\u{00A0}000", "zaokrouhleno nahoru", .times),
                Shown("Minimální vyměřovací základ", "64\u{00A0}644", "5\u{00A0}387 × 12\u{00A0}měsíců"),
                Shown(
                    "Vyměřovací základ", "220\u{00A0}000",
                    "vyšší z obou · max. 2\u{00A0}350\u{00A0}416 (roční strop, nekrátí se)", .equals, .strong),
                Shown("29,2\u{00A0}%", "64\u{00A0}240", "zaokrouhleno na celé koruny nahoru", .times),
                Shown("Sociální pojištění", "64\u{00A0}240\u{00A0}Kč", nil, .equals, .total),
            ])
        #expect(
            shown(page.sections[2]) == [
                Shown("Zisk", "400\u{00A0}000,00"),
                Shown("50\u{00A0}% zisku", "200\u{00A0}000,00", nil, .times),
                Shown("Minimální vyměřovací základ", "0,00", Self.exemptNote),
                Shown(
                    "Vyměřovací základ", "200\u{00A0}000,00", "vyšší z obou · bez maxima, nezaokrouhluje se", .equals,
                    .strong),
                Shown("13,5\u{00A0}%", "27\u{00A0}000", "zaokrouhleno na celé koruny nahoru", .times),
                Shown("Zdravotní pojištění", "27\u{00A0}000\u{00A0}Kč", nil, .equals, .total),
            ])
    }

    @Test func theMinimumInsuranceNotesNameTheMonthsOfTheActivity() throws {
        let sections = try build(choose(income: 100_000, months: 5)).sections

        #expect(try row("Minimální vyměřovací základ", in: sections[1]).note == "17\u{00A0}139 × 5\u{00A0}měsíců")
        #expect(try row("Minimální vyměřovací základ", in: sections[2]).note == "24\u{00A0}483,50 × 5\u{00A0}měsíců")
        #expect(try row("Minimální vyměřovací základ", in: sections[1]).value == "85\u{00A0}695")
        #expect(try row("Minimální vyměřovací základ", in: sections[2]).value == "122\u{00A0}417,50")
        // One month is "1 měsíc".
        let single = try build(choose(income: 100_000, months: 1)).sections
        #expect(try row("Minimální vyměřovací základ", in: single[1]).note == "17\u{00A0}139 × 1\u{00A0}měsíc")
    }

    @Test func withoutIncomeTheTaxCardIsAllZeros() throws {
        let tax = try build(choose(income: 0)).sections[0]

        #expect(
            shown(tax) == [
                Shown("Příjmy", "0,00"),
                Shown(
                    "Výdaje paušálem 60\u{00A0}%", "0,00",
                    "60\u{00A0}% z příjmů, zaokrouhleno dolů · strop 1\u{00A0}200\u{00A0}000 nedosažen", .minus),
                Shown("Zisk", "0,00", nil, .equals, .strong),
                Shown("Odpočty", "0,00", "úroky · spoření · dary", .minus),
                Shown("Základ daně", "0", "zaokrouhlený dolů na stovky", .equals, .strong),
                Shown("Daň 15\u{00A0}%", "0", "z 0 základu (pásmo do 1\u{00A0}762\u{00A0}812)"),
                Shown(
                    "Sleva na poplatníka", "0", "roční sleva 30\u{00A0}840 se uplatní nejvýše do výše daně", .minus),
                Shown("Daň z příjmů", "0\u{00A0}Kč", nil, .equals, .total),
            ])
    }

    @Test func theTaxCardShowsBothBandsAndSaysThatTheirSumIsRoundedUp() throws {
        let tax = try build(choose(income: 6_000_000)).sections[0]

        #expect(
            shown(tax) == [
                Shown("Příjmy", "6\u{00A0}000\u{00A0}000,00"),
                Shown(
                    "Výdaje paušálem 60\u{00A0}%", "\u{2212}1\u{00A0}200\u{00A0}000,00",
                    "60\u{00A0}% je 3\u{00A0}600\u{00A0}000,00 → použije se strop 1\u{00A0}200\u{00A0}000", .minus),
                Shown("Zisk", "4\u{00A0}800\u{00A0}000,00", nil, .equals, .strong),
                Shown("Odpočty", "0,00", "úroky · spoření · dary", .minus),
                Shown("Základ daně", "4\u{00A0}800\u{00A0}000", "zaokrouhlený dolů na stovky", .equals, .strong),
                Shown(
                    "Daň 15\u{00A0}%", "264\u{00A0}421,80",
                    "z 1\u{00A0}762\u{00A0}812 základu (pásmo do 1\u{00A0}762\u{00A0}812)"),
                Shown(
                    "Daň 23\u{00A0}%", "698\u{00A0}553,24",
                    "z 3\u{00A0}037\u{00A0}188 základu (pásmo nad 1\u{00A0}762\u{00A0}812)", .plus),
                Shown("Sleva na poplatníka", "\u{2212}30\u{00A0}840", "celá roční částka", .minus),
                Shown(
                    "Daň z příjmů", "932\u{00A0}136\u{00A0}Kč",
                    "daň před slevou 962\u{00A0}976, zaokrouhleno na celé koruny nahoru", .equals, .total),
            ])
    }

    @Test func theDeductionsRowCountsWhatTheLawAllowsAndSaysWhenTheProfitCutsItOff() throws {
        let claims = Deductions(
            mortgageInterestPaid: 200_000, lifeInsurance: 10_000, pensionSavings: 20_000, gifts: 30_000)
        let counted = try build(choose(deductions: claims)).sections[0]

        // The interest is held to the limit of 150 000 Kč, and the retirement products and the gifts are within theirs.
        let deductions = try row("Odpočty", in: counted)
        #expect(deductions.value == "\u{2212}210\u{00A0}000,00")
        #expect(deductions.note == "úroky · spoření · dary")
        #expect(deductions.sign == .minus)
        #expect(try row("Základ daně", in: counted).value == "1\u{00A0}090\u{00A0}000")
        #expect(try row("Daň z příjmů", in: counted).value == "132\u{00A0}660\u{00A0}Kč")

        // The deductions cannot take more than the profit, which is 40 000 Kč here, and the note says so.
        let cut = try build(choose(income: 100_000, deductions: Deductions(mortgageInterestPaid: 150_000))).sections[0]
        let cutRow = try row("Odpočty", in: cut)
        #expect(cutRow.value == "\u{2212}40\u{00A0}000,00")
        #expect(cutRow.note == "úroky · spoření · dary – celkem nejvýše do výše zisku")

        // Before 2024 pension savings and life insurance have a limit each, and both count.
        let separate = try build(
            choose(year: 2023, deductions: Deductions(lifeInsurance: 10_000, pensionSavings: 5_000))
        ).sections[0]
        #expect(try row("Odpočty", in: separate).value == "\u{2212}15\u{00A0}000,00")
        #expect(try row("Odpočty", in: separate).note == "úroky · spoření · dary")
    }

    @Test func theCreditRowSaysWhetherAndHowMuchOfItApplies() throws {
        // Switched off, it takes nothing off the tax of 195 000 Kč.
        let off = try build(choose(credit: false)).sections[0]
        let creditOff = try row("Sleva na poplatníka", in: off)
        #expect(creditOff.value == "0")
        #expect(creditOff.note == "neuplatňuje se")
        #expect(try row("Daň z příjmů", in: off).value == "195\u{00A0}000\u{00A0}Kč")

        // A tax of 6 000 Kč can use only 6 000 Kč of the credit of 30 840 Kč.
        let small = try build(choose(income: 100_000)).sections[0]
        let creditSmall = try row("Sleva na poplatníka", in: small)
        #expect(creditSmall.value == "\u{2212}6\u{00A0}000")
        #expect(creditSmall.note == "roční sleva 30\u{00A0}840 se uplatní nejvýše do výše daně")
        #expect(try row("Daň z příjmů", in: small).value == "0\u{00A0}Kč")
    }

    // MARK: The card of the net income

    /// The card of the net income of the worked example: 2 500 000 Kč less the tax of 164 160 Kč, the social insurance
    /// of 208 780 Kč and the health insurance of 87 750 Kč leaves 2 039 310 Kč, which is 81,6 % of the income and,
    /// over the twelve months of the year, 169 943 Kč a month. The Simulátor words the card for itself: the first row
    /// is "Příjmy", the result is "Čistý příjem za rok", the share is of "příjmu" (in the singular), the title has no
    /// tag and the row of the months no note.
    @Test func theNetIncomeCardOfTheWorkedExampleTakesTheLeviesOffTheIncome() throws {
        let page = try build(choose())
        let card = page.sections[3]

        #expect(card.title == "Čistý příjem")
        #expect(card.tag == nil)
        #expect(card.authority == nil)
        #expect(card.isNetIncome)
        #expect(
            shown(card) == [
                Shown("Příjmy", "2\u{00A0}500\u{00A0}000,00", "bez DPH"),
                Shown("Daň z příjmů", "\u{2212}164\u{00A0}160", nil, .minus),
                Shown("Sociální pojištění", "\u{2212}208\u{00A0}780", nil, .minus),
                Shown("Zdravotní pojištění", "\u{2212}87\u{00A0}750", nil, .minus),
                Shown(
                    "Čistý příjem za rok", "2\u{00A0}039\u{00A0}310",
                    "81,6\u{00A0}% příjmu · skutečné výdaje podnikání tu odečtené nejsou", .equals, .strong),
                Shown("12\u{00A0}měsíců", "12", nil, .divided),
                Shown(
                    "Průměrně za měsíc", "169\u{00A0}943\u{00A0}Kč", "čistý příjem na jeden měsíc", .equals, .total),
            ])
        // The result card says the figures of the card.
        let year = try row("Čistý příjem za rok", in: card)
        #expect(try row("Průměrně za měsíc", in: card).value == page.summary.netIncome.amount)
        #expect(page.summary.netIncome.sub == "za rok \(year.value)\u{00A0}Kč · \(Self.notSubtracted)")
    }

    /// Without income the minimum insurance of the whole year is all the levies, so the year leaves −99 720 Kč, which
    /// is −8 310 Kč a month. There is no income for the levies to take a part of, so the result has no share, only the
    /// words that the expenses of the business are not taken off.
    @Test func withoutIncomeTheNetIncomeCardIsNegativeAndHasNoShare() throws {
        let card = try build(choose(income: 0)).sections[3]

        #expect(
            shown(card) == [
                Shown("Příjmy", "0,00", "bez DPH"),
                Shown("Daň z příjmů", "0", nil, .minus),
                Shown("Sociální pojištění", "\u{2212}60\u{00A0}056", nil, .minus),
                Shown("Zdravotní pojištění", "\u{2212}39\u{00A0}664", nil, .minus),
                Shown("Čistý příjem za rok", "\u{2212}99\u{00A0}720", Self.notSubtracted, .equals, .strong),
                Shown("12\u{00A0}měsíců", "12", nil, .divided),
                Shown(
                    "Průměrně za měsíc", "\u{2212}8\u{00A0}310\u{00A0}Kč", "čistý příjem na jeden měsíc", .equals,
                    .total),
            ])
    }

    /// 150 000 Kč with the sample family: the tax is a bonus of 37 524 Kč, which the tax office pays, so the card adds
    /// it to the income in place of the tax, as Výpočet does, and the figures of its rows are those of Výpočet for the
    /// same result.
    @Test func aTaxBonusIsAddedToTheNetIncomeAsVypocetAddsIt() throws {
        let choices = choose(income: 150_000, family: Self.sampleFamily)
        let result = try compute(choices)
        let card = SimulatorBuilder.page(result, choices: choices, rateFromSettings: false).sections[3]

        #expect(
            card.rows.map(\.label) == [
                "Příjmy", "Daňový bonus", "Sociální pojištění", "Zdravotní pojištění", "Čistý příjem za rok",
                "12\u{00A0}měsíců", "Průměrně za měsíc",
            ])
        #expect(
            card.rows[1]
                == ComputationRow(
                    label: "Daňový bonus", value: "37\u{00A0}524", note: "vyplatí ho finanční úřad", sign: .plus))
        #expect(try row("Čistý příjem za rok", in: card).value == "87\u{00A0}804")
        let vypocet = ComputationBuilder.build(
            result, input: SimulatorBuilder.input(choices), today: civilDate("2026-12-31"), incomeFXMethod: .cnbDaily)
        let vypocetCard = try #require(vypocet.first { $0.isNetIncome })
        #expect(card.rows.map(\.value) == vypocetCard.rows.map(\.value))
    }

    // MARK: The health minimum of a secondary activity

    /// The note of the minimum base of the health insurance for months without the minimum. It names the reasons for
    /// one: employment, studies, a pension, parental leave, ZTP/P and the like.
    private static let exemptNote =
        "minimum neplatíte – po celé měsíce zaměstnání, studium, důchod, rodičovská, ZTP/P a podobně"

    /// The cases below are one month of 2025 on an income of 5 000 Kč with expenses at 60 %: the profit is 2 000 Kč and
    /// the base of the health insurance, half of it, 1 000 Kč. The minimum of a month is 23 278,50 Kč, which makes the
    /// insurance 3 143 Kč (13,5 % of it, rounded up); without the minimum it is 135 Kč (13,5 % of 1 000 Kč).
    @Test func vedlejsiActivityWithoutTheSwitchPaysTheHealthMinimum() throws {
        let page = try build(choose(year: 2025, income: 5_000, percent: 60, activity: .secondary, months: 1))

        let health = page.summary.levyBar.parts[2]
        #expect(health.legendValue == "3\u{00A0}143\u{00A0}Kč")
        #expect(health.note == "platíte minimum")
        let minimum = try row("Minimální vyměřovací základ", in: page.sections[2])
        #expect(minimum.value == "23\u{00A0}278,50")
        #expect(minimum.note == "23\u{00A0}278,50 × 1\u{00A0}měsíc")
    }

    @Test func vedlejsiActivityWithTheSwitchIsExemptFromTheHealthMinimum() throws {
        let page = try build(
            choose(
                year: 2025, income: 5_000, percent: 60, activity: .secondary, healthMinimumExempt: true, months: 1))

        let health = page.summary.levyBar.parts[2]
        #expect(health.legendValue == "135\u{00A0}Kč")
        #expect(health.note == nil)
        let minimum = try row("Minimální vyměřovací základ", in: page.sections[2])
        #expect(minimum.value == "0,00")
        #expect(minimum.note == Self.exemptNote)
    }

    /// The switch is for a secondary activity: with a main one it changes nothing on the page, whatever it says.
    @Test func hlavniActivityAlwaysPaysTheMinimum() throws {
        let page = try build(
            choose(year: 2025, income: 5_000, percent: 60, activity: .main, healthMinimumExempt: true, months: 1))

        #expect(page.summary.levyBar.parts[2].legendValue == "3\u{00A0}143\u{00A0}Kč")
        let minimum = try row("Minimální vyměřovací základ", in: page.sections[2])
        #expect(minimum.note == "23\u{00A0}278,50 × 1\u{00A0}měsíc")
        let withoutTheSwitch = try build(
            choose(year: 2025, income: 5_000, percent: 60, activity: .main, months: 1))
        #expect(page == withoutTheSwitch)
    }

    // MARK: The marginal levy

    /// What the next thousand crowns of income cost in the worked example, in the words of the Simulátor: the total
    /// and the rates of the bar are those of Výpočet for the same result (15 %, 16,06 % and 6,75 % of the whole width),
    /// the sentence names whole crowns for a thousand, and the flat-rate expenses are at their cap, so the next crown
    /// is all profit. The parts of the sentence add up to its sum: 150 + 161 + 67 = 378, where the prototype's own
    /// rounding of each part (150, 161 and 68) says 379.
    @Test func theMarginalLevyOfTheWorkedExampleSaysWhatTheNextThousandCrownsCost() throws {
        let choices = choose()
        let result = try compute(choices)
        let marginal = SimulatorBuilder.page(result, choices: choices, rateFromSettings: false).summary.marginal
        let vypocet = ComputationBuilder.marginal(of: result)

        #expect(marginal.total == "37,8\u{00A0}%")
        #expect(marginal.total == vypocet.total)
        #expect(marginal.shares == vypocet.shares)
        #expect(marginal.shares.map(\.authority) == [.tax, .social, .health])
        // The parts of its bar are the rates themselves, as on Výpočet: 15 %, 16,06 % and 6,75 % of the whole width.
        #expect(isClose(marginal.shares[0].fraction, 0.15))
        #expect(isClose(marginal.shares[1].fraction, 0.1606))
        #expect(isClose(marginal.shares[2].fraction, 0.0675))
        #expect(
            marginal.text
                == "Z každé další tisícovky příjmu odvedete 378\u{00A0}Kč: daň 150\u{00A0}Kč,"
                + " sociální 161\u{00A0}Kč a zdravotní 67\u{00A0}Kč."
                + " Paušál je na stropu, takže každá další koruna je celá zisk.")
    }

    /// 1 000 000 Kč at 60 % is below the cap of the expenses: of each further crown the flat rate covers 60 %, so the
    /// tax takes 6 % of it (15 % of the 40 % that is profit), the social insurance 6,424 % (29,2 % of 55 % of that
    /// profit) and the health insurance nothing, as it stays at its minimum. The sentence says that part of each crown
    /// is still covered.
    @Test func belowTheCapOfTheExpensesTheMarginalLevySaysThatTheFlatRateStillCoversPartOfTheNextCrown() throws {
        let marginal = try build(choose(income: 1_000_000)).summary.marginal

        #expect(marginal.total == "12,4\u{00A0}%")
        #expect(
            marginal.text
                == "Z každé další tisícovky příjmu odvedete 124\u{00A0}Kč: daň 60\u{00A0}Kč,"
                + " sociální 64\u{00A0}Kč a zdravotní 0\u{00A0}Kč. Část každé další koruny ještě pokryje paušál.")
    }

    /// At 6 000 000 Kč the tax is in the band of 23 %, the social insurance is at its maximum base and takes nothing
    /// more, and the health insurance takes 6,75 %: 230 + 0 + 67,5 is 297,5, so 298 for the thousand, the half
    /// crown going to the part with the largest remainder.
    @Test func theMarginalLevyOfAHighIncomeHasNoSocialInsurancePartAndItsPartsAddUp() throws {
        let marginal = try build(choose(income: 6_000_000)).summary.marginal

        #expect(marginal.total == "29,8\u{00A0}%")
        #expect(
            marginal.text
                == "Z každé další tisícovky příjmu odvedete 298\u{00A0}Kč: daň 230\u{00A0}Kč,"
                + " sociální 0\u{00A0}Kč a zdravotní 68\u{00A0}Kč."
                + " Paušál je na stropu, takže každá další koruna je celá zisk.")
        #expect(isClose(marginal.shares[1].fraction, 0))
    }

    /// Without income the next crowns pay nothing more: the minimum insurance covers them. The flat rate is nowhere
    /// near its cap.
    @Test func withoutIncomeTheMarginalLevyIsNothing() throws {
        let marginal = try build(choose(income: 0)).summary.marginal

        #expect(marginal.total == "0,0\u{00A0}%")
        #expect(
            marginal.text
                == "Z každé další tisícovky příjmu odvedete 0\u{00A0}Kč: daň 0\u{00A0}Kč,"
                + " sociální 0\u{00A0}Kč a zdravotní 0\u{00A0}Kč. Část každé další koruny ještě pokryje paušál.")
        #expect(marginal.shares.map(\.fraction) == [0, 0, 0])
    }

    /// The flat-rate expenses are on their cap from the income where the percentage of it reaches the cap, also exactly
    /// there (the note under the inputs says so too), though `expensesCapped` is true only over it: a crown of income
    /// more adds nothing to the expenses, so the next crown is all profit. A crown less, it is not.
    @Test func theMarginalLevySaysTheNextCrownIsAllProfitFromTheIncomeWhereTheFlatRateReachesItsCap() throws {
        let capped = "Paušál je na stropu, takže každá další koruna je celá zisk."
        let covered = "Část každé další koruny ještě pokryje paušál."
        for percent in [80, 60, 40, 30] {
            // 2 000 000 Kč is where the expenses reach their cap at every percentage.
            let exactly = choose(income: 2_000_000, percent: percent)
            let result = try compute(exactly)
            #expect(result.uncappedExpenses == result.expenseCap, "\(percent) %")
            #expect(!result.expensesCapped, "\(percent) %")
            #expect(try build(exactly).summary.marginal.text.hasSuffix(capped), "\(percent) %")
            #expect(try build(choose(income: 2_000_001, percent: percent)).summary.marginal.text.hasSuffix(capped))
            #expect(try build(choose(income: 1_999_999, percent: percent)).summary.marginal.text.hasSuffix(covered))
        }
    }

    /// The sum and the three parts the sentence of the marginal levy names, in whole Kč, in the order of the sentence.
    private func figures(ofTheMarginalLevy text: String) -> [Int64] {
        var runs: [String] = []
        var run = ""
        for character in text {
            if character.isNumber || character == "\u{00A0}" {
                run.append(character)
            } else {
                runs.append(run)
                run = ""
            }
        }
        runs.append(run)
        return runs.map { $0.filter(\.isNumber) }.filter { !$0.isEmpty }.compactMap { Int64($0) }
    }

    // MARK: The texts of the inputs

    @Test func theRulesLineNamesTheYearsThresholdMinimumAndCheck() {
        #expect(
            SimulatorBuilder.rulesLine(year: 2026)
                == "Pravidla 2026 · 23\u{00A0}% nad 1\u{00A0}762\u{00A0}812\u{00A0}Kč"
                + " · minimální základ 17\u{00A0}139\u{00A0}Kč měsíčně · ověřeno 20.\u{00A0}10.\u{00A0}2026")
    }

    @Test func theRulesLineOfEachYearHasThatYearsThresholdAndMinimum() {
        // The band starts at 48 times the average wage until 2023 and at 36 times from 2024.
        let expected = [
            (2022, "1\u{00A0}867\u{00A0}728", "9\u{00A0}728"),
            (2023, "1\u{00A0}935\u{00A0}552", "10\u{00A0}081"),
            (2024, "1\u{00A0}582\u{00A0}812", "13\u{00A0}191"),
            (2025, "1\u{00A0}676\u{00A0}052", "16\u{00A0}295"),
        ]
        for (year, threshold, minimum) in expected {
            #expect(
                SimulatorBuilder.rulesLine(year: year)
                    == "Pravidla \(year) · 23\u{00A0}% nad \(threshold)\u{00A0}Kč"
                    + " · minimální základ \(minimum)\u{00A0}Kč měsíčně · ověřeno 20.\u{00A0}10.\u{00A0}2026")
        }
    }

    @Test func theExpenseNoteSaysTheFlatRateAndItsCap() throws {
        let page = try build(choose(income: 1_000_000), rateFromSettings: false)

        #expect(page.expenseNote == "Paušál 600\u{00A0}000\u{00A0}Kč, strop 1\u{00A0}200\u{00A0}000\u{00A0}Kč.")
        // The sentence about the settings is added to either form while the percentage comes from them.
        let prefilled = try build(choose(income: 1_000_000), rateFromSettings: true)
        #expect(
            prefilled.expenseNote
                == "Paušál 600\u{00A0}000\u{00A0}Kč, strop 1\u{00A0}200\u{00A0}000\u{00A0}Kč."
                + " Předvyplněno podle Nastavení roku 2026.")
    }

    @Test func theExpenseNoteOfAFlatRateAtItsCapNamesTheCapOfThePercentage() throws {
        let page = try build(choose(year: 2024, income: 3_000_000, percent: 80), rateFromSettings: true)

        #expect(
            page.expenseNote
                == "Paušál je na stropu 1\u{00A0}600\u{00A0}000\u{00A0}Kč. Předvyplněno podle Nastavení roku 2024.")
        #expect(
            try build(choose(income: 3_000_000, percent: 30)).expenseNote
                == "Paušál je na stropu 600\u{00A0}000\u{00A0}Kč. " + Self.rentNote)
    }

    /// The sentence that the rate of 30 % adds to the note of the expenses.
    private static let rentNote = "Běžný pronájem podle § 9 aplikace nepočítá – není to příjem z podnikání."

    @Test func theExpenseNoteOf30PercentEndsWithTheSentenceThatOrdinaryRentIsNotCounted() throws {
        let page = try build(choose(income: 1_000_000, percent: 30), rateFromSettings: false)

        #expect(page.expenseNote == "Paušál 300\u{00A0}000\u{00A0}Kč, strop 600\u{00A0}000\u{00A0}Kč. " + Self.rentNote)
        // The sentence comes last, after the one about the settings of the year.
        let prefilled = try build(choose(income: 1_000_000, percent: 30), rateFromSettings: true)
        #expect(
            prefilled.expenseNote
                == "Paušál 300\u{00A0}000\u{00A0}Kč, strop 600\u{00A0}000\u{00A0}Kč."
                + " Předvyplněno podle Nastavení roku 2026. " + Self.rentNote)
    }

    @Test func theExpenseNoteOfAnyOtherPercentageSaysNothingOfRent() throws {
        for percent in [80, 60, 40] {
            for rateFromSettings in [false, true] {
                let note = try build(choose(percent: percent), rateFromSettings: rateFromSettings).expenseNote
                #expect(!note.contains("§ 9"), "\(percent) %, from the settings: \(rateFromSettings)")
            }
        }
    }

    @Test func aFlatRateExactlyAtItsCapReadsAsAtTheCap() throws {
        // 60 % of 2 000 000 Kč is exactly the cap of 1 200 000 Kč, and the expenses are at their cap, not below it.
        let page = try build(choose(income: 2_000_000), rateFromSettings: false)
        #expect(page.expenseNote == "Paušál je na stropu 1\u{00A0}200\u{00A0}000\u{00A0}Kč.")

        // 2 000 000 Kč is where the expenses reach their cap at every percentage, and from there on they stay at it.
        let caps = [
            (80, "1\u{00A0}600\u{00A0}000"), (60, "1\u{00A0}200\u{00A0}000"), (40, "800\u{00A0}000"),
            (30, "600\u{00A0}000"),
        ]
        for (percent, cap) in caps {
            // Only the rate of 30 % adds the sentence about rent.
            let rent = percent == 30 ? " " + Self.rentNote : ""
            for income: Int64 in [2_000_000, 2_000_001] {
                let note = try build(choose(income: income, percent: percent)).expenseNote
                #expect(note == "Paušál je na stropu \(cap)\u{00A0}Kč." + rent, "\(percent) % of \(income)")
            }
        }
        // A crown less of income, the expenses are a crown short of their cap.
        let below = try build(choose(income: 1_999_999)).expenseNote
        #expect(below == "Paušál 1\u{00A0}199\u{00A0}999\u{00A0}Kč, strop 1\u{00A0}200\u{00A0}000\u{00A0}Kč.")
    }

    // MARK: The hints

    @Test func dipAndLongTermCareCountForNothingBefore2024() throws {
        let with = try build(
            choose(year: 2023, income: 1_000_000, deductions: Deductions(dip: 20_000, longTermCare: 10_000)))
        let without = try build(choose(year: 2023, income: 1_000_000))

        #expect(with.summary.levyBar.parts[0].legendValue == without.summary.levyBar.parts[0].legendValue)
        #expect(with.summary == without.summary)
        #expect(with.sections == without.sections)
        #expect(with.hints.retirementLimits.count == 2)
    }

    @Test func noMonthsOfInterestAllowNoInterest() throws {
        let page = try build(choose(deductions: Deductions(mortgageInterestPaid: 100_000, mortgageMonths: 0)))

        #expect(page.hints.mortgageAllowed == "0\u{00A0}Kč")
        #expect(page.hints.mortgageOverLimit == "100\u{00A0}000\u{00A0}Kč")
    }

    @Test func theHintsUnderTheFieldsAreThoseOfTheAdvancesAndDeductionsScreen() throws {
        let claims = Deductions(
            mortgageInterestPaid: 200_000, lifeInsurance: 10_000, pensionSavings: 20_000, dip: 15_000, gifts: 20_000)
        let choices = choose(deductions: claims)
        let result = try compute(choices)
        let page = SimulatorBuilder.page(result, choices: choices, rateFromSettings: false)

        #expect(page.hints == DeductionHints.make(from: result.deductionLines, deductions: claims))
        #expect(page.hints.mortgageAllowed == "150\u{00A0}000\u{00A0}Kč")
        #expect(page.hints.mortgageOverLimit == "50\u{00A0}000\u{00A0}Kč")
        #expect(page.hints.mortgageLimit == "limit 150\u{00A0}000\u{00A0}Kč za 12 měsíců")
        #expect(page.hints.retirementLimits.map(\.usedText) == ["45\u{00A0}000 z 48\u{00A0}000\u{00A0}Kč"])
        #expect(page.hints.retirementAllowed == "45\u{00A0}000\u{00A0}Kč")
        #expect(page.hints.giftsAllowed == "20\u{00A0}000\u{00A0}Kč")
    }

    // MARK: Every choice of the screen

    @Test func everyChoiceOfTheScreenGivesUniqueRowsTheFiguresOfTheResultAndABarThatAddsUp() throws {
        let incomes: [Int64] = [0, 1, 99_720, 150_000, 500_000, 2_500_000, 6_000_000, 50_000_000]
        let claims = [
            Deductions(),
            Deductions(
                mortgageInterestPaid: 200_000, lifeInsurance: 10_000, pensionSavings: 20_000, dip: 5_000,
                longTermCare: 3_000, gifts: 30_000),
        ]
        // A secondary activity with the switch of the health minimum off and on; a main activity ignores the switch.
        let activities: [(activity: SimulatorActivity, exempt: Bool)] = [
            (.main, false), (.secondary, false), (.secondary, true),
        ]
        for year in TaxRules.supportedYears {
            for income in incomes {
                for (activity, exempt) in activities {
                    for months in [1, 5, 12] {
                        for percent in [30, 60, 80] {
                            for deductions in claims {
                                for credit in [true, false] {
                                    for family in [nil, Self.sampleFamily] {
                                        let choices = choose(
                                            year: year, income: income, percent: percent, activity: activity,
                                            healthMinimumExempt: exempt, months: months, deductions: deductions,
                                            credit: credit, family: family)
                                        try check(choices)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The share a text such as "18,4 %", "−25,0 %" or "385 300,0 %" gives, in tenths of a percent.
    private func tenths(ofShare text: String) -> Int64? {
        let number = text.replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: number).map { NSDecimalNumber(decimal: $0 * 10).int64Value }
    }

    /// The invariants of the page for `choices`: the sections and the bar agree with each other and with the result.
    /// The key figure counts a tax bonus, and the bar weighs each part by its levy, so a bonus is negative and no part
    /// of it. The shares of the popovers add up to the share of the key figure, the months are a twelfth of the years,
    /// and the parts of the sentence of the marginal levy add up to its sum. The net income is the income less what the
    /// year costs, and its average is over the twelve months.
    private func check(_ choices: SimulatorInput) throws {
        let context = "\(choices)"
        let result = try compute(choices)
        let page = SimulatorBuilder.page(result, choices: choices, rateFromSettings: false)
        let summary = page.summary
        let total = result.netTax + result.social.insurance + result.health.insurance
        let parts = summary.levyBar.parts

        #expect(summary.keyFigure.eyebrow == "Odvody za rok \(choices.year)", "\(context)")
        #expect(summary.keyFigure.figure == CzechFormat.wholeKc(total), "\(context)")
        #expect(summary.levyBar.header == "Odvody podle úřadů", "\(context)")
        #expect(summary.levyBar.total == nil && summary.levyBar.totalShare == nil, "\(context)")
        #expect(page.sections.map(\.title) == titles, "\(context)")
        #expect(parts.map(\.authority) == Authority.allCases, "\(context)")
        for (section, part) in zip(page.sections, parts) {
            #expect(Set(section.rows.map(\.label)).count == section.rows.count, "\(context) \(section.title)")
            #expect(section.rows.last?.style == .total, "\(context) \(section.title)")
            if part.authority == .tax && result.netTax < 0 {
                #expect(section.rows.last?.value == CzechFormat.wholeKc(result.netTax), "\(context)")
                #expect(part.legendValue == "bonus " + CzechFormat.wholeKc(-result.netTax), "\(context)")
            } else {
                #expect(section.rows.last?.value == part.legendValue, "\(context) \(section.title)")
            }
            // The popover: the levy of the year as the legend has it, a twelfth of it, and the share of the income.
            let levy = result.balance(part.authority).liability
            #expect(part.weight == levy, "\(context) \(part.authority)")
            #expect(part.rows.map(\.label) == ["Za rok", "Měsíčně", "Z příjmu"], "\(context) \(part.authority)")
            #expect(part.rows.map(\.style) == [.strong, .muted, .muted], "\(context) \(part.authority)")
            #expect(part.rows[0].value == part.legendValue, "\(context) \(part.authority)")
            let month = CzechFormat.wholeKc(DecimalMath.halfUp(Decimal(levy) / 12))
            #expect(part.rows[1].value == month, "\(context) \(part.authority)")
            #expect(part.shareLine == nil, "\(context) \(part.authority)")
            #expect(part.accessibilityLabel.hasPrefix(part.authority.title + ": za rok "), "\(context)")
        }
        #expect(parts[0].legendValue.hasPrefix("bonus") == (result.childBonus > 0), "\(context)")
        #expect(page.family.children.rows.count == choices.family.children.count, "\(context)")
        // The shares of the three popovers add up to the share of the key figure; with no income there is none.
        if choices.incomeKc > 0 {
            let shares = parts.compactMap { tenths(ofShare: $0.rows[2].value) }
            #expect(shares.count == 3, "\(context)")
            #expect(shares.reduce(0, +) == summary.keyFigure.share.flatMap(tenths(ofShare:)), "\(context) \(shares)")
            let month = CzechFormat.wholeKc(DecimalMath.halfUp(Decimal(total) / 12))
            #expect(summary.keyFigure.sentence == month + " měsíčně", "\(context)")
        } else {
            #expect(parts.allSatisfy { $0.rows[2].value == "—" }, "\(context)")
            #expect(summary.keyFigure.share == nil, "\(context)")
            #expect(summary.keyFigure.sentence == "zadejte příjem", "\(context)")
        }
        // The net income is the income less the levies, a bonus included, and its average is over the twelve months.
        let net = summary.netIncome
        let monthly = DecimalMath.halfUp(Decimal(choices.incomeKc - total) / 12)
        #expect(net.label == "Čistý příjem průměrně za měsíc", "\(context)")
        #expect(net.amount == CzechFormat.wholeKc(monthly), "\(context)")
        let year = CzechFormat.wholeKc(choices.incomeKc - total)
        #expect(net.sub == "za rok \(year) · \(Self.notSubtracted)", "\(context)")
        // The card of the net income agrees with it, and has a label of its own for each row.
        let card = page.sections[3]
        let yearRow = card.rows.first { $0.label == "Čistý příjem za rok" }
        #expect(Set(card.rows.map(\.label)).count == card.rows.count, "\(context) \(card.title)")
        #expect(card.rows.last?.style == .total, "\(context) \(card.title)")
        #expect(card.rows.last?.value == net.amount, "\(context) \(card.title)")
        #expect(yearRow?.value == CzechFormat.grouped(choices.incomeKc - total), "\(context) \(card.title)")
        #expect((page.incomePerMonth == nil) == (choices.incomeKc == 0), "\(context)")
        // The marginal levy: the total and the bar are those of Výpočet, and the parts of the sentence add up.
        let marginal = summary.marginal
        let vypocet = ComputationBuilder.marginal(of: result)
        #expect(marginal.total == vypocet.total && marginal.shares == vypocet.shares, "\(context)")
        let named = figures(ofTheMarginalLevy: marginal.text)
        #expect(named.count == 4, "\(context) \(marginal.text)")
        if named.count == 4 {
            #expect(named[0] == named[1] + named[2] + named[3], "\(context) \(named)")
            #expect(named[0] == DecimalMath.halfUp(result.marginalTotal * 1_000), "\(context) \(named)")
            for (figure, authority) in zip(named.dropFirst(), Authority.allCases) {
                let exact = (result.marginal[authority] ?? 0) * 1_000
                #expect((Decimal(figure) - exact).magnitude < 1, "\(context) \(authority) \(figure) of \(exact)")
            }
        }
        let capped = result.uncappedExpenses >= result.expenseCap
        #expect(
            marginal.text.hasSuffix(
                capped
                    ? "Paušál je na stropu, takže každá další koruna je celá zisk."
                    : "Část každé další koruny ještě pokryje paušál."), "\(context)")
    }
}

/// The levies of `choices` as the model asks the engine for them: the whole year, as of its last day.
private func compute(_ choices: SimulatorInput) throws -> TaxResult {
    try AppModel.compute(SimulatorBuilder.input(choices), asOf: civilDate("\(choices.year)-12-31"))
}

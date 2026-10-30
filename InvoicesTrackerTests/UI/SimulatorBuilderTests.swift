import Foundation
import Testing
@testable import InvoicesTracker

/// What the Simulátor shows for a simulation, as the builder makes it from the choices and from the result the tax
/// engine works out for them: the input of the engine, the result card, the four cards of the breakdown, the marginal
/// levy, the hints under the deduction fields and the cards of the family. The worked example is 2026 with an income of
/// 2 500 000 Kč, expenses at 60 %, a main activity for the whole year, no deductions, the taxpayer credit and no
/// family. Its levies, and those of the other cases below, were worked out for the same data by a separate
/// implementation of the rules (exact fractions, run in Python); those with the family by hand. In every expected
/// string `\u{00A0}` is the no-break space and `\u{2212}` the minus.
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
    private func netIncome(_ amount: String, year: String, isNegative: Bool = false) -> SimulatorNetIncome {
        SimulatorNetIncome(
            label: "Čistý příjem průměrně za měsíc", amount: amount, sub: "za rok \(year) · \(Self.notSubtracted)",
            isNegative: isNegative)
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

        #expect(summary.heading == "Zaplatíte za rok 2026")
        #expect(summary.total == "460\u{00A0}690\u{00A0}Kč")
        #expect(summary.subline == "≈ 38\u{00A0}391\u{00A0}Kč měsíčně · 18,4\u{00A0}% z příjmu")
        #expect(summary.lines.map(\.authority) == [.tax, .social, .health])
        #expect(summary.lines.map(\.id) == [.tax, .social, .health])
        #expect(summary.lines.map(\.label) == ["Daň z příjmů", "Sociální pojištění", "Zdravotní pojištění"])
        #expect(
            summary.lines.map(\.amount) == [
                "164\u{00A0}160\u{00A0}Kč", "208\u{00A0}780\u{00A0}Kč", "87\u{00A0}750\u{00A0}Kč",
            ])
        #expect(summary.lines.map(\.note) == [String?](repeating: nil, count: 3))
        // The income less the levies is 2 039 310 Kč, which over the twelve months is 169 942,50 Kč, rounded away from
        // zero.
        #expect(
            summary.netIncome
                == SimulatorNetIncome(
                    label: "Čistý příjem průměrně za měsíc", amount: "169\u{00A0}943\u{00A0}Kč",
                    sub: "za rok 2\u{00A0}039\u{00A0}310\u{00A0}Kč · skutečné výdaje podnikání tu odečtené nejsou",
                    isNegative: false))
        #expect(page.marginal.total == "37,8\u{00A0}%")
        #expect(
            page.expenseNote
                == "Paušál je na stropu 1\u{00A0}200\u{00A0}000\u{00A0}Kč. Předvyplněno podle Nastavení roku 2026.")
        #expect(page.incomePerMonth == "≈ 208\u{00A0}333\u{00A0}Kč měsíčně")
    }

    /// The minimum insurance of the whole year, 99 720 Kč, is all the levies, so the year leaves −99 720 Kč, which over
    /// the twelve months is −8 310 Kč. Both are shown with the minus sign, and the net income is marked negative, for
    /// the view to warn.
    @Test func withoutIncomeTheMinimumInsuranceIsShownAndTheLeviesAreOverTheIncome() throws {
        let page = try build(choose(income: 0))
        let summary = page.summary

        #expect(summary.total == "99\u{00A0}720\u{00A0}Kč")
        #expect(summary.subline == "Zadejte příjem")
        #expect(summary.lines.map(\.amount) == ["0\u{00A0}Kč", "60\u{00A0}056\u{00A0}Kč", "39\u{00A0}664\u{00A0}Kč"])
        #expect(summary.lines.map(\.note) == [nil, "platíte minimum", "platíte minimum"])
        #expect(
            summary.netIncome
                == SimulatorNetIncome(
                    label: "Čistý příjem průměrně za měsíc", amount: "\u{2212}8\u{00A0}310\u{00A0}Kč",
                    sub: "za rok \u{2212}99\u{00A0}720\u{00A0}Kč · skutečné výdaje podnikání tu odečtené nejsou",
                    isNegative: true))
        #expect(page.incomePerMonth == nil)
    }

    @Test func whenTheLeviesEqualTheIncomeNothingIsLeftAndNothingIsOver() throws {
        // An income of 99 720 Kč pays no tax and the minimum insurance, which is 99 720 Kč.
        let summary = try build(choose(income: 99_720)).summary

        #expect(summary.total == "99\u{00A0}720\u{00A0}Kč")
        #expect(summary.netIncome == netIncome("0\u{00A0}Kč", year: "0\u{00A0}Kč"))
        #expect(summary.subline == "≈ 8\u{00A0}310\u{00A0}Kč měsíčně · 100,0\u{00A0}% z příjmu")
    }

    /// An income of 99 715 Kč pays no tax and the minimum insurance of 99 720 Kč, so the year leaves −5 Kč. That is
    /// below zero, and the net income is negative, though its average per month, −0,42 Kč, rounds to 0 Kč.
    @Test func aYearBelowZeroByAFewCrownsIsNegativeThoughItsAverageRoundsToZero() throws {
        let summary = try build(choose(income: 99_715)).summary

        #expect(summary.total == "99\u{00A0}720\u{00A0}Kč")
        #expect(summary.netIncome == netIncome("0\u{00A0}Kč", year: "\u{2212}5\u{00A0}Kč", isNegative: true))
    }

    @Test func aSecondaryActivityBelowTheDecisiveAmountPaysNoSocialInsurance() throws {
        // The health insurance is that of the profit alone, as the activity is exempt from the health minimum.
        let page = try build(choose(income: 100_000, activity: .secondary, healthMinimumExempt: true))
        let lines = page.summary.lines

        #expect(lines[1].amount == "0\u{00A0}Kč")
        #expect(lines[1].note == "vedlejší činnost pod rozhodnou částkou – neplatí se")
        #expect(lines[2].amount == "2\u{00A0}700\u{00A0}Kč")
        #expect(lines[2].note == nil)
        #expect(page.summary.total == "2\u{00A0}700\u{00A0}Kč")
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

        #expect(page.summary.lines[1].note == "dosažen maximální vyměřovací základ")
        #expect(page.summary.lines[0].note == nil)
        #expect(page.summary.lines[2].note == nil)
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
            #expect(try build(choices).summary.lines[1].note == reached, "\(income)")
        }
        // A crown less of income is a base a crown short of the maximum, without the note. A crown more than those two
        // is a base over the maximum, with it.
        let short = choose(income: 5_473_481)
        #expect(try compute(short).social.computedBase == 2_350_415)
        #expect(try build(short).summary.lines[1].note == nil)
        let over = choose(income: 5_473_484)
        #expect(try compute(over).social.computedBase == 2_350_417)
        #expect(try build(over).summary.lines[1].note == reached)
    }

    @Test func theBarIsSplitByTheShareEachLevyHasInTheTotal() throws {
        let shares = try build(choose()).summary.shares

        #expect(shares.map(\.authority) == [.tax, .social, .health])
        #expect(shares.map(\.id) == [.tax, .social, .health])
        #expect(isClose(shares[0].fraction, 0.3563350626234561))
        #expect(isClose(shares[1].fraction, 0.45318978054657144))
        #expect(isClose(shares[2].fraction, 0.19047515682997243))
        // With no tax, the bar is the two insurances.
        let minimum = try build(choose(income: 0)).summary.shares
        #expect(minimum[0].fraction == 0)
        #expect(isClose(minimum[1].fraction, 0.6022462896109105))
        #expect(isClose(minimum[2].fraction, 0.39775371038908947))
    }

    /// 150 000 Kč with the sample family: the taxpayer credit takes the tax of 9 000 Kč, so the children's 37 524 Kč
    /// are all a bonus, as the income has reached six minimum wages (134 400 Kč). The tax reads as the bonus, what the
    /// year costs is the minimum insurance less the bonus, and the bar is of the insurance alone: a bonus is no part of
    /// it.
    @Test func aNegativeTaxReadsAsBonusAndTheLevyBarLeavesItOut() throws {
        let page = try build(choose(income: 150_000, family: Self.sampleFamily))
        let summary = page.summary

        #expect(summary.lines.map(\.label) == ["Daň z příjmů", "Sociální pojištění", "Zdravotní pojištění"])
        #expect(
            summary.lines.map(\.amount) == [
                "bonus 37\u{00A0}524\u{00A0}Kč", "60\u{00A0}056\u{00A0}Kč", "39\u{00A0}664\u{00A0}Kč",
            ])
        #expect(summary.lines.map(\.note) == [nil, "platíte minimum", "platíte minimum"])
        // 60 056 + 39 664 − 37 524 Kč.
        #expect(summary.total == "62\u{00A0}196\u{00A0}Kč")
        #expect(summary.subline == "≈ 5\u{00A0}183\u{00A0}Kč měsíčně · 41,5\u{00A0}% z příjmu")
        // The income less the levies, 150 000 − 62 196 Kč, is 87 804 Kč, which is 7 317 Kč a month.
        #expect(summary.netIncome == netIncome("7\u{00A0}317\u{00A0}Kč", year: "87\u{00A0}804\u{00A0}Kč"))
        // The bar is that of the minimum insurance alone, as without income.
        #expect(summary.shares.map(\.authority) == [.tax, .social, .health])
        #expect(summary.shares[0].fraction == 0)
        #expect(isClose(summary.shares[1].fraction, 0.6022462896109105))
        #expect(isClose(summary.shares[2].fraction, 0.39775371038908947))
        #expect(summary.shares == (try build(choose(income: 0)).summary.shares))

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
        #expect(page.summary.lines[0].amount == "101\u{00A0}796\u{00A0}Kč")
        #expect(page.summary.total == "398\u{00A0}326\u{00A0}Kč")

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

        #expect(summary.total == "0\u{00A0}Kč")
        #expect(summary.subline == "Zadejte příjem")
        #expect(summary.shares.map(\.fraction) == [0, 0, 0])
        #expect(summary.netIncome == netIncome("0\u{00A0}Kč", year: "0\u{00A0}Kč"))
        // Nothing is paid on such a secondary activity without income: no minimum, and the social insurance says why.
        #expect(summary.lines.map(\.amount) == ["0\u{00A0}Kč", "0\u{00A0}Kč", "0\u{00A0}Kč"])
        #expect(summary.lines.map(\.note) == [nil, "vedlejší činnost pod rozhodnou částkou – neplatí se", nil])
    }

    @Test func theMonthlyFiguresAreRoundedHalfUp() throws {
        // 6 Kč a year is exactly half a crown a month, which is 1 Kč; 30 Kč is 2,50 Kč, which is 3 Kč; 5 Kč is 0,42 Kč.
        #expect(try build(choose(income: 6)).incomePerMonth == "≈ 1\u{00A0}Kč měsíčně")
        #expect(try build(choose(income: 30)).incomePerMonth == "≈ 3\u{00A0}Kč měsíčně")
        #expect(try build(choose(income: 5)).incomePerMonth == "≈ 0\u{00A0}Kč měsíčně")
        // Seven months of main activity on 100 000 Kč pay the minimum insurances and no tax: 58 170 Kč, which is
        // 4 847,50 Kč a month.
        let subline = try build(choose(income: 100_000, months: 7)).summary.subline
        #expect(subline == "≈ 4\u{00A0}848\u{00A0}Kč měsíčně · 58,2\u{00A0}% z příjmu")
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
            page.summary.lines.map(\.amount) == [
                "29\u{00A0}160\u{00A0}Kč", "64\u{00A0}240\u{00A0}Kč", "27\u{00A0}000\u{00A0}Kč",
            ])
        #expect(page.summary.lines.map(\.note) == [String?](repeating: nil, count: 3))
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

        let health = page.summary.lines[2]
        #expect(health.amount == "3\u{00A0}143\u{00A0}Kč")
        #expect(health.note == "platíte minimum")
        let minimum = try row("Minimální vyměřovací základ", in: page.sections[2])
        #expect(minimum.value == "23\u{00A0}278,50")
        #expect(minimum.note == "23\u{00A0}278,50 × 1\u{00A0}měsíc")
    }

    @Test func vedlejsiActivityWithTheSwitchIsExemptFromTheHealthMinimum() throws {
        let page = try build(
            choose(
                year: 2025, income: 5_000, percent: 60, activity: .secondary, healthMinimumExempt: true, months: 1))

        let health = page.summary.lines[2]
        #expect(health.amount == "135\u{00A0}Kč")
        #expect(health.note == nil)
        let minimum = try row("Minimální vyměřovací základ", in: page.sections[2])
        #expect(minimum.value == "0,00")
        #expect(minimum.note == Self.exemptNote)
    }

    /// The switch is for a secondary activity: with a main one it changes nothing on the page, whatever it says.
    @Test func hlavniActivityAlwaysPaysTheMinimum() throws {
        let page = try build(
            choose(year: 2025, income: 5_000, percent: 60, activity: .main, healthMinimumExempt: true, months: 1))

        #expect(page.summary.lines[2].amount == "3\u{00A0}143\u{00A0}Kč")
        let minimum = try row("Minimální vyměřovací základ", in: page.sections[2])
        #expect(minimum.note == "23\u{00A0}278,50 × 1\u{00A0}měsíc")
        let withoutTheSwitch = try build(
            choose(year: 2025, income: 5_000, percent: 60, activity: .main, months: 1))
        #expect(page == withoutTheSwitch)
    }

    // MARK: The marginal levy

    @Test func theMarginalLevyIsTheOneOfVypocetForTheSameResult() throws {
        let choices = choose()
        let result = try compute(choices)
        let page = SimulatorBuilder.page(result, choices: choices, rateFromSettings: false)

        #expect(page.marginal == ComputationBuilder.marginal(of: result))
        #expect(page.marginal.total == "37,8\u{00A0}%")
        #expect(
            page.marginal.text
                == "Ze 100\u{00A0}Kč dalšího příjmu bez DPH odvedete 37,81\u{00A0}Kč:"
                + " daň 15,00 · sociální 16,06 · zdravotní 6,75.")
        #expect(page.marginal.shares.map(\.authority) == [.tax, .social, .health])
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

        #expect(with.summary.lines[0].amount == without.summary.lines[0].amount)
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

    /// The invariants of the page for `choices`: the sections and the lines agree with each other and with the result.
    /// What the year costs counts a tax bonus, and the bar does not: it is of what is paid. The net income is the
    /// income less what the year costs, and its average is over the twelve months.
    private func check(_ choices: SimulatorInput) throws {
        let context = "\(choices)"
        let result = try compute(choices)
        let page = SimulatorBuilder.page(result, choices: choices, rateFromSettings: false)
        let total = result.netTax + result.social.insurance + result.health.insurance
        let paid = result.tax + result.social.insurance + result.health.insurance

        #expect(page.summary.total == CzechFormat.wholeKc(total), "\(context)")
        #expect(page.summary.heading == "Zaplatíte za rok \(choices.year)", "\(context)")
        #expect(page.sections.map(\.title) == titles, "\(context)")
        #expect(page.summary.lines.map(\.authority) == Authority.allCases, "\(context)")
        for (section, line) in zip(page.sections, page.summary.lines) {
            #expect(Set(section.rows.map(\.label)).count == section.rows.count, "\(context) \(section.title)")
            #expect(section.rows.last?.style == .total, "\(context) \(section.title)")
            if line.authority == .tax && result.netTax < 0 {
                #expect(section.rows.last?.value == CzechFormat.wholeKc(result.netTax), "\(context)")
                #expect(line.amount == "bonus " + CzechFormat.wholeKc(-result.netTax), "\(context)")
            } else {
                #expect(section.rows.last?.value == line.amount, "\(context) \(section.title)")
            }
        }
        #expect(page.summary.lines[0].amount.hasPrefix("bonus") == (result.childBonus > 0), "\(context)")
        #expect(page.family.children.rows.count == choices.family.children.count, "\(context)")
        let fractions = page.summary.shares.map(\.fraction)
        #expect(page.summary.shares.map(\.authority) == Authority.allCases, "\(context)")
        #expect(isClose(fractions.reduce(0, +), paid > 0 ? 1 : 0), "\(context) \(fractions)")
        #expect(fractions.allSatisfy { $0 >= 0 }, "\(context) \(fractions)")
        // The net income is the income less the levies, a bonus included, and its average is over the twelve months.
        let net = page.summary.netIncome
        let monthly = DecimalMath.halfUp(Decimal(choices.incomeKc - total) / 12)
        #expect(net.label == "Čistý příjem průměrně za měsíc", "\(context)")
        #expect(net.amount == CzechFormat.wholeKc(monthly), "\(context)")
        let year = CzechFormat.wholeKc(choices.incomeKc - total)
        #expect(net.sub == "za rok \(year) · \(Self.notSubtracted)", "\(context)")
        #expect(net.isNegative == (choices.incomeKc < total), "\(context)")
        // The card of the net income agrees with it, and has a label of its own for each row.
        let card = page.sections[3]
        let yearRow = card.rows.first { $0.label == "Čistý příjem za rok" }
        #expect(Set(card.rows.map(\.label)).count == card.rows.count, "\(context) \(card.title)")
        #expect(card.rows.last?.style == .total, "\(context) \(card.title)")
        #expect(card.rows.last?.value == net.amount, "\(context) \(card.title)")
        #expect(yearRow?.value == CzechFormat.grouped(choices.incomeKc - total), "\(context) \(card.title)")
        #expect((page.incomePerMonth == nil) == (choices.incomeKc == 0), "\(context)")
        #expect((page.summary.subline == "Zadejte příjem") == (choices.incomeKc == 0), "\(context)")
    }
}

/// The levies of `choices` as the model asks the engine for them: the whole year, as of its last day.
private func compute(_ choices: SimulatorInput) throws -> TaxResult {
    try AppModel.compute(SimulatorBuilder.input(choices), asOf: civilDate("\(choices.year)-12-31"))
}

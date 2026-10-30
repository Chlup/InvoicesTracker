import Foundation
import Testing
@testable import InvoicesTracker

/// What the deductions do to the tax of a year, worked out for the panel of Zálohy a odpočty: the effect of each
/// deduction in turn (the lines add up to the saving of all of them), the totals with the credits of the family, and
/// the texts of the hints of the form. The expected figures were worked out by hand for the same inputs (15 % of a
/// deduction in the lower band, 23 % in the upper one, to whole crowns), not with the engine. In every expected string
/// `\u{00A0}` is the no-break space.
struct AdvanceImpactTests {
    // MARK: Inputs

    /// The input of a year with one payment of `crowns` Kč on its last day, 60 % flat-rate expenses and the credit.
    private static func input(
        year: Int = 2026, crowns: Int64, deductions: Deductions = Deductions(), credit: Bool = true
    ) -> YearInput {
        var settings = YearSettings(year: year)
        settings.deductions = deductions
        settings.taxpayerCredit = credit
        let receipt = Receipt(
            day: civilDate("\(year)-12-31"), czkNetHalere: crowns * 100, czkVatHalere: 0, source: .synthetic)
        return AppModel.yearInput(settings, receipts: [receipt], family: FamilyFacts())
    }

    private static func build(_ input: YearInput) throws -> AdvanceImpact {
        try AdvanceImpactBuilder.build(input, asOf: civilDate("\(input.year)-12-31"))
    }

    // MARK: Figures

    @Test func theRegressionYearAsOf17OctoberSavesTheTaxOfItsDeductionsOneAfterTheOther() throws {
        let impact = try AdvanceImpactBuilder.build(
            TaxEngineRegressionTests.sampleYear2026, asOf: civilDate("2026-10-17"))

        // The profit is 991 771 Kč; 150 000 Kč of interest take 22 500 Kč off the tax and 6 480 Kč of life
        // insurance 975 Kč more; without them the tax would be 117 915 Kč and with them it is 94 440 Kč.
        #expect(
            impact.lines == [
                ImpactLine(
                    kind: .mortgageInterest, title: "Úroky z úvěru na bydlení", claimedKc: 219_000,
                    appliedKc: 150_000, taxSavedKc: 22_500),
                ImpactLine(
                    kind: .retirementProducts, title: "Spoření a pojištění na stáří", claimedKc: 6_480,
                    appliedKc: 6_480, taxSavedKc: 975),
            ])
        #expect(
            impact.totals
                == ImpactTotals(deductionsKc: 156_480, taxWithoutKc: 117_915, taxWithKc: 94_440))
        #expect(impact.totals.savedKc == 23_475)
    }

    @Test func inTheUpperBandADeductionSavesTwentyThreePercent() throws {
        // 5 000 000 Kč of income: expenses stop at 1 200 000 Kč, the base is 3 800 000 Kč, far above the 1 762 812 Kč
        // where the 23 % rate starts.
        let impact = try Self.build(
            Self.input(crowns: 5_000_000, deductions: Deductions(mortgageInterestPaid: 150_000)))

        #expect(impact.lines.map(\.taxSavedKc) == [34_500])
        // 3 800 000 Kč: 264 421,80 + 23 % of 2 037 188 = 732 975,04 → 732 976, less the credit.
        #expect(impact.totals.taxWithoutKc == 702_136)
        #expect(impact.totals.taxWithKc == 667_636)
        #expect(impact.totals.deductionsKc == 150_000)
    }

    @Test func aTaxThatTheCreditPaysAnywayIsSavedNothing() throws {
        // 100 000 Kč of income, 40 000 Kč of profit: 6 000 Kč of tax before a credit of 30 840 Kč.
        let impact = try Self.build(Self.input(crowns: 100_000, deductions: Deductions(mortgageInterestPaid: 10_000)))

        #expect(impact.totals == ImpactTotals(deductionsKc: 10_000, taxWithoutKc: 0, taxWithKc: 0))
        #expect(impact.lines.map(\.taxSavedKc) == [0])
        #expect(impact.lines.map(\.appliedKc) == [10_000])
    }

    @Test func aDeductionThatRaisesTheBonusSavesWhatItAddsToIt() throws {
        // 700 000 Kč of income, 280 000 Kč of profit: 42 000 Kč of tax, 11 160 Kč after the taxpayer credit, which one
        // child's 15 204 Kč take, leaving a bonus of 4 044 Kč. 10 000 Kč of gifts take 1 500 Kč off the tax before the
        // credits, so the bonus is 5 544 Kč: the tax is zero either way, the net tax is 1 500 Kč lower.
        var input = Self.input(crowns: 700_000, deductions: Deductions(gifts: 10_000))
        input.family = FamilyFacts(children: [
            ChildFacts(
                label: "Anna", birthDate: civilDate("2019-09-03"), household: MonthRange.wholeYear, claimant: .me,
                order: 1, ztpp: nil, studies: nil)
        ])

        let impact = try Self.build(input)

        // The panel's tax without the deductions leaves out the child too: 11 160 Kč. So it saves 16 704 Kč, the
        // gifts' 1 500 Kč and the child's 15 204 Kč, of which 9 660 Kč are a credit and 5 544 Kč the bonus.
        #expect(
            impact.totals
                == ImpactTotals(
                    deductionsKc: 10_000, taxWithoutKc: 11_160, taxWithKc: -5_544, spouseCreditKc: nil,
                    childBenefitKc: 15_204, childBonusKc: 5_544))
        #expect(impact.totals.savedKc == 16_704)
        #expect(impact.lines.map(\.taxSavedKc) == [1_500])
    }

    /// Beside the deductions the panel lists the credits of the family that are used: the spouse credit and the child
    /// benefit. The tax without the deductions leaves them out too (the taxpayer credit stays), and the tax after
    /// everything has them all. The sample year as of 17. 10. 2026 with the sample family: 117 915 Kč of tax without
    /// them and 32 076 Kč with them, so 85 839 Kč are saved, 23 475 Kč by the deductions and 62 364 Kč by the family.
    @Test func theImpactListsTheFamilyCredits() throws {
        var input = TaxEngineRegressionTests.sampleYear2026
        input.family = TaxEngineFamilyTests.sampleFamily

        let impact = try AdvanceImpactBuilder.build(input, asOf: civilDate("2026-10-17"))

        #expect(ImpactTotals.savedTitle == "Ušetříte na dani")
        #expect(impact.totals.savedText == "85\u{00A0}839\u{00A0}Kč")
        #expect(
            impact.totals.rows == [
                ImpactTotalRow(title: "Odpočty celkem", value: "156\u{00A0}480\u{00A0}Kč"),
                ImpactTotalRow(title: "Sleva na manžela / manželku", value: "\u{2212}24\u{00A0}840\u{00A0}Kč"),
                ImpactTotalRow(title: "Zvýhodnění na děti", value: "\u{2212}37\u{00A0}524\u{00A0}Kč"),
                ImpactTotalRow(title: "Daň bez odpočtů a slev na rodinu", value: "117\u{00A0}915\u{00A0}Kč"),
                ImpactTotalRow(
                    title: "Daň po odpočtech a slevách", value: "32\u{00A0}076\u{00A0}Kč", isEmphasized: true),
            ])
        // Each deduction saves what it did without the family: the credits take only a part of the tax.
        #expect(impact.lines.map(\.taxSavedKc) == [22_500, 975])

        // Without a family there are no lines for it.
        let alone = try AdvanceImpactBuilder.build(
            TaxEngineRegressionTests.sampleYear2026, asOf: civilDate("2026-10-17"))
        #expect(
            alone.totals.rows.map(\.title)
                == ["Odpočty celkem", "Daň bez odpočtů a slev na rodinu", "Daň po odpočtech a slevách"])
        #expect(alone.totals.savedText == "23\u{00A0}475\u{00A0}Kč")
    }

    /// A bonus: the child benefit says how much of it is paid as a bonus, and the tax after everything is the bonus.
    /// 150 000 Kč of income bring 9 000 Kč of tax, which the taxpayer credit takes, so the spouse credit uses nothing
    /// and the children's 37 524 Kč are all paid as a bonus.
    @Test func aBonusIsSaidInTheChildBenefitAndInTheTaxAfterEverything() throws {
        var input = Self.input(crowns: 150_000)
        input.family = TaxEngineFamilyTests.sampleFamily

        let impact = try Self.build(input)

        #expect(
            impact.totals.rows == [
                ImpactTotalRow(title: "Odpočty celkem", value: "0\u{00A0}Kč"),
                ImpactTotalRow(title: "Sleva na manžela / manželku", value: "0\u{00A0}Kč"),
                ImpactTotalRow(
                    title: "Zvýhodnění na děti",
                    value: "\u{2212}37\u{00A0}524\u{00A0}Kč (z toho bonus 37\u{00A0}524\u{00A0}Kč)"),
                ImpactTotalRow(title: "Daň bez odpočtů a slev na rodinu", value: "0\u{00A0}Kč"),
                ImpactTotalRow(
                    title: "Daň po odpočtech a slevách", value: "bonus 37\u{00A0}524\u{00A0}Kč", isEmphasized: true),
            ])
        #expect(impact.totals.savedText == "37\u{00A0}524\u{00A0}Kč")
    }

    @Test func deductionsTogetherTakeOffAtMostTheProfit() throws {
        // 100 000 Kč of income, 40 000 Kč of profit, and 150 000 Kč of interest allowed: only the profit comes off.
        let impact = try Self.build(
            Self.input(crowns: 100_000, deductions: Deductions(mortgageInterestPaid: 150_000), credit: false))

        #expect(impact.totals.deductionsKc == 40_000)
        #expect(impact.totals.taxWithoutKc == 6_000)
        #expect(impact.totals.taxWithKc == 0)
        #expect(impact.lines.map(\.taxSavedKc) == [6_000])
        // The law allows 150 000 Kč, but only the profit comes off: the line says what comes off.
        #expect(impact.lines.map(\.claimedKc) == [150_000])
        #expect(impact.lines.map(\.appliedKc) == [40_000])
    }

    @Test func earlyInTheYearTheProfitHasRoomForTheFirstDeductionAndForNoneAfterIt() throws {
        // As of 28. 2. 2026 only the payment of 3. 2. (220 000 Kč) is income: 132 000 Kč of expenses and 88 000 Kč of
        // profit. The interest of 219 000 Kč allows 150 000 Kč, of which the profit takes 88 000 Kč, and nothing is
        // left for the life insurance, so the lines add up to the 88 000 Kč that come off.
        let impact = try AdvanceImpactBuilder.build(
            TaxEngineRegressionTests.sampleYear2026, asOf: civilDate("2026-02-28"))

        #expect(
            impact.lines == [
                ImpactLine(
                    kind: .mortgageInterest, title: "Úroky z úvěru na bydlení", claimedKc: 219_000,
                    appliedKc: 88_000, taxSavedKc: 0),
                ImpactLine(
                    kind: .retirementProducts, title: "Spoření a pojištění na stáří", claimedKc: 6_480,
                    appliedKc: 0, taxSavedKc: 0),
            ])
        #expect(impact.totals == ImpactTotals(deductionsKc: 88_000, taxWithoutKc: 0, taxWithKc: 0))
        #expect(impact.lines.map(\.appliedKc).reduce(0, +) == impact.totals.deductionsKc)
    }

    @Test func theLinesAddUpToTheDeductionsThatCameOffAndTheLastOnesTakeWhatIsLeft() throws {
        // 625 000 Kč of income, 250 000 Kč of profit. The interest takes 150 000 Kč and the retirement products
        // 48 000 Kč; the gifts of 100 000 Kč are allowed 75 000 Kč (30 % of the profit), of which only the 52 000 Kč
        // that are left of the profit come off.
        let impact = try Self.build(
            Self.input(
                crowns: 625_000,
                deductions: Deductions(mortgageInterestPaid: 150_000, pensionSavings: 48_000, gifts: 100_000)))

        #expect(
            impact.lines == [
                ImpactLine(
                    kind: .mortgageInterest, title: "Úroky z úvěru na bydlení", claimedKc: 150_000,
                    appliedKc: 150_000, taxSavedKc: 6_660),
                ImpactLine(
                    kind: .retirementProducts, title: "Spoření a pojištění na stáří", claimedKc: 48_000,
                    appliedKc: 48_000, taxSavedKc: 0),
                ImpactLine(kind: .gifts, title: "Dary", claimedKc: 100_000, appliedKc: 52_000, taxSavedKc: 0),
            ])
        // Without deductions the tax is 37 500 Kč less the credit of 30 840 Kč; the interest alone takes it to nothing.
        #expect(impact.totals == ImpactTotals(deductionsKc: 250_000, taxWithoutKc: 6_660, taxWithKc: 0))
        #expect(impact.lines.map(\.appliedKc).reduce(0, +) == impact.totals.deductionsKc)
    }

    @Test func in2022And2023PensionSavingsAndLifeInsuranceHaveLimitsOfTheirOwn() throws {
        let impact = try Self.build(
            Self.input(
                year: 2022, crowns: 1_000_000, deductions: Deductions(lifeInsurance: 10_000, pensionSavings: 30_000)))

        // 400 000 Kč of profit; the pension savings allow 24 000 Kč of 30 000 Kč, the insurance all of 10 000 Kč.
        #expect(
            impact.lines == [
                ImpactLine(
                    kind: .pensionSavings, title: "Penzijní spoření", claimedKc: 30_000, appliedKc: 24_000,
                    taxSavedKc: 3_600),
                ImpactLine(
                    kind: .lifeInsurance, title: "Soukromé životní pojištění", claimedKc: 10_000, appliedKc: 10_000,
                    taxSavedKc: 1_500),
            ])
        #expect(impact.totals == ImpactTotals(deductionsKc: 34_000, taxWithoutKc: 29_160, taxWithKc: 24_060))
        #expect(impact.hints.retirementLimits.map(\.title) == ["Penzijní spoření", "Soukromé životní pojištění"])
        #expect(
            impact.hints.retirementLimits.map(\.usedText)
                == ["30\u{00A0}000 z 24\u{00A0}000\u{00A0}Kč", "10\u{00A0}000 z 24\u{00A0}000\u{00A0}Kč"])
        // The bar is full when the claim is over the limit, and otherwise as full as the claim is of the limit.
        #expect(impact.hints.retirementLimits.map(\.usedPermille) == [1_000, 416])
        #expect(impact.hints.retirementAllowed == "34\u{00A0}000\u{00A0}Kč")
    }

    @Test func from2024TheRetirementProductsShareOneLimit() throws {
        let impact = try Self.build(
            Self.input(
                year: 2025, crowns: 1_000_000,
                deductions: Deductions(
                    lifeInsurance: 20_000, pensionSavings: 20_000, dip: 10_000, longTermCare: 5_000)))

        #expect(impact.lines.map(\.kind) == [.retirementProducts])
        #expect(impact.lines.first?.claimedKc == 55_000)
        // 55 000 Kč claimed against a limit of 48 000 Kč.
        #expect(impact.lines.first?.appliedKc == 48_000)
        #expect(impact.lines.first?.taxSavedKc == 7_200)
        #expect(impact.hints.retirementLimits.map(\.title) == ["Společný limit"])
        #expect(impact.hints.retirementLimits.map(\.usedText) == ["55\u{00A0}000 z 48\u{00A0}000\u{00A0}Kč"])
        #expect(impact.hints.retirementLimits.map(\.usedPermille) == [1_000])
        #expect(impact.hints.retirementAllowed == "48\u{00A0}000\u{00A0}Kč")
    }

    @Test func theLinesAddUpToTheSavingOfAllTheDeductionsWhateverTheyAre() throws {
        for crowns: Int64 in [50_000, 400_000, 2_191_771, 5_000_000, 9_000_000] {
            for mortgage: Int64 in [0, 80_000, 219_000] {
                for gifts: Int64 in [0, 500, 15_000, 400_000] {
                    let deductions = Deductions(
                        mortgageInterestPaid: mortgage, lifeInsurance: 6_480, pensionSavings: 12_000, gifts: gifts)
                    let impact = try Self.build(Self.input(crowns: crowns, deductions: deductions))
                    #expect(
                        impact.lines.map(\.taxSavedKc).reduce(0, +) == impact.totals.savedKc,
                        "\(crowns) Kč, interest \(mortgage), gifts \(gifts)")
                    // What each line says comes off is what comes off in all, however small the profit is.
                    #expect(
                        impact.lines.map(\.appliedKc).reduce(0, +) == impact.totals.deductionsKc,
                        "\(crowns) Kč, interest \(mortgage), gifts \(gifts)")
                    #expect(impact.lines.allSatisfy { $0.appliedKc >= 0 && $0.appliedKc <= $0.claimedKc })
                    #expect(impact.totals.savedKc >= 0)
                }
            }
        }
    }

    @Test func noDeductionIsNoLine() throws {
        let impact = try Self.build(Self.input(crowns: 1_000_000))

        #expect(impact.lines.isEmpty)
        #expect(impact.totals.deductionsKc == 0)
        #expect(impact.totals.savedKc == 0)
        #expect(impact.totals.taxWithKc == impact.totals.taxWithoutKc)
    }

    @Test(arguments: BrokenYearInput.allCases)
    func aYearTheComputationWouldRefuseGivesNoNumbers(_ broken: BrokenYearInput) throws {
        var input = Self.input(crowns: 1_000_000, deductions: Deductions(mortgageInterestPaid: 100_000))
        var asOf = civilDate("2026-12-31")
        broken.apply(to: &input, asOf: &asOf)

        #expect(throws: ComputationError.invalidYear(2026)) {
            try AdvanceImpactBuilder.build(input, asOf: asOf)
        }
    }

    // MARK: Hints

    @Test(arguments: [
        (1_000_000 as Int64, 120_000 as Int64, 12, "limit 150\u{00A0}000\u{00A0}Kč za 12 měsíců", nil as String?),
        (1_000_000, 200_000, 12, "limit 150\u{00A0}000\u{00A0}Kč za 12 měsíců", "50\u{00A0}000\u{00A0}Kč"),
        (1_000_000, 200_000, 1, "limit 12\u{00A0}500\u{00A0}Kč za 1 měsíc", "187\u{00A0}500\u{00A0}Kč"),
        (1_000_000, 200_000, 2, "limit 25\u{00A0}000\u{00A0}Kč za 2 měsíce", "175\u{00A0}000\u{00A0}Kč"),
        (1_000_000, 200_000, 4, "limit 50\u{00A0}000\u{00A0}Kč za 4 měsíce", "150\u{00A0}000\u{00A0}Kč"),
        (1_000_000, 200_000, 5, "limit 62\u{00A0}500\u{00A0}Kč za 5 měsíců", "137\u{00A0}500\u{00A0}Kč"),
        (1_000_000, 200_000, 0, "limit 0\u{00A0}Kč za 0 měsíců", "200\u{00A0}000\u{00A0}Kč"),
    ])
    func theLimitOfTheInterestIsSaidWithItsMonths(
        crowns: Int64, interest: Int64, months: Int, limit: String, over: String?
    ) throws {
        let impact = try Self.build(
            Self.input(crowns: crowns, deductions: Deductions(mortgageInterestPaid: interest, mortgageMonths: months)))

        #expect(impact.hints.mortgageLimit == limit)
        #expect(impact.hints.mortgageOverLimit == over)
    }

    @Test func theGiftsHintSaysWhyGiftsDoNotCount() throws {
        // A profit of 400 000 Kč: gifts count from 1 000 Kč, or when they are more than 2 % of the profit (8 000 Kč).
        let below = try Self.build(Self.input(crowns: 1_000_000, deductions: Deductions(gifts: 999)))
        #expect(below.hints.giftsNote == "pod minimem – neuplatní se")
        #expect(below.hints.giftsAllowed == "0\u{00A0}Kč")

        let enough = try Self.build(Self.input(crowns: 1_000_000, deductions: Deductions(gifts: 1_000)))
        #expect(enough.hints.giftsNote == "od 1 000 Kč (nebo nad 2 % základu), nejvýš 30 % základu")
        #expect(enough.hints.giftsAllowed == "1\u{00A0}000\u{00A0}Kč")

        let none = try Self.build(Self.input(crowns: 1_000_000))
        #expect(none.hints.giftsNote == "od 1 000 Kč (nebo nad 2 % základu), nejvýš 30 % základu")

        // At most 30 % of the profit: 120 000 Kč of 400 000 Kč.
        let capped = try Self.build(Self.input(crowns: 1_000_000, deductions: Deductions(gifts: 200_000)))
        #expect(capped.hints.giftsAllowed == "120\u{00A0}000\u{00A0}Kč")
    }

    // MARK: Which deductions are kept

    @Test func aSelectionOfDeductionsKeepsOnlyTheClaimsOfThoseAndTheRestOfTheSettings() {
        let all = Deductions(
            mortgageInterestPaid: 1, mortgageMonths: 7, mortgageCap: .before2021, lifeInsurance: 2, pensionSavings: 3,
            dip: 4, longTermCare: 5, gifts: 6)

        #expect(
            all.keeping([])
                == Deductions(mortgageMonths: 7, mortgageCap: .before2021))
        #expect(
            all.keeping([.mortgageInterest])
                == Deductions(mortgageInterestPaid: 1, mortgageMonths: 7, mortgageCap: .before2021))
        #expect(
            all.keeping([.retirementProducts])
                == Deductions(
                    mortgageMonths: 7, mortgageCap: .before2021, lifeInsurance: 2, pensionSavings: 3, dip: 4,
                    longTermCare: 5))
        #expect(
            all.keeping([.pensionSavings])
                == Deductions(mortgageMonths: 7, mortgageCap: .before2021, pensionSavings: 3))
        #expect(
            all.keeping([.lifeInsurance, .gifts])
                == Deductions(mortgageMonths: 7, mortgageCap: .before2021, lifeInsurance: 2, gifts: 6))
        #expect(
            all.keeping([.mortgageInterest, .retirementProducts, .gifts, .pensionSavings, .lifeInsurance]) == all)
    }

    // MARK: Texts of the panel and of the form

    @Test func thePanelExplainsInWhatOrderTheSavingsAreCounted() {
        #expect(ImpactPanel.orderNote == "Úspora u každého odpočtu se počítá po odpočtech uvedených nad ním.")
    }

    @Test(arguments: [
        (2021, "(příspěvky nad 1\u{00A0}000\u{00A0}Kč měsíčně)"),
        (2022, "(příspěvky nad 1\u{00A0}000\u{00A0}Kč měsíčně)"),
        (2023, "(příspěvky nad 1\u{00A0}000\u{00A0}Kč měsíčně)"),
        (
            2024,
            "(příspěvky nad 1\u{00A0}000\u{00A0}Kč měsíčně, od 1.\u{00A0}7.\u{00A0}2024 nad 1\u{00A0}700\u{00A0}Kč)"
        ),
        (2025, "(příspěvky nad 1\u{00A0}700\u{00A0}Kč měsíčně)"),
        (2026, "(příspěvky nad 1\u{00A0}700\u{00A0}Kč měsíčně)"),
        (2027, "(příspěvky nad 1\u{00A0}700\u{00A0}Kč měsíčně)"),
    ])
    func theAdviceOnPensionSavingsNamesTheContributionsThatCountInThatYear(year: Int, contributions: String) {
        #expect(
            DeductionHints.pensionAdvice(year: year)
                == "U penzijního spoření zadejte částku z potvrzení penzijní společnosti " + contributions)
    }

    // MARK: Words

    @Test(arguments: [
        (0, "0 měsíců"), (1, "1 měsíc"), (2, "2 měsíce"), (3, "3 měsíce"), (4, "4 měsíce"), (5, "5 měsíců"),
        (11, "11 měsíců"), (12, "12 měsíců"),
    ])
    func monthsAreCountedInCzech(count: Int, text: String) {
        #expect(DeductionHints.months(count) == text)
    }
}

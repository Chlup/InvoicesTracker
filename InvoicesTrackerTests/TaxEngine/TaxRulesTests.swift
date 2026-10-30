import Foundation
import Testing
@testable import InvoicesTracker

struct TaxRulesTests {
    /// One year's row of the verified rules table. The rows below are typed from the verified values, not taken from
    /// the implementation, so a slip in either one fails here.
    struct Row: Sendable, CustomTestStringConvertible {
        let year: Int
        let averageWage: Int64
        let taxBandThreshold: Int64
        let retirementLimit: RetirementLimit
        let hasDIPAndLongTermCare: Bool
        let socialAssessmentPercent: Decimal
        let socialMinimumMonthlyMain: Int64
        let socialMinimumMonthlySecondary: Int64
        let socialDecisiveAmount: Int64
        let socialMaximumAnnualBase: Int64
        let healthMinimumMonthlyBase: Decimal
        let childCareHealthExemption: Bool
        let minimumWage: Int64
        let spouseNeedsYoungChild: Bool

        var testDescription: String {
            String(year)
        }
    }

    static let rows: [Row] = [
        Row(
            year: 2022, averageWage: 38_911, taxBandThreshold: 1_867_728,
            retirementLimit: .separate(pensionSavings: 24_000, lifeInsurance: 24_000),
            hasDIPAndLongTermCare: false, socialAssessmentPercent: decimal("0.50"),
            socialMinimumMonthlyMain: 9_728, socialMinimumMonthlySecondary: 3_892,
            socialDecisiveAmount: 93_387, socialMaximumAnnualBase: 1_867_728,
            healthMinimumMonthlyBase: decimal("19455.50"), childCareHealthExemption: true,
            minimumWage: 16_200, spouseNeedsYoungChild: false
        ),
        Row(
            year: 2023, averageWage: 40_324, taxBandThreshold: 1_935_552,
            retirementLimit: .separate(pensionSavings: 24_000, lifeInsurance: 24_000),
            hasDIPAndLongTermCare: false, socialAssessmentPercent: decimal("0.50"),
            socialMinimumMonthlyMain: 10_081, socialMinimumMonthlySecondary: 4_033,
            socialDecisiveAmount: 96_777, socialMaximumAnnualBase: 1_935_552,
            healthMinimumMonthlyBase: decimal("20162.00"), childCareHealthExemption: true,
            minimumWage: 17_300, spouseNeedsYoungChild: false
        ),
        Row(
            year: 2024, averageWage: 43_967, taxBandThreshold: 1_582_812,
            retirementLimit: .combined(48_000),
            hasDIPAndLongTermCare: true, socialAssessmentPercent: decimal("0.55"),
            socialMinimumMonthlyMain: 13_191, socialMinimumMonthlySecondary: 4_837,
            socialDecisiveAmount: 105_520, socialMaximumAnnualBase: 2_110_416,
            healthMinimumMonthlyBase: decimal("21983.50"), childCareHealthExemption: true,
            minimumWage: 18_900, spouseNeedsYoungChild: true
        ),
        Row(
            year: 2025, averageWage: 46_557, taxBandThreshold: 1_676_052,
            retirementLimit: .combined(48_000),
            hasDIPAndLongTermCare: true, socialAssessmentPercent: decimal("0.55"),
            socialMinimumMonthlyMain: 16_295, socialMinimumMonthlySecondary: 5_122,
            socialDecisiveAmount: 111_736, socialMaximumAnnualBase: 2_234_736,
            healthMinimumMonthlyBase: decimal("23278.50"), childCareHealthExemption: true,
            minimumWage: 20_800, spouseNeedsYoungChild: true
        ),
        Row(
            year: 2026, averageWage: 48_967, taxBandThreshold: 1_762_812,
            retirementLimit: .combined(48_000),
            hasDIPAndLongTermCare: true, socialAssessmentPercent: decimal("0.55"),
            socialMinimumMonthlyMain: 17_139, socialMinimumMonthlySecondary: 5_387,
            socialDecisiveAmount: 117_521, socialMaximumAnnualBase: 2_350_416,
            healthMinimumMonthlyBase: decimal("24483.50"), childCareHealthExemption: false,
            minimumWage: 22_400, spouseNeedsYoungChild: true
        ),
    ]

    // MARK: The rules table

    @Test(arguments: TaxRulesTests.rows)
    func rulesMatchTheVerifiedTable(_ row: Row) {
        let year = row.year
        let (rules, isEstimate) = TaxRules.forYear(year)
        #expect(!isEstimate, "\(year) is a supported year")
        #expect(rules.year == year)
        #expect(rules.averageWage == row.averageWage, "\(year) averageWage")
        #expect(rules.taxBandThreshold == row.taxBandThreshold, "\(year) taxBandThreshold")
        #expect(rules.taxpayerCredit == 30_840, "\(year) taxpayerCredit")
        #expect(rules.retirementLimit == row.retirementLimit, "\(year) retirementLimit")
        #expect(rules.hasDIPAndLongTermCare == row.hasDIPAndLongTermCare, "\(year) hasDIPAndLongTermCare")
        #expect(rules.socialAssessmentPercent == row.socialAssessmentPercent, "\(year) socialAssessmentPercent")
        #expect(rules.socialMinimumMonthlyMain == row.socialMinimumMonthlyMain, "\(year) socialMinimumMonthlyMain")
        #expect(
            rules.socialMinimumMonthlySecondary == row.socialMinimumMonthlySecondary,
            "\(year) socialMinimumMonthlySecondary"
        )
        #expect(rules.socialDecisiveAmount == row.socialDecisiveAmount, "\(year) socialDecisiveAmount")
        #expect(rules.socialMaximumAnnualBase == row.socialMaximumAnnualBase, "\(year) socialMaximumAnnualBase")
        #expect(rules.healthMinimumMonthlyBase == row.healthMinimumMonthlyBase, "\(year) healthMinimumMonthlyBase")
        #expect(rules.childCareHealthExemption == row.childCareHealthExemption, "\(year) childCareHealthExemption")
        #expect(rules.spouseCreditMonthly == 2_070, "\(year) spouseCreditMonthly")
        #expect(rules.childMonthly == [1_267, 1_860, 2_320], "\(year) childMonthly")
        #expect(rules.minimumWage == row.minimumWage, "\(year) minimumWage")
        #expect(rules.spouseIncomeLimit == 68_000, "\(year) spouseIncomeLimit")
        #expect(rules.spouseNeedsYoungChild == row.spouseNeedsYoungChild, "\(year) spouseNeedsYoungChild")
        #expect(rules.bonusMinimum == 100, "\(year) bonusMinimum")
    }

    /// The 23 % band, the social maximum and the health minimum are fixed multiples of the average wage, so a slip
    /// in any one of those figures shows up against the average wage.
    @Test(arguments: TaxRulesTests.rows)
    func bandsAndLimitsAreMultiplesOfTheAverageWage(_ row: Row) {
        let rules = TaxRules.forYear(row.year).rules
        let bandMultiple: Int64 = row.year <= 2023 ? 48 : 36
        #expect(rules.taxBandThreshold == bandMultiple * rules.averageWage, "\(row.year) 23 % band")
        #expect(rules.socialMaximumAnnualBase == 48 * rules.averageWage, "\(row.year) social maximum")
        #expect(rules.healthMinimumMonthlyBase == Decimal(rules.averageWage) / 2, "\(row.year) health minimum")
    }

    @Test func rowsCoverEverySupportedYearOnce() {
        #expect(TaxRulesTests.rows.map(\.year) == Array(TaxRules.supportedYears))
    }

    @Test func rulesCompareByValueAndEveryYearDiffers() {
        #expect(TaxRules.forYear(2024).rules == TaxRules.forYear(2024).rules)
        #expect(TaxRules.forYear(2024).rules != TaxRules.forYear(2025).rules)
        #expect(Set(TaxRulesTests.rows.map { TaxRules.forYear($0.year).rules }).count == 5)
    }

    // MARK: Years without rules

    @Test func supportedYearsAre2022To2026() {
        #expect(TaxRules.supportedYears == 2022...2026)
    }

    @Test(arguments: 2022...2026)
    func supportedYearsGiveTheirOwnRulesAndNoEstimate(_ year: Int) {
        let result = TaxRules.forYear(year)
        #expect(result.rules.year == year)
        #expect(!result.isEstimate)
    }

    @Test func aYearAfterTheLastOneUsesTheLastRulesAsAnEstimate() {
        let last = TaxRules.forYear(2026).rules
        let next = TaxRules.forYear(2027)
        #expect(next.rules == last)
        #expect(next.isEstimate)
        // The estimate carries the year of the rules it borrows, so a caller can tell which rules were used.
        #expect(next.rules.year == 2026)
        for year in [2028, 2100, Int.max] {
            let result = TaxRules.forYear(year)
            #expect(result.rules == last, "\(year)")
            #expect(result.isEstimate, "\(year)")
        }
    }

    @Test func aYearBeforeTheFirstOneUsesTheFirstRulesAsAnEstimate() {
        let first = TaxRules.forYear(2022).rules
        let previous = TaxRules.forYear(2021)
        #expect(previous.rules == first)
        #expect(previous.isEstimate)
        #expect(previous.rules.year == 2022)
        for year in [2000, 0, -1, Int.min] {
            let result = TaxRules.forYear(year)
            #expect(result.rules == first, "\(year)")
            #expect(result.isEstimate, "\(year)")
        }
    }

    @Test func the2025RulesAreNotAnEstimate() {
        #expect(!TaxRules.forYear(2025).isEstimate)
    }

    // MARK: Constants that hold in every year

    @Test func ratesAndGiftLimitsAreExact() {
        #expect(TaxRules.taxRateLow == decimal("0.15"))
        #expect(TaxRules.taxRateHigh == decimal("0.23"))
        #expect(TaxRules.socialRate == decimal("0.292"))
        #expect(TaxRules.healthRate == decimal("0.135"))
        #expect(TaxRules.healthAssessmentPercent == decimal("0.5"))
        #expect(TaxRules.giftsCapPercent == decimal("0.30"))
        #expect(TaxRules.giftsMinimumKc == 1_000)
        #expect(TaxRules.giftsMinimumPercent == decimal("0.02"))
    }

    @Test func expenseCapsAreTheStatutoryAmounts() {
        #expect(TaxRules.expenseCap(percent: 80) == 1_600_000)
        #expect(TaxRules.expenseCap(percent: 60) == 1_200_000)
        #expect(TaxRules.expenseCap(percent: 40) == 800_000)
        #expect(TaxRules.expenseCap(percent: 30) == 600_000)
    }

    @Test(arguments: [50, 0, 20, 29, 31, 59, 61, 70, 79, 81, 100, -60])
    func otherExpensePercentagesHaveNoCap(_ percent: Int) {
        #expect(TaxRules.expenseCap(percent: percent) == nil)
    }

    // MARK: Decisive amount

    /// ⌈D ÷ 12⌉ of each year's decisive amount, worked out by hand: 93 387 ÷ 12 = 7 782,25 and so on.
    @Test(arguments: [(2022, 7_783), (2023, 8_065), (2024, 8_794), (2025, 9_312), (2026, 9_794)] as [(Int, Int64)])
    func decisiveTwelfthRoundsUpToWholeCrowns(_ year: Int, _ twelfth: Int64) {
        #expect(TaxRules.forYear(year).rules.decisiveTwelfth == twelfth)
    }

    @Test func reducedDecisiveAmountTakesOffATwelfthForEachMonthWithoutSecondaryActivity() {
        let rules2022 = TaxRules.forYear(2022).rules
        let rules2025 = TaxRules.forYear(2025).rules
        #expect(rules2022.decisiveTwelfth == 7_783)
        // Six secondary months: the values of the ČSSZ tables.
        #expect(rules2022.reducedDecisiveAmount(monthsWithoutSecondary: 6) == 46_689)
        #expect(rules2025.reducedDecisiveAmount(monthsWithoutSecondary: 6) == 55_864)
        // Twelve secondary months: the whole amount.
        #expect(rules2022.reducedDecisiveAmount(monthsWithoutSecondary: 0) == 93_387)
        // The month's share is the rounded-up twelfth (7 783), not 93 387 ÷ 12 = 7 782,25.
        #expect(rules2022.reducedDecisiveAmount(monthsWithoutSecondary: 1) == 85_604)
    }

    // MARK: The family credits

    /// A year's spouse credit and child amounts are twelve monthly ones: 24 840 Kč, and 15 204, 22 320 and 27 840 Kč
    /// for the first, the second and the third and every further child.
    @Test(arguments: 2022...2026)
    func theYearlyFamilyAmountsAreTwelveMonthlyOnes(_ year: Int) {
        let rules = TaxRules.forYear(year).rules
        #expect(12 * rules.spouseCreditMonthly == 24_840)
        #expect(rules.childMonthly.map { 12 * $0 } == [15_204, 22_320, 27_840])
    }

    /// The bonus is paid only with an income of six minimum wages of the year, the minimum wage of 1 January.
    @Test(arguments: [
        (2022, 97_200), (2023, 103_800), (2024, 113_400), (2025, 124_800), (2026, 134_400),
    ] as [(Int, Int64)])
    func theBonusIncomeThresholdIsSixMinimumWages(_ year: Int, _ threshold: Int64) {
        #expect(TaxRules.forYear(year).rules.bonusIncomeThreshold == threshold)
    }

    // MARK: Verification and sources

    @Test(arguments: 2022...2026)
    func everyYearCarriesTheVerificationDate(_ year: Int) {
        // The day the rules were last checked, with the spouse credit and the child benefit. The date has a no-break
        // space after each dot, like every date the app shows.
        #expect(TaxRules.forYear(year).rules.verification == "ověřeno 20.\u{00A0}10.\u{00A0}2026")
    }

    @Test(arguments: 2022...2026)
    func everyYearNamesItsLegalSources(_ year: Int) {
        let sources = TaxRules.forYear(year).rules.sources
        let text = sources.joined(separator: "\n")
        #expect(Set(sources).count == sources.count, "\(year) lists a source twice")
        for number in ["586/1992", "589/1992", "592/1992", "128/2022", "349/2023", "24/2025"] {
            #expect(text.contains(number), "\(year) names \(number)")
        }
        // Only the government decree of the year itself is named.
        let decrees = [2022: "356/2021", 2023: "290/2022", 2024: "286/2023", 2025: "282/2024", 2026: "365/2025"]
        for (decreeYear, number) in decrees {
            #expect(text.contains(number) == (decreeYear == year), "\(year) and decree \(number)")
        }
        // The change of the 2026 social minimum applies to 2026 only.
        #expect(text.contains("90/2026") == (year == 2026), "\(year) and zákon 90/2026")
        // Only the regulation of the minimum wage of the year itself is named: the government decree of the year until
        // 2024, and from 2025 the announcement of the year's amount by the MPSV.
        let minimumWages = [2022: "405/2021", 2023: "465/2022", 2024: "396/2023", 2025: "286/2024", 2026: "356/2025"]
        for (wageYear, number) in minimumWages {
            #expect(text.contains(number) == (wageYear == year), "\(year) and the minimum wage of \(wageYear)")
        }
        // The government decree that sets the minimum wage from the average wage from 2025 is named in each of those
        // years, in the same line as the year's announcement.
        #expect(text.contains("285/2024") == (year >= 2025), "\(year) and nařízení vlády č. 285/2024 Sb.")
        let announcements = [2025: "286/2024", 2026: "356/2025"]
        if let announcement = announcements[year] {
            #expect(
                sources.contains(
                    "nařízení vlády č. 285/2024 Sb. a sdělení MPSV č. \(announcement) Sb. (minimální mzda)"),
                "\(year) cites the decree with its announcement")
        }
        // The child benefit in every year, and the conditions of the spouse credit in § 35bb from 2024.
        #expect(text.contains("§ 35c"), "\(year) names § 35c")
        #expect(text.contains("§ 35bb") == (year >= 2024), "\(year) and § 35bb")
    }
}

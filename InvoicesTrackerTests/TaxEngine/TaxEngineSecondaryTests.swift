import Foundation
import Testing
@testable import InvoicesTracker

struct TaxEngineSecondaryTests {
    /// The cases with secondary or inactive months: S5a, S5b, S6 and S7 of each year.
    static let secondaryAndPartYearCases = GoldenCases.all.filter { $0.months.contains { $0 != "M" } }

    // MARK: Golden vectors

    /// A whole year (31 December, every month counted, the secondary months exempt from the health minimum) gives
    /// every value of the vector.
    @Test(arguments: TaxEngineSecondaryTests.secondaryAndPartYearCases)
    func goldenSecondaryAndPartYear(case c: GoldenCase) {
        let result = TaxEngine.compute(input(for: c), asOf: civilDate("\(c.year)-12-31"))
        expectResult(result, matches: c)
    }

    /// Guards the filter above, so a typo in the vectors cannot quietly drop cases from the test.
    @Test func secondaryAndPartYearCasesAreFourScenariosOfEveryYear() {
        let cases = TaxEngineSecondaryTests.secondaryAndPartYearCases
        #expect(cases.count == 20)
        for year in 2022...2026 {
            let names = cases.filter { $0.year == year }.map(\.name)
            #expect(names == ["S5a", "S5b", "S6", "S7"], "\(year)")
        }
    }

    @Test(arguments: GoldenCases.mixed)
    func mixedRows(case c: MixedCase) {
        let rules = TaxRules.forYear(c.year).rules
        let social = TaxEngine.socialAssessment(
            dz: c.dz,
            mainMonths: c.mainMonths,
            secondaryMonths: c.secondaryMonths,
            rules: rules
        )
        #expect(social.secondaryInsured == c.secondaryInsured)
        #expect(social.base == c.socialBase)
        #expect(social.insurance == c.socialInsurance)
    }

    // MARK: Decisive amount

    /// "Dosáhl aspoň": a secondary activity whose profit equals the decisive amount is insured.
    @Test func decisiveBoundaryIsInclusive() {
        let rules = TaxRules.forYear(2022).rules
        let reached = TaxEngine.socialAssessment(dz: 93_387, mainMonths: 0, secondaryMonths: 12, rules: rules)
        #expect(reached.secondaryInsured == true)
        #expect(reached.base == 46_704)
        #expect(reached.insurance == 13_638)

        let missed = TaxEngine.socialAssessment(dz: 93_386, mainMonths: 0, secondaryMonths: 12, rules: rules)
        #expect(missed.secondaryInsured == false)
        #expect(missed.base == 0)
        #expect(missed.insurance == 0)
    }

    // MARK: The rows of the assessment

    /// 2024, profit 123 457 over 7 main and 5 secondary months. Row 23 is 123 457 ÷ 12 = 10 288,083… → 10 288,08; the
    /// decisive amount less seven twelfths is 105 520 − 7 × 8 794 = 43 962, and the secondary share 51 440,40 reaches
    /// it. Row 25: ⌈0,55 × 72 016,56⌉ = 39 610 and ⌈0,55 × 51 440,40⌉ = 28 293; row 26: 13 191 × 7 = 92 337 and
    /// 4 837 × 5 = 24 185. The main minimum plus the secondary share of the profit is the highest: 120 630.
    @Test func mixedYearFollowsTheRowsOfTheOverview() {
        let social = TaxEngine.socialAssessment(
            dz: 123_457,
            mainMonths: 7,
            secondaryMonths: 5,
            rules: TaxRules.forYear(2024).rules
        )
        #expect(social.mainMonths == 7)
        #expect(social.secondaryMonths == 5)
        #expect(social.row23 == decimal("10288.08"))
        #expect(social.reducedDecisiveAmount == 43_962)
        #expect(social.secondaryInsured == true)
        #expect(social.computedBase == 67_903)
        #expect(social.minimumBase == 116_522)
        #expect(social.maximumBase == 2_110_416)
        #expect(social.base == 120_630)
        #expect(social.insurance == 35_224)
    }

    /// 2025, profit 90 000 over 6 main and 6 secondary months: the secondary share 45 000 misses 55 864, so only the
    /// main part counts: ⌈0,55 × 45 000⌉ = 24 750 against the minimum 16 295 × 6 = 97 770.
    @Test func mixedYearWithAnUninsuredSecondaryPartCountsOnlyTheMainPart() {
        let social = TaxEngine.socialAssessment(
            dz: 90_000,
            mainMonths: 6,
            secondaryMonths: 6,
            rules: TaxRules.forYear(2025).rules
        )
        #expect(social.row23 == decimal("7500"))
        #expect(social.reducedDecisiveAmount == 55_864)
        #expect(social.secondaryInsured == false)
        #expect(social.computedBase == 24_750)
        #expect(social.minimumBase == 97_770)
        #expect(social.base == 97_770)
        #expect(social.insurance == 28_549)
    }

    @Test func secondaryOnlyYearHasNoRow23() {
        let rules = TaxRules.forYear(2022).rules
        let insured = TaxEngine.socialAssessment(dz: 120_000, mainMonths: 0, secondaryMonths: 12, rules: rules)
        #expect(insured.row23 == nil)
        #expect(insured.reducedDecisiveAmount == 93_387)
        #expect(insured.computedBase == 60_000)
        #expect(insured.minimumBase == 46_704)
        #expect(insured.base == 60_000)

        // Nothing is assessed for a secondary activity that is not insured.
        let uninsured = TaxEngine.socialAssessment(dz: 80_000, mainMonths: 0, secondaryMonths: 12, rules: rules)
        #expect(uninsured.row23 == nil)
        #expect(uninsured.computedBase == 0)
        #expect(uninsured.minimumBase == 0)
        #expect(uninsured.base == 0)
    }

    // MARK: Counted months

    /// As of 31 March only January to March count, and they are all main months: the main-activity formula applies.
    @Test func windowBeforeSecondaryMonths() {
        let input = yearInput(2026, receipts: [payment("2026-02-01", kc: 100_000)], months: "MMMMMMSSSSSS")
        let result = TaxEngine.compute(input, asOf: civilDate("2026-03-31"))
        #expect(result.social.mainMonths == 3)
        #expect(result.social.secondaryMonths == 0)
        #expect(result.social.minimumBase == 51_417)
        #expect(result.social.base == 51_417)
        #expect(result.social.secondaryInsured == nil)
        #expect(result.social.reducedDecisiveAmount == nil)
    }

    /// As of 30 September the counted months are six main and three secondary. By the app's as-of convention the
    /// three months not reached yet also count as months without secondary activity, so the decisive amount loses
    /// nine twelfths (117 521 − 9 × 9 794 = 29 375), and row 23 divides the profit 240 000 by nine: 26 666,67.
    @Test func secondaryMonthsCountWithinTheCountedMonths() {
        let input = yearInput(2026, receipts: [payment("2026-02-01", kc: 600_000)], months: "MMMMMMSSSSSS")
        let result = TaxEngine.compute(input, asOf: civilDate("2026-09-30"))
        #expect(result.DZ == 240_000)
        #expect(result.social.mainMonths == 6)
        #expect(result.social.secondaryMonths == 3)
        #expect(result.social.reducedDecisiveAmount == 29_375)
        #expect(result.social.row23 == decimal("26666.67"))
        #expect(result.social.secondaryInsured == true)
        #expect(result.social.base == 146_835)
        #expect(result.social.insurance == 42_876)
    }

    /// 2022: no activity January to March, main activity April to June, secondary July to December (exempt from the
    /// health minimum), 600 000 Kč in the whole year, so the profit is 240 000. Row 23 divides it by the nine active
    /// months only: 26 666,67 (twelve months would give 20 000, a base of 90 000 and insurance of 26 280). The
    /// inactive months count like the main ones as months without secondary activity: 93 387 − 6 × 7 783 = 46 689.
    /// Row 25: ⌈0,5 × 80 000,01⌉ = 40 001 and ⌈0,5 × 160 000,02⌉ = 80 001; row 26: 9 728 × 3 = 29 184 and
    /// 3 892 × 6 = 23 352. Base 120 002, insurance ⌈0,292 × 120 002⌉ = 35 041.
    @Test func mixedPartYearDividesRow23ByTheActiveMonthsOnly() {
        var input = yearInput(2022, receipts: [payment("2022-06-15", kc: 600_000)], months: "---MMMSSSSSS")
        input.healthExemptMonths = Set(7...12)
        let result = TaxEngine.compute(input, asOf: civilDate("2022-12-31"))
        #expect(result.DZ == 240_000)
        #expect(result.social.mainMonths == 3)
        #expect(result.social.secondaryMonths == 6)
        #expect(result.social.row23 == decimal("26666.67"))
        #expect(result.social.reducedDecisiveAmount == 46_689)
        #expect(result.social.secondaryInsured == true)
        #expect(result.social.computedBase == 120_002)
        #expect(result.social.minimumBase == 52_536)
        #expect(result.social.base == 120_002)
        #expect(result.social.insurance == 35_041)
        // The health minimum applies only in the three main months: active and not exempt.
        #expect(result.health.minimumMonths == 3)
    }

    // MARK: Years without rules

    /// A year after the last one with rules uses that year's rules as an estimate, a year before the first one uses
    /// the first year's rules, and a supported year uses its own.
    @Test func unsupportedYears() {
        let expected: [(year: Int, rulesYear: Int, isEstimate: Bool)] = [
            (2027, 2026, true),
            (2021, 2022, true),
            (2026, 2026, false),
        ]
        for (year, rulesYear, isEstimate) in expected {
            let input = yearInput(year, receipts: [payment("\(year)-02-01", kc: 100_000)])
            let result = TaxEngine.compute(input, asOf: civilDate("\(year)-12-31"))
            #expect(result.year == year)
            #expect(result.rulesAreEstimate == isEstimate, "\(year)")
            #expect(result.rules.year == rulesYear, "\(year)")
        }
    }
}

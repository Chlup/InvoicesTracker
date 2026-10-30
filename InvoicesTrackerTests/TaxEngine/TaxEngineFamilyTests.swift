import Foundation
import Testing
@testable import InvoicesTracker

/// The spouse credit and the child tax benefit in the tax of a year. The taxpayer credit comes first, then the spouse
/// credit, both taking the tax down to zero at most ("Daň po slevách"); then the child benefit is a credit up to the
/// tax that is left, and the rest is a bonus, paid when it is at least 100 Kč and the income received by the as-of day
/// is at least six minimum wages. The tax stays at zero or above; the net tax, the tax less the bonus, is what the
/// balance with the tax office, the totals, the marginal rate and the effect of a receipt count. The figures were
/// worked out by hand.
struct TaxEngineFamilyTests {
    /// The sample family: Anna (3. 9. 2019) and Tomáš (12. 4. 2024), the first and the second child, in the household
    /// the whole year and claimed by me, and a spouse without own income claimed for the whole year.
    static let sampleFamily = FamilyFacts(
        children: [
            ChildFacts(
                label: "Anna", birthDate: civilDate("2019-09-03"), household: MonthRange.wholeYear, claimant: .me,
                order: 1, ztpp: nil, studies: nil),
            ChildFacts(
                label: "Tomáš", birthDate: civilDate("2024-04-12"), household: MonthRange.wholeYear, claimant: .me,
                order: 2, ztpp: nil, studies: nil),
        ],
        spouse: SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil))

    /// Two receipts of 2026: 120 000 Kč on 20. 1. and 130 000 Kč on 20. 2.
    static let earlyReceipts = [payment("2026-01-20", kc: 120_000), payment("2026-02-20", kc: 130_000)]

    /// 2026 at 60 % flat-rate expenses, with `receipts` and `family`.
    static func input(_ receipts: [Receipt], family: FamilyFacts = sampleFamily) -> YearInput {
        var input = yearInput(2026, receipts: receipts)
        input.family = family
        return input
    }

    /// The whole year 2026 with one receipt of `kc` on 15. 6. and `family`.
    static func wholeYear(_ kc: Int64, family: FamilyFacts = sampleFamily) -> TaxResult {
        TaxEngine.compute(input([payment("2026-06-15", kc: kc)], family: family), asOf: civilDate("2026-12-31"))
    }

    // MARK: The checked cases

    /// 2 035 200 Kč at 60 %: the expenses stop at the cap of 1 200 000 Kč, the profit and the base are 835 200 Kč and
    /// the tax before the credits is 125 280 Kč. The taxpayer credit (30 840) and the spouse credit (24 840) take it to
    /// 69 600 Kč, and the children's 37 524 Kč (Anna 15 204, Tomáš 22 320) to 32 076 Kč, with no bonus.
    @Test func theSampleFamilyIn2026() {
        let result = Self.wholeYear(2_035_200)

        #expect(result.V == 1_200_000)
        #expect(result.DZ == 835_200)
        #expect(result.B == 835_200)
        #expect(result.taxBeforeCredit == 125_280)
        #expect(result.creditApplied == 30_840)
        #expect(result.spouseCreditApplied == 24_840)
        #expect(result.family.spouseMonths == 12)
        // "Daň po slevách".
        #expect(result.taxBeforeCredit - result.creditApplied - result.spouseCreditApplied == 69_600)
        #expect(result.taxAfterCredits == 69_600)
        #expect(result.family.children.map(\.amount) == [15_204, 22_320])
        #expect(result.family.childBenefit == 37_524)
        #expect(result.childCredit == 37_524)
        #expect(result.tax == 32_076)
        #expect(result.childBonus == 0)
        #expect(result.bonusWithheld == nil)
        #expect(result.withheldBonus == 0)
        #expect(result.netTax == 32_076)
        #expect(result.balance(.tax).liability == 32_076)
    }

    /// The sample family with 120 000 Kč received on 20. 1. and 130 000 Kč on 20. 2. The credits count every month of
    /// the year, but the bonus asks for an income of six minimum wages (6 × 22 400 = 134 400 Kč) received by the as-of
    /// day. As of 31. 1. the taxpayer credit covers the tax and the bonus is not paid yet; as of 28. 2. it is.
    @Test func aBonusIsPaidOnceIncomeReachesSixMinimumWages() {
        let january = TaxEngine.compute(Self.input(Self.earlyReceipts), asOf: civilDate("2026-01-31"))
        #expect(january.P == 120_000)
        #expect(january.family.childBenefit == 37_524)
        #expect(january.family.spouseCredit == 24_840)
        #expect(january.spouseCreditApplied == 0)
        #expect(january.childCredit == 0)
        #expect(january.tax == 0)
        #expect(january.childBonus == 0)
        #expect(january.bonusWithheld == .incomeBelowThreshold(134_400))
        #expect(january.withheldBonus == 37_524)
        #expect(january.netTax == 0)

        let february = TaxEngine.compute(Self.input(Self.earlyReceipts), asOf: civilDate("2026-02-28"))
        #expect(february.P == 250_000)
        #expect(february.tax == 0)
        #expect(february.childBonus == 37_524)
        #expect(february.bonusWithheld == nil)
        #expect(february.withheldBonus == 0)
        #expect(february.netTax == -37_524)
    }

    /// 766 000 Kč at 60 %: the base is 306 400 Kč, the tax before the credits 45 960 Kč and 15 120 Kč after the
    /// taxpayer credit. One child at the first rate the whole year (15 204 Kč) takes all of it and leaves 84 Kč, which
    /// is not paid.
    @Test func aBonusUnder100IsNotPaid() {
        let result = Self.wholeYear(766_000, family: FamilyFacts(children: [Self.sampleFamily.children[0]]))

        #expect(result.B == 306_400)
        #expect(result.taxBeforeCredit == 45_960)
        #expect(result.taxBeforeCredit - result.creditApplied == 15_120)
        #expect(result.spouseCreditApplied == 0)
        #expect(result.family.childBenefit == 15_204)
        #expect(result.childCredit == 15_120)
        #expect(result.childBonus == 0)
        #expect(result.bonusWithheld == .belowMinimum)
        #expect(result.withheldBonus == 84)
        #expect(result.tax == 0)
        #expect(result.netTax == 0)
    }

    /// Advances of 10 000 Kč paid and a bonus of 37 524 Kč: the tax office returns both, 47 524 Kč, and none of it pays
    /// what the insurers are owed.
    @Test func advancesAndTheBonusComeBackTogether() {
        var input = Self.input(Self.earlyReceipts)
        input.advances.tax[0] = 10_000
        let result = TaxEngine.compute(input, asOf: civilDate("2026-02-28"))

        let tax = result.balance(.tax)
        #expect(tax.liability == -37_524)
        #expect(tax.advancesPaid == 10_000)
        #expect(tax.remaining == 0)
        #expect(tax.overpayment == 47_524)
        #expect(tax.leavesViaPlannedAdvances == 0)
        #expect(tax.settlement == 0)
        #expect(result.overpaymentTotal == 47_524)
        #expect(result.balance(.social).remaining == result.social.insurance)
        #expect(result.balance(.health).remaining == result.health.insurance)
        #expect(result.remainingTotal == result.social.insurance + result.health.insurance)
        #expect(result.liabilityTotal == -37_524 + result.social.insurance + result.health.insurance)
    }

    // MARK: The bonus

    /// A bonus of exactly 100 Kč is paid. Ema is born on 15. 3. 2026, so 10 months at the first rate give 12 670 Kč. At
    /// 723 500 Kč the base is 289 400 Kč, the tax after the taxpayer credit 12 570 Kč, and 100 Kč is left. At 723 750
    /// Kč the base is 289 500 Kč and 15 Kč less is left: 85 Kč, which is not paid.
    @Test func aBonusOfExactly100IsPaid() {
        let ema = ChildFacts(
            label: "Ema", birthDate: civilDate("2026-03-15"), household: MonthRange.wholeYear, claimant: .me, order: 1,
            ztpp: nil, studies: nil)

        let hundred = Self.wholeYear(723_500, family: FamilyFacts(children: [ema]))
        #expect(hundred.family.childBenefit == 12_670)
        #expect(hundred.B == 289_400)
        #expect(hundred.childCredit == 12_570)
        #expect(hundred.childBonus == 100)
        #expect(hundred.bonusWithheld == nil)
        #expect(hundred.netTax == -100)

        let less = Self.wholeYear(723_750, family: FamilyFacts(children: [ema]))
        #expect(less.B == 289_500)
        #expect(less.childCredit == 12_585)
        #expect(less.childBonus == 0)
        #expect(less.bonusWithheld == .belowMinimum)
        #expect(less.withheldBonus == 85)
        #expect(less.netTax == 0)
    }

    /// The income the bonus asks for is six minimum wages of the year, and that income exactly is enough. With one
    /// child (Anna, 15 204 Kč) and an income whose tax the taxpayer credit covers, the whole benefit is the bonus.
    @Test(arguments: [
        (2022, 97_200), (2023, 103_800), (2024, 113_400), (2025, 124_800), (2026, 134_400),
    ] as [(Int, Int64)])
    func theBonusAsksForSixMinimumWagesOfTheYear(_ year: Int, _ threshold: Int64) {
        func result(_ kc: Int64) -> TaxResult {
            var input = yearInput(year, receipts: [payment("\(year)-06-15", kc: kc)])
            input.family = FamilyFacts(children: [Self.sampleFamily.children[0]])
            return TaxEngine.compute(input, asOf: civilDate("\(year)-12-31"))
        }

        let below = result(threshold - 1)
        #expect(below.tax == 0)
        #expect(below.childBonus == 0)
        #expect(below.bonusWithheld == .incomeBelowThreshold(threshold))
        #expect(below.withheldBonus == 15_204)

        let reached = result(threshold)
        #expect(reached.childBonus == 15_204)
        #expect(reached.bonusWithheld == nil)
        #expect(reached.netTax == -15_204)
    }

    /// A spouse credit larger than the tax the taxpayer credit leaves takes the tax to zero and no further: only the
    /// child benefit is paid out. At 600 000 Kč the tax is 36 000 Kč before the credits and 5 160 Kč after the taxpayer
    /// credit.
    @Test func theSpouseCreditTakesTheTaxToZeroAtMost() {
        let result = Self.wholeYear(600_000)

        #expect(result.taxBeforeCredit == 36_000)
        #expect(result.family.spouseCredit == 24_840)
        #expect(result.spouseCreditApplied == 5_160)
        #expect(result.childCredit == 0)
        #expect(result.tax == 0)
        #expect(result.childBonus == 37_524)
        #expect(result.netTax == -37_524)
    }

    // MARK: What a crown and a receipt cost

    /// One more crown and one more receipt cost what they take off the bonus too. At 1 000 000 Kč the credits leave 4
    /// 320 Kč of tax, which the children's 37 524 Kč take, so the bonus is 33 204 Kč; 100 000 Kč more is 6 000 Kč more
    /// tax before the credits and as much less bonus. The receipt of 20. 2. brings the income to six minimum wages, so
    /// it brings the whole bonus.
    @Test func theMarginalRateAndTheEffectOfAReceiptCountTheBonus() throws {
        let result = Self.wholeYear(1_000_000)
        #expect(result.tax == 0)
        #expect(result.childBonus == 33_204)
        #expect(result.marginal[.tax] == decimal("0.06"))

        let input = Self.input(Self.earlyReceipts)
        let receipt = try #require(input.receipts.last)
        let effect = TaxEngine.effect(of: receipt, in: input)
        #expect(effect.tax == -37_524)
        #expect(effect.total == effect.tax + effect.social + effect.health)
    }

    /// The bonus that six minimum wages of income bring is a step, not a rate: the next crown is levied with the bonus
    /// paid or not, as it is now. As of 31. 1. the income is 120 000 Kč and the bonus is not paid yet; 100 000 Kč more
    /// would bring all of it, but the rate is that of the levies with it still not paid: no tax, which the taxpayer
    /// credit covers, 6 424 Kč more social and 2 634 Kč more health insurance. As of 28. 2. it is paid on both sides.
    @Test func theMarginalRateHoldsTheBonusAsItIsNow() {
        let january = TaxEngine.compute(Self.input(Self.earlyReceipts), asOf: civilDate("2026-01-31"))
        #expect(january.bonusWithheld == .incomeBelowThreshold(134_400))
        #expect(january.marginal[.tax] == 0)
        #expect(january.marginal[.social] == decimal("0.06424"))
        #expect(january.marginal[.health] == decimal("0.02634"))
        #expect(january.marginalTotal == decimal("0.09058"))

        let february = TaxEngine.compute(Self.input(Self.earlyReceipts), asOf: civilDate("2026-02-28"))
        #expect(february.childBonus == 37_524)
        #expect(february.marginal[.tax] == 0)
    }

    /// A bonus that is paid stays paid on the other side of the step, even when 100 000 Kč more would leave less of it
    /// than the 100 Kč that are paid. With Anna alone, 666 500 Kč at 60 % are a base of 266 600 Kč and a tax of
    /// 9 150 Kč after the taxpayer credit, so 6 054 Kč of her 15 204 Kč are paid as a bonus; 100 000 Kč more are
    /// 6 000 Kč more tax and leave 54 Kč, which would not be paid: the rate is the 6 000 Kč, not the 6 054 Kč.
    @Test func aBonusThatIsPaidIsHeldPaidForTheMarginalRate() {
        let result = Self.wholeYear(666_500, family: FamilyFacts(children: [Self.sampleFamily.children[0]]))

        #expect(result.B == 266_600)
        #expect(result.childCredit == 9_150)
        #expect(result.childBonus == 6_054)
        #expect(result.marginal[.tax] == decimal("0.06"))
    }

    // MARK: The threshold of the bonus

    /// The receipt of 20. 2. takes the income from 120 000 Kč to 250 000 Kč, past six minimum wages (134 400 Kč), and
    /// so brings the whole bonus of 37 524 Kč: it names the threshold with the bonus, and its effect stays the true
    /// change, the bonus included.
    @Test func aReceiptThatBringsTheIncomeToSixMinimumWagesNamesTheBonusItBrings() throws {
        let input = Self.input(Self.earlyReceipts)
        let receipt = try #require(input.receipts.last)

        let effect = TaxEngine.effect(of: receipt, in: input)

        #expect(
            effect.crossings == [
                ThresholdCrossing(threshold: .bonusIncome, limit: 134_400, extent: .part(115_600), bonus: 37_524)
            ])
        #expect(effect.tax == -37_524)
    }

    /// Only the receipt that brings the bonus names the threshold. One that ends exactly at six minimum wages brings
    /// it, with no crown past it; one after them does not name it, and neither does one that reaches them without a
    /// bonus to pay: without a family, or with less than 100 Kč of the benefit left at the income it brings.
    @Test func onlyTheReceiptThatBringsTheBonusNamesItsThreshold() {
        let january = [payment("2026-01-20", kc: 120_000)]

        let exactly = TaxEngine.effect(of: payment("2026-02-20", kc: 14_400), in: Self.input(january))
        #expect(
            exactly.crossings == [
                ThresholdCrossing(threshold: .bonusIncome, limit: 134_400, extent: .part(0), bonus: 37_524)
            ])

        let later = TaxEngine.effect(of: payment("2026-03-02", kc: 10_000), in: Self.input(Self.earlyReceipts))
        #expect(later.crossings.isEmpty)

        let withoutAFamily = TaxEngine.effect(
            of: payment("2026-02-20", kc: 130_000), in: Self.input(january, family: FamilyFacts()))
        #expect(withoutAFamily.crossings.isEmpty)

        // Anna alone: 646 000 Kč more take the income to 766 000 Kč, where 84 Kč of her benefit are left.
        let anna = FamilyFacts(children: [Self.sampleFamily.children[0]])
        let underAHundred = TaxEngine.effect(
            of: payment("2026-06-15", kc: 646_000), in: Self.input(january, family: anna))
        #expect(underAHundred.crossings.isEmpty)
    }

    // MARK: Without a family

    /// Without a family nothing changes: no credit of the family, no bonus, and the net tax is the tax.
    @Test func withoutAFamilyTheTaxIsAsItWas() {
        let result = TaxEngine.compute(TaxEngineRegressionTests.sampleYear2026, asOf: civilDate("2026-10-17"))

        #expect(
            result.family
                == FamilyCredits(
                    spouseMonths: 0, spouseZTPPMonths: 0, spouseYoungChildMonths: 0, spouseCredit: 0, children: [],
                    childBenefit: 0))
        #expect(result.spouseCreditApplied == 0)
        #expect(result.childCredit == 0)
        #expect(result.childBonus == 0)
        #expect(result.bonusWithheld == nil)
        #expect(result.tax == 94_440)
        #expect(result.netTax == 94_440)
        #expect(result.balance(.tax).liability == 94_440)
    }
}

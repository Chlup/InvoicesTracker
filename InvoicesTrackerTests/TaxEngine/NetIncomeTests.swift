import Foundation
import Testing
@testable import InvoicesTracker

/// The net income of a year ("čistý příjem"): the income the engine counts less the tax, the social insurance and the
/// health insurance, its average over the months, and the part of the income that each levy takes. The figures were
/// worked out for the same data by a separate implementation: the sample year of `PredictionSample` as of 17. 10. 2026,
/// its estimate for the whole of 2026, 2025 as of its last day, and a simulation of 2 500 000 Kč.
struct NetIncomeTests {
    // MARK: Helpers

    /// The levies of the sample year `year` (`PredictionSample.yearInput(year:)`) as of `day`, written `YYYY-MM-DD`.
    private func sample(_ year: Int, asOf day: String) -> TaxResult {
        TaxEngine.compute(PredictionSample.yearInput(year: year), asOf: civilDate(day))
    }

    /// 2026 of the sample family with 120 000 Kč received on 20. 1. and 130 000 Kč on 20. 2., as of 28. 2.: the income
    /// has reached six minimum wages, so what the child benefit leaves after its credit is paid as a tax bonus of
    /// 37 524 Kč, and the net tax is below zero.
    private func bonusYear() -> TaxResult {
        TaxEngine.compute(TaxEngineFamilyTests.input(TaxEngineFamilyTests.earlyReceipts), asOf: civilDate("2026-02-28"))
    }

    // MARK: The net income

    /// The sample year as of 17. 10. 2026: 2 191 771 Kč of income less 258 300 Kč of levies leave 1 933 471 Kč, which
    /// over the ten months so far is 193 347 Kč a month.
    @Test func theSampleYearSoFarLeavesItsIncomeLessItsLevies() {
        let net = NetIncome(sample(2026, asOf: "2026-10-17"))

        #expect(net.incomeKc == 2_191_771)
        #expect(net.leviesKc == 258_300)
        #expect(net.yearKc == 1_933_471)
        #expect(net.months == 10)
        #expect(!net.isWholeYear)
        #expect(net.monthlyKc == 193_347)
    }

    /// 2025 as of its last day is a whole year: 2 393 295 Kč over twelve months is 199 441 Kč a month.
    @Test func aYearShownAsOfItsLastDayIsAWholeYear() {
        let net = NetIncome(sample(2025, asOf: "2025-12-31"))

        #expect(net.yearKc == 2_393_295)
        #expect(net.months == 12)
        #expect(net.isWholeYear)
        #expect(net.monthlyKc == 199_441)
    }

    /// The prediction's 2 743 157 Kč income less 466 782 Kč levies leaves 2 276 375 Kč for the whole year.
    /// Spread over twelve months, 189 697.916… Kč rounds to 189 698 Kč.
    @Test func theEstimateOfTheYearIsAWholeYear() throws {
        let net = NetIncome(try PredictionSample.outcome(year: 2026).result)

        #expect(net.yearKc == 2_276_375)
        #expect(net.monthlyKc == 189_698)
        #expect(net.months == 12)
        #expect(net.isWholeYear)
    }

    /// A simulation is worked out as of 31. 12., with the income received on that day: 2 039 310 Kč over twelve months
    /// is 169 942,5 Kč, and the half goes up.
    @Test func theSimulationIsAWholeYear() throws {
        let choices = SimulatorInput(
            year: 2026, incomeKc: 2_500_000, expensePercent: 60, activity: .main, healthMinimumExempt: false,
            months: 12, deductions: Deductions(), taxpayerCredit: true,
            family: FamilyYear(year: 2026, children: [], spouse: nil))
        let net = NetIncome(try AppModel.compute(SimulatorBuilder.input(choices), asOf: civilDate("2026-12-31")))

        #expect(net.yearKc == 2_039_310)
        #expect(net.monthlyKc == 169_943)
    }

    /// The levies count the net tax, which is the tax less a tax bonus, so a bonus adds to what the income leaves.
    @Test func aTaxBonusAddsToTheNetIncome() {
        let result = bonusYear()
        #expect(result.netTax == -37_524)

        let net = NetIncome(result)

        #expect(net.yearKc == result.P + 37_524 - result.social.insurance - result.health.insurance)
        #expect(net.months == 2)
    }

    /// 189 698,5 goes up to 189 699, and −8 310,5 goes down to −8 311, so a loss is rounded as a gain is. −8 310 is not
    /// a half and stays.
    @Test func theAverageRoundsHalvesAwayFromZero() {
        #expect(NetIncome(incomeKc: 2_276_382, leviesKc: 0, months: 12, isWholeYear: true).monthlyKc == 189_699)
        #expect(NetIncome(incomeKc: 0, leviesKc: 99_726, months: 12, isWholeYear: true).monthlyKc == -8_311)
        #expect(NetIncome(incomeKc: 0, leviesKc: 99_720, months: 12, isWholeYear: true).monthlyKc == -8_310)
    }

    /// Only 31. 12. makes a whole year: in the rest of December the average is still of twelve months, but of a year
    /// that is not over. In January it is of the one month.
    @Test func aDayOfDecemberBeforeTheLastIsNotAWholeYear() {
        for day in ["2026-12-17", "2026-12-30"] {
            let december = NetIncome(sample(2026, asOf: day))

            #expect(december.months == 12, "\(day)")
            #expect(!december.isWholeYear, "\(day)")
        }
        #expect(NetIncome(sample(2026, asOf: "2026-01-15")).months == 1)
    }

    // MARK: The shares of the income

    /// The levies of the sample year as of 17. 10. 2026 take 11,8 % of its income: the tax 1,5 %, the social insurance
    /// 7,3 % and the health insurance 3,0 %, which leaves 88,2 %. Of the whole of 2026 as estimated they take 17,0 %,
    /// and of 2025 as of its last day 18,3 %. The parts add up to the levies' share.
    @Test func theSharesOfTheSampleYearAddUpToTheLeviesShare() throws {
        let sofar = try #require(IncomeShares(sample(2026, asOf: "2026-10-17")))
        #expect(sofar.leviesTenths == 118)
        #expect(sofar.tenths == [.tax: 15, .social: 73, .health: 30])
        #expect(sofar.netTenths == 882)

        let estimate = try #require(IncomeShares(try PredictionSample.outcome(year: 2026).result))
        #expect(estimate.netTenths == 830)
        #expect(estimate.tenths.values.reduce(0, +) == estimate.leviesTenths)

        let closed = try #require(IncomeShares(sample(2025, asOf: "2025-12-31")))
        #expect(closed.leviesTenths == 183)
        #expect(closed.netTenths == 817)
        #expect(closed.tenths.values.reduce(0, +) == closed.leviesTenths)
    }

    /// A tax bonus makes the tax's part of the income negative, and the three parts still add up to the share of the
    /// three levies together, which is rounded from the exact figure.
    @Test func aBonusHasANegativeShareAndTheSharesStillAddUp() throws {
        let result = bonusYear()
        let shares = try #require(IncomeShares(result))

        #expect(try #require(shares.tenths[.tax]) < 0)
        #expect(shares.tenths.values.reduce(0, +) == shares.leviesTenths)
        #expect(
            shares.leviesTenths == DecimalMath.halfUp(Decimal(result.liabilityTotal) * 1_000 / Decimal(result.P)))
    }

    /// With no income, or with less received back than earned, there is nothing for the levies to take a part of.
    @Test func withoutIncomeThereAreNoShares() {
        let day = civilDate("2026-10-17")
        let none = TaxEngine.compute(yearInput(2026, receipts: []), asOf: day)
        #expect(IncomeShares(none) == nil)

        let refund = Receipt(
            day: civilDate("2026-03-02"), czkNetHalere: -1_000_000, czkVatHalere: 0, source: .adjustment(1))
        let negative = TaxEngine.compute(yearInput(2026, receipts: [refund]), asOf: day)
        #expect(negative.P < 0)
        #expect(IncomeShares(negative) == nil)
    }

    // MARK: Rounding to a given sum

    /// The leftover units go to the largest remainders, the first of two equal ones first, and a negative total works
    /// the same way (−58,856 rounds to −59, so −150,096 goes to −150, not −151).
    @Test func roundedKeepingSumGivesTheLeftoverUnitsToTheLargestRemainders() {
        let equal = DecimalMath.roundedKeepingSum(
            [decimal("1.45"), decimal("1.45"), decimal("1.1")], total: decimal("4.0"))
        #expect(equal.parts == [2, 1, 1])
        #expect(equal.total == 4)

        let shares = DecimalMath.roundedKeepingSum(
            [decimal("18.7955"), decimal("75.4029"), decimal("31.6915")], total: decimal("125.8899"))
        #expect(shares.parts == [19, 75, 32])
        #expect(shares.total == 126)

        let negative = DecimalMath.roundedKeepingSum(
            [decimal("-150.096"), decimal("64.24"), decimal("27.0")], total: decimal("-58.856"))
        #expect(negative.parts == [-150, 64, 27])
        #expect(negative.total == -59)
    }
}

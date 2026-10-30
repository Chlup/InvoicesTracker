import Foundation
import Testing
@testable import InvoicesTracker

struct TaxEngineRegressionTests {
    /// A sample year: eleven payments in 2026 at 60 % flat-rate expenses, main activity all year, mortgage interest
    /// above the limit, life insurance, the taxpayer credit, insurance advances that drop from May and two income tax
    /// advances.
    static let sampleYear2026: YearInput = {
        let payments: [(day: String, net: Int64, vat: Int64)] = [
            ("2026-02-03", 22_000_000, 4_620_000),
            ("2026-03-03", 19_000_000, 3_990_000),
            ("2026-04-07", 21_000_000, 4_410_000),
            ("2026-04-10", 21_000_000, 4_410_000),
            ("2026-05-05", 21_000_000, 4_410_000),
            ("2026-07-07", 28_880_600, 0),
            ("2026-08-07", 26_880_560, 0),
            ("2026-08-26", 450_000, 94_500),
            ("2026-09-09", 27_943_300, 0),
            ("2026-10-02", 30_572_675, 0),
            ("2026-10-15", 450_000, 94_500),
        ]
        var taxAdvances = [Int64](repeating: 0, count: 12)
        taxAdvances[5] = 23_000
        taxAdvances[11] = 23_000
        return YearInput(
            year: 2026,
            receipts: payments.enumerated().map { index, entry in
                Receipt(
                    day: civilDate(entry.day),
                    czkNetHalere: entry.net,
                    czkVatHalere: entry.vat,
                    source: .invoice(Int64(index + 1))
                )
            },
            expensePercent: 60,
            months: [MonthActivity](repeating: .main, count: 12),
            healthExemptMonths: [],
            deductions: Deductions(
                mortgageInterestPaid: 219_000,
                mortgageMonths: 12,
                mortgageCap: .after2021,
                lifeInsurance: 6_480
            ),
            taxpayerCredit: true,
            advances: AdvancePlan(
                social: [Int64](repeating: 13_340, count: 4) + [Int64](repeating: 12_150, count: 8),
                health: [Int64](repeating: 6_920, count: 4) + [Int64](repeating: 5_480, count: 8),
                tax: taxAdvances
            )
        )
    }()

    /// The sample year as of 17 October 2026, counting the minimums of the months to date.
    @Test func headline2026() {
        let result = TaxEngine.compute(TaxEngineRegressionTests.sampleYear2026, asOf: civilDate("2026-10-17"))

        #expect(result.incomeHalere == 219_177_135)
        #expect(result.P == 2_191_771)
        #expect(result.V == 1_200_000)
        #expect(result.DZ == 991_771)
        #expect(result.deductionsTotal == 156_480)
        #expect(result.B == 835_200)
        #expect(result.taxBeforeCredit == 125_280)
        #expect(result.tax == 94_440)
        #expect(result.social.base == 545_475)
        #expect(result.social.insurance == 159_279)
        #expect(result.health.baseHalere == 49_588_550)
        #expect(result.health.insurance == 66_945)
        #expect(result.liabilityTotal == 320_664)

        #expect(result.balance(.tax).advancesPaid == 23_000)
        #expect(result.balance(.social).advancesPaid == 126_260)
        #expect(result.balance(.health).advancesPaid == 60_560)
        #expect(result.advancesPaidTotal == 209_820)
        #expect(result.remainingTotal == 110_844)
        #expect(result.leavesViaPlannedAdvances == 53_685)
        #expect(result.settlementTotal == 57_159)

        #expect(result.marginal[.tax] == decimal("0.15"))
        #expect(result.marginal[.social] == decimal("0.1606"))
        #expect(result.marginal[.health] == decimal("0.0675"))
        #expect(result.marginalTotal == decimal("0.3781"))
    }

    /// The steps behind the flat-rate expenses and the tax, which the breakdown of the year shows.
    @Test func theResultKeepsWhatTheExpensesWouldBeWithoutTheCapAndHowTheBaseSplitsBetweenTheRates() {
        let result = TaxEngine.compute(TaxEngineRegressionTests.sampleYear2026, asOf: civilDate("2026-10-17"))

        // 60 % of 2 191 771 Kč is 1 315 062,60 Kč, rounded down to 1 315 062 Kč, which the cap of 1 200 000 Kč cut.
        #expect(result.uncappedExpenses == 1_315_062)
        #expect(result.V == 1_200_000)
        #expect(result.expensesCapped)
        // The base of 835 200 Kč is all at 15 %: the band of 23 % starts above 1 762 812 Kč.
        #expect(result.taxBaseInLowBand == 835_200)
        #expect(result.taxBaseInHighBand == 0)
    }

    @Test func aBaseAboveTheBandIsSplitAtTheThresholdAndTheTwoPartsAddUpToTheBase() {
        // 5 700 000 Kč of income: expenses of 3 420 000 Kč without the cap, a profit and a base of 4 500 000 Kč.
        let input = computationYearInput(netHalere: 570_000_000)
        let result = TaxEngine.compute(input, asOf: civilDate("2026-10-17"))

        #expect(result.uncappedExpenses == 3_420_000)
        #expect(result.taxBaseInLowBand == 1_762_812)
        #expect(result.taxBaseInHighBand == 2_737_188)
        #expect(result.taxBaseInLowBand + result.taxBaseInHighBand == result.B)
    }

    @Test func withoutIncomeAndWithALossThereAreNoExpensesAndNoBands() {
        // A payment of 1 000 Kč and an adjustment of −3 000 Kč: income of −2 000 Kč.
        let loss = computationYearInput(netHalere: 100_000, adjustmentHalere: -300_000)
        for input in [computationYearInput(), loss] {
            let result = TaxEngine.compute(input, asOf: civilDate("2026-10-17"))

            #expect(result.uncappedExpenses == 0)
            #expect(result.V == 0)
            #expect(result.taxBaseInLowBand == 0)
            #expect(result.taxBaseInHighBand == 0)
        }
    }

    @Test func theExpensesAreTheUncappedOnesUntilTheCapCutsThem() {
        for (net, uncapped, expenses) in [
            (Int64(199_999_900), Int64(1_199_999), Int64(1_199_999)),
            (200_000_000, 1_200_000, 1_200_000),
            (200_000_100, 1_200_000, 1_200_000),
            (210_000_000, 1_260_000, 1_200_000),
        ] {
            let result = TaxEngine.compute(computationYearInput(netHalere: net), asOf: civilDate("2026-10-17"))

            #expect(result.uncappedExpenses == uncapped)
            #expect(result.V == expenses)
        }
    }
}

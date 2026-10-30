import Foundation
import Testing
@testable import InvoicesTracker

struct TaxEngineAsOfTests {
    // MARK: As-of day

    /// The sample year on 1 October: the payments of 2 and 15 October do not count yet.
    @Test func sampleYearAsOfTheFirstOfOctober() {
        let result = TaxEngine.compute(TaxEngineRegressionTests.sampleYear2026, asOf: civilDate("2026-10-01"))
        #expect(result.P == 1_881_545)
        #expect(result.V == 1_128_927)
        #expect(result.DZ == 752_618)
        #expect(result.B == 596_100)
        #expect(result.taxBeforeCredit == 89_415)
        #expect(result.tax == 58_575)
        #expect(result.social.base == 413_940)
        #expect(result.social.insurance == 120_871)
        #expect(result.health.insurance == 50_802)
        #expect(result.liabilityTotal == 230_248)
    }

    @Test func receiptsAfterTheAsOfDayOrInAnotherYearAreIgnored() {
        let input = yearInput(2026, receipts: [
            payment("2026-02-01", kc: 100_000),
            payment("2026-03-31", kc: 20_000),
            payment("2026-04-01", kc: 300_000),
            payment("2025-06-15", kc: 400_000),
            payment("2027-01-01", kc: 500_000),
        ])
        let result = TaxEngine.compute(input, asOf: civilDate("2026-03-31"))
        // A payment on the as-of day itself counts.
        #expect(result.receiptCount == 2)
        #expect(result.incomeHalere == 12_000_000)
        #expect(result.P == 120_000)
    }

    @Test func incomeAdjustmentsCountAsIncomeAndAreReportedApart() {
        let invoice = Receipt(
            day: civilDate("2026-03-10"),
            czkNetHalere: 10_000_000,
            czkVatHalere: 2_100_000,
            source: .invoice(1)
        )
        let creditNote = Receipt(
            day: civilDate("2026-04-20"),
            czkNetHalere: -2_000_000,
            czkVatHalere: 0,
            source: .adjustment(1)
        )
        let result = TaxEngine.compute(yearInput(2026, receipts: [invoice, creditNote]), asOf: civilDate("2026-12-31"))
        #expect(result.incomeHalere == 8_000_000)
        #expect(result.adjustmentsHalere == -2_000_000)
        #expect(result.vatHalere == 2_100_000)
        // The count is of payments; adjustments are their own line.
        #expect(result.receiptCount == 1)
        #expect(result.P == 80_000)
    }

    // MARK: Minimum bases

    /// One payment of 100 000 Kč on 15 January: the profit is below every minimum, so the minimums of the active
    /// months decide, those of January through the as-of month: three as of 31 March, all twelve as of 31 December.
    @Test func theMinimumsCountTheActiveMonthsThroughTheAsOfMonth() {
        let input = yearInput(2026, receipts: [payment("2026-01-15", kc: 100_000)])

        let march = TaxEngine.compute(input, asOf: civilDate("2026-03-31"))
        #expect(march.lastCountedMonth == 3)
        #expect(march.social.base == 51_417)
        #expect(march.social.insurance == 15_014)
        #expect(march.health.baseHalere == 7_345_050)
        #expect(march.health.insurance == 9_916)

        let december = TaxEngine.compute(input, asOf: civilDate("2026-12-31"))
        #expect(december.lastCountedMonth == 12)
        #expect(december.social.base == 205_668)
        #expect(december.social.insurance == 60_056)
        #expect(december.health.baseHalere == 29_380_200)
        #expect(december.health.insurance == 39_664)
    }

    // MARK: Deductions

    /// ZD 40 000 (100 000 Kč at 60 %): gifts count when they are more than 2 % of it (800 Kč) or at least 1 000 Kč.
    @Test(arguments: [(801, 801), (800, 0)] as [(Int64, Int64)])
    func giftsCountWhenMoreThanTwoPercentOfTheBase(_ gifts: Int64, _ allowed: Int64) throws {
        let deductions = Deductions(gifts: gifts)
        let input = yearInput(2026, receipts: [payment("2026-02-01", kc: 100_000)], deductions: deductions)
        let result = TaxEngine.compute(input, asOf: civilDate("2026-12-31"))
        #expect(result.DZ == 40_000)
        let line = try #require(result.deductionLines.first { $0.kind == .gifts })
        #expect(line.claimed == gifts)
        #expect(line.allowed == allowed)
        #expect(result.deductionsTotal == allowed)
    }

    /// 200 000 Kč of interest against a twelfth of the yearly cap for each month of the loan: 150 000 × 7 ÷ 12 for
    /// housing acquired after 2020, 300 000 × 5 ÷ 12 for housing acquired before 2021.
    @Test(arguments: [
        (Deductions(mortgageInterestPaid: 200_000, mortgageMonths: 7, mortgageCap: .after2021), 87_500),
        (Deductions(mortgageInterestPaid: 200_000, mortgageMonths: 5, mortgageCap: .before2021), 125_000),
    ] as [(Deductions, Int64)])
    func mortgageInterestIsCappedPerMonthOfTheLoan(_ deductions: Deductions, _ allowed: Int64) throws {
        let input = yearInput(2026, receipts: [payment("2026-02-01", kc: 1_000_000)], deductions: deductions)
        let result = TaxEngine.compute(input, asOf: civilDate("2026-12-31"))
        let line = try #require(result.deductionLines.first { $0.kind == .mortgageInterest })
        #expect(line.claimed == 200_000)
        #expect(line.allowed == allowed)
        #expect(line.limit == allowed)
        #expect(result.deductionsTotal == allowed)
    }

    /// Pension savings 30 000, life insurance 10 000 and DIP 20 000: in 2023 pension savings and life insurance have a
    /// limit of 24 000 each and DIP does not exist; from 2024 one limit of 48 000 covers all of them.
    @Test(arguments: [(2023, 34_000), (2024, 48_000)] as [(Int, Int64)])
    func retirementProductsFollowTheLimitsOfTheYear(_ year: Int, _ allowed: Int64) {
        let deductions = Deductions(lifeInsurance: 10_000, pensionSavings: 30_000, dip: 20_000)
        let input = yearInput(year, receipts: [payment("\(year)-02-01", kc: 1_000_000)], deductions: deductions)
        let result = TaxEngine.compute(input, asOf: civilDate("\(year)-12-31"))
        #expect(result.deductionsTotal == allowed)
    }

    @Test func retirementLinesFollowTheLimitsOfTheYear() {
        let deductions = Deductions(lifeInsurance: 10_000, pensionSavings: 30_000, dip: 20_000)
        let separate = TaxEngine.compute(
            yearInput(2023, receipts: [payment("2023-02-01", kc: 1_000_000)], deductions: deductions),
            asOf: civilDate("2023-12-31")
        )
        #expect(separate.deductionLines.filter { $0.kind != .mortgageInterest && $0.kind != .gifts } == [
            DeductionLine(kind: .pensionSavings, claimed: 30_000, allowed: 24_000, limit: 24_000),
            DeductionLine(kind: .lifeInsurance, claimed: 10_000, allowed: 10_000, limit: 24_000),
        ])
        let combined = TaxEngine.compute(
            yearInput(2024, receipts: [payment("2024-02-01", kc: 1_000_000)], deductions: deductions),
            asOf: civilDate("2024-12-31")
        )
        #expect(combined.deductionLines.filter { $0.kind != .mortgageInterest && $0.kind != .gifts } == [
            DeductionLine(kind: .retirementProducts, claimed: 60_000, allowed: 48_000, limit: 48_000)
        ])
    }

    /// ZD 40 000 against 150 000 Kč of allowed interest: the deductions stop at the tax base.
    @Test func deductionsAreCappedAtTheTaxBase() {
        let deductions = Deductions(mortgageInterestPaid: 150_000, mortgageMonths: 12, mortgageCap: .after2021)
        let input = yearInput(2026, receipts: [payment("2026-02-01", kc: 100_000)], deductions: deductions)
        let result = TaxEngine.compute(input, asOf: civilDate("2026-12-31"))
        #expect(result.DZ == 40_000)
        #expect(result.deductionsTotal == 40_000)
        #expect(result.B == 0)
        #expect(result.tax == 0)
    }

    @Test func withoutTheTaxpayerCreditTheTaxIsTheTaxBeforeCredit() throws {
        let s2 = try #require(GoldenCases.all.first { $0.year == 2026 && $0.name == "S2" })
        var withoutCredit = input(for: s2)
        withoutCredit.taxpayerCredit = false
        let result = TaxEngine.compute(withoutCredit, asOf: civilDate("2026-12-31"))
        #expect(result.taxBeforeCredit == 125_280)
        #expect(result.creditApplied == 0)
        #expect(result.tax == result.taxBeforeCredit)
    }

    // MARK: Balances

    /// The tax is covered by the credit, so its advance is an overpayment; it does not lower what is left to pay to
    /// the insurers.
    @Test func anOverpaymentNeverOffsetsAnotherAuthority() {
        var input = yearInput(2026, receipts: [payment("2026-02-01", kc: 100_000)])
        input.advances.tax[2] = 10_000
        input.advances.social = [Int64](repeating: 5_000, count: 12)
        let result = TaxEngine.compute(input, asOf: civilDate("2026-12-31"))
        #expect(result.balance(.tax).liability == 0)
        #expect(result.balance(.tax).overpayment == 10_000)
        #expect(result.balance(.social).remaining == 56)
        #expect(result.balance(.health).remaining == 39_664)
        #expect(result.remainingTotal == 39_720)
        #expect(result.overpaymentTotal == 10_000)
        #expect(result.settlementTotal == 39_720)
    }

    // MARK: Effect of one receipt

    /// The payment of 15 October in the sample year, at its own day: what it adds to each levy.
    @Test func effectOfThePaymentOf15October() throws {
        let input = TaxEngineRegressionTests.sampleYear2026
        let receipt = try #require(input.receipts.first { $0.day == civilDate("2026-10-15") })
        let effect = TaxEngine.effect(of: receipt, in: input)
        #expect(effect.receipt == receipt)
        #expect(effect.tax == 675)
        #expect(effect.social == 723)
        #expect(effect.health == 304)
        #expect(effect.total == 1_702)
    }

    /// A receipt that is not in the input yet (a preview) has the same effect as the one that is.
    @Test func effectOfAReceiptThatIsNotInTheInput() {
        var input = TaxEngineRegressionTests.sampleYear2026
        input.receipts.removeAll { $0.day == civilDate("2026-10-15") }
        let preview = Receipt(
            day: civilDate("2026-10-15"),
            czkNetHalere: 450_000,
            czkVatHalere: 94_500,
            source: .synthetic
        )
        let effect = TaxEngine.effect(of: preview, in: input)
        #expect(effect.tax == 675)
        #expect(effect.social == 723)
        #expect(effect.health == 304)
        #expect(effect.total == 1_702)
    }

    /// A payment edited from 100 000 Kč to 300 000 Kč replaces the stored payment of the same invoice (or adjustment)
    /// instead of counting on top of it. Without it nothing is left, so the minimums of January and February decide:
    /// social 10 010 and health 6 611. With 300 000 Kč the profit of 120 000 gives social 19 272 and health 8 100,
    /// and the credit still covers the tax.
    @Test(arguments: [ReceiptSource.invoice(1), ReceiptSource.adjustment(1)])
    func anEditedReceiptReplacesTheStoredOne(_ source: ReceiptSource) {
        let stored = Receipt(day: civilDate("2026-02-01"), czkNetHalere: 10_000_000, czkVatHalere: 0, source: source)
        let edited = Receipt(day: civilDate("2026-02-01"), czkNetHalere: 30_000_000, czkVatHalere: 0, source: source)
        let input = yearInput(2026, receipts: [stored])
        let effect = TaxEngine.effect(of: edited, in: input)
        #expect(effect.tax == 0)
        #expect(effect.social == 9_262)
        #expect(effect.health == 1_489)
        #expect(effect.total == 10_751)
    }

    @Test func aReceiptOfAnotherYearHasNoEffect() {
        let receipt = payment("2025-12-31", kc: 100_000)
        let input = TaxEngineRegressionTests.sampleYear2026
        let effect = TaxEngine.effect(of: receipt, in: input)
        #expect(effect == ReceiptEffect(receipt: receipt, tax: 0, social: 0, health: 0, total: 0))
    }
}

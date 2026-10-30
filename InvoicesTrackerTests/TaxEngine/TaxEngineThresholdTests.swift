import Foundation
import Testing
@testable import InvoicesTracker

/// Which thresholds of its year a receipt's income reaches, and how much of the income is past each: the cap of the
/// flat-rate expenses, the 23 % band and the maximum social base. They explain why the levies take a share of one
/// payment that differs so much from that of an earlier one.
struct TaxEngineThresholdTests {
    /// The payments of the prediction sample's 2026 (`PredictionSample`), at 60 % flat-rate expenses with the main
    /// activity all year, no deductions and the taxpayer credit: Sierra's five of the first half of the year,
    /// 1 040 000 Kč in all; Foxtrot's in dollars, 288 806,00 Kč on 7. 7., 268 805,60 Kč on 7. 8., 279 433,00 Kč on
    /// 9. 9. and 305 726,75 Kč on 2. 10.; and Tango's 4 500 Kč on 26. 8. and on 15. 10. The income is 1 881 544,60 Kč
    /// before 2. 10. and 2 187 271,35 Kč after it.
    static let year2026: YearInput = {
        let payments: [(day: String, net: Int64)] = [
            ("2026-02-03", 22_000_000),
            ("2026-03-03", 19_000_000),
            ("2026-04-07", 21_000_000),
            ("2026-04-10", 21_000_000),
            ("2026-05-05", 21_000_000),
            ("2026-07-07", 28_880_600),
            ("2026-08-07", 26_880_560),
            ("2026-08-26", 450_000),
            ("2026-09-09", 27_943_300),
            ("2026-10-02", 30_572_675),
            ("2026-10-15", 450_000),
        ]
        return yearInput(
            2026,
            receipts: payments.enumerated().map { index, entry in
                Receipt(
                    day: civilDate(entry.day),
                    czkNetHalere: entry.net,
                    czkVatHalere: 0,
                    source: .invoice(Int64(index + 1))
                )
            }
        )
    }()

    /// What the payment of `day` in `year2026` adds to the levies, on its day.
    static func effect(on day: String) throws -> ReceiptEffect {
        let input = year2026
        let receipt = try #require(input.receipts.first { $0.day == civilDate(day) })
        return TaxEngine.effect(of: receipt, in: input)
    }

    private let capWhole = ThresholdCrossing(threshold: .expenseCap, limit: 2_000_000, extent: .whole)
    private let bandWhole = ThresholdCrossing(threshold: .taxBand, limit: 1_762_812, extent: .whole)

    // MARK: The cap of the flat-rate expenses

    /// 7. 7. and 7. 8.: the income stays below 2 000 000 Kč, so the expenses take 60 % of each crown and the levies
    /// about 15 % of it.
    @Test func paymentsBelowTheCapReachNoThreshold() throws {
        let july = try Self.effect(on: "2026-07-07")
        #expect(july.tax == 17_325)
        #expect(july.social == 18_553)
        #expect(july.health == 7_798)
        #expect(july.total == 43_676)
        #expect(july.crossings.isEmpty)

        let august = try Self.effect(on: "2026-08-07")
        #expect(august.tax == 16_125)
        #expect(august.social == 17_268)
        #expect(august.health == 7_258)
        #expect(august.total == 40_651)
        #expect(august.crossings.isEmpty)
    }

    /// 2. 10.: the income goes from 1 881 545 Kč to 2 187 271 Kč, so the last 187 271 Kč of the payment are past the
    /// cap, where every crown is profit.
    @Test func aPaymentThatStraddlesTheCapHasPartOfItPastIt() throws {
        let effect = try Self.effect(on: "2026-10-02")

        #expect(effect.tax == 35_190)
        #expect(effect.social == 37_685)
        #expect(effect.health == 15_839)
        #expect(effect.total == 88_714)
        #expect(
            effect.crossings == [ThresholdCrossing(threshold: .expenseCap, limit: 2_000_000, extent: .part(187_271))])
    }

    /// 15. 10.: the income was past the cap before the payment, so all of the payment is, and the levies take 37,8 % of
    /// it.
    @Test func aPaymentAboveTheCapIsPastItWhole() throws {
        let effect = try Self.effect(on: "2026-10-15")

        #expect(effect.tax == 675)
        #expect(effect.social == 723)
        #expect(effect.health == 304)
        #expect(effect.total == 1_702)
        #expect(effect.crossings == [capWhole])
    }

    /// The cap is reached at an income of 2 000 000 Kč whatever the percentage: 80 % up to 1 600 000 Kč, 60 % up to
    /// 1 200 000 Kč, 40 % up to 800 000 Kč and 30 % up to 600 000 Kč.
    @Test(arguments: [80, 60, 40, 30])
    func theCapIsReachedAtTwoMillionAtEveryPercentage(_ percent: Int) {
        var input = yearInput(2026, receipts: [payment("2026-03-02", kc: 1_900_000)])
        input.expensePercent = percent

        let effect = TaxEngine.effect(of: payment("2026-04-01", kc: 200_000), in: input)

        #expect(
            effect.crossings == [ThresholdCrossing(threshold: .expenseCap, limit: 2_000_000, extent: .part(100_000))])
    }

    /// A payment that takes the income exactly to 2 000 000 Kč reaches the cap, but none of it is past it: the next
    /// crown would be the first that is all profit.
    @Test func aPaymentThatEndsAtTheCapHasNothingPastIt() {
        let input = yearInput(2026, receipts: [payment("2026-03-02", kc: 1_900_000)])

        let effect = TaxEngine.effect(of: payment("2026-04-01", kc: 100_000), in: input)

        #expect(effect.crossings.isEmpty)
    }

    /// A payment that starts there is past it whole.
    @Test func aPaymentThatStartsAtTheCapIsPastItWhole() {
        let input = yearInput(2026, receipts: [payment("2026-03-02", kc: 2_000_000)])

        let effect = TaxEngine.effect(of: payment("2026-04-01", kc: 100_000), in: input)

        #expect(effect.crossings == [capWhole])
    }

    /// A credit note of 200 000 Kč takes an income of 2 100 000 Kč back to 1 900 000 Kč: 100 000 Kč of what it takes
    /// away were past the cap.
    @Test func aReceiptThatLowersTheIncomeCountsWhatItTakesAwayPastTheCap() {
        let input = yearInput(2026, receipts: [payment("2026-03-02", kc: 2_100_000)])
        let creditNote = Receipt(
            day: civilDate("2026-04-01"), czkNetHalere: -20_000_000, czkVatHalere: 0, source: .adjustment(1))

        let effect = TaxEngine.effect(of: creditNote, in: input)

        #expect(effect.total < 0)
        #expect(
            effect.crossings == [ThresholdCrossing(threshold: .expenseCap, limit: 2_000_000, extent: .part(100_000))])
    }

    @Test func aReceiptOfAnotherYearReachesNoThreshold() {
        let effect = TaxEngine.effect(of: payment("2025-12-31", kc: 5_000_000), in: Self.year2026)

        #expect(effect.crossings.isEmpty)
    }

    // MARK: The 23 % band

    /// After 15. 10. the income is 2 191 771 Kč and the base 991 700 Kč. 800 000 Kč more on 2. 11. take the base to
    /// 1 791 700 Kč. The band starts with a base of 1 762 900 Kč, the first whole hundred above 1 762 812 Kč, at an
    /// income of 2 962 900 Kč, so the last 28 871 Kč of the payment are in it; all of the payment is past the cap.
    @Test func aPaymentThatStraddlesTheBandHasPartOfItInIt() {
        let payment = Receipt(
            day: civilDate("2026-11-02"), czkNetHalere: 80_000_000, czkVatHalere: 0, source: .invoice(12))

        let effect = TaxEngine.effect(of: payment, in: Self.year2026)

        #expect(effect.tax == 122_312)
        #expect(effect.total == 304_792)
        #expect(
            effect.crossings == [
                capWhole, ThresholdCrossing(threshold: .taxBand, limit: 1_762_812, extent: .part(28_871)),
            ])
    }

    /// 100 000 Kč more on 3. 11. are in the band whole: the levies take 23 % + 16,06 % + 6,75 % of them.
    @Test func aPaymentAboveTheBandIsInItWhole() {
        var input = Self.year2026
        input.receipts.append(
            Receipt(day: civilDate("2026-11-02"), czkNetHalere: 80_000_000, czkVatHalere: 0, source: .invoice(12)))
        let payment = Receipt(
            day: civilDate("2026-11-03"), czkNetHalere: 10_000_000, czkVatHalere: 0, source: .invoice(13))

        let effect = TaxEngine.effect(of: payment, in: input)

        #expect(effect.tax == 23_000)
        #expect(effect.social == 16_060)
        #expect(effect.health == 6_750)
        #expect(effect.crossings == [capWhole, bandWhole])
    }

    // MARK: The social maximum

    /// 5 000 000 Kč, then 1 000 000 Kč: the social base reaches its maximum of 2 350 416 Kč at a profit of
    /// 4 273 482 Kč, an income of 5 473 482 Kč, so the last 526 518 Kč of the second payment add no social insurance.
    @Test func aPaymentThatStraddlesTheSocialMaximumHasPartOfItPastIt() {
        let input = yearInput(2026, receipts: [payment("2026-03-02", kc: 5_000_000)])

        let effect = TaxEngine.effect(of: payment("2026-12-01", kc: 1_000_000), in: input)

        #expect(
            effect.crossings == [
                capWhole, bandWhole,
                ThresholdCrossing(threshold: .socialMaximum, limit: 2_350_416, extent: .part(526_518)),
            ])
    }
}

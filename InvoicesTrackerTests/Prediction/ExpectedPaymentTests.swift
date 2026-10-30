import Foundation
import Testing
@testable import InvoicesTracker

/// What the payments a prediction expects add to the levies of their year, each on its own day and on top of the money
/// received and of the payments expected before it: the sample year's four payments, which were worked out for the
/// same data by a separate implementation, two payments that are equal, and a prediction with nothing left to expect.
struct ExpectedPaymentTests {
    // MARK: Helpers

    /// The year of `outcome`'s input with `receipts` instead of its own.
    private func year(of outcome: PredictionOutcome, receipts: [Receipt]) -> YearInput {
        var input = outcome.input
        input.receipts = receipts
        return input
    }

    // MARK: The sample year

    /// The payments of the sample year as of 17. 10. 2026, in the order of the days they are paid: Foxtrot's October
    /// invoice of 256 692,80 Kč and Tango's of 4 500,00 Kč on 7. 11., then Foxtrot's November invoice of 285 692,84 Kč
    /// on 7. 12. and Tango's on 8. 12. Each adds its levies on top of the 11 payments received and of the expected
    /// ones before it, so the first adds 97 057 Kč and the second, of 4 500,00 Kč, only 1 702 Kč.
    @Test func thePaymentsOfTheSampleYearAddWhatWasWorkedOutSeparately() throws {
        let payments = try PredictionSample.outcome(year: 2026).expectedPayments()

        #expect(payments.map(\.day) == ["2026-11-07", "2026-11-07", "2026-12-07", "2026-12-08"].map(civilDate))
        #expect(payments.map(\.amountHalere) == [25_669_280, 450_000, 28_569_284, 450_000])
        #expect(payments.map(\.leviesKc) == [97_057, 1_702, 108_021, 1_702])
        #expect(payments.map(\.netHalere) == [15_963_580, 279_800, 17_767_184, 279_800])
    }

    // MARK: Equal payments

    /// Two payments that are the same, 256 692,80 Kč on 7. 11. 2026, both count. The first adds what the sample's
    /// payment of that day does, and the second adds its levies on top of the first, so more than nothing: together
    /// they add what the engine finds for the money received with both and without them. An effect that takes an equal
    /// receipt out of the input first would work the second out as if the first were not there.
    @Test func twoEqualPaymentsBothCount() throws {
        var outcome = try PredictionSample.outcome(year: 2026)
        let invoice = PredictedInvoice(
            kind: .expected, issueDate: civilDate("2026-10-31"), payDay: civilDate("2026-11-07"),
            amountHalere: 25_669_280, isCounted: true)
        outcome.prediction.expectedInvoices = [invoice, invoice]
        let base = outcome.input.receipts.filter { $0.source != .synthetic }
        outcome.input.receipts = base + outcome.prediction.syntheticReceipts

        let payments = outcome.expectedPayments()

        let day = civilDate("2026-11-07")
        let both = TaxEngine.compute(year(of: outcome, receipts: outcome.input.receipts), asOf: day)
        let none = TaxEngine.compute(year(of: outcome, receipts: base), asOf: day)
        #expect(payments.map(\.day) == [day, day])
        #expect(payments.map(\.amountHalere) == [25_669_280, 25_669_280])
        #expect(payments.first?.leviesKc == 97_057)
        #expect(payments.last.map { $0.leviesKc > 0 } == true)
        #expect(payments.map(\.leviesKc).reduce(0, +) == both.liabilityTotal - none.liabilityTotal)
    }

    // MARK: A payment outside the year

    /// A payment expected on 30. 12. 2025 in the prediction of 2026, as an invoice issued in January 2026 gets from a
    /// client's stored days to pay below zero, adds no levies to 2026: the engine counts the receipts of the year only,
    /// and it takes no as-of day of another year, so it is not asked about that day. The payment stays in the result,
    /// in its place before the sample's first, and that payment is worked out as it is without the one before it.
    @Test func aPaymentExpectedInTheYearBeforeAddsNoLeviesAndStopsNothing() throws {
        var outcome = try PredictionSample.outcome(year: 2026)
        let inTheYear = try #require(outcome.prediction.expectedInvoices.first)
        let inTheYearBefore = PredictedInvoice(
            kind: .expected, issueDate: civilDate("2026-01-05"), payDay: civilDate("2025-12-30"),
            amountHalere: 10_000_000, isCounted: true)
        outcome.prediction.expectedInvoices = [inTheYearBefore, inTheYear]
        let base = outcome.input.receipts.filter { $0.source != .synthetic }
        outcome.input.receipts = base + outcome.prediction.syntheticReceipts

        let payments = outcome.expectedPayments()

        #expect(payments.map(\.day) == [civilDate("2025-12-30"), civilDate("2026-11-07")])
        #expect(payments.map(\.amountHalere) == [10_000_000, 25_669_280])
        #expect(payments.map(\.leviesKc) == [0, 97_057])
    }

    // MARK: A closed prediction

    /// On 31. 12. 2026 the year is closed: nothing is expected, so there is no payment to work out.
    @Test func aClosedPredictionExpectsNoPayments() throws {
        let outcome = try PredictionSample.outcome(year: 2026, today: civilDate("2026-12-31"))

        #expect(outcome.prediction.isClosed)
        #expect(outcome.expectedPayments() == [])
    }
}

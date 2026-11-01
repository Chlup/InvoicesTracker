import Foundation
import Testing
@testable import InvoicesTracker

/// The unpaid invoices that the average of the current year on Přehled counts as paid: the days that bound them, and
/// the receipt each of them brings the engine. The tests are about Sunday 1 November 2026.
struct DueInvoicesTests {
    // MARK: Helpers

    private let today = civilDate("2026-11-01")

    private func usd(_ rate: String) -> ExchangeRate {
        ExchangeRate(currency: .usd, amount: 1, rate: decimal(rate))
    }

    /// The row of an unpaid invoice issued on 15. 10. 2026, in crowns unless `currency` says otherwise, whose amounts
    /// are in the minor units of its currency. It has no payment unless `paidOn` says when it was paid.
    private func row(
        id: Int64 = 1, currency: CurrencyCode = .czk, net: Int64, vat: Int64 = 0, issueDayRate: ExchangeRate? = nil,
        paidOn: String? = nil, paymentNet: Int64? = nil, paymentVat: Int64? = nil
    ) -> InvoiceChartRow {
        InvoiceChartRow(
            id: id, issueDate: civilDate("2026-10-15"), isDraft: false, inReview: false, currency: currency,
            netMinor: net, vatMinor: vat, paymentDate: paidOn.map(civilDate), paymentNetHalere: paymentNet,
            paymentVatHalere: paymentVat, issueDayRate: issueDayRate
        )
    }

    // MARK: The days

    /// The invoices are due through the last day of the month of today, a leap February included, and are issued from
    /// the first day of last year, also in January. On the last day of the month that day is today.
    @Test func theInvoicesAreDueThroughTheLastDayOfTodaysMonth() {
        #expect(DueInvoices.dueThrough(today: civilDate("2026-11-01")) == civilDate("2026-11-30"))
        #expect(DueInvoices.dueThrough(today: civilDate("2028-02-10")) == civilDate("2028-02-29"))
        #expect(DueInvoices.dueThrough(today: civilDate("2026-12-31")) == civilDate("2026-12-31"))
        #expect(DueInvoices.issuedFrom(today: civilDate("2026-11-01")) == civilDate("2025-01-01"))
        #expect(DueInvoices.issuedFrom(today: civilDate("2027-01-01")) == civilDate("2026-01-01"))
    }

    // MARK: The receipts

    @Test func aDueInvoiceInCrownsIsAReceiptOfItsAmountWithoutVATOnTheDay() {
        let receipts = DueInvoices.receipts(of: [row(net: 1_000_000, vat: 210_000)], on: today)

        #expect(receipts == [Receipt(day: today, czkNetHalere: 1_000_000, czkVatHalere: 210_000, source: .synthetic)])
    }

    /// An invoice in dollars is worth what the charts count for it, its amounts at the rate of its day of issue, each
    /// rounded once: 12 040,00 dollars and 2 528,40 dollars at 21,622 Kč.
    @Test func aForeignInvoiceCountsAtItsIssueDayRate() {
        let rate = usd("21.622")
        let invoice = row(currency: .usd, net: 1_204_000, vat: 252_840, issueDayRate: rate)

        let receipts = DueInvoices.receipts(of: [invoice], on: today)

        let net = rate.czkHalere(fromMinor: 1_204_000)
        let vat = rate.czkHalere(fromMinor: 252_840)
        #expect(receipts == [Receipt(day: today, czkNetHalere: net, czkVatHalere: vat, source: .synthetic)])
        #expect(net == 26_032_888)
        #expect(vat == 5_466_906)
        let value = OverviewBuilder.issuedValue(of: invoice, receivedThrough: today)
        #expect(receipts.map(\.czkNetHalere) == [value.net])
        #expect(receipts.map { $0.czkNetHalere + $0.czkVatHalere } == [value.gross])
    }

    /// An invoice that is worth nothing brings no receipt, so the average has nothing to say about it: one in dollars
    /// that has no rate, and one of 0 Kč.
    @Test func anInvoiceWorthNothingBringsNoReceipt() {
        let withoutRate = row(currency: .usd, net: 1_204_000, vat: 252_840, issueDayRate: nil)
        let nothing = row(net: 0)

        #expect(DueInvoices.receipts(of: [withoutRate, nothing], on: today) == [])
    }

    /// Two invoices of the same amount are two receipts, though the receipts made up for them are equal.
    @Test func twoInvoicesOfTheSameAmountAreTwoReceipts() {
        let rows = [row(id: 1, net: 100_000, vat: 21_000), row(id: 2, net: 100_000, vat: 21_000)]

        let receipts = DueInvoices.receipts(of: rows, on: today)

        let receipt = Receipt(day: today, czkNetHalere: 100_000, czkVatHalere: 21_000, source: .synthetic)
        #expect(receipts == [receipt, receipt])
    }

    /// The receipts follow the rows, and an invoice worth nothing between two others leaves them next to each other.
    @Test func theReceiptsFollowTheOrderOfTheRows() {
        let rows = [
            row(id: 1, net: 300_000),
            row(id: 2, currency: .usd, net: 100_000, issueDayRate: nil),
            row(id: 3, currency: .usd, net: 100_000, issueDayRate: usd("20")),
            row(id: 4, net: 100_000),
        ]

        #expect(DueInvoices.receipts(of: rows, on: today).map(\.czkNetHalere) == [300_000, 2_000_000, 100_000])
    }

    /// A payment dated after the day has not come by it, so it changes nothing about what the invoice is worth: an
    /// invoice in dollars is worth its amount at the rate of its day of issue and not what that payment says.
    @Test func aPaymentAfterTheDayDoesNotChangeWhatTheInvoiceIsWorth() {
        let dollars = row(
            currency: .usd, net: 100_000, issueDayRate: usd("21"), paidOn: "2026-11-25", paymentNet: 123,
            paymentVat: 0)
        let crowns = row(net: 400_000, vat: 84_000, paidOn: "2026-11-25", paymentNet: 111, paymentVat: 0)

        let receipts = DueInvoices.receipts(of: [dollars, crowns], on: today)

        #expect(
            receipts == [
                Receipt(day: today, czkNetHalere: 2_100_000, czkVatHalere: 0, source: .synthetic),
                Receipt(day: today, czkNetHalere: 400_000, czkVatHalere: 84_000, source: .synthetic),
            ])
    }
}

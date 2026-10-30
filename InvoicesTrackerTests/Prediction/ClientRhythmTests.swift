import Foundation
import Testing
@testable import InvoicesTracker

/// How a client invoices and pays, read from its issued invoices: the usual delay of a payment, the usual interval
/// between invoices and whether it is regular, and the step in months. Each rule uses independent small fixtures.
struct ClientRhythmTests {
    // MARK: Helpers

    /// An issued invoice of 1 000,00 Kč, unless `net` and `currency` say otherwise, issued on `issued` and paid on
    /// `paid` (`YYYY-MM-DD`), if given.
    private func invoice(
        _ issued: String, paid: String? = nil, net: Int64 = 100_000, currency: CurrencyCode = .czk
    ) -> Invoice {
        Invoice.fixture(
            number: "R\(issued)", currency: currency, issued: issued, duzp: issued, dueDate: issued,
            items: [.fixture("1", at: net)], payment: paid.map { Payment.fixture(on: $0, net: net, vat: 0) })
    }

    /// The rhythm of a client due in `dueDays`, with `issued` invoices, as of `now`.
    private func rhythm(
        _ issued: [Invoice], now: String = "2026-10-17", dueDays: Int? = 30
    ) -> ClientRhythm {
        ClientRhythm(issued: issued, now: civilDate(now), dueDays: dueDays)
    }

    // MARK: The delay of a payment

    /// The delays are 10, 3, 20 and 7 days: in order 3, 7, 10, 20, whose lower median is 7, not the 10 of the upper
    /// median and of the mean.
    @Test func theDelayIsTheLowerMedianOfIssueToPayment() {
        let issued = [
            invoice("2026-01-31", paid: "2026-02-10"),
            invoice("2026-02-28", paid: "2026-03-03"),
            invoice("2026-03-31", paid: "2026-04-20"),
            invoice("2026-04-30", paid: "2026-05-07"),
        ]

        #expect(rhythm(issued).delayDays == 7)
    }

    /// Two of three invoices were paid before they were issued, 10 and 3 days before: each counts as 0 days, so the
    /// median of 0, 0 and 8 is 0. Taken as they are it would be −3, and left out 8.
    @Test func aPaymentBeforeItsIssueCountsAsNoDelay() {
        let issued = [
            invoice("2026-04-30", paid: "2026-04-20"),
            invoice("2026-05-29", paid: "2026-05-26"),
            invoice("2026-06-30", paid: "2026-07-08"),
        ]

        #expect(rhythm(issued).delayDays == 0)
    }

    /// Without a payment by "now" the client is expected to pay in its due days, and a client the app does not know
    /// (with no due days) in 14. A payment dated after "now" is still to come, so it does not count yet.
    @Test func aClientWithoutPaymentsWaitsItsDueDaysOrFourteen() {
        let unpaid = [invoice("2026-09-30")]
        let paidLater = [invoice("2026-09-30", paid: "2026-10-30")]

        #expect(rhythm(unpaid, dueDays: 30).delayDays == 30)
        #expect(rhythm(unpaid, dueDays: nil).delayDays == 14)
        #expect(rhythm([], dueDays: 7).delayDays == 7)
        #expect(rhythm(paidLater, dueDays: 21).delayDays == 21)
        #expect(rhythm(paidLater, now: "2026-10-30", dueDays: 21).delayDays == 30)
    }

    // MARK: The interval and the regular client

    /// Two invoices a month apart, the last one recent, make a regular client. One invoice does not, nor do invoices
    /// only 19 days apart. The interval is the lower median of the last four gaps: 40, 60, 40 and 60 days give 40. The
    /// older gap of 100 days does not count (with it the lower median would be 60), and the upper median would be 60.
    @Test func aClientIsRegularAfterTwoInvoicesOfAMonthOrMore() {
        let two = rhythm([invoice("2026-08-31"), invoice("2026-09-30")])
        let one = rhythm([invoice("2026-09-30")])
        let tooOften = rhythm([invoice("2026-09-11"), invoice("2026-09-30")])
        let six = rhythm([
            invoice("2025-12-01"), invoice("2026-03-11"), invoice("2026-04-20"), invoice("2026-06-19"),
            invoice("2026-07-29"), invoice("2026-09-27"),
        ])

        #expect(two.intervalDays == 30)
        #expect(two.isRegular)
        #expect(one.intervalDays == 0)
        #expect(!one.isRegular)
        #expect(tooOften.intervalDays == 19)
        #expect(!tooOften.isRegular)
        #expect(six.intervalDays == 40)
        #expect(six.isRegular)
    }

    /// With invoices 30 days apart the last one may be up to 45 days old (1,5 × 30): on 14. 11. 2026, 45 days after
    /// 30. 9., the client is still regular, and a day later it is not.
    @Test func aClientWhoseLastInvoiceIsTooOldIsNotRegular() {
        let issued = [invoice("2026-08-31"), invoice("2026-09-30")]

        #expect(rhythm(issued, now: "2026-11-14").isRegular)
        #expect(!rhythm(issued, now: "2026-11-15").isRegular)
    }

    /// The step is the interval in months of 30,4 days, rounded, and at least 1: 31 days are a month, 91 days three.
    /// The app expects a regular client's invoices from the month of the last one on, one step at a time, in the year:
    /// from September monthly in October, November and December, and from July quarterly in October.
    @Test func theStepIsTheIntervalInMonths() {
        let monthly = rhythm([invoice("2026-08-30"), invoice("2026-09-30")])
        let quarterly = rhythm([invoice("2026-05-01"), invoice("2026-07-31")])
        let weekly = rhythm([invoice("2026-10-01"), invoice("2026-10-08")])

        #expect(monthly.intervalDays == 31)
        #expect(monthly.step == 1)
        #expect(monthly.automaticMonths(in: 2026, draftMonths: []) == [10, 11, 12])
        #expect(quarterly.intervalDays == 91)
        #expect(quarterly.step == 3)
        #expect(quarterly.automaticMonths(in: 2026, draftMonths: []) == [10])
        #expect(quarterly.automaticMonths(in: 2027, draftMonths: []) == [1, 4, 7, 10])
        // A client that is not regular has no month of its rhythm, only those of its drafts.
        #expect(weekly.step == 1)
        #expect(!weekly.isRegular)
        #expect(weekly.automaticMonths(in: 2026, draftMonths: [11]) == [11])
    }

}

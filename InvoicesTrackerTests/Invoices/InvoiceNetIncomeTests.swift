import Foundation
import Testing
@testable import InvoicesTracker

/// What each invoice leaves after the levies its payment adds, or would add (`InvoiceNetIncome`): the income of the
/// payment, or of the amount expected for an invoice that is not paid, less what the engine says that income adds to
/// the levies of its year on its day. Each invoice is worked out on its own, as if it were the last receipt of its day.
/// The data is the prediction sample as of 17. 10. 2026, and the figures are those that a separate implementation
/// worked out for it.
struct InvoiceNetIncomeTests {
    // MARK: Helpers

    /// The invoice of the sample with the id `id`, 1 to 39: 1 to 11 are the payments of 2026, 12 is the draft.
    private func sample(_ id: Int64) -> Invoice {
        PredictionSample.invoices[Int(id) - 1]
    }

    /// The nets of `invoices` as of `asOf` (`YYYY-MM-DD`), with the rates given, in the year 2026 of the sample alone.
    private func workedOut(
        _ invoices: [Invoice], asOf: String = "2026-10-17", rates: [Int64: ExchangeRate] = [:]
    ) -> [Int64: InvoiceNetIncome] {
        InvoiceNetIncome.make(
            for: invoices, asOf: civilDate(asOf), rates: rates, years: [2026: PredictionSample.yearInput(year: 2026)])
    }

    // MARK: The payments

    @Test func thePaymentsOfTheSampleYearLeaveTheNetsWorkedOutSeparately() {
        let paid = PredictionSample.invoices.filter { $0.payment?.date.year == 2026 }
        let nets = InvoiceNetIncome.make(
            for: paid, asOf: civilDate("2026-10-17"), rates: [:], years: [2026: PredictionSample.yearInput(year: 2026)])

        #expect(paid.count == 11)
        #expect(
            paid.map { nets[$0.id]?.effect.total } == [
                -33_401, 12_479, 17_008, 19_161, 19_160, 26_921, 40_651, 681, 42_265, 88_714, 1_702,
            ])
        #expect(
            paid.map { nets[$0.id]?.netHalere } == [
                25_340_100, 17_752_100, 19_299_200, 19_083_900, 19_084_000, 26_188_500, 22_815_460, 381_900,
                23_716_800, 21_701_275, 279_800,
            ])
        #expect(paid.compactMap { nets[$0.id]?.netHalere }.reduce(0, +) == 195_643_035)
        let first = nets[1]?.effect
        #expect([first?.tax, first?.social, first?.health] == [-37_524, 4_123, 0])
        #expect(paid.allSatisfy { nets[$0.id]?.isEstimate == false && nets[$0.id]?.isProvisional == false })
    }

    @Test func aPaidInvoiceGetsTheReceiptOfItsPayment() throws {
        let invoice = sample(6)
        let payment = try #require(invoice.payment)

        let net = try #require(workedOut([invoice])[invoice.id])

        #expect(net.day == civilDate("2026-07-07"))
        #expect(net.incomeHalere == 28_880_600)
        #expect(
            net.effect.receipt
                == Receipt(
                    day: payment.date, czkNetHalere: payment.czkNetHalere, czkVatHalere: payment.czkVatHalere,
                    source: .invoice(invoice.id)))
    }

    @Test func theNetOfAnEffectIsItsIncomeLessItsLeviesInHalere() {
        func receipt(_ day: String, halere: Int64, of id: Int64) -> Receipt {
            Receipt(day: civilDate(day), czkNetHalere: halere, czkVatHalere: 0, source: .invoice(id))
        }
        let income = receipt("2026-02-03", halere: 22_000_000, of: 1)
        let small = receipt("2026-10-15", halere: 450_000, of: 11)
        let tiny = receipt("2026-01-05", halere: 100_000, of: 2)

        // A tax bonus makes the levies negative, and the net more than the income.
        let withBonus = ReceiptEffect(receipt: income, tax: -37_524, social: 4_123, health: 0, total: -33_401)
        #expect(withBonus.netHalere == 25_340_100)
        let levied = ReceiptEffect(receipt: small, tax: 675, social: 1_027, health: 0, total: 1_702)
        #expect(levied.netHalere == 279_800)
        // The insurance has a minimum, so the levies can be more than the income.
        let minimum = ReceiptEffect(receipt: tiny, tax: 0, social: 1_500, health: 500, total: 2_000)
        #expect(minimum.netHalere == -100_000)
    }

    @Test func aPaymentWaitingForItsRateIsProvisional() throws {
        var waiting = sample(10)
        waiting.payment?.provisional = true

        let net = try #require(workedOut([waiting])[waiting.id])

        #expect(net.isProvisional)
        #expect(!net.isEstimate)
        #expect(net.netHalere == 21_701_275)
    }

    @Test func aPaymentDatedAfterTheDayShownStillHasItsNet() throws {
        let invoice = sample(1)
        #expect(invoice.payment?.date == civilDate("2026-02-03"))

        let net = try #require(workedOut([invoice], asOf: "2026-02-01")[invoice.id])

        #expect(net.netHalere == 25_340_100)
        #expect(net.day == civilDate("2026-02-03"))
        #expect(!net.isEstimate)
    }

    // MARK: The invoices that are not paid

    @Test func theDraftIsEstimatedAsPaidOnItsDueDateAtTheRateGiven() throws {
        let draft = sample(12)
        #expect(draft.dueDate == civilDate("2026-11-30"))
        let nets = InvoiceNetIncome.make(
            for: [draft], asOf: civilDate("2026-10-17"), rates: [draft.id: PredictionSample.usdRate],
            years: [2026: PredictionSample.yearInput(year: 2026)])

        let net = try #require(nets[draft.id])

        #expect(net.isEstimate)
        #expect(!net.isProvisional)
        #expect(net.day == civilDate("2026-11-30"))
        #expect(net.incomeHalere == 25_669_280)
        #expect(net.effect.total == 97_057)
        #expect(net.netHalere == 15_963_580)
    }

    @Test func aDayShownAfterTheDueDateIsTheDayTheMoneyIsExpected() throws {
        let draft = sample(12)
        let shown = civilDate("2026-12-05")

        #expect(InvoiceNetIncome.expectedDay(of: draft, asOf: civilDate("2026-10-17")) == civilDate("2026-11-30"))
        #expect(InvoiceNetIncome.expectedDay(of: draft, asOf: civilDate("2026-11-30")) == civilDate("2026-11-30"))
        #expect(InvoiceNetIncome.expectedDay(of: draft, asOf: shown) == shown)
        let net = try #require(
            workedOut([draft], asOf: "2026-12-05", rates: [draft.id: PredictionSample.usdRate])[draft.id])
        #expect(net.day == shown)
        #expect(net.incomeHalere == 25_669_280)
    }

    @Test func anUnpaidInvoiceInCrownsIsWorthItsNetWhateverRateIsGiven() throws {
        let invoice = Invoice.fixture(dueDate: "2026-11-15")
        let expected = Receipt(
            day: civilDate("2026-11-15"), czkNetHalere: 450_000, czkVatHalere: 94_500, source: .invoice(invoice.id))

        let withoutRate = try #require(workedOut([invoice])[invoice.id])
        let withRate = try #require(
            workedOut([invoice], rates: [invoice.id: PredictionSample.usdRate])[invoice.id])

        #expect(withoutRate.isEstimate)
        #expect(withoutRate.effect.receipt == expected)
        #expect(withRate.effect.receipt == expected)
    }

    @Test func anInvoiceInReviewAndAForeignInvoiceWithoutARateHaveNone() {
        var reviewed = sample(11)
        reviewed.review = ReviewFlag(reason: "chybí kurz faktury")
        var draftInReview = sample(12)
        draftInReview.review = ReviewFlag(reason: "chybí kurz faktury")
        let draft = sample(12)

        let inReview = workedOut([reviewed, draftInReview], rates: [draft.id: PredictionSample.usdRate])
        let withoutRate = workedOut([draft], rates: [:])

        #expect(inReview[reviewed.id] == nil)
        #expect(inReview[draftInReview.id] == nil)
        #expect(inReview.isEmpty)
        #expect(withoutRate[draft.id] == nil)
        #expect(withoutRate.isEmpty)
    }

    // MARK: The year

    @Test func anInvoiceWhoseYearIsNotGivenHasNone() {
        let draft = sample(12)
        let rates = [draft.id: PredictionSample.usdRate]

        let none = InvoiceNetIncome.make(
            for: PredictionSample.invoices, asOf: PredictionSample.sampleToday, rates: rates, years: [:])
        let only2026 = workedOut(PredictionSample.invoices, rates: rates)

        #expect(none.isEmpty)
        #expect(only2026.keys.sorted() == (1...12).map { Int64($0) })
    }

    @Test func theYearOfTheLeviesIsTheYearOfThePaymentOrOfTheDayTheMoneyIsExpected() {
        let december = sample(24)
        #expect(december.issueDate == civilDate("2024-12-31"))
        #expect(december.payment?.date == civilDate("2025-01-05"))
        let draft = sample(12)
        var paidDraft = draft
        paidDraft.payment = sample(11).payment
        var reviewedAndPaid = sample(11)
        reviewedAndPaid.review = ReviewFlag(reason: "záporná částka")
        var reviewedAndUnpaid = draft
        reviewedAndUnpaid.review = ReviewFlag(reason: "záporná částka")
        let today = civilDate("2026-10-17")

        // A payment is income of the year the money came in, whatever the year of the invoice or the day shown.
        #expect(InvoiceNetIncome.yearOfLevies(of: december, asOf: civilDate("2024-12-31")) == 2025)
        #expect(InvoiceNetIncome.yearOfLevies(of: sample(1), asOf: civilDate("2026-01-01")) == 2026)
        // An invoice that is not paid is expected on the later of its due date and the day shown.
        #expect(InvoiceNetIncome.yearOfLevies(of: draft, asOf: today) == 2026)
        #expect(InvoiceNetIncome.yearOfLevies(of: draft, asOf: civilDate("2027-01-05")) == 2027)
        // What does not count as income has none: a draft that is paid, and an invoice in review, paid or not.
        #expect(InvoiceNetIncome.yearOfLevies(of: paidDraft, asOf: today) == nil)
        #expect(InvoiceNetIncome.yearOfLevies(of: reviewedAndPaid, asOf: today) == nil)
        #expect(InvoiceNetIncome.yearOfLevies(of: reviewedAndUnpaid, asOf: today) == nil)
    }

    @Test func onlyAnUnpaidInvoiceInAForeignCurrencyThatIsNotInReviewNeedsARate() {
        var reviewed = sample(12)
        reviewed.review = ReviewFlag(reason: "chybí kurz faktury")

        #expect(InvoiceNetIncome.needsRate(sample(12)))
        #expect(!InvoiceNetIncome.needsRate(sample(6)))
        #expect(!InvoiceNetIncome.needsRate(reviewed))
        #expect(!InvoiceNetIncome.needsRate(Invoice.fixture()))
    }
}

import Foundation
import Testing
@testable import InvoicesTracker

/// The annual sample keeps every eligible real invoice and averages its original net amount after daily conversion.
struct PredictionAverageTests {
    /// An issued invoice with an original net amount, independently of the stored payment conversion and DUZP.
    private func invoice(
        _ issued: String, net: Int64, currency: CurrencyCode = .czk, paid: String? = nil
    ) -> Invoice {
        Invoice.fixture(
            currency: currency, issued: issued, duzp: "2024-01-01", dueDate: issued,
            items: [InvoiceItem.fixture("1", at: net)], vatMode: .none,
            payment: paid.map { Payment.fixture(on: $0, conversion: .bankCZK, net: 99, vat: 0) })
    }

    /// The selected year's training sample as of the real day, with a fourteen-day expected payment delay.
    private func samples(
        _ invoices: [Invoice], year: Int = 2026, now: String = "2026-10-17", delayDays: Int = 14
    ) -> [PredictionAverageSample] {
        PredictionAverage.samples(issued: invoices, year: year, now: civilDate(now), delayDays: delayDays)
    }

    /// Every invoice counts, including the oldest across a long gap and invoices sharing the fixture's unsaved id.
    @Test func fiveCZKInvoicesTrainTheAnnualMean() {
        let issued = [
            invoice("2026-01-01", net: 28_900_000, paid: "2026-01-15"),
            invoice("2026-02-01", net: 26_900_000, paid: "2026-02-15"),
            invoice("2026-07-01", net: 27_900_000, paid: "2026-07-15"),
            invoice("2026-08-01", net: 30_600_000, paid: "2026-08-15"),
            invoice("2026-09-01", net: 25_700_000),
        ]
        let selected = samples(issued)
        let average = PredictionAverage.make(samples: selected, rates: [:])

        #expect(selected.count == 5)
        #expect(selected.allSatisfy { $0.rateKey == nil })
        #expect(average.sampleCount == 5)
        #expect(average.amountHalere == 28_000_000)
        #expect(average.missingRateKeys.isEmpty)
    }

    /// USD 100 at 20 Kč and EUR 100 at 25 Kč contribute 2 000 Kč and 2 500 Kč before averaging.
    @Test func mixedCurrenciesAreConvertedBeforeAveraging() {
        let selected = samples([
            invoice("2026-01-01", net: 10_000, currency: .usd, paid: "2026-01-15"),
            invoice("2026-09-01", net: 10_000, currency: .eur),
        ])
        let average = PredictionAverage.make(
            samples: selected,
            rates: [
                PredictionRateKey(currency: .usd, day: civilDate("2026-01-15")):
                    storedRate("USD", "20", declaredOn: "2026-01-14"),
                PredictionRateKey(currency: .eur, day: civilDate("2026-09-01")):
                    storedRate("EUR", "25", declaredOn: "2026-09-01"),
            ])

        #expect(average.sampleCount == 2)
        #expect(average.amountHalere == 225_000)
        #expect(average.missingRateKeys.isEmpty)
    }

    /// The payment year selects even a much older invoice, and its payment day selects the daily rate.
    @Test func aPriorDecemberPaymentUsesItsJanuaryPaymentYearAndFXDate() {
        let selected = samples([
            invoice("2025-12-20", net: 10_000, currency: .usd, paid: "2026-01-10"),
            invoice("2024-12-20", net: 20_000, currency: .eur, paid: "2026-01-11"),
            invoice("2026-02-01", net: 30_000, paid: "2025-12-31"),
        ])

        #expect(selected == [
            PredictionAverageSample(netMinor: 10_000, currency: .usd, rateDay: civilDate("2026-01-10")),
            PredictionAverageSample(netMinor: 20_000, currency: .eur, rateDay: civilDate("2026-01-11")),
        ])
    }

    /// A waiting December invoice paid after year end is excluded, while a paid invoice still trains the year.
    @Test func nextYearReceiptsAreExcluded() {
        let selected = samples([
            invoice("2026-11-01", net: 10_000, paid: "2026-11-15"),
            invoice("2026-12-20", net: 20_000),
        ], now: "2026-12-20")

        #expect(selected == [
            PredictionAverageSample(netMinor: 10_000, currency: .czk, rateDay: civilDate("2026-11-15"))
        ])
    }

    /// An imported future payment remains waiting and uses issue-day FX, even when the recorded payment is next year.
    @Test func aFuturePaymentRemainsPending() {
        var future = invoice("2026-09-30", net: 10_000, currency: .usd, paid: "2027-01-10")
        future.source = .imported(fakturoidID: "future", fingerprint: "test", changedInApp: false)
        let selected = samples([future])

        #expect(selected == [
            PredictionAverageSample(netMinor: 10_000, currency: .usd, rateDay: civilDate("2026-09-30"))
        ])
    }

    /// Waiting invoices keep the previous/current issue-year window and overdue amounts move to tomorrow.
    @Test func unpaidEligibilityKeepsTheExistingIssueYearAndPaymentRules() {
        let issued = [
            invoice("2024-12-31", net: 10_000),
            invoice("2025-01-01", net: 20_000),
            invoice("2026-09-30", net: 30_000),
            invoice("2027-01-01", net: 40_000),
        ]
        let selected = samples(issued)

        #expect(selected == [
            PredictionAverageSample(netMinor: 20_000, currency: .czk, rateDay: civilDate("2025-01-01")),
            PredictionAverageSample(netMinor: 30_000, currency: .czk, rateDay: civilDate("2026-09-30")),
        ])
        #expect(samples(issued, now: "2026-12-31").isEmpty)
    }

    /// Future issue dates retain their original lookup key so the loader can apply its current-day cap.
    @Test func aFutureIssueKeepsItsOriginalRateDayForTheLoader() {
        let selected = samples([invoice("2026-11-01", net: 10_000, currency: .usd)])

        #expect(selected == [
            PredictionAverageSample(netMinor: 10_000, currency: .usd, rateDay: civilDate("2026-11-01"))
        ])
    }

    /// Drafts and review flags never contribute, even when they have payments. Generated receipts are not invoices.
    @Test func onlyRealIssuedInvoicesWithoutReviewTrainTheMean() {
        let real = invoice("2026-09-01", net: 10_000)
        var draft = invoice("2026-09-02", net: 20_000, paid: "2026-09-03")
        draft.status = .draft
        var review = invoice("2026-09-04", net: 30_000, paid: "2026-09-05")
        review.review = ReviewFlag(reason: "Needs review")

        #expect(samples([real, draft, review]) == [
            PredictionAverageSample(netMinor: 10_000, currency: .czk, rateDay: civilDate("2026-09-01"))
        ])
    }

    /// A missing rate makes the whole mean unavailable while preserving both invoices and the precise lookup key.
    @Test func missingConversionPreservesTheDenominator() {
        let selected = samples([
            invoice("2026-09-01", net: 10_000, currency: .usd),
            invoice("2026-09-02", net: 10_000, currency: .eur),
        ])
        let average = PredictionAverage.make(
            samples: selected,
            rates: [PredictionRateKey(currency: .usd, day: civilDate("2026-09-01")):
                storedRate("USD", "20", declaredOn: "2026-09-01")])

        #expect(average.sampleCount == 2)
        #expect(average.amountHalere == nil)
        #expect(average.missingRateKeys == [PredictionRateKey(currency: .eur, day: civilDate("2026-09-02"))])
    }

    /// No qualifying history is unavailable, whereas an actual zero-value invoice has a known zero mean.
    @Test func zeroIsKnownButAnEmptySampleIsUnavailable() {
        let empty = PredictionAverage.make(samples: [], rates: [:])
        let zero = PredictionAverage.make(samples: samples([invoice("2026-09-01", net: 0)]), rates: [:])

        #expect(empty.sampleCount == 0)
        #expect(empty.amountHalere == nil)
        #expect(empty.missingRateKeys.isEmpty)
        #expect(zero.sampleCount == 1)
        #expect(zero.amountHalere == 0)
        #expect(zero.missingRateKeys.isEmpty)
    }

    /// A per-100 rate converts 1 minor unit to 0,5 haléře, rounded to 1 before averaging with 2 to give 2.
    @Test func quotedUnitsAndHalfHalereMeansRoundCorrectly() {
        let day = civilDate("2026-09-01")
        let average = PredictionAverage.make(
            samples: [
                PredictionAverageSample(netMinor: 1, currency: .usd, rateDay: day),
                PredictionAverageSample(netMinor: 2, currency: .czk, rateDay: day),
            ],
            rates: [PredictionRateKey(currency: .usd, day: day):
                storedRate("USD", "50", declaredOn: "2026-09-01", amount: 100)])

        #expect(average.sampleCount == 2)
        #expect(average.amountHalere == 2)
        #expect(average.missingRateKeys.isEmpty)
    }
}

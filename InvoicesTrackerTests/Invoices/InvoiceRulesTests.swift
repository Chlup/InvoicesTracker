import Foundation
import Testing
@testable import InvoicesTracker

/// In every expected string `\u{00A0}` is the no-break space.
struct InvoiceRulesTests {
    // MARK: Helpers

    private func payment(on day: String) -> Payment {
        Payment(date: civilDate(day), conversion: .czk, czkNetHalere: 450_000, czkVatHalere: 94_500)
    }

    /// A CZK invoice due on 30 October 2026.
    private func invoice(
        status: InvoiceStatus = .issued, paidOn day: String? = nil, review: ReviewFlag? = nil
    ) -> Invoice {
        Invoice.fixture(dueDate: "2026-10-30", status: status, review: review, payment: day.map(payment))
    }

    private func status(of invoice: Invoice, asOf day: String) -> InvoiceDisplayStatus {
        invoice.displayStatus(asOf: civilDate(day))
    }

    // MARK: Numbering

    @Test func theDigitsOfANumberAreWhatItIsUniqueBy() {
        #expect(InvoiceNumbering.digits(of: "2026-05-01") == "20260501")
        #expect(InvoiceNumbering.digits(of: "20260501") == "20260501")
        #expect(InvoiceNumbering.digits(of: "Z20261001") == "20261001")
        #expect(InvoiceNumbering.digits(of: "FA 2026/09 - 04") == "20260904")
        #expect(InvoiceNumbering.digits(of: "") == "")
        #expect(InvoiceNumbering.digits(of: "bez čísla") == "")
    }

    @Test func onlyAsciiDigitsAreDigits() {
        // Digits of other scripts and fractions are not digits of the number, and a mark after a digit goes.
        #expect(InvoiceNumbering.digits(of: "٢٠٢٦") == "")
        #expect(InvoiceNumbering.digits(of: "２０２６") == "")
        #expect(InvoiceNumbering.digits(of: "½") == "")
        #expect(InvoiceNumbering.digits(of: "1\u{0301}2") == "12")
    }

    @Test func theVariableSymbolIsTheDigitsOfTheNumber() {
        #expect(InvoiceNumbering.variableSymbol(of: "2026-05-01") == "20260501")
        #expect(InvoiceNumbering.variableSymbol(of: "20260901") == "20260901")
        #expect(InvoiceNumbering.variableSymbol(of: "Z20261001") == "20261001")
    }

    @Test func theNextNumberIsOneAboveTheHighestOfTheMonth() {
        let existing = ["20260901", "2026-09-02", "20260801"]

        #expect(InvoiceNumbering.next(forDUZP: civilDate("2026-09-30"), existingNumbers: existing) == "20260903")
    }

    @Test func aMonthWithoutNumbersStartsAtOne() {
        let september = ["20260901"]

        #expect(InvoiceNumbering.next(forDUZP: civilDate("2026-10-31"), existingNumbers: september) == "20261001")
        #expect(InvoiceNumbering.next(forDUZP: civilDate("2026-10-31"), existingNumbers: []) == "20261001")
    }

    @Test func aGapIsNotFilledAndTheOrderOfTheNumbersDoesNotMatter() {
        let day = civilDate("2026-09-15")

        #expect(InvoiceNumbering.next(forDUZP: day, existingNumbers: ["20260905", "20260901"]) == "20260906")
        #expect(InvoiceNumbering.next(forDUZP: day, existingNumbers: ["20260901", "20260905"]) == "20260906")
    }

    @Test func anImportedNumberCountsByItsDigits() {
        let day = civilDate("2026-09-15")

        #expect(InvoiceNumbering.next(forDUZP: day, existingNumbers: ["2026-09-04"]) == "20260905")
        #expect(InvoiceNumbering.next(forDUZP: day, existingNumbers: ["Z20260904"]) == "20260905")
        #expect(InvoiceNumbering.next(forDUZP: day, existingNumbers: ["FA-2026-09-04"]) == "20260905")
    }

    @Test func numbersWhoseDigitsAreNotEightLongAreNotCounted() {
        // Seven, six, nine and ten digits that all start with 202609.
        let others = ["2026091", "202609", "202609012", "2026090007"]

        let day = civilDate("2026-09-15")

        #expect(InvoiceNumbering.next(forDUZP: day, existingNumbers: others) == "20260901")
        #expect(InvoiceNumbering.next(forDUZP: day, existingNumbers: others + ["20260902"]) == "20260903")
    }

    @Test func otherMonthsAndYearsAreNotCounted() {
        let existing = ["20250999", "20260899", "20261099", "20270999"]

        #expect(InvoiceNumbering.next(forDUZP: civilDate("2026-09-15"), existingNumbers: existing) == "20260901")
    }

    @Test func theMonthHasTwoDigitsAtTheEdgesOfTheYear() {
        #expect(InvoiceNumbering.next(forDUZP: civilDate("2026-05-15"), existingNumbers: ["20260508"]) == "20260509")
        #expect(InvoiceNumbering.next(forDUZP: civilDate("2026-05-15"), existingNumbers: ["20260509"]) == "20260510")
        #expect(InvoiceNumbering.next(forDUZP: civilDate("2026-12-31"), existingNumbers: ["20261209"]) == "20261210")
        #expect(InvoiceNumbering.next(forDUZP: civilDate("2027-01-01"), existingNumbers: ["20261209"]) == "20270101")
    }

    // MARK: Amounts

    @Test func anItemIsQuantityTimesPriceRoundedHalfUp() {
        #expect(InvoiceMath.itemAmount(quantity: decimal("7.5"), unitPriceMinor: 60_000) == 450_000)
        #expect(InvoiceMath.itemAmount(quantity: 172, unitPriceMinor: 7000) == 1_204_000)
        #expect(InvoiceMath.itemAmount(quantity: decimal("0.335"), unitPriceMinor: 100) == 34)
        #expect(InvoiceMath.itemAmount(quantity: decimal("0.334"), unitPriceMinor: 100) == 33)
        #expect(InvoiceMath.itemAmount(quantity: 0, unitPriceMinor: 60_000) == 0)
        #expect(InvoiceMath.itemAmount(quantity: decimal("-0.335"), unitPriceMinor: 100) == -34)
    }

    @Test func vatIsTheRateOfTheNetRoundedHalfUp() {
        #expect(InvoiceMath.vat(netMinor: 450_000, mode: .domestic21) == 94_500)
        #expect(InvoiceMath.vat(netMinor: 3, mode: .domestic21) == 1)
        #expect(InvoiceMath.vat(netMinor: 2, mode: .domestic21) == 0)
        #expect(InvoiceMath.vat(netMinor: 450_000, mode: .domestic12) == 54_000)
        #expect(InvoiceMath.vat(netMinor: 5, mode: .domestic12) == 1)
        #expect(InvoiceMath.vat(netMinor: 4, mode: .domestic12) == 0)
    }

    @Test func noVatIsChargedOutsideTheDomesticModes() {
        #expect(InvoiceMath.vat(netMinor: 1_435_000, mode: .outsideCountry) == 0)
        #expect(InvoiceMath.vat(netMinor: 1_435_000, mode: .euReverseCharge) == 0)
        #expect(InvoiceMath.vat(netMinor: 1_435_000, mode: VatMode.none) == 0)
    }

    @Test func anInvoiceHasTheTotalsOfItsItems() {
        let czk = Invoice.fixture()
        #expect(czk.netMinor == 450_000)
        #expect(czk.vatMinor == 94_500)
        #expect(czk.totalMinor == 544_500)

        let usd = Invoice.fixture(currency: .usd, items: [.fixture("205", at: 7000)], vatMode: .outsideCountry)
        #expect(usd.netMinor == 1_435_000)
        #expect(usd.vatMinor == 0)
        #expect(usd.totalMinor == 1_435_000)

        let eur = Invoice.fixture(currency: .eur, items: [.fixture("1", at: 100_000)])
        #expect(eur.netMinor == 100_000)
        #expect(eur.vatMinor == 21_000)
        #expect(eur.totalMinor == 121_000)
    }

    @Test func eachItemIsRoundedBeforeTheyAreAdded() {
        // 0,335 × 1,00 is 0,335 and rounds to 0,34 for each of the two items, whereas their exact sum would be 0,67.
        let invoice = Invoice.fixture(items: [.fixture("0.335", at: 100), .fixture("0.335", at: 100)])

        #expect(invoice.netMinor == 68)
    }

    @Test func vatIsWorkedOutOnTheNetOfTheInvoiceAndNotOnEachItem() {
        // Three items of 0,03: 21 % of each is 0,0063 and rounds to 0,01, but 21 % of their net 0,09 is 0,0189 and
        // rounds to 0,02.
        let invoice = Invoice.fixture(items: [.fixture("1", at: 3), .fixture("1", at: 3), .fixture("1", at: 3)])

        #expect(invoice.netMinor == 9)
        #expect(invoice.vatMinor == 2)
        #expect(invoice.totalMinor == 11)
    }

    @Test func anInvoiceWithoutItemsIsWorthNothing() {
        let invoice = Invoice.fixture(items: [])

        #expect(invoice.netMinor == 0)
        #expect(invoice.vatMinor == 0)
        #expect(invoice.totalMinor == 0)
    }

    @Test func theDigitsOfTheNumberAndTheForeignCurrencyFollowFromTheInvoice() {
        #expect(Invoice.fixture(number: "2026-05-01").numberDigits == "20260501")
        #expect(Invoice.fixture(number: "20260901").numberDigits == "20260901")
        #expect(!Invoice.fixture(currency: .czk).isForeignCurrency)
        #expect(Invoice.fixture(currency: .usd).isForeignCurrency)
        #expect(Invoice.fixture(currency: .eur).isForeignCurrency)
    }

    // MARK: Statuses

    @Test func aDraftIsADraft() {
        let draft = invoice(status: .draft)

        #expect(status(of: draft, asOf: "2026-10-17") == .draft)
        // Even after the due date.
        #expect(status(of: draft, asOf: "2026-11-30") == .draft)
    }

    @Test func anIssuedInvoiceAwaitsPaymentUntilTheDayAfterItIsDue() {
        let issued = invoice()

        #expect(status(of: issued, asOf: "2026-10-17") == .awaitingPayment)
        #expect(status(of: issued, asOf: "2026-10-30") == .awaitingPayment)
        #expect(status(of: issued, asOf: "2026-10-31") == .overdue)
        #expect(status(of: issued, asOf: "2027-03-01") == .overdue)
    }

    @Test func aPaymentOnOrBeforeTheDayMakesTheInvoicePaid() {
        let paid = invoice(paidOn: "2026-10-02")

        #expect(status(of: paid, asOf: "2026-10-17") == .paid(civilDate("2026-10-02")))
        #expect(status(of: paid, asOf: "2026-10-02") == .paid(civilDate("2026-10-02")))
        // Paid stays paid when the invoice would have been overdue.
        #expect(status(of: paid, asOf: "2026-12-01") == .paid(civilDate("2026-10-02")))
    }

    @Test func anInvoiceIsPaidFromTheDayOfItsPaymentOnWhateverYearItWasIssuedIn() {
        // Issued on 30. 12. 2025, due on 13. 1. 2026 and paid on 2. 1. 2026. The screens ask for today, which is in
        // another year than the issue: the payment counts from its own day on, in any later year.
        let invoice = Invoice.fixture(
            number: "20251201", issued: "2025-12-30", duzp: "2025-12-30", dueDate: "2026-01-13",
            payment: payment(on: "2026-01-02"))

        #expect(status(of: invoice, asOf: "2025-12-31") == .awaitingPayment)
        #expect(status(of: invoice, asOf: "2026-01-01") == .awaitingPayment)
        #expect(status(of: invoice, asOf: "2026-01-02") == .paid(civilDate("2026-01-02")))
        #expect(status(of: invoice, asOf: "2026-10-20") == .paid(civilDate("2026-01-02")))
        #expect(status(of: invoice, asOf: "2027-03-01") == .paid(civilDate("2026-01-02")))
    }

    @Test func aPaymentAfterTheDayDoesNotCountYet() {
        let later = invoice(paidOn: "2026-10-20")

        #expect(status(of: later, asOf: "2026-10-17") == .awaitingPayment)
        #expect(status(of: later, asOf: "2026-10-19") == .awaitingPayment)
        #expect(status(of: later, asOf: "2026-10-20") == .paid(civilDate("2026-10-20")))

        let afterTheDueDate = invoice(paidOn: "2026-11-05")
        #expect(status(of: afterTheDueDate, asOf: "2026-10-31") == .overdue)
    }

    @Test func aReviewFlagComesBeforeAnythingButADraft() {
        let flag = ReviewFlag(reason: "Zrušeno ve Fakturoidu")

        #expect(status(of: invoice(review: flag), asOf: "2026-10-17") == .needsReview("Zrušeno ve Fakturoidu"))
        #expect(status(of: invoice(review: flag), asOf: "2026-11-30") == .needsReview("Zrušeno ve Fakturoidu"))
        #expect(
            status(of: invoice(paidOn: "2026-10-02", review: flag), asOf: "2026-10-17")
                == .needsReview("Zrušeno ve Fakturoidu")
        )
        #expect(status(of: invoice(status: .draft, review: flag), asOf: "2026-10-17") == .draft)
    }

    @Test func eachStatusHasItsLabel() {
        let paid = status(of: invoice(paidOn: "2026-10-02"), asOf: "2026-10-17")

        #expect(InvoiceDisplayStatus.draft.label == "Koncept")
        #expect(InvoiceDisplayStatus.needsReview("Zrušeno").label == "Ke kontrole")
        #expect(InvoiceDisplayStatus.awaitingPayment.label == "Čeká na platbu")
        #expect(InvoiceDisplayStatus.overdue.label == "Po splatnosti")
        #expect(paid == .paid(civilDate("2026-10-02")))
        #expect(paid.label == "Uhrazená 2.\u{00A0}10.")
        #expect(InvoiceDisplayStatus.paid(civilDate("2026-01-15")).label == "Uhrazená 15.\u{00A0}1.")
    }

    @Test func aPaymentFromAnotherYearThanTheDayShowsItsYear() {
        let earlier = InvoiceDisplayStatus.paid(civilDate("2025-12-20"))
        let thisYear = InvoiceDisplayStatus.paid(civilDate("2026-10-02"))

        #expect(earlier.label(asOf: civilDate("2026-10-17")) == "Uhrazená 20.\u{00A0}12.\u{00A0}2025")
        #expect(thisYear.label(asOf: civilDate("2026-10-17")) == "Uhrazená 2.\u{00A0}10.")
        #expect(thisYear.label(asOf: civilDate("2026-12-31")) == "Uhrazená 2.\u{00A0}10.")
        #expect(thisYear.label(asOf: civilDate("2027-01-01")) == "Uhrazená 2.\u{00A0}10.\u{00A0}2026")
    }

    /// The pill of a row of the list names the status without the day of the payment, which the list shows in a
    /// column of its own; every other status reads as its label.
    @Test func theLabelOfTheListHasNoDate() {
        #expect(InvoiceDisplayStatus.paid(civilDate("2026-10-02")).listLabel == "Uhrazená")
        #expect(InvoiceDisplayStatus.paid(civilDate("2025-12-20")).listLabel == "Uhrazená")
        #expect(InvoiceDisplayStatus.draft.listLabel == "Koncept")
        #expect(InvoiceDisplayStatus.needsReview("Zrušeno").listLabel == "Ke kontrole")
        #expect(InvoiceDisplayStatus.awaitingPayment.listLabel == "Čeká na platbu")
        #expect(InvoiceDisplayStatus.overdue.listLabel == "Po splatnosti")
    }

    @Test func theOtherLabelsDoNotDependOnTheDay() {
        let day = civilDate("2027-06-01")

        #expect(InvoiceDisplayStatus.draft.label(asOf: day) == "Koncept")
        #expect(InvoiceDisplayStatus.needsReview("Zrušeno").label(asOf: day) == "Ke kontrole")
        #expect(InvoiceDisplayStatus.awaitingPayment.label(asOf: day) == "Čeká na platbu")
        #expect(InvoiceDisplayStatus.overdue.label(asOf: day) == "Po splatnosti")
    }

    @Test func eachStatusBelongsToOneFilter() {
        #expect(InvoiceDisplayStatus.draft.filter == .drafts)
        #expect(InvoiceDisplayStatus.needsReview("Zrušeno").filter == .review)
        #expect(InvoiceDisplayStatus.awaitingPayment.filter == .awaiting)
        #expect(InvoiceDisplayStatus.overdue.filter == .overdue)
        #expect(InvoiceDisplayStatus.paid(civilDate("2026-10-02")).filter == .paid)
    }

    @Test func theFiltersAreTheChipsOfTheListInTheirOrder() {
        #expect(InvoiceStatusFilter.allCases == [.all, .drafts, .awaiting, .overdue, .paid, .review])
        #expect(
            InvoiceStatusFilter.allCases.map(\.title)
                == ["Vše", "Koncepty", "Čeká na platbu", "Po splatnosti", "Uhrazené", "Ke kontrole"]
        )
        #expect(
            InvoiceStatusFilter.allCases.map(\.rawValue)
                == ["all", "drafts", "awaiting", "overdue", "paid", "review"]
        )
    }

    // MARK: Invoice rate

    @Test func aSundayDUZPFixesTheRateOfTheFridayAndThatDay() {
        let fixed = InvoiceRateFixing.rateForIssue(
            currency: .usd, duzp: civilDate("2025-11-30"), lookup: declaredLookup("USD", "20.895", on: "2025-11-28"),
            latestBefore: storedRate("USD", "20.5", declaredOn: "2025-11-26")
        )

        #expect(fixed == storedRate("USD", "20.895", declaredOn: "2025-11-28"))
    }

    @Test func theRateOfTheDUZPComesFromTheRateTable() throws {
        let table = RateTable(rows: try cnbYearlyRows([2025]))
        let lookup = table.lookup(.usd, on: civilDate("2025-11-30"))

        let fixed = InvoiceRateFixing.rateForIssue(
            currency: .usd, duzp: civilDate("2025-11-30"), lookup: lookup, latestBefore: nil
        )

        let rate = try #require(fixed?.rate)
        #expect(fixed?.declaredOn == civilDate("2025-11-28"))
        #expect(rate.currency == .usd)
        #expect(lookup == .declared(rate, declaredOn: civilDate("2025-11-28")))
    }

    @Test func aRateThatIsNotDeclaredYetFallsBackToTheLatestRateBefore() {
        let before = storedRate("USD", "20.5", declaredOn: "2025-11-26")

        for lookup in [RateLookupResult.notYetAvailable, .notPublished] {
            let fixed = InvoiceRateFixing.rateForIssue(
                currency: .usd, duzp: civilDate("2025-11-30"), lookup: lookup, latestBefore: before
            )
            #expect(fixed == before)
        }
    }

    @Test func withoutAnyRateNoRateIsFixed() {
        let fixed = InvoiceRateFixing.rateForIssue(
            currency: .usd, duzp: civilDate("2025-11-30"), lookup: .notYetAvailable, latestBefore: nil
        )

        #expect(fixed == nil)
    }

    @Test func aDeclaredRateWinsOverTheLatestRateBefore() {
        let fixed = InvoiceRateFixing.rateForIssue(
            currency: .eur, duzp: civilDate("2026-09-30"), lookup: declaredLookup("EUR", "24.325", on: "2026-09-30"),
            latestBefore: storedRate("EUR", "24.1", declaredOn: "2026-09-29")
        )

        #expect(fixed == storedRate("EUR", "24.325", declaredOn: "2026-09-30"))
    }

    @Test func anInvoiceInCrownsHasNoRate() {
        let crown = ExchangeRate(currency: .czk, amount: 1, rate: 1)

        let declaredToday = InvoiceRateFixing.rateForIssue(
            currency: .czk, duzp: civilDate("2026-09-30"),
            lookup: .declared(crown, declaredOn: civilDate("2026-09-30")), latestBefore: nil
        )
        let withALatestRate = InvoiceRateFixing.rateForIssue(
            currency: .czk, duzp: civilDate("2026-09-30"), lookup: .notYetAvailable,
            latestBefore: storedRate("USD", "20.5", declaredOn: "2026-09-29")
        )

        #expect(declaredToday == nil)
        #expect(withALatestRate == nil)
    }

    // MARK: The rate that may be fixed on an invoice that is issued

    /// Saturday 17 October 2026: the newest declaration that should be in the cache is that of Friday 16 October.
    private let newestExpected = civilDate("2026-10-16")

    private func rateToFix(
        duzp: String, lookup: RateLookupResult, latestBefore: StoredRate? = storedRate(
            "USD", "21.5", declaredOn: "2026-10-16"),
        newestCached: String? = "2026-10-16"
    ) -> StoredRate? {
        InvoiceRateFixing.rateToFix(
            currency: .usd, duzp: civilDate(duzp), lookup: lookup, latestBefore: latestBefore,
            expectedNewestDeclaration: newestExpected, newestCachedDeclaration: newestCached.map(civilDate))
    }

    @Test func theRateDeclaredForTheDUZPIsTheOneToFixWhateverTheCache() {
        let lookup = declaredLookup("USD", "21.732", on: "2026-10-15")

        #expect(
            rateToFix(duzp: "2026-10-15", lookup: lookup, newestCached: "2026-10-15")
                == storedRate("USD", "21.732", declaredOn: "2026-10-15"))
        #expect(
            rateToFix(duzp: "2026-10-15", lookup: lookup, newestCached: nil)
                == storedRate("USD", "21.732", declaredOn: "2026-10-15"))
    }

    @Test func aDUZPThatIsStillAheadTakesTheLastDeclaredRateWhileTheCacheIsCurrent() {
        // 31 October is a Saturday, after the newest declaration there can be on the 17th.
        let fixed = rateToFix(duzp: "2026-10-31", lookup: .notYetAvailable)

        #expect(fixed == storedRate("USD", "21.5", declaredOn: "2026-10-16"))
        // A cache that holds more than it should (a clock that is behind) is current as well.
        #expect(rateToFix(duzp: "2026-10-31", lookup: .notYetAvailable, newestCached: "2026-10-19") == fixed)
    }

    @Test func aCurrencyThatIsNotInTheNewestDeclarationGetsNoOlderRateEvenWhileTheCacheIsCurrent() {
        // The newest declaration, 16. 10., has no rate of this currency: the last one is days old, or there is none.
        let older = storedRate("USD", "21.5", declaredOn: "2026-10-15")

        #expect(rateToFix(duzp: "2026-10-31", lookup: .notYetAvailable, latestBefore: older) == nil)
        #expect(rateToFix(duzp: "2026-10-31", lookup: .notYetAvailable, latestBefore: nil) == nil)
    }

    @Test func aDUZPThatIsStillAheadWaitsWhileTheCacheIsBehind() {
        #expect(rateToFix(duzp: "2026-10-31", lookup: .notYetAvailable, newestCached: "2026-10-15") == nil)
        #expect(rateToFix(duzp: "2026-10-31", lookup: .notYetAvailable, newestCached: nil) == nil)
    }

    @Test func aRateThatShouldBeThereButIsNotIsNeverReplacedByAnOlderOne() {
        // A hole in the rows, or a declaration that is not stored yet: the DUZP is not after the newest declaration.
        #expect(rateToFix(duzp: "2026-10-16", lookup: .notYetAvailable) == nil)
        #expect(rateToFix(duzp: "2026-08-14", lookup: .notYetAvailable) == nil)
        #expect(rateToFix(duzp: "2025-03-14", lookup: .notYetAvailable, newestCached: "2026-10-16") == nil)
    }

    @Test func aCurrencyTheCNBDoesNotQuoteHasNoRateToFix() {
        #expect(rateToFix(duzp: "2026-10-15", lookup: .notPublished) == nil)
        #expect(rateToFix(duzp: "2026-10-31", lookup: .notPublished) == nil)
    }

    @Test func noRateIsFixedForCrowns() {
        let fixed = InvoiceRateFixing.rateToFix(
            currency: .czk, duzp: civilDate("2026-10-31"), lookup: .notYetAvailable,
            latestBefore: storedRate("USD", "21.5", declaredOn: "2026-10-15"),
            expectedNewestDeclaration: newestExpected, newestCachedDeclaration: civilDate("2026-10-16"))

        #expect(fixed == nil)
    }

    @Test func theYearlyFilesThatFillAGapAreThoseOfTheDeclarationTheDUZPNeeds() {
        func years(_ duzp: String, expected: String = "2026-10-16") -> [Int] {
            InvoiceRateFixing.yearsToFetch(duzp: civilDate(duzp), expectedNewestDeclaration: civilDate(expected))
        }

        #expect(years("2022-06-30") == [2022])
        // Later in January the days before the declaration are in January too.
        #expect(years("2022-01-10") == [2022])
        // The first declaration of a year is told from the last one of the year before when a day is skipped.
        #expect(years("2026-01-02") == [2026, 2025])
        // Jan 1 and the weekend that follows it in 2027: the first declaration is on Monday 4. 1.
        #expect(years("2027-01-04", expected: "2027-06-01") == [2027, 2026])
        // New Year's Day and the days up to the first declaration take the rate of the last business day of the year
        // before.
        #expect(years("2026-01-01") == [2025])
        #expect(years("2027-01-02", expected: "2027-06-01") == [2026])
        // A DUZP that is ahead needs the declarations up to the newest one that should exist.
        #expect(years("2026-10-31") == [2026])
        #expect(years("2027-01-31", expected: "2027-01-14") == [2027])
        #expect(years("2027-01-31", expected: "2027-01-04") == [2027, 2026])
    }

    // MARK: Deleting

    @Test func theNumberOrItsDigitsConfirmADelete() {
        #expect(DeleteConfirmation.matches(typed: "20260501", number: "2026-05-01"))
        #expect(DeleteConfirmation.matches(typed: "2026-05-01", number: "2026-05-01"))
        #expect(DeleteConfirmation.matches(typed: "20260901", number: "20260901"))
        #expect(DeleteConfirmation.matches(typed: "Z20261001", number: "Z20261001"))
        #expect(DeleteConfirmation.matches(typed: "20261001", number: "Z20261001"))
    }

    @Test func spacesAroundTheTextAreIgnored() {
        #expect(DeleteConfirmation.matches(typed: " 2026-05-01 ", number: "2026-05-01"))
        #expect(DeleteConfirmation.matches(typed: "\t20260501\n", number: "2026-05-01"))
        #expect(DeleteConfirmation.matches(typed: "\u{00A0}20260501\u{00A0}", number: "2026-05-01"))
    }

    @Test func anythingElseDoesNotConfirmADelete() {
        #expect(!DeleteConfirmation.matches(typed: "2026050", number: "2026-05-01"))
        #expect(!DeleteConfirmation.matches(typed: "202605011", number: "2026-05-01"))
        #expect(!DeleteConfirmation.matches(typed: "2026 05 01", number: "2026-05-01"))
        #expect(!DeleteConfirmation.matches(typed: "20260502", number: "2026-05-01"))
        #expect(!DeleteConfirmation.matches(typed: "2026-05-01", number: "20260501"))
    }

    @Test func nothingTypedNeverConfirmsADelete() {
        #expect(!DeleteConfirmation.matches(typed: "", number: "2026-05-01"))
        #expect(!DeleteConfirmation.matches(typed: "   ", number: "2026-05-01"))
        // Not even for a number that has no digits, whose digits are the empty text.
        #expect(!DeleteConfirmation.matches(typed: "", number: "bez čísla"))
        #expect(!DeleteConfirmation.matches(typed: "", number: ""))
    }

    // MARK: Template text

    @Test func monthAndYearFillInThePlaceholders() {
        let day = civilDate("2026-09-30")

        #expect(TemplateText.fill("Vývoj – {měsíc} {rok}", duzp: day) == "Vývoj – září 2026")
        #expect(TemplateText.fill("Development {month} {year}", duzp: day) == "Development September 2026")
    }

    @Test func theCzechAndTheEnglishPlaceholdersCanBeMixed() {
        let text = TemplateText.fill("{měsíc} {rok} / {month} {year}", duzp: civilDate("2026-03-01"))

        #expect(text == "březen 2026 / March 2026")
    }

    @Test func everyMonthHasItsNameInBothLanguages() {
        let czech = [
            "leden", "únor", "březen", "duben", "květen", "červen",
            "červenec", "srpen", "září", "říjen", "listopad", "prosinec",
        ]
        let english = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December",
        ]
        for month in 1...12 {
            let day = civilDate("2026-\(month < 10 ? "0" : "")\(month)-15")
            #expect(TemplateText.fill("{měsíc}", duzp: day) == czech[month - 1])
            #expect(TemplateText.fill("{month}", duzp: day) == english[month - 1])
        }
    }

    @Test func aPlaceholderIsFilledEveryTimeItAppears() {
        let text = TemplateText.fill("{rok}/{rok} {year}{year}", duzp: civilDate("2027-01-01"))

        #expect(text == "2027/2027 20272027")
    }

    @Test func textWithoutAPlaceholderStaysAsItIs() {
        let day = civilDate("2026-09-30")

        #expect(TemplateText.fill("", duzp: day) == "")
        #expect(TemplateText.fill("IT služby", duzp: day) == "IT služby")
        #expect(TemplateText.fill("{jiné} {Měsíc} {YEAR} {rok", duzp: day) == "{jiné} {Měsíc} {YEAR} {rok")
    }

    @Test func aPlaceholderTypedWithCombiningMarksIsStillFilled() {
        let decomposed = "{měsíc}".decomposedStringWithCanonicalMapping

        #expect(TemplateText.fill("Vývoj \(decomposed)", duzp: civilDate("2026-09-30")) == "Vývoj září")
    }
}

import Foundation
import Testing
@testable import InvoicesTracker

struct PaymentConverterTests {
    // MARK: Helpers

    /// 205 hours at 70,00 USD: 14 350,00 USD without VAT, with the ČNB rate of 30 September 2026 as the invoice rate.
    private func usdInvoice(hours: String = "205") -> Invoice {
        Invoice.fixture(
            currency: .usd, items: [.fixture(hours, at: 7000)], vatMode: .outsideCountry,
            invoiceRate: storedRate("USD", "21.359", declaredOn: "2026-09-30")
        )
    }

    /// 1 000,00 EUR, and with 21 % VAT 1 210,00 EUR.
    private func eurInvoice(_ vatMode: VatMode = .domestic21, quantity: String = "1") -> Invoice {
        Invoice.fixture(
            currency: .eur, items: [.fixture(quantity, at: 100_000)], vatMode: vatMode,
            invoiceRate: storedRate("EUR", "24.325", declaredOn: "2026-09-30")
        )
    }

    /// 4 500,00 Kč and 945,00 Kč VAT.
    private func czkInvoice() -> Invoice {
        Invoice.fixture()
    }

    private func uniformRate(_ code: String, _ rate: String) -> ExchangeRate {
        storedRate(code, rate, declaredOn: "2026-12-31").rate
    }

    private func convert(
        _ invoice: Invoice, _ requested: PaymentConversion, on day: String = "2026-10-02", bank: Int64? = nil,
        cnb: RateLookupResult = .notYetAvailable, uniform: ExchangeRate? = nil
    ) -> Payment {
        PaymentConverter.convert(
            invoice: invoice, date: civilDate(day), requested: requested, bankCZKTotalHalere: bank, cnbRate: cnb,
            uniformRate: uniform
        )
    }

    private func reapply(_ payment: Payment, to invoice: Invoice) -> Payment {
        PaymentConverter.reapply(payment, to: invoice)
    }

    // MARK: ČNB rate of the day

    @Test func aDeclaredRateConvertsTheNetOfTheInvoice() {
        let payment = convert(usdInvoice(), .cnbDaily, cnb: declaredLookup("USD", "21.305", on: "2026-10-02"))

        #expect(
            payment == Payment(
                date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 30_572_675, czkVatHalere: 0,
                rate: storedRate("USD", "21.305", declaredOn: "2026-10-02"), provisional: false,
                bankCZKTotalHalere: nil
            )
        )
    }

    @Test func aWeekendPaymentKeepsTheDayTheRateWasDeclaredOn() {
        let payment = convert(
            usdInvoice(), .cnbDaily, on: "2026-10-03", cnb: declaredLookup("USD", "21.305", on: "2026-10-02")
        )

        #expect(payment.date == civilDate("2026-10-03"))
        #expect(payment.rate == storedRate("USD", "21.305", declaredOn: "2026-10-02"))
        #expect(payment.czkNetHalere == 30_572_675)
    }

    @Test func theNetAndTheVatAreConvertedEachOnItsOwn() {
        // 0,03 EUR and 0,01 EUR VAT at 24,50: 0,735 Kč and 0,245 Kč round to 0,74 Kč and 0,25 Kč, which add up to
        // more than the 0,98 Kč of the total of 0,04 EUR.
        let invoice = Invoice.fixture(currency: .eur, items: [.fixture("1", at: 3)], vatMode: .domestic21)
        #expect(invoice.netMinor == 3)
        #expect(invoice.vatMinor == 1)

        let payment = convert(invoice, .cnbDaily, cnb: declaredLookup("EUR", "24.5", on: "2026-10-02"))

        #expect(payment.czkNetHalere == 74)
        #expect(payment.czkVatHalere == 25)
    }

    @Test func theVatOfAForeignInvoiceIsConvertedWithTheSameRate() {
        let payment = convert(eurInvoice(), .cnbDaily, cnb: declaredLookup("EUR", "24.325", on: "2026-10-02"))

        #expect(payment.czkNetHalere == 2_432_500)
        #expect(payment.czkVatHalere == 510_825)
    }

    @Test func aRateQuotedForSeveralUnitsIsDividedByTheAmount() {
        // 1 000 000,00 HUF at 6,337 Kč per 100 HUF is 63 370,00 Kč.
        let invoice = Invoice.fixture(
            currency: CurrencyCode("HUF")!, items: [.fixture("1", at: 100_000_000)], vatMode: .outsideCountry
        )

        let payment = convert(invoice, .cnbDaily, cnb: declaredLookup("HUF", "6.337", on: "2026-10-02", amount: 100))

        #expect(payment.czkNetHalere == 6_337_000)
        #expect(payment.rate == storedRate("HUF", "6.337", declaredOn: "2026-10-02", amount: 100))
    }

    @Test func aRateThatIsNotAvailableYetFallsBackToTheInvoiceRateAndIsProvisional() {
        for lookup in [RateLookupResult.notYetAvailable, .notPublished] {
            let payment = convert(usdInvoice(), .cnbDaily, cnb: lookup)

            #expect(
                payment == Payment(
                    date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 30_650_165, czkVatHalere: 0,
                    rate: storedRate("USD", "21.359", declaredOn: "2026-09-30"), provisional: true,
                    bankCZKTotalHalere: nil
                )
            )
        }
    }

    @Test func withoutAnyRateThePaymentIsWorthNothingAndProvisional() {
        let invoice = Invoice.fixture(currency: .usd, items: [.fixture("205", at: 7000)], vatMode: .outsideCountry)
        #expect(invoice.invoiceRate == nil)

        for lookup in [RateLookupResult.notYetAvailable, .notPublished] {
            let payment = convert(invoice, .cnbDaily, cnb: lookup)

            #expect(
                payment == Payment(
                    date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 0, czkVatHalere: 0, rate: nil,
                    provisional: true, bankCZKTotalHalere: nil
                )
            )
        }
    }

    @Test func aBankAmountIsNotKeptWithAnotherMethod() {
        let payment = convert(
            usdInvoice(), .cnbDaily, bank: 30_600_000, cnb: declaredLookup("USD", "21.305", on: "2026-10-02")
        )

        #expect(payment.bankCZKTotalHalere == nil)
    }

    // MARK: Uniform rate

    @Test func aKnownUniformRateConvertsAndIsDeclaredOnTheLastDayOfTheYear() {
        let payment = convert(
            usdInvoice(), .uniform, cnb: declaredLookup("USD", "21.305", on: "2026-10-02"),
            uniform: uniformRate("USD", "21.84")
        )

        #expect(
            payment == Payment(
                date: civilDate("2026-10-02"), conversion: .uniform, czkNetHalere: 31_340_400, czkVatHalere: 0,
                rate: storedRate("USD", "21.84", declaredOn: "2026-12-31"), provisional: false,
                bankCZKTotalHalere: nil
            )
        )
    }

    @Test func theUniformRateIsDeclaredOnTheLastDayOfTheYearOfThePayment() {
        let payment = convert(usdInvoice(), .uniform, on: "2027-01-04", uniform: uniformRate("USD", "21.84"))

        #expect(payment.rate?.declaredOn == civilDate("2027-12-31"))
        #expect(payment.date == civilDate("2027-01-04"))
    }

    @Test func aKnownUniformRateConvertsTheVatToo() {
        let payment = convert(eurInvoice(), .uniform, uniform: uniformRate("EUR", "24.66"))

        #expect(payment.czkNetHalere == 2_466_000)
        #expect(payment.czkVatHalere == 517_860)
        #expect(!payment.provisional)
    }

    /// A year chosen to convert at the uniform rate that does not have it (not published yet, or not for the currency)
    /// is converted at the daily ČNB rates meanwhile: the payment is one at the rate of its day, as in a year that
    /// converts at them, and nothing about it waits for the uniform rate.
    @Test func aYearChosenUniformWithoutItsRateConvertsAtDailyRates() {
        let payment = convert(usdInvoice(), .uniform, cnb: declaredLookup("USD", "21.305", on: "2026-10-02"))

        #expect(
            payment == Payment(
                date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 30_572_675, czkVatHalere: 0,
                rate: storedRate("USD", "21.305", declaredOn: "2026-10-02"), provisional: false,
                bankCZKTotalHalere: nil
            )
        )
        #expect(payment == convert(usdInvoice(), .cnbDaily, cnb: declaredLookup("USD", "21.305", on: "2026-10-02")))
    }

    @Test func withoutItsUniformRateAndTheRateOfTheDayThePaymentWaitsAtTheInvoiceRateAsADailyOne() {
        let payment = convert(usdInvoice(), .uniform)

        #expect(
            payment == Payment(
                date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 30_650_165, czkVatHalere: 0,
                rate: storedRate("USD", "21.359", declaredOn: "2026-09-30"), provisional: true,
                bankCZKTotalHalere: nil
            )
        )
    }

    @Test func withoutItsUniformRateAndAnyOtherRateThePaymentIsWorthNothing() {
        let invoice = Invoice.fixture(currency: .usd, items: [.fixture("205", at: 7000)], vatMode: .outsideCountry)

        let payment = convert(invoice, .uniform, cnb: .notPublished)

        #expect(
            payment == Payment(
                date: civilDate("2026-10-02"), conversion: .cnbDaily, czkNetHalere: 0, czkVatHalere: 0, rate: nil,
                provisional: true, bankCZKTotalHalere: nil
            )
        )
    }

    // MARK: Amount in crowns from the bank

    @Test func theBankAmountOfAnInvoiceWithoutVatIsAllNet() {
        let payment = convert(
            usdInvoice(), .bankCZK, bank: 30_600_000, cnb: declaredLookup("USD", "21.305", on: "2026-10-02")
        )

        #expect(
            payment == Payment(
                date: civilDate("2026-10-02"), conversion: .bankCZK, czkNetHalere: 30_600_000, czkVatHalere: 0,
                rate: nil, provisional: false, bankCZKTotalHalere: 30_600_000
            )
        )
    }

    @Test func theBankAmountOfAnInvoiceWithVatIsSplitInTheProportionOfTheInvoice() {
        let payment = convert(eurInvoice(), .bankCZK, bank: 2_940_000)

        #expect(
            payment == Payment(
                date: civilDate("2026-10-02"), conversion: .bankCZK, czkNetHalere: 2_429_752, czkVatHalere: 510_248,
                rate: nil, provisional: false, bankCZKTotalHalere: 2_940_000
            )
        )
    }

    @Test func theNetOfTheBankAmountIsRoundedHalfUpAndTheVatIsTheRest() {
        // 1,00 EUR and 0,12 EUR VAT: 0,14 Kč splits into 0,125 Kč and 0,015 Kč, and the net rounds up to 0,13 Kč.
        let invoice = Invoice.fixture(currency: .eur, items: [.fixture("1", at: 100)], vatMode: .domestic12)
        #expect(invoice.netMinor == 100)
        #expect(invoice.vatMinor == 12)

        let payment = convert(invoice, .bankCZK, bank: 14)

        #expect(payment.czkNetHalere == 13)
        #expect(payment.czkVatHalere == 1)
    }

    @Test func theTwoPartsOfTheBankAmountAlwaysAddUpToIt() {
        let invoices = [eurInvoice(), eurInvoice(.domestic12), eurInvoice(quantity: "3.333"), usdInvoice()]

        for invoice in invoices {
            for bank in [Int64(1), 2, 3, 7, 14, 100, 2_940_001, 30_600_000] {
                let payment = convert(invoice, .bankCZK, bank: bank)
                #expect(payment.czkNetHalere + payment.czkVatHalere == bank)
                #expect((0...bank).contains(payment.czkNetHalere))
                #expect(payment.bankCZKTotalHalere == bank)
            }
        }
    }

    @Test func aBankAmountThatWasNotEnteredIsWorthNothing() {
        let payment = convert(eurInvoice(), .bankCZK, bank: nil)

        #expect(
            payment == Payment(
                date: civilDate("2026-10-02"), conversion: .bankCZK, czkNetHalere: 0, czkVatHalere: 0, rate: nil,
                provisional: false, bankCZKTotalHalere: nil
            )
        )
    }

    // MARK: Invoice in crowns

    @Test func anInvoiceInCrownsTakesItsOwnAmountsWhateverMethodIsRequested() {
        let expected = Payment(
            date: civilDate("2026-10-02"), conversion: .czk, czkNetHalere: 450_000, czkVatHalere: 94_500, rate: nil,
            provisional: false, bankCZKTotalHalere: nil
        )
        let crown = ExchangeRate(currency: .czk, amount: 1, rate: 1)

        for requested in [PaymentConversion.czk, .cnbDaily, .uniform, .bankCZK] {
            let payment = convert(
                czkInvoice(), requested, bank: 123_456, cnb: .declared(crown, declaredOn: civilDate("2026-10-02")),
                uniform: uniformRate("USD", "21.84")
            )
            #expect(payment == expected)
        }
    }

    @Test func anInvoiceInCrownsWithoutVatHasNoVatToTake() {
        let invoice = Invoice.fixture(vatMode: .none)

        let payment = convert(invoice, .czk)

        #expect(payment.czkNetHalere == 450_000)
        #expect(payment.czkVatHalere == 0)
    }

    @Test func aForeignInvoiceIsNeverConvertedAsCrowns() {
        let payment = convert(usdInvoice(), .czk, cnb: declaredLookup("USD", "21.305", on: "2026-10-02"))

        #expect(payment.conversion == .cnbDaily)
        #expect(payment.czkNetHalere == 30_572_675)
    }

    // MARK: Editing a paid invoice

    @Test func aChangedQuantityIsConvertedWithTheStoredRate() {
        let stored = convert(usdInvoice(), .cnbDaily, cnb: declaredLookup("USD", "21.305", on: "2026-10-02"))

        let payment = reapply(stored, to: usdInvoice(hours: "220"))

        #expect(payment.czkNetHalere == 32_809_700)
        #expect(payment.czkVatHalere == 0)
        #expect(payment.rate == storedRate("USD", "21.305", declaredOn: "2026-10-02"))
        #expect(payment.date == stored.date)
        #expect(payment.conversion == .cnbDaily)
        #expect(!payment.provisional)
    }

    @Test func aChangedVatModeIsConvertedWithTheStoredRate() {
        let stored = convert(eurInvoice(), .cnbDaily, cnb: declaredLookup("EUR", "24.325", on: "2026-10-02"))

        let payment = reapply(stored, to: eurInvoice(.domestic12))

        #expect(payment.czkNetHalere == 2_432_500)
        #expect(payment.czkVatHalere == 291_900)
    }

    @Test func aProvisionalPaymentStaysProvisionalAtItsStandInRate() {
        let stored = convert(usdInvoice(), .cnbDaily)
        #expect(stored.provisional)

        let payment = reapply(stored, to: usdInvoice(hours: "220"))

        #expect(payment.czkNetHalere == 32_892_860)
        #expect(payment.rate == storedRate("USD", "21.359", declaredOn: "2026-09-30"))
        #expect(payment.provisional)
    }

    @Test func aUniformPaymentKeepsItsUniformRate() {
        let stored = convert(usdInvoice(), .uniform, uniform: uniformRate("USD", "21.84"))

        let payment = reapply(stored, to: usdInvoice(hours: "220"))

        #expect(payment.czkNetHalere == 33_633_600)
        #expect(payment.conversion == .uniform)
        #expect(payment.rate == storedRate("USD", "21.84", declaredOn: "2026-12-31"))
        #expect(!payment.provisional)
    }

    @Test func aProvisionalUniformPaymentStaysProvisional() {
        // A stand-in for a uniform rate that was not there, as earlier versions of the app stored it: at the ČNB rate
        // of the day, provisional.
        let stored = Payment(
            date: civilDate("2026-10-02"), conversion: .uniform, czkNetHalere: 30_572_675, czkVatHalere: 0,
            rate: storedRate("USD", "21.305", declaredOn: "2026-10-02"), provisional: true)

        let payment = reapply(stored, to: usdInvoice(hours: "220"))

        #expect(payment.czkNetHalere == 32_809_700)
        #expect(payment.conversion == .uniform)
        #expect(payment.provisional)
    }

    @Test func theEnteredBankAmountStaysAndIsSplitByTheNewProportion() {
        let stored = convert(eurInvoice(), .bankCZK, bank: 2_940_000)

        let lowerVat = reapply(stored, to: eurInvoice(.domestic12))
        let noVat = reapply(stored, to: eurInvoice(VatMode.none))
        let doubled = reapply(stored, to: eurInvoice(quantity: "2"))

        // 1 000,00 EUR and 120,00 EUR VAT: 29 400,00 Kč is 26 250,00 Kč and 3 150,00 Kč.
        #expect(lowerVat.czkNetHalere == 2_625_000)
        #expect(lowerVat.czkVatHalere == 315_000)
        #expect(noVat.czkNetHalere == 2_940_000)
        #expect(noVat.czkVatHalere == 0)
        #expect(doubled.czkNetHalere == 2_429_752)
        #expect(doubled.czkVatHalere == 510_248)
        for payment in [lowerVat, noVat, doubled] {
            #expect(payment.bankCZKTotalHalere == 2_940_000)
            #expect(payment.conversion == .bankCZK)
            #expect(payment.date == stored.date)
            #expect(payment.rate == nil)
        }
    }

    @Test func aPaymentInCrownsTakesTheNewAmounts() {
        let stored = convert(czkInvoice(), .czk)

        let payment = reapply(stored, to: Invoice.fixture(items: [.fixture("7", at: 60_000)]))

        #expect(payment.czkNetHalere == 420_000)
        #expect(payment.czkVatHalere == 88_200)
        #expect(payment.conversion == .czk)
        #expect(payment.date == stored.date)
    }

    @Test func aPaymentWithoutTheRateItNeedsKeepsItsAmounts() {
        // A payment worth nothing for lack of a rate has nothing to apply to the new amounts. A payment is not
        // reapplied in that state, but if it is, it stays as it is rather than getting an invented rate.
        let noRate = convert(
            Invoice.fixture(currency: .usd, items: [.fixture("205", at: 7000)], vatMode: .outsideCountry), .cnbDaily
        )
        let noBankAmount = convert(eurInvoice(), .bankCZK, bank: nil)

        #expect(reapply(noRate, to: usdInvoice(hours: "220")) == noRate)
        #expect(reapply(noBankAmount, to: eurInvoice(quantity: "2")) == noBankAmount)
    }

    @Test func reapplyingToTheSameInvoiceChangesNothing() {
        let usdWithoutRate = Invoice.fixture(
            currency: .usd, items: [.fixture("205", at: 7000)], vatMode: .outsideCountry
        )
        let cases: [(invoice: Invoice, payment: Payment)] = [
            (usdInvoice(), convert(usdInvoice(), .cnbDaily, cnb: declaredLookup("USD", "21.305", on: "2026-10-02"))),
            (usdInvoice(), convert(usdInvoice(), .cnbDaily)),
            (usdWithoutRate, convert(usdWithoutRate, .cnbDaily)),
            (usdInvoice(), convert(usdInvoice(), .uniform, uniform: uniformRate("USD", "21.84"))),
            (usdInvoice(), convert(usdInvoice(), .uniform, cnb: declaredLookup("USD", "21.305", on: "2026-10-02"))),
            (eurInvoice(), convert(eurInvoice(), .cnbDaily, cnb: declaredLookup("EUR", "24.325", on: "2026-10-02"))),
            (eurInvoice(), convert(eurInvoice(), .bankCZK, bank: 2_940_000)),
            (usdInvoice(), convert(usdInvoice(), .bankCZK, bank: 30_600_000)),
            (czkInvoice(), convert(czkInvoice(), .czk)),
        ]

        for (index, row) in cases.enumerated() {
            #expect(reapply(row.payment, to: row.invoice) == row.payment, "case \(index)")
        }
    }
}

import Foundation
import Testing

@testable import InvoicesTracker

/// The items, the VAT mode, the rate and the payment method that an ISDOC invoice gives an invoice of the app.
struct IsdocInvoiceBuilderTests {
    private func read(_ name: String) throws -> IsdocInvoice {
        try IsdocReader.read(Data(contentsOf: fixtureURL(name, "isdoc")))
    }

    /// An invoice with the given lines, in crowns unless a currency is given.
    private func invoice(lines: [IsdocLine], currency: String = "CZK") -> IsdocInvoice {
        let party = IsdocParty(
            name: "Klient", street: "", postcode: "", city: "", country: "CZ", ico: "", dic: "", email: ""
        )
        return IsdocInvoice(
            documentType: 1, number: "2026-7", uuid: "u", issueDate: nil, taxPointDate: nil, dueDate: nil, note: "",
            currency: currency, rate: nil, customer: party, supplier: nil, lines: lines, paymentMeansCode: ""
        )
    }

    private func line(quantity: Decimal, amount: Int64, price: Int64?, vat: Decimal = 21) -> IsdocLine {
        IsdocLine(
            description: "Práce", quantity: quantity, unit: "h", lineAmountMinor: amount, unitPriceCZKMinor: price,
            vatPercent: vat
        )
    }

    @Test func aCrownLineKeepsItsQuantityUnitAndUnitPrice() throws {
        let result = IsdocInvoiceBuilder.items(of: try read("czk-21"))
        #expect(result.notes.isEmpty)
        let item = try #require(result.items.first)
        #expect(item.quantity == 7)
        #expect(item.unit == "hod")
        #expect(item.unitPriceMinor == 72000)
    }

    @Test func aForeignLineGetsItsPriceInTheCurrency() throws {
        let result = IsdocInvoiceBuilder.items(of: try read("usd-0"))
        #expect(result.notes.isEmpty)
        let item = try #require(result.items.first)
        #expect(item.quantity == 194)
        #expect(item.unit == "h")
        #expect(item.unitPriceMinor == 7400)
        #expect(InvoiceMath.itemAmount(quantity: item.quantity, unitPriceMinor: item.unitPriceMinor) == 1_435_600)
    }

    @Test func aLineThatDoesNotDivideExactlyBecomesOneTimesItsAmountWithANote() {
        let isdoc = invoice(lines: [line(quantity: 3, amount: 1000, price: nil)], currency: "USD")
        let result = IsdocInvoiceBuilder.items(of: isdoc)
        #expect(result.items == [InvoiceItem(description: "Práce", quantity: 1, unit: "", unitPriceMinor: 1000)])
        #expect(result.notes == ["2026-7 — položka „Práce“ převzata jako 1 × částka řádku"])
    }

    @Test func aCrownLineWhoseUnitPriceDoesNotGiveItsAmountBecomesOneTimesItsAmount() {
        let isdoc = invoice(lines: [line(quantity: 2, amount: 1000, price: 501)])
        let result = IsdocInvoiceBuilder.items(of: isdoc)
        #expect(result.items == [InvoiceItem(description: "Práce", quantity: 1, unit: "", unitPriceMinor: 1000)])
        #expect(result.notes.count == 1)
    }

    @Test func aZeroQuantityBecomesOneTimesItsAmount() {
        let isdoc = invoice(lines: [line(quantity: 0, amount: 0, price: 500)])
        let result = IsdocInvoiceBuilder.items(of: isdoc)
        #expect(result.items == [InvoiceItem(description: "Práce", quantity: 1, unit: "", unitPriceMinor: 0)])
        #expect(result.notes == ["2026-7 — položka „Práce“ převzata jako 1 × částka řádku"])
    }

    @Test func twentyOnePercentIsDomestic21AndTwelveIsDomestic12() {
        let at21 = invoice(lines: [line(quantity: 1, amount: 100, price: 100, vat: 21)])
        let at12 = invoice(lines: [line(quantity: 1, amount: 100, price: 100, vat: 12)])
        #expect(IsdocInvoiceBuilder.vatMode(of: at21, existing: nil, clientCountry: "CZ") == .domestic21)
        #expect(IsdocInvoiceBuilder.vatMode(of: at12, existing: .domestic21, clientCountry: "DE") == .domestic12)
    }

    @Test func zeroKeepsAnExistingZeroModeAndAnewInvoiceOutsideTheEUIsOutside() {
        let zero = invoice(lines: [line(quantity: 1, amount: 100, price: 100, vat: 0)])
        let kept = IsdocInvoiceBuilder.vatMode(of: zero, existing: .euReverseCharge, clientCountry: "US")
        #expect(kept == .euReverseCharge)
        #expect(IsdocInvoiceBuilder.vatMode(of: zero, existing: VatMode.none, clientCountry: "US") == VatMode.none)
        let outside = IsdocInvoiceBuilder.vatMode(of: zero, existing: .outsideCountry, clientCountry: "CZ")
        #expect(outside == .outsideCountry)
        #expect(IsdocInvoiceBuilder.vatMode(of: zero, existing: .domestic21, clientCountry: "US") == .outsideCountry)
        #expect(IsdocInvoiceBuilder.vatMode(of: zero, existing: nil, clientCountry: "US") == .outsideCountry)
        #expect(IsdocInvoiceBuilder.vatMode(of: zero, existing: nil, clientCountry: "DE") == VatMode.none)
        #expect(IsdocInvoiceBuilder.vatMode(of: zero, existing: nil, clientCountry: "CZ") == VatMode.none)
        #expect(IsdocInvoiceBuilder.vatMode(of: zero, existing: nil, clientCountry: "") == VatMode.none)
    }

    @Test func mixedRatesHaveNoMode() throws {
        #expect(IsdocInvoiceBuilder.vatMode(of: try read("mixed-vat"), existing: nil, clientCountry: "CZ") == nil)
        let other = invoice(lines: [line(quantity: 1, amount: 100, price: 100, vat: 15)])
        #expect(IsdocInvoiceBuilder.vatMode(of: other, existing: nil, clientCountry: "CZ") == nil)
    }

    @Test func theRateIsCurrRateOverRefCurrRateDeclaredForTheDUZP() throws {
        #expect(IsdocInvoiceBuilder.invoiceRate(of: try read("czk-21"), duzp: CivilDate(iso: "2026-09-02")!) == nil)
        let duzp = CivilDate(iso: "2026-09-02")!
        let stored = try #require(IsdocInvoiceBuilder.invoiceRate(of: try read("usd-0"), duzp: duzp))
        #expect(stored.rate == ExchangeRate(currency: .usd, amount: 1, rate: Decimal(string: "21.278")!))
        #expect(stored.declaredOn == CzechCalendar.rateDeclarationDay(for: duzp))
    }

    @Test func code42IsPrevodemOrBankTransferAndOtherCodesAreNothing() {
        #expect(IsdocInvoiceBuilder.paymentMethod(code: "42", language: .cs) == "Převodem")
        #expect(IsdocInvoiceBuilder.paymentMethod(code: "42", language: .en) == "Bank transfer")
        #expect(IsdocInvoiceBuilder.paymentMethod(code: "10", language: .cs) == nil)
        #expect(IsdocInvoiceBuilder.paymentMethod(code: "", language: .en) == nil)
    }
}

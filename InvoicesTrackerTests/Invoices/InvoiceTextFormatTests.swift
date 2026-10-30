import Foundation
import Testing
@testable import InvoicesTracker

/// The text an invoice prints, per language: dates, amounts, quantities, country names and the labels of the layout. In
/// every expected string `\u{00A0}` is the no-break space and `\u{2212}` the minus sign.
struct InvoiceTextFormatTests {
    // MARK: Dates

    @Test func aCzechDateHasTwoDigitsForTheDayAndTheMonthAndANoBreakSpaceAfterEachDot() {
        #expect(InvoiceTextFormat.date(civilDate("2026-09-30"), language: .cs) == "30.\u{00A0}09.\u{00A0}2026")
        #expect(InvoiceTextFormat.date(civilDate("2026-10-05"), language: .cs) == "05.\u{00A0}10.\u{00A0}2026")
        #expect(InvoiceTextFormat.date(civilDate("2027-01-01"), language: .cs) == "01.\u{00A0}01.\u{00A0}2027")
    }

    @Test(arguments: [
        (1, "Jan"), (2, "Feb"), (3, "Mar"), (4, "Apr"), (5, "May"), (6, "Jun"),
        (7, "Jul"), (8, "Aug"), (9, "Sep"), (10, "Oct"), (11, "Nov"), (12, "Dec"),
    ])
    func anEnglishDateIsTheMonthAbbreviatedTheDayWithoutALeadingZeroAndTheYear(month: Int, name: String) throws {
        let day = try #require(CivilDate(year: 2026, month: month, day: 5))
        #expect(InvoiceTextFormat.date(day, language: .en) == "\(name) 5, 2026")
    }

    @Test func anEnglishDateKeepsTwoDigitDays() {
        #expect(InvoiceTextFormat.date(civilDate("2026-09-30"), language: .en) == "Sep 30, 2026")
        #expect(InvoiceTextFormat.date(civilDate("2026-12-31"), language: .en) == "Dec 31, 2026")
    }

    // MARK: Amounts

    @Test(arguments: [
        (450_000 as Int64, "CZK", "4\u{00A0}500,00\u{00A0}Kč"),
        (544_500, "CZK", "5\u{00A0}445,00\u{00A0}Kč"),
        (0, "CZK", "0,00\u{00A0}Kč"),
        (5, "CZK", "0,05\u{00A0}Kč"),
        (99, "CZK", "0,99\u{00A0}Kč"),
        (100_050, "CZK", "1\u{00A0}000,50\u{00A0}Kč"),
        (123_456_789, "CZK", "1\u{00A0}234\u{00A0}567,89\u{00A0}Kč"),
        (1_435_000, "USD", "14\u{00A0}350,00\u{00A0}USD"),
        (121_000, "EUR", "1\u{00A0}210,00\u{00A0}EUR"),
        (-450_000, "CZK", "\u{2212}4\u{00A0}500,00\u{00A0}Kč"),
        (-5, "USD", "\u{2212}0,05\u{00A0}USD"),
    ])
    func aCzechAmountHasNoBreakSpacesBetweenThousandsADecimalCommaAndTheCurrencyAfterIt(
        minor: Int64, code: String, text: String
    ) throws {
        let currency = try #require(CurrencyCode(code))
        #expect(InvoiceTextFormat.amount(minor, currency: currency, language: .cs) == text)
    }

    @Test(arguments: [
        (1_435_000 as Int64, "USD", "$\u{00A0}14,350.00"),
        (121_000, "EUR", "€\u{00A0}1,210.00"),
        (250_000, "GBP", "£\u{00A0}2,500.00"),
        (450_000, "CZK", "4,500.00\u{00A0}CZK"),
        (123_456, "CHF", "1,234.56\u{00A0}CHF"),
        (0, "USD", "$\u{00A0}0.00"),
        (5, "USD", "$\u{00A0}0.05"),
        (123_456_789, "USD", "$\u{00A0}1,234,567.89"),
        (-1_435_000, "USD", "-$\u{00A0}14,350.00"),
        (-5, "EUR", "-€\u{00A0}0.05"),
        (-450_000, "CZK", "-4,500.00\u{00A0}CZK"),
    ])
    func anEnglishAmountPutsTheSymbolBeforeTheNumberOrTheCodeAfterItWithACommaForThousands(
        minor: Int64, code: String, text: String
    ) throws {
        let currency = try #require(CurrencyCode(code))
        #expect(InvoiceTextFormat.amount(minor, currency: currency, language: .en) == text)
    }

    @Test func knownAmountsComeOutAsWritten() {
        #expect(InvoiceTextFormat.amount(1435000, currency: .usd, language: .en) == "$\u{00A0}14,350.00")
        #expect(InvoiceTextFormat.czkAmount(30650165, language: .en) == "306,501.65\u{00A0}CZK")
        #expect(InvoiceTextFormat.amount(450000, currency: .czk, language: .cs) == "4\u{00A0}500,00\u{00A0}Kč")
    }

    @Test func theCrownEquivalentIsAnAmountInCrownsInTheLanguageOfTheInvoice() {
        #expect(InvoiceTextFormat.czkAmount(30_650_165, language: .en) == "306,501.65\u{00A0}CZK")
        #expect(InvoiceTextFormat.czkAmount(30_650_165, language: .cs) == "306\u{00A0}501,65\u{00A0}Kč")
        #expect(InvoiceTextFormat.czkAmount(0, language: .en) == "0.00\u{00A0}CZK")
        #expect(InvoiceTextFormat.czkAmount(0, language: .cs) == "0,00\u{00A0}Kč")
    }

    @Test func amountsCoverTheWholeInt64Range() {
        #expect(
            InvoiceTextFormat.amount(Int64.max, currency: .czk, language: .cs)
                == "92\u{00A0}233\u{00A0}720\u{00A0}368\u{00A0}547\u{00A0}758,07\u{00A0}Kč")
        #expect(
            InvoiceTextFormat.amount(Int64.min, currency: .usd, language: .en)
                == "-$\u{00A0}92,233,720,368,547,758.08")
    }

    // MARK: Quantities

    @Test(arguments: [
        ("6.5", "6,5"), ("6.50", "6,5"), ("218", "218"), ("0.25", "0,25"), ("1.125", "1,125"), ("0", "0"),
        ("1234.5", "1234,5"), ("-2", "\u{2212}2"), ("-0.5", "\u{2212}0,5"),
    ])
    func aCzechQuantityHasADecimalCommaAndNoTrailingZerosOrGrouping(quantity: String, text: String) {
        #expect(InvoiceTextFormat.quantity(decimal(quantity), language: .cs) == text)
    }

    @Test(arguments: [
        ("6.5", "6.5"), ("6.50", "6.5"), ("218", "218"), ("0.25", "0.25"), ("1.125", "1.125"), ("0", "0"),
        ("1234.5", "1234.5"), ("-2", "-2"), ("-0.5", "-0.5"),
    ])
    func anEnglishQuantityHasADecimalPointAndNoTrailingZerosOrGrouping(quantity: String, text: String) {
        #expect(InvoiceTextFormat.quantity(decimal(quantity), language: .en) == text)
    }

    @Test func aKnownQuantityComesOutAsWritten() throws {
        #expect(InvoiceTextFormat.quantity(try #require(Decimal(string: "6.5")), language: .cs) == "6,5")
    }

    // MARK: Country names

    @Test func knownCountryNamesComeOutAsWritten() {
        #expect(InvoiceTextFormat.countryName("CZ", language: .en) == "Czech Republic")
        #expect(InvoiceTextFormat.countryName("US", language: .en) == "United States of America")
        #expect(InvoiceTextFormat.countryName("CZ", language: .cs) == "Česko")
    }

    @Test(arguments: [
        ("CZ", "Czech Republic", "Česko"),
        ("SK", "Slovakia", "Slovensko"),
        ("DE", "Germany", "Německo"),
        ("AT", "Austria", "Rakousko"),
        ("PL", "Poland", "Polsko"),
        ("GB", "United Kingdom", "Spojené království"),
        ("US", "United States of America", "Spojené státy americké"),
        ("CH", "Switzerland", "Švýcarsko"),
        ("IE", "Ireland", "Irsko"),
        ("NL", "Netherlands", "Nizozemsko"),
    ])
    func theCountriesAFreelancerInvoicesAreWrittenOutInBothLanguages(code: String, english: String, czech: String) {
        #expect(InvoiceTextFormat.countryName(code, language: .en) == english)
        #expect(InvoiceTextFormat.countryName(code, language: .cs) == czech)
    }

    @Test func aCodeIsReadInAnyCaseAndWithoutSurroundingSpaces() {
        #expect(InvoiceTextFormat.countryName("us", language: .en) == "United States of America")
        #expect(InvoiceTextFormat.countryName(" cz ", language: .cs) == "Česko")
    }

    @Test func aCountryOutsideTheTableTakesTheNameTheSystemHasForTheLanguage() {
        #expect(InvoiceTextFormat.countryName("JP", language: .en) == "Japan")
        #expect(InvoiceTextFormat.countryName("JP", language: .cs) == "Japonsko")
    }

    /// An imported client may keep a country as text: it prints as it was typed, not as a code in capitals.
    @Test func aCountryTypedAsTextIsPrintedAsTyped() {
        #expect(InvoiceTextFormat.countryName("Brazil", language: .en) == "Brazil")
        #expect(InvoiceTextFormat.countryName("Brazil", language: .cs) == "Brazil")
        #expect(InvoiceTextFormat.countryName("Česká republika", language: .cs) == "Česká republika")
        #expect(InvoiceTextFormat.countryName("  Nový Zéland ", language: .en) == "Nový Zéland")
        #expect(InvoiceTextFormat.countryName("United States", language: .cs) == "United States")
    }

    /// The system names ZZ "Unknown Region", which is not what an invoice should print.
    @Test func theCodeForAnUnknownRegionIsNotNamed() {
        #expect(InvoiceTextFormat.countryName("ZZ", language: .en) == "ZZ")
        #expect(InvoiceTextFormat.countryName(" zz ", language: .cs) == "zz")
    }

    @Test func aCodeWithNoNameIsPrintedAsItIsAndNothingStaysNothing() {
        #expect(InvoiceTextFormat.countryName("QQ", language: .en) == "QQ")
        #expect(InvoiceTextFormat.countryName("", language: .cs) == "")
        #expect(InvoiceTextFormat.countryName("  ", language: .en) == "")
    }

    // MARK: VAT rate and reference

    @Test func aVATRateIsAWholePercentWithANoBreakSpaceBeforeTheSign() {
        #expect(InvoiceTextFormat.vatRate(21) == "21\u{00A0}%")
        #expect(InvoiceTextFormat.vatRate(12) == "12\u{00A0}%")
        #expect(InvoiceTextFormat.vatRate(0) == "0\u{00A0}%")
    }

    @Test func theReferenceIsTheVariableSymbolOnACzechInvoiceAndTheNumberAsItIsOnAnEnglishOne() {
        #expect(InvoiceTextFormat.reference(ofNumber: "20260902", language: .cs) == "20260902")
        #expect(InvoiceTextFormat.reference(ofNumber: "2026-05-01", language: .cs) == "20260501")
        #expect(InvoiceTextFormat.reference(ofNumber: "Z20261001", language: .cs) == "20261001")
        #expect(InvoiceTextFormat.reference(ofNumber: "20260901", language: .en) == "20260901")
        #expect(InvoiceTextFormat.reference(ofNumber: "2026-05-01", language: .en) == "2026-05-01")
    }

    // MARK: Labels

    @Test func theCzechLabelsAreThoseOfTheLayout() {
        let expected = InvoiceLabels(
            document: "Faktura", subtitle: "DAŇOVÝ DOKLAD", supplier: "DODAVATEL", customer: "ODBĚRATEL",
            registrationNumber: "IČO", vatID: "DIČ", bankAccount: "Bankovní účet", iban: "IBAN", bic: "BIC",
            routingNumber: "Routing number", reference: "Variabilní symbol", paymentMethod: "Způsob platby",
            issueDate: "Datum vystavení", dueDate: "Datum splatnosti", taxableSupplyDate: "Datum zdan. plnění",
            vat: "DPH", unitPrice: "CENA ZA MJ", totalWithoutVAT: "CELKEM BEZ DPH", vatRate: "SAZBA", vatBase: "ZÁKLAD",
            quantityHeader: "Počet", unitHeader: "Jednotka", descriptionHeader: "Popis")
        #expect(InvoiceTextFormat.labels(.cs) == expected)
    }

    @Test func theEnglishLabelsAreThoseOfTheLayout() {
        let expected = InvoiceLabels(
            document: "Invoice", subtitle: "TAX DOCUMENT", supplier: "SUPPLIER", customer: "CUSTOMER",
            registrationNumber: "Reg. no.", vatID: "VAT ID", bankAccount: "Bank account", iban: "IBAN", bic: "BIC",
            routingNumber: "Routing number", reference: "Reference", paymentMethod: "Payment method",
            issueDate: "Issued on", dueDate: "Due on", taxableSupplyDate: "Date of taxable supply", vat: "VAT",
            unitPrice: "UNIT PRICE", totalWithoutVAT: "TOTAL W/O VAT", vatRate: "VAT RATE", vatBase: "VAT BASE",
            quantityHeader: "Quantity", unitHeader: "Unit", descriptionHeader: "Description")
        #expect(InvoiceTextFormat.labels(.en) == expected)
    }
}

import Foundation
import Testing
@testable import InvoicesTracker

/// What an invoice document is made of and the text it prints, before any drawing: the account of the invoice's
/// currency, the QR code that follows the flag of the invoice, and every line of the layout. The supplier, the clients
/// and the accounts are invented. In every expected string `\u{00A0}` is the no-break space.
struct InvoiceDocumentTests {
    private typealias Fixtures = InvoicePageFixtures

    // MARK: Making a document

    @Test func theDocumentKeepsTheInvoiceTheSupplierAndTheAccountOfTheInvoiceCurrency() {
        let crown = Fixtures.document(Fixtures.crownInvoice())
        #expect(crown.invoice == Fixtures.crownInvoice())
        #expect(crown.supplier == Fixtures.supplier)
        #expect(crown.account == Fixtures.czkAccount)

        #expect(Fixtures.document(Fixtures.dollarInvoice()).account == Fixtures.usdAccount)

        var euro = Fixtures.crownInvoice()
        euro.currency = .eur
        #expect(Fixtures.document(euro).account == Fixtures.eurAccount)
    }

    @Test func anInvoiceInACurrencyWithoutAnAccountHasNoAccount() {
        #expect(Fixtures.document(Fixtures.crownInvoice(), accounts: [Fixtures.usdAccount]).account == nil)
        #expect(Fixtures.document(Fixtures.crownInvoice(), accounts: []).account == nil)
    }

    @Test func aDocumentIsProvisionalOnlyWhileTheInvoiceIsADraft() {
        #expect(Fixtures.document(Fixtures.dollarInvoice(status: .draft)).isProvisional)
        #expect(!Fixtures.document(Fixtures.dollarInvoice(status: .issued)).isProvisional)
    }

    @Test func theQRCodeIsThePaymentCodeOfTheInvoiceWhenTheInvoiceWantsOne() throws {
        let invoice = Fixtures.crownInvoice()
        let made = Fixtures.document(invoice)

        #expect(made.qr == QRPayload.payload(for: invoice, supplier: Fixtures.supplier, accounts: Fixtures.accounts))
        let qr = try #require(made.text.qr)
        #expect(qr.label == "QR Platba")
        #expect(qr.payload.hasPrefix("SPD*1.0*ACC:CZ6508000000192000145399+GIBACZPX*AM:5445.00*CC:CZK*"))
    }

    @Test func thereIsNoQRCodeWhenTheInvoiceDoesNotWantOneWhateverTheAccountsAre() {
        var invoice = Fixtures.crownInvoice()
        invoice.qrEnabled = false

        let made = Fixtures.document(invoice)

        guard case .unavailable = made.qr else {
            Issue.record("An invoice without the flag got a QR code: \(made.qr)")
            return
        }
        #expect(made.text.qr == nil)
    }

    @Test func theQRCodeOfAnEnglishInvoiceInEurosIsLabelledInEnglish() throws {
        var invoice = Fixtures.crownInvoice()
        invoice.currency = .eur
        invoice.language = .en

        let qr = try #require(Fixtures.document(invoice).text.qr)

        #expect(qr.label == "QR payment")
        #expect(qr.payload.hasPrefix("BCD\n002\n1\nSCT\nCOBADEFFXXX\nJan Novák\nDE89370400440532013000\nEUR5445.00"))
    }

    @Test func aCurrencyWithoutAPaymentCodeHasNone() {
        var invoice = Fixtures.dollarInvoice()
        invoice.qrEnabled = true

        #expect(Fixtures.document(invoice).text.qr == nil)
    }

    @Test func theFileIsNamedAfterTheNumberWithoutCharactersAFileNameCannotHave() {
        #expect(Fixtures.document(Fixtures.crownInvoice()).fileName == "20260902.pdf")
        var imported = Fixtures.crownInvoice()
        imported.number = "2026-05-01"
        #expect(Fixtures.document(imported).fileName == "2026-05-01.pdf")
        imported.number = "FV/2026:7"
        #expect(Fixtures.document(imported).fileName == "FV-2026-7.pdf")
    }

    // MARK: A Czech invoice in crowns

    @Test func aCzechInvoiceInCrownsPrintsEveryLineInCzech() {
        let text = Fixtures.document(Fixtures.crownInvoice()).text

        #expect(text.labels == InvoiceTextFormat.labels(.cs))
        #expect(text.number == "20260902")
        #expect(text.supplier.name == "Jan Novák")
        #expect(text.supplier.lines == ["Dlouhá 12", "110 00 Praha"])
        #expect(
            text.supplier.identifiers == [
                InvoiceField(label: "IČO", value: "11223344"), InvoiceField(label: "DIČ", value: "CZ11223344"),
            ])
        #expect(text.customer.name == "Alfa Systems s.r.o.")
        #expect(text.customer.lines == ["Hlavní 1", "261 01 Příbram"])
        #expect(
            text.customer.identifiers == [
                InvoiceField(label: "IČO", value: "12345678"), InvoiceField(label: "DIČ", value: "CZ12345678"),
            ])
        #expect(
            text.paymentRows == [
                InvoiceField(label: "Bankovní účet", value: "1234567890/0800"),
                InvoiceField(label: "IBAN", value: "CZ65 0800 0000 1920 0014 5399"),
                InvoiceField(label: "Variabilní symbol", value: "20260902"),
                InvoiceField(label: "Způsob platby", value: "Převodem"),
            ])
        #expect(
            text.dateRows == [
                InvoiceField(label: "Datum vystavení", value: "30.\u{00A0}09.\u{00A0}2026"),
                InvoiceField(label: "Datum splatnosti", value: "14.\u{00A0}10.\u{00A0}2026"),
                InvoiceField(label: "Datum zdan. plnění", value: "30.\u{00A0}09.\u{00A0}2026"),
            ])
        #expect(
            text.items == [
                InvoiceDocumentText.Item(
                    quantity: "7,5", unit: "hod", description: "Vývoj", vatRate: "21\u{00A0}%",
                    unitPrice: "600,00\u{00A0}Kč", amount: "4\u{00A0}500,00\u{00A0}Kč")
            ])
        #expect(
            text.summary
                == InvoiceDocumentText.Summary(
                    vatRate: "21\u{00A0}%", base: "4\u{00A0}500,00\u{00A0}Kč", vat: "945,00\u{00A0}Kč",
                    total: "5\u{00A0}445,00\u{00A0}Kč", baseInCrowns: nil, vatInCrowns: nil))
        #expect(text.note == nil)
        #expect(text.legalFooter == "Fyzická osoba zapsaná v živnostenském rejstříku.")
    }

    @Test func theVariableSymbolOfAnImportedNumberIsItsDigits() {
        var invoice = Fixtures.crownInvoice()
        invoice.number = "2026-05-01"

        let text = Fixtures.document(invoice).text

        #expect(text.number == "2026-05-01")
        #expect(text.paymentRows.contains(InvoiceField(label: "Variabilní symbol", value: "20260501")))
    }

    @Test func theLegalFooterIsTheSuppliersAndOnlyOnCzechInvoices() {
        var supplier = Fixtures.supplier
        supplier.czechFooter = "Zapsán v živnostenském rejstříku u úřadu v Praze."
        #expect(
            Fixtures.document(Fixtures.crownInvoice(), supplier: supplier).text.legalFooter
                == "Zapsán v živnostenském rejstříku u úřadu v Praze.")

        var english = Fixtures.crownInvoice()
        english.language = .en
        #expect(Fixtures.document(english, supplier: supplier).text.legalFooter == nil)

        supplier.czechFooter = "  "
        #expect(Fixtures.document(Fixtures.crownInvoice(), supplier: supplier).text.legalFooter == nil)
    }

    @Test func theNotePrintsAsWrittenWithoutBlankLinesAroundIt() {
        var invoice = Fixtures.crownInvoice()
        invoice.note = "\n  První řádek\n\nTřetí řádek  \n\n"
        #expect(Fixtures.document(invoice).text.note == "První řádek\n\nTřetí řádek")

        invoice.note = " \n "
        #expect(Fixtures.document(invoice).text.note == nil)
    }

    @Test func linesWithNothingInThemAreLeftOut() {
        var supplier = Fixtures.supplier
        supplier.street = ""
        supplier.ico = ""
        supplier.dic = ""
        var invoice = Fixtures.crownInvoice()
        invoice.client.dic = ""
        invoice.client.postcode = ""
        invoice.paymentMethod = ""

        let text = Fixtures.document(invoice, supplier: supplier).text

        #expect(text.supplier.lines == ["110 00 Praha"])
        #expect(text.supplier.identifiers.isEmpty)
        #expect(text.customer.lines == ["Hlavní 1", "Příbram"])
        #expect(text.customer.identifiers == [InvoiceField(label: "IČO", value: "12345678")])
        #expect(text.paymentRows.map(\.label) == ["Bankovní účet", "IBAN", "Variabilní symbol"])
    }

    // MARK: Countries

    @Test func aCzechInvoiceLeavesOutCzechiaAndNamesOtherCountriesInCzech() {
        var supplier = Fixtures.supplier
        supplier.country = "SK"
        var invoice = Fixtures.crownInvoice()
        invoice.client.country = "US"

        let text = Fixtures.document(invoice, supplier: supplier).text

        #expect(text.supplier.lines == ["Dlouhá 12", "110 00 Praha", "Slovensko"])
        #expect(text.customer.lines == ["Hlavní 1", "261 01 Příbram", "Spojené státy americké"])
    }

    @Test func anEnglishInvoiceNamesEveryCountryInEnglishCzechRepublicIncluded() {
        var invoice = Fixtures.crownInvoice()
        invoice.language = .en

        let text = Fixtures.document(invoice).text

        #expect(text.supplier.lines == ["Dlouhá 12", "110 00 Praha", "Czech Republic"])
        #expect(text.customer.lines == ["Hlavní 1", "261 01 Příbram", "Czech Republic"])
    }

    @Test func aCountryTypedAsTextIsPrintedAsTypedAndNotAsACode() {
        var supplier = Fixtures.supplier
        supplier.country = "Slovensko"
        var invoice = Fixtures.crownInvoice()
        invoice.client.country = "Brazil"

        let text = Fixtures.document(invoice, supplier: supplier).text

        #expect(text.supplier.lines.last == "Slovensko")
        #expect(text.customer.lines.last == "Brazil")
    }

    // MARK: VAT

    /// 7,5 hours at 600,00 Kč are 4 500,00 Kč whatever the VAT mode is.
    @Test(arguments: [
        (VatMode.domestic21, "21\u{00A0}%", "945,00\u{00A0}Kč", "5\u{00A0}445,00\u{00A0}Kč"),
        (VatMode.domestic12, "12\u{00A0}%", "540,00\u{00A0}Kč", "5\u{00A0}040,00\u{00A0}Kč"),
        (VatMode.outsideCountry, "0\u{00A0}%", "0,00\u{00A0}Kč", "4\u{00A0}500,00\u{00A0}Kč"),
        (VatMode.euReverseCharge, "0\u{00A0}%", "0,00\u{00A0}Kč", "4\u{00A0}500,00\u{00A0}Kč"),
        (VatMode.none, "0\u{00A0}%", "0,00\u{00A0}Kč", "4\u{00A0}500,00\u{00A0}Kč"),
    ])
    func theVATModeDecidesTheRateTheVATAndTheTotalOfAnInvoiceInCrowns(
        mode: VatMode, rate: String, vat: String, total: String
    ) {
        var invoice = Fixtures.crownInvoice()
        invoice.vatMode = mode

        let text = Fixtures.document(invoice).text

        #expect(text.summary.vatRate == rate)
        #expect(text.summary.base == "4\u{00A0}500,00\u{00A0}Kč")
        #expect(text.summary.vat == vat)
        #expect(text.summary.total == total)
        #expect(text.items.map(\.vatRate) == [rate])
    }

    @Test func twelvePercentVATOnAnInvoiceInDollarsHasItsCrownEquivalentsToo() {
        var invoice = Fixtures.dollarInvoice()
        invoice.vatMode = .domestic12

        let summary = Fixtures.document(invoice).text.summary

        // 14 350,00 USD and 1 722,00 USD VAT at 21,359: 306 501,65 Kč and 36 780,20 Kč.
        #expect(summary.vatRate == "12\u{00A0}%")
        #expect(summary.base == "$\u{00A0}14,350.00")
        #expect(summary.vat == "$\u{00A0}1,722.00")
        #expect(summary.total == "$\u{00A0}16,072.00")
        #expect(summary.baseInCrowns == "306,501.65\u{00A0}CZK")
        #expect(summary.vatInCrowns == "36,780.20\u{00A0}CZK")
    }

    // MARK: The bank account

    @Test func anAccountInCrownsPrintsItsNumberAndIBANButNotTheBIC() {
        let rows = Fixtures.document(Fixtures.crownInvoice()).text.paymentRows

        #expect(
            rows.prefix(2) == [
                InvoiceField(label: "Bankovní účet", value: "1234567890/0800"),
                InvoiceField(label: "IBAN", value: "CZ65 0800 0000 1920 0014 5399"),
            ])
        #expect(!rows.contains { $0.label == "BIC" })
    }

    @Test func anAccountInDollarsPrintsItsNumberAndRoutingNumberButNotTheTypeOfAccount() {
        let rows = Fixtures.document(Fixtures.dollarInvoice()).text.paymentRows

        #expect(
            rows.prefix(2) == [
                InvoiceField(label: "Bank account", value: "000123456789"),
                InvoiceField(label: "Routing number", value: "123456789"),
            ])
        #expect(!rows.contains { $0.value == "Checking" })
    }

    /// The data of the account has the name and address of its bank, and no row of the invoice shows it.
    @Test func aUSDInvoicePrintsNoBankNameOrAddress() {
        let account = Fixtures.dollarAccount(bankNameAndAddress: "Chase Bank, 270 Park Ave, New York")

        let rows = Fixtures.document(Fixtures.dollarInvoice(), accounts: [account]).text.paymentRows

        #expect(rows.contains(InvoiceField(label: "Bank account", value: "000123456789")))
        #expect(rows.contains(InvoiceField(label: "Routing number", value: "123456789")))
        #expect(!rows.contains { $0.value.contains("Chase") }, "The bank is printed: \(rows)")
        #expect(rows.map(\.label) == ["Bank account", "Routing number", "Reference", "Payment method"])
    }

    @Test func anAccountInEurosPrintsItsIBANAndBIC() {
        var invoice = Fixtures.crownInvoice()
        invoice.currency = .eur

        let rows = Fixtures.document(invoice).text.paymentRows

        #expect(
            rows.prefix(2) == [
                InvoiceField(label: "IBAN", value: "DE89 3704 0044 0532 0130 00"),
                InvoiceField(label: "BIC", value: "COBADEFFXXX"),
            ])
    }

    @Test func fieldsTheAccountDoesNotHaveAreNotPrinted() {
        let sparse = [BankAccount(currency: .usd, accountNumber: "000123456789")]

        let rows = Fixtures.document(Fixtures.dollarInvoice(), accounts: sparse).text.paymentRows

        #expect(
            rows == [
                InvoiceField(label: "Bank account", value: "000123456789"),
                InvoiceField(label: "Reference", value: "20260901"),
                InvoiceField(label: "Payment method", value: "ACH (USD)"),
            ])
    }

    @Test func anInvoiceWithoutAnAccountPrintsOnlyTheReferenceAndTheMethodOfPayment() {
        let rows = Fixtures.document(Fixtures.dollarInvoice(), accounts: [Fixtures.czkAccount]).text.paymentRows

        #expect(rows.map(\.label) == ["Reference", "Payment method"])
    }

    /// Nastavení › Moje údaje has boxes for accounts in crowns, dollars and euros alone, but imported data can hold an
    /// account in another currency: an invoice in that currency prints it, whatever numbers it has, and no name or
    /// address of its bank.
    @Test func anAccountInAnotherCurrencyPrintsItsNumbersButNoBankNameOrAddress() throws {
        let pounds = try #require(CurrencyCode("GBP"))
        var invoice = Fixtures.crownInvoice()
        invoice.currency = pounds
        let account = BankAccount(
            currency: pounds, accountNumber: "12345678", iban: "GB33BUKB20201555555555", bic: "BUKBGB22",
            routingNumber: "200000", bankNameAndAddress: "Chase Bank, 270 Park Ave, New York")

        let document = Fixtures.document(invoice, accounts: Fixtures.accounts + [account])

        #expect(document.account == account)
        #expect(
            document.text.paymentRows == [
                InvoiceField(label: "Bankovní účet", value: "12345678"),
                InvoiceField(label: "IBAN", value: "GB33BUKB20201555555555"),
                InvoiceField(label: "BIC", value: "BUKBGB22"),
                InvoiceField(label: "Routing number", value: "200000"),
                InvoiceField(label: "Variabilní symbol", value: "20260902"),
                InvoiceField(label: "Způsob platby", value: "Převodem"),
            ])
    }

    /// Without an account in its currency such an invoice prints none, as the form of its template says.
    @Test func anInvoiceInAnotherCurrencyWithoutAnAccountInItPrintsNone() throws {
        var invoice = Fixtures.crownInvoice()
        invoice.currency = try #require(CurrencyCode("GBP"))

        let document = Fixtures.document(invoice)

        #expect(document.account == nil)
        #expect(
            document.text.paymentRows == [
                InvoiceField(label: "Variabilní symbol", value: "20260902"),
                InvoiceField(label: "Způsob platby", value: "Převodem"),
            ])
    }

    // MARK: An English invoice in dollars

    @Test func anEnglishInvoiceInDollarsPrintsEveryLineInEnglishWithTheCrownEquivalents() {
        let text = Fixtures.document(Fixtures.dollarInvoice()).text

        #expect(text.labels == InvoiceTextFormat.labels(.en))
        #expect(text.number == "20260901")
        #expect(text.customer.name == "Bravo Labs, Inc.")
        #expect(text.customer.lines == ["100 Congress Avenue", "78701 Austin, TX", "United States of America"])
        #expect(text.customer.identifiers.isEmpty)
        #expect(
            text.paymentRows.suffix(2) == [
                InvoiceField(label: "Reference", value: "20260901"),
                InvoiceField(label: "Payment method", value: "ACH (USD)"),
            ])
        #expect(
            text.dateRows == [
                InvoiceField(label: "Issued on", value: "Sep 30, 2026"),
                InvoiceField(label: "Due on", value: "Oct 30, 2026"),
                InvoiceField(label: "Date of taxable supply", value: "Sep 30, 2026"),
            ])
        #expect(
            text.items == [
                InvoiceDocumentText.Item(
                    quantity: "205", unit: "h", description: "Software development", vatRate: "0\u{00A0}%",
                    unitPrice: "$\u{00A0}70.00", amount: "$\u{00A0}14,350.00")
            ])
        #expect(
            text.summary
                == InvoiceDocumentText.Summary(
                    vatRate: "0\u{00A0}%", base: "$\u{00A0}14,350.00", vat: "$\u{00A0}0.00",
                    total: "$\u{00A0}14,350.00", baseInCrowns: "306,501.65\u{00A0}CZK",
                    vatInCrowns: "0.00\u{00A0}CZK"))
        #expect(text.legalFooter == nil)
        #expect(text.qr == nil)
    }

    @Test func theCrownEquivalentsAreWorkedOutFromTheRateOfTheInvoiceAndRoundedOnTheirOwn() {
        var invoice = Fixtures.dollarInvoice()
        invoice.vatMode = .domestic21
        invoice.items = [InvoiceItem(description: "Práce", quantity: decimal("1"), unit: "ks", unitPriceMinor: 12_345)]

        let summary = Fixtures.document(invoice).text.summary

        // 123,45 USD at 21,359 is 2 636,76855 Kč and the VAT of 25,92 USD is 553,62528 Kč, each rounded half up.
        #expect(summary.baseInCrowns == "2,636.77\u{00A0}CZK")
        #expect(summary.vatInCrowns == "553.63\u{00A0}CZK")
    }

    @Test func theCrownEquivalentsOfADraftAreMarkedWithAnApproximatelySign() {
        let summary = Fixtures.document(Fixtures.dollarInvoice(status: .draft)).text.summary

        #expect(summary.baseInCrowns == "≈\u{00A0}306,501.65\u{00A0}CZK")
        #expect(summary.vatInCrowns == "≈\u{00A0}0.00\u{00A0}CZK")
    }

    @Test func thereAreNoCrownEquivalentsWithoutTheRateOfTheInvoiceOrForAnInvoiceInCrowns() {
        var withoutRate = Fixtures.dollarInvoice()
        withoutRate.invoiceRate = nil
        #expect(Fixtures.document(withoutRate).text.summary.baseInCrowns == nil)
        #expect(Fixtures.document(withoutRate).text.summary.vatInCrowns == nil)

        var wrongCurrency = Fixtures.dollarInvoice()
        wrongCurrency.invoiceRate = storedRate("EUR", "24.50", declaredOn: "2026-09-30")
        #expect(Fixtures.document(wrongCurrency).text.summary.baseInCrowns == nil)

        var crowns = Fixtures.crownInvoice()
        crowns.invoiceRate = storedRate("USD", "21.359", declaredOn: "2026-09-30")
        #expect(Fixtures.document(crowns).text.summary.baseInCrowns == nil)
    }
}

import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import InvoicesTracker

/// The texts of the payment codes and the pictures made from them. The IBANs are the well-known example ones, and the
/// supplier is invented.
struct QRPayloadTests {
    // MARK: Helpers

    private static let czkAccount = BankAccount(currency: .czk, iban: "CZ65 0800 0000 1920 0014 5399", bic: "GIBACZPX")
    private static let eurAccount = BankAccount(currency: .eur, iban: "DE89 3704 0044 0532 0130 00", bic: "COBADEFFXXX")
    private static let usdAccount = BankAccount(
        currency: .usd, accountNumber: "000123456789", routingNumber: "123456789", accountType: "Checking"
    )
    private static let supplier = Supplier(name: "Jan Novák")

    /// The QR Platba of the fixture invoice up to its variable symbol: the CZK account and the total of 5 445,00 Kč.
    private static let fixtureHead = "SPD*1.0*ACC:CZ6508000000192000145399+GIBACZPX*AM:5445.00*CC:CZK*"

    /// The EPC code of an invoice of the fixtures up to its amount: the euro account and the supplier's name.
    private static let epcHead = "BCD\n002\n1\nSCT\nCOBADEFFXXX\nJan Novák\nDE89370400440532013000\n"

    /// The QR Platba of the first example in which only the given values differ.
    private func spayd(
        iban: String = "CZ6508000000192000145399", bic: String = "GIBACZPX", amountMinor: Int64 = 544_500,
        variableSymbol: String = "20260902", due: String = "2026-10-30", message: String = "Faktura 20260902"
    ) -> String {
        QRPayload.spayd(
            iban: iban, bic: bic, amountMinor: amountMinor, variableSymbol: variableSymbol, due: civilDate(due),
            message: message
        )
    }

    /// The EPC code of the example in which only the given values differ.
    private func epc(
        name: String = "Jan Novák", iban: String = "DE89370400440532013000", bic: String = "COBADEFFXXX",
        amountMinor: Int64 = 121_000, remittance: String = "Invoice 20261001"
    ) -> String {
        QRPayload.epc(name: name, iban: iban, bic: bic, amountMinor: amountMinor, remittance: remittance)
    }

    /// The value of the field `key` of a QR Platba, or nil when it has no such field.
    private func field(_ key: String, of spayd: String) -> String? {
        spayd.split(separator: "*", omittingEmptySubsequences: false)
            .first { $0.hasPrefix(key + ":") }
            .map { String($0.dropFirst(key.count + 1)) }
    }

    /// The lines of an EPC code, the empty ones included.
    private func lines(of epc: String) -> [String] {
        epc.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
    }

    private func payload(of result: QRPayloadResult) -> String? {
        guard case .payload(let text, label: _) = result else { return nil }
        return text
    }

    /// An invoice in `currency` of one item at `total` minor units and without VAT, so that this is its total.
    private func invoice(in currency: CurrencyCode, total: Int64) -> Invoice {
        Invoice.fixture(currency: currency, items: [.fixture("1", at: total)], vatMode: VatMode.none)
    }

    /// The code of `invoice` from the accounts of all three currencies and the invented supplier.
    private func result(for invoice: Invoice, supplier: Supplier = Self.supplier) -> QRPayloadResult {
        QRPayload.payload(
            for: invoice, supplier: supplier, accounts: [Self.czkAccount, Self.eurAccount, Self.usdAccount]
        )
    }

    // MARK: QR Platba

    @Test func qrPlatbaHasTheFieldsOfSpaydInOrder() {
        let payload = QRPayload.spayd(
            iban: "CZ6508000000192000145399", bic: "GIBACZPX", amountMinor: 544500, variableSymbol: "20260902",
            due: civilDate("2026-10-30"), message: "Faktura 20260902"
        )

        #expect(
            payload
                == "SPD*1.0*ACC:CZ6508000000192000145399+GIBACZPX*AM:5445.00*CC:CZK*"
                + "X-VS:20260902*DT:20261030*MSG:FAKTURA 20260902"
        )
    }

    @Test func theBicIsLeftOutWhenThereIsNoneAndAStarInTheMessageBecomesASpace() {
        let payload = QRPayload.spayd(
            iban: "CZ6508000000192000145399", bic: "", amountMinor: 5, variableSymbol: "1",
            due: civilDate("2026-01-05"), message: "Příliš*žluťoučký"
        )

        #expect(
            payload
                == "SPD*1.0*ACC:CZ6508000000192000145399*AM:0.05*CC:CZK*X-VS:1*DT:20260105*MSG:PRILIS ZLUTOUCKY"
        )
    }

    @Test(arguments: [
        (0 as Int64, "0.00"), (5, "0.05"), (99, "0.99"), (100, "1.00"), (101, "1.01"), (1_000, "10.00"),
        (544_500, "5445.00"), (100_050, "1000.50"), (123_456_789, "1234567.89"),
        (Int64.max, "92233720368547758.07"), (-5, "-0.05"), (Int64.min, "-92233720368547758.08"),
    ])
    func theAmountHasAPointAndExactlyTwoDecimalsWithoutGrouping(amountMinor: Int64, text: String) {
        #expect(field("AM", of: spayd(amountMinor: amountMinor)) == text)
    }

    @Test func theAccountIsTheIbanAndTheBicWithoutSpacesInUpperCase() {
        let payload = spayd(iban: "cz65 0800 0000 1920 0014 5399", bic: " giba cz\u{00A0}px ")

        #expect(field("ACC", of: payload) == "CZ6508000000192000145399+GIBACZPX")
    }

    @Test func aBicOfNothingButSpacesIsNoBic() {
        #expect(field("ACC", of: spayd(bic: " \u{00A0} ")) == "CZ6508000000192000145399")
    }

    @Test func theDueDateIsWrittenWithoutSeparators() {
        #expect(field("DT", of: spayd(due: "2026-10-30")) == "20261030")
        #expect(field("DT", of: spayd(due: "2027-01-05")) == "20270105")
        #expect(field("DT", of: spayd(due: "2026-12-31")) == "20261231")
    }

    // MARK: Variable symbol

    @Test func theVariableSymbolKeepsTheDigitsOfWhatItIsGiven() {
        #expect(field("X-VS", of: spayd(variableSymbol: "2026-09-02")) == "20260902")
        #expect(field("X-VS", of: spayd(variableSymbol: "Z20261001")) == "20261001")
        #expect(field("X-VS", of: spayd(variableSymbol: "0001")) == "0001")
    }

    @Test func aVariableSymbolOfTenDigitsIsKept() {
        #expect(field("X-VS", of: spayd(variableSymbol: "1234567890")) == "1234567890")
        #expect(field("X-VS", of: spayd(variableSymbol: "2026/09/0001")) == "2026090001")
    }

    /// A variable symbol is at most ten digits. Cutting digits off would pay another invoice, so the field is left out
    /// and the payer types the symbol in.
    @Test func aVariableSymbolOfMoreThanTenDigitsIsLeftOutNotCut() {
        let withoutSymbol =
            "SPD*1.0*ACC:CZ6508000000192000145399+GIBACZPX*AM:5445.00*CC:CZK*DT:20261030*MSG:FAKTURA 20260902"

        #expect(spayd(variableSymbol: "12345678901") == withoutSymbol)
        #expect(spayd(variableSymbol: "2026-09-0001-2") == withoutSymbol)
    }

    @Test(arguments: ["", "abc", " ", "-"])
    func aVariableSymbolWithoutDigitsIsLeftOut(symbol: String) {
        #expect(field("X-VS", of: spayd(variableSymbol: symbol)) == nil)
        #expect(spayd(variableSymbol: symbol).contains("X-VS") == false)
    }

    // MARK: Message of the QR Platba

    @Test func theMessageIsUpperCaseWithoutDiacritics() {
        let pangram = spayd(message: "Příliš žluťoučký kůň úpěl ďábelské ódy")

        #expect(field("MSG", of: pangram) == "PRILIS ZLUTOUCKY KUN UPEL DABELSKE ODY")
        #expect(field("MSG", of: spayd(message: "Faktura 2026-09-02")) == "FAKTURA 2026-09-02")
    }

    @Test func everyStarOfTheMessageBecomesASpaceAndRunsOfSpacesBecomeOne() {
        #expect(field("MSG", of: spayd(message: "A**B * C")) == "A B C")
        #expect(field("MSG", of: spayd(message: "*Faktura*")) == "FAKTURA")
        #expect(field("MSG", of: spayd(message: "  Faktura\u{00A0}\u{00A0}2026\t09\n")) == "FAKTURA 2026 09")
    }

    @Test func theMessageHasNothingButAsciiLeft() {
        // The euro sign, the dash and the quotes have no ASCII form: each becomes a space, like a star.
        #expect(field("MSG", of: spayd(message: "Cena: 5 € – ß“x”")) == "CENA: 5 SS X")
        #expect(field("MSG", of: spayd(message: "a\u{0001}b\u{007F}c")) == "A B C")
    }

    @Test func theMessageIsAtMostSixtyCharactersLong() {
        let sixty = String(repeating: "A", count: 60)

        #expect(field("MSG", of: spayd(message: sixty)) == sixty)
        #expect(field("MSG", of: spayd(message: sixty + "B")) == sixty)
        #expect(field("MSG", of: spayd(message: String(repeating: "Příliš žluťoučký kůň ", count: 5)))
            == "PRILIS ZLUTOUCKY KUN PRILIS ZLUTOUCKY KUN PRILIS ZLUTOUCKY K")
    }

    @Test func aMessageCutAtASpaceDoesNotEndInOne() {
        let fiftyNine = String(repeating: "A", count: 59)

        #expect(field("MSG", of: spayd(message: fiftyNine + " BCD")) == fiftyNine)
    }

    /// SPAYD writes a `*` inside a value as `%2A`, so a reader that decodes values would take a `%` of the message for
    /// the start of an escape.
    @Test func everyPercentSignOfTheMessageBecomesASpaceLikeAStar() {
        #expect(field("MSG", of: spayd(message: "Sleva 10% z 100%")) == "SLEVA 10 Z 100")
        #expect(field("MSG", of: spayd(message: "A%2AB")) == "A 2AB")
        #expect(field("MSG", of: spayd(message: "%Faktura%")) == "FAKTURA")
        #expect(field("MSG", of: spayd(message: "a*b%c")) == "A B C")
    }

    @Test(arguments: ["", " ", "***", "€ – “”", "%", "*%*"])
    func aMessageOfNothingLeavesTheFieldOut(message: String) {
        let payload = spayd(message: message)

        #expect(payload == "SPD*1.0*ACC:CZ6508000000192000145399+GIBACZPX*AM:5445.00*CC:CZK*X-VS:20260902*DT:20261030")
    }

    /// `*` separates the fields, so a value that holds one would cut the code in two.
    @Test func noValueHoldsAStar() {
        let payload = spayd(iban: "CZ65*0800", bic: "GIBA*CZPX", variableSymbol: "12*34", message: "a*b")

        #expect(payload.split(separator: "*", omittingEmptySubsequences: false).count == 8)
        #expect(payload == "SPD*1.0*ACC:CZ650800+GIBACZPX*AM:5445.00*CC:CZK*X-VS:1234*DT:20261030*MSG:A B")
    }

    @Test func noValueHoldsAPercentSign() {
        let payload = spayd(iban: "CZ65%0800", bic: "GIBA%CZPX", variableSymbol: "12%34", message: "5 %")

        #expect(payload == "SPD*1.0*ACC:CZ650800+GIBACZPX*AM:5445.00*CC:CZK*X-VS:1234*DT:20261030*MSG:5")
        #expect(payload.contains("%") == false)
    }

    // MARK: EPC

    @Test func anEpcCodeHasTheElevenLinesOfVersionTwo() {
        let payload = QRPayload.epc(
            name: "Jan Novák", iban: "DE89370400440532013000", bic: "COBADEFFXXX", amountMinor: 121000,
            remittance: "Invoice 20261001"
        )

        #expect(
            payload
                == "BCD\n002\n1\nSCT\nCOBADEFFXXX\nJan Novák\nDE89370400440532013000\n"
                + "EUR1210.00\n\n\nInvoice 20261001"
        )
    }

    @Test func theBicLineIsEmptyWithoutABic() {
        let payload = epc(bic: "")

        #expect(payload == "BCD\n002\n1\nSCT\n\nJan Novák\nDE89370400440532013000\nEUR1210.00\n\n\nInvoice 20261001")
        #expect(lines(of: payload).count == 11)
    }

    @Test func theEpcAccountIsWrittenWithoutSpacesInUpperCase() {
        let payload = epc(iban: "de89 3704 0044 0532 0130 00", bic: " cobadeffxxx ")

        #expect(lines(of: payload)[4] == "COBADEFFXXX")
        #expect(lines(of: payload)[6] == "DE89370400440532013000")
    }

    @Test(arguments: [
        (0 as Int64, "EUR0.00"), (5, "EUR0.05"), (100, "EUR1.00"), (121_000, "EUR1210.00"),
        (123_456_789, "EUR1234567.89"), (Int64.max, "EUR92233720368547758.07"), (-5, "EUR-0.05"),
    ])
    func theEpcAmountIsEurAndTwoDecimalsWithoutGrouping(amountMinor: Int64, text: String) {
        #expect(lines(of: epc(amountMinor: amountMinor))[7] == text)
    }

    @Test func theNameIsCutAtSeventyCharactersAndTheRemittanceAtOneHundredForty() {
        let name70 = String(repeating: "N", count: 70)
        let remittance140 = String(repeating: "R", count: 140)

        #expect(lines(of: epc(name: name70, remittance: remittance140))[5] == name70)
        #expect(lines(of: epc(name: name70, remittance: remittance140))[10] == remittance140)
        #expect(lines(of: epc(name: name70 + "N", remittance: remittance140 + "R"))[5] == name70)
        #expect(lines(of: epc(name: name70 + "N", remittance: remittance140 + "R"))[10] == remittance140)
    }

    @Test func aCutNeverEndsInASpace() {
        let name = String(repeating: "N", count: 69) + " Novák"

        #expect(lines(of: epc(name: name))[5] == String(repeating: "N", count: 69))
    }

    /// The cut falls between two characters as a person sees them: a letter keeps its accent, and a family or a
    /// face is never torn into its parts.
    @Test func aCutNeverSplitsACharacter() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let accented = String(repeating: "a", count: 69) + "e\u{0301}x"
        let face = String(repeating: "a", count: 69) + "\u{1F600}b"
        let crowd = String(repeating: "a", count: 68) + family

        #expect(lines(of: epc(name: accented))[5] == String(repeating: "a", count: 69))
        #expect(lines(of: epc(name: face))[5] == String(repeating: "a", count: 69) + "\u{1F600}")
        #expect(lines(of: epc(name: crowd))[5] == String(repeating: "a", count: 68))
        #expect(lines(of: epc(remittance: String(repeating: "a", count: 139) + "e\u{0301}"))[10]
            == String(repeating: "a", count: 139))
    }

    @Test func aLineBreakInATextDoesNotAddALine() {
        let payload = epc(name: "Jan\nNovák\r\n", remittance: "Invoice\r\n2026\u{2028}1001\n\n")

        #expect(lines(of: payload).count == 11)
        #expect(lines(of: payload)[5] == "Jan Novák")
        #expect(lines(of: payload)[10] == "Invoice 2026 1001")
    }

    // MARK: Payload of an invoice

    @Test func aCzkInvoiceGetsQRPlatbaWithTheTotalAndTheDueDate() {
        let result = QRPayload.payload(for: .fixture(), supplier: Self.supplier, accounts: [Self.czkAccount])

        // 7,5 hours at 600,00 Kč and 21 % VAT: 5 445,00 Kč, due on 14 October 2026.
        #expect(
            result == .payload(Self.fixtureHead + "X-VS:20260901*DT:20261014*MSG:FAKTURA 20260901", label: "QR Platba")
        )
    }

    @Test func anEnglishInvoiceLabelsItsCodeInEnglishAndWritesTheMessageInEnglish() {
        var invoice = Invoice.fixture()
        invoice.language = .en

        let result = QRPayload.payload(for: invoice, supplier: Self.supplier, accounts: [Self.czkAccount])

        #expect(
            result == .payload(Self.fixtureHead + "X-VS:20260901*DT:20261014*MSG:INVOICE 20260901", label: "QR payment")
        )
    }

    @Test func theVariableSymbolIsTheDigitsOfTheNumberAndTheMessageKeepsTheNumberAsPrinted() {
        let result = QRPayload.payload(
            for: .fixture(number: "2026-09-02"), supplier: Self.supplier, accounts: [Self.czkAccount]
        )

        let text = payload(of: result)
        #expect(text.flatMap { field("X-VS", of: $0) } == "20260902")
        #expect(text.flatMap { field("MSG", of: $0) } == "FAKTURA 2026-09-02")
    }

    @Test func aNumberOfMoreThanTenDigitsLeavesTheVariableSymbolOut() {
        let result = QRPayload.payload(
            for: .fixture(number: "20260902001"), supplier: Self.supplier, accounts: [Self.czkAccount]
        )

        let text = payload(of: result)
        #expect(text != nil)
        #expect(text.flatMap { field("X-VS", of: $0) } == nil)
        #expect(text.flatMap { field("MSG", of: $0) } == "FAKTURA 20260902001")
    }

    @Test func aStarInTheNumberDoesNotBreakTheCode() {
        let result = QRPayload.payload(
            for: .fixture(number: "A*20260902"), supplier: Self.supplier, accounts: [Self.czkAccount]
        )

        #expect(
            result
                == .payload(Self.fixtureHead + "X-VS:20260902*DT:20261014*MSG:FAKTURA A 20260902", label: "QR Platba")
        )
    }

    @Test func aCzkInvoiceWithoutAnIbanHasNoCode() {
        let reason = QRPayloadResult.unavailable("Doplňte IBAN účtu v Kč v Nastavení › Moje údaje.")
        let withoutIban = BankAccount(currency: .czk, accountNumber: "1234567890/0300")
        let blankIban = BankAccount(currency: .czk, iban: " \u{00A0} ", bic: "GIBACZPX")

        #expect(QRPayload.payload(for: .fixture(), supplier: Self.supplier, accounts: [withoutIban]) == reason)
        #expect(QRPayload.payload(for: .fixture(), supplier: Self.supplier, accounts: [blankIban]) == reason)
        #expect(QRPayload.payload(for: .fixture(), supplier: Self.supplier, accounts: []) == reason)
    }

    @Test func aCzkInvoiceNeverUsesTheIbanOfAnotherCurrency() {
        let reason = QRPayloadResult.unavailable("Doplňte IBAN účtu v Kč v Nastavení › Moje údaje.")
        let withoutIban = BankAccount(currency: .czk, accountNumber: "1234567890/0300")

        let result = QRPayload.payload(
            for: .fixture(), supplier: Self.supplier, accounts: [Self.eurAccount, Self.usdAccount, withoutIban]
        )

        #expect(result == reason)
    }

    @Test(arguments: ["USD", "GBP", "PLN"])
    func aCurrencyWithoutAStandardHasNoCode(code: String) throws {
        let currency = try #require(CurrencyCode(code))
        let account = BankAccount(currency: currency, iban: "GB29 NWBK 6016 1331 9268 19")

        let result = QRPayload.payload(
            for: .fixture(currency: currency, vatMode: .outsideCountry), supplier: Self.supplier,
            accounts: [Self.czkAccount, Self.eurAccount, Self.usdAccount, account]
        )

        #expect(result == .unavailable("Pro platby v \(code) QR standard není, faktura bude bez QR kódu."))
    }

    @Test func aEuroInvoiceGetsAnEpcCodeWithTheSuppliersNameAndTheEuroAccount() {
        let invoice = Invoice.fixture(number: "20261001", currency: .eur, vatMode: .euReverseCharge)

        let result = QRPayload.payload(
            for: invoice, supplier: Self.supplier, accounts: [Self.czkAccount, Self.usdAccount, Self.eurAccount]
        )

        // 7,5 hours at 600,00 EUR without VAT: 4 500,00 EUR.
        #expect(result == .payload(Self.epcHead + "EUR4500.00\n\n\nFaktura 20261001", label: "QR Platba"))
    }

    @Test func anEnglishEuroInvoiceHasAnEnglishRemittanceAndLabel() {
        var invoice = Invoice.fixture(number: "20261001", currency: .eur, vatMode: .euReverseCharge)
        invoice.language = .en

        let result = QRPayload.payload(for: invoice, supplier: Self.supplier, accounts: [Self.eurAccount])

        #expect(result == .payload(Self.epcHead + "EUR4500.00\n\n\nInvoice 20261001", label: "QR payment"))
    }

    @Test func aEuroInvoiceWithoutAnIbanHasNoCode() {
        let invoice = Invoice.fixture(currency: .eur, vatMode: .euReverseCharge)
        let reason = QRPayloadResult.unavailable("Doplňte IBAN účtu v eurech v Nastavení › Moje údaje.")
        let withoutIban = BankAccount(currency: .eur, bic: "COBADEFFXXX")

        #expect(QRPayload.payload(for: invoice, supplier: Self.supplier, accounts: [withoutIban]) == reason)
        #expect(QRPayload.payload(for: invoice, supplier: Self.supplier, accounts: [Self.czkAccount]) == reason)
    }

    @Test func theAccountOfTheInvoiceCurrencyIsUsedWhateverTheOrder() {
        let accounts = [Self.eurAccount, Self.usdAccount, Self.czkAccount]
        let euro = Invoice.fixture(currency: .eur, vatMode: .euReverseCharge)

        let czkText = payload(of: QRPayload.payload(for: .fixture(), supplier: Self.supplier, accounts: accounts))
        let eurText = payload(of: QRPayload.payload(for: euro, supplier: Self.supplier, accounts: accounts))
        let reversedText = payload(
            of: QRPayload.payload(for: euro, supplier: Self.supplier, accounts: accounts.reversed())
        )

        #expect(czkText.flatMap { field("ACC", of: $0) } == "CZ6508000000192000145399+GIBACZPX")
        #expect(eurText.map { lines(of: $0)[6] } == "DE89370400440532013000")
        #expect(reversedText == eurText)
    }

    // MARK: Amount range

    @Test(arguments: [("CZK", 0 as Int64), ("CZK", -1), ("CZK", -544_500), ("EUR", 0), ("EUR", -1), ("EUR", -544_500)])
    func aTotalThatIsNotPositiveHasNoCode(code: String, total: Int64) throws {
        let currency = try #require(CurrencyCode(code))

        #expect(result(for: invoice(in: currency, total: total)) == .unavailable("Faktura nemá kladnou částku."))
    }

    /// An invoice whose items are not priced yet, as the editor shows it while it is being written.
    @Test(arguments: ["CZK", "EUR"])
    func anInvoiceWithoutItemsHasNoCode(code: String) throws {
        let currency = try #require(CurrencyCode(code))
        let blank = Invoice.fixture(currency: currency, items: [], vatMode: VatMode.none)

        #expect(result(for: blank) == .unavailable("Faktura nemá kladnou částku."))
    }

    @Test func theSmallestTotalGetsACode() {
        let czk = payload(of: result(for: invoice(in: .czk, total: 1)))
        let eur = payload(of: result(for: invoice(in: .eur, total: 1)))

        #expect(czk.flatMap { field("AM", of: $0) } == "0.01")
        #expect(eur.map { lines(of: $0)[7] } == "EUR0.01")
    }

    /// A QR Platba has ten characters for the amount, so 9 999 999,99 Kč at most. An EPC code has 999 999 999,99 EUR.
    @Test func theLargestTotalOfEachCodeGetsACode() {
        let czk = payload(of: result(for: invoice(in: .czk, total: 999_999_999)))
        let eur = payload(of: result(for: invoice(in: .eur, total: 99_999_999_999)))

        #expect(czk.flatMap { field("AM", of: $0) } == "9999999.99")
        #expect(eur.map { lines(of: $0)[7] } == "EUR999999999.99")
    }

    @Test func aTotalOneMinorUnitOverTheLimitHasNoCode() {
        let tooHigh = QRPayloadResult.unavailable("Částka je pro QR kód příliš vysoká.")

        #expect(result(for: invoice(in: .czk, total: 1_000_000_000)) == tooHigh)
        #expect(result(for: invoice(in: .eur, total: 100_000_000_000)) == tooHigh)
        #expect(result(for: invoice(in: .czk, total: Int64.max)) == tooHigh)
    }

    /// Each limit is that of its own code: 10 000 000,00 EUR fit an EPC code, but 10 000 000,00 Kč do not fit a QR
    /// Platba.
    @Test func eachCurrencyHasTheLimitOfItsOwnCode() {
        #expect(payload(of: result(for: invoice(in: .eur, total: 1_000_000_000))) != nil)
        #expect(payload(of: result(for: invoice(in: .czk, total: 1_000_000_000))) == nil)
    }

    // MARK: Supplier name

    /// The name of the beneficiary is a required line of an EPC code.
    @Test(arguments: ["", " ", "\n", " \u{00A0}\t\r\n "])
    func aEuroInvoiceWithoutASupplierNameHasNoCode(name: String) {
        let invoice = Invoice.fixture(currency: .eur, vatMode: .euReverseCharge)

        #expect(
            result(for: invoice, supplier: Supplier(name: name))
                == .unavailable("Doplňte jméno dodavatele v Nastavení › Moje údaje.")
        )
    }

    @Test func aCzkInvoiceDoesNotNeedTheSupplierName() {
        let code = result(for: .fixture(), supplier: Supplier())

        #expect(payload(of: code) != nil)
    }

    // MARK: Size of an EPC code

    /// An EPC code carries 331 bytes at most (a QR code of version 13 at error correction level M). A letter with an
    /// accent takes two bytes, so a long enough number fills the code before the limit on characters cuts in.
    @Test func anEpcCodeOf331BytesGetsACodeAndOneByteMoreHasNone() {
        let fittingNumber = String(repeating: "Á", count: 125)
        let overflowingNumber = String(repeating: "Á", count: 124) + "€"
        let fitting = epc(amountMinor: 450_000, remittance: "Faktura " + fittingNumber)
        let overflowing = epc(amountMinor: 450_000, remittance: "Faktura " + overflowingNumber)
        #expect(fitting.utf8.count == 331)
        #expect(overflowing.utf8.count == 332)

        let fits = result(for: .fixture(number: fittingNumber, currency: .eur, vatMode: .euReverseCharge))
        let overflows = result(for: .fixture(number: overflowingNumber, currency: .eur, vatMode: .euReverseCharge))

        #expect(fits == .payload(fitting, label: "QR Platba"))
        #expect(overflows == .unavailable("Údaje platby se do QR kódu nevejdou."))
    }

    @Test func aNameOfSeventyEmojiFillsTheCodeBeyondTheLimit() {
        let invoice = Invoice.fixture(currency: .eur, vatMode: .euReverseCharge)
        let supplier = Supplier(name: String(repeating: "\u{1F600}", count: 70))

        #expect(result(for: invoice, supplier: supplier) == .unavailable("Údaje platby se do QR kódu nevejdou."))
    }

    // MARK: What is reported first

    /// What the person has to fix in Nastavení comes before what is missing in the invoice: a blank invoice does not
    /// hide a missing IBAN or name.
    @Test func aProblemOfTheSettingsIsReportedBeforeOneOfTheAmount() {
        let blank = Invoice.fixture(currency: .eur, items: [], vatMode: VatMode.none)
        let withoutIban = BankAccount(currency: .eur, bic: "COBADEFFXXX")

        #expect(
            QRPayload.payload(for: blank, supplier: Self.supplier, accounts: [withoutIban])
                == .unavailable("Doplňte IBAN účtu v eurech v Nastavení › Moje údaje.")
        )
        #expect(
            result(for: blank, supplier: Supplier())
                == .unavailable("Doplňte jméno dodavatele v Nastavení › Moje údaje.")
        )
        #expect(result(for: blank) == .unavailable("Faktura nemá kladnou částku."))
    }

    /// Whether an invoice wants a code (`qrEnabled`) is up to the editor and the document, not to the payload.
    @Test func theFlagOfTheInvoiceDoesNotChangeThePayload() {
        var wanted = Invoice.fixture()
        wanted.qrEnabled = true
        var unwanted = Invoice.fixture()
        unwanted.qrEnabled = false

        let accounts = [Self.czkAccount]
        #expect(
            QRPayload.payload(for: wanted, supplier: Self.supplier, accounts: accounts)
                == QRPayload.payload(for: unwanted, supplier: Self.supplier, accounts: accounts)
        )
    }

    // MARK: Picture

    private static let qrPlatba =
        "SPD*1.0*ACC:CZ6508000000192000145399+GIBACZPX*AM:5445.00*CC:CZK*X-VS:20260902*DT:20261030*MSG:FAKTURA 20260902"

    /// The QR code that a scanner finds in `image`.
    private func scanned(_ image: CGImage) throws -> CIQRCodeFeature? {
        let options = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: options))
        return detector.features(in: CIImage(cgImage: image)).compactMap { $0 as? CIQRCodeFeature }.first
    }

    /// The text of the QR code in `image`, read the way a phone reads it.
    private func decoded(_ image: CGImage) throws -> String? {
        try scanned(image)?.messageString
    }

    /// The pixels of an image as 8-bit sRGB with alpha, in rows from the top.
    private struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) throws {
            width = image.width
            height = image.height
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer in
                let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: image.width * 4, space: space, bitmapInfo: bitmapInfo
                    )
                else {
                    return false
                }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            try #require(drawn)
            self.bytes = bytes
        }

        /// The red, green, blue and alpha values of a pixel.
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let start = (y * width + x) * 4
            return Array(bytes[start..<start + 4])
        }

        func isDark(_ x: Int, _ y: Int) -> Bool {
            bytes[(y * width + x) * 4] < 128
        }
    }

    @Test func theImageDecodesBackToTheSameQRPlatba() throws {
        let image = try #require(QRImage.make(Self.qrPlatba, moduleSize: 8))

        #expect(try decoded(image) == Self.qrPlatba)
    }

    @Test func theImageDecodesBackToTheSameEpcCode() throws {
        let code = epc()
        let image = try #require(QRImage.make(code, moduleSize: 8))

        #expect(try decoded(image) == code)
    }

    @Test func theImageOfAnInvoicePayloadDecodesBack() throws {
        let result = QRPayload.payload(for: .fixture(), supplier: Self.supplier, accounts: [Self.czkAccount])
        let text = try #require(payload(of: result))
        let image = try #require(QRImage.make(text, moduleSize: 4))

        #expect(try decoded(image) == text)
    }

    @Test(arguments: [1, 3, 8] as [CGFloat])
    func theSymbolHasAQuietZoneOfFourModules(moduleSize: CGFloat) throws {
        let image = try #require(QRImage.make(Self.qrPlatba, moduleSize: moduleSize))
        let bitmap = try Bitmap(image)
        let size = Int(moduleSize)

        var left = bitmap.width
        var right = -1
        var top = bitmap.height
        var bottom = -1
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where bitmap.isDark(x, y) {
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
            }
        }

        // Four modules of white on every side of the dark finder patterns, which touch the edges of the symbol.
        #expect(left == 4 * size)
        #expect(top == 4 * size)
        #expect(bitmap.width - 1 - right == 4 * size)
        #expect(bitmap.height - 1 - bottom == 4 * size)
    }

    @Test func theCodeUsesErrorCorrectionLevelM() throws {
        let image = try #require(QRImage.make(Self.qrPlatba, moduleSize: 8))

        let code = try #require(try scanned(image))
        #expect(code.symbolDescriptor?.errorCorrectionLevel == .levelM)
    }

    @Test func theImageIsTheSymbolAndAQuietZoneOfFourModulesOnEverySide() throws {
        let image = try #require(QRImage.make(Self.qrPlatba, moduleSize: 6))

        // A symbol of version v is 17 + 4v modules wide.
        let version = try #require(try scanned(image)?.symbolDescriptor?.symbolVersion)
        #expect(image.width == (17 + 4 * version + 2 * 4) * 6)
        #expect(image.height == image.width)
    }

    @Test func theSmallestSymbolIsTwentyOneModulesWide() throws {
        let image = try #require(QRImage.make("A", moduleSize: 4))

        #expect(image.width == (21 + 8) * 4)
        #expect(image.height == (21 + 8) * 4)
    }

    @Test func theModuleSizeScalesTheWholeImage() throws {
        let one = try #require(QRImage.make(Self.qrPlatba, moduleSize: 1))
        let ten = try #require(QRImage.make(Self.qrPlatba, moduleSize: 10))

        #expect(ten.width == one.width * 10)
        #expect(ten.height == one.height * 10)
    }

    /// Every module is a square of `moduleSize` pixels in black or white and nothing else: the scaling does not blur.
    @Test func theModulesAreSharpSquaresOfBlackAndWhite() throws {
        let size = 5
        let image = try #require(QRImage.make(Self.qrPlatba, moduleSize: CGFloat(size)))
        let bitmap = try Bitmap(image)
        let black: [UInt8] = [0, 0, 0, 255]
        let white: [UInt8] = [255, 255, 255, 255]

        var onlyBlackAndWhite = true
        var everyModuleUniform = true
        for moduleY in 0..<bitmap.height / size {
            for moduleX in 0..<bitmap.width / size {
                let first = bitmap.pixel(moduleX * size, moduleY * size)
                if first != black && first != white {
                    onlyBlackAndWhite = false
                }
                for dy in 0..<size {
                    for dx in 0..<size where bitmap.pixel(moduleX * size + dx, moduleY * size + dy) != first {
                        everyModuleUniform = false
                    }
                }
            }
        }

        #expect(onlyBlackAndWhite)
        #expect(everyModuleUniform)
        #expect(bitmap.width % size == 0)
    }

    /// A module is a whole number of pixels wide, so that none is wider than another and no edge is half covered.
    @Test(arguments: [(2.5 as CGFloat, 3), (2.4, 2), (0.5, 1), (7.9, 8)])
    func aFractionalModuleSizeIsRoundedToWholePixels(moduleSize: CGFloat, pixels: Int) throws {
        let image = try #require(QRImage.make("A", moduleSize: moduleSize))
        let bitmap = try Bitmap(image)

        #expect(image.width == (21 + 8) * pixels)
        let opaque = (0..<bitmap.height).allSatisfy { y in
            (0..<bitmap.width).allSatisfy { x in bitmap.pixel(x, y)[3] == 255 }
        }
        #expect(opaque)
    }

    @Test(arguments: [0, -1, 0.4, .nan, .infinity, -.infinity] as [CGFloat])
    func thereIsNoImageForAModuleSizeThatIsNotAPixel(moduleSize: CGFloat) {
        #expect(QRImage.make(Self.qrPlatba, moduleSize: moduleSize) == nil)
    }

    /// Nothing is drawn that would take hundreds of megabytes, whatever the caller asks for.
    @Test func thereIsNoImageOfAMonstrousSize() {
        #expect(QRImage.make(Self.qrPlatba, moduleSize: 1_000) == nil)
        #expect(QRImage.make(Self.qrPlatba, moduleSize: 100_000) == nil)
        #expect(QRImage.make(Self.qrPlatba, moduleSize: 8) != nil)
    }

    @Test func thereIsNoImageOfATextThatDoesNotFitInACode() {
        #expect(QRImage.make(String(repeating: "A", count: 5_000), moduleSize: 1) == nil)
    }
}

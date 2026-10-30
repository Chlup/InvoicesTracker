import Foundation
import Testing
@testable import InvoicesTracker

/// Reading the rows of a Fakturoid export: the columns by their names, the numbers in the two spellings the export
/// has, and the fingerprint that tells a later import whether a row has changed.
struct FakturoidRowTests {
    // MARK: The export

    @Test func theFixturesHaveTheSixtyColumnsOfTheExport() throws {
        #expect(FakturoidCSV.header.count == 60)
        for name in ["fakturoid_sample", "fakturoid_reimport"] {
            let text = try String(contentsOf: fixtureURL(name, "csv"), encoding: .utf8)
            let table = try CSVTable.parse(text)
            #expect(text.hasPrefix(FakturoidCSV.headerLine + "\n"), "\(name)")
            #expect(table.header == FakturoidCSV.header, "\(name)")
            #expect(table.rows.allSatisfy { $0.count == 60 }, "\(name)")
        }
    }

    @Test func theSampleHasThirteenRowsAndTheReimportFourteen() throws {
        #expect(try fakturoidFixtureRows("fakturoid_sample").count == 13)
        #expect(try fakturoidFixtureRows("fakturoid_reimport").count == 14)
    }

    // MARK: Columns

    @Test func theColumnsAreFoundByNameWhateverTheirOrder() throws {
        let table = CSVTable(
            header: ["Status", "Subtotal", "Issued on", "Number", "Currency"],
            rows: [["paid", "14350,0", "2026-09-30", "20260901", "usd"]]
        )

        let row = try #require(try FakturoidRow.rows(from: table).first)

        #expect(row.number == "20260901")
        #expect(row.issuedOn == civilDate("2026-09-30"))
        #expect(row.status == "paid")
        #expect(row.subtotalMinor == 1_435_000)
        #expect(row.currency == "USD")
    }

    @Test func unknownColumnsAreIgnoredAndMissingOptionalOnesAreTolerated() throws {
        let table = CSVTable(
            header: ["Number", "Mystery", "Issued on"], rows: [["20260901", "x", "2026-09-30"]]
        )

        let row = try #require(try FakturoidRow.rows(from: table).first)

        #expect(row.number == "20260901" && row.issuedOn == civilDate("2026-09-30"))
        #expect(row.fakturoidID.isEmpty && row.clientName.isEmpty && row.subject.isEmpty)
        #expect(row.paidOn == nil && row.dueOn == nil && row.dueDays == nil && row.taxableFulfillmentDue == nil)
        #expect(row.subtotalMinor == nil && row.vatMinor == nil && row.exchangeRate == nil)
        #expect(!row.proforma && !row.cancelled && !row.transferredTaxLiability)
        // The export does not say, so neither does the row: it is not taken for crowns.
        #expect(row.currency.isEmpty)
    }

    @Test func headerNamesAreTrimmed() throws {
        let table = CSVTable(header: [" Number ", "Issued on  "], rows: [["20260901", "2026-09-30"]])

        #expect(try FakturoidRow.rows(from: table).first?.number == "20260901")
    }

    @Test(arguments: [["Issued on", "Subtotal"], ["Number", "Subtotal"], [], ["number", "issued on"]])
    func withoutNumberOrIssuedOnItIsNoFakturoidExport(header: [String]) {
        let table = CSVTable(header: header, rows: [Array(repeating: "x", count: header.count)])

        #expect(throws: ImportError.notAFakturoidExport) { try FakturoidRow.rows(from: table) }
    }

    @Test func theMessagesOfAFileThatCannotBeImportedAreInCzech() {
        #expect(ImportError.notAFakturoidExport.errorDescription == "Nevypadá to jako export faktur z Fakturoidu.")
        #expect(ImportError.emptyFile.errorDescription == "Soubor je prázdný.")
    }

    @Test func aRowWithAnotherNumberOfFieldsThanTheHeaderDamagesTheFile() {
        // Which column a value belongs to is unknown then, and a currency or a payment date could be taken for another.
        let short = CSVTable(
            header: ["Number", "Issued on", "Currency"], rows: [["1", "2026-09-30", "USD"], ["2", "2026-09-30"]])
        let long = CSVTable(header: ["Number", "Issued on"], rows: [["1", "2026-09-30", "USD"]])

        #expect(throws: ImportError.damagedFile(line: 3)) { try FakturoidRow.rows(from: short) }
        #expect(throws: ImportError.damagedFile(line: 2)) { try FakturoidRow.rows(from: long) }
    }

    @Test func aRowWithNoValueAtAllIsNotARow() throws {
        let table = CSVTable(
            header: ["Number", "Issued on"],
            rows: [["20260901", "2026-09-30"], ["", ""], [" ", ""], ["20260902", "2026-09-30"]]
        )

        #expect(try FakturoidRow.rows(from: table).map(\.number) == ["20260901", "20260902"])
    }

    @Test func aRowOfTheSampleIsReadWithEveryColumnTheImportUses() throws {
        let rows = try fakturoidFixtureRows()
        let first = rows[0]

        #expect(first.fakturoidID == "5001")
        #expect(first.number == "20260902")
        #expect(first.issuedOn == civilDate("2026-09-30"))
        #expect(first.taxableFulfillmentDue == civilDate("2026-09-30"))
        #expect(first.dueDays == 30)
        #expect(first.dueOn == civilDate("2026-10-30"))
        #expect(first.paidOn == civilDate("2026-10-15"))
        #expect(first.status == "paid")
        #expect(!first.proforma && !first.cancelled && !first.transferredTaxLiability)
        #expect(first.currency == "CZK")
        #expect(first.exchangeRate == decimal("1"))
        #expect(first.subtotalMinor == 450_000 && first.totalMinor == 544_500 && first.vatMinor == 94_500)
        #expect(first.language == "cz")
        #expect(first.paymentMethodHuman == "Banka")
        #expect(first.subject == "Vývoj software, září 2026")
        #expect(first.clientName == "Alfa Systems s.r.o.")
        #expect(first.clientStreet == "Náměstí 1" && first.clientStreet2.isEmpty)
        #expect(first.clientCity == "Příbram" && first.clientZip == "26101" && first.clientCountry == "CZ")
        #expect(first.clientRegistrationNo == "12345678" && first.clientVatNo == "CZ12345678")
        #expect(first.clientEmail == "fakturace@alfa.example" && first.clientPhone.isEmpty)
        #expect(first.yourName == "Jana Vzorová" && first.yourStreet == "Polní 5" && first.yourStreet2.isEmpty)
        #expect(first.yourCity == "Brno" && first.yourZip == "60200" && first.yourCountry == "CZ")
        #expect(first.yourRegistrationNo == "11223344" && first.yourVatNo == "CZ11223344")
        #expect(rows[1].exchangeRate == decimal("21.359") && rows[1].currency == "USD")
        #expect(rows[1].subtotalMinor == 1_435_000 && rows[1].vatMinor == 0)
        #expect(rows[2].clientPhone == "+420 111 222 333" && rows[2].number == "2026-10-01")
    }

    @Test func theDeliveryColumnsAreNotRead() throws {
        let row = try FakturoidCSV.parsed([
            "Client delivery name": "Sklad", "Client delivery street": "Dodací 1", "Client delivery city": "Plzeň",
            "Client delivery zip": "30100", "Client delivery country": "CZ",
        ])

        #expect(row == (try FakturoidCSV.parsed()))
    }

    @Test func textIsTrimmed() throws {
        let row = try FakturoidCSV.parsed([
            "Number": " 20260901 ", "Client name": "  Alfa Systems s.r.o.\t", "Status": " Paid ",
            "Currency": " usd ", "Language": " CZ ", "Subject": "  Vývoj ",
        ])

        #expect(row.number == "20260901" && row.clientName == "Alfa Systems s.r.o.")
        #expect(row.status == "paid" && row.currency == "USD" && row.language == "cz" && row.subject == "Vývoj")
    }

    // MARK: Numbers

    @Test(arguments: [
        ("4500,0", 450_000), ("4500.0", 450_000), ("4500", 450_000), ("4500,00", 450_000), ("4500,5", 450_050),
        ("0,01", 1), ("0.01", 1), ("-4500,0", -450_000), ("−4500,0", -450_000), ("1 000,50", 100_050),
        ("945.0", 94_500), ("9999999999,99", 999_999_999_999),
    ])
    func anAmountIsReadWithADecimalCommaOrAPoint(text: String, minor: Int64) throws {
        let row = try FakturoidCSV.parsed(["Subtotal": text, "Vat": text])

        #expect(row.subtotalMinor == minor)
        #expect(row.vatMinor == minor)
        #expect(row.totalMinor == 544_500)
    }

    @Test(arguments: [
        "", "abc", "12,345", "1.234,50", "1,234.50", "10000000000,0", "99999999999999999999", "4500,0 Kč", "--5",
    ])
    func anAmountThatCannotBeReadExactlyIsNotAnAmount(text: String) throws {
        let row = try FakturoidCSV.parsed(["Subtotal": text, "Vat": text, "Total": text])

        #expect(row.subtotalMinor == nil)
        #expect(row.vatMinor == nil)
        #expect(row.totalMinor == nil)
    }

    @Test(arguments: [
        "abc", "12,345", "1.234,50", "1,234.50", "10000000000,0", "99999999999999999999", "945.0 Kč", "--5",
    ])
    func aVATCellWithTextThatIsNotAnExactAmountIsMarkedUnreadable(text: String) throws {
        let row = try FakturoidCSV.parsed(["Vat": text])

        #expect(row.vatMinor == nil)
        #expect(row.vatUnreadable)
    }

    @Test(
        arguments: [("", nil), ("  ", nil), ("0.0", 0), ("945.0", 94_500), ("-945,0", -94_500)]
            as [(String, Int64?)]
    )
    func aVATCellThatIsEmptyOrAnAmountIsNotUnreadable(text: String, minor: Int64?) throws {
        let row = try FakturoidCSV.parsed(["Vat": text])

        #expect(row.vatMinor == minor)
        #expect(!row.vatUnreadable)
    }

    @Test(arguments: [("21.359", "21.359"), ("21,359", "21.359"), ("1.0", "1"), ("24", "24"), ("0.0482", "0.0482")])
    func anExchangeRateIsReadWithADecimalCommaOrAPoint(text: String, expected: String) throws {
        #expect(try FakturoidCSV.parsed(["Exchange rate": text]).exchangeRate == decimal(expected))
    }

    @Test(arguments: ["", "abc", "0", "0.0", "-21.359", "1000000", "21.359.1", "21,359 Kč"])
    func anExchangeRateThatIsNotAPositiveNumberIsNoRate(text: String) throws {
        #expect(try FakturoidCSV.parsed(["Exchange rate": text]).exchangeRate == nil)
    }

    @Test(arguments: [("30", 30), ("0", 0), ("14", 14), (" 15 ", 15), ("3650", 3650)])
    func theDaysUntilDueAreAWholeNumber(text: String, days: Int) throws {
        #expect(try FakturoidCSV.parsed(["Due": text]).dueDays == days)
    }

    @Test(arguments: ["", "-1", "x", "1.5", "3651", "99999999999999999999"])
    func daysUntilDueThatAreNotAWholeNumberOfDaysAreNone(text: String) throws {
        #expect(try FakturoidCSV.parsed(["Due": text]).dueDays == nil)
    }

    // MARK: Dates and flags

    @Test func datesAreReadAsIsoDates() throws {
        let row = try FakturoidCSV.parsed([
            "Issued on": "2026-09-30", "Taxable fulfillment due": "2026-09-29", "Due on": "2026-10-30",
            "Paid on": "2026-10-15",
        ])

        #expect(row.issuedOn == civilDate("2026-09-30"))
        #expect(row.taxableFulfillmentDue == civilDate("2026-09-29"))
        #expect(row.dueOn == civilDate("2026-10-30"))
        #expect(row.paidOn == civilDate("2026-10-15"))
    }

    @Test(arguments: ["", "30.9.2026", "2026-9-30", "2026-02-30", "2026-13-01", "soon", "2026-09-30T10:00:00"])
    func aTextThatIsNoIsoDateIsNoDate(text: String) throws {
        let row = try FakturoidCSV.parsed([
            "Issued on": text, "Taxable fulfillment due": text, "Due on": text, "Paid on": text,
        ])

        #expect(row.issuedOn == nil && row.taxableFulfillmentDue == nil && row.dueOn == nil && row.paidOn == nil)
    }

    @Test(arguments: ["0001-01-01", "1899-12-31", "2101-01-01", "9999-12-31"])
    func aDateFarFromAnyInvoiceIsNoDate(text: String) throws {
        // Dates this far out would not be taken for a date, and the calendar and the rate lookups work from them.
        let row = try FakturoidCSV.parsed(["Issued on": text, "Paid on": text])

        #expect(row.issuedOn == nil && row.paidOn == nil)
    }

    @Test func aProformaIsOneOrAPartialProforma() throws {
        #expect(try !FakturoidCSV.parsed().proforma)
        #expect(try FakturoidCSV.parsed(["Proforma": "true"]).proforma)
        #expect(try FakturoidCSV.parsed(["Partial proforma": "true"]).proforma)
        #expect(try FakturoidCSV.parsed(["Proforma": "TRUE"]).proforma)
        #expect(try !FakturoidCSV.parsed(["Proforma": "false", "Partial proforma": "false"]).proforma)
    }

    @Test func anInvoiceIsCancelledByTheDateItWasCancelledOnOrByItsStatus() throws {
        #expect(try !FakturoidCSV.parsed().cancelled)
        #expect(try FakturoidCSV.parsed(["Cancelled at": "2026-10-05 12:00:00"]).cancelled)
        #expect(try FakturoidCSV.parsed(["Status": "cancelled"]).cancelled)
        #expect(try FakturoidCSV.parsed(["Status": "Cancelled"]).cancelled)
        #expect(try !FakturoidCSV.parsed(["Status": "paid"]).cancelled)
    }

    @Test func aTransferredTaxLiabilityIsTrueOrFalse() throws {
        #expect(try FakturoidCSV.parsed(["Transferred tax liability": "true"]).transferredTaxLiability)
        #expect(try !FakturoidCSV.parsed(["Transferred tax liability": "false"]).transferredTaxLiability)
        #expect(try !FakturoidCSV.parsed(["Transferred tax liability": ""]).transferredTaxLiability)
    }

    @Test func anEmptyCurrencyStaysEmptyAndIsNotTakenForCrowns() throws {
        #expect(try FakturoidCSV.parsed(["Currency": ""]).currency.isEmpty)
        #expect(try FakturoidCSV.parsed(["Currency": "  "]).currency.isEmpty)
        #expect(try FakturoidCSV.parsed(["Currency": "eur"]).currency == "EUR")
    }

    // MARK: Fingerprint

    @Test func theFingerprintOfARowIsAPinnedSHA256() throws {
        // Worked out outside the app from the normalized fields of this row. It is stored with every imported invoice,
        // so a change of it makes every invoice look changed once.
        let fingerprint = try FakturoidCSV.parsed().fingerprint

        #expect(fingerprint == "489c7a86887f07a6eaccb40b5ba1da8c8df59a437e1e84efb25de17bafb1968c")
        #expect(fingerprint.count == 64 && fingerprint.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func theSameRowHasTheSameFingerprintWhateverItsSpellingAndColumnsNotUsed() throws {
        let base = try FakturoidCSV.parsed().fingerprint

        let spelled = try FakturoidCSV.parsed([
            "Subtotal": "4500.00", "Vat": "945,0", "Exchange rate": "1.000", "Number": " 20261001 ",
            "Currency": "czk",
        ])
        let otherColumns = try FakturoidCSV.parsed([
            "Your name": "Někdo Jiný", "Your street": "Jiná 1", "Your street2": "patro 2", "Your city": "Praha",
            "Your zip": "11000", "Your country": "SK", "Your registration no": "1", "Your vat no": "SK1",
            "Client phone": "+420 111 222 333", "Total": "9999,0", "Sent at": "2026-10-02 09:00:00",
            "Token": "abc", "Bank account": "123/0100", "Remaining amount": "0,0", "Client delivery name": "Sklad",
        ])

        #expect(spelled.fingerprint == base)
        #expect(otherColumns.fingerprint == base)
    }

    @Test(arguments: [
        ["Id": "2"], ["Number": "20261002"], ["Issued on": "2026-10-02"], ["Taxable fulfillment due": "2026-10-02"],
        ["Due": "30"], ["Due on": "2026-10-17"], ["Paid on": "2026-10-20"], ["Status": "paid"],
        ["Status": "cancelled"], ["Cancelled at": "2026-10-20 10:00:00"], ["Proforma": "true"],
        ["Partial proforma": "true"], ["Currency": "USD"], ["Exchange rate": "21.359"], ["Subtotal": "4600,0"],
        ["Vat": "966.0"], ["Transferred tax liability": "true"], ["Language": "en"],
        ["Payment method human": "Hotově"], ["Subject": "Něco jiného"], ["Client name": "Alfa Systems"],
        ["Client street": "Jiná 2"], ["Client street2": "patro 3"], ["Client city": "Brno"],
        ["Client zip": "60200"], ["Client country": "SK"], ["Client registration no": "87654321"],
        ["Client vat no": "CZ87654321"], ["Client email": "jiny@example.com"],
    ])
    func aChangeInAColumnTheInvoiceIsMadeFromChangesTheFingerprint(change: [String: String]) throws {
        let base = try FakturoidCSV.parsed().fingerprint

        #expect(try FakturoidCSV.parsed(change).fingerprint != base, "\(change)")
    }

    @Test func theFingerprintTellsAVATThatCannotBeReadFromAnEmptyOne() throws {
        let empty = try FakturoidCSV.parsed(["Vat": ""]).fingerprint
        let unreadable = try FakturoidCSV.parsed(["Vat": "abc"]).fingerprint
        let another = try FakturoidCSV.parsed(["Vat": "1.234,50"]).fingerprint

        #expect(empty != unreadable)
        // Whatever the text, a cell that cannot be read is the same to the import.
        #expect(unreadable == another)
    }

    @Test func fieldsThatRunTogetherDoNotMakeTheSameFingerprint() throws {
        // "ab" + "" and "a" + "b" must not hash alike.
        let first = try FakturoidCSV.parsed(["Client street": "ab", "Client street2": ""])
        let second = try FakturoidCSV.parsed(["Client street": "a", "Client street2": "b"])

        #expect(first.fingerprint != second.fingerprint)
    }

    @Test func theRowsOfTheSampleHaveFingerprintsOfTheirOwn() throws {
        let fingerprints = try fakturoidFixtureRows().map(\.fingerprint)

        #expect(Set(fingerprints).count == 13)
    }

    @Test func theReimportChangesTheRowsItSaysItChanges() throws {
        let sample = try fakturoidFixtureRows("fakturoid_sample")
        let reimport = try fakturoidFixtureRows("fakturoid_reimport")

        let changed = zip(sample, reimport).enumerated().filter { $0.element.0.fingerprint != $0.element.1.fingerprint }

        #expect(changed.map(\.offset) == [0, 1, 2])
        #expect(reimport[0].subtotalMinor == 460_000 && reimport[0].vatMinor == 96_600)
        #expect(reimport[1].cancelled)
        #expect(reimport[2].paidOn == civilDate("2026-11-03"))
        #expect(reimport.count == sample.count + 1 && reimport[13].number == "20261102")
    }
}

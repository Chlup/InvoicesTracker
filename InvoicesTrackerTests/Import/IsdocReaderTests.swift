import Foundation
import Testing

@testable import InvoicesTracker

/// The reading of one ISDOC invoice, as Fakturoid writes it. The files are invented fixtures in
/// `Fixtures/Import/isdoc/`.
struct IsdocReaderTests {
    private func data(_ name: String, _ ext: String = "isdoc") throws -> Data {
        try Data(contentsOf: fixtureURL(name, ext))
    }

    private func read(_ name: String, _ ext: String = "isdoc") throws -> IsdocInvoice {
        try IsdocReader.read(data(name, ext))
    }

    @Test func theCrownInvoiceIsReadWithItsLineUnitAndPrice() throws {
        let invoice = try read("czk-21")
        #expect(invoice.number == "20260902")
        #expect(invoice.documentType == 1)
        #expect(invoice.currency == "CZK")
        #expect(invoice.rate == nil)
        #expect(invoice.issueDate == CivilDate(iso: "2026-09-02"))
        #expect(invoice.taxPointDate == CivilDate(iso: "2026-09-02"))
        #expect(invoice.dueDate == CivilDate(iso: "2026-09-16"))
        #expect(invoice.note == "Fakturujeme vám za září.")
        #expect(invoice.paymentMeansCode == "42")
        #expect(invoice.customer.name == "Truhlářství Doubek s.r.o.")
        #expect(invoice.customer.ico == "17392047")
        #expect(invoice.customer.dic == "CZ17392047")
        #expect(invoice.supplier?.name == "Truhlářství Doubek s.r.o.")
        #expect(invoice.lines.count == 1)
        let line = try #require(invoice.lines.first)
        #expect(line.quantity == Decimal(7))
        #expect(line.unit == "hod")
        #expect(line.description == "Správa IT a podpora – září 2026")
        #expect(line.lineAmountMinor == 504_000)
        #expect(line.unitPriceCZKMinor == 72_000)
        #expect(line.vatPercent == 21)
    }

    @Test func aForeignInvoiceTakesItsCurrencyRateAndAmountsInTheCurrency() throws {
        let invoice = try read("usd-0")
        #expect(invoice.currency == "USD")
        #expect(invoice.rate == Decimal(string: "21.278"))
        let line = try #require(invoice.lines.first)
        #expect(line.lineAmountMinor == 1_435_600)
        #expect(line.unitPriceCZKMinor == 157_457)
        #expect(line.unit == "h")
        #expect(line.vatPercent == 0)
        #expect(invoice.customer.ico == "")
        #expect(invoice.customer.country == "US")
    }

    @Test func theStreetIsTheStreetAndTheBuildingNumberJoined() throws {
        let invoice = try read("czk-21")
        #expect(invoice.customer.street == "Na Výsluní 112")
        #expect(invoice.customer.city == "Benešov")
        #expect(invoice.customer.postcode == "25601")
    }

    @Test func anEmptyUnitStaysEmpty() throws {
        let invoice = try read("two-lines")
        #expect(invoice.lines.map(\.unit) == ["hod", ""])
        #expect(invoice.lines.map(\.description) == ["Správa IT a podpora – září 2026", "Doprava"])
    }

    @Test func aDocumentTypeOfFourIsAProformaAndMixedRatesStayPerLine() throws {
        #expect(try read("proforma").documentType == 4)
        #expect(try read("mixed-vat").lines.map(\.vatPercent) == [21, 12])
    }

    @Test func aDeclaredEncodingIsReadAndABOMSkipped() throws {
        let legacy = try read("windows-1250")
        #expect(legacy.lines.first?.description == "Správa IT a podpora – září 2026")
        #expect(legacy.note == "Fakturujeme vám za září.")
        #expect(legacy.customer.name == "Truhlářství Doubek s.r.o.")

        let bom = Data([0xEF, 0xBB, 0xBF]) + (try data("czk-21"))
        let withBOM = try IsdocReader.read(bom)
        #expect(withBOM.number == "20260902")
        #expect(withBOM.lines.first?.description == "Správa IT a podpora – září 2026")
    }

    @Test func aUBLFileIsNotAnIsdocInvoice() throws {
        #expect(throws: ImportError.notAnIsdocInvoice) { try read("not-isdoc", "xml") }
    }

    @Test func aDamagedFileIsNotAnIsdocInvoice() throws {
        #expect(throws: ImportError.notAnIsdocInvoice) { try read("damaged") }
        #expect(throws: ImportError.notAnIsdocInvoice) { try IsdocReader.read(Data()) }
    }

    @Test func aFileWithoutAnIDSaysSo() throws {
        #expect(throws: ImportError.isdocWithoutNumber) { try read("no-id") }
    }

    @Test func aFileWithoutLinesSaysSo() throws {
        #expect(throws: ImportError.isdocWithoutLines) { try read("no-lines") }
    }

    @Test func theFingerprintIsTheSameForTheSameContentAndDiffersWhenALineChanges() throws {
        let invoice = try read("czk-21")
        let again = try read("czk-21")
        #expect(invoice.fingerprint == again.fingerprint)
        #expect(invoice.fingerprint.count == 64)
        #expect(invoice.fingerprint.allSatisfy { "0123456789abcdef".contains($0) })

        var changed = invoice
        changed.lines[0].quantity = 8
        #expect(changed.fingerprint != invoice.fingerprint)
        #expect(try read("two-lines").fingerprint != invoice.fingerprint)
    }

    @Test func theErrorsSayTheTextsOfTheImportScreen() {
        #expect(ImportError.notAnIsdocInvoice.errorDescription == "Nevypadá to jako faktura ve formátu ISDOC.")
        #expect(ImportError.isdocWithoutNumber.errorDescription == "V souboru ISDOC chybí číslo faktury.")
        #expect(ImportError.isdocWithoutLines.errorDescription == "Ve faktuře ISDOC nejsou žádné položky.")
        #expect(ImportError.unsupportedFile.errorDescription == "Tento soubor není CSV ani ISDOC.")
    }
}

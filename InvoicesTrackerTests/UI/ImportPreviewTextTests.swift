import Foundation
import Testing

@testable import InvoicesTracker

/// The words of the preview of an import ("Před importem"): its rows, the title of its button, the header and the
/// lines of its files and its progress. In every expected string `\u{00A0}` is the no-break space.
struct ImportPreviewTextTests {
    private func plan(
        new: [String] = [], overwritten: [String] = [], unchanged: [String] = [], skipped: [String] = [],
        notAdded: [ImportNotAddedItem] = []
    ) -> ImportPlan {
        var plan = ImportPlan()
        plan.newNumbers = new
        plan.overwrittenNumbers = overwritten
        plan.unchangedNumbers = unchanged
        plan.skippedNumbers = skipped
        plan.notAdded = notAdded
        return plan
    }

    // MARK: Outcome rows

    @Test func theRowsComeInOrderEachOnlyWithNumbers() {
        let rows = ImportPreviewText.outcomeRows(
            of: plan(
                new: ["1", "2"], overwritten: ["3", "4"], unchanged: ["5", "6"], skipped: ["Z7"],
                notAdded: [
                    ImportNotAddedItem(number: "8", reason: "číslo už používá faktura v jiné měně"),
                    ImportNotAddedItem(number: "9", reason: "chybí den vystavení"),
                ]))

        #expect(rows.map(\.label) == ["Nové", "Přepíší se", "Beze změny", "Přeskočí se", "Nepřidají se"])
        #expect(rows.map(\.count) == [2, 2, 2, 1, 2])
        #expect(rows.map(\.tone) == [.new, .overwrite, .neutral, .neutral, .neutral])
        #expect(rows[0].note == "Přidají se: 1, 2.")
        #expect(rows[1].note == "3, 4 – už je v aplikaci máte. Co jste u nich v aplikaci změnili, se ztratí.")
        #expect(rows[2].note == "V aplikaci už jsou stejné: 5, 6.")
        #expect(rows[3].note == "Zálohové a stornované faktury: Z7.")
        #expect(rows[4].note == "8 – číslo už používá faktura v jiné měně; 9 – chybí den vystavení")
    }

    @Test func oneOverwrittenInvoiceIsSaidInTheSingular() {
        let rows = ImportPreviewText.outcomeRows(of: plan(overwritten: ["3"]))

        #expect(rows.map(\.label) == ["Přepíší se"])
        #expect(rows[0].note == "3 – už ji v aplikaci máte. Co jste u ní v aplikaci změnili, se ztratí.")
    }

    @Test func aPlanWithNothingToImportHasOneRowSayingSo() {
        let rows = ImportPreviewText.outcomeRows(of: plan())

        #expect(rows.count == 1)
        #expect(rows[0].label == "Žádná faktura k importu" && rows[0].count == 0 && rows[0].tone == .neutral)
        #expect(rows[0].note == "Ve zvolených souborech není žádná faktura, kterou by šlo naimportovat.")
    }

    // MARK: Button, header, progress

    @Test(arguments: [
        (0, "Importovat"), (1, "Importovat 1\u{00A0}fakturu"), (3, "Importovat 3\u{00A0}faktury"),
        (5, "Importovat 5\u{00A0}faktur"), (1_234, "Importovat 1\u{00A0}234\u{00A0}faktur"),
    ])
    func theButtonCountsTheInvoicesInCzech(count: Int, title: String) {
        #expect(ImportPreviewText.importButtonTitle(count: count) == title)
    }

    @Test(arguments: [(1, "1\u{00A0}soubor"), (2, "2\u{00A0}soubory"), (5, "5\u{00A0}souborů")])
    func theHeaderCountsTheFilesInCzech(count: Int, text: String) {
        #expect(ImportPreviewText.filesHeader(count: count) == text)
    }

    @Test func theProgressSaysHowManyAreDone() {
        #expect(ImportPreviewText.progress(done: 3, total: 12) == "Importuji 3 z 12…")
    }

    // MARK: Files

    private func csvFile(rows count: Int, size: Int? = 5_620) throws -> ImportFile {
        let row = try FakturoidCSV.parsed()
        return ImportFile(name: "a.csv", size: size, kind: .csv, content: .rows(Array(repeating: row, count: count)))
    }

    @Test(arguments: [
        (1, "1\u{00A0}faktura · 5,5\u{00A0}kB"), (3, "3\u{00A0}faktury · 5,5\u{00A0}kB"),
        (12, "12\u{00A0}faktur · 5,5\u{00A0}kB"),
    ])
    func aCSVFileSaysHowManyInvoicesItHas(count: Int, detail: String) throws {
        #expect(ImportPreviewText.fileDetail(of: try csvFile(rows: count)) == detail)
    }

    @Test func anIsdocFileNamesItsInvoiceAndAFailedFileItsErrorWithTheSize() throws {
        let invoice = try IsdocReader.read(Data(contentsOf: fixtureURL("czk-21", "isdoc")))
        let isdoc = ImportFile(name: "a.isdoc", size: 5_940, kind: .isdoc, content: .invoice(invoice))
        let failed = ImportFile(name: "b.csv", size: 5_620, kind: .csv, content: .failed(.emptyFile))
        let unknownSize = ImportFile(name: "c.csv", size: nil, kind: .csv, content: .failed(.emptyFile))

        #expect(ImportPreviewText.fileDetail(of: isdoc) == "faktura 20260902 · 5,8\u{00A0}kB")
        #expect(ImportPreviewText.fileDetail(of: failed) == "Soubor je prázdný. · 5,5\u{00A0}kB")
        #expect(ImportPreviewText.fileDetail(of: unknownSize) == "Soubor je prázdný.")
    }

    @Test func thePillSaysTheKindOfTheFile() throws {
        let failed = ImportFile(name: "x.txt", size: 1, kind: nil, content: .failed(.unsupportedFile))

        #expect(ImportPreviewText.pill(of: try csvFile(rows: 1)) == "CSV")
        #expect(ImportPreviewText.pill(of: failed) == "?")
        let isdoc = ImportFile(name: "a.isdoc", size: 1, kind: .isdoc, content: .failed(.notAnIsdocInvoice))
        #expect(ImportPreviewText.pill(of: isdoc) == "ISDOC")
    }
}

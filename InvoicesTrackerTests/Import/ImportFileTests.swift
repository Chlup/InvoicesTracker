import Foundation
import Testing

@testable import InvoicesTracker

/// The reading of the files and folders the person chose for an import, one file at a time.
struct ImportFileTests {
    /// Copies the invented fixture `name.ext` into `directory` under `fileName`.
    private func copyFixture(_ name: String, _ ext: String, as fileName: String, to directory: URL) throws -> URL {
        let url = directory.appending(path: fileName)
        try Data(contentsOf: fixtureURL(name, ext)).write(to: url)
        return url
    }

    private func csvText() -> String {
        FakturoidCSV.text([FakturoidCSV.row()])
    }

    @Test func aFolderIsReadAsItsCsvIsdocAndXmlFilesOneLevelDeep() async throws {
        let directory = try makeTemporaryDirectory()
        _ = try writeCSV(csvText(), named: "b-export.csv", in: directory)
        _ = try copyFixture("czk-21", "isdoc", as: "a-invoice.isdoc", to: directory)
        _ = try copyFixture("not-isdoc", "xml", as: "c-other.xml", to: directory)
        _ = try writeCSV("ignored", named: "notes.txt", in: directory)
        let sub = directory.appending(path: "sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        _ = try writeCSV(csvText(), named: "deep.csv", in: sub)

        let files = await ImportFile.read([directory])

        #expect(files.map(\.name) == ["a-invoice.isdoc", "b-export.csv", "c-other.xml"])
        #expect(files.map(\.id) == files.map(\.name))
        #expect(files.map(\.kind) == [.isdoc, .csv, .isdoc])
        #expect(files[0].size != nil)
        guard case .invoice(let invoice) = files[0].content else {
            Issue.record("The ISDOC file should be an invoice.")
            return
        }
        #expect(invoice.number == "20260902")
        guard case .rows(let rows) = files[1].content else {
            Issue.record("The CSV file should be rows.")
            return
        }
        #expect(rows.count == 1)
        #expect(files[2].content == .failed(.notAnIsdocInvoice))
    }

    @Test func upperCaseExtensionsAreAccepted() {
        #expect(ImportFileKind.of(fileName: "A.CSV") == .csv)
        #expect(ImportFileKind.of(fileName: "A.Isdoc") == .isdoc)
        #expect(ImportFileKind.of(fileName: "A.XML") == .isdoc)
        #expect(ImportFileKind.of(fileName: "A.txt") == nil)
        #expect(ImportFileKind.of(fileName: "csv") == nil)
    }

    @Test func anotherFileIsNotCsvOrIsdoc() async throws {
        let directory = try makeTemporaryDirectory()
        let url = try writeCSV("hello", named: "notes.txt", in: directory)

        let files = await ImportFile.read([url])

        #expect(files.count == 1)
        #expect(files[0].kind == nil)
        #expect(files[0].content == .failed(.unsupportedFile))
    }

    @Test func aBrokenFileFailsAloneAndTheOthersAreRead() async throws {
        let directory = try makeTemporaryDirectory()
        let good = try writeCSV(csvText(), named: "good.csv", in: directory)
        let empty = try writeCSV("", named: "empty.csv", in: directory)
        let damaged = try copyFixture("damaged", "isdoc", as: "damaged.isdoc", to: directory)
        let missing = directory.appending(path: "missing.csv")

        let files = await ImportFile.read([good, empty, damaged, missing])

        #expect(files.count == 4)
        guard case .rows = files[0].content else {
            Issue.record("The good file should be read.")
            return
        }
        #expect(files[1].content == .failed(.emptyFile))
        #expect(files[2].content == .failed(.notAnIsdocInvoice))
        #expect(files[3].content == .failed(.unreadableFile))
        #expect(files[3].size == nil)
    }

    @Test func theSourcesLeaveOutTheFailedFiles() async throws {
        let directory = try makeTemporaryDirectory()
        let csv = try writeCSV(csvText(), named: "a.csv", in: directory)
        let isdoc = try copyFixture("czk-21", "isdoc", as: "b.isdoc", to: directory)
        let broken = try copyFixture("no-id", "isdoc", as: "c.isdoc", to: directory)
        let other = try writeCSV("x", named: "d.txt", in: directory)

        let files = await ImportFile.read([csv, isdoc, broken, other])
        let sources = files.sources

        #expect(sources.rows.count == 1)
        #expect(sources.isdocs.map(\.number) == ["20260902"])
    }
}

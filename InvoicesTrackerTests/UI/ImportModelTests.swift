import Foundation
import Testing
@testable import InvoicesTracker

/// The model of the Import screen: the files it collects and the preview it makes of them without writing anything, the
/// import it runs when it is asked to and what it says once that is done, the summary with the lines of the clients,
/// the line of the last import, the sidebar badge while an import runs, the one step at a time that the import shares
/// with the restore and the change of the keys, filling an empty supplier from the export, and Zobrazit faktury.
/// The files are the invented fixtures `fakturoid_sample.csv` (13 rows: 11 invoices, 4 of them to check, 2 skipped)
/// and `fakturoid_reimport.csv`; the server of the ČNB is a stub with the file of 2026. The clock is at noon of
/// 17. 10. 2026. In every expected string `\u{00A0}` is the no-break space.
@Suite(.settlesBackups)
@MainActor
struct ImportModelTests {
    // MARK: Helpers

    /// The counts of the sample, as the lines of the summary and of the file say them.
    private static let sampleCounts = "nové 11, přepsané 0, beze změny 0, přeskočené 2"

    /// The server of the ČNB with the yearly file of 2026, which the paid invoices of the sample need.
    private func cnb() throws -> StubHTTPClient {
        StubHTTPClient([CNBEndpoints.yearly(2026): try Data(contentsOf: fixtureURL("cnb_rok_2026", "txt"))])
    }

    /// An app model that has gone through the first launch, with the supplier skipped, so that it is empty.
    private func makeApp(in directory: URL, http: any HTTPClient) async throws -> AppModel {
        let app = makeAppModel(in: directory, http: http)
        try await startFresh(app)
        return app
    }

    private func sampleURL(_ name: String = "fakturoid_sample") throws -> URL {
        try fixtureURL(name, "csv")
    }

    /// An export of `rows` in a new file of `directory`.
    private func file(_ rows: [FakturoidCSV.Row], named name: String, in directory: URL) throws -> URL {
        try writeCSV(FakturoidCSV.text(rows), named: name, in: directory)
    }

    /// An open invoice in crowns issued on `day`, written as `YYYY-MM-DD`.
    private func openRow(_ number: String, issued day: String) -> FakturoidCSV.Row {
        FakturoidCSV.row([
            "Id": number, "Number": number, "Variable symbol": number, "Issued on": day,
            "Taxable fulfillment due": day, "Due on": day,
        ])
    }

    // MARK: The summary

    @Test func importingTheSampleSaysWhatWasDoneAndWhatClientsCame() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        let version = app.dataVersion

        await model.importAll([try sampleURL()])

        #expect(model.failure == nil)
        #expect(!model.running && app.importBadge == nil && !app.securityStepRunning)
        #expect(model.files.isEmpty && model.preview == nil && model.progress == nil)
        #expect(
            model.summaryLines == [
                "Hotovo – " + Self.sampleCounts + ".",
                "noví odběratelé 4, doplněné údaje u 0",
            ])
        #expect(model.summaryLines.contains { $0.contains("nové 11") })
        #expect(model.summaryLines.contains { $0.contains("přeskočené 2") })
        #expect(!model.summaryLines.contains { $0.contains("ke kontrole") })
        #expect(model.summaryLines.contains { $0.contains("noví odběratelé 4") })
        #expect(model.summary?.added == 11 && model.summary?.skipped == 2 && model.summary?.needsReview == 4)
        #expect(try await #require(app.database).invoiceCount() == 11)
        #expect(app.dataVersion > version)
    }

    @Test func theListsOfTheSummaryAreTheItemsToCheckKeepAndMiss() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        await model.importAll([try sampleURL()])

        let lists = model.summaryLists

        #expect(lists.map(\.title) == ["Ke kontrole (4)"])
        #expect(lists.first?.items == model.summary?.reviewItems)
        #expect(lists.first?.items.contains("20261003 — záporná částka") == true)
    }

    // MARK: The files

    @Test func addingFilesPreviewsThemAndWritesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let database = try #require(app.database)
        let model = ImportModel(app: app)
        let version = app.dataVersion
        let writes = await database.writeCount

        await model.addFiles([try sampleURL()])

        #expect(model.files.map(\.name) == ["fakturoid_sample.csv"])
        #expect(model.failure == nil && !model.running && model.progress == nil && model.summary == nil)
        #expect(model.preview?.newNumbers.count == 11 && model.preview?.skippedNumbers.count == 2)
        #expect(model.outcomeRows.map(\.label) == ["Nové", "Přeskočí se"])
        #expect(model.outcomeRows.map(\.count) == [11, 2])
        #expect(model.importButtonTitle == "Importovat 11\u{00A0}faktur")
        #expect(model.canImport)
        #expect(await database.writeCount == writes && app.dataVersion == version)
        #expect(try await database.invoiceCount() == 0)
        #expect(try await database.clients().isEmpty)
    }

    @Test func aFileOfTheSameNameReplacesTheEarlierOne() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        let first = try file([openRow("20261201", issued: "2026-12-01")], named: "export.csv", in: directory)
        await model.addFiles([first, try sampleURL()])
        #expect(model.files.map(\.name) == ["export.csv", "fakturoid_sample.csv"])
        #expect(model.preview?.newNumbers.count == 12)

        // The same name again, with other rows in it, in the folder of the first.
        _ = try file(
            [openRow("20261202", issued: "2026-12-02"), openRow("20261203", issued: "2026-12-03")],
            named: "export.csv", in: directory)
        await model.addFiles([first])

        #expect(model.files.map(\.name) == ["export.csv", "fakturoid_sample.csv"])
        #expect(model.preview?.newNumbers.count == 13)
        #expect(model.preview?.newNumbers.contains("20261201") == false)
    }

    @Test func removingAFileAndCancellingChangeThePreview() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        await model.addFiles([try sampleURL(), try sampleURL("fakturoid_reimport")])
        #expect(model.preview?.skippedNumbers.count == 4)

        await model.removeFile(named: "fakturoid_reimport.csv")

        #expect(model.files.map(\.name) == ["fakturoid_sample.csv"])
        #expect(model.preview?.skippedNumbers.count == 2)
        // A name that is not collected changes nothing.
        await model.removeFile(named: "other.csv")
        #expect(model.files.count == 1)

        model.cancel()

        #expect(model.files.isEmpty && model.preview == nil && model.outcomeRows.isEmpty)
        #expect(!model.canImport && model.importButtonTitle == "Importovat")
    }

    @Test func removingTheLastFileLeavesNoPreview() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        await model.addFiles([try sampleURL()])

        await model.removeFile(named: "fakturoid_sample.csv")

        #expect(model.files.isEmpty && model.preview == nil && !model.canImport)
    }

    @Test func aFileThatIsNoExportIsListedWithItsErrorAndLeftOutOfTheImport() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        let bank = try writeCSV("Date,Amount\n2026-10-01,5\n", named: "bank.csv", in: directory)

        await model.addFiles([try sampleURL(), bank])

        #expect(model.files.map(\.name) == ["fakturoid_sample.csv", "bank.csv"])
        #expect(ImportPreviewText.fileDetail(of: model.files[1]).hasPrefix("Nevypadá to jako export faktur"))
        #expect(model.failure == nil)
        #expect(model.preview?.newNumbers.count == 11)

        await model.importCollected()

        // The file that failed is left out and the others are imported.
        #expect(model.failure == nil && model.summary?.added == 11)
        #expect(try await #require(app.database).invoiceCount() == 11)
    }

    @Test func severalFilesAreOneImportCountedTogether() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)

        await model.importAll([try sampleURL(), try sampleURL("fakturoid_reimport")])

        #expect(model.summary?.files == ["fakturoid_sample.csv", "fakturoid_reimport.csv"])
        #expect(model.summary?.added == 11 && model.summary?.skipped == 4)
        #expect(model.lastImportLine?.contains("2\u{00A0}soubory") == true)
        #expect(model.files.isEmpty && model.preview == nil)
    }

    // MARK: The last import

    @Test func theLastImportLineNamesTheDayTheFilesAndTheCounts() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        await model.load()
        #expect(model.lastImportLine == nil)

        await model.importAll([try sampleURL()])

        let expected = "Poslední import 17.\u{00A0}10.\u{00A0}2026 · 1\u{00A0}soubor · " + Self.sampleCounts
        #expect(model.lastImportLine == expected)
        // A model made later, as after a relaunch, reads it from the log, and has no files or summary to show.
        let later = ImportModel(app: app)
        await later.load()
        #expect(later.lastImportLine == expected)
        #expect(later.files.isEmpty && later.summary == nil && later.summaryLines.isEmpty)
    }

    @Test func theAppHoldsTheModelWhileTheScreensChangeAndMakesANewOneForOtherData() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = app.importModel
        #expect(app.importModel === model)
        await model.importAll([try sampleURL()])
        app.screen = .overview
        #expect(app.importModel.summary != nil)

        // Data is opened: what the model shows is about the data before.
        await app.open(try #require(app.database))

        #expect(app.importModel !== model)
        #expect(app.importModel.summary == nil)
    }

    @Test func theAppIsNotKeptAliveByTheModelItHoldsForTheImport() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        weak var released: AppModel?
        var held: ImportModel?
        do {
            let app = try await makeApp(in: directory, http: try cnb())
            held = app.importModel
            released = app
            await app.database?.close()
        }

        // The app and its data go when nothing else holds them: the model of the import is not a reason to keep them.
        #expect(released == nil)
        // What is left of the model has nothing to work with, and does nothing.
        let orphan = try #require(held)
        await orphan.addFiles([try sampleURL()])
        await orphan.importCollected()
        await orphan.removeFile(named: "fakturoid_sample.csv")
        await orphan.load()
        await orphan.fillSupplierFromExport()
        orphan.showInvoices()
        #expect(!orphan.running && orphan.files.isEmpty && orphan.preview == nil)
        #expect(orphan.failure == nil && orphan.summary == nil)
    }

    // MARK: An import that runs

    @Test(.hangGuard)
    func importingShowsProgressInTheModelAndTheBadgeAndKeepsOtherStepsOut() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let gate = Gate()
        let app = try await makeApp(in: directory, http: GatedHTTPClient(base: try cnb(), gate: gate))
        let model = ImportModel(app: app)
        await model.addFiles([try sampleURL(), try sampleURL("fakturoid_reimport")])
        let total = try #require(model.preview?.invoiceCount)
        #expect(total == 11)

        let run = Task { await model.importCollected() }
        // The importer asks for the ČNB file of 2026, which is held back.
        await gate.untilARequestWaits()

        #expect(model.running)
        // None is stored before the rates are there.
        #expect(app.importBadge == "0/\(total)")
        #expect(model.progress?.done == 0 && model.progress?.total == total)
        #expect(app.securityStepRunning)
        #expect(!model.canImport && !model.canFillSupplier)
        // The files stay as they were and cannot be changed meanwhile, and another import does nothing.
        await model.addFiles([try sampleURL()])
        await model.removeFile(named: "fakturoid_sample.csv")
        model.cancel()
        await model.importCollected()
        #expect(model.files.map(\.name) == ["fakturoid_sample.csv", "fakturoid_reimport.csv"])
        await #expect(throws: VaultError.busy) { _ = try await app.setTouchID(false) }
        app.request(.restoreBackup)
        #expect(app.settingsAction == nil)

        await gate.open()
        await run.value

        #expect(!model.running && app.importBadge == nil && !app.securityStepRunning)
        #expect(model.progress == nil)
        #expect(model.summary?.added == 11)
        #expect(model.files.isEmpty && model.preview == nil)
    }

    @Test func importingWithNothingToDoIsNotOffered() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let database = try #require(app.database)
        let model = ImportModel(app: app)
        await model.importAll([try sampleURL()])

        // The same export again: every invoice is as it is, so there is nothing to import.
        await model.addFiles([try sampleURL()])
        let logged = try await database.lastImportLog()

        #expect(model.preview?.invoiceCount == 0)
        #expect(!model.canImport && model.importButtonTitle == "Importovat")
        #expect(model.outcomeRows.map(\.label) == ["Beze změny", "Přeskočí se"])
        await model.importCollected()
        // Nothing was imported, so no import was logged.
        #expect(try await database.lastImportLog()?.json == logged?.json)
        #expect(try await database.invoiceCount() == 11)
        #expect(model.files.count == 1 && model.summary == nil && model.failure == nil)
    }

    @Test(.hangGuard)
    func anImportAskedForWhileAStepOfTheVaultRunsSaysSoAndKeepsTheFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        await model.addFiles([try sampleURL()])
        let gate = Gate()
        let step = Task { try await app.runSecurityStep { await gate.pass() } }
        await gate.untilARequestWaits()

        await model.importCollected()

        #expect(model.failure == "Aplikace ještě dokončuje jiný krok s daty. Zkuste to za chvíli znovu.")
        #expect(model.files.count == 1 && model.preview != nil && model.summary == nil && !model.running)
        #expect(app.importBadge == nil)
        #expect(try await #require(app.database).invoiceCount() == 0)
        // Adding a file forgets the failure of the import that was asked for.
        await model.addFiles([try sampleURL()])
        #expect(model.failure == nil && model.files.count == 1)

        await gate.open()
        try await step.value
        await model.importCollected()
        #expect(model.failure == nil && model.summary?.added == 11 && model.files.isEmpty)
    }

    @Test func aLockedVaultKeepsTheCollectedFilesAndSaysSo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let database = try #require(app.database)
        let model = ImportModel(app: app)
        await model.addFiles([try sampleURL()])
        let writes = await database.writeCount
        app.database = nil

        await model.importCollected()

        #expect(model.failure == "Data jsou zamčená. Nejdřív je odemkněte.")
        #expect(model.files.map(\.name) == ["fakturoid_sample.csv"] && model.preview != nil)
        #expect(model.summary == nil && !model.running && app.importBadge == nil)
        #expect(await database.writeCount == writes)
    }

    @Test func filesAddedWhileTheDataIsLockedAreListedAndSayTheyCannotBeChecked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        app.database = nil

        await model.addFiles([try sampleURL()])

        #expect(model.failure == "Data jsou zamčená. Nejdřív je odemkněte.")
        #expect(model.files.map(\.name) == ["fakturoid_sample.csv"])
        #expect(model.preview == nil && !model.canImport && !model.running)
    }

    @Test func anImportThatFailsInTheDatabaseLeavesTheDataAsItWasAndKeepsTheFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let database = try #require(app.database)
        let model = ImportModel(app: app)
        try await database.execute(
            """
            CREATE TRIGGER refuse_the_last_row BEFORE INSERT ON invoice WHEN NEW.number = '20261010'
            BEGIN SELECT RAISE(ABORT, 'refused'); END
            """
        )
        await model.addFiles([try sampleURL()])

        await model.importCollected()

        #expect(model.failure == "Import se nepodařilo dokončit. Data zůstala beze změny.")
        #expect(model.summary == nil && !model.running && app.importBadge == nil && !app.securityStepRunning)
        #expect(model.progress == nil)
        #expect(try await database.invoiceCount() == 0)
        #expect(try await database.clients().isEmpty)
        #expect(model.files.map(\.name) == ["fakturoid_sample.csv"] && model.preview != nil)
    }

    @Test func addingFilesAfterAnImportShowsTheReviewAndForgetsTheResultAndTheFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        await model.importAll([try sampleURL()])
        #expect(model.summary != nil && !model.summaryLines.isEmpty && model.lastImportLine != nil)

        await model.addFiles([try sampleURL("fakturoid_reimport")])

        #expect(model.summary == nil && model.summaryLines.isEmpty && model.summaryLists.isEmpty)
        #expect(model.files.map(\.name) == ["fakturoid_reimport.csv"] && model.preview != nil)
        #expect(!model.canFillSupplier)
    }

    @Test func importIsNotOfferedWhileThePreviewIsMadeAndNoStalePreviewLandsAfterwards() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        await model.addFiles([try sampleURL()])
        #expect(model.canImport)
        let url = try sampleURL("fakturoid_reimport")

        // The file is listed at once and its preview is still being made.
        let adding = Task { await model.addFiles([url]) }
        while model.files.count < 2 {
            await Task.yield()
        }
        #expect(model.previewing && !model.canImport)
        await model.importCollected()
        #expect(!model.running && model.summary == nil && model.files.count == 2)

        await adding.value

        #expect(!model.previewing && model.canImport)
        #expect(model.preview?.skippedNumbers.count == 4)
        await model.importCollected()
        #expect(model.summary?.added == 11 && model.files.isEmpty && model.preview == nil)
        #expect(model.failure == nil && !model.previewing)
    }

    @Test func filesWhosePreviewFailedAreNotImportedAndStayCollected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let database = try #require(app.database)
        let model = ImportModel(app: app)
        try await database.execute("ALTER TABLE invoice RENAME TO invoice_moved")

        await model.addFiles([try sampleURL()])

        #expect(model.preview == nil && model.failure == ImportModel.previewFailedText)
        await model.importCollected()
        #expect(model.files.map(\.name) == ["fakturoid_sample.csv"] && model.summary == nil && !model.running)
        #expect(model.failure == ImportModel.previewFailedText && app.importBadge == nil)
        try await database.execute("ALTER TABLE invoice_moved RENAME TO invoice")
        #expect(try await database.invoiceCount() == 0)
    }

    @Test func filesAddedWhileLockedAreNotImportedOnceTheDataIsBack() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let database = try #require(app.database)
        let model = ImportModel(app: app)
        app.database = nil
        await model.addFiles([try sampleURL()])
        app.database = database

        await model.importCollected()

        #expect(model.preview == nil && model.summary == nil && model.files.count == 1)
        #expect(try await database.invoiceCount() == 0)
    }

    @Test func noFilesIsNoImportAndNoPreview() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)

        await model.addFiles([])
        await model.importCollected()

        #expect(!model.running && model.files.isEmpty && model.preview == nil)
        #expect(model.failure == nil && model.summary == nil)
    }

    // MARK: The supplier of the export

    @Test func anEmptySupplierIsOfferedTheOneOfTheExportAndFillingStoresIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let database = try #require(app.database)
        let model = ImportModel(app: app)
        app.screen = .importer
        #expect(!model.canFillSupplier)

        await model.importAll([try sampleURL()])

        #expect(model.canFillSupplier)
        let version = app.dataVersion
        await model.fillSupplierFromExport()
        let supplier = try await database.supplier()
        #expect(supplier.name == "Jana Vzorová")
        #expect(supplier.street == "Polní 5" && supplier.postcode == "60200" && supplier.city == "Brno")
        #expect(supplier.country == "CZ" && supplier.ico == "11223344" && supplier.dic == "CZ11223344")
        // What the export does not have is what a new supplier has.
        #expect(supplier.email == "" && supplier.phone == "" && supplier.czechFooter == Supplier().czechFooter)
        #expect(!model.canFillSupplier)
        #expect(app.dataVersion > version)
        #expect(
            app.banner
                == AppBanner(
                    text: "Údaje dodavatele jsou doplněné z exportu. Zkontrolujte je v Nastavení › Moje údaje.",
                    screen: .importer))
    }

    @Test func aSupplierWithDetailsIsNotOfferedTheOneOfTheExportAndIsNeverOverwritten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let database = try #require(app.database)
        try await database.saveSupplier(Supplier(name: "Vlastní jméno", ico: "99999999"))
        let model = ImportModel(app: app)

        await model.importAll([try sampleURL()])
        await model.fillSupplierFromExport()

        #expect(!model.canFillSupplier)
        #expect(model.summary?.exportSupplier?.name == "Jana Vzorová")
        let supplier = try await database.supplier()
        #expect(supplier.name == "Vlastní jméno" && supplier.ico == "99999999" && supplier.street == "")
    }

    @Test func aSupplierFilledAfterTheImportIsNotOverwrittenByFillingFromTheExport() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let database = try #require(app.database)
        let model = ImportModel(app: app)
        await model.importAll([try sampleURL()])
        #expect(model.canFillSupplier)

        // Typed in Nastavení while the summary was on the screen.
        try await database.saveSupplier(Supplier(name: "Jiné jméno"))
        await model.fillSupplierFromExport()

        let supplier = try await database.supplier()
        #expect(supplier.name == "Jiné jméno" && supplier.street == "" && supplier.ico == "")
        #expect(!model.canFillSupplier)
        // Nothing was filled, so nothing is said of it.
        #expect(app.banner == nil)
    }

    @Test func anExportWithoutDetailsOfTheSupplierOffersNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: StubHTTPClient())
        let model = ImportModel(app: app)
        let blank = [
            "Your name": "", "Your street": "", "Your city": "", "Your zip": "", "Your country": "",
            "Your registration no": "", "Your vat no": "",
        ]
        let url = try file([FakturoidCSV.row(blank)], named: "plain.csv", in: directory)

        await model.importAll([url])

        #expect(model.summary?.exportSupplier == nil)
        #expect(!model.canFillSupplier)
    }

    // MARK: Zobrazit faktury

    @Test func zobrazitFakturyOpensFakturyOnTheNewestImportedYearWithTheDetailClosed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        app.selectYear(2025)
        app.screen = .importer
        app.pendingDetailInvoiceID = 42
        await model.importAll([try sampleURL()])
        #expect(model.summary?.newestYear == 2026)

        model.showInvoices()

        #expect(app.screen == .invoices)
        #expect(app.asOf.year == 2026 && app.asOf.followsToday)
        #expect(app.pendingDetailInvoiceID == nil)
    }

    @Test func theYearThatIsShownAlreadyKeepsTheDayThatWasPicked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        app.pickAsOf(civilDate("2026-06-30"))
        app.screen = .importer
        await model.importAll([try sampleURL()])

        model.showInvoices()

        #expect(app.screen == .invoices)
        #expect(app.asOf.year == 2026 && app.asOf.asOf == civilDate("2026-06-30"))
    }

    @Test func anImportOfOlderYearsOpensTheNewestOfThem() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: StubHTTPClient())
        let model = ImportModel(app: app)
        let url = try file(
            [openRow("20230101", issued: "2023-01-01"), openRow("20250310", issued: "2025-03-10")], named: "old.csv",
            in: directory)
        app.screen = .importer
        await model.importAll([url])

        model.showInvoices()

        #expect(model.summary?.newestYear == 2025)
        #expect(app.screen == .invoices && app.asOf.year == 2025)
    }

    @Test func aYearAfterTheCurrentOneIsNotOpened() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: StubHTTPClient())
        let model = ImportModel(app: app)
        let url = try file([openRow("20270301", issued: "2027-03-01")], named: "future.csv", in: directory)
        await model.importAll([url])

        model.showInvoices()

        #expect(model.summary?.newestYear == 2027)
        #expect(app.screen == .invoices && app.asOf.year == 2026)
    }

    @Test func anImportThatChangedNothingLeavesTheYearAlone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory, http: try cnb())
        let model = ImportModel(app: app)
        await model.addFiles([try sampleURL()])
        // The same invoices are imported by another model meanwhile, so the preview of this one is out of date.
        await ImportModel(app: app).importAll([try sampleURL()])
        await model.importCollected()
        #expect(model.summary?.added == 0 && model.summary?.unchanged == 11)
        app.selectYear(2025)
        app.screen = .importer

        model.showInvoices()

        #expect(model.summary?.newestYear == nil)
        #expect(app.screen == .invoices && app.asOf.year == 2025)
    }
}

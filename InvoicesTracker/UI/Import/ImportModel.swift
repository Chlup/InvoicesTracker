import Foundation
import Observation
import os

/// The model of the Import screen: it collects the CSV and ISDOC files the person chose or dropped, says what importing
/// them would do, imports them only when asked to, says how far the import is, and, once it is done, says what it did.
///
/// - **Two steps.** Adding files (`addFiles(_:)`) reads them and makes the preview (`preview`) against the database
///   without writing anything. Only `importCollected()` writes: the importer fetches the missing ČNB rates, plans the
///   import again on the data as they are then and stores everything in one transaction, so the counts of the summary
///   may differ from the preview's when the data changed in between. A file that cannot be used is listed with its
///   error and left out of the import.
/// - The import runs while other screens are shown. The app holds this model (`AppModel.importModel`), so that the
///   screen finds the collected files, the progress, or the summary when it comes back, and the sidebar shows the
///   progress meanwhile (`AppModel.importBadge`), "3/11": the invoices the importer has stored of those it stores. The
///   badge goes with the import. The model does not hold the app back: one that outlives it has nothing to work with.
/// - It is one step at a time with a change of the keys and a restore (`AppModel.runSecurityStep(_:)`): an import asked
///   for while one of them runs is refused, and so are they while the import runs.
/// - When the export carries the supplier's details and the supplier profile is empty, the details can be filled in
///   from it (`fillSupplierFromExport()`). Nothing of the export goes to the profile before.
@MainActor
@Observable
final class ImportModel {
    // MARK: Texts

    /// What the screen says of an import that failed for any other reason than a file: the invoices are as they were.
    nonisolated static let failedText = "Import se nepodařilo dokončit. Data zůstala beze změny."

    /// What the screen says when the files cannot be checked: the invoices are as they were.
    nonisolated static let previewFailedText = "Soubory se nepodařilo zkontrolovat. Data zůstala beze změny."

    /// What the green banner says once the supplier is filled in from the export.
    nonisolated static let supplierFilledText =
        "Údaje dodavatele jsou doplněné z exportu. Zkontrolujte je v Nastavení › Moje údaje."

    nonisolated static let supplierFailedText = "Údaje dodavatele se nepodařilo doplnit."

    // MARK: State

    /// The files collected for the next import, in the order they were added in, until the import is done or they are
    /// cancelled. A file that cannot be used is among them, with its error.
    private(set) var files: [ImportFile] = []

    /// What importing the collected files would do, or nil without files and while the preview is made, and when it
    /// cannot be made (`failure` says why).
    private(set) var preview: ImportPlan?

    /// Whether the preview of the collected files is being made. The preview shown is not that of the files until it
    /// is done.
    private(set) var previewing = false

    /// Whether an import runs: from the moment "Importovat" is pressed until it is done or has failed.
    private(set) var running = false

    /// How many invoices the running import has stored of those it stores, from the start of the import until it ends.
    private(set) var progress: (done: Int, total: Int)?

    /// What the import did, once it is done.
    private(set) var summary: ImportSummary?

    /// What the green box of the summary says.
    private(set) var summaryLines: [String] = []

    /// "Poslední import 17. 10. 2026 · 1 soubor · …": the latest import there has been, also one of an earlier run of
    /// the app. Nil when there has been none.
    private(set) var lastImportLine: String?

    /// What went wrong with the import or with filling in the supplier, in Czech, until the next import.
    private(set) var failure: String?

    /// Whether the profile of the supplier has no details, as it was last read.
    private(set) var supplierIsEmpty = false

    /// The app, held weakly: it holds this model.
    @ObservationIgnored private weak var app: AppModel?

    /// What the app works with, kept apart from the app: the clock, the network and the time zone.
    private let dependencies: AppDependencies

    /// Which preview is the newest, so that one that is overtaken is not shown.
    @ObservationIgnored private var previewGeneration = 0

    init(app: AppModel) {
        self.app = app
        dependencies = app.dependencies
    }

    /// The rows of the preview: what will become of the invoices, empty without a preview.
    var outcomeRows: [ImportOutcomeRow] {
        preview.map { ImportPreviewText.outcomeRows(of: $0) } ?? []
    }

    /// How many invoices importing the collected files adds or overwrites.
    private var invoicesToImport: Int {
        preview.map { $0.newNumbers.count + $0.overwrittenNumbers.count } ?? 0
    }

    /// The title of the button that imports: "Importovat 11 faktur", or "Importovat" when there is nothing to import.
    var importButtonTitle: String {
        ImportPreviewText.importButtonTitle(count: invoicesToImport)
    }

    /// Whether "Importovat" is offered: the preview of exactly the collected files is made and adds or overwrites an
    /// invoice, and no import runs.
    var canImport: Bool {
        invoicesToImport > 0 && !running && !previewing && !files.isEmpty
    }

    /// The lists under the summary: what is to check, what the app kept as it was and what could not be added.
    var summaryLists: [ImportList] {
        summary.map { ImportText.lists(of: $0) } ?? []
    }

    /// Whether "Doplnit údaje dodavatele z exportu" is offered: the export of the import that is done carries the
    /// supplier's details, and the profile of the supplier has none.
    var canFillSupplier: Bool {
        !running && supplierIsEmpty && summary?.exportSupplier != nil
    }

    // MARK: Loading

    /// Reads the line of the last import and whether the supplier is empty, as the screen loads again. A failure is
    /// logged and leaves what the screen shows.
    func load() async {
        guard let database = app?.database else { return }
        do {
            let last = try await database.lastImportLog()
            let supplier = try await database.supplier()
            supplierIsEmpty = Self.hasNoDetails(supplier)
            guard !running else { return }
            lastImportLine = try last.map { entry in
                let summary = try JSONDecoder().decode(ImportSummary.self, from: entry.json)
                return ImportText.lastImportLine(of: summary, on: day(of: entry.at))
            }
        } catch {
            AppModel.log("Loading the last import", failedWith: error)
        }
    }

    // MARK: Collecting

    /// Reads the files and folders in `urls`, adds them to the collected files, and makes the preview of all of them.
    /// A file of a name that is collected already replaces it. It writes nothing. It forgets the result of the import
    /// before and the failure, so that the review of the files shows. Does nothing without files or while an import
    /// runs. While the data is locked the files are listed, and `failure` says that they cannot be checked.
    func addFiles(_ urls: [URL]) async {
        guard !urls.isEmpty, !running, app != nil else { return }
        let read = await ImportFile.read(urls)
        // An import may have started while the files were read: the files collected are the ones it imports.
        guard !running, !read.isEmpty else { return }
        failure = nil
        summary = nil
        summaryLines = []
        for file in read {
            if let index = files.firstIndex(where: { $0.id == file.id }) {
                files[index] = file
            } else {
                files.append(file)
            }
        }
        await makePreview()
    }

    /// Takes the file called `name` out of the collected files and makes the preview of the rest. Does nothing while an
    /// import runs.
    func removeFile(named name: String) async {
        guard !running, files.contains(where: { $0.name == name }) else { return }
        files.removeAll { $0.name == name }
        await makePreview()
    }

    /// Drops the collected files and their preview. Does nothing while an import runs.
    func cancel() {
        guard !running else { return }
        previewGeneration += 1
        previewing = false
        files = []
        preview = nil
        failure = nil
    }

    /// Makes the preview of the collected files, read-only. Only the newest preview is shown. A failure is logged and
    /// said; the files stay.
    private func makePreview() async {
        previewGeneration += 1
        let generation = previewGeneration
        guard !files.isEmpty else {
            preview = nil
            previewing = false
            return
        }
        guard let database = app?.database else {
            preview = nil
            previewing = false
            failure = WelcomeTexts.vaultErrorText(.locked)
            return
        }
        let importer = FakturoidImporter(database: database, fetcher: nil, clock: dependencies.clock)
        previewing = true
        do {
            let plan = try await importer.preview(files)
            guard generation == previewGeneration else { return }
            preview = plan
            previewing = false
        } catch {
            guard generation == previewGeneration else { return }
            previewing = false
            AppModel.log("Checking the files to import", failedWith: error)
            preview = nil
            failure = Self.previewFailedText
        }
    }

    // MARK: Importing

    /// Imports the collected files: the ČNB rates of the years the invoices were paid in are fetched when they are
    /// missing, and everything is saved in one go, which `didWrite()` then tells the app of. A file that cannot be used
    /// is left out. When it is done the files and their preview are dropped and the summary is shown.
    ///
    /// The years whose payments the import changed are converted again by the method each uses then, as the payments
    /// may change what they have the uniform rate for, and the import converted them before it wrote them, by the
    /// method their year used then (`AppModel.recomputePaymentsAfterChanges(inYears:)`). Returns when it is done. Does
    /// nothing unless `canImport`: without a preview of exactly the collected files that has something to import, or
    /// while an import runs. While another step of the vault runs or the data is locked it says so (`failure`) and
    /// keeps the files. Any other failure leaves the data as they were and the files collected.
    func importCollected() async {
        guard canImport, let app else { return }
        guard !app.securityStepRunning else {
            failure = WelcomeTexts.vaultErrorText(.busy)
            return
        }
        guard let database = app.database else {
            failure = WelcomeTexts.vaultErrorText(.locked)
            return
        }
        failure = nil
        summary = nil
        summaryLines = []
        running = true
        // No preview that is still being made may land from now on.
        previewGeneration += 1
        // The badge shows the total from the preview, which holds the plan the import is about to make again, until
        // the importer reports the first invoice it stores (it fetches the missing rates first).
        let expected = preview?.invoiceCount ?? 0
        progress = (done: 0, total: expected)
        app.importBadge = expected > 0 ? "0/\(expected)" : nil
        let collected = files
        // The importer reports each invoice it stores from the database: they are shown on the main actor in order.
        let (stored, reportStored) = AsyncStream.makeStream(of: StoredInvoices.self)
        let watcher = Task {
            for await invoices in stored {
                progress = (done: invoices.done, total: invoices.total)
                app.importBadge = "\(invoices.done)/\(invoices.total)"
            }
        }
        do {
            let result = try await app.runSecurityStep {
                let importer = FakturoidImporter(
                    database: database, fetcher: CNBFetcher(http: dependencies.http), clock: dependencies.clock)
                let summary = try await importer.importFiles(collected) { done, total in
                    reportStored.yield(StoredInvoices(done: done, total: total))
                }
                await app.recomputePaymentsAfterChanges(inYears: importer.yearsOfChangedPayments)
                return summary
            }
            finish(with: result)
        } catch {
            stop(because: error)
        }
        // Every invoice reported is shown before the badge goes.
        reportStored.finish()
        await watcher.value
        running = false
        progress = nil
        app.importBadge = nil
        guard summary != nil else { return }
        await readSupplier()
        await app.didWrite()
    }

    /// How many invoices the importer has stored of those it stores.
    private struct StoredInvoices: Sendable {
        let done: Int
        let total: Int
    }

    /// The import is done: its summary is shown, the collected files are dropped, and the line of the last import is
    /// that of this one.
    private func finish(with result: ImportSummary) {
        summary = result
        summaryLines = ImportText.summaryLines(of: result)
        previewGeneration += 1
        files = []
        preview = nil
        lastImportLine = ImportText.lastImportLine(of: result, on: day(of: dependencies.clock.now()))
    }

    /// The import ended with `error`, and nothing is changed: the files stay collected. Another step of the vault or
    /// the lock is said as the vault says it; any other error is logged and said without a word of it.
    private func stop(because error: any Error) {
        switch error {
        case let error as VaultError:
            failure = WelcomeTexts.vaultErrorText(error)
        default:
            AppModel.log("Importing the invoices", failedWith: error)
            failure = Self.failedText
        }
    }

    // MARK: The supplier of the export

    /// Doplnit údaje dodavatele z exportu: fills the supplier profile with the details the export carries (name,
    /// address, country, IČO and DIČ). It fills only a profile that has no details, which is looked at where it is
    /// changed, so nothing the person typed is overwritten, also when they typed something while the summary was shown:
    /// the profile is left as it is then, and nothing is said of it. Does nothing when the supplier is not offered.
    func fillSupplierFromExport() async {
        guard canFillSupplier, let exported = summary?.exportSupplier, let app, let database = app.database else {
            return
        }
        let filled = OSAllocatedUnfairLock(initialState: false)
        do {
            let saved = try await database.updateSupplierDetails { supplier, _ in
                guard Self.hasNoDetails(supplier) else { return }
                supplier.name = exported.name
                supplier.street = exported.street
                supplier.postcode = exported.postcode
                supplier.city = exported.city
                supplier.country = exported.country
                supplier.ico = exported.ico
                supplier.dic = exported.dic
                filled.withLock { $0 = true }
            }
            supplierIsEmpty = Self.hasNoDetails(saved.supplier)
            guard filled.withLock({ $0 }) else { return }
            failure = nil
            app.showBanner(Self.supplierFilledText)
            await app.didWrite()
        } catch {
            AppModel.log("Filling the supplier from the export", failedWith: error)
            failure = Self.supplierFailedText
        }
    }

    /// Reads whether the supplier profile is empty. A failure is logged: the supplier is not offered then.
    private func readSupplier() async {
        guard let database = app?.database else { return }
        do {
            supplierIsEmpty = Self.hasNoDetails(try await database.supplier())
        } catch {
            AppModel.log("Reading the supplier", failedWith: error)
            supplierIsEmpty = false
        }
    }

    /// Whether `supplier` has no details of the person: the country and the footer of the Czech invoices a new supplier
    /// has are not.
    private nonisolated static func hasNoDetails(_ supplier: Supplier) -> Bool {
        [
            supplier.name, supplier.street, supplier.postcode, supplier.city, supplier.ico, supplier.dic,
            supplier.email, supplier.phone,
        ].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: Zobrazit faktury

    /// Zobrazit faktury: shows Faktury for the newest year the import brought invoices of, as it is entered, with no
    /// invoice open. A year after the current one is not shown, and an import that changed no invoice leaves the year
    /// where it is.
    func showInvoices() {
        guard let app else { return }
        if let year = summary?.newestYear {
            let shown = min(year, app.today.year)
            // The year that is shown already stays as it is, with the day that was picked in it.
            if app.asOf.year != shown {
                app.selectYear(shown)
            }
        }
        app.pendingDetailInvoiceID = nil
        app.screen = .invoices
    }

    // MARK: Helpers

    /// The day of `instant` in the time zone of the Mac.
    private func day(of instant: Date) -> CivilDate {
        CivilDate.today(now: instant, timeZone: dependencies.timeZone())
    }
}

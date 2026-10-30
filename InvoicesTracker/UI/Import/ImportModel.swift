import Foundation
import Observation
import os

/// The model of the Import screen: it imports the Fakturoid exports the person chose or dropped, says how far each file
/// is, and, once the import is done, says what it did.
///
/// - Several files are one import (`FakturoidImporter`): they are all read before anything is changed, and a file that
///   cannot be read stops the import, which then changes nothing. So the counts are those of the import, not of a file;
///   they are listed with a file only when the import has the one.
/// - The import runs while other screens are shown. The app holds this model (`AppModel.importModel`), so that the
///   screen finds the progress, or the summary, when it comes back, and the sidebar shows the rows meanwhile, "0/27":
///   the rows imported of the rows of the files read so far (`AppModel.importBadge`). The importer stores everything in
///   one go once it has read the files, so none is imported before that, and the badge goes with the import. The model
///   does not hold the app back: one that outlives it has nothing to work with.
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

    /// What follows the name of a file that cannot be imported.
    nonisolated static let nothingImportedText = "Nic se neimportovalo."

    /// What the green banner says once the supplier is filled in from the export.
    nonisolated static let supplierFilledText =
        "Údaje dodavatele jsou doplněné z exportu. Zkontrolujte je v Nastavení › Moje údaje."

    nonisolated static let supplierFailedText = "Údaje dodavatele se nepodařilo doplnit."

    // MARK: Files

    /// How far a file of the import is.
    enum Stage: Equatable, Sendable {
        /// Not read yet.
        case waiting

        /// Read. The import goes on with it, or an error of the files stopped it before anything was changed.
        case read

        /// Imported.
        case done

        /// Cannot be imported, and why, in Czech.
        case failed(String)
    }

    /// A file of the import as the card of the progress lists it.
    struct FileRow: Identifiable, Equatable, Sendable {
        let id: Int
        let name: String

        /// "5,5 kB", or nil when the size cannot be read.
        let size: String?
        var stage: Stage

        /// How many rows the file has, once it is read.
        var rows: Int?

        /// The counts of the import, for an import of one file only.
        var counts: String?
    }

    // MARK: State

    /// Whether an import runs: from the moment the files are chosen until it is done or has failed.
    private(set) var running = false

    /// The files of the import in the order they were chosen in, until the next import.
    private(set) var fileRows: [FileRow] = []

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

    /// How many files of the running import were read.
    @ObservationIgnored private var filesRead = 0

    init(app: AppModel) {
        self.app = app
        dependencies = app.dependencies
    }

    /// The names of the files with their counts, in the order of the import. The counts are empty where the import has
    /// more than one file.
    var fileProgress: [(name: String, counts: String)] {
        fileRows.map { (name: $0.name, counts: $0.counts ?? "") }
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

    /// What the line of a file says: where it is, or why it cannot be imported.
    func statusText(of row: FileRow) -> String {
        switch row.stage {
        case .waiting: running ? "Čeká…" : "Nepřečteno"
        case .read: running ? "Zpracovávám…" : "Přečteno"
        case .done: row.rows.map { "Hotovo · " + ImportText.rows($0) } ?? "Hotovo"
        case .failed(let reason): reason
        }
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

    // MARK: Importing

    /// Imports the invoices in `urls`: the files are read, the ČNB rates of the years the invoices were paid in are
    /// fetched when they are missing, and everything is saved in one go, which `didWrite()` then tells the app of.
    /// The years whose payments the import changed are converted again by the method each uses then, as the payments
    /// may change what they have the uniform rate for, and the import converted them before it wrote them, by the
    /// method their year used then (`AppModel.recomputePaymentsAfterChanges(inYears:)`). Returns when it is done. Does
    /// nothing without files, while an import runs, and says so while another step of the vault runs (`failure`) or the
    /// data is locked.
    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty, !running, let app else { return }
        guard !app.securityStepRunning else {
            failure = WelcomeTexts.vaultErrorText(.busy)
            return
        }
        guard let database = app.database else {
            failure = WelcomeTexts.vaultErrorText(.locked)
            return
        }
        begin(urls, in: app)
        do {
            let result = try await app.runSecurityStep {
                let importer = FakturoidImporter(
                    database: database, fetcher: CNBFetcher(http: dependencies.http), clock: dependencies.clock)
                let summary = try await importer.importFiles(urls) { progress in
                    noteRead(progress, in: app)
                }
                await app.recomputePaymentsAfterChanges(inYears: importer.yearsOfChangedPayments)
                return summary
            }
            finish(with: result)
        } catch {
            stop(because: error)
        }
        running = false
        app.importBadge = nil
        guard summary != nil else { return }
        await readSupplier()
        await app.didWrite()
    }

    private func begin(_ urls: [URL], in app: AppModel) {
        failure = nil
        summary = nil
        summaryLines = []
        fileRows = urls.enumerated().map { index, url in
            FileRow(id: index, name: url.lastPathComponent, size: Self.size(of: url), stage: .waiting)
        }
        filesRead = 0
        running = true
        // The rows are not known before the first file is read.
        app.importBadge = nil
    }

    /// The files of `progress` are read: each says how many rows it has, and the badge counts the rows read so far, of
    /// which none is imported yet.
    private func noteRead(_ progress: ImportProgress, in app: AppModel) {
        filesRead = progress.filesRead
        for (index, rows) in progress.rowCounts.enumerated() where fileRows.indices.contains(index) {
            fileRows[index].stage = .read
            fileRows[index].rows = rows
        }
        app.importBadge = "0/\(progress.rowsRead)"
    }

    private func finish(with result: ImportSummary) {
        summary = result
        summaryLines = ImportText.summaryLines(of: result)
        for index in fileRows.indices {
            fileRows[index].stage = .done
        }
        if fileRows.count == 1 {
            fileRows[0].counts = ImportText.counts(of: result)
        }
        lastImportLine = ImportText.lastImportLine(of: result, on: day(of: dependencies.clock.now()))
    }

    /// The import ended with `error`, and nothing is changed: a file that cannot be read is named, with its reason, on
    /// its line and in the failure; any other error is logged and said without a word of it.
    private func stop(because error: any Error) {
        switch error {
        case let error as FileImportError:
            if filesRead < fileRows.count {
                fileRows[filesRead].stage = .failed(error.reason.errorDescription ?? Self.failedText)
            }
            failure = (error.errorDescription ?? Self.failedText) + " " + Self.nothingImportedText
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

    /// "5,5 kB" for the file at `url`, or nil when its size cannot be read, which is logged.
    private static func size(of url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            guard let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
            return ImportText.fileSize(bytes: bytes)
        } catch {
            AppModel.log("Reading the size of a file", failedWith: error)
            return nil
        }
    }
}

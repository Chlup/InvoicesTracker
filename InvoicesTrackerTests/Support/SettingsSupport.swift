import Foundation
import Testing
@testable import InvoicesTracker

/// An app model on the folder `Data` inside `directory` that has gone through the first launch (code no. 1 of the
/// clock's day, Touch ID on), as of noon of 17. 10. 2026 unless the clock says otherwise. The refresh is made but not
/// started unless `startsRefresh`; `sleep` and `resolveBookmark` are those of `makeAppModel`.
@MainActor
func makeSettingsApp(
    in directory: URL,
    clock: ManualClock = ManualClock(localNoon(2026, 10, 17)),
    scheduler: ManualScheduler = ManualScheduler(),
    startsRefresh: Bool = false,
    sleep: @escaping @Sendable (Duration) async throws -> Void = patientWait,
    resolveBookmark: @escaping @Sendable (Data, URL.BookmarkResolutionOptions) async throws -> URL =
        BackupService.resolveBookmark
) async throws -> AppModel {
    let app = makeAppModel(
        in: directory, clock: clock, scheduler: scheduler, startsRefresh: startsRefresh, sleep: sleep,
        resolveBookmark: resolveBookmark)
    try await startFresh(app)
    return app
}

/// A backup made on another Mac, whose device key this Mac's protector does not take for its own: the data of that Mac
/// with `invoices` invented invoices, started on 30. 9. 2026, so that its code is "kód č. 1 z 30. 9. 2026", and with
/// `folder` as its folder of the backups outside the Mac when one is given. Returns the file, the code that opens it
/// and the code's label.
@MainActor
func makeBackupOfAnotherMac(
    in directory: URL, invoices: Int, folder: URL? = nil
) async throws -> (url: URL, code: String, label: String) {
    let other = makeAppModel(
        in: directory.appending(path: "Other Mac", directoryHint: .isDirectory), device: OtherMacProtector(),
        clock: ManualClock(localNoon(2026, 9, 30)))
    let code = try await startFresh(other)
    if let folder {
        _ = try await other.setBackupFolder(folder)
    }
    let database = try #require(other.database)
    for number in 0..<invoices {
        try await database.saveInvoice(Invoice.fixture(number: "2026090\(number + 1)"))
    }
    await other.didWriteAndBackUp()
    let backup = try #require(try other.backups.localBackups().first)
    let label = try #require(other.vault.requiredRecoveryLabel)
    await database.close()
    return (backup.url, code, label)
}

/// A paid invoice of 1 000 USD without VAT, supplied on 30. 9. 2025 and paid on 7. 10. 2025 at the ČNB rate of that
/// day, 24,000 Kč.
func paidDollarInvoiceOf2025() -> Invoice {
    var invoice = Invoice.fixture(
        number: "20251001", currency: .usd, duzp: "2025-09-30", dueDate: "2025-10-14",
        items: [.fixture("10", at: 10_000)], vatMode: .outsideCountry,
        invoiceRate: storedRate("USD", "24.100", declaredOn: "2025-09-30"))
    invoice.payment = Payment(
        date: civilDate("2025-10-07"), conversion: .cnbDaily, czkNetHalere: 2_400_000, czkVatHalere: 0,
        rate: storedRate("USD", "24.000", declaredOn: "2025-10-07"))
    return invoice
}

extension Database {
    /// Writes a way of conversion the app does not know into the payment of the invoice `id`, as damaged data would
    /// have it: the payments of the year of the invoice cannot be listed then.
    func makeUnreadable(paymentOf id: Int64) throws {
        try write { connection in
            try connection.run("UPDATE payment SET conversion = 'unknown' WHERE invoice_id = ?", [.integer(id)])
        }
    }
}

/// The texts of the Czech dates the expectations are written with: `"17. 10. 2026"` with the no-break spaces of
/// `CzechFormat`.
func czechDate(_ iso: String) -> String {
    CzechFormat.date(civilDate(iso))
}

// MARK: - Steps of the vault that fail half way

/// Makes a step of the vault of `app` fail at one of its moments, as a busy or a damaged disk would, after the vault has
/// locked the data or before: `release()` undoes what it did and takes the trap away.
@MainActor
final class VaultStepTrap {
    private let app: AppModel
    private var writer: SQLiteConnection?
    private var lockedPaths: [(path: String, mode: Int)] = []

    private init(_ app: AppModel) {
        self.app = app
    }

    /// The rekey of the next new recovery code fails: at `.bothKeySetsSaved` another connection holds the lock for
    /// writing, so the rekey cannot begin. The keys file of the old key is put back and the vault locks.
    static func failingRekey(of app: AppModel) throws -> VaultStepTrap {
        let trap = VaultStepTrap(app)
        let key = try #require(app.vault.dataKey)
        let path = app.vault.paths.database.path(percentEncoded: false)
        app.vault.stepObserver = { [weak trap] step in
            guard step == .bothKeySetsSaved else { return }
            do {
                let connection = try SQLiteConnection(path: path, key: key)
                try connection.execute("BEGIN IMMEDIATE")
                trap?.writer = connection
            } catch {
                Issue.record(error)
            }
        }
        return trap
    }

    /// The check of the next new recovery code fails after the rekey: at `.databaseRekeyed` the database cannot be
    /// opened on a connection of its own. The vault locks with the slots of both keys on disk, and the new key in force.
    static func failingCheckAfterTheRekey(of app: AppModel) -> VaultStepTrap {
        trap(app, at: .databaseRekeyed, path: app.vault.paths.database, mode: 0o000, restoring: 0o644)
    }

    /// The next restore fails before its database is put in place: at `.restoreKeySetsSaved` the folder of the data
    /// cannot be written. The vault has locked the data, which stays as it was.
    static func failingRestoreBeforeTheSwap(of app: AppModel) -> VaultStepTrap {
        trap(app, at: .restoreKeySetsSaved, path: app.vault.paths.directory, mode: 0o555, restoring: 0o755)
    }

    /// The next restore fails after its database is put in place: at `.restoredKeysSettled` the restored database
    /// cannot be opened. The vault has locked the data, and the restored database is the one on disk.
    static func failingRestoreAfterTheSwap(of app: AppModel) -> VaultStepTrap {
        trap(app, at: .restoredKeysSettled, path: app.vault.paths.database, mode: 0o000, restoring: 0o644)
    }

    private static func trap(
        _ app: AppModel, at moment: VaultStep, path url: URL, mode: Int, restoring: Int
    ) -> VaultStepTrap {
        let trap = VaultStepTrap(app)
        let path = url.path(percentEncoded: false)
        app.vault.stepObserver = { [weak trap] step in
            guard step == moment else { return }
            do {
                try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
                trap?.lockedPaths.append((path, restoring))
            } catch {
                Issue.record(error)
            }
        }
        return trap
    }

    /// Undoes what the trap did, and takes it away from the vault.
    func release() {
        do {
            try writer?.execute("ROLLBACK")
        } catch {
            Issue.record(error)
        }
        writer?.close()
        writer = nil
        for locked in lockedPaths {
            try? FileManager.default.setAttributes([.posixPermissions: locked.mode], ofItemAtPath: locked.path)
        }
        lockedPaths = []
        app.vault.stepObserver = nil
    }
}

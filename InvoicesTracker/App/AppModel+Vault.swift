import Foundation

/// What a change of the keys while the data is open tells: what the vault says of it, and the backup outside the Mac
/// that follows it.
nonisolated struct KeyChangeResult<Outcome: Equatable & Sendable>: Equatable, Sendable {
    /// What the vault says of the change (`KeyChangeOutcome`, `NewCodeOutcome`), with the local backup it made.
    let outcome: Outcome

    /// The backup outside the Mac that follows the change: nil when no folder is set, otherwise whether it was made.
    let offMacBackupMade: Bool?
}

/// What restoring a backup while the data was open tells.
nonisolated struct RestoreOutcome: Equatable, Sendable {
    /// The label of the recovery code that opens the restored data, such as "kód č. 1 z 17. 10. 2026"; nil when the
    /// data names none.
    let codeLabel: String?

    /// Whether that code is another one than the code that opened the data before the restore: the code of an older
    /// backup, or of another Mac.
    let codeChanged: Bool

    /// Whether the settings of the backup named another folder of the backups outside the Mac than this Mac's, which
    /// the restored data keeps instead.
    let backupHadAnotherFolder: Bool
}

/// A change of the keys or a restore that failed after the vault had locked the data: what it was doing, for the
/// notice that the next unlock of the same data gives on Nastavení › Zabezpečení a zálohy (`AppModel.securityNotice`).
nonisolated enum InterruptedChange: Equatable, Sendable {
    /// The new recovery code with this number, made on this day, was being put in force in place of the code labelled
    /// `replacedLabel`, numbered `replacedNumber`.
    case newCode(number: Int, created: CivilDate, replacedLabel: String?, replacedNumber: Int?)

    /// The backup named `title` was being restored in place of the data, whose database was the file `databaseFile`,
    /// with `folder` as this Mac's folder of the backups outside the Mac.
    case restore(title: String, databaseFile: FileIdentity?, folder: OffMacFolder)
}

/// Which file a path leads to: the disk and the number of the file on it. A file put in the place of another under its
/// name is another file.
nonisolated struct FileIdentity: Equatable, Sendable {
    let device: Int
    let file: Int

    /// The identity of the file at `url`, or nil when it cannot be read, which is logged.
    static func of(_ url: URL) -> FileIdentity? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        } catch {
            AppModel.log("Reading which file the database is", failedWith: error)
            return nil
        }
        guard let device = attributes[.systemNumber] as? Int, let file = attributes[.systemFileNumber] as? Int else {
            return nil
        }
        return FileIdentity(device: device, file: file)
    }
}

/// This Mac's folder of the backups outside the Mac, as the settings have it: its bookmark, which only this Mac can
/// resolve, its name, its last backup and when it was chosen.
nonisolated struct OffMacFolder: Equatable, Sendable {
    let bookmark: Data?
    let name: String?
    let lastBackup: Date?
    let chosen: Date?

    init(_ settings: AppSettings) {
        bookmark = settings.backupFolderBookmark
        name = settings.backupFolderName
        lastBackup = settings.lastOffMacBackup
        chosen = settings.backupFolderChosen
    }

    func apply(to settings: inout AppSettings) {
        settings.backupFolderBookmark = bookmark
        settings.backupFolderName = name
        settings.lastOffMacBackup = lastBackup
        settings.backupFolderChosen = chosen
    }
}

/// The steps of the vault that change the data while it is open — Touch ID on or off, a new recovery code, a restore
/// of a backup in its place — and what the app does around them. Each is one step of Zabezpečení a zálohy
/// (`runSecurityStep(_:)`). A step the vault refuses changes nothing. When the vault locked the data on the way (a
/// rekey or a restore that failed half way), the app locks too, and the next unlock of the same data says on Nastavení
/// what the step left in force (`securityNotice`); a step that succeeds takes such a notice away.
extension AppModel {
    /// Turns unlocking with Touch ID on or off (`Vault.setTouchID(_:)`): the data key is sealed into a new device slot
    /// of this Mac, and a local backup is made; then the backup outside the Mac, when a folder is set, so that the
    /// newest backup there carries the new slot too. The settings are read again, as the vault records the choice and
    /// the backup in the data. Throws `VaultError.busy` while another step runs, and what the vault throws; nothing
    /// changes then.
    func setTouchID(_ on: Bool) async throws -> KeyChangeResult<KeyChangeOutcome> {
        try await runSecurityStep {
            let outcome = try await vault.setTouchID(on)
            securityNotice = nil
            await reloadAppSettings()
            return KeyChangeResult(outcome: outcome, offMacBackupMade: await backUpOffMacAfterKeyChange())
        }
    }

    /// Puts the new recovery code of `pending` in force once the person has stored it
    /// (`Vault.commitNewRecoveryCode(_:)`), and keeps the label and the number of the code it replaced, which the card
    /// of the code names for the older backups; then makes the backup outside the Mac, when a folder is set. Throws
    /// `VaultError.busy` while another step runs, and what the vault throws: `VaultError.outdatedCode` when the keys
    /// changed since the code was made, `.locked`, `.busy`; nothing changes then, unless the vault locked the data, and
    /// then the app locks too.
    func commitNewRecoveryCode(_ pending: PendingRecoveryCode) async throws -> KeyChangeResult<NewCodeOutcome> {
        try await runSecurityStep {
            let replaced = vault.keys?.newestRecoverySlot
            let outcome: NewCodeOutcome
            do {
                outcome = try await vault.commitNewRecoveryCode(pending)
            } catch {
                if database != nil, vault.database == nil {
                    lockAfterFailedChange(
                        .newCode(
                            number: pending.number, created: pending.created, replacedLabel: replaced?.label,
                            replacedNumber: replaced?.number))
                }
                throw error
            }
            securityNotice = nil
            let label = outcome.previousLabel.isEmpty ? nil : outcome.previousLabel
            await updateAppSettings(Self.recordingReplacedCode(label: label, number: replaced?.number))
            return KeyChangeResult(outcome: outcome, offMacBackupMade: await backUpOffMacAfterKeyChange())
        }
    }

    /// The change of the settings that records the recovery code which the code in force replaced, labelled `label`
    /// and numbered `number`: the card of the code names it for the older backups. No label, no number.
    private nonisolated static func recordingReplacedCode(
        label: String?, number: Int?
    ) -> @Sendable (inout AppSettings) -> Void {
        let number = label == nil ? nil : number
        return { settings in
            settings.replacedRecoveryCodeLabel = label
            settings.replacedRecoveryCodeNumber = number
        }
    }

    /// The backup outside the Mac after a change of the keys: nil when no folder is set, otherwise whether it was made.
    /// A backup outside the Mac that runs is waited for, and a fresh one with the new slots is made after it.
    private func backUpOffMacAfterKeyChange() async -> Bool? {
        guard appSettings.backupFolderBookmark != nil else { return nil }
        return await backUpOffMac(afterTheRunningOne: true)
    }

    /// Obnovit ze zálohy… while the data is open: restores the backup at `url`, which the person knows as `title` (the
    /// name of the file unless given), in place of the data (`Vault.restore(from:recoveryCode:)`, which backs up the
    /// open data first) and opens the restored data as an unlock opens data: with its settings and years, a refresh of
    /// its own and its backups when they are due; the screens load again. `recoveryCode` is needed for a backup that
    /// this Mac does not open itself. The restored data keeps this Mac's folder of the backups outside the Mac, as the
    /// bookmark of a folder belongs to the Mac that made it.
    ///
    /// The invoice editor works on the data that is replaced, so it is closed first: the person has been asked
    /// "Zahodit rozepsanou fakturu?" when it held changes. The refresh stops and the wake of the local backup is
    /// cancelled for the time of the restore. When the restore fails before anything changed, the data stays open and
    /// goes on as before; when it fails after the vault locked the data, the app locks.
    ///
    /// Throws `VaultError.locked` while the data is locked, `VaultError.busy` while another step runs, and what the
    /// vault throws.
    func restoreWhileOpen(from url: URL, recoveryCode: String?, title: String? = nil) async throws -> RestoreOutcome {
        try await runSecurityStep {
            guard phase == .ready, let current = database else { throw VaultError.locked }
            let codeBefore = vault.keys?.newestRecoverySlot
            let databaseFile = FileIdentity.of(vault.paths.database)
            let folder = OffMacFolder(appSettings)
            editorRequest = nil
            refresh?.stop()
            cancelLocalBackupWake()
            let restored: Database
            do {
                restored = try await Self.withSecurityScopedAccess(to: url) {
                    try await vault.restore(from: url, recoveryCode: recoveryCode)
                }
            } catch {
                if vault.database == nil {
                    lockAfterFailedChange(
                        .restore(title: title ?? url.lastPathComponent, databaseFile: databaseFile, folder: folder))
                } else if vault.database === current {
                    // Nothing changed: the data goes on as it was.
                    if dependencies.startsRefresh {
                        refresh?.start()
                    }
                    await backUpLocallyIfDue()
                }
                throw error
            }
            let backupHadAnotherFolder = await keep(folder, in: restored)
            pendingDetailInvoiceID = nil
            pendingUniformRate = nil
            uniformRateReminderYear = nil
            uniformRateOffer = nil
            await open(restored, afterRestore: true)
            reloadScreens()
            return RestoreOutcome(
                codeLabel: vault.requiredRecoveryLabel, codeChanged: vault.keys?.newestRecoverySlot != codeBefore,
                backupHadAnotherFolder: backupHadAnotherFolder)
        }
    }

    /// Puts this Mac's folder of the backups outside the Mac, `folder`, into the settings of the restored data, in
    /// place of the folder of the backup. Returns whether the backup named another folder. A failure is logged: the
    /// restore is done, and only the folder of the backup stays.
    private func keep(_ folder: OffMacFolder, in restored: Database) async -> Bool {
        do {
            let fromBackup = try await restored.appSettings()
            let hadAnother = fromBackup.backupFolderBookmark != nil && fromBackup.backupFolderName != folder.name
            try await restored.updateAppSettings { folder.apply(to: &$0) }
            return hadAnother
        } catch {
            Self.log("Keeping the folder outside the Mac after a restore", failedWith: error)
            return false
        }
    }

    /// What the notice of a new code that is in force says last, when no backup holds its key: a backup made since
    /// (Zálohovat teď) takes the notice away.
    nonisolated static let backupWithNewKeyMissingText =
        "Záloha s novým klíčem se ale neuložila – zálohujte data tlačítkem Zálohovat teď."

    /// What `change`, which a lock cut off, left in force, now that the unlock of the same data opened `database`, as
    /// the notice of Nastavení says it. What the change left half done on disk is finished first: a new code that is in
    /// force after all gets the code it replaced recorded, and a restore that had put its database in place gets this
    /// Mac's folder of the backups outside the Mac.
    func settle(_ change: InterruptedChange, in database: Database) async -> String {
        let label = vault.requiredRecoveryLabel ?? "kód pro obnovení"
        switch change {
        case .newCode(let number, let created, let replacedLabel, let replacedNumber):
            guard vault.keys?.newestRecoverySlot?.number == number else {
                return "Nový kód č. \(number) se nepodařilo použít – platí dál \(label). Nový kód zahoďte."
            }
            do {
                _ = try await database.updateAppSettings(
                    Self.recordingReplacedCode(label: replacedLabel, number: replacedNumber))
            } catch {
                Self.log("Recording the code that was replaced", failedWith: error)
            }
            return "Nový kód č. \(number) z \(CzechFormat.date(created)) platí. " + Self.backupWithNewKeyMissingText
        case .restore(let title, let fileBefore, let folder):
            let fileNow = FileIdentity.of(vault.paths.database)
            if let fileBefore, let fileNow, fileBefore != fileNow {
                _ = await keep(folder, in: database)
                return "Data jsou obnovená ze zálohy „\(title)“, aplikace je ale mezitím zamkla. Otevírá je \(label)."
            }
            if fileBefore != nil, fileBefore == fileNow {
                return "Obnovení ze zálohy „\(title)“ se nepodařilo dokončit. Otevřená jsou data jako před obnovením a"
                    + " otevírá je \(label)."
            }
            return "Obnovení ze zálohy „\(title)“ se nepodařilo dokončit. Otevřená data otevírá \(label)."
        }
    }
}

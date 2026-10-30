import CryptoKit
import Foundation

/// What Zálohovat teď made.
nonisolated struct BackupNowOutcome: Equatable, Sendable {
    /// When the local backup was made.
    let created: Date

    /// The backup outside the Mac: nil when no folder is set for it, otherwise whether it was made.
    let offMac: Bool?
}

/// The backups of the open data: the local backup a change waits for, made an hour after the last one at the earliest,
/// with the one wake that makes it when the hour is up, the daily backup outside the Mac, and the backups the person
/// asks for in Nastavení: one at once, an export, and the first one in a new folder outside the Mac. Each of those is a
/// step of Zabezpečení a zálohy, one at a time across the app (`runSecurityStep(_:)`).
///
/// A write starts the backups that are due and does not wait for them (`startBackupsAfterWrite()`). One local backup
/// runs at a time, and one backup outside the Mac: a backup asked for while one runs leaves its change to the next.
///
/// The automatic backups outside the Mac — after a write, the daily check, the launch — show no UI of the system when
/// they reach the folder, and after one that failed the next automatic one waits an hour. Those the person asked for —
/// Zálohovat teď, the first one into a folder just chosen, those after a change of the keys or a restore — may show the
/// system's UI and are always tried.
///
/// A backup takes a while, and the data can be replaced meanwhile (a restore): what a backup records — the moment of
/// the last backup, the changes it holds — is recorded only while the data it was made of is the data that is open,
/// and a backup outside the Mac only while its folder is the folder set.
extension AppModel {
    /// How much later than its time the wake of the local backup may come, so that the system can bundle it.
    private static let localBackupWakeTolerance: TimeInterval = 60

    /// How long a backup outside the Mac waits for the one that runs there, and for its own end, before it goes on
    /// without the answer: a folder on a disk or a share that does not answer must not keep a change of the keys, the
    /// sheet that waits for it and every other step blocked. The backup is not stopped; only the wait for it is, and
    /// a backup that a wait gave up on is not waited for again.
    static let offMacWaitLimit = Duration.seconds(20)

    /// How long the automatic backups outside the Mac wait after one that failed: a disk that is not connected or a
    /// share that is asleep is tried at most once an hour, not at every write.
    static let offMacRetryInterval: TimeInterval = 60 * 60

    /// Whether a change waits for the local backup: one of this session that no backup holds for certain yet, or one
    /// that an earlier session left waiting.
    private var changeWaitsForBackup: Bool {
        changeCount > changesBackedUp || appSettings.localBackupPendingSince != nil
    }

    /// Whether to remind the person of the backup outside the Mac: a folder is set and 30 days have passed since the
    /// last backup there, or since the folder was chosen while it has had none.
    var needsOffMacReminder: Bool {
        let since = [appSettings.lastOffMacBackup, appSettings.backupFolderChosen].compactMap { $0 }.max()
        return backups.needsOffMacReminder(last: since, folderSet: appSettings.backupFolderBookmark != nil)
    }

    /// Records in the settings that a change waits for the local backup, from now, unless one waits already.
    func markChangeWaitingForBackup() async {
        let now = dependencies.clock.now()
        await updateAppSettings { settings in
            if settings.localBackupPendingSince == nil {
                settings.localBackupPendingSince = now
            }
        }
    }

    /// Starts the backups that are due after a write: the local one, then the automatic one outside the Mac. Nothing
    /// waits for them but the backups of the next write, which start after them (`backupsAfterWrite`).
    func startBackupsAfterWrite() {
        let before = backupsAfterWrite
        backupsAfterWrite = Task {
            await before?.value
            await backUpLocallyIfDue()
            await backUpOffMacIfDue()
        }
    }

    // MARK: The local backup

    /// Makes the local backup when a change waits for it and an hour has passed since the last backup, and records the
    /// backup as the last one. Before the hour is up, the one wake that makes the backup then is armed. A last backup
    /// later than now is one of a clock that was set back, and the backup is due.
    ///
    /// The change stops waiting only when the backup holds it for certain: when no change was told of while the backup
    /// was made. A change that came meanwhile, and a backup that failed, are backed up an hour later; a failure is
    /// logged. A backup that ends after the data was replaced is of the data before: nothing of it is recorded, and the
    /// data open now is looked at again.
    func backUpLocallyIfDue() async {
        guard changeWaitsForBackup else {
            cancelLocalBackupWake()
            return
        }
        if let lastBackup = appSettings.lastLocalBackup {
            let now = dependencies.clock.now()
            let due = lastBackup + BackupService.localBackupInterval
            guard now >= due || lastBackup > now else {
                armLocalBackupWake(at: due)
                return
            }
        }
        guard !makingLocalBackup, let open = openData() else { return }
        makingLocalBackup = true
        cancelLocalBackupWake()
        let changesBefore = changeCount
        let sameData: Bool
        do {
            let backup = try await backups.makeBackup(database: open.database, key: open.key, keys: open.keys)
            sameData = await recordLocalBackup(backup, of: open.database, changesBefore: changesBefore)
        } catch {
            Self.log("Making a local backup", failedWith: error)
            sameData = database === open.database
            if sameData {
                armLocalBackupWake(at: dependencies.clock.now() + BackupService.localBackupInterval)
            }
        }
        makingLocalBackup = false
        if !sameData {
            await backUpLocallyIfDue()
        }
    }

    /// Zálohovat teď: makes the local backup at once, whenever the last one was, and records it; then the backup
    /// outside the Mac, when a folder is set for it, also at once, after the one that runs there, if one does. Throws
    /// `VaultError.locked` while the data is locked, `VaultError.busy` while another step runs or the local backup is
    /// being made, and what making the local backup throws; a backup outside the Mac that fails is logged and said in
    /// the outcome.
    func backUpNow() async throws -> BackupNowOutcome {
        try await runSecurityStep {
            guard let open = openData() else { throw VaultError.locked }
            guard !makingLocalBackup else { throw VaultError.busy }
            makingLocalBackup = true
            defer { makingLocalBackup = false }
            cancelLocalBackupWake()
            let changesBefore = changeCount
            let backup: BackupResult
            do {
                backup = try await backups.makeBackup(database: open.database, key: open.key, keys: open.keys)
            } catch {
                if changeWaitsForBackup, database === open.database {
                    armLocalBackupWake(at: dependencies.clock.now() + BackupService.localBackupInterval)
                }
                throw error
            }
            await recordLocalBackup(backup, of: open.database, changesBefore: changesBefore)
            // The backup holds the keys in force now: the notice that no backup holds the new key is not true any more.
            if securityNotice?.hasSuffix(Self.backupWithNewKeyMissingText) == true {
                securityNotice = nil
            }
            var offMac: Bool?
            if appSettings.backupFolderBookmark != nil {
                offMac = await backUpOffMac(afterTheRunningOne: true)
            }
            return BackupNowOutcome(created: backup.created, offMac: offMac)
        }
    }

    /// Records `backup`, a local backup of `backedUp` that started when the changes told of were `changesBefore`: the
    /// moment of the last backup, and, when no change came while it was made, that no change waits for it any more.
    /// Arms the wake of the next backup when a change still waits. Returns false, and records nothing, when `backedUp`
    /// is no longer the data that is open; false too when it was replaced while the backup was recorded.
    @discardableResult
    func recordLocalBackup(_ backup: BackupResult, of backedUp: Database, changesBefore: Int) async -> Bool {
        guard database === backedUp else { return false }
        if let cleanupError = backup.cleanupError {
            Self.log("Removing old local backups", failedWith: cleanupError)
        }
        changesBackedUp = max(changesBackedUp, changesBefore)
        let holdsEveryChange = changeCount == changesBefore
        let created = backup.created
        await updateAppSettings { settings in
            settings.lastLocalBackup = created
            if holdsEveryChange {
                settings.localBackupPendingSince = nil
            }
        }
        // Replaced while the backup was recorded: what follows is about the data open now.
        guard database === backedUp else { return false }
        if holdsEveryChange && changeCount != changesBefore {
            // A change was told of while the backup was recorded as holding every change: it waits again.
            await markChangeWaitingForBackup()
        }
        if changeWaitsForBackup {
            armLocalBackupWake(at: dependencies.clock.now() + BackupService.localBackupInterval)
        } else {
            cancelLocalBackupWake()
        }
        return true
    }

    /// Arms the wake that makes the local backup at `date`, in place of the one armed before.
    private func armLocalBackupWake(at date: Date) {
        localBackupWake?.cancel()
        let tolerance = Self.localBackupWakeTolerance
        localBackupWake = dependencies.scheduler.schedule(at: date, tolerance: tolerance) { [weak self] in
            Task { @MainActor in
                await self?.backUpLocallyIfDue()
            }
        }
    }

    /// Cancels the wake of the local backup, if one is armed: nothing waits for it, or the data it was armed for is not
    /// open any more.
    func cancelLocalBackupWake() {
        localBackupWake?.cancel()
        localBackupWake = nil
    }

    // MARK: The backup outside the Mac

    /// Makes the backup outside the Mac when a folder for it is set and a day has passed since the last one, and
    /// records it as the last one. Nothing is made while a backup outside the Mac runs.
    ///
    /// An `automatic` one — after a write, the daily check, the launch — reaches the folder without any UI of the
    /// system, and when it fails (the disk is not connected, the share does not answer), which is logged, the next
    /// automatic one waits `offMacRetryInterval`. One that is not automatic (after a restore) may show the system's UI
    /// and is tried whatever failed before.
    func backUpOffMacIfDue(automatic: Bool = true) async {
        guard appSettings.backupFolderBookmark != nil, backups.isOffMacBackupDue(last: appSettings.lastOffMacBackup)
        else {
            return
        }
        if automatic, let failure = offMacAutomaticFailure {
            let now = dependencies.clock.now()
            // A failure later than now is one of a clock that was set back, and holds nothing back.
            guard failure > now || now >= failure + Self.offMacRetryInterval else { return }
        }
        await backUpOffMac(automatic: automatic)
    }

    /// Makes the backup outside the Mac now, into the folder set for it, and records it as the last one. Returns
    /// whether it was made; a failure is logged. Nothing is made while no folder is set or the data is locked. While
    /// another backup outside the Mac runs, nothing is made either, unless `afterTheRunningOne`: a backup that has to
    /// carry the keys in force (after a change of the keys) or go to the folder just chosen, or one the person asked
    /// for, waits for that one to end and then is made anew. A backup that ends after the data was replaced is of the
    /// data before and is not recorded, and the data open now is looked at again.
    ///
    /// An `automatic` backup reaches the folder without any UI of the system, and when it fails it holds the next
    /// automatic ones back for `offMacRetryInterval` (`backUpOffMacIfDue(automatic:)`); a backup that is made lets
    /// them go again.
    ///
    /// Neither wait is for ever: after `offMacWaitLimit` this gives up waiting (logged) and returns false, though the
    /// backup it gave up on goes on and records itself when it ends. Until it ends nothing waits for it again: a later
    /// call returns false at once.
    @discardableResult
    func backUpOffMac(afterTheRunningOne: Bool = false, automatic: Bool = false) async -> Bool {
        while let running = offMacBackupRun {
            guard afterTheRunningOne, running != abandonedOffMacRun else { return false }
            guard await waitForOffMacBackup(running) != nil else { return false }
        }
        guard let bookmark = appSettings.backupFolderBookmark, let open = openData() else { return false }
        let run = Task {
            // Ends the run before those who wait for it go on.
            defer {
                offMacBackupRun = nil
                abandonedOffMacRun = nil
            }
            do {
                let backup = try await backups.writeOffMacBackup(
                    database: open.database, key: open.key, keys: open.keys, bookmark: bookmark,
                    withoutUI: automatic)
                let recorded = await recordOffMacBackup(backup, of: open.database, into: bookmark)
                if recorded {
                    offMacAutomaticFailure = nil
                }
                return recorded
            } catch {
                Self.log("Making a backup outside the Mac", failedWith: error)
                if automatic, database === open.database, appSettings.backupFolderBookmark == bookmark {
                    offMacAutomaticFailure = dependencies.clock.now()
                }
                return false
            }
        }
        offMacBackupRun = run
        guard let made = await waitForOffMacBackup(run) else { return false }
        if database !== open.database {
            await backUpOffMacIfDue(automatic: automatic)
        }
        return made
    }

    /// Whether `run`, a backup outside the Mac, made its backup, or nil when it has not ended within `offMacWaitLimit`:
    /// the folder is not answering. The first wait that gives up on a run logs it and leaves the run to itself
    /// (`abandonedOffMacRun`), so that nothing waits for it again.
    private func waitForOffMacBackup(_ run: Task<Bool, Never>) async -> Bool? {
        let made = await BoundedWait.result(
            of: { await run.value }, within: Self.offMacWaitLimit, sleep: dependencies.sleep)
        if made == nil, abandonedOffMacRun != run {
            Self.log("Waiting for a backup outside the Mac", failedWith: BackupError.folderUnavailable)
            // A run that ended meanwhile has gone already.
            if offMacBackupRun == run {
                abandonedOffMacRun = run
            }
        }
        return made
    }

    /// Records `backup`, a backup of `backedUp` outside the Mac in the folder of `bookmark`, as the last one there.
    /// Returns false, and records nothing, when `backedUp` is no longer the data that is open or the folder is no
    /// longer the folder set; false too when the data was replaced meanwhile.
    @discardableResult
    func recordOffMacBackup(_ backup: BackupResult, of backedUp: Database, into bookmark: Data) async -> Bool {
        guard database === backedUp, appSettings.backupFolderBookmark == bookmark else { return false }
        if let cleanupError = backup.cleanupError {
            Self.log("Removing old backups outside the Mac", failedWith: cleanupError)
        }
        let created = backup.created
        await updateAppSettings { settings in
            // Another folder may have been chosen meanwhile, which has no backup yet.
            if settings.backupFolderBookmark == bookmark {
                settings.lastOffMacBackup = created
            }
        }
        return database === backedUp && appSettings.backupFolderBookmark == bookmark
    }

    /// Makes `folder`, which the person has just chosen in a panel, the folder of the backups outside the Mac: the app
    /// keeps a security-scoped bookmark of it, its name to show and when it was chosen, from which the reminder counts
    /// while it has no backup, and makes the first backup there at once, after the one that runs in the folder before,
    /// if one does. Returns whether that backup was made; one that was not is made at the next write or the next day,
    /// whatever failed in the folder before. Throws `VaultError.locked` while the data is locked, `VaultError.busy`
    /// while another step runs, and what making the bookmark or saving the settings throws; the folder set before
    /// stays then.
    func setBackupFolder(_ folder: URL) async throws -> Bool {
        try await runSecurityStep {
            guard database != nil else { throw VaultError.locked }
            let bookmark = try await Self.withSecurityScopedAccess(to: folder) {
                try BackupService.makeBookmark(for: folder)
            }
            let name = Self.displayName(ofFolder: folder)
            let now = dependencies.clock.now()
            try await changeAppSettings { settings in
                settings.backupFolderBookmark = bookmark
                settings.backupFolderName = name
                settings.backupFolderChosen = now
                // The folder has no backup yet.
                settings.lastOffMacBackup = nil
            }
            offMacAutomaticFailure = nil
            return await backUpOffMac(afterTheRunningOne: true)
        }
    }

    /// The name of `folder` as Finder shows it, after the name of the folder it is in, such as
    /// "iCloud Drive › InvoicesTracker". A folder at the top of a disk is named alone.
    private static func displayName(ofFolder folder: URL) -> String {
        let manager = FileManager.default
        let name = manager.displayName(atPath: folder.path(percentEncoded: false))
        let parent = folder.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
        guard !["/", "/Volumes", "/Volumes/"].contains(parent) else { return name }
        return manager.displayName(atPath: parent) + " › " + name
    }

    // MARK: The export

    /// Exportovat zálohu…: writes one backup of the open data to `file`, which the person chose in the save panel,
    /// replacing a file that is there. Nothing else in that folder is touched, and nothing is pruned. Throws
    /// `VaultError.locked` while the data is locked, `VaultError.busy` while another step runs, and what writing the
    /// backup throws.
    func exportBackup(to file: URL) async throws {
        try await runSecurityStep {
            guard let open = openData() else { throw VaultError.locked }
            try await Self.withSecurityScopedAccess(to: file) {
                try await backups.exportBackup(database: open.database, key: open.key, keys: open.keys, to: file)
            }
        }
    }

    // MARK: The open data

    /// The open data with the key it is encrypted with and the slots that open it, as a backup needs them: only when
    /// the vault holds the database the model has, so that the key and the slots are that database's.
    private func openData() -> (database: Database, key: SymmetricKey, keys: KeysFile)? {
        guard let database, vault.database === database, let key = vault.dataKey, let keys = vault.keys else {
            return nil
        }
        return (database, key, keys)
    }
}

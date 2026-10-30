import CryptoKit
import Foundation

/// A backup file together with the header read from it.
nonisolated struct BackupListing: Sendable, Hashable {
    let url: URL
    let header: BackupHeader
}

/// What making a backup gives back: the new file, when it was made, and whether tidying up around it went wrong.
nonisolated struct BackupResult: Sendable {
    /// The new backup file. It is complete: a result exists only for a backup that was written.
    let url: URL

    /// The moment the backup was made, as its header has it (`BackupHeader.created`): to the second, taken before the
    /// snapshot, so a change made while the backup was written is after it. It is the time to record as the last
    /// backup.
    let created: Date

    /// The first error from tidying up around the backup: deleting the old backups beyond the newest ones, or removing
    /// leftover temporary files of a backup that never finished. Nil when all went well. The backup is made either way,
    /// so the caller records it as made, and may tell the person that old files could not be removed.
    let cleanupError: (any Error)?
}

/// Makes encrypted backups of the database, keeps the newest ones in a folder, and says when the backup outside the Mac
/// is due and when to remind of it. When the local backup is due is for the caller to say: it gives the interval
/// (`localBackupInterval`).
///
/// A backup is a snapshot of the database packed with the key slots into one `.ttbackup` file (see `BackupFormat`). The
/// local backups go to `backupsDirectory`, the optional daily one to a folder outside the Mac that is reached through a
/// security-scoped bookmark. Both folders keep the newest `keep` backups the service made itself.
///
/// The service remembers nothing: when the last backup was comes in with every question, and the caller keeps that
/// date.
@MainActor
final class BackupService {
    /// The least time between two local backups: one is made at most once an hour, after a change.
    static let localBackupInterval: TimeInterval = 60 * 60
    private static let offMacBackupInterval: TimeInterval = 24 * 60 * 60
    private static let offMacReminderInterval: TimeInterval = 30 * 24 * 60 * 60

    /// A hidden temporary file of the service that is older than this is the leftover of a backup that never finished.
    private static let leftoverAge: TimeInterval = 24 * 60 * 60

    private let backupsDirectory: URL
    private let clock: any AppClock
    private let appVersion: String
    private let deviceName: String
    private let keep: Int
    private let files: BackupFileWorker

    /// `backupsDirectory` is where the local backups are made (created on the first one) and where every snapshot is
    /// made first, `appVersion` and `deviceName` go into the header of every backup, and `keep` is how many of the
    /// service's own backups stay in a folder, at least one. `resolveBookmark` resolves the bookmark of the folder
    /// outside the Mac, as the system does unless a test says otherwise.
    init(
        backupsDirectory: URL, clock: any AppClock, appVersion: String, deviceName: String, keep: Int = 30,
        resolveBookmark: @escaping @Sendable (Data, URL.BookmarkResolutionOptions) async throws -> URL =
            BackupService.resolveBookmark
    ) {
        precondition(keep >= 1, "A folder of backups keeps at least the newest one.")
        self.backupsDirectory = backupsDirectory
        self.clock = clock
        self.appVersion = appVersion
        self.deviceName = deviceName
        self.keep = keep
        self.files = BackupFileWorker(localDirectory: backupsDirectory, resolveBookmark: resolveBookmark)
    }

    // MARK: Making backups

    /// Makes a backup of `database` and returns its file and the outcome of tidying up (see `BackupResult`). `key` is
    /// the data key the database is encrypted with, and the backup is encrypted with it too; `keys` are the key slots
    /// as they are now, which the backup carries so that it opens with the recovery code that is valid now.
    ///
    /// The file goes to `directory`, or to the local backups folder, and is named after the clock in the Mac's local
    /// time: "InvoicesTracker 2026-10-17 14-05-12.ttbackup", and "… 2.ttbackup", "… 3.ttbackup" when that name is
    /// taken. The snapshot is made in the local backups folder whatever `directory` is, and removed again, so the only
    /// thing written to another folder (an external disk, a network share, iCloud Drive) is the finished backup, as a
    /// hidden temporary file that is renamed when complete. Nothing of SQLite touches that folder.
    ///
    /// Then the newest `keep` backups of `directory` stay. Only files with a name the service gives its backups
    /// ("InvoicesTracker yyyy-MM-dd HH-mm-ss.ttbackup", with a number after the time when needed) and a readable header
    /// are counted and can be deleted: a backup exported by hand, another Mac's backups under other names and any
    /// damaged file are neither counted nor touched. With `onlyThisMac`, for a folder that other Macs may share, only
    /// the backups whose header names this Mac (`deviceName`) are counted and can be deleted, as the app of another Mac
    /// names its backups the same way. The backup just made is not deleted either, whatever its date says, so a clock
    /// that was set back cannot remove it at once, and neither is `spared`, however old it is: the backup that is
    /// being restored, say. A later backup that is not told to spare it treats it like any other.
    ///
    /// When it starts, hidden temporary files of the service that are more than a day old are removed from the local
    /// backups folder and from `directory`: the leftovers of a backup that was cut short.
    ///
    /// Throws what the database throws, and the error of the file system, when no backup was made. Once the backup is
    /// written this does not throw: a failure to delete old backups or old leftovers is in the result.
    func makeBackup(
        database: Database,
        key: SymmetricKey,
        keys: KeysFile,
        into directory: URL? = nil,
        sparing spared: URL? = nil,
        onlyThisMac: Bool = false
    ) async throws -> BackupResult {
        let directory = directory ?? backupsDirectory
        let now = clock.now()
        let preparation = try await files.prepare(target: directory, leftoversBefore: now - Self.leftoverAge)
        do {
            let header = try await makeSnapshot(
                of: database, key: key, keys: keys, at: preparation.snapshot, now: now
            )
            let stored = try await files.store(
                snapshot: preparation.snapshot, header: header, in: directory, keep: keep, sparing: spared,
                madeOn: onlyThisMac ? deviceName : nil
            )
            await files.removeSnapshot(preparation.snapshot)
            return BackupResult(
                url: stored.backup, created: header.created,
                cleanupError: preparation.cleanupError ?? stored.pruneError
            )
        } catch {
            await files.removeSnapshot(preparation.snapshot)
            throw error
        }
    }

    /// Makes a backup in the folder the security-scoped `bookmark` (from `makeBookmark(for:)`) points to, and returns
    /// its file; `makeBackup` says what is made and kept there, where only the backups of this Mac are pruned, as the
    /// folder may be shared with another Mac. The folder is opened for the time of the backup and closed again. With
    /// `withoutUI` the bookmark is resolved without any UI of the system (`bookmarkResolutionOptions(withoutUI:)`).
    ///
    /// Throws `BackupError.folderUnavailable` when the bookmark does not resolve to a folder that can be opened: it was
    /// deleted, or its disk or network share is not connected. A bookmark that went stale (the folder was moved) but
    /// still resolves is used as it is.
    func writeOffMacBackup(
        database: Database,
        key: SymmetricKey,
        keys: KeysFile,
        bookmark: Data,
        withoutUI: Bool
    ) async throws -> BackupResult {
        let folder = try await files.resolveFolder(
            bookmark, options: Self.bookmarkResolutionOptions(withoutUI: withoutUI))
        guard folder.startAccessingSecurityScopedResource() else {
            throw BackupError.folderUnavailable
        }
        defer { folder.stopAccessingSecurityScopedResource() }
        return try await makeBackup(database: database, key: key, keys: keys, into: folder, onlyThisMac: true)
    }

    /// Writes exactly one backup of `database` to `fileURL`, the file the person chose to export to, replacing a file
    /// that is there (the save panel has asked them). Nothing else in that folder is read, changed or deleted: no old
    /// backups are pruned, whatever the folder holds, and no leftovers are removed.
    ///
    /// The backup is made like any other (see `makeBackup`) but in the local backups folder, from where the finished
    /// file is moved to `fileURL` with `FileManager.replaceItemAt`, which swaps a file in one step. The service creates
    /// no temporary file of its own beside `fileURL`, because a sandboxed app may be allowed to write only the file
    /// the person chose. The local backups folder is left as it was.
    func exportBackup(database: Database, key: SymmetricKey, keys: KeysFile, to fileURL: URL) async throws {
        let now = clock.now()
        let snapshot = try await files.prepare(target: nil, leftoversBefore: nil).snapshot
        do {
            let header = try await makeSnapshot(of: database, key: key, keys: keys, at: snapshot, now: now)
            try await files.place(snapshot: snapshot, header: header, at: fileURL)
            await files.removeSnapshot(snapshot)
        } catch {
            await files.removeSnapshot(snapshot)
            throw error
        }
    }

    /// The bookmark that keeps access to `folder` after the app is restarted. `folder` is a folder the person just
    /// chose, in a panel, so the app is allowed to use it now.
    nonisolated static func makeBookmark(for folder: URL) throws -> Data {
        try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// How a backup outside the Mac resolves the bookmark of its folder: always within the scope the sandbox keeps for
    /// it, and with `withoutUI` without any UI of the system, so that a share that is not mounted is mounted silently
    /// with the credentials the system keeps, or not at all, and no dialog of the system asks the person for anything.
    nonisolated static func bookmarkResolutionOptions(withoutUI: Bool) -> URL.BookmarkResolutionOptions {
        withoutUI ? [.withSecurityScope, .withoutUI] : [.withSecurityScope]
    }

    /// The folder `bookmark` points to, resolved by the system with `options`. A bookmark that went stale (the folder
    /// was moved) but still resolves is used as it is.
    nonisolated static func resolveBookmark(
        _ bookmark: Data, options: URL.BookmarkResolutionOptions
    ) async throws -> URL {
        var isStale = false
        return try URL(
            resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    /// Writes the snapshot of `database` to `snapshot`, encrypted with `key`, and returns the header of the backup that
    /// is made from it, dated `now` to the second as the file name has it.
    private func makeSnapshot(
        of database: Database,
        key: SymmetricKey,
        keys: KeysFile,
        at snapshot: URL,
        now: Date
    ) async throws -> BackupHeader {
        try await database.exportSnapshot(to: snapshot, key: key)
        let schemaVersion = try await database.schemaVersion()
        let contents = try await database.contentSummary()
        return BackupHeader(
            created: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down)), appVersion: appVersion,
            schemaVersion: schemaVersion, invoiceCount: contents.invoiceCount, clientCount: contents.clientCount,
            years: contents.years, deviceName: deviceName, keys: keys
        )
    }

    // MARK: Listing

    /// The readable backups in the local backups folder, whatever their names, the newest first by the date in their
    /// header, with their headers. Nothing in the listing is a file that is not a readable backup. Empty when there is
    /// no folder yet.
    func localBackups() throws -> [BackupListing] {
        do {
            return try BackupFolder.backups(in: backupsDirectory).map {
                BackupListing(url: $0.url, header: $0.header)
            }
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
    }

    // MARK: When a backup is due

    /// Whether the backup outside the Mac is due: a day has passed since the last one, or there has been none.
    func isOffMacBackupDue(last: Date?) -> Bool {
        guard let last else { return true }
        return clock.now().timeIntervalSince(last) >= Self.offMacBackupInterval
    }

    /// Whether to remind the person of the backup outside the Mac: a folder is set and 30 days have passed since the
    /// last backup there. With no backup yet there is no reminder, as the backup is due and is made.
    func needsOffMacReminder(last: Date?, folderSet: Bool) -> Bool {
        guard folderSet, let last else { return false }
        return clock.now().timeIntervalSince(last) >= Self.offMacReminderInterval
    }
}

// MARK: - File work

/// The file work of backups. It runs away from the main actor, because a folder can be on an external disk or a
/// network share that is slow or asleep, and one piece at a time: backups that are made together get different names
/// and prune one after the other.
private actor BackupFileWorker {
    /// The local backups folder, where every snapshot and every export is made before it goes anywhere else.
    private let localDirectory: URL

    /// Resolves the bookmark of the folder outside the Mac.
    private let resolveBookmark: @Sendable (Data, URL.BookmarkResolutionOptions) async throws -> URL

    init(
        localDirectory: URL,
        resolveBookmark: @escaping @Sendable (Data, URL.BookmarkResolutionOptions) async throws -> URL
    ) {
        self.localDirectory = localDirectory
        self.resolveBookmark = resolveBookmark
    }

    /// Gets ready for a backup: makes sure the local folder and `target` (the folder the backup goes to, when it goes
    /// to one) exist, removes the leftover temporary files from them that were last changed before `cutoff` (when
    /// there is one), and returns the path of a new snapshot file in the local folder. The first error of removing
    /// leftovers is returned, not thrown: it does not stop a backup.
    ///
    /// The name of the snapshot starts with a dot, so a leftover is not shown.
    func prepare(
        target: URL?,
        leftoversBefore cutoff: Date?
    ) throws -> (snapshot: URL, cleanupError: (any Error)?) {
        var directories = [localDirectory]
        if let target, target != localDirectory {
            directories.append(target)
        }
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var cleanupError: (any Error)?
        if let cutoff {
            for directory in directories {
                do {
                    try BackupFolder.removeLeftovers(in: directory, before: cutoff)
                } catch {
                    cleanupError = cleanupError ?? error
                }
            }
        }
        return (localDirectory.appending(path: ".snapshot-\(UUID().uuidString).tmp"), cleanupError)
    }

    /// Packs `snapshot` and `header` into a new backup file in `directory`, named after the date of the header, and
    /// deletes the service's own older readable backups beyond the newest `keep`, but not `spared`; with `device`,
    /// only those made on the Mac of that name count and can be deleted. Returns the new file, and the error of
    /// deleting if it failed: the new file is there either way.
    func store(
        snapshot: URL,
        header: BackupHeader,
        in directory: URL,
        keep: Int,
        sparing spared: URL?,
        madeOn device: String?
    ) throws -> (backup: URL, pruneError: (any Error)?) {
        let backup = BackupFileNaming.unusedURL(in: directory, created: header.created)
        try BackupFormat.write(header: header, databaseFile: snapshot, to: backup)
        do {
            try BackupFolder.prune(directory, keep: keep, sparing: backup, and: spared, madeOn: device)
            return (backup, nil)
        } catch {
            return (backup, error)
        }
    }

    /// Packs `snapshot` and `header` into a file in the local folder and swaps that file in for `fileURL`.
    func place(snapshot: URL, header: BackupHeader, at fileURL: URL) throws {
        let packed = localDirectory.appending(path: ".export.\(UUID().uuidString).partial")
        // After a successful swap the file is gone and there is nothing to remove.
        defer { try? FileManager.default.removeItem(at: packed) }
        try BackupFormat.write(header: header, databaseFile: snapshot, to: packed)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: packed)
    }

    /// Deletes the snapshot file, if there is one. A file that cannot be deleted stays as an encrypted file no list
    /// shows, until the next backup finds it old enough to remove it. The backup made from it is complete, so that is
    /// not an error of the backup.
    func removeSnapshot(_ snapshot: URL) {
        try? FileManager.default.removeItem(at: snapshot)
    }

    /// The folder the security-scoped `bookmark` points to, resolved with `options`. Throws
    /// `BackupError.folderUnavailable` when it does not resolve.
    func resolveFolder(_ bookmark: Data, options: URL.BookmarkResolutionOptions) async throws -> URL {
        do {
            return try await resolveBookmark(bookmark, options)
        } catch {
            throw BackupError.folderUnavailable
        }
    }
}

/// The names of the files the service makes.
private nonisolated enum BackupFileNaming {
    static let fileExtension = "ttbackup"

    /// "InvoicesTracker 2026-10-17 14-05-12": the moment `date` in the Mac's local time, to the second. Digits and hyphens
    /// only, so no file system objects to it.
    static func stem(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "InvoicesTracker " + formatter.string(from: date)
    }

    /// The file for a backup made at `created`, which is named after that moment. When the name is taken (two backups
    /// in one second) the first free of "… 2", "… 3" and so on is used.
    static func unusedURL(in directory: URL, created: Date) -> URL {
        let stem = stem(for: created)
        var url = directory.appending(path: "\(stem).\(fileExtension)")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            url = directory.appending(path: "\(stem) \(number).\(fileExtension)")
            number += 1
        }
        return url
    }

    /// Whether `name` is a name the service gives its backups: `stem(for:)` of some moment, then a number from 2 on
    /// when the name had been taken, then `.ttbackup`. Case matters. Pruning deletes no other file.
    static func isOwnBackup(_ name: String) -> Bool {
        let own = #/InvoicesTracker [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}-[0-9]{2}-[0-9]{2}( [0-9]+)?\.ttbackup/#
        return name.wholeMatch(of: own) != nil
    }

    /// Whether `name` is a hidden temporary file of the service: a snapshot, `.snapshot-<UUID>.tmp`, or a file that is
    /// being packed, `.<name>.<UUID>.partial`.
    static func isTemporary(_ name: String) -> Bool {
        let snapshot =
            #/\.snapshot-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.tmp/#
        let partial =
            #/\..+\.[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.partial/#
        return name.wholeMatch(of: snapshot) != nil || name.wholeMatch(of: partial) != nil
    }
}

/// The files of a backup folder: which are readable backups, in which order, and which to delete.
private nonisolated enum BackupFolder {
    /// A readable backup in a folder.
    struct Backup {
        let url: URL
        let header: BackupHeader

        /// The name without the extension. Backups of one second differ by the number at its end.
        var stem: String {
            url.deletingPathExtension().lastPathComponent
        }
    }

    /// The regular files of `directory` with the extension `.ttbackup` whose header can be read, the newest first.
    /// Hidden files, files of other names, folders and files that do not read as a backup are not in it. With `ownOnly`
    /// only those named as the service names its backups are, and the others are not even opened. Of two with the same
    /// date the one with the greater number in its name is newer.
    static func backups(in directory: URL, ownOnly: Bool = false) throws -> [Backup] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        var backups: [Backup] = []
        for url in urls where url.pathExtension.lowercased() == BackupFileNaming.fileExtension {
            if ownOnly && !BackupFileNaming.isOwnBackup(url.lastPathComponent) {
                continue
            }
            // A file that is gone by now, or is not a plain file (a pipe would block the read), is not a backup.
            guard
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                values.isRegularFile == true
            else {
                continue
            }
            // A file that does not read as a backup is left out of the order, and so is never in the way of one that
            // does. Nothing deletes it.
            guard let header = try? BackupFormat.readHeader(from: url) else {
                continue
            }
            backups.append(Backup(url: url, header: header))
        }
        return backups.sorted(by: isNewer)
    }

    /// Deletes the service's own readable backups beyond the newest `keep` of them, except `newest` and `spared`. Files
    /// that are not its own or not readable are neither counted nor deleted, and with `device` neither are the backups
    /// whose header names another Mac. Every deletion is tried, and the first error is thrown when it is over.
    ///
    /// `spared` can be spelled otherwise than the listing spells the folder (`/var` for `/private/var`), so paths are
    /// compared with their symbolic links resolved.
    static func prune(
        _ directory: URL, keep: Int, sparing newest: URL, and spared: URL?, madeOn device: String?
    ) throws {
        let sparedPath = spared?.resolvingSymlinksInPath().path(percentEncoded: false)
        let counted = try backups(in: directory, ownOnly: true).filter { backup in
            device.map { backup.header.deviceName == $0 } ?? true
        }
        var failure: (any Error)?
        for backup in counted.dropFirst(keep)
        where backup.url.lastPathComponent != newest.lastPathComponent
            && backup.url.resolvingSymlinksInPath().path(percentEncoded: false) != sparedPath {
            do {
                try FileManager.default.removeItem(at: backup.url)
            } catch {
                failure = failure ?? error
            }
        }
        if let failure {
            throw failure
        }
    }

    /// Deletes the hidden temporary files of the service in `directory` that were last changed before `cutoff`. Every
    /// deletion is tried, and the first error is thrown when it is over.
    static func removeLeftovers(in directory: URL, before cutoff: Date) throws {
        var failure: (any Error)?
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where BackupFileNaming.isTemporary(url.lastPathComponent) {
            guard
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                values.isRegularFile == true,
                let changed = values.contentModificationDate,
                changed < cutoff
            else {
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                failure = failure ?? error
            }
        }
        if let failure {
            throw failure
        }
    }

    private static func isNewer(_ first: Backup, _ second: Backup) -> Bool {
        if first.header.created != second.header.created {
            return first.header.created > second.header.created
        }
        // "… 14-05-12 10" is after "… 14-05-12 9", though a comparison of the characters would say the opposite.
        return first.stem.compare(second.stem, options: .numeric) == .orderedDescending
    }
}

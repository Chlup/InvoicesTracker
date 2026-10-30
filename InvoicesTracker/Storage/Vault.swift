import CryptoKit
import Foundation
import os

// MARK: - Paths and states

/// Where the data lives: the database, the keys file and the local backups, in one folder.
nonisolated struct VaultPaths: Sendable {
    let directory: URL

    /// The SQLCipher database. SQLite keeps its write-ahead log and the log's shared memory beside it, under its name
    /// with `-wal` and `-shm`.
    var database: URL {
        directory.appending(path: "InvoicesTracker.sqlite")
    }

    /// The keys file.
    var keys: URL {
        directory.appending(path: "InvoicesTracker.keys")
    }

    /// The folder of the local backups.
    var backups: URL {
        directory.appending(path: "Backups", directoryHint: .isDirectory)
    }
}

/// What there is when the app starts.
nonisolated enum VaultLaunchState: Sendable, Equatable {
    /// Neither the database nor the keys file is there: nothing has been made yet.
    case firstLaunch

    /// The database and a keys file this version of the app can read are there, to be unlocked.
    case existing

    /// One of the two is missing, or the keys file cannot be read. The text says which, in Czech, for the screen.
    case damaged(String)
}

/// What the vault refuses to do in the state it is in. No case carries a key, a code or a path.
nonisolated enum VaultError: Error, Equatable {
    /// The step needs the data open, and it is locked.
    case locked

    /// The data is open already, so it is neither started nor unlocked again.
    case alreadyOpen

    /// There is nothing to unlock: the database or the keys file is missing (`launchState()` says which).
    case noData

    /// Another step that opens or changes the data or its keys is still running.
    case busy

    /// The new recovery code was made to replace recovery slots that are no longer in force (another new code or a
    /// restore came in between), so it is not put in force and nothing is written: a new one has to be made.
    case outdatedCode
}

/// A start with empty data that is ready but not made yet: the recovery code to show, with its label, and the data key
/// and recovery slot it stands for. Nothing is written until `Vault.startFresh(_:touchID:)`, and the vault keeps
/// nothing of it, so an app that quits in between finds the first launch again.
nonisolated struct PendingFreshStart: Sendable {
    let code: String
    let label: String
    fileprivate let key: SymmetricKey
    fileprivate let slot: RecoverySlot

    /// The sequence number of the code, 1 for the first code, which the code step names.
    var number: Int {
        slot.number
    }

    /// The day the code was made, which the code step names.
    var created: CivilDate {
        slot.created
    }
}

/// A new recovery code that is ready but not in force yet: the code to show, with its label, and the new data key and
/// recovery slot it stands for, made to replace the recovery slots in force at the time. Nothing is written until
/// `Vault.commitNewRecoveryCode(_:)`, and the vault keeps nothing of it, so the old code stays in force until the
/// person has stored the new one.
nonisolated struct PendingRecoveryCode: Sendable {
    let code: String
    let label: String
    fileprivate let key: SymmetricKey
    fileprivate let slot: RecoverySlot
    fileprivate let replaces: [RecoverySlot]

    /// The sequence number of the code, one more than that of the code in force, which the sheet of the code names.
    var number: Int {
        slot.number
    }

    /// The day the code was made, which the sheet of the code names.
    var created: CivilDate {
        slot.created
    }
}

/// What putting a new recovery code in force tells.
nonisolated struct NewCodeOutcome: Sendable, Equatable {
    /// The label of the new code, such as "kód č. 2 z 18. 10. 2026".
    let label: String

    /// The label of the code it replaced, which older backups still need.
    let previousLabel: String

    /// Whether the local backup that follows the change was made: only then may the app say that it is saved.
    let backupMade: Bool
}

/// What turning Touch ID on or off tells.
nonisolated struct KeyChangeOutcome: Sendable, Equatable {
    /// Whether the local backup that follows the change was made: only then may the app say that it is saved.
    let backupMade: Bool
}

/// The moments between the steps of a change of the data key, each named after the step that has just ended. A crash
/// at one of them leaves the files as they are at that moment. Only the tests look at them.
nonisolated enum VaultStep: Sendable {
    /// A new recovery code is being put in force: the slots of the new data key are made (the recovery slot when the
    /// code was made, the device slot now), and nothing is written yet.
    case newKeyMade

    /// The keys file holds the slots of both keys, and the database still has the old one.
    case bothKeySetsSaved

    /// The database has the new key.
    case databaseRekeyed

    /// The file opened with the new key on a connection of its own, and every page of it was read.
    case rekeyVerified

    /// The keys file holds the new slots alone, unless it could not be written.
    case oldKeySetRemoved

    /// The backup with the new key is made, unless it could not be.
    case backupMade

    /// A restore: the keys file holds the slots of the restored data, and, when the data that was there was open,
    /// those of that data as well. The database file is the one that was there.
    case restoreKeySetsSaved

    /// The database file is the restored one.
    case databaseReplaced

    /// The keys file holds the slots of the restored data alone, unless it could not be written.
    case restoredKeysSettled
}

// MARK: - Vault

/// The whole life of the data: the first launch, unlocking with the device key of this Mac or with the recovery code,
/// a new recovery code, Touch ID on or off, and restoring a backup.
///
/// The data is one SQLCipher database encrypted with a random data key, which the keys file holds in key slots: a
/// device slot that a device key of this Mac opens, and recovery slots that a recovery code opens (see `KeyManager`).
/// Every step keeps a slot on disk that opens the database as it is at that moment, also when the app is cut off in the
/// middle of the step:
/// - A step that keeps the data key and replaces the device slot (unlocking with the code, Touch ID on or off) writes
///   the keys file in one atomic step, and the file before and the file after both open the database.
/// - A step that changes the data key (a new recovery code, a restore) first writes a keys file with the slots of both
///   keys (`KeysFile.previous`), then changes the database, and then writes the slots of the new key alone.
/// - A new recovery code, and the code of a start with empty data, are made in a step of their own that writes
///   nothing (`prepareNewRecoveryCode()`, `prepareFreshStart()`). They go into force only once the person has stored
///   them, so a code that is in force is never one nobody has seen.
/// - Unlocking tries the slots of every key in the keys file, and the key that opens the database is the one in force;
///   a key that does not open it is passed over. A keys file with the slots of two keys is then written again with the
///   slots in force alone, which finishes a change that was cut off, or undoes it, whichever way the database went.
///
/// While the data is open the vault holds the database, its data key and the slots in force. No key or code is ever
/// written anywhere in plain form or logged; a new recovery code is returned to be shown once, and then forgotten.
///
/// One step at a time: a step that opens or changes something, started while another one waits for the database or
/// the disk, is refused with `VaultError.busy`, because the two could otherwise write keys that do not fit the
/// database.
@MainActor
final class Vault {
    let paths: VaultPaths

    /// The open database, while the data is unlocked.
    private(set) var database: Database?

    /// The data key the database is encrypted with, while the data is unlocked.
    private(set) var dataKey: SymmetricKey?

    /// The slots of `dataKey` as the keys file has them, while the data is unlocked: what a backup carries.
    private(set) var keys: KeysFile?

    #if DEBUG
    /// Called at every `VaultStep`. Only the tests set it, to copy the files as a crash at that moment would leave
    /// them, or to make the next step fail.
    var stepObserver: ((VaultStep) -> Void)?
    #endif

    private let device: any DeviceKeyProtector
    private let backups: BackupService
    private let clock: any AppClock

    /// Whether a step that opens or changes something is running.
    private var isBusy = false

    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "InvoicesTracker", category: "Vault"
    )

    /// The file, beside the database, that the database of a backup is extracted to before it replaces the database.
    private static let extractedFileName = ".InvoicesTracker restore.sqlite"

    /// What the Touch ID or password prompt gives as the reason when a backup is opened with the device key.
    private static let restoreReason = "obnovit data ze zálohy"

    /// `device` seals and opens the device slots, `backups` makes the local backups (into `paths.backups`), and `clock`
    /// dates the recovery codes and names the folders of data set aside.
    init(paths: VaultPaths, device: any DeviceKeyProtector, backups: BackupService, clock: any AppClock) {
        self.paths = paths
        self.device = device
        self.backups = backups
        self.clock = clock
    }

    // MARK: What there is

    /// What there is to open: nothing yet, the data, or files that do not belong together. Only the files are looked
    /// at: the keys file is read to see that this version of the app can read it.
    func launchState() -> VaultLaunchState {
        switch (Self.exists(paths.database), Self.exists(paths.keys)) {
        case (false, false):
            return .firstLaunch
        case (true, false):
            return .damaged("Chybí soubor s klíči k datům.")
        case (false, true):
            return .damaged("Chybí databáze.")
        case (true, true):
            do {
                return try KeyManager.load(paths.keys) == nil ? .damaged("Chybí soubor s klíči k datům.") : .existing
            } catch {
                return .damaged("Soubor s klíči je poškozený.")
            }
        }
    }

    /// The label of the recovery code that opens the data, such as "kód č. 2 z 17. 10. 2026": that of the newest
    /// recovery slot in force while the data is open, and of the newest recovery slot of the keys file on disk while it
    /// is locked. Nil when there is no keys file that can be read.
    var requiredRecoveryLabel: String? {
        (keys ?? (try? KeyManager.load(paths.keys)))?.newestRecoverySlot?.label
    }

    // MARK: Opening the data

    /// The first step of starting with empty data: a new data key, and recovery slot no. 1 dated today, with its code
    /// and label to show. Nothing is written and nothing kept, so the code can be shown for as long as the person needs
    /// to store it; `startFresh(_:touchID:)` then makes the data. Throws `VaultError.alreadyOpen` while data is open.
    func prepareFreshStart() throws -> PendingFreshStart {
        guard database == nil else {
            throw VaultError.alreadyOpen
        }
        let key = KeyManager.newDataKey()
        let recovery = try KeyManager.makeRecoverySlot(for: key, number: 1, created: today())
        return PendingFreshStart(code: recovery.code, label: recovery.slot.label, key: key, slot: recovery.slot)
    }

    /// Starts with empty data, once the person has stored the code of `pending`: the database made with its data key,
    /// a device slot (asking for Touch ID or the password when `touchID`, which `AppSettings.touchIDUnlock` records
    /// too) and its recovery slot in the keys file. Returns the open database.
    ///
    /// Data that is there and cannot be opened now — the data of another Mac without its code, a database without its
    /// keys file — is set aside, not replaced (see `setAsideData()`). When this throws, the new data is gone again and
    /// what was set aside is back.
    func startFresh(_ pending: PendingFreshStart, touchID: Bool) async throws -> Database {
        try beginStep()
        defer { endStep() }
        guard database == nil else {
            throw VaultError.alreadyOpen
        }
        try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        let keys = KeysFile(
            deviceSlot: try device.seal(pending.key, userPresence: touchID), recoverySlots: [pending.slot]
        )
        let setAside = try setAsideData()
        let database: Database
        do {
            database = try await Self.open(paths.database, key: pending.key)
            do {
                try await database.updateAppSettings { $0.touchIDUnlock = touchID }
                try await Self.saveKeys(keys, to: paths.keys)
            } catch {
                await database.close()
                throw error
            }
        } catch {
            // Without its keys file the new database could never be opened again.
            removeDatabaseFiles(at: paths.database)
            putBack(setAside)
            throw error
        }
        adopt(database, key: pending.key, keys: keys)
        return database
    }

    /// Unlocks the data with the device key of this Mac: the device slot opens the data key (asking for Touch ID or the
    /// password, with `reason`, when the slot needs it), and the data key opens the database. Returns the database.
    ///
    /// A keys file of a change that was cut off holds the slots of two keys. The device slot of each is tried, the
    /// replaced key's first, as a change is far more often cut off before the database got the new key than after; the
    /// key that opens the database is the one in force (see `settle(_:inForce:)`). A slot whose key the device key of
    /// this Mac does not take for its own (`DeviceKeyProtector.canOpen`), such as the slot of another Mac that came
    /// with the data through Migration Assistant, is not tried: opening it would ask for Touch ID first, for nothing.
    ///
    /// Throws `KeyError.userCancelled` when the prompt does not unlock (the app stays locked and can ask again), and
    /// `KeyError.deviceKeyUnusable` when no device slot of this Mac opens the database — it was sealed on another Mac,
    /// the Mac was repaired, a slot is damaged or there is none — so only a recovery code opens it now. Throws
    /// `VaultError.noData` when the database or the keys file is missing (nothing is made then),
    /// `KeyError.keysFileDamaged` for a keys file that cannot be read, and what opening the database throws other than
    /// a wrong key.
    func unlockWithDevice(reason: String) async throws -> Database {
        try beginStep()
        defer { endStep() }
        guard database == nil else {
            throw VaultError.alreadyOpen
        }
        let stored = try storedKeys()
        for slots in stored.slotSets {
            guard let slot = slots.deviceSlot, device.canOpen(slot) else { continue }
            let key: SymmetricKey
            do {
                key = try await KeyManager.unlock(slots, device: device, reason: reason)
            } catch KeyError.noDeviceSlot, KeyError.deviceKeyUnusable {
                continue
            }
            if let database = try await Self.openIfKeyFits(paths.database, key: key) {
                adopt(database, key: key, keys: await settle(stored, inForce: slots))
                return database
            }
        }
        throw KeyError.deviceKeyUnusable
    }

    /// Unlocks the data with the recovery code where the device key does not open it (another Mac, a repaired one, a
    /// damaged slot): the code opens the data key in its recovery slot, and the data key opens the database. Then a new
    /// device slot of this Mac replaces the device slot in the keys file, so that this Mac opens the data itself next
    /// time, asking for Touch ID as `AppSettings.touchIDUnlock` in the database says. The recovery slots stay, and with
    /// them the code. Returns the database.
    ///
    /// Throws `KeyError.malformedRecoveryCode` for text that is not a code, and `KeyError.wrongRecoveryCode` when the
    /// code opens no slot whose key opens the database; nothing is changed then. Throws `VaultError.noData`,
    /// `KeyError.keysFileDamaged` and what opening the database throws as `unlockWithDevice(reason:)` does, and what
    /// sealing and writing the keys file throw, after which the data stays locked and the keys file as it was.
    func unlockWithRecoveryCode(_ code: String) async throws -> Database {
        try beginStep()
        defer { endStep() }
        guard database == nil else {
            throw VaultError.alreadyOpen
        }
        let stored = try storedKeys()
        for unlocked in try Self.unlock(stored, recoveryCode: code) {
            guard let database = try await Self.openIfKeyFits(paths.database, key: unlocked.key) else {
                continue
            }
            do {
                let touchID = try await database.appSettings().touchIDUnlock
                let keys = KeysFile(
                    deviceSlot: try device.seal(unlocked.key, userPresence: touchID),
                    recoverySlots: unlocked.slots.recoverySlots
                )
                try await Self.saveKeys(keys, to: paths.keys)
                adopt(database, key: unlocked.key, keys: keys)
                return database
            } catch {
                await database.close()
                throw error
            }
        }
        throw KeyError.wrongRecoveryCode
    }

    // MARK: Changing the keys

    /// The first step of a new recovery code: a new data key, and a recovery slot numbered after the newest one in
    /// force and dated today, with its code and label to show. Nothing is written and nothing kept: the old code stays
    /// in force until `commitNewRecoveryCode(_:)`, which comes once the person has stored the new one. Throws
    /// `VaultError.locked` while the data is locked.
    func prepareNewRecoveryCode() throws -> PendingRecoveryCode {
        guard database != nil, dataKey != nil, let keys else {
            throw VaultError.locked
        }
        let key = KeyManager.newDataKey()
        let recovery = try KeyManager.makeRecoverySlot(
            for: key, number: (keys.newestRecoverySlot?.number ?? 0) + 1, created: today()
        )
        return PendingRecoveryCode(
            code: recovery.code, label: recovery.slot.label, key: key, slot: recovery.slot,
            replaces: keys.recoverySlots
        )
    }

    /// Puts the new recovery code of `pending` in force, once the person has stored it. The data gets the new data
    /// key, sealed into a new device slot (which asks for Touch ID as `AppSettings.touchIDUnlock` says) and wrapped
    /// into the new recovery slot; they replace the old slots, and a local backup is made with the new key. Returns
    /// the labels of the new code and of the one it replaced, which older backups still need, and whether the backup
    /// was made.
    ///
    /// The steps, each of which leaves a slot on disk that opens the database (see the type):
    /// 1. the device slot of the new key is made (its recovery slot is in `pending`);
    /// 2. the keys file is written with the slots of both keys;
    /// 3. the database is encrypted again with the new key (`Database.rekey(to:)`);
    /// 4. the file is opened with the new key on a connection of its own, and every page of it read;
    /// 5. the keys file is written with the new slots alone;
    /// 6. the backup is made (`backUpAfterKeyChange()`).
    ///
    /// Until the database has the new key, a failure throws and leaves the old key and the old keys file; when the
    /// rekey itself fails, the database is closed (see `Database.rekey(to:)`) and the vault locks, and unlocking opens
    /// the data with the old key. Once the database has the new key, the change has taken effect: a failure of step 5
    /// or 6 is logged, not thrown (`backupMade` tells whether the backup was made), as the keys file of both keys opens
    /// the data with the new code too, and the next unlock or change of the keys writes the file again. When step 4
    /// fails, which key the file has is not certain: the vault locks and throws, and the slots of both keys stay on
    /// disk for the next unlock to try.
    ///
    /// Throws `VaultError.locked` while the data is locked, and `VaultError.outdatedCode` when the recovery slots in
    /// force are no longer those `pending` was made to replace; nothing is written then.
    func commitNewRecoveryCode(_ pending: PendingRecoveryCode) async throws -> NewCodeOutcome {
        try beginStep()
        defer { endStep() }
        guard let database, dataKey != nil, let oldKeys = keys else {
            throw VaultError.locked
        }
        guard oldKeys.recoverySlots == pending.replaces else {
            throw VaultError.outdatedCode
        }
        let touchID = try await database.appSettings().touchIDUnlock
        let newKeys = KeysFile(
            deviceSlot: try device.seal(pending.key, userPresence: touchID), recoverySlots: [pending.slot]
        )
        reached(.newKeyMade)
        try await Self.saveKeys(newKeys.replacing(oldKeys), to: paths.keys)
        reached(.bothKeySetsSaved)
        do {
            try await database.rekey(to: pending.key)
        } catch {
            // The file keeps the old key, and the failed rekey closed the database, which could no longer be written
            // safely: the vault locks, and unlocking opens the data again with the old key. The file of both keys
            // opens it too, so putting the old file back only tidies up, and the next unlock does that if this fails.
            await saveKeys(oldKeys, logging: "Putting back the keys file of the old data key")
            await lock()
            throw error
        }
        adopt(database, key: pending.key, keys: newKeys)
        reached(.databaseRekeyed)
        do {
            try await Self.verify(paths.database, opensWith: pending.key)
        } catch {
            await lock()
            throw error
        }
        reached(.rekeyVerified)
        await saveKeys(newKeys, logging: "Removing the slots of the replaced data key")
        reached(.oldKeySetRemoved)
        let backupMade = await backUpAfterKeyChange()
        reached(.backupMade)
        return NewCodeOutcome(
            label: pending.label, previousLabel: oldKeys.newestRecoverySlot?.label ?? "", backupMade: backupMade
        )
    }

    /// Turns unlocking with Touch ID on or off. The data key and the recovery code stay: the data key is sealed into a
    /// new device slot, with a new device key of this Mac that asks for Touch ID or the password only when `on`, which
    /// replaces the device slot in the keys file; `AppSettings.touchIDUnlock` records the choice. Then a local backup
    /// is made, which carries the new slot (see `backUpAfterKeyChange()`); the outcome tells whether it was.
    ///
    /// Throws `VaultError.locked` while the data is locked. When this throws, the keys file and the setting are as they
    /// were.
    func setTouchID(_ on: Bool) async throws -> KeyChangeOutcome {
        try beginStep()
        defer { endStep() }
        guard let database, let dataKey, let keys else {
            throw VaultError.locked
        }
        var newKeys = keys
        newKeys.deviceSlot = try device.seal(dataKey, userPresence: on)
        let before = try await database.appSettings().touchIDUnlock
        try await database.updateAppSettings { $0.touchIDUnlock = on }
        do {
            try await Self.saveKeys(newKeys, to: paths.keys)
        } catch {
            // The device slot is the old one, so the setting goes back to what it was.
            do {
                _ = try await database.updateAppSettings { $0.touchIDUnlock = before }
            } catch let revertError {
                Self.log("Putting back the Touch ID setting", failedWith: revertError)
            }
            throw error
        }
        self.keys = newKeys
        return KeyChangeOutcome(backupMade: await backUpAfterKeyChange())
    }

    // MARK: Restoring a backup

    /// The header of the backup file at `url`: when and where it was made, what it holds and the slots that open it.
    /// Throws what `BackupFormat.readHeader(from:)` throws, and `BackupError.newerSchema` for a backup of a database of
    /// a newer schema than this version of the app knows, which it does not restore.
    func inspectBackup(_ url: URL) throws -> BackupHeader {
        let header = try BackupFormat.readHeader(from: url)
        guard header.schemaVersion <= Schema.latestVersion else {
            throw BackupError.newerSchema(header.schemaVersion)
        }
        return header
    }

    /// Whether the backup of `header` opens without its recovery code. It does when it was made with the data key that
    /// is open now, as it carries the device slot in force or one of the recovery slots in force (a slot wraps one data
    /// key, so the same slot means the same key); `restore` then uses the open key and asks for nothing. It does too
    /// when it carries a device slot that the device key of this Mac takes for its own (`DeviceKeyProtector.canOpen`),
    /// which `restore` opens, asking for Touch ID or the password when the slot needs it; this asks for nothing. A
    /// backup of another Mac needs the code that was valid when it was made.
    func canOpenWithDevice(_ header: BackupHeader) async -> Bool {
        if slotsOfOpenDataKey(in: header.keys) != nil {
            return true
        }
        return header.keys.slotSets.contains { slots in
            slots.deviceSlot.map { device.canOpen($0) } ?? false
        }
    }

    /// Restores the backup at `url` in place of the data and returns the restored database.
    ///
    /// The backup's data key is the open one when the backup was made with it; otherwise it comes from the backup's
    /// device slot when the device key of this Mac takes the slot for its own (see `canOpenWithDevice(_:)`), and from
    /// `recoveryCode` when it does not, or cannot open it after all. The backup's database is extracted beside the
    /// database and opened with that key, which migrates an older schema: only a database that opens replaces the data.
    /// Then the data that is there is kept — backed up with its own keys when it is open, set aside as it is when it
    /// is locked (see `setAsideData()`) — and the database file is replaced. The keys file gets the backup's recovery
    /// slots, so that the backup's code goes on opening the data, and a new device slot of this Mac, which asks for
    /// Touch ID as `AppSettings.touchIDUnlock` of the restored data says. While the data was open, the keys file holds
    /// the slots of both data keys until the file is replaced, so a crash at any moment leaves a slot that opens the
    /// database that is there. The backup made before the restore spares the file that is being restored, so that it
    /// is never pruned from under the restore.
    ///
    /// Throws `BackupError.newerSchema` for a backup of a newer schema, `KeyError.userCancelled` when the prompt for
    /// the device slot does not unlock (whatever `recoveryCode` is: the person can ask again),
    /// `KeyError.wrongRecoveryCode` when a code is needed and `recoveryCode` is nil or opens none of the backup's
    /// slots, `KeyError.malformedRecoveryCode` for text that is not a code, `BackupError.notABackup` when the backup's
    /// database does not open with its key, and what reading the backup, sealing, backing up and writing the keys
    /// file throw. Until the database file is replaced, a failure leaves the data, its keys and its files as they were
    /// (a backup of the open data may have been made). When replacing the file fails, the data stays locked, and its
    /// keys file opens the database that is there.
    func restore(from url: URL, recoveryCode: String?) async throws -> Database {
        try beginStep()
        defer { endStep() }
        let header = try inspectBackup(url)
        let candidates: [UnlockedSlots]
        if let slots = slotsOfOpenDataKey(in: header.keys), let dataKey {
            candidates = [UnlockedSlots(slots: slots, key: dataKey)]
        } else if let unlocked = try await openDeviceSlot(of: header.keys) {
            candidates = [unlocked]
        } else if let recoveryCode {
            candidates = try Self.unlock(header.keys, recoveryCode: recoveryCode)
        } else {
            throw KeyError.wrongRecoveryCode
        }
        try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        let extracted = paths.directory.appending(path: Self.extractedFileName)
        // What a restore that was cut off left there.
        removeDatabaseFiles(at: extracted)
        let restored: UnlockedSlots
        let restoredKeys: KeysFile
        let openBefore: Bool
        let setAside: URL?
        do {
            try await Self.extract(url, to: extracted)
            let opened = try await openExtracted(extracted, trying: candidates)
            restored = opened.unlocked
            restoredKeys = KeysFile(
                deviceSlot: try device.seal(restored.key, userPresence: opened.touchID),
                recoverySlots: restored.slots.recoverySlots
            )
            if let current = database, let currentKey = dataKey, let currentKeys = keys {
                let backup = try await backups.makeBackup(
                    database: current, key: currentKey, keys: currentKeys, sparing: url
                )
                if let cleanupError = backup.cleanupError {
                    Self.log("Removing old backups before a restore", failedWith: cleanupError)
                }
                try await Self.saveKeys(restoredKeys.replacing(currentKeys), to: paths.keys)
                openBefore = true
                setAside = nil
            } else {
                openBefore = false
                setAside = try setAsideData()
                do {
                    try await Self.saveKeys(restoredKeys, to: paths.keys)
                } catch {
                    putBack(setAside)
                    throw error
                }
            }
        } catch {
            removeDatabaseFiles(at: extracted)
            throw error
        }
        reached(.restoreKeySetsSaved)
        await lock()
        do {
            try replaceDatabase(with: extracted)
        } catch {
            removeDatabaseFiles(at: extracted)
            if !openBefore {
                // The data that was there was set aside, and goes back with its keys file.
                remove(paths.keys, logging: "Removing the keys file of a restore that did not finish")
                putBack(setAside)
            }
            throw error
        }
        removeDatabaseFiles(at: extracted)
        reached(.databaseReplaced)
        if openBefore {
            await saveKeys(restoredKeys, logging: "Removing the slots of the replaced data")
        }
        reached(.restoredKeysSettled)
        let database = try await Self.open(paths.database, key: restored.key)
        adopt(database, key: restored.key, keys: restoredKeys)
        return database
    }
}

// MARK: - Steps

/// The slots of one data key, with that key.
private nonisolated struct UnlockedSlots: Sendable {
    let slots: KeysFile
    let key: SymmetricKey
}

private extension Vault {
    /// Marks the start of a step that opens or changes something. Throws `VaultError.busy` while another one runs.
    func beginStep() throws {
        guard !isBusy else {
            throw VaultError.busy
        }
        isBusy = true
    }

    func endStep() {
        isBusy = false
    }

    /// Calls the observer of the tests, if there is one.
    func reached(_ step: VaultStep) {
        #if DEBUG
        stepObserver?(step)
        #endif
    }

    /// The day of the Mac's calendar at the clock's moment.
    func today() -> CivilDate {
        CivilDate.today(now: clock.now(), timeZone: .autoupdatingCurrent)
    }

    func adopt(_ database: Database, key: SymmetricKey, keys: KeysFile) {
        self.database = database
        self.dataKey = key
        self.keys = keys
    }

    /// Forgets the database, its key and its slots, and closes the database, if it is open.
    func lock() async {
        let open = database
        database = nil
        dataKey = nil
        keys = nil
        await open?.close()
    }

    /// The keys file of the data there is to unlock. Throws `VaultError.noData` unless the database and the keys file
    /// are both there, and what `KeyManager.load(_:)` throws for a keys file it cannot read.
    func storedKeys() throws -> KeysFile {
        guard Self.exists(paths.database), let keys = try KeyManager.load(paths.keys) else {
            throw VaultError.noData
        }
        return keys
    }

    /// The slots in force once `inForce`, one of the sets of `stored`, opened the database. When `stored` is the keys
    /// file of a change of the data key that was cut off, it is written again with those slots alone: that finishes the
    /// change, or undoes it, whichever way the database went. When the file cannot be written it stays as it is, which
    /// opens the database too, and the next unlock tries again.
    func settle(_ stored: KeysFile, inForce: KeysFile) async -> KeysFile {
        guard stored.previous != nil else {
            return stored
        }
        await saveKeys(inForce, logging: "Finishing a change of the keys that was cut off")
        return inForce
    }

    /// Writes `keys` to the keys file, and logs a failure instead of throwing it: for a write after which the file that
    /// is there opens the data as well, so only tidying up is lost.
    func saveKeys(_ keys: KeysFile, logging step: String) async {
        do {
            try await Self.saveKeys(keys, to: paths.keys)
        } catch {
            Self.log(step, failedWith: error)
        }
    }

    /// The data key of `keys` from a device slot of this Mac, with its slots: the first device slot that the device key
    /// takes for its own (`DeviceKeyProtector.canOpen`) and opens, which asks for Touch ID or the password when the
    /// slot needs it. Nil when there is none, or when the device key cannot open them after all; a prompt that does not
    /// unlock throws `KeyError.userCancelled`. A backup of the vault carries the slots of one data key, so there is one
    /// device slot to try.
    func openDeviceSlot(of keys: KeysFile) async throws -> UnlockedSlots? {
        for slots in keys.slotSets {
            guard let slot = slots.deviceSlot, device.canOpen(slot) else {
                continue
            }
            do {
                return UnlockedSlots(slots: slots, key: try await device.open(slot, reason: Self.restoreReason))
            } catch KeyError.deviceKeyUnusable {
                continue
            }
        }
        return nil
    }

    /// The slots of each data key in `keys` that `recoveryCode` opens, with the key they hold. Throws
    /// `KeyError.malformedRecoveryCode` for text that is not a code, and `KeyError.wrongRecoveryCode` when the code
    /// opens no slot.
    nonisolated static func unlock(_ keys: KeysFile, recoveryCode: String) throws -> [UnlockedSlots] {
        var unlocked: [UnlockedSlots] = []
        for slots in keys.slotSets {
            do {
                let key = try KeyManager.unlock(slots, recoveryCode: recoveryCode).dek
                unlocked.append(UnlockedSlots(slots: slots, key: key))
            } catch KeyError.wrongRecoveryCode {
                continue
            }
        }
        guard !unlocked.isEmpty else {
            throw KeyError.wrongRecoveryCode
        }
        return unlocked
    }

    /// The slots in `keys` of the data key that is open now, recognised by the slots alone: the set that has the device
    /// slot in force or one of the recovery slots in force. Nil while the data is locked, or when no set has them.
    func slotsOfOpenDataKey(in keys: KeysFile) -> KeysFile? {
        guard let current = self.keys else {
            return nil
        }
        return keys.slotSets.first { slots in
            (slots.deviceSlot != nil && slots.deviceSlot == current.deviceSlot)
                || slots.recoverySlots.contains { current.recoverySlots.contains($0) }
        }
    }

    /// Makes the local backup that follows a change of the keys, so that the newest backup carries the slots in force,
    /// records its moment as the last local backup (`AppSettings.lastLocalBackup`), and returns whether it was made.
    ///
    /// The change has taken effect by then, and a failure here does not turn it into a failure of the change, which
    /// would hide that the change happened. A backup that cannot be made is logged and the answer is false; the last
    /// local backup then stays as it was.
    func backUpAfterKeyChange() async -> Bool {
        guard let database, let dataKey, let keys else {
            return false
        }
        let backup: BackupResult
        do {
            backup = try await backups.makeBackup(database: database, key: dataKey, keys: keys)
        } catch {
            Self.log("The backup after a change of the keys", failedWith: error)
            return false
        }
        if let cleanupError = backup.cleanupError {
            Self.log("Removing old backups after a change of the keys", failedWith: cleanupError)
        }
        let created = backup.created
        do {
            try await database.updateAppSettings { $0.lastLocalBackup = created }
        } catch {
            Self.log("Recording the backup after a change of the keys", failedWith: error)
        }
        return true
    }

    /// Opens the database extracted from a backup with each candidate key in turn, which migrates a database of an
    /// older schema, reads its Touch ID setting, and closes it again to be moved into place. Returns the candidate that
    /// opened it. Throws `BackupError.notABackup` when none does: the backup's database is damaged, or not the one its
    /// slots belong to.
    func openExtracted(
        _ file: URL,
        trying candidates: [UnlockedSlots]
    ) async throws -> (unlocked: UnlockedSlots, touchID: Bool) {
        for candidate in candidates {
            guard let database = try await Self.openIfKeyFits(file, key: candidate.key) else {
                continue
            }
            let touchID: Bool
            do {
                touchID = try await database.appSettings().touchIDUnlock
            } catch {
                await database.close()
                throw error
            }
            await database.close()
            return (candidate, touchID)
        }
        throw BackupError.notABackup
    }

    /// Puts the database file `file` in place of the database; both are closed. The write-ahead log and the shared
    /// memory of the database go first, so that SQLite never reads them as part of the new file; then the file is
    /// renamed, which replaces the old one in one step.
    func replaceDatabase(with file: URL) throws {
        for companion in Self.companions(of: paths.database) {
            try Self.removeIfPresent(companion)
        }
        guard rename(file.path(percentEncoded: false), paths.database.path(percentEncoded: false)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    // MARK: Data set aside

    /// The files of the data: the database, its write-ahead log and shared memory, and the keys file.
    var dataFiles: [URL] {
        [paths.database] + Self.companions(of: paths.database) + [paths.keys]
    }

    /// Moves the files of the data that are there — the database, its write-ahead log and shared memory, and the keys
    /// file — into a new folder beside them, "Set aside 2026-10-18 14-05-12" after the clock in the Mac's local time,
    /// and returns the folder; nil when none of them is there. They are moved as they are, encrypted: what this vault
    /// cannot open now (the data of another Mac without its code, a database without its keys file) stays on disk for
    /// when its code or its keys turn up. When a move fails, the files moved go back and the error is thrown.
    func setAsideData() throws -> URL? {
        let files = dataFiles.filter { Self.exists($0) }
        guard !files.isEmpty else {
            return nil
        }
        let folder = newSetAsideFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        var moved: [URL] = []
        do {
            for file in files {
                try FileManager.default.moveItem(at: file, to: folder.appending(path: file.lastPathComponent))
                moved.append(file)
            }
        } catch {
            putBack(moved, from: folder)
            throw error
        }
        return folder
    }

    /// Moves the files that `setAsideData()` moved into `folder` back where they were.
    func putBack(_ folder: URL?) {
        guard let folder else {
            return
        }
        putBack(dataFiles, from: folder)
    }

    /// Moves those of `files` that are in `folder` back where they were, as far as it can, and removes the folder once
    /// it is empty: a file that cannot go back stays in the folder, and the failure is logged.
    func putBack(_ files: [URL], from folder: URL) {
        for file in files {
            let aside = folder.appending(path: file.lastPathComponent)
            guard Self.exists(aside) else {
                continue
            }
            do {
                try FileManager.default.moveItem(at: aside, to: file)
            } catch {
                Self.log("Putting back a file of the data that was set aside", failedWith: error)
            }
        }
        // rmdir removes only an empty folder.
        _ = rmdir(folder.path(percentEncoded: false))
    }

    /// A folder for data set aside that does not exist yet: "Set aside 2026-10-18 14-05-12" after the clock in the
    /// Mac's local time, and "… 2", "… 3" when the name is taken.
    func newSetAsideFolder() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let stem = "Set aside " + formatter.string(from: clock.now())
        var folder = paths.directory.appending(path: stem, directoryHint: .isDirectory)
        var number = 2
        while Self.exists(folder) {
            folder = paths.directory.appending(path: "\(stem) \(number)", directoryHint: .isDirectory)
            number += 1
        }
        return folder
    }

    // MARK: Files

    /// Removes the database file `url` with its write-ahead log and shared memory, as far as it can, and logs what
    /// cannot be removed. Only for files that hold nothing to keep: what stays is encrypted, and the next restore
    /// removes a leftover of its own.
    func removeDatabaseFiles(at url: URL) {
        for file in [url] + Self.companions(of: url) {
            remove(file, logging: "Removing a database file that holds nothing to keep")
        }
    }

    /// Removes the file at `url` if it is there, and logs a failure instead of throwing it.
    func remove(_ url: URL, logging step: String) {
        do {
            try Self.removeIfPresent(url)
        } catch {
            Self.log(step, failedWith: error)
        }
    }

    nonisolated static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// The write-ahead log and the shared memory of the database file `url`: its name with `-wal` and `-shm`.
    nonisolated static func companions(of url: URL) -> [URL] {
        let folder = url.deletingLastPathComponent()
        return ["-wal", "-shm"].map { folder.appending(path: url.lastPathComponent + $0) }
    }

    /// Removes the file at `url`. One that is not there is not an error.
    nonisolated static func removeIfPresent(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            // Nothing to remove.
        }
    }

    /// Opens the database at `url` with `key`, away from the main actor: migrating an older schema can take a while.
    @concurrent
    nonisolated static func open(_ url: URL, key: SymmetricKey) async throws -> Database {
        try Database(fileURL: url, key: key)
    }

    /// The database at `url` opened with `key` as `open` opens it, or nil when the file does not open with that key.
    @concurrent
    nonisolated static func openIfKeyFits(_ url: URL, key: SymmetricKey) async throws -> Database? {
        do {
            return try Database(fileURL: url, key: key)
        } catch SQLiteError.wrongKey {
            return nil
        }
    }

    /// Extracts the database of the backup at `url` into `file`, away from the main actor: the backup can be on a slow
    /// disk.
    @concurrent
    nonisolated static func extract(_ url: URL, to file: URL) async throws {
        try BackupFormat.extractDatabase(from: url, to: file)
    }

    /// Writes `keys` to the keys file `url` (see `KeyManager.save(_:to:)`), away from the main actor: flushing the file
    /// and its folder to the drive waits for the drive.
    @concurrent
    nonisolated static func saveKeys(_ keys: KeysFile, to url: URL) async throws {
        try KeyManager.save(keys, to: url)
    }

    /// Opens the database file at `url` with `key` on a connection of its own and reads every page of it, away from
    /// the main actor: proof that the file, as SQLite reads it from the disk, is encrypted with `key` throughout.
    @concurrent
    nonisolated static func verify(_ url: URL, opensWith key: SymmetricKey) async throws {
        let connection = try SQLiteConnection(path: url.path(percentEncoded: false), key: key)
        defer { connection.close() }
        guard try connection.scalar("PRAGMA quick_check") == .text("ok") else {
            throw SQLiteError.step("The database does not pass its check after the rekey.")
        }
    }

    /// Logs that `step` failed, with the domain and the code of the error alone: its description could name a file.
    static func log(_ step: String, failedWith error: any Error) {
        let error = error as NSError
        logger.error(
            "\(step, privacy: .public) failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)"
        )
    }
}

import CryptoKit
import Foundation
import Testing
@testable import InvoicesTracker

// MARK: - Test doubles and helpers

/// Seals like `SoftwareKeyProtector` and takes the same slots for its own, and opening any slot throws `error`: a Touch
/// ID prompt that was dismissed, or a device key this Mac cannot use after all (a repaired Mac, a damaged slot).
private struct FailingProtector: DeviceKeyProtector {
    let error: KeyError

    var name: String {
        SoftwareKeyProtector().name
    }

    func seal(_ dek: SymmetricKey, userPresence: Bool) throws -> DeviceSlot {
        try SoftwareKeyProtector().seal(dek, userPresence: userPresence)
    }

    func canOpen(_ slot: DeviceSlot) -> Bool {
        SoftwareKeyProtector().canOpen(slot)
    }

    func open(_ slot: DeviceSlot, reason: String) async throws -> SymmetricKey {
        throw error
    }
}

/// What the tests of the vault are made of: invented invoices, a clock at noon of a day, the vault of one launch of
/// the app, and the files in a folder.
@MainActor
private enum VaultFixtures {
    static let reason = "Odemknout data"

    /// A well-formed code that opens no slot.
    static let strangerCode = "7777-7777-7777-7777-7777-7777-7777-7777"

    /// The files of the data: the database, its write-ahead log and the log's shared memory, and the keys file.
    static let dataFileNames: Set = [
        "InvoicesTracker.sqlite", "InvoicesTracker.sqlite-wal", "InvoicesTracker.sqlite-shm", "InvoicesTracker.keys",
    ]

    /// Noon of the day in the Mac's own time zone and in the Gregorian calendar, so the clock's day is that day
    /// wherever the tests run.
    static func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        guard let value = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else {
            preconditionFailure("Not a day: \(year)-\(month)-\(day)")
        }
        return value
    }

    /// An invoice of invented data with its own number: `202609` and `number` as two digits.
    static func invoice(_ number: Int) -> Invoice {
        Invoice.fixture(number: "202609" + String(format: "%02d", number))
    }

    /// The vault of the data in `paths` as one launch of the app makes it, with its backup service, which makes the
    /// local backups in `paths.backups` and keeps the newest `keep`.
    static func vault(
        _ paths: VaultPaths,
        device: any DeviceKeyProtector = SoftwareKeyProtector(),
        clock: ManualClock,
        keep: Int = 30
    ) -> (vault: Vault, backups: BackupService) {
        let backups = BackupService(
            backupsDirectory: paths.backups, clock: clock, appVersion: "1.0", deviceName: "Testovací MacBook",
            keep: keep
        )
        return (Vault(paths: paths, device: device, backups: backups, clock: clock), backups)
    }

    /// Starts with empty data in `vault` as the first launch does, in its two steps: the code is made and shown, and
    /// the data is made once the person has stored the code. Returns the database with the code and its label.
    static func startFresh(
        _ vault: Vault,
        touchID: Bool = true
    ) async throws -> (database: Database, code: String, label: String) {
        let pending = try vault.prepareFreshStart()
        let database = try await vault.startFresh(pending, touchID: touchID)
        return (database, pending.code, pending.label)
    }

    /// A new recovery code in its two steps: the code is made and shown, and put in force once the person has stored
    /// it. Returns the code with what putting it in force tells.
    static func newCode(
        _ vault: Vault
    ) async throws -> (code: String, label: String, previousLabel: String, backupMade: Bool) {
        let pending = try vault.prepareNewRecoveryCode()
        let outcome = try await vault.commitNewRecoveryCode(pending)
        return (pending.code, outcome.label, outcome.previousLabel, outcome.backupMade)
    }

    /// The paths of the data in the folder `name` inside `directory`.
    static func paths(_ name: String, in directory: URL) -> VaultPaths {
        VaultPaths(directory: directory.appending(path: name, directoryHint: .isDirectory))
    }

    /// The keys file in `paths`, which has to be there.
    static func keysFile(_ paths: VaultPaths) throws -> KeysFile {
        try #require(try KeyManager.load(paths.keys))
    }

    /// The name and the bytes of every file directly in `directory`, hidden ones too. Folders are left out.
    static func files(in directory: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) {
            let url = directory.appending(path: name)
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            files[name] = try Data(contentsOf: url)
        }
        return files
    }

    /// The folders directly in `directory` whose names start with "Set aside ".
    static func setAsideFolders(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.hasPrefix("Set aside ") }
            .sorted()
    }

    /// Copies the files of the data in `paths` as they are at this moment — the database with its write-ahead log, and
    /// the keys file, whichever of them are there — into the new folder `directory`: what a crash now leaves on disk.
    /// The shared memory of the log is not copied: SQLite builds it again from the log.
    static func copyData(of paths: VaultPaths, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = paths.directory.appending(path: paths.database.lastPathComponent + "-wal")
        for file in [paths.database, log, paths.keys]
        where FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            try FileManager.default.copyItem(at: file, to: directory.appending(path: file.lastPathComponent))
        }
    }

    /// Sets the permissions of the folder at `url`: `0o555` for one nothing can be added to or removed from.
    static func setPermissions(_ mode: Int, on url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// Writes a backup file at `url` with `header` and the bytes `database` as its database.
    static func writeBackup(_ header: BackupHeader, database: Data, to url: URL) throws {
        let part = url.deletingLastPathComponent().appending(path: "\(url.lastPathComponent).part")
        try database.write(to: part)
        defer { try? FileManager.default.removeItem(at: part) }
        try BackupFormat.write(header: header, databaseFile: part, to: url)
    }
}

// MARK: - Vault

/// The vault: the first launch, unlocking with the device key and with the recovery code, a new recovery code, Touch
/// ID on and off, and restoring a backup — and that every step, also one cut off by a crash, leaves a slot that opens
/// the data. A software key protector stands in for the Secure Enclave, and every test has its own folder.
@MainActor
struct VaultTests {
    // MARK: First launch and unlocking with the device

    @Test func aFreshStartIsDataThatTheDeviceOpensAgainWithCodeNumberOneOfTheClocksDay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        #expect(vault.launchState() == .firstLaunch)
        #expect(vault.requiredRecoveryLabel == nil)

        // The code is shown first, and the data is made once the person has stored it.
        let pending = try vault.prepareFreshStart()
        #expect(vault.launchState() == .firstLaunch)
        let fresh = try await vault.startFresh(pending, touchID: true)
        try await fresh.saveInvoice(VaultFixtures.invoice(1))

        #expect(pending.label == "kód č. 1 z 18.\u{00A0}10.\u{00A0}2026")
        #expect(pending.code.split(separator: "-").map(\.count) == [4, 4, 4, 4, 4, 4, 4, 4])
        #expect(fresh.fileURL == paths.database)
        #expect(vault.database === fresh)
        #expect(vault.launchState() == .existing)
        #expect(vault.requiredRecoveryLabel == pending.label)
        let keys = try VaultFixtures.keysFile(paths)
        #expect(keys == vault.keys)
        #expect(keys.previous == nil)
        #expect(keys.deviceSlot?.userPresence == true)
        #expect(keys.recoverySlots.map(\.number) == [1])
        #expect(try KeyManager.unlock(keys, recoveryCode: pending.code).dek == vault.dataKey)
        #expect(try await fresh.appSettings().touchIDUnlock)
        await fresh.close()

        // The next launch.
        let (relaunched, _) = VaultFixtures.vault(paths, clock: clock)
        #expect(relaunched.launchState() == .existing)
        #expect(relaunched.database == nil)
        #expect(relaunched.requiredRecoveryLabel == pending.label)
        let database = try await relaunched.unlockWithDevice(reason: VaultFixtures.reason)
        #expect(try await database.invoiceCount() == 1)
        #expect(try await database.invoice(numberDigits: "20260901", currency: .czk) != nil)
        #expect(relaunched.database === database)
        #expect(relaunched.keys == keys)
        #expect(relaunched.dataKey == vault.dataKey)
    }

    /// Showing the code of a fresh start writes nothing, so an app that quits before the code is stored finds the
    /// first launch again.
    @Test func quittingAfterTheCodeOfAFreshStartWasShownLeavesTheFirstLaunch() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)

        let pending = try vault.prepareFreshStart()

        #expect(pending.label == "kód č. 1 z 18.\u{00A0}10.\u{00A0}2026")
        #expect(!FileManager.default.fileExists(atPath: paths.directory.path(percentEncoded: false)))
        #expect(vault.database == nil)
        let (relaunched, _) = VaultFixtures.vault(paths, clock: clock)
        #expect(relaunched.launchState() == .firstLaunch)
        #expect(relaunched.requiredRecoveryLabel == nil)
        // The next launch shows a new code.
        #expect(try relaunched.prepareFreshStart().code != pending.code)
    }

    @Test func aFreshStartWithoutTouchIDSealsTheDeviceSlotWithoutUserPresence() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let (vault, _) = VaultFixtures.vault(paths, clock: ManualClock(VaultFixtures.noon(2026, 10, 18)))

        let fresh = try await VaultFixtures.startFresh(vault, touchID: false)

        #expect(try VaultFixtures.keysFile(paths).deviceSlot?.userPresence == false)
        #expect(try await fresh.database.appSettings().touchIDUnlock == false)
    }

    /// A dismissed prompt leads to the locked screen, an unusable device key to the recovery code.
    @Test(arguments: [KeyError.userCancelled, .deviceKeyUnusable])
    func aDismissedPromptAndAnUnusableDeviceKeyComeThroughAndTheDataStaysLocked(_ error: KeyError) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        try await VaultFixtures.startFresh(vault).database.close()
        let keys = try VaultFixtures.keysFile(paths)

        let (locked, _) = VaultFixtures.vault(paths, device: FailingProtector(error: error), clock: clock)
        await #expect(throws: error) {
            _ = try await locked.unlockWithDevice(reason: VaultFixtures.reason)
        }

        #expect(locked.database == nil)
        #expect(locked.dataKey == nil)
        #expect(locked.keys == nil)
        #expect(try VaultFixtures.keysFile(paths) == keys)
    }

    /// Data that came from another Mac (through Migration Assistant, say) have a device slot whose key this Mac cannot
    /// load: the vault says so without a Touch ID prompt first, which could not have unlocked anything.
    @Test func aDeviceSlotOfAnotherMacIsUnusableWithoutAPrompt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (elsewhere, _) = VaultFixtures.vault(paths, device: OtherMacProtector(), clock: clock)
        try await VaultFixtures.startFresh(elsewhere, touchID: true).database.close()
        let protector = PromptCountingProtector()
        let (migrated, _) = VaultFixtures.vault(paths, device: protector, clock: clock)

        await #expect(throws: KeyError.deviceKeyUnusable) {
            _ = try await migrated.unlockWithDevice(reason: VaultFixtures.reason)
        }

        #expect(protector.prompts == 0)
        #expect(migrated.database == nil)

        // The slot of this Mac asks once, and opens.
        let fresh = VaultFixtures.paths("Fresh", in: directory)
        let (here, _) = VaultFixtures.vault(fresh, device: protector, clock: clock)
        try await VaultFixtures.startFresh(here, touchID: true).database.close()
        let (relaunched, _) = VaultFixtures.vault(fresh, device: protector, clock: clock)
        _ = try await relaunched.unlockWithDevice(reason: VaultFixtures.reason)
        #expect(protector.prompts == 1)
    }

    // MARK: Unlocking with the recovery code

    @Test func theCodeOpensTheDataWhenTheDeviceKeyIsUnusableAndSealsADeviceSlotOfThisMac() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        // Touch ID is off in the data itself, and a new device slot follows the data, not the slot it replaces.
        try await fresh.database.updateAppSettings { $0.touchIDUnlock = false }
        let before = try VaultFixtures.keysFile(paths)
        let dataKey = try #require(vault.dataKey)
        await fresh.database.close()

        let (newMac, _) = VaultFixtures.vault(
            paths, device: FailingProtector(error: .deviceKeyUnusable), clock: clock
        )
        await #expect(throws: KeyError.deviceKeyUnusable) {
            _ = try await newMac.unlockWithDevice(reason: VaultFixtures.reason)
        }
        // Typed as it may be: in lowercase, with spaces instead of dashes.
        let typed = fresh.code.lowercased().replacingOccurrences(of: "-", with: " ")
        let database = try await newMac.unlockWithRecoveryCode(typed)

        #expect(try await database.invoiceCount() == 1)
        #expect(newMac.database === database)
        #expect(newMac.dataKey == dataKey)
        let after = try VaultFixtures.keysFile(paths)
        #expect(after == newMac.keys)
        #expect(after.previous == nil)
        #expect(after.recoverySlots == before.recoverySlots)
        let deviceSlot = try #require(after.deviceSlot)
        #expect(deviceSlot != before.deviceSlot)
        #expect(deviceSlot.userPresence == false)
        #expect(try await SoftwareKeyProtector().open(deviceSlot, reason: VaultFixtures.reason) == dataKey)
        #expect(newMac.requiredRecoveryLabel == fresh.label)
        await database.close()

        // From now on the device of this Mac opens the data, and the same code still does.
        let (relaunched, _) = VaultFixtures.vault(paths, clock: clock)
        #expect(try await relaunched.unlockWithDevice(reason: VaultFixtures.reason).invoiceCount() == 1)
        #expect(try KeyManager.unlock(after, recoveryCode: fresh.code).dek == dataKey)
    }

    @Test func aWrongCodeIsRefusedAndChangesNothingOnDisk() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        await fresh.database.close()
        let before = try VaultFixtures.files(in: paths.directory)

        let (newMac, _) = VaultFixtures.vault(
            paths, device: FailingProtector(error: .deviceKeyUnusable), clock: clock
        )
        await #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try await newMac.unlockWithRecoveryCode(VaultFixtures.strangerCode)
        }
        await #expect(throws: KeyError.malformedRecoveryCode) {
            _ = try await newMac.unlockWithRecoveryCode("K7QF-2M9X")
        }

        #expect(try VaultFixtures.files(in: paths.directory) == before)
        #expect(newMac.database == nil)
        #expect(newMac.dataKey == nil)
    }

    // MARK: A new recovery code

    @Test func aNewCodeGivesTheDataANewKeyAndAnOlderBackupStillOpensWithTheOldCode() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, backups) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        let oldKey = try #require(vault.dataKey)
        let older = try await backups.makeBackup(
            database: fresh.database, key: oldKey, keys: try #require(vault.keys)
        )
        try await fresh.database.saveInvoice(VaultFixtures.invoice(2))
        // Touch ID is off in the data, which the new device slot follows.
        try await fresh.database.updateAppSettings { $0.touchIDUnlock = false }
        clock.set(VaultFixtures.noon(2026, 10, 19))

        let pending = try vault.prepareNewRecoveryCode()
        #expect(pending.label == "kód č. 2 z 19.\u{00A0}10.\u{00A0}2026")
        let outcome = try await vault.commitNewRecoveryCode(pending)

        #expect(outcome == NewCodeOutcome(label: pending.label, previousLabel: fresh.label, backupMade: true))
        #expect(pending.code != fresh.code)
        #expect(vault.requiredRecoveryLabel == pending.label)
        // The keys file has the new slots alone: the old code opens nothing, the new one the new key.
        let keys = try VaultFixtures.keysFile(paths)
        #expect(keys == vault.keys)
        #expect(keys.previous == nil)
        #expect(keys.recoverySlots.map(\.number) == [2])
        #expect(keys.deviceSlot?.userPresence == false)
        #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try KeyManager.unlock(keys, recoveryCode: fresh.code)
        }
        let newKey = try KeyManager.unlock(keys, recoveryCode: pending.code).dek
        #expect(newKey == vault.dataKey)
        #expect(newKey != oldKey)
        let deviceSlot = try #require(keys.deviceSlot)
        #expect(try await SoftwareKeyProtector().open(deviceSlot, reason: VaultFixtures.reason) == newKey)
        // The open database goes on working.
        try await fresh.database.saveInvoice(VaultFixtures.invoice(3))
        // A backup with the new key and slots, recorded as the last local backup.
        let listing = try backups.localBackups()
        #expect(listing.count == 2)
        let newest = try #require(listing.first)
        #expect(newest.header.keys == keys)
        #expect(try await fresh.database.appSettings().lastLocalBackup == newest.header.created)
        await fresh.database.close()
        // The file no longer opens with the old key; the device opens it with the new one.
        #expect(throws: SQLiteError.wrongKey) {
            _ = try Database(fileURL: paths.database, key: oldKey)
        }
        let (relaunched, _) = VaultFixtures.vault(paths, clock: clock)
        #expect(try await relaunched.unlockWithDevice(reason: VaultFixtures.reason).invoiceCount() == 3)

        // The backup made before opens with the old code, and only with it, when it is restored on another Mac.
        let elsewhere = VaultFixtures.paths("Other Mac", in: directory)
        let (other, _) = VaultFixtures.vault(elsewhere, device: OtherMacProtector(), clock: clock)
        await #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try await other.restore(from: older.url, recoveryCode: pending.code)
        }
        let restored = try await other.restore(from: older.url, recoveryCode: fresh.code)
        #expect(try await restored.invoiceCount() == 1)
    }

    /// Showing a new code writes nothing and keeps nothing: until it is put in force, the data, its keys and its
    /// backups stay as they are, and an app that quits in between finds the old code in force.
    @Test func aNewCodeThatIsShownButNotPutInForceChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, backups) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        let keysBefore = try Data(contentsOf: paths.keys)
        let keysInForce = vault.keys
        clock.set(VaultFixtures.noon(2026, 10, 19))

        let pending = try vault.prepareNewRecoveryCode()

        #expect(pending.label == "kód č. 2 z 19.\u{00A0}10.\u{00A0}2026")
        #expect(pending.code != fresh.code)
        #expect(try Data(contentsOf: paths.keys) == keysBefore)
        #expect(vault.keys == keysInForce)
        #expect(vault.requiredRecoveryLabel == fresh.label)
        // The app quits before the code is put in force.
        await fresh.database.close()
        let (relaunched, _) = VaultFixtures.vault(paths, clock: clock)
        #expect(try await relaunched.unlockWithDevice(reason: VaultFixtures.reason).invoiceCount() == 1)
        #expect(try Data(contentsOf: paths.keys) == keysBefore)
        await relaunched.database?.close()
        let (newMac, _) = VaultFixtures.vault(
            paths, device: FailingProtector(error: .deviceKeyUnusable), clock: clock
        )
        await #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try await newMac.unlockWithRecoveryCode(pending.code)
        }
        #expect(try await newMac.unlockWithRecoveryCode(fresh.code).invoiceCount() == 1)
        #expect(try backups.localBackups().isEmpty)
    }

    /// A code is put in force only in place of the code it was made to replace: after another new code or a restore
    /// it is refused, and nothing is written.
    @Test func aCodeMadeForSlotsThatAreNoLongerInForceIsRefusedWithNothingWritten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, backups) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        let backup = try await backups.makeBackup(
            database: fresh.database, key: try #require(vault.dataKey), keys: try #require(vault.keys)
        )
        let first = try vault.prepareNewRecoveryCode()
        let second = try vault.prepareNewRecoveryCode()
        #expect(first.label == second.label)
        clock.advance(by: 60)
        _ = try await vault.commitNewRecoveryCode(first)
        let keysAfterFirst = try Data(contentsOf: paths.keys)
        let backupCount = try backups.localBackups().count

        await #expect(throws: VaultError.outdatedCode) {
            _ = try await vault.commitNewRecoveryCode(second)
        }

        #expect(try Data(contentsOf: paths.keys) == keysAfterFirst)
        #expect(try backups.localBackups().count == backupCount)
        #expect(try KeyManager.unlock(try VaultFixtures.keysFile(paths), recoveryCode: first.code).dek == vault.dataKey)

        // A restore brings the slots of the backup.
        let third = try vault.prepareNewRecoveryCode()
        clock.advance(by: 60)
        let restored = try await vault.restore(from: backup.url, recoveryCode: fresh.code)
        let keysAfterRestore = try Data(contentsOf: paths.keys)
        let dataKey = vault.dataKey

        await #expect(throws: VaultError.outdatedCode) {
            _ = try await vault.commitNewRecoveryCode(third)
        }

        #expect(try Data(contentsOf: paths.keys) == keysAfterRestore)
        #expect(vault.dataKey == dataKey)
        #expect(try await restored.invoiceCount() == 1)
        #expect(vault.requiredRecoveryLabel == fresh.label)
    }

    /// A crash at any moment of a new code leaves data that the device of this Mac opens, and one code that opens it:
    /// the old code until the database has the new key, and the new code from then on. Unlocking finishes the keys
    /// file, so it holds the slots of one key again.
    @Test(arguments: [
        VaultStep.newKeyMade, .bothKeySetsSaved, .databaseRekeyed, .rekeyVerified, .oldKeySetRemoved, .backupMade,
    ])
    func aNewCodeCutOffByACrashStillOpensWithTheDeviceAndWithTheCodeInForce(at step: VaultStep) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let byDevice = VaultFixtures.paths("After the crash", in: directory)
        let byCode = VaultFixtures.paths("After the crash on a new Mac", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        try await fresh.database.saveInvoice(VaultFixtures.invoice(2))
        let oldKey = try #require(vault.dataKey)
        var reached: [VaultStep] = []
        vault.stepObserver = { current in
            reached.append(current)
            guard current == step else { return }
            do {
                try VaultFixtures.copyData(of: paths, to: byDevice.directory)
                try VaultFixtures.copyData(of: paths, to: byCode.directory)
            } catch {
                Issue.record(error)
            }
        }

        let new = try await VaultFixtures.newCode(vault)

        let allSteps: [VaultStep] = [
            .newKeyMade, .bothKeySetsSaved, .databaseRekeyed, .rekeyVerified, .oldKeySetRemoved, .backupMade,
        ]
        #expect(reached == allSteps)
        let newKey = try #require(vault.dataKey)
        let rekeyed = ![VaultStep.newKeyMade, .bothKeySetsSaved].contains(step)
        let keyInForce = rekeyed ? newKey : oldKey
        let codeInForce = rekeyed ? new.code : fresh.code
        let otherCode = rekeyed ? fresh.code : new.code

        let (relaunched, _) = VaultFixtures.vault(byDevice, clock: clock)
        #expect(relaunched.launchState() == .existing)
        let database = try await relaunched.unlockWithDevice(reason: VaultFixtures.reason)
        #expect(try await database.invoiceCount() == 2)
        #expect(relaunched.dataKey == keyInForce)
        let settled = try VaultFixtures.keysFile(byDevice)
        #expect(settled == relaunched.keys)
        #expect(settled.previous == nil)
        #expect(try KeyManager.unlock(settled, recoveryCode: codeInForce).dek == keyInForce)

        let (newMac, _) = VaultFixtures.vault(
            byCode, device: FailingProtector(error: .deviceKeyUnusable), clock: clock
        )
        await #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try await newMac.unlockWithRecoveryCode(otherCode)
        }
        #expect(try await newMac.unlockWithRecoveryCode(codeInForce).invoiceCount() == 2)
        #expect(newMac.dataKey == keyInForce)
        #expect(try VaultFixtures.keysFile(byCode).previous == nil)
    }

    @Test func aNewCodeWhoseKeysFileCannotBeWrittenChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        let before = try VaultFixtures.keysFile(paths)
        let oldKey = try #require(vault.dataKey)
        // Nothing can be added to the folder, so the keys file cannot be replaced.
        try VaultFixtures.setPermissions(0o555, on: paths.directory)
        defer { try? VaultFixtures.setPermissions(0o755, on: paths.directory) }

        await #expect(throws: (any Error).self) {
            _ = try await VaultFixtures.newCode(vault)
        }

        try VaultFixtures.setPermissions(0o755, on: paths.directory)
        #expect(try VaultFixtures.keysFile(paths) == before)
        #expect(vault.keys == before)
        #expect(vault.dataKey == oldKey)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(2))
        await fresh.database.close()
        #expect(try await Database(fileURL: paths.database, key: oldKey).invoiceCount() == 2)
    }

    @Test func aNewCodeWhoseRekeyFailsPutsTheOldKeysFileBackAndLocks() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        let before = try VaultFixtures.keysFile(paths)
        let oldKey = try #require(vault.dataKey)
        var bothSetsWereSaved = false
        var writer: SQLiteConnection?
        vault.stepObserver = { step in
            guard step == .bothKeySetsSaved else { return }
            bothSetsWereSaved = (try? VaultFixtures.keysFile(paths).previous) != nil
            // Another connection holds the lock for writing, so the rekey cannot begin.
            do {
                let connection = try SQLiteConnection(path: paths.database.path(percentEncoded: false), key: oldKey)
                try connection.execute("BEGIN IMMEDIATE")
                writer = connection
            } catch {
                Issue.record(error)
            }
        }

        await #expect(throws: SQLiteError.self) {
            _ = try await VaultFixtures.newCode(vault)
        }

        try writer?.execute("ROLLBACK")
        writer?.close()
        #expect(bothSetsWereSaved)
        #expect(try VaultFixtures.keysFile(paths) == before)
        // The failed rekey closed the database, which could no longer be written safely, and the vault locked.
        #expect(vault.database == nil)
        #expect(vault.dataKey == nil)
        await #expect(throws: SQLiteError.self) {
            try await fresh.database.saveInvoice(VaultFixtures.invoice(2))
        }
        // Unlocking opens the data, intact, with the old key and the old code.
        let (relaunched, _) = VaultFixtures.vault(paths, clock: clock)
        let database = try await relaunched.unlockWithDevice(reason: VaultFixtures.reason)
        #expect(try await database.text("PRAGMA quick_check") == "ok")
        #expect(try await database.invoiceCount() == 1)
        #expect(relaunched.dataKey == oldKey)
        #expect(try KeyManager.unlock(try VaultFixtures.keysFile(paths), recoveryCode: fresh.code).dek == oldKey)
    }

    /// A database that can no longer be read refuses the new code before anything is written: the Touch ID setting
    /// that the new device slot follows comes from it.
    @Test func aNewCodeForAClosedDatabaseWritesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let (vault, _) = VaultFixtures.vault(paths, clock: ManualClock(VaultFixtures.noon(2026, 10, 18)))
        let fresh = try await VaultFixtures.startFresh(vault)
        let keysBefore = try Data(contentsOf: paths.keys)
        var reached: [VaultStep] = []
        vault.stepObserver = { reached.append($0) }
        // A closed database refuses every statement.
        await fresh.database.close()

        await #expect(throws: SQLiteError.self) {
            _ = try await VaultFixtures.newCode(vault)
        }

        #expect(reached.isEmpty)
        #expect(try Data(contentsOf: paths.keys) == keysBefore)
    }

    /// Once the database has the new key, the old code no longer opens it, so the new code has to reach the person even
    /// when the old slots cannot be removed: the keys file of both keys stays, and opens the data with the new code.
    @Test func aNewCodeComesBackWhenTheOldSlotsCannotBeRemoved() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        vault.stepObserver = { step in
            guard step == .rekeyVerified else { return }
            do {
                try VaultFixtures.setPermissions(0o555, on: paths.directory)
            } catch {
                Issue.record(error)
            }
        }
        defer { try? VaultFixtures.setPermissions(0o755, on: paths.directory) }

        let new = try await VaultFixtures.newCode(vault)

        #expect(!new.backupMade)
        try VaultFixtures.setPermissions(0o755, on: paths.directory)
        let keys = try VaultFixtures.keysFile(paths)
        #expect(keys.previous != nil)
        #expect(try KeyManager.unlock(keys, recoveryCode: new.code).dek == vault.dataKey)
        #expect(vault.keys?.previous == nil)
        // The backup failed as well, as the folder for it could not be made: the last backup is not recorded.
        #expect(try await fresh.database.appSettings().lastLocalBackup == nil)
        await fresh.database.close()
        let (newMac, _) = VaultFixtures.vault(
            paths, device: FailingProtector(error: .deviceKeyUnusable), clock: clock
        )
        await #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try await newMac.unlockWithRecoveryCode(fresh.code)
        }
        #expect(try await newMac.unlockWithRecoveryCode(new.code).invoiceCount() == 1)
        #expect(try VaultFixtures.keysFile(paths).previous == nil)
    }

    @Test func aNewCodeComesBackWhenNoBackupCanBeMade() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        // A file where the backups folder would be.
        try Data().write(to: paths.directory.appending(path: "Backups"))

        let new = try await VaultFixtures.newCode(vault)

        #expect(!new.backupMade)
        let keys = try VaultFixtures.keysFile(paths)
        #expect(keys.previous == nil)
        #expect(try KeyManager.unlock(keys, recoveryCode: new.code).dek == vault.dataKey)
        #expect(try await fresh.database.appSettings().lastLocalBackup == nil)
        #expect(try VaultFixtures.files(in: paths.directory)["Backups"] == Data())
    }

    /// When the file does not open with the new key after the rekey, which key it has is not certain: the vault locks
    /// and the keys file keeps the slots of both keys, so the next unlock can try both.
    @Test func aRekeyThatCannotBeConfirmedLocksTheVaultAndKeepsTheSlotsOfBothKeys() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        vault.stepObserver = { step in
            guard step == .databaseRekeyed else { return }
            // Damages the first page on disk, which the open connection does not read again.
            do {
                let file = try FileHandle(forWritingTo: paths.database)
                try file.seek(toOffset: 100)
                try file.write(contentsOf: Data(repeating: 0xA5, count: 64))
                try file.close()
            } catch {
                Issue.record(error)
            }
        }

        await #expect(throws: SQLiteError.wrongKey) {
            _ = try await VaultFixtures.newCode(vault)
        }

        #expect(vault.database == nil)
        #expect(vault.dataKey == nil)
        #expect(vault.keys == nil)
        #expect(try VaultFixtures.keysFile(paths).previous != nil)
        await #expect(throws: SQLiteError.self) {
            _ = try await fresh.database.invoiceCount()
        }
    }

    // MARK: Touch ID on and off

    @Test func touchIDOffSealsANewDeviceSlotKeepsTheKeyAndTheCodeAndMakesABackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, backups) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        let before = try VaultFixtures.keysFile(paths)
        let dataKey = try #require(vault.dataKey)
        #expect(try backups.localBackups().isEmpty)

        let outcome = try await vault.setTouchID(false)

        #expect(outcome.backupMade)
        let keys = try VaultFixtures.keysFile(paths)
        #expect(keys == vault.keys)
        #expect(keys.previous == nil)
        let deviceSlot = try #require(keys.deviceSlot)
        #expect(deviceSlot.userPresence == false)
        #expect(deviceSlot != before.deviceSlot)
        #expect(keys.recoverySlots == before.recoverySlots)
        #expect(vault.dataKey == dataKey)
        #expect(try await SoftwareKeyProtector().open(deviceSlot, reason: VaultFixtures.reason) == dataKey)
        #expect(try KeyManager.unlock(keys, recoveryCode: fresh.code).dek == dataKey)
        let listing = try backups.localBackups()
        #expect(listing.count == 1)
        #expect(listing.first?.header.keys == keys)
        #expect(listing.first?.header.invoiceCount == 1)
        let settings = try await fresh.database.appSettings()
        #expect(settings.touchIDUnlock == false)
        #expect(settings.lastLocalBackup == listing.first?.header.created)

        clock.advance(by: 60)
        #expect(try await vault.setTouchID(true).backupMade)

        #expect(try VaultFixtures.keysFile(paths).deviceSlot?.userPresence == true)
        #expect(try await fresh.database.appSettings().touchIDUnlock)
        #expect(try backups.localBackups().count == 2)
        await fresh.database.close()
        // The data key is the same, so the code and the device open the data as before.
        let (newMac, _) = VaultFixtures.vault(
            paths, device: FailingProtector(error: .deviceKeyUnusable), clock: clock
        )
        #expect(try await newMac.unlockWithRecoveryCode(fresh.code).invoiceCount() == 1)
        #expect(newMac.dataKey == dataKey)
    }

    @Test func touchIDThatCannotBeSavedLeavesTheKeysFileAndTheSettingAsTheyWere() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, backups) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        let before = try VaultFixtures.keysFile(paths)
        try VaultFixtures.setPermissions(0o555, on: paths.directory)
        defer { try? VaultFixtures.setPermissions(0o755, on: paths.directory) }

        await #expect(throws: (any Error).self) {
            try await vault.setTouchID(false)
        }

        try VaultFixtures.setPermissions(0o755, on: paths.directory)
        #expect(try VaultFixtures.keysFile(paths) == before)
        #expect(vault.keys == before)
        #expect(try await fresh.database.appSettings().touchIDUnlock)
        #expect(try backups.localBackups().isEmpty)
    }

    /// The change takes effect without the backup that follows it, and says so, so the app does not claim a backup.
    @Test func touchIDOffWhenNoBackupCanBeMadeSaysThatNoneWasMade() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let (vault, _) = VaultFixtures.vault(paths, clock: ManualClock(VaultFixtures.noon(2026, 10, 18)))
        let fresh = try await VaultFixtures.startFresh(vault)
        // A file where the backups folder would be.
        try Data().write(to: paths.directory.appending(path: "Backups"))

        let outcome = try await vault.setTouchID(false)

        #expect(!outcome.backupMade)
        #expect(try VaultFixtures.keysFile(paths).deviceSlot?.userPresence == false)
        let settings = try await fresh.database.appSettings()
        #expect(settings.touchIDUnlock == false)
        #expect(settings.lastLocalBackup == nil)
    }

    // MARK: Restoring a backup

    @Test func aBackupOfAnotherMacNeedsItsCodeAndReplacesTheDataOnlyAfterBackingItUp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        // Another Mac's data, with Touch ID off, and its backup.
        let (other, otherBackups) = VaultFixtures.vault(
            VaultFixtures.paths("Other Mac", in: directory), device: OtherMacProtector(), clock: clock
        )
        let otherFresh = try await VaultFixtures.startFresh(other, touchID: false)
        try await otherFresh.database.saveInvoice(VaultFixtures.invoice(1))
        try await otherFresh.database.saveInvoice(VaultFixtures.invoice(2))
        let backup = try await otherBackups.makeBackup(
            database: otherFresh.database, key: try #require(other.dataKey), keys: try #require(other.keys)
        )
        // This Mac's data.
        let paths = VaultFixtures.paths("Data", in: directory)
        let (vault, backups) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(7))
        let ownKeys = try #require(vault.keys)
        let ownKey = try #require(vault.dataKey)
        clock.advance(by: 60)

        let header = try vault.inspectBackup(backup.url)
        #expect(header.invoiceCount == 2)
        #expect(await vault.canOpenWithDevice(header) == false)
        await #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try await vault.restore(from: backup.url, recoveryCode: nil)
        }
        await #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try await vault.restore(from: backup.url, recoveryCode: fresh.code)
        }
        #expect(try await fresh.database.invoiceCount() == 1)
        #expect(try backups.localBackups().isEmpty)

        let restored = try await vault.restore(from: backup.url, recoveryCode: otherFresh.code)

        #expect(try await restored.invoiceCount() == 2)
        #expect(try await restored.invoice(numberDigits: "20260902", currency: .czk) != nil)
        #expect(try await restored.invoice(numberDigits: "20260907", currency: .czk) == nil)
        #expect(restored.fileURL == paths.database)
        #expect(vault.database === restored)
        #expect(vault.dataKey == other.dataKey)
        // The data that was there went into a backup first, with its own keys and code.
        let saved = try #require(try backups.localBackups().first)
        #expect(try backups.localBackups().count == 1)
        #expect(saved.header.invoiceCount == 1)
        #expect(saved.header.keys == ownKeys)
        #expect(try KeyManager.unlock(saved.header.keys, recoveryCode: fresh.code).dek == ownKey)
        await #expect(throws: SQLiteError.self) {
            _ = try await fresh.database.invoiceCount()
        }
        // The keys file: the backup's recovery slot, which its code opens, and a device slot of this Mac that follows
        // the Touch ID setting of the restored data.
        let keys = try VaultFixtures.keysFile(paths)
        #expect(keys == vault.keys)
        #expect(keys.previous == nil)
        #expect(keys.recoverySlots == header.keys.recoverySlots)
        #expect(keys.deviceSlot?.protector == SoftwareKeyProtector().name)
        #expect(keys.deviceSlot?.userPresence == false)
        #expect(try KeyManager.unlock(keys, recoveryCode: otherFresh.code).dek == vault.dataKey)
        #expect(vault.requiredRecoveryLabel == otherFresh.label)
        // Nothing of the restore is left beside the data.
        #expect(try Set(VaultFixtures.files(in: paths.directory).keys).isSubset(of: VaultFixtures.dataFileNames))
        await restored.close()

        // The next launch: the device of this Mac opens the restored data.
        let (relaunched, _) = VaultFixtures.vault(paths, clock: clock)
        #expect(try await relaunched.unlockWithDevice(reason: VaultFixtures.reason).invoiceCount() == 2)
    }

    @Test func aBackupOfANewerSchemaIsRefusedBeforeAnythingChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, backups) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        let file = directory.appending(path: "Newer.ttbackup")
        let header = BackupHeader(
            created: VaultFixtures.noon(2027, 3, 1), appVersion: "2.0", schemaVersion: 99, invoiceCount: 3,
            deviceName: "Jiný Mac", keys: try #require(vault.keys)
        )
        try VaultFixtures.writeBackup(header, database: Data("not read".utf8), to: file)
        let keysBefore = try Data(contentsOf: paths.keys)
        let namesBefore = try Set(VaultFixtures.files(in: paths.directory).keys)

        #expect(throws: BackupError.newerSchema(99)) {
            _ = try vault.inspectBackup(file)
        }
        await #expect(throws: BackupError.newerSchema(99)) {
            _ = try await vault.restore(from: file, recoveryCode: fresh.code)
        }

        #expect(try Data(contentsOf: paths.keys) == keysBefore)
        #expect(try Set(VaultFixtures.files(in: paths.directory).keys) == namesBefore)
        #expect(vault.database === fresh.database)
        #expect(try await fresh.database.invoiceCount() == 1)
        #expect(try backups.localBackups().isEmpty)
    }

    /// A backup whose database does not open with its own key fails the restore before anything is replaced: the
    /// extracted file goes, and the data, its keys and its backups stay as they were.
    @Test func aBackupWhoseDatabaseDoesNotOpenChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, backups) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        let file = directory.appending(path: "Damaged.ttbackup")
        let header = BackupHeader(
            created: VaultFixtures.noon(2026, 10, 17), appVersion: "1.0", schemaVersion: Schema.latestVersion,
            invoiceCount: 1, deviceName: "Testovací MacBook", keys: try #require(vault.keys)
        )
        try VaultFixtures.writeBackup(header, database: KeyManager.randomBytes(count: 8192), to: file)
        let keysBefore = try Data(contentsOf: paths.keys)
        let namesBefore = try Set(VaultFixtures.files(in: paths.directory).keys)
        #expect(await vault.canOpenWithDevice(header))

        await #expect(throws: BackupError.notABackup) {
            _ = try await vault.restore(from: file, recoveryCode: fresh.code)
        }

        #expect(vault.database === fresh.database)
        #expect(try await fresh.database.invoiceCount() == 1)
        #expect(try Data(contentsOf: paths.keys) == keysBefore)
        #expect(try Set(VaultFixtures.files(in: paths.directory).keys) == namesBefore)
        #expect(try backups.localBackups().isEmpty)
    }

    /// A backup made with the data key that is open now — before Touch ID was turned off, say — opens without a code.
    @Test func aBackupOfTheOpenDataKeyIsRestoredWithoutACodeOrAPrompt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        // Any prompt would be dismissed, so the restore below asks for none.
        let (vault, backups) = VaultFixtures.vault(
            paths, device: FailingProtector(error: .userCancelled), clock: clock
        )
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        let dataKey = try #require(vault.dataKey)
        let first = try await backups.makeBackup(database: fresh.database, key: dataKey, keys: try #require(vault.keys))
        clock.advance(by: 60)
        _ = try await vault.setTouchID(false)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(2))
        let recoverySlots = try VaultFixtures.keysFile(paths).recoverySlots
        let header = try vault.inspectBackup(first.url)
        #expect(header.keys.deviceSlot != vault.keys?.deviceSlot)
        #expect(await vault.canOpenWithDevice(header))
        // Locked, this Mac opens it with its device key; another Mac does not.
        let (lockedHere, _) = VaultFixtures.vault(paths, clock: clock)
        #expect(await lockedHere.canOpenWithDevice(header))
        let (lockedElsewhere, _) = VaultFixtures.vault(paths, device: OtherMacProtector(), clock: clock)
        #expect(await lockedElsewhere.canOpenWithDevice(header) == false)

        let restored = try await vault.restore(from: first.url, recoveryCode: nil)

        #expect(try await restored.invoiceCount() == 1)
        #expect(vault.dataKey == dataKey)
        let keys = try VaultFixtures.keysFile(paths)
        #expect(keys.recoverySlots == recoverySlots)
        // Touch ID was on in the data of the backup.
        #expect(keys.deviceSlot?.userPresence == true)
        // The data from before the restore, with both invoices, is the newest backup.
        #expect(try backups.localBackups().first?.header.invoiceCount == 2)
    }

    /// A backup this Mac made with another data key — before a new code, or the one made just before a restore — opens
    /// with the device key of this Mac (asking for Touch ID when the slot needs it), without a code.
    @Test func backupsOfThisMacWithAnotherDataKeyOpenWithTheDeviceWithoutACode() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, backups) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        let oldKey = try #require(vault.dataKey)
        let older = try await backups.makeBackup(database: fresh.database, key: oldKey, keys: try #require(vault.keys))
        try await fresh.database.saveInvoice(VaultFixtures.invoice(2))
        clock.advance(by: 60)
        let new = try await VaultFixtures.newCode(vault)
        let newKey = try #require(vault.dataKey)
        clock.advance(by: 60)
        #expect(await vault.canOpenWithDevice(try vault.inspectBackup(older.url)))

        let restored = try await vault.restore(from: older.url, recoveryCode: nil)

        #expect(try await restored.invoiceCount() == 1)
        #expect(vault.dataKey == oldKey)
        #expect(vault.requiredRecoveryLabel == fresh.label)
        // The data from before the restore, with the new key, is the newest backup, and it opens the same way.
        let beforeRestore = try #require(try backups.localBackups().first)
        #expect(beforeRestore.header.invoiceCount == 2)
        #expect(await vault.canOpenWithDevice(beforeRestore.header))
        clock.advance(by: 60)

        let back = try await vault.restore(from: beforeRestore.url, recoveryCode: nil)

        #expect(try await back.invoiceCount() == 2)
        #expect(vault.dataKey == newKey)
        #expect(vault.requiredRecoveryLabel == new.label)
    }

    /// A prompt dismissed while a backup is restored leaves everything as it was, even with a code given: the person
    /// can try again.
    @Test func aPromptDismissedDuringARestoreChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, backups) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        let older = try await backups.makeBackup(
            database: fresh.database, key: try #require(vault.dataKey), keys: try #require(vault.keys)
        )
        try await fresh.database.saveInvoice(VaultFixtures.invoice(2))
        clock.advance(by: 60)
        let new = try await VaultFixtures.newCode(vault)
        await fresh.database.close()
        // The next launch, unlocked with the code, where the person dismisses the prompt of the restore.
        let (cancelling, cancellingBackups) = VaultFixtures.vault(
            paths, device: FailingProtector(error: .userCancelled), clock: clock
        )
        let database = try await cancelling.unlockWithRecoveryCode(new.code)
        let keysBefore = try Data(contentsOf: paths.keys)
        let namesBefore = try Set(VaultFixtures.files(in: paths.directory).keys)
        let backupCount = try cancellingBackups.localBackups().count
        #expect(await cancelling.canOpenWithDevice(try cancelling.inspectBackup(older.url)))

        await #expect(throws: KeyError.userCancelled) {
            _ = try await cancelling.restore(from: older.url, recoveryCode: fresh.code)
        }

        #expect(cancelling.database === database)
        #expect(try await database.invoiceCount() == 2)
        #expect(try Data(contentsOf: paths.keys) == keysBefore)
        #expect(try Set(VaultFixtures.files(in: paths.directory).keys) == namesBefore)
        #expect(try cancellingBackups.localBackups().count == backupCount)
    }

    /// A device slot that the device key takes for its own but cannot open after all (a repaired Mac, a damaged slot)
    /// leaves the recovery code to open the backup.
    @Test func aRestoreWhoseDeviceSlotCannotBeOpenedFallsBackToTheCode() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, backups) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(1))
        let older = try await backups.makeBackup(
            database: fresh.database, key: try #require(vault.dataKey), keys: try #require(vault.keys)
        )
        try await fresh.database.saveInvoice(VaultFixtures.invoice(2))
        clock.advance(by: 60)
        let new = try await VaultFixtures.newCode(vault)
        await fresh.database.close()
        let (repaired, _) = VaultFixtures.vault(
            paths, device: FailingProtector(error: .deviceKeyUnusable), clock: clock
        )
        _ = try await repaired.unlockWithRecoveryCode(new.code)
        #expect(await repaired.canOpenWithDevice(try repaired.inspectBackup(older.url)))

        await #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try await repaired.restore(from: older.url, recoveryCode: nil)
        }
        await #expect(throws: KeyError.wrongRecoveryCode) {
            _ = try await repaired.restore(from: older.url, recoveryCode: new.code)
        }
        let restored = try await repaired.restore(from: older.url, recoveryCode: fresh.code)

        #expect(try await restored.invoiceCount() == 1)
    }

    /// The backup made just before a restore never removes the backup being restored, even when that is the oldest of
    /// those the folder keeps.
    @Test func aRestoreOfTheOldestBackupKeptKeepsItsFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, backups) = VaultFixtures.vault(paths, clock: clock, keep: 3)
        let fresh = try await VaultFixtures.startFresh(vault)
        var made: [URL] = []
        for number in 1...3 {
            try await fresh.database.saveInvoice(VaultFixtures.invoice(number))
            let backup = try await backups.makeBackup(
                database: fresh.database, key: try #require(vault.dataKey), keys: try #require(vault.keys)
            )
            made.append(backup.url)
            clock.advance(by: 60)
        }
        let oldest = try #require(made.first)
        let bytes = try Data(contentsOf: oldest)

        let restored = try await vault.restore(from: oldest, recoveryCode: nil)

        #expect(try await restored.invoiceCount() == 1)
        #expect(try Data(contentsOf: oldest) == bytes)
        #expect(try backups.localBackups().count == 4)
    }

    /// A crash at any moment after the data that was there has been backed up leaves data that the device opens: the
    /// data from before until the database file is replaced, the restored data from then on.
    @Test(arguments: [VaultStep.restoreKeySetsSaved, .databaseReplaced, .restoredKeysSettled])
    func aRestoreCutOffByACrashStillOpensWithTheDevice(at step: VaultStep) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (other, otherBackups) = VaultFixtures.vault(
            VaultFixtures.paths("Other Mac", in: directory), device: OtherMacProtector(), clock: clock
        )
        let otherFresh = try await VaultFixtures.startFresh(other)
        try await otherFresh.database.saveInvoice(VaultFixtures.invoice(1))
        try await otherFresh.database.saveInvoice(VaultFixtures.invoice(2))
        let backup = try await otherBackups.makeBackup(
            database: otherFresh.database, key: try #require(other.dataKey), keys: try #require(other.keys)
        )
        let paths = VaultFixtures.paths("Data", in: directory)
        let crashed = VaultFixtures.paths("After the crash", in: directory)
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(7))
        let ownKey = try #require(vault.dataKey)
        var reached: [VaultStep] = []
        vault.stepObserver = { current in
            reached.append(current)
            guard current == step else { return }
            do {
                try VaultFixtures.copyData(of: paths, to: crashed.directory)
            } catch {
                Issue.record(error)
            }
        }

        _ = try await vault.restore(from: backup.url, recoveryCode: otherFresh.code)

        #expect(reached == [.restoreKeySetsSaved, .databaseReplaced, .restoredKeysSettled])
        let replaced = step != .restoreKeySetsSaved
        let (relaunched, _) = VaultFixtures.vault(crashed, clock: clock)
        let database = try await relaunched.unlockWithDevice(reason: VaultFixtures.reason)
        #expect(try await database.invoiceCount() == (replaced ? 2 : 1))
        #expect(relaunched.dataKey == (replaced ? other.dataKey : ownKey))
        #expect(try VaultFixtures.keysFile(crashed).previous == nil)
    }

    /// When the database file cannot be replaced, the data stays locked, and its keys file, which holds the slots of
    /// both keys, opens the data that is still there. A restore after that removes what the failed one left behind.
    @Test func aRestoreWhoseDatabaseCannotBeReplacedLeavesTheDataThatWasThere() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (other, otherBackups) = VaultFixtures.vault(
            VaultFixtures.paths("Other Mac", in: directory), device: OtherMacProtector(), clock: clock
        )
        let otherFresh = try await VaultFixtures.startFresh(other)
        try await otherFresh.database.saveInvoice(VaultFixtures.invoice(1))
        try await otherFresh.database.saveInvoice(VaultFixtures.invoice(2))
        let backup = try await otherBackups.makeBackup(
            database: otherFresh.database, key: try #require(other.dataKey), keys: try #require(other.keys)
        )
        let paths = VaultFixtures.paths("Data", in: directory)
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(7))
        let ownKey = try #require(vault.dataKey)
        vault.stepObserver = { step in
            guard step == .restoreKeySetsSaved else { return }
            do {
                try VaultFixtures.setPermissions(0o555, on: paths.directory)
            } catch {
                Issue.record(error)
            }
        }
        defer { try? VaultFixtures.setPermissions(0o755, on: paths.directory) }

        await #expect(throws: (any Error).self) {
            _ = try await vault.restore(from: backup.url, recoveryCode: otherFresh.code)
        }

        try VaultFixtures.setPermissions(0o755, on: paths.directory)
        #expect(vault.database == nil)
        #expect(vault.dataKey == nil)
        #expect(try VaultFixtures.keysFile(paths).previous != nil)
        let (relaunched, _) = VaultFixtures.vault(paths, clock: clock)
        #expect(try await relaunched.unlockWithDevice(reason: VaultFixtures.reason).invoiceCount() == 1)
        #expect(relaunched.dataKey == ownKey)
        #expect(try VaultFixtures.keysFile(paths).previous == nil)

        let restored = try await relaunched.restore(from: backup.url, recoveryCode: otherFresh.code)

        #expect(try await restored.invoiceCount() == 2)
        #expect(try Set(VaultFixtures.files(in: paths.directory).keys).isSubset(of: VaultFixtures.dataFileNames))
    }

    /// While the data is locked, a restore that cannot put its database in place puts back the data it set aside.
    @Test func aRestoreOverLockedDataThatCannotReplaceTheDatabasePutsThatDataBack() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (other, otherBackups) = VaultFixtures.vault(
            VaultFixtures.paths("Other Mac", in: directory), device: OtherMacProtector(), clock: clock
        )
        let otherFresh = try await VaultFixtures.startFresh(other)
        let backup = try await otherBackups.makeBackup(
            database: otherFresh.database, key: try #require(other.dataKey), keys: try #require(other.keys)
        )
        let paths = VaultFixtures.paths("Data", in: directory)
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(7))
        await fresh.database.close()
        let before = try VaultFixtures.files(in: paths.directory)
        let (newMac, _) = VaultFixtures.vault(
            paths, device: FailingProtector(error: .deviceKeyUnusable), clock: clock
        )
        newMac.stepObserver = { step in
            guard step == .restoreKeySetsSaved else { return }
            // The extracted database, the only hidden file there, goes missing.
            do {
                let folder = paths.directory
                for name in try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
                where name.hasPrefix(".") {
                    try FileManager.default.removeItem(at: folder.appending(path: name))
                }
            } catch {
                Issue.record(error)
            }
        }

        await #expect(throws: (any Error).self) {
            _ = try await newMac.restore(from: backup.url, recoveryCode: otherFresh.code)
        }

        #expect(try VaultFixtures.files(in: paths.directory) == before)
        #expect(try VaultFixtures.setAsideFolders(in: paths.directory).isEmpty)
        #expect(newMac.database == nil)
        #expect(newMac.launchState() == .existing)
    }

    /// On a Mac that cannot open the data and without its code, a restore keeps that data: the files are set aside as
    /// they are, still encrypted.
    @Test func aRestoreOverDataThisMacCannotOpenSetsThatDataAside() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (other, otherBackups) = VaultFixtures.vault(
            VaultFixtures.paths("Other Mac", in: directory), device: OtherMacProtector(), clock: clock
        )
        let otherFresh = try await VaultFixtures.startFresh(other)
        try await otherFresh.database.saveInvoice(VaultFixtures.invoice(1))
        let backup = try await otherBackups.makeBackup(
            database: otherFresh.database, key: try #require(other.dataKey), keys: try #require(other.keys)
        )
        let paths = VaultFixtures.paths("Data", in: directory)
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let fresh = try await VaultFixtures.startFresh(vault)
        try await fresh.database.saveInvoice(VaultFixtures.invoice(7))
        await fresh.database.close()
        let before = try VaultFixtures.files(in: paths.directory)
        clock.advance(by: 65)

        let (newMac, newMacBackups) = VaultFixtures.vault(
            paths, device: FailingProtector(error: .deviceKeyUnusable), clock: clock
        )
        await #expect(throws: KeyError.deviceKeyUnusable) {
            _ = try await newMac.unlockWithDevice(reason: VaultFixtures.reason)
        }
        #expect(await newMac.canOpenWithDevice(try newMac.inspectBackup(backup.url)) == false)
        let restored = try await newMac.restore(from: backup.url, recoveryCode: otherFresh.code)

        #expect(try await restored.invoiceCount() == 1)
        #expect(try await restored.invoice(numberDigits: "20260901", currency: .czk) != nil)
        #expect(try VaultFixtures.keysFile(paths).recoverySlots == other.keys?.recoverySlots)
        #expect(try VaultFixtures.setAsideFolders(in: paths.directory) == ["Set aside 2026-10-18 12-01-05"])
        let aside = paths.directory.appending(path: "Set aside 2026-10-18 12-01-05")
        #expect(try VaultFixtures.files(in: aside) == before)
        // Nothing could back up the data that was there.
        #expect(try newMacBackups.localBackups().isEmpty)
        // The data set aside still opens with its own code.
        let keptKeys = try #require(try KeyManager.load(aside.appending(path: "InvoicesTracker.keys")))
        let keptKey = try KeyManager.unlock(keptKeys, recoveryCode: fresh.code).dek
        let kept = try Database(fileURL: aside.appending(path: "InvoicesTracker.sqlite"), key: keptKey)
        #expect(try await kept.invoiceCount() == 1)
    }

    @Test func startingFreshOverDataThisMacCannotOpenSetsThatDataAside() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        let first = try await VaultFixtures.startFresh(vault)
        try await first.database.saveInvoice(VaultFixtures.invoice(1))
        await first.database.close()
        let before = try VaultFixtures.files(in: paths.directory)
        clock.advance(by: 30)

        let (newMac, _) = VaultFixtures.vault(
            paths, device: FailingProtector(error: .deviceKeyUnusable), clock: clock
        )
        let fresh = try await VaultFixtures.startFresh(newMac)

        #expect(try await fresh.database.invoiceCount() == 0)
        #expect(fresh.code != first.code)
        #expect(newMac.launchState() == .existing)
        #expect(try VaultFixtures.setAsideFolders(in: paths.directory) == ["Set aside 2026-10-18 12-00-30"])
        #expect(try VaultFixtures.files(in: paths.directory.appending(path: "Set aside 2026-10-18 12-00-30")) == before)
    }

    /// A file of the data that cannot be moved stops a fresh start before anything is made, and what was moved goes
    /// back.
    @Test func startingFreshOverDataThatCannotBeSetAsideChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        let paths = VaultFixtures.paths("Data", in: directory)
        defer {
            try? FileManager.default.setAttributes(
                [.immutable: false], ofItemAtPath: paths.keys.path(percentEncoded: false)
            )
            removeTemporaryDirectory(directory)
        }
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        try await VaultFixtures.startFresh(vault).database.close()
        let before = try VaultFixtures.files(in: paths.directory)
        // Not even its owner can move a file that has the "user immutable" flag. The database is moved first.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: paths.keys.path(percentEncoded: false))

        let (newMac, _) = VaultFixtures.vault(
            paths, device: FailingProtector(error: .deviceKeyUnusable), clock: clock
        )
        await #expect(throws: (any Error).self) {
            _ = try await VaultFixtures.startFresh(newMac)
        }

        #expect(try VaultFixtures.files(in: paths.directory) == before)
        #expect(try VaultFixtures.setAsideFolders(in: paths.directory).isEmpty)
        #expect(newMac.database == nil)
    }

    // MARK: Damaged data and steps out of turn

    @Test func aDatabaseWithoutItsKeysKeysWithoutTheirDatabaseAndAnUnreadableKeysFileAreDamaged() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let clock = ManualClock(VaultFixtures.noon(2026, 10, 18))
        let (vault, _) = VaultFixtures.vault(paths, clock: clock)
        try await VaultFixtures.startFresh(vault).database.close()
        let keys = try Data(contentsOf: paths.keys)
        let database = try Data(contentsOf: paths.database)
        let (relaunched, _) = VaultFixtures.vault(paths, clock: clock)

        try FileManager.default.removeItem(at: paths.keys)
        #expect(relaunched.launchState() == .damaged("Chybí soubor s klíči k datům."))
        #expect(relaunched.requiredRecoveryLabel == nil)
        await #expect(throws: VaultError.noData) {
            _ = try await relaunched.unlockWithDevice(reason: VaultFixtures.reason)
        }

        try keys.write(to: paths.keys)
        try FileManager.default.removeItem(at: paths.database)
        #expect(relaunched.launchState() == .damaged("Chybí databáze."))
        await #expect(throws: VaultError.noData) {
            _ = try await relaunched.unlockWithDevice(reason: VaultFixtures.reason)
        }
        // Trying did not create a database.
        #expect(!FileManager.default.fileExists(atPath: paths.database.path(percentEncoded: false)))

        try database.write(to: paths.database)
        try Data("{".utf8).write(to: paths.keys)
        #expect(relaunched.launchState() == .damaged("Soubor s klíči je poškozený."))
        await #expect(throws: KeyError.keysFileDamaged) {
            _ = try await relaunched.unlockWithDevice(reason: VaultFixtures.reason)
        }
    }

    @Test func aStepThatNeedsTheDataLockedOrOpenRefusesTheOtherState() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let (vault, _) = VaultFixtures.vault(paths, clock: ManualClock(VaultFixtures.noon(2026, 10, 18)))

        await #expect(throws: VaultError.noData) {
            _ = try await vault.unlockWithDevice(reason: VaultFixtures.reason)
        }
        await #expect(throws: VaultError.noData) {
            _ = try await vault.unlockWithRecoveryCode(VaultFixtures.strangerCode)
        }
        #expect(throws: VaultError.locked) {
            _ = try vault.prepareNewRecoveryCode()
        }
        await #expect(throws: VaultError.locked) {
            try await vault.setTouchID(false)
        }
        #expect(vault.launchState() == .firstLaunch)

        let pending = try vault.prepareFreshStart()
        let fresh = try await vault.startFresh(pending, touchID: true)

        #expect(throws: VaultError.alreadyOpen) {
            _ = try vault.prepareFreshStart()
        }
        await #expect(throws: VaultError.alreadyOpen) {
            _ = try await vault.startFresh(pending, touchID: true)
        }
        await #expect(throws: VaultError.alreadyOpen) {
            _ = try await vault.unlockWithDevice(reason: VaultFixtures.reason)
        }
        await #expect(throws: VaultError.alreadyOpen) {
            _ = try await vault.unlockWithRecoveryCode(pending.code)
        }
        #expect(vault.database === fresh)
        // A code made while the data is open is not put in force by a vault where it is locked.
        let code = try vault.prepareNewRecoveryCode()
        let (locked, _) = VaultFixtures.vault(paths, clock: ManualClock(VaultFixtures.noon(2026, 10, 18)))
        let keysBefore = try Data(contentsOf: paths.keys)
        await #expect(throws: VaultError.locked) {
            _ = try await locked.commitNewRecoveryCode(code)
        }
        #expect(try Data(contentsOf: paths.keys) == keysBefore)
    }

    /// The steps that change something wait for the database and the disk, and one started meanwhile could write a keys
    /// file that does not fit the database, so it is refused.
    @Test func aChangeStartedWhileAnotherIsRunningIsRefused() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let paths = VaultFixtures.paths("Data", in: directory)
        let (vault, _) = VaultFixtures.vault(paths, clock: ManualClock(VaultFixtures.noon(2026, 10, 18)))
        _ = try await VaultFixtures.startFresh(vault)
        var interloper: Task<Void, any Error>?
        vault.stepObserver = { step in
            guard step == .bothKeySetsSaved, interloper == nil else { return }
            interloper = Task { _ = try await vault.setTouchID(false) }
        }

        let new = try await VaultFixtures.newCode(vault)

        let outcome = try #require(await interloper?.result)
        #expect(throws: VaultError.busy) {
            try outcome.get()
        }
        let keys = try VaultFixtures.keysFile(paths)
        #expect(keys.deviceSlot?.userPresence == true)
        #expect(try KeyManager.unlock(keys, recoveryCode: new.code).dek == vault.dataKey)
        // Once it is over, the next one runs.
        _ = try await vault.setTouchID(false)
        #expect(try VaultFixtures.keysFile(paths).deviceSlot?.userPresence == false)
    }
}

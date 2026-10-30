import Foundation
import Testing
@testable import InvoicesTracker

/// The app model while the data is open: a restore of a backup in its place, a new recovery code that fails half way,
/// the backups made at once, exported and outside the Mac, and the bookkeeping of the local backups. Every test has its
/// own folder, a software key protector stands in for the Secure Enclave, the clock is at noon of 17 October 2026 in
/// the Mac's time zone, and nothing reaches the network.
@Suite(.settlesBackups)
@MainActor
struct AppModelRestoreTests {
    /// A well-formed recovery code that opens no slot.
    private let strangerCode = "7777-7777-7777-7777-7777-7777-7777-7777"

    // MARK: Restoring while the data is open

    @Test func aRestoreReplacesTheOpenDataAndOpensTheRestoredDataLikeAnUnlock() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = try await makeSettingsApp(in: directory, clock: clock)
        let before = try #require(app.database)
        try await before.saveInvoice(Invoice.fixture())
        await app.didWriteAndBackUp()
        let backup = try #require(try app.backups.localBackups().first)
        try await before.saveInvoice(Invoice.fixture(number: "20260902"))
        await app.didWriteAndBackUp()
        clock.advance(by: 60)
        let refreshBefore = try #require(app.refresh)
        app.screen = .settings
        let version = app.dataVersion

        let outcome = try await app.restoreWhileOpen(from: backup.url, recoveryCode: nil)

        let restored = try #require(app.database)
        #expect(restored !== before)
        #expect(app.vault.database === restored)
        #expect(try await restored.invoiceCount() == 1)
        #expect(app.phase == .ready)
        #expect(app.completion == nil)
        #expect(app.screen == .settings)
        #expect(app.dataVersion > version)
        let refreshAfter = try #require(app.refresh)
        #expect(refreshAfter !== refreshBefore)
        #expect(
            outcome
                == RestoreOutcome(
                    codeLabel: "kód č. 1 z 17.\u{00A0}10.\u{00A0}2026", codeChanged: false, backupHadAnotherFolder: false))
        // The data that was open is in a backup of its own, the only one with both invoices.
        #expect(try app.backups.localBackups().contains { $0.header.invoiceCount == 2 })
    }

    @Test func aRestoreForgetsTheUniformRateTheReminderTheSheetAndTheImportOfTheDataItReplaces() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = try await makeSettingsApp(in: directory, clock: clock)
        try await #require(app.database).saveInvoice(Invoice.fixture())
        await app.didWriteAndBackUp()
        let backup = try #require(try app.backups.localBackups().first)
        clock.advance(by: 60)
        try await #require(app.database).execute("DELETE FROM uniform_rate WHERE year = 2025")
        await app.offerUniformRate(try gfrFinding2025())
        #expect(app.pendingUniformRate != nil && app.uniformRateOffer != nil)
        app.refresh?.onUniformRateReminder?(2026)
        let importModel = app.importModel

        _ = try await app.restoreWhileOpen(from: backup.url, recoveryCode: nil)

        #expect(app.pendingUniformRate == nil)
        #expect(app.uniformRateOffer == nil)
        #expect(app.uniformRateReminderYear == nil)
        #expect(app.importModel !== importModel)
    }

    @Test func aRestoreOfABackupOfAnotherMacNamesTheCodeThatOpensTheDataNow() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let other = try await makeBackupOfAnotherMac(in: directory, invoices: 2)
        let app = try await makeSettingsApp(in: directory)

        let outcome = try await app.restoreWhileOpen(from: other.url, recoveryCode: other.code)

        #expect(outcome == RestoreOutcome(codeLabel: other.label, codeChanged: true, backupHadAnotherFolder: false))
        #expect(try await #require(app.database).invoiceCount() == 2)
        // This Mac opens the restored data with its own device key from now on.
        await app.database?.close()
        let relaunched = makeAppModel(in: directory)
        await relaunched.launch()
        #expect(relaunched.phase == .ready)
        #expect(try await #require(relaunched.database).invoiceCount() == 2)
    }

    @Test(.hangGuard)
    func aRestoreThatFailsBeforeAnythingChangedLeavesTheDataOpenAndRunningAsBefore() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let other = try await makeBackupOfAnotherMac(in: directory, invoices: 2)
        let scheduler = ManualScheduler()
        let app = try await makeSettingsApp(in: directory, scheduler: scheduler, startsRefresh: true)
        let before = try #require(app.database)
        let refresh = try #require(app.refresh)
        await scheduler.untilAWakeIsAsked()

        await #expect(throws: KeyError.wrongRecoveryCode) {
            try await app.restoreWhileOpen(from: other.url, recoveryCode: strangerCode)
        }

        #expect(app.database === before)
        #expect(app.vault.database === before)
        #expect(app.phase == .ready)
        #expect(app.refresh === refresh)
        #expect(refresh.isStarted)
        #expect(try await before.invoiceCount() == 0)
        refresh.stop()
    }

    @Test func aRestoreThatFailsAfterTheVaultLockedTheDataLocksTheApp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let other = try await makeBackupOfAnotherMac(in: directory, invoices: 2)
        let app = try await makeSettingsApp(in: directory)
        try await #require(app.database).saveInvoice(Invoice.fixture())
        let folder = app.vault.paths.directory
        app.vault.stepObserver = { step in
            guard step == .restoreKeySetsSaved else { return }
            do {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))
            } catch {
                Issue.record(error)
            }
        }
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
        }

        await #expect(throws: (any Error).self) {
            try await app.restoreWhileOpen(from: other.url, recoveryCode: other.code)
        }

        #expect(app.phase == .locked)
        #expect(app.database == nil)
        #expect(app.refresh == nil)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
        app.vault.stepObserver = nil
        app.screen = .overview
        // Unlocking opens the data that was there, and Nastavení says so.
        await app.unlockWithDevice()
        #expect(app.phase == .ready)
        #expect(try await #require(app.database).invoiceCount() == 1)
        #expect(
            app.securityNotice
                == "Obnovení ze zálohy „\(other.url.lastPathComponent)“ se nepodařilo dokončit. Otevřená jsou data jako"
                + " před obnovením a otevírá je kód č. 1 z 17.\u{00A0}10.\u{00A0}2026.")
        #expect(app.screen == .settings)
        #expect(app.settingsTab == .security)
    }

    @Test func aRestoreKeepsTheFolderOutsideTheMacOfThisMac() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let other = try await makeBackupOfAnotherMac(in: directory, invoices: 1)
        let app = try await makeSettingsApp(in: directory)
        let folder = directory.appending(path: "Disk", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(try await app.setBackupFolder(folder))
        let before = app.appSettings

        let outcome = try await app.restoreWhileOpen(from: other.url, recoveryCode: other.code)

        #expect(!outcome.backupHadAnotherFolder)
        let stored = try await #require(app.database).appSettings()
        for settings in [app.appSettings, stored] {
            #expect(settings.backupFolderBookmark == before.backupFolderBookmark)
            #expect(settings.backupFolderName == before.backupFolderName)
            #expect(settings.lastOffMacBackup == before.lastOffMacBackup)
        }
        #expect(try await #require(app.database).invoiceCount() == 1)
    }

    @Test func aRestoreClosesTheInvoiceEditorFirst() async throws {
        try await EditorFixture.with { f in
            f.app.startNewInvoice(templateID: f.crownTemplate.id)
            await f.app.openEditor()
            #expect(f.app.editor != nil)
            let backup = try #require(try f.app.backups.localBackups().first)

            _ = try await f.app.restoreWhileOpen(from: backup.url, recoveryCode: nil)

            #expect(f.app.editorRequest == nil)
            #expect(f.app.editor == nil)
        }
    }

    // MARK: A new recovery code

    @Test func aNewCodeWhoseRekeyFailsLocksTheAppAndUnlockingOpensTheDataWithTheOldCode() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        try await #require(app.database).saveInvoice(Invoice.fixture())
        let oldKey = try #require(app.vault.dataKey)
        let path = app.vault.paths.database.path(percentEncoded: false)
        var writer: SQLiteConnection?
        app.vault.stepObserver = { step in
            guard step == .bothKeySetsSaved else { return }
            // Another connection holds the lock for writing, so the rekey cannot begin.
            do {
                let connection = try SQLiteConnection(path: path, key: oldKey)
                try connection.execute("BEGIN IMMEDIATE")
                writer = connection
            } catch {
                Issue.record(error)
            }
        }
        let pending = try app.vault.prepareNewRecoveryCode()

        await #expect(throws: SQLiteError.self) {
            _ = try await app.commitNewRecoveryCode(pending)
        }

        try writer?.execute("ROLLBACK")
        writer?.close()
        app.vault.stepObserver = nil
        #expect(app.phase == .locked)
        #expect(app.database == nil)
        #expect(app.refresh == nil)
        await app.unlockWithDevice()
        #expect(app.phase == .ready)
        #expect(try await #require(app.database).invoiceCount() == 1)
        #expect(app.vault.keys?.newestRecoverySlot?.number == 1)
        #expect(
            app.securityNotice
                == "Nový kód č. 2 se nepodařilo použít – platí dál kód č. 1 z 17.\u{00A0}10.\u{00A0}2026. Nový kód"
                + " zahoďte.")
        #expect(app.screen == .settings)
        #expect(app.settingsTab == .security)
    }

    @Test func aNewCodeWhoseCheckFailsAfterTheRekeySaysAfterTheUnlockThatItIsInForce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        try await #require(app.database).saveInvoice(Invoice.fixture())
        let file = app.vault.paths.database.path(percentEncoded: false)
        app.vault.stepObserver = { step in
            guard step == .databaseRekeyed else { return }
            // The file cannot be opened on a connection of its own, so the new key cannot be confirmed.
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file)
            } catch {
                Issue.record(error)
            }
        }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file) }
        let pending = try app.vault.prepareNewRecoveryCode()

        await #expect(throws: (any Error).self) {
            _ = try await app.commitNewRecoveryCode(pending)
        }

        #expect(app.phase == .locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file)
        app.vault.stepObserver = nil
        await app.unlockWithDevice()
        #expect(app.phase == .ready)
        #expect(app.vault.keys?.newestRecoverySlot?.number == 2)
        #expect(
            app.securityNotice
                == "Nový kód č. 2 z 17.\u{00A0}10.\u{00A0}2026 platí. Záloha s novým klíčem se ale neuložila –"
                + " zálohujte data tlačítkem Zálohovat teď.")
    }

    @Test func aKeyChangeTellsOfTheBackupOutsideTheMacOnlyWhenAFolderIsSet() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)

        let withoutFolder = try await app.setTouchID(false)

        #expect(withoutFolder == KeyChangeResult(outcome: KeyChangeOutcome(backupMade: true), offMacBackupMade: nil))
        let folder = directory.appending(path: "Disk", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(try await app.setBackupFolder(folder))
        let withFolder = try await app.commitNewRecoveryCode(try app.vault.prepareNewRecoveryCode())
        #expect(withFolder.offMacBackupMade == true)
        #expect(withFolder.outcome.backupMade)
    }

    // MARK: Backups made at once

    @Test func backingUpNowMakesTheLocalBackupWhateverTheHourAndRecordsIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeSettingsApp(in: directory, clock: clock, scheduler: scheduler)
        await app.didWriteAndBackUp()
        clock.advance(by: 10 * 60)
        await app.didWriteAndBackUp()
        #expect(scheduler.armed == [localNoon(2026, 10, 17) + 60 * 60])

        let outcome = try await app.backUpNow()

        #expect(outcome == BackupNowOutcome(created: localNoon(2026, 10, 17) + 10 * 60, offMac: nil))
        #expect(try app.backups.localBackups().count == 2)
        #expect(app.appSettings.lastLocalBackup == localNoon(2026, 10, 17) + 10 * 60)
        #expect(app.appSettings.localBackupPendingSince == nil)
        #expect(scheduler.armed.isEmpty)
    }

    @Test func backingUpNowSaysWhenTheFolderOutsideTheMacCannotBeReached() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let folder = directory.appending(path: "Disk", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let made = try await app.setBackupFolder(folder)
        #expect(made)
        // The folder can be read but not written, as a disk that is full or a share without the right to write.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
        }

        let outcome = try await app.backUpNow()

        #expect(outcome.offMac == false)
        #expect(try app.backups.localBackups().count == 1)
    }

    @Test func aBackupOutsideTheMacAfterAKeyChangeWaitsForTheOneRunningAndMakesAFreshOne() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = try await makeSettingsApp(in: directory, clock: clock)
        let folder = directory.appending(path: "Disk", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(try await app.setBackupFolder(folder))
        // A day later the daily backup is due, and runs.
        clock.advance(by: 24 * 60 * 60)
        let daily = Task.immediate { await app.backUpOffMacIfDue() }

        let made = await app.backUpOffMac(afterTheRunningOne: true)

        await daily.value
        #expect(made)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names.filter { $0.hasSuffix(".ttbackup") }.count == 3)
    }

    @Test(.hangGuard)
    func aBackupOutsideTheMacDoesNotWaitForEverForOneThatNeverEnds() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let limit = LimitSwitch()
        let app = try await makeSettingsApp(in: directory, sleep: limit.wait)
        let folder = directory.appending(path: "Disk", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(try await app.setBackupFolder(folder))
        let backupsBefore = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            .filter { $0.hasSuffix(".ttbackup") }.count
        // A backup that has run for ever, as one to a share that does not answer, and a limit that has run out.
        let gate = Gate()
        app.offMacBackupRun = Task {
            await gate.pass()
            return true
        }
        limit.runOut()

        let made = await app.backUpOffMac(afterTheRunningOne: true)

        // It gave up waiting for that one, said that no backup was made, and made none of its own.
        #expect(made == false)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names.filter { $0.hasSuffix(".ttbackup") }.count == backupsBefore)
        await gate.open()
    }

    @Test(.hangGuard)
    func aChangeOfTheKeysIsNotHeldUpForEverByABackupOutsideTheMacThatNeverEnds() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let limit = LimitSwitch()
        let app = try await makeSettingsApp(in: directory, sleep: limit.wait)
        let folder = directory.appending(path: "Disk", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(try await app.setBackupFolder(folder))
        let gate = Gate()
        app.offMacBackupRun = Task {
            await gate.pass()
            return true
        }
        limit.runOut()

        let result = try await app.setTouchID(false)

        // The change is made, the backup that follows it says that the one outside the Mac was not made, and the app
        // is free for the next step.
        #expect(result.offMacBackupMade == false)
        #expect(!app.securityStepRunning)
        await gate.open()
    }

    @Test(.hangGuard)
    func aBackupOutsideTheMacThatTakesLongerThanTheLimitIsNotWaitedForAndGoesOn() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let limit = LimitSwitch()
        let app = try await makeSettingsApp(in: directory, sleep: limit.wait)
        let folder = directory.appending(path: "Disk", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(try await app.setBackupFolder(folder))
        let backups = {
            try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
                .filter { $0.hasSuffix(".ttbackup") }.count
        }
        let before = try backups()
        limit.runOut()

        // The limit has run out as soon as the backup starts, so it is not waited for.
        let made = await app.backUpOffMac()

        #expect(made == false)
        // The backup itself is not stopped: it ends in its own time, and the app is free for the next one.
        try await waitUntil {
            let made = try backups()
            return app.offMacBackupRun == nil && made == before + 1
        }
    }

    @Test func anExportNeverPrunesTheFolderItIsWrittenTo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let folder = directory.appending(path: "Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Files named as the app names its own backups, which a pruning would count.
        for second in 0..<3 {
            try Data("x".utf8).write(to: folder.appending(path: "InvoicesTracker 2026-10-01 10-00-0\(second).ttbackup"))
        }

        try await app.exportBackup(to: folder.appending(path: "InvoicesTracker 2026-10-17.ttbackup"))

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names.count == 4)
        #expect(names.contains("InvoicesTracker 2026-10-17.ttbackup"))
    }

    // MARK: The bookkeeping of the local backups

    @Test func aBackupOfDataThatWasReplacedMeanwhileIsNotRecordedForTheDataOpenNow() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        await app.didWriteAndBackUp()
        let recorded = app.appSettings.lastLocalBackup
        let (replaced, replacedDirectory) = try makeDatabase()
        defer { removeTemporaryDirectory(replacedDirectory) }
        let folder = directory.appending(path: "Disk", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(try await app.setBackupFolder(folder))
        let recordedOffMac = app.appSettings.lastOffMacBackup
        let stale = BackupResult(
            url: replacedDirectory.appending(path: "InvoicesTracker 2026-10-17 13-00-00.ttbackup"),
            created: localNoon(2026, 10, 17) + 60 * 60, cleanupError: nil)

        await app.recordLocalBackup(stale, of: replaced, changesBefore: app.changeCount)
        await app.recordOffMacBackup(stale, of: replaced, into: try #require(app.appSettings.backupFolderBookmark))

        #expect(app.appSettings.lastLocalBackup == recorded)
        #expect(app.appSettings.lastOffMacBackup == recordedOffMac)
        #expect(try await #require(app.database).appSettings().lastLocalBackup == recorded)
        await replaced.close()
    }

    @Test func aBackupOutsideTheMacThatEndsAfterAnotherFolderWasChosenIsNotTheNewFoldersBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = try await makeSettingsApp(in: directory, clock: clock)
        let first = directory.appending(path: "Disk", directoryHint: .isDirectory)
        let second = directory.appending(path: "Other disk", directoryHint: .isDirectory)
        for folder in [first, second] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        #expect(try await app.setBackupFolder(first))
        let firstBookmark = try #require(app.appSettings.backupFolderBookmark)
        clock.advance(by: 60 * 60)
        #expect(try await app.setBackupFolder(second))
        let recorded = app.appSettings.lastOffMacBackup
        // The backup that was made in the first folder ends only now.
        let late = BackupResult(
            url: first.appending(path: "InvoicesTracker 2026-10-17 14-00-00.ttbackup"),
            created: localNoon(2026, 10, 17) + 2 * 60 * 60, cleanupError: nil)

        let made = await app.recordOffMacBackup(late, of: try #require(app.database), into: firstBookmark)

        #expect(!made)
        #expect(app.appSettings.lastOffMacBackup == recorded)
        #expect(try await #require(app.database).appSettings().lastOffMacBackup == recorded)
    }

    @Test func aLastBackupLaterThanNowIsOneOfAClockThatWasSetBackAndTheBackupIsDue() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let scheduler = ManualScheduler()
        let app = try await makeSettingsApp(in: directory, clock: clock, scheduler: scheduler)
        await app.didWriteAndBackUp()
        #expect(try app.backups.localBackups().count == 1)

        // The clock goes back by two hours, and a change comes.
        clock.advance(by: -2 * 60 * 60)
        await app.didWriteAndBackUp()

        #expect(try app.backups.localBackups().count == 2)
        #expect(app.appSettings.lastLocalBackup == localNoon(2026, 10, 17) - 2 * 60 * 60)
        #expect(scheduler.armed.isEmpty)
    }

    // MARK: Nastavení from the menu

    @Test func theMenuCommandsOfTheBackupsOpenZabezpeceniAZalohy() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        app.showSettings(.application)
        app.showBanner("Kurzy ČNB jsou aktuální.")

        app.request(.restoreBackup)

        #expect(app.screen == .settings)
        #expect(app.settingsTab == .security)
        #expect(app.settingsAction == .restoreBackup)
        // Another tab closes the banner of the one before.
        #expect(app.banner == nil)
    }

    @Test func theMenuCommandsOfTheBackupsAskForNothingWhileAStepRuns() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        app.showSettings(.application)
        let backup = Task.immediate { try await app.backUpNow() }

        app.request(.restoreBackup)
        app.request(.exportBackup)

        #expect(app.settingsAction == nil)
        #expect(app.settingsTab == .application)
        _ = try await backup.value
        app.request(.exportBackup)
        #expect(app.settingsAction == .exportBackup)
    }
}

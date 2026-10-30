import Foundation
import Testing
@testable import InvoicesTracker

/// A new recovery code or a restore that failed after the vault had locked the data: the next unlock of the same data
/// says on Nastavení what it left in force; a retry that succeeds, any other change of the keys and any other data that
/// is opened take the notice away; a restore that had put its database in place keeps this Mac's folder of the backups
/// outside the Mac. A software key protector stands in for the Secure Enclave, the clock is at noon of 17 October 2026,
/// and nothing reaches the network. In every expected string `\u{00A0}` is the no-break space.
@Suite(.settlesBackups)
@MainActor
struct AppModelInterruptedChangeTests {
    private let firstCode = "kód č. 1 z 17.\u{00A0}10.\u{00A0}2026"

    /// An app whose new recovery code failed in its rekey and was unlocked again: Nastavení says that the old code is
    /// in force.
    private func appAfterAFailedNewCode(in directory: URL) async throws -> AppModel {
        let app = try await makeSettingsApp(in: directory)
        let trap = try VaultStepTrap.failingRekey(of: app)
        await #expect(throws: SQLiteError.self) {
            _ = try await app.commitNewRecoveryCode(try app.vault.prepareNewRecoveryCode())
        }
        trap.release()
        #expect(app.phase == .locked)
        await app.unlockWithDevice()
        #expect(app.securityNotice?.hasPrefix("Nový kód č. 2 se nepodařilo použít") == true)
        return app
    }

    // MARK: A retry takes the notice away

    @Test func aNewCodeThatSucceedsAfterOneThatFailedTakesTheNoticeAway() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await appAfterAFailedNewCode(in: directory)

        let result = try await app.commitNewRecoveryCode(try app.vault.prepareNewRecoveryCode())

        #expect(result.outcome.label == "kód č. 2 z 17.\u{00A0}10.\u{00A0}2026")
        #expect(app.securityNotice == nil)
    }

    @Test func aChangeOfTouchIDTakesTheNoticeAway() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await appAfterAFailedNewCode(in: directory)

        _ = try await app.setTouchID(false)

        #expect(app.securityNotice == nil)
    }

    @Test func aRestoreThatSucceedsAfterOneThatFailedTakesTheNoticeAway() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let other = try await makeBackupOfAnotherMac(in: directory, invoices: 2)
        let app = try await makeSettingsApp(in: directory)
        let trap = VaultStepTrap.failingRestoreBeforeTheSwap(of: app)
        defer { trap.release() }
        await #expect(throws: (any Error).self) {
            try await app.restoreWhileOpen(from: other.url, recoveryCode: other.code)
        }
        trap.release()
        await app.unlockWithDevice()
        #expect(app.securityNotice?.hasPrefix("Obnovení ze zálohy") == true)

        _ = try await app.restoreWhileOpen(from: other.url, recoveryCode: other.code)

        #expect(app.securityNotice == nil)
        #expect(try await #require(app.database).invoiceCount() == 2)
    }

    // MARK: Only an unlock of the same data tells

    @Test func dataRestoredAtTheWelcomeInsteadOfTheUnlockSayNothingOfTheChange() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let other = try await makeBackupOfAnotherMac(in: directory, invoices: 1)
        let app = try await makeSettingsApp(in: directory)
        let trap = try VaultStepTrap.failingRekey(of: app)
        await #expect(throws: SQLiteError.self) {
            _ = try await app.commitNewRecoveryCode(try app.vault.prepareNewRecoveryCode())
        }
        trap.release()
        #expect(app.interruptedChange != nil)
        app.useRecoveryCode()

        try await app.restoreAtWelcome(from: other.url, recoveryCode: other.code)

        #expect(app.phase == .ready)
        #expect(app.securityNotice == nil)
        #expect(app.interruptedChange == nil)
    }

    @Test func dataStartedEmptyInsteadOfTheUnlockSayNothingOfTheChange() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let trap = try VaultStepTrap.failingRekey(of: app)
        await #expect(throws: SQLiteError.self) {
            _ = try await app.commitNewRecoveryCode(try app.vault.prepareNewRecoveryCode())
        }
        trap.release()
        app.useRecoveryCode()

        try await app.startFresh()
        try await app.finishRecoveryCodeStep(touchID: true)

        #expect(app.database != nil)
        #expect(app.securityNotice == nil)
        #expect(app.interruptedChange == nil)
    }

    // MARK: What the unlock says and keeps

    @Test func aRestoreCutOffAfterItsDatabaseWasPutInPlaceIsToldAndKeepsThisMacsFolder() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let otherFolder = directory.appending(path: "Other disk", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        let other = try await makeBackupOfAnotherMac(in: directory, invoices: 2, folder: otherFolder)
        let app = try await makeSettingsApp(in: directory)
        let folder = directory.appending(path: "Disk", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(try await app.setBackupFolder(folder))
        let ours = app.appSettings
        let trap = VaultStepTrap.failingRestoreAfterTheSwap(of: app)
        defer { trap.release() }
        await #expect(throws: (any Error).self) {
            try await app.restoreWhileOpen(from: other.url, recoveryCode: other.code, title: "Záloha z jiného Macu")
        }
        #expect(app.phase == .locked)
        trap.release()

        await app.unlockWithDevice()

        #expect(app.phase == .ready)
        #expect(try await #require(app.database).invoiceCount() == 2)
        #expect(
            app.securityNotice
                == "Data jsou obnovená ze zálohy „Záloha z jiného Macu“, aplikace je ale mezitím zamkla. Otevírá je "
                + other.label + ".")
        let stored = try await #require(app.database).appSettings()
        for settings in [app.appSettings, stored] {
            #expect(settings.backupFolderBookmark == ours.backupFolderBookmark)
            #expect(settings.backupFolderName == ours.backupFolderName)
            #expect(settings.backupFolderChosen == ours.backupFolderChosen)
        }
    }

    @Test func aBackupMadeWithZalohovatTedTakesAwayTheNoticeThatNoBackupHoldsTheNewKey() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let trap = VaultStepTrap.failingCheckAfterTheRekey(of: app)
        defer { trap.release() }
        await #expect(throws: (any Error).self) {
            _ = try await app.commitNewRecoveryCode(try app.vault.prepareNewRecoveryCode())
        }
        trap.release()
        await app.unlockWithDevice()
        let notice = try #require(app.securityNotice)
        #expect(notice.hasSuffix("Záloha s novým klíčem se ale neuložila – zálohujte data tlačítkem Zálohovat teď."))

        _ = try await app.backUpNow()

        // The backup holds the new key now, so the notice is not true any more.
        #expect(app.securityNotice == nil)
    }

    @Test func aBackupMadeWithZalohovatTedLeavesTheNoticeOfARestoreAlone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let other = try await makeBackupOfAnotherMac(in: directory, invoices: 2)
        let app = try await makeSettingsApp(in: directory)
        let trap = VaultStepTrap.failingRestoreAfterTheSwap(of: app)
        defer { trap.release() }
        await #expect(throws: (any Error).self) {
            try await app.restoreWhileOpen(from: other.url, recoveryCode: other.code, title: "Záloha z jiného Macu")
        }
        trap.release()
        await app.unlockWithDevice()
        let notice = try #require(app.securityNotice)
        #expect(notice.hasPrefix("Data jsou obnovená ze zálohy „Záloha z jiného Macu“"))

        _ = try await app.backUpNow()

        // What the restore left in force is as true after a backup as before it.
        #expect(app.securityNotice == notice)
    }

    @Test func aNewCodeInForceAfterACheckThatFailedNamesTheCodeItReplaced() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        let trap = VaultStepTrap.failingCheckAfterTheRekey(of: app)
        defer { trap.release() }
        await #expect(throws: (any Error).self) {
            _ = try await app.commitNewRecoveryCode(try app.vault.prepareNewRecoveryCode())
        }
        trap.release()

        await app.unlockWithDevice()

        #expect(app.vault.keys?.newestRecoverySlot?.number == 2)
        #expect(app.securityNotice?.hasPrefix("Nový kód č. 2 z 17.\u{00A0}10.\u{00A0}2026 platí.") == true)
        #expect(app.appSettings.replacedRecoveryCodeLabel == firstCode)
        #expect(app.appSettings.replacedRecoveryCodeNumber == 1)
        #expect(try await #require(app.database).appSettings().replacedRecoveryCodeNumber == 1)
    }
}

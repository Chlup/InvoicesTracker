import Foundation
import Testing
@testable import InvoicesTracker

/// What the first-launch, locked and new-Mac screens need of the app model: the number and the day of the code that is
/// shown, the card after unlocking with the code or restoring a backup, and the way from the locked screen to the code.
/// Every test has its own folder, a software key protector stands in for the Secure Enclave, and the clock is at noon
/// of 17 October 2026 in the Mac's time zone.
@Suite(.settlesBackups)
@MainActor
struct AppModelWelcomeTests {
    /// A well-formed recovery code that opens no slot.
    private let strangerCode = "7777-7777-7777-7777-7777-7777-7777-7777"

    /// The label of the first code, made on the day of the clock.
    private let label = "kód č. 1 z 17.\u{00A0}10.\u{00A0}2026"

    /// Data that another Mac made and left in `directory`, and its code. Closed, so a model of the folder can open it.
    private func dataOfAnotherMac(in directory: URL) async throws -> String {
        let before = makeAppModel(in: directory)
        let code = try await startFresh(before)
        await before.database?.close()
        return code
    }

    // MARK: The code that is shown

    @Test func theCodeStepCarriesTheNumberAndTheDayOfTheCodeItShows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        await model.launch()

        try await model.startFresh()

        guard case .onboarding(.recoveryCode(let code, let shownLabel, let number, let created)) = model.phase else {
            Issue.record("The first step shows the recovery code, not \(model.phase).")
            return
        }
        #expect(code.count == 39)
        #expect(shownLabel == label)
        #expect(number == 1)
        #expect(created == civilDate("2026-10-17"))
        #expect(
            WelcomeTexts.codeCaption(number: number, created: created)
                == "Kód č. 1 · vytvořen 17.\u{00A0}10.\u{00A0}2026")
    }

    // MARK: Unlocking with the code

    @Test func unlockingWithTheCodeEndsInACardUntilItIsDismissed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let code = try await dataOfAnotherMac(in: directory)
        let model = makeAppModel(in: directory, device: ScriptedKeyProtector(openFailure: .deviceKeyUnusable))
        await model.launch()
        #expect(model.phase == .newMac)
        #expect(model.completion == nil)

        await #expect(throws: KeyError.wrongRecoveryCode) {
            try await model.unlock(recoveryCode: strangerCode)
        }

        // A code that does not fit changes nothing and shows no card.
        #expect(model.phase == .newMac)
        #expect(model.completion == nil)

        try await model.unlock(recoveryCode: code)

        #expect(model.phase == .ready)
        #expect(model.completion == UnlockCompletion(kind: .unlocked, codeLabel: label))

        model.dismissCompletion()

        #expect(model.completion == nil)
        #expect(model.phase == .ready)
    }

    @Test func aCodeTypedInLowerCaseWithSpacesInsteadOfDashesUnlocksTheData() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let code = try await dataOfAnotherMac(in: directory)
        let model = makeAppModel(in: directory, device: ScriptedKeyProtector(openFailure: .deviceKeyUnusable))
        await model.launch()

        try await model.unlock(recoveryCode: code.lowercased().replacing("-", with: " "))

        #expect(model.phase == .ready)
        #expect(model.completion?.kind == .unlocked)
    }

    @Test func anOrdinaryUnlockShowsNoCard() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        _ = try await dataOfAnotherMac(in: directory)
        let device = ScriptedKeyProtector(openFailure: .userCancelled)
        let model = makeAppModel(in: directory, device: device)

        await model.launch()
        #expect(model.phase == .locked)

        device.openFailure = nil
        await model.unlockWithDevice()

        #expect(model.phase == .ready)
        #expect(model.completion == nil)
    }

    @Test func aFreshStartShowsNoCard() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)

        try await startFresh(model)

        #expect(model.completion == nil)
    }

    // MARK: The locked screen

    @Test func theLockedScreenOpensTheCodeScreenOfANewMac() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let code = try await dataOfAnotherMac(in: directory)
        let model = makeAppModel(in: directory, device: ScriptedKeyProtector(openFailure: .userCancelled))
        await model.launch()
        #expect(model.phase == .locked)

        model.useRecoveryCode()

        #expect(model.phase == .newMac)
        #expect(model.database == nil)

        // The code opens the data from there as on any Mac that does not know the data.
        try await model.unlock(recoveryCode: code)

        #expect(model.phase == .ready)
        #expect(model.completion == UnlockCompletion(kind: .unlocked, codeLabel: label))
    }

    @Test func theCodeScreenIsOpenedFromTheLockedScreenAndNowhereElse() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        await model.launch()
        #expect(model.phase == .welcome)

        model.useRecoveryCode()

        #expect(model.phase == .welcome)

        try await startFresh(model)
        model.useRecoveryCode()

        #expect(model.phase == .ready)
    }

    // MARK: A backup file

    @Test func aBackupFileIsLookedAtBeforeAnythingIsAskedOfThePerson() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        // A backup that this Mac made itself, and one that another Mac made: its device key is not this Mac's.
        let here = makeAppModel(in: directory.appending(path: "Here"))
        try await startFresh(here)
        await here.didWriteAndBackUp()
        let ownBackup = try #require(try here.backups.localBackups().first).url
        let other = makeAppModel(in: directory.appending(path: "Other Mac"), device: OtherMacProtector())
        try await startFresh(other)
        try await #require(other.database).saveClient(Client(name: "Alfa Systems s.r.o."))
        try await #require(other.database).saveInvoice(Invoice.fixture())
        await other.didWriteAndBackUp()
        let otherBackup = try #require(try other.backups.localBackups().first).url
        let model = makeAppModel(in: directory.appending(path: "New Mac"))
        await model.launch()

        let own = try await model.inspectBackup(at: ownBackup)
        let foreign = try await model.inspectBackup(at: otherBackup)

        #expect(own.opensWithThisMac)
        #expect(own.url == ownBackup)
        #expect(!foreign.opensWithThisMac)
        #expect(foreign.url == otherBackup)
        #expect(foreign.header.invoiceCount == 1)
        #expect(foreign.header.clientCount == 1)
        #expect(foreign.header.years == 2026...2026)
        #expect(WelcomeTexts.backupCodeLabel(foreign.header) == label)
        // Looking changes nothing.
        #expect(model.phase == .welcome)
        #expect(model.vault.launchState() == .firstLaunch)
    }

    @Test func aFileThatIsNoBackupIsRefusedAndAFileThatIsNotThereFailsToo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        await model.launch()
        let text = directory.appending(path: "Poznámky.ttbackup")
        try Data("Tohle jsou jen poznámky, žádná záloha.".utf8).write(to: text)

        await #expect(throws: BackupError.notABackup) {
            _ = try await model.inspectBackup(at: text)
        }
        await #expect(throws: CocoaError.self) {
            _ = try await model.inspectBackup(at: directory.appending(path: "Chybí.ttbackup"))
        }

        #expect(model.phase == .welcome)
    }

    // MARK: Restoring a backup

    @Test func restoringABackupEndsInACardThatSaysWhatWasOpened() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let other = makeAppModel(in: directory.appending(path: "Other Mac"))
        let code = try await startFresh(other)
        try await #require(other.database).saveClient(Client(name: "Alfa Systems s.r.o."))
        try await #require(other.database).saveInvoice(Invoice.fixture())
        await other.didWriteAndBackUp()
        let backup = try #require(try other.backups.localBackups().first).url
        let model = makeAppModel(
            in: directory.appending(path: "New Mac"), device: ScriptedKeyProtector(openFailure: .deviceKeyUnusable))
        await model.launch()
        #expect(model.phase == .welcome)

        await #expect(throws: KeyError.wrongRecoveryCode) {
            try await model.restoreAtWelcome(from: backup, recoveryCode: strangerCode)
        }

        #expect(model.completion == nil)

        try await model.restoreAtWelcome(from: backup, recoveryCode: code)

        #expect(model.phase == .ready)
        let restored = UnlockCompletion.Kind.restored(created: civilDate("2026-10-17"), invoiceCount: 1, clientCount: 1)
        #expect(model.completion == UnlockCompletion(kind: restored, codeLabel: label))
        let completion = try #require(model.completion)
        #expect(
            WelcomeTexts.doneText(completion, touchID: model.appSettings.touchIDUnlock)
                == "Otevřela se záloha z 17.\u{00A0}10.\u{00A0}2026 (1 faktura, 1 odběratel). "
                + "Tento Mac ji odteď odemyká přes Touch ID a kód č. 1 z 17.\u{00A0}10.\u{00A0}2026 platí dál.")
    }

    @Test func theDayOfARestoredBackupIsTheDayInTheTimeZoneOfTheMac() throws {
        // 23:30 UTC on 16 October is already the 17th in Prague.
        let header = BackupHeader(
            created: date("2026-10-16T23:30:00Z"), appVersion: "1.0", schemaVersion: Schema.latestVersion,
            invoiceCount: 13, clientCount: 3, years: 2024...2026, deviceName: "Testovací MacBook",
            keys: KeysFile(recoverySlots: []))

        let prague = UnlockCompletion.restored(
            from: header, codeLabel: label, in: try #require(TimeZone(identifier: "Europe/Prague")))
        let newYork = UnlockCompletion.restored(
            from: header, codeLabel: label, in: try #require(TimeZone(identifier: "America/New_York")))

        #expect(prague.kind == .restored(created: civilDate("2026-10-17"), invoiceCount: 13, clientCount: 3))
        #expect(prague.codeLabel == label)
        #expect(newYork.kind == .restored(created: civilDate("2026-10-16"), invoiceCount: 13, clientCount: 3))
    }

    @Test func aBackupFromBeforeTheClientsWereCountedIsRestoredWithoutTheirNumber() throws {
        let header = BackupHeader(
            created: date("2026-10-16T12:00:00Z"), appVersion: "1.0", schemaVersion: Schema.latestVersion,
            invoiceCount: 13, deviceName: "Testovací MacBook", keys: KeysFile(recoverySlots: []))

        let completion = UnlockCompletion.restored(
            from: header, codeLabel: nil, in: try #require(TimeZone(identifier: "Europe/Prague")))

        #expect(completion.kind == .restored(created: civilDate("2026-10-16"), invoiceCount: 13, clientCount: nil))
        #expect(completion.codeLabel == nil)
    }
}

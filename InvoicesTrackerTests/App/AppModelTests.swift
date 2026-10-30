import Foundation
import Testing
@testable import InvoicesTracker

/// The app model: the first launch, unlocking, "K datu" and the years, writes and their backups, the payments that are
/// converted again, and the computation of the selected year. Every test has its own folder, a software key protector
/// stands in for the Secure Enclave, the clock is at noon of 17 October 2026 in the Mac's time zone, and nothing
/// reaches the network.
@Suite(.settlesBackups)
@MainActor
struct AppModelTests {
    /// A well-formed recovery code that opens no slot.
    private let strangerCode = "7777-7777-7777-7777-7777-7777-7777-7777"

    // MARK: First launch

    @Test func aFolderWithoutDataWelcomes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)

        await model.launch()

        #expect(model.phase == .welcome)
        #expect(model.database == nil)
        #expect(model.today == civilDate("2026-10-17"))
        #expect(model.asOf == AsOfState.launch(today: civilDate("2026-10-17")))
        #expect(model.years == [2026])
    }

    @Test func aFreshStartShowsTheCodeFirstAndMakesTheDataOnceItIsStored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        await model.launch()

        try await model.startFresh()

        guard case .onboarding(.recoveryCode(let code, let label, _, _)) = model.phase else {
            Issue.record("The first step shows the recovery code, not \(model.phase).")
            return
        }
        #expect(code.count == 39)
        #expect(label == "kód č. 1 z 17.\u{00A0}10.\u{00A0}2026")
        // Nothing is on disk until the person has stored the code.
        #expect(model.vault.launchState() == .firstLaunch)
        #expect(model.database == nil)

        try await model.finishRecoveryCodeStep(touchID: true)

        #expect(model.phase == .onboarding(.supplier))
        #expect(model.vault.launchState() == .existing)
        #expect(model.vault.requiredRecoveryLabel == label)
        let keys = try #require(try KeyManager.load(model.vault.paths.keys))
        #expect(try KeyManager.unlock(keys, recoveryCode: code).slot.label == label)
        #expect(try await #require(model.database).appSettings().touchIDUnlock)

        model.skipSupplierStep()

        #expect(model.phase == .onboarding(.importOffer))

        model.finishOnboarding(importNow: true)

        #expect(model.phase == .ready)
        #expect(model.screen == .importer)
    }

    @Test func startingWithoutImportOpensPřehled() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)

        try await startFresh(model)

        #expect(model.phase == .ready)
        #expect(model.screen == .overview)
    }

    @Test func aCodeStepThatCannotMakeTheDataStaysWithTheSameCodeUntilItCan() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let device = ScriptedKeyProtector(sealFailure: .deviceKeyUnusable)
        let model = makeAppModel(in: directory, device: device)
        await model.launch()
        try await model.startFresh()
        let codeStep = model.phase

        await #expect(throws: KeyError.deviceKeyUnusable) {
            try await model.finishRecoveryCodeStep(touchID: false)
        }

        #expect(model.phase == codeStep)
        #expect(model.vault.launchState() == .firstLaunch)

        device.sealFailure = nil
        try await model.finishRecoveryCodeStep(touchID: false)

        #expect(model.phase == .onboarding(.supplier))
        guard case .onboarding(.recoveryCode(let code, _, _, _)) = codeStep else {
            Issue.record("The first step shows the recovery code, not \(codeStep).")
            return
        }
        // The code that was shown is the code of the data, and Touch ID stays off as chosen.
        let keys = try #require(try KeyManager.load(model.vault.paths.keys))
        #expect(throws: Never.self) { try KeyManager.unlock(keys, recoveryCode: code) }
        #expect(try await #require(model.database).appSettings().touchIDUnlock == false)
    }

    @Test func theSupplierStepSavesTheSupplierAndTheAccountInCrowns() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        await model.launch()
        try await model.startFresh()
        try await model.finishRecoveryCodeStep(touchID: true)
        var supplier = Supplier()
        supplier.name = "Jana Nováková"
        supplier.street = "Dlouhá 12"
        supplier.postcode = "110 00"
        supplier.city = "Praha"
        supplier.ico = "12345678"
        let account = BankAccount(currency: .czk, accountNumber: "19-2000145399/0800", iban: "CZ6508000000192000145399")

        try await model.saveSupplierStep(supplier, czkAccount: account)

        #expect(model.phase == .onboarding(.importOffer))
        let database = try #require(model.database)
        #expect(try await database.supplier() == supplier)
        #expect(try await database.bankAccounts() == [account])
    }

    @Test func startingWithEmptyDataOnAMacThatCannotOpenTheDataSetsTheOldDataAside() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let before = makeAppModel(in: directory)
        try await startFresh(before)
        try await #require(before.database).saveInvoice(Invoice.fixture())
        await before.database?.close()
        let model = makeAppModel(in: directory, device: ScriptedKeyProtector(openFailure: .deviceKeyUnusable))
        await model.launch()
        #expect(model.phase == .newMac)

        try await model.startFresh()
        try await model.finishRecoveryCodeStep(touchID: true)

        #expect(model.phase == .onboarding(.supplier))
        let dataFolder = model.vault.paths.directory
        let setAside = try FileManager.default.contentsOfDirectory(atPath: dataFolder.path(percentEncoded: false))
            .filter { $0.hasPrefix("Set aside ") }
        try #require(setAside.count == 1)
        let aside = try FileManager.default.contentsOfDirectory(
            atPath: dataFolder.appending(path: setAside[0]).path(percentEncoded: false))
        #expect(aside.contains("InvoicesTracker.sqlite"))
        #expect(aside.contains("InvoicesTracker.keys"))
        // The new data is open, and it is empty.
        #expect(try await #require(model.database).invoiceCount() == 0)
        #expect(model.vault.launchState() == .existing)
    }

    @Test func goingBackFromTheCodeStepReturnsToTheWelcomeWithNothingOnDisk() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        await model.launch()
        try await model.startFresh()

        model.cancelFreshStart()

        #expect(model.phase == .welcome)
        #expect(model.vault.launchState() == .firstLaunch)
        #expect(!FileManager.default.fileExists(atPath: model.vault.paths.directory.path(percentEncoded: false)))
        // The code that was shown is forgotten: confirming it now makes nothing.
        try await model.finishRecoveryCodeStep(touchID: true)
        #expect(model.phase == .welcome)
        #expect(model.vault.launchState() == .firstLaunch)
    }

    @Test func goingBackFromTheCodeStepOnAMacThatCannotOpenTheDataLeavesTheDataAsItIs() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let before = makeAppModel(in: directory)
        try await startFresh(before)
        try await #require(before.database).saveInvoice(Invoice.fixture())
        await before.database?.close()
        let model = makeAppModel(in: directory, device: ScriptedKeyProtector(openFailure: .deviceKeyUnusable))
        await model.launch()
        let files = try contents(of: model.vault.paths.directory)

        try await model.startFresh()
        model.cancelFreshStart()

        #expect(model.phase == .newMac)
        #expect(try contents(of: model.vault.paths.directory) == files)
        #expect(model.database == nil)
    }

    @Test func goingBackFromTheCodeStepOfDamagedDataShowsItAgain() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let before = makeAppModel(in: directory)
        try await startFresh(before)
        await before.database?.close()
        try FileManager.default.removeItem(at: before.vault.paths.keys)
        let model = makeAppModel(in: directory)
        await model.launch()
        let files = try contents(of: model.vault.paths.directory)

        try await model.startFresh()
        model.cancelFreshStart()

        #expect(model.phase == .damaged("Chybí soubor s klíči k datům."))
        #expect(try contents(of: model.vault.paths.directory) == files)
    }

    @Test func eachStepOfTheStartMovesOnFromItsOwnStepOnly() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        await model.launch()
        try await model.startFresh()
        let codeStep = model.phase

        model.skipSupplierStep()
        model.finishOnboarding(importNow: true)

        #expect(model.phase == codeStep)

        try await model.finishRecoveryCodeStep(touchID: true)
        model.finishOnboarding(importNow: true)

        #expect(model.phase == .onboarding(.supplier))

        model.skipSupplierStep()
        model.skipSupplierStep()

        #expect(model.phase == .onboarding(.importOffer))

        model.finishOnboarding(importNow: false)

        #expect(model.phase == .ready)
        #expect(model.screen == .overview)
    }

    /// The names of the files and folders directly in `folder`, with the bytes of each file.
    private func contents(of folder: URL) throws -> [String: Data] {
        var contents: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) {
            let url = folder.appending(path: name)
            let isFile = try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            contents[name] = isFile ? try Data(contentsOf: url) : Data()
        }
        return contents
    }

    // MARK: Unlocking

    @Test func aDismissedTouchIDPromptLocksAndUnlockingAgainOpensTheData() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let before = makeAppModel(in: directory)
        try await startFresh(before)
        await before.database?.close()
        let device = ScriptedKeyProtector(openFailure: .userCancelled)
        let model = makeAppModel(in: directory, device: device)

        await model.launch()

        #expect(model.phase == .locked)
        #expect(model.database == nil)
        #expect(model.refresh == nil)

        device.openFailure = nil
        await model.unlockWithDevice()

        #expect(model.phase == .ready)
        #expect(model.database != nil)
        #expect(model.refresh != nil)
    }

    @Test func aMacWhoseDeviceKeyCannotOpenTheDataOpensItWithTheRightCodeOnly() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let before = makeAppModel(in: directory)
        let code = try await startFresh(before)
        await before.database?.close()
        let model = makeAppModel(in: directory, device: ScriptedKeyProtector(openFailure: .deviceKeyUnusable))

        await model.launch()

        #expect(model.phase == .newMac)

        await #expect(throws: KeyError.wrongRecoveryCode) {
            try await model.unlock(recoveryCode: strangerCode)
        }

        #expect(model.phase == .newMac)
        #expect(model.database == nil)

        try await model.unlock(recoveryCode: code)

        #expect(model.phase == .ready)
        #expect(model.database != nil)
    }

    @Test func aDatabaseWithoutItsKeysFileIsDamaged() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let before = makeAppModel(in: directory)
        try await startFresh(before)
        await before.database?.close()
        try FileManager.default.removeItem(at: before.vault.paths.keys)
        let model = makeAppModel(in: directory)

        await model.launch()

        #expect(model.phase == .damaged("Chybí soubor s klíči k datům."))
        #expect(model.database == nil)
    }

    @Test func dataThatANewerVersionOfTheAppSavedIsNotOpened() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let before = makeAppModel(in: directory)
        try await startFresh(before)
        let key = try #require(before.vault.dataKey)
        await before.database?.close()
        let newer = try SQLiteConnection(path: before.vault.paths.database.path(percentEncoded: false), key: key)
        try newer.setUserVersion(Schema.latestVersion + 1)
        newer.close()
        let model = makeAppModel(in: directory)

        await model.launch()

        #expect(model.phase == .newerVersion)
        #expect(model.database == nil)
        #expect(model.refresh == nil)
    }

    /// Data that a newer version of the app saved, on a Mac that does not know them: the recovery code opens the keys,
    /// and the data say they are newer. That is what the window says, not that something went wrong, and neither the
    /// start with empty data nor a restore can set them aside from there.
    @Test func dataOfANewerVersionReachedWithTheRecoveryCodeShowNewerVersionAndAreNotSetAside() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let backup = try await makeBackupOfAnotherMac(in: directory, invoices: 1)
        let before = makeAppModel(in: directory)
        let code = try await startFresh(before)
        let key = try #require(before.vault.dataKey)
        await before.database?.close()
        let newer = try SQLiteConnection(path: before.vault.paths.database.path(percentEncoded: false), key: key)
        try newer.setUserVersion(Schema.latestVersion + 1)
        newer.close()
        let model = makeAppModel(in: directory, device: ScriptedKeyProtector(openFailure: .deviceKeyUnusable))
        await model.launch()
        #expect(model.phase == .newMac)

        try await model.unlock(recoveryCode: code)

        #expect(model.phase == .newerVersion)
        #expect(model.database == nil)
        let files = try contents(of: model.vault.paths.directory)

        try await model.startFresh()
        #expect(model.phase == .newerVersion)
        try await model.restoreAtWelcome(from: backup.url, recoveryCode: backup.code)
        #expect(model.phase == .newerVersion)
        #expect(model.database == nil)
        #expect(try contents(of: model.vault.paths.directory) == files)
    }

    @Test func dataOfAnotherMacAskForTheRecoveryCodeWithoutATouchIDPromptFirst() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        // The data came through Migration Assistant: their device slot is the other Mac's, with Touch ID on.
        let other = makeAppModel(in: directory, device: OtherMacProtector())
        try await startFresh(other)
        await other.database?.close()
        let protector = PromptCountingProtector()
        let model = makeAppModel(in: directory, device: protector)

        await model.launch()

        #expect(model.phase == .newMac)
        #expect(protector.prompts == 0)
    }

    @Test func aRestoreWhosePromptIsDismissedOrWhoseCodeIsWrongChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let other = makeAppModel(in: directory.appending(path: "Other Mac"))
        let code = try await startFresh(other)
        await other.didWriteAndBackUp()
        let backup = try #require(try other.backups.localBackups().first).url
        await other.database?.close()
        // The prompt for the device key of this Mac is dismissed.
        let welcome = makeAppModel(
            in: directory.appending(path: "Welcome"), device: ScriptedKeyProtector(openFailure: .userCancelled))
        await welcome.launch()

        await #expect(throws: KeyError.userCancelled) {
            try await welcome.restoreAtWelcome(from: backup, recoveryCode: code)
        }

        #expect(welcome.phase == .welcome)
        #expect(welcome.database == nil)
        #expect(welcome.vault.launchState() == .firstLaunch)

        // Data this Mac cannot open, and a backup it cannot open either, with a wrong code.
        let lost = makeAppModel(in: directory.appending(path: "New Mac"))
        try await startFresh(lost)
        await lost.database?.close()
        let newMac = makeAppModel(
            in: directory.appending(path: "New Mac"), device: ScriptedKeyProtector(openFailure: .deviceKeyUnusable))
        await newMac.launch()
        let files = try contents(of: newMac.vault.paths.directory)

        await #expect(throws: KeyError.wrongRecoveryCode) {
            try await newMac.restoreAtWelcome(from: backup, recoveryCode: strangerCode)
        }

        #expect(newMac.phase == .newMac)
        #expect(newMac.database == nil)
        #expect(try contents(of: newMac.vault.paths.directory) == files)
    }

    @Test func aBackupRestoredAtTheWelcomeOpensItsData() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let before = makeAppModel(in: directory.appending(path: "Other Mac"))
        let code = try await startFresh(before)
        try await #require(before.database).saveInvoice(Invoice.fixture())
        await before.didWriteAndBackUp()
        let backup = try #require(try before.backups.localBackups().first).url
        let model = makeAppModel(in: directory, device: ScriptedKeyProtector(openFailure: .deviceKeyUnusable))
        await model.launch()
        #expect(model.phase == .welcome)

        try await model.restoreAtWelcome(from: backup, recoveryCode: code)

        #expect(model.phase == .ready)
        #expect(try await #require(model.database).invoiceCount() == 1)
    }

    // MARK: Years and "K datu"

    @Test func theYearsAreTheYearsWithDataAndTheCurrentYearNewestFirstAndNoneAfterIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let database = try #require(model.database)
        var imported = Invoice.fixture(number: "20210301", duzp: "2021-03-31", dueDate: "2021-04-14")
        imported.source = .imported(fakturoidID: "1001", fingerprint: "fingerprint-1001", changedInApp: false)
        try await database.saveInvoice(imported)
        // An invoice dated next year by mistake does not add a year that has not come yet.
        try await database.saveInvoice(Invoice.fixture(number: "20270101", duzp: "2027-01-31", dueDate: "2027-02-14"))

        await model.didWrite()

        #expect(model.years == [2026, 2021])
    }

    @Test func atNewYearAStateThatFollowsTodayMovesToTheNewYearWhichIsAnEstimate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        #expect(model.asOf.followsToday)

        model.handleDayChanged(civilDate("2027-01-01"))

        #expect(model.today == civilDate("2027-01-01"))
        #expect(model.asOf.year == 2027)
        #expect(model.asOf.asOf == civilDate("2027-01-31"))
        #expect(model.asOf.followsToday)
        #expect(model.years.first == 2027)
        #expect(model.newYearBanner == 2026)
        let result = try await model.computeSelectedYear()
        #expect(result.year == 2027)
        #expect(result.asOf == civilDate("2027-01-01"))
        #expect(result.rulesAreEstimate)
    }

    @Test func theNewYearIsSaidToVoiceOverOnceWhenItBegins() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        var announced: [String] = []
        model.announce = { announced.append($0) }

        model.handleDayChanged(civilDate("2027-01-01"))
        // The next day, and the banner that is closed, say nothing more.
        model.handleDayChanged(civilDate("2027-01-02"))
        model.newYearBanner = nil

        #expect(announced == ["Začal rok 2027 — rok 2026 je uzavřený"])
    }

    @Test func pickingAnotherDayStopsFollowingTodayAndANewDayLeavesItAlone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)

        model.pickAsOf(civilDate("2026-09-30"))

        #expect(model.asOf.asOf == civilDate("2026-09-30"))
        #expect(!model.asOf.followsToday)

        model.handleDayChanged(civilDate("2026-10-18"))

        #expect(model.today == civilDate("2026-10-18"))
        #expect(model.asOf.asOf == civilDate("2026-09-30"))
        #expect(!model.asOf.followsToday)
        #expect(model.newYearBanner == nil)
    }

    @Test func returningToTheCurrentYearAndPickingMonthEndFollowTheAutomaticCutoffAgain() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)

        model.selectYear(2025)

        #expect(model.asOf == AsOfState(year: 2025, asOf: civilDate("2025-12-31"), followsToday: false))

        model.goToday()

        #expect(model.asOf == AsOfState.launch(today: civilDate("2026-10-17")))

        model.pickAsOf(civilDate("2026-12-24"))

        #expect(!model.asOf.followsToday)

        model.pickAsOf(civilDate("2026-10-31"))

        #expect(model.asOf.followsToday)
    }

    /// Moving the real clock inside a month invalidates cash-based screens without moving their reporting cutoff.
    @Test func reportingFollowsMonthEndWhileRealTodayInvalidatesReloadsEveryDay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory, clock: ManualClock(localNoon(2026, 10, 28)))
        try await startFresh(model)

        #expect(model.today == civilDate("2026-10-28"))
        #expect(model.asOf.asOf == civilDate("2026-10-31"))
        let octoberKey = model.reloadKey
        model.handleDayChanged(civilDate("2026-10-29"))
        #expect(model.today == civilDate("2026-10-29"))
        #expect(model.asOf.asOf == civilDate("2026-10-31"))
        #expect(model.reloadKey != octoberKey)

        model.handleDayChanged(civilDate("2026-11-01"))
        #expect(model.today == civilDate("2026-11-01"))
        #expect(model.asOf.asOf == civilDate("2026-11-30"))

        model.selectYear(2025)
        model.handleDayChanged(civilDate("2026-12-01"))
        #expect(model.asOf.asOf == civilDate("2025-12-31"))
        #expect(!model.asOf.followsToday)
    }

    @Test func theReloadKeyIncludesTheReportingDayAndRealTodayAlongsideDataAndSearch() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let version = model.dataVersion

        model.pickAsOf(civilDate("2026-09-30"))
        model.searchText = "cetus"

        #expect(
            model.reloadKey
                == ReloadKey(
                    year: 2026, asOf: civilDate("2026-09-30"), today: civilDate("2026-10-17"),
                    dataVersion: version, search: "cetus"))
    }

    // MARK: Screens and banners

    @Test func aBannerBelongsToItsScreenAndClosesWhenTheScreenChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        model.screen = .invoices

        model.showBanner("Faktura 20260901 byla smazána.")

        #expect(model.banner == AppBanner(text: "Faktura 20260901 byla smazána.", screen: .invoices))

        model.showBanner("Změny faktury 20260902 jsou uložené.")

        #expect(model.banner == AppBanner(text: "Změny faktury 20260902 jsou uložené.", screen: .invoices))

        model.screen = .overview

        #expect(model.banner == nil)
    }

    @Test func theBadgeOfFakturyCountsTheDraftsOfTheSelectedYear() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let database = try #require(model.database)
        try await database.saveInvoice(Invoice.fixture(number: "20260901", status: .draft))
        try await database.saveInvoice(Invoice.fixture(number: "20260902", status: .draft))
        try await database.saveInvoice(Invoice.fixture(number: "20260903"))
        try await database.saveInvoice(Invoice.fixture(number: "20251201", duzp: "2025-12-01", status: .draft))

        #expect(await model.draftCountOfSelectedYear() == 2)

        model.selectYear(2025)

        #expect(await model.draftCountOfSelectedYear() == 1)
    }

    @Test func openingAnInvoiceShowsFakturyWithItsDetail() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)

        model.openInvoice(42)

        #expect(model.screen == .invoices)
        #expect(model.pendingDetailInvoiceID == 42)
    }

    @Test func aNewInvoiceIsStartedOnFakturyWhateverScreenAskedForIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        model.screen = .computation
        model.editorRequest = .chooser

        model.startNewInvoice(templateID: 7)

        #expect(model.screen == .invoices)
        #expect(model.editorRequest == .new(templateID: 7))
        #expect(model.isEditorOpen)
    }

    @Test func closingTheEditorOfAnInvoiceShowsFakturyWithItsDetail() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        model.screen = .invoices
        model.editorRequest = .edit(42)

        model.closeEditor()

        #expect(model.editorRequest == nil)
        #expect(model.screen == .invoices)
        #expect(model.pendingDetailInvoiceID == 42)
        #expect(model.isEditorOpen == false)
    }

    @Test func closingTheEditorOfANewInvoiceShowsFakturyWithTheDetailClosed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        model.startNewInvoice(templateID: nil)

        model.closeEditor()

        #expect(model.editorRequest == nil)
        #expect(model.screen == .invoices)
        #expect(model.pendingDetailInvoiceID == nil)
    }

    @Test func leavingFakturyKeepsTheEditorAndTheChooserWhereTheyAre() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        model.startNewInvoice(templateID: nil)

        model.screen = .overview

        // The invoice that is being written waits for the window to come back to Faktury.
        #expect(model.editorRequest == .new(templateID: nil))
        #expect(model.isEditorOpen)

        model.screen = .computation
        model.screen = .invoices

        #expect(model.editorRequest == .new(templateID: nil))

        model.editorRequest = .chooser
        model.screen = .computation

        #expect(model.editorRequest == .chooser)
        #expect(model.requestBeforeChooser == .new(templateID: nil))
    }

    @Test func theChooserOpensOverTheEditorAndLeavesItWhereItIs() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        model.startNewInvoice(templateID: 3)
        #expect(model.shownEditorRequest == .new(templateID: 3))

        model.editorRequest = .chooser

        // The chooser is not the editor, and the editor stays on the screen under it.
        #expect(model.isEditorOpen == false)
        #expect(model.requestBeforeChooser == .new(templateID: 3))
        #expect(model.shownEditorRequest == .new(templateID: 3))

        model.cancelChooser()

        #expect(model.editorRequest == .new(templateID: 3))
        #expect(model.requestBeforeChooser == nil)
        #expect(model.shownEditorRequest == .new(templateID: 3))
    }

    @Test func aChoiceInTheChooserReplacesTheEditorUnderIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        model.startNewInvoice(templateID: nil)
        let generation = model.editorGeneration
        model.editorRequest = .chooser

        // The same blank invoice again is a new editor, not the one that was under the chooser.
        model.startNewInvoice(templateID: nil)

        #expect(model.editorRequest == .new(templateID: nil))
        #expect(model.requestBeforeChooser == nil)
        #expect(model.editorGeneration == generation + 1)
    }

    @Test func theChooserOverAnInvoiceThatIsEditedShowsItAgainOnCancel() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        model.screen = .invoices
        model.editorRequest = .edit(42)
        model.editorRequest = .chooser

        model.cancelChooser()

        #expect(model.editorRequest == .edit(42))
    }

    @Test func theChooserOverAScreenWithoutAnEditorClosesOnCancel() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        model.screen = .computation
        model.editorRequest = .chooser
        #expect(model.requestBeforeChooser == nil)
        #expect(model.shownEditorRequest == nil)

        model.cancelChooser()

        #expect(model.editorRequest == nil)
        #expect(model.screen == .computation)
        // Zrušit does nothing while there is no chooser to cancel.
        model.editorRequest = .edit(7)
        model.cancelChooser()
        #expect(model.editorRequest == .edit(7))
    }

    @Test func hledatFocusesTheSearchOfFakturyOnlyWhileFakturyIsShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        #expect(model.screen == .overview)

        // Přehled has no search field.
        model.focusSearch()
        #expect(model.searchFocusRequests == 0)

        model.screen = .invoices
        model.focusSearch()
        #expect(model.searchFocusRequests == 1)
        model.focusSearch()
        #expect(model.searchFocusRequests == 2)

        model.screen = .clients
        model.focusSearch()
        #expect(model.searchFocusRequests == 2)
    }

    @Test func hledatDoesNothingWhileASheetOrTheEditorIsOverFaktury() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        model.screen = .invoices
        #expect(model.canFocusSearch)

        // A sheet of Faktury (payment, deletion, PDF) is open: its screen says so.
        model.invoiceSheetOpen = true
        #expect(!model.canFocusSearch)
        model.focusSearch()
        #expect(model.searchFocusRequests == 0)
        model.invoiceSheetOpen = false
        #expect(model.canFocusSearch)

        // The chooser, a sheet of the window, and the editor that Faktury shows in place of its list.
        model.editorRequest = .chooser
        #expect(!model.canFocusSearch)
        model.focusSearch()
        model.editorRequest = .edit(7)
        #expect(!model.canFocusSearch)
        model.focusSearch()
        model.editorRequest = nil
        #expect(model.searchFocusRequests == 0)

        // The sheet that asks to confirm a uniform rate is over every screen.
        model.uniformRateOffer = try gfrFinding2025()
        #expect(!model.canFocusSearch)
        model.focusSearch()
        #expect(model.searchFocusRequests == 0)
        model.uniformRateOffer = nil

        model.focusSearch()
        #expect(model.searchFocusRequests == 1)
    }

    // MARK: Writes, settings and backups

    @Test func aBackupNamesThisMac() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)

        await model.didWriteAndBackUp()

        let header = try #require(try model.backups.localBackups().first).header
        #expect(header.deviceName == (Host.current().localizedName ?? "Mac"))
        #expect(!header.deviceName.isEmpty)
    }

    @Test func aWriteReloadsTheScreensAndMakesTheFirstLocalBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let version = model.dataVersion
        #expect(try model.backups.localBackups().isEmpty)

        await model.didWriteAndBackUp()

        #expect(model.dataVersion == version + 1)
        let backups = try model.backups.localBackups()
        #expect(backups.count == 1)
        #expect(model.appSettings.lastLocalBackup == backups.first?.header.created)
        #expect(try await #require(model.database).appSettings().lastLocalBackup == backups.first?.header.created)
    }

    @Test func aChangeWithinTheHourOfABackupIsBackedUpByTheWakeArmedForTheHour() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let noon = localNoon(2026, 10, 17)
        let clock = ManualClock(noon)
        let scheduler = ManualScheduler()
        let model = makeAppModel(in: directory, clock: clock, scheduler: scheduler)
        try await startFresh(model)
        await model.didWriteAndBackUp()
        #expect(try model.backups.localBackups().count == 1)
        #expect(model.appSettings.localBackupPendingSince == nil)
        #expect(scheduler.armed.isEmpty)

        clock.advance(by: 30 * 60)
        await model.didWriteAndBackUp()

        #expect(try model.backups.localBackups().count == 1)
        #expect(model.appSettings.localBackupPendingSince == noon + 30 * 60)
        #expect(scheduler.armed == [noon + 60 * 60])

        clock.advance(by: 30 * 60)
        #expect(scheduler.fire())
        try await waitUntil { model.appSettings.localBackupPendingSince == nil }

        #expect(try model.backups.localBackups().count == 2)
        #expect(model.appSettings.lastLocalBackup == noon + 60 * 60)
        #expect(try await #require(model.database).appSettings().localBackupPendingSince == nil)
        #expect(scheduler.armed.isEmpty)
    }

    @Test func aChangeStillWaitingWhenTheAppQuitIsBackedUpAfterTheNextLaunchOnceTheHourIsUp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let noon = localNoon(2026, 10, 17)
        let clock = ManualClock(noon)
        let first = makeAppModel(in: directory, clock: clock)
        try await startFresh(first)
        await first.didWriteAndBackUp()
        clock.advance(by: 30 * 60)
        await first.didWriteAndBackUp()
        await first.database?.close()

        // Before the hour is up, the next launch arms the wake for it.
        clock.advance(by: 15 * 60)
        let earlyScheduler = ManualScheduler()
        let early = makeAppModel(in: directory, clock: clock, scheduler: earlyScheduler)
        await early.launch()

        #expect(early.phase == .ready)
        #expect(try early.backups.localBackups().count == 1)
        #expect(early.appSettings.localBackupPendingSince == noon + 30 * 60)
        #expect(earlyScheduler.armed == [noon + 60 * 60])

        await early.database?.close()
        // After it, the launch makes the backup.
        clock.advance(by: 16 * 60)
        let late = makeAppModel(in: directory, clock: clock)
        await late.launch()

        #expect(try late.backups.localBackups().count == 2)
        #expect(late.appSettings.lastLocalBackup == noon + 61 * 60)
        #expect(late.appSettings.localBackupPendingSince == nil)
    }

    @Test func aBackupThatFailsLeavesTheChangeWaitingAndIsTriedAgainAnHourLater() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let noon = localNoon(2026, 10, 17)
        let clock = ManualClock(noon)
        let scheduler = ManualScheduler()
        let model = makeAppModel(in: directory, clock: clock, scheduler: scheduler)
        try await startFresh(model)
        // A file where the folder of the local backups belongs: no backup can be made.
        let blocker = model.vault.paths.directory.appending(path: "Backups")
        try Data().write(to: blocker)

        await model.didWriteAndBackUp()

        #expect(model.appSettings.lastLocalBackup == nil)
        #expect(model.appSettings.localBackupPendingSince == noon)
        #expect(try await #require(model.database).appSettings().localBackupPendingSince == noon)
        #expect(scheduler.armed == [noon + 60 * 60])

        try FileManager.default.removeItem(at: blocker)
        clock.advance(by: 60 * 60)
        #expect(scheduler.fire())
        try await waitUntil { model.appSettings.localBackupPendingSince == nil }

        #expect(try model.backups.localBackups().count == 1)
        #expect(model.appSettings.lastLocalBackup == noon + 60 * 60)
    }

    @Test func aFolderOutsideTheMacGetsItsBackupAtAWriteAndADayLaterAtTheLaunch() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let model = makeAppModel(in: directory, clock: clock)
        try await startFresh(model)
        let folder = directory.appending(path: "Off the Mac", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bookmark = try BackupService.makeBookmark(for: folder)
        await model.updateAppSettings { $0.backupFolderBookmark = bookmark }
        let backupsOutside = {
            try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
                .filter { $0.hasSuffix(".ttbackup") }
        }

        await model.didWriteAndBackUp()

        #expect(try backupsOutside().count == 1)
        #expect(model.appSettings.lastOffMacBackup == localNoon(2026, 10, 17))

        // Within the day nothing more is made outside the Mac; the next day's launch makes the next one.
        clock.advance(by: 2 * 60 * 60)
        await model.didWriteAndBackUp()
        #expect(try backupsOutside().count == 1)
        await model.database?.close()
        clock.advance(by: 22 * 60 * 60)
        let relaunched = makeAppModel(in: directory, clock: clock)

        await relaunched.launch()

        #expect(try backupsOutside().count == 2)
        #expect(relaunched.appSettings.lastOffMacBackup == localNoon(2026, 10, 18))
    }

    @Test func aChangeOfTheSettingsIsSavedAndShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)

        await model.updateAppSettings { $0.appearance = .dark }

        #expect(model.appSettings.appearance == .dark)
        #expect(try await #require(model.database).appSettings().appearance == .dark)
        // The settings are read again when the data is opened.
        await model.database?.close()
        let relaunched = makeAppModel(in: directory)
        await relaunched.launch()
        #expect(relaunched.appSettings.appearance == .dark)
    }

    // MARK: The refresh

    @Test func theRefreshTellsTheModelOfADayRatesAndTheUniformRate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let refresh = try #require(model.refresh)
        let published = try gfrFinding2025()
        let finding = GFRFinding(
            year: 2026, instruction: "GFŘ-D-80", issueURL: try #require(URL(string: "https://mf.gov.cz/issue")),
            pdfURL: try #require(URL(string: "https://mf.gov.cz/issue.pdf")), rates: published.rates)

        refresh.onDayChanged?(civilDate("2026-10-18"))
        refresh.onUniformRateFound?(finding)
        refresh.onUniformRateReminder?(2026)

        #expect(model.today == civilDate("2026-10-18"))
        #expect(model.asOf.asOf == civilDate("2026-10-31"))
        #expect(model.uniformRateReminderYear == 2026)
        // The finding is offered once the data say that its year has no rates.
        try await waitUntil { model.pendingUniformRate == finding }
    }

    @Test(.hangGuard)
    func theRefreshRunsOnlyWhenTheAppStartsIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        // Started: it listens to the triggers, and its first run asks the server for the missing rates and sets its
        // timer.
        let server = StubHTTPClient()
        let scheduler = ManualScheduler()
        let started = makeAppModel(
            in: directory.appending(path: "Started"), http: server, scheduler: scheduler, startsRefresh: true)
        try await startFresh(started)
        let refresh = try #require(started.refresh)
        // A refresh that was not started would never set its timer, and the wait below would not end.
        try #require(refresh.isStarted)

        // A run sets its timer as the last of its steps, after it has asked the server.
        await scheduler.untilAWakeIsAsked()

        #expect(!server.requests.isEmpty)
        refresh.stop()

        // Not started: it is there for Nastavení, but listens to nothing, so it asks nothing and sets no timer.
        let quietServer = StubHTTPClient()
        let quietScheduler = ManualScheduler()
        let quiet = makeAppModel(in: directory.appending(path: "Quiet"), http: quietServer, scheduler: quietScheduler)
        try await startFresh(quiet)

        #expect(try #require(quiet.refresh).isStarted == false)
        #expect(quietServer.requests.isEmpty)
        #expect(quietScheduler.wakes.isEmpty)
    }

    @Test func newRatesFromTheRefreshConvertTheProvisionalPayments() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let database = try #require(model.database)
        var invoice = dollarInvoice(
            number: "20260906", invoiceRate: storedRate("USD", "21.500", declaredOn: "2026-09-30"))
        invoice.payment = PaymentConverter.convert(
            invoice: invoice, date: civilDate("2026-10-07"), requested: .cnbDaily, bankCZKTotalHalere: nil,
            cnbRate: .notYetAvailable, uniformRate: nil)
        let id = try await database.saveInvoice(invoice)
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2026-10-07"), currency: .usd, amount: 1, rate: decimal("21.000"))
        ])
        let refresh = try #require(model.refresh)
        let backupsBefore = model.backupsAfterWrite

        refresh.onRatesUpdated?()
        try await waitUntil { try await database.invoice(id: id)?.payment?.provisional == false }
        // The conversion is a write, told from a task of the callback: the test goes on once that write has started
        // its backups, which the trait of the suite waits for, so that none of them runs after the folder is removed.
        try await waitUntil { model.backupsAfterWrite != backupsBefore }

        let payment = try #require(try await database.invoice(id: id)?.payment)
        #expect(payment.rate == storedRate("USD", "21.000", declaredOn: "2026-10-07"))
        #expect(payment.czkNetHalere == 2_100_000)
    }

    @Test func newRatesReloadTheScreensAlsoWhenNoPaymentChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let version = model.dataVersion

        await model.ratesUpdated()

        #expect(model.dataVersion == version + 1)
    }

    // MARK: Payments converted again

    /// 1 000 USD without VAT, supplied on 30 September 2026, with the invoice rate 21,500 Kč of that day.
    private func dollarInvoice(number: String, invoiceRate: StoredRate?) -> Invoice {
        Invoice.fixture(
            number: number, currency: .usd, items: [.fixture("10", at: 10_000)], vatMode: .outsideCountry,
            invoiceRate: invoiceRate)
    }

    @Test func newRatesConvertAProvisionalPaymentAtTheRateOfItsDay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let database = try #require(model.database)
        var invoice = dollarInvoice(
            number: "20260902", invoiceRate: storedRate("USD", "21.500", declaredOn: "2026-09-30"))
        // Paid on 7 October before the rate of the day was stored: at the invoice rate, for now.
        invoice.payment = PaymentConverter.convert(
            invoice: invoice, date: civilDate("2026-10-07"), requested: .cnbDaily, bankCZKTotalHalere: nil,
            cnbRate: .notYetAvailable, uniformRate: nil)
        #expect(invoice.payment?.provisional == true)
        let id = try await database.saveInvoice(invoice)
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2026-10-07"), currency: .usd, amount: 1, rate: decimal("21.000"))
        ])
        let version = model.dataVersion

        await model.ratesUpdated()

        let payment = try #require(try await database.invoice(id: id)?.payment)
        #expect(payment.conversion == .cnbDaily)
        #expect(payment.rate == storedRate("USD", "21.000", declaredOn: "2026-10-07"))
        #expect(payment.czkNetHalere == 2_100_000)
        #expect(payment.czkVatHalere == 0)
        #expect(!payment.provisional)
        #expect(model.dataVersion > version)
    }

    @Test func aProvisionalPaymentWhoseRateIsStillMissingStaysAsItIsInsteadOfBecomingNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let database = try #require(model.database)
        // No invoice rate, and converted for now at the latest rate there was: with no rate of the day either, a new
        // conversion would be worth 0 Kč.
        var invoice = dollarInvoice(number: "20260903", invoiceRate: nil)
        let stored = Payment(
            date: civilDate("2026-10-07"), conversion: .cnbDaily, czkNetHalere: 2_150_000, czkVatHalere: 0,
            rate: storedRate("USD", "21.500", declaredOn: "2026-09-30"), provisional: true)
        invoice.payment = stored
        let id = try await database.saveInvoice(invoice)
        let version = model.dataVersion

        try await model.recomputePayments(year: nil, in: database)

        #expect(try await database.invoice(id: id)?.payment == stored)
        #expect(model.dataVersion == version)
    }

    @Test func anInvoiceDeletedMeanwhileIsNotBroughtBack() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let database = try #require(model.database)
        var invoice = dollarInvoice(
            number: "20260904", invoiceRate: storedRate("USD", "21.500", declaredOn: "2026-09-30"))
        invoice.payment = PaymentConverter.convert(
            invoice: invoice, date: civilDate("2026-10-07"), requested: .cnbDaily, bankCZKTotalHalere: nil,
            cnbRate: .notYetAvailable, uniformRate: nil)
        let id = try await database.saveInvoice(invoice)
        let listed = try await database.provisionalPayments()
        try await database.deleteInvoice(id: id)
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2026-10-07"), currency: .usd, amount: 1, rate: decimal("21.000"))
        ])

        let saved = try await model.recomputePayments(of: listed, in: database)

        #expect(saved == 0)
        #expect(try await database.invoice(id: id) == nil)
        #expect(try await database.invoiceCount() == 0)
    }

    @Test func anInvoiceEditedAfterItWasListedKeepsTheEdit() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let database = try #require(model.database)
        var invoice = dollarInvoice(
            number: "20260905", invoiceRate: storedRate("USD", "21.500", declaredOn: "2026-09-30"))
        invoice.payment = PaymentConverter.convert(
            invoice: invoice, date: civilDate("2026-10-07"), requested: .cnbDaily, bankCZKTotalHalere: nil,
            cnbRate: .notYetAvailable, uniformRate: nil)
        let id = try await database.saveInvoice(invoice)
        let listed = try await database.provisionalPayments()
        // The editor saves the invoice after the list was read and before the payment is converted again.
        var edited = try #require(try await database.invoice(id: id))
        edited.note = "Opraveno po vystavení."
        try await database.saveInvoice(edited)
        try await database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2026-10-07"), currency: .usd, amount: 1, rate: decimal("21.000"))
        ])

        let saved = try await model.recomputePayments(of: listed, in: database)

        #expect(saved == 0)
        #expect(try await database.invoice(id: id) == edited)
    }

    @Test func aYearThatTurnsToTheUniformRateConvertsItsPaymentsAgainButNotTheBanksAmounts() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let database = try #require(model.database)
        var daily = dollarInvoice(
            number: "20251001", invoiceRate: storedRate("USD", "24.100", declaredOn: "2025-09-30"))
        daily.payment = Payment(
            date: civilDate("2025-10-07"), conversion: .cnbDaily, czkNetHalere: 2_400_000, czkVatHalere: 0,
            rate: storedRate("USD", "24.000", declaredOn: "2025-10-07"))
        var bank = dollarInvoice(number: "20251101", invoiceRate: storedRate("USD", "24.100", declaredOn: "2025-09-30"))
        bank.payment = Payment(
            date: civilDate("2025-11-05"), conversion: .bankCZK, czkNetHalere: 2_350_000, czkVatHalere: 0,
            bankCZKTotalHalere: 2_350_000)
        let crowns = Invoice.fixture(
            number: "20250301", duzp: "2025-03-31", dueDate: "2025-04-14", payment: Payment.fixture(on: "2025-04-03"))
        let dailyID = try await database.saveInvoice(daily)
        let bankID = try await database.saveInvoice(bank)
        let crownsID = try await database.saveInvoice(crowns)
        var settings = try await database.yearSettings(2025)
        settings.incomeFXMethod = .uniform
        try await database.saveYearSettings(settings)
        let version = model.dataVersion

        try await model.recomputePayments(year: 2025, in: database)

        // 1 000 USD at the uniform rate of 2025, 21,84 Kč, which counts as declared on 31 December.
        let converted = try #require(try await database.invoice(id: dailyID)?.payment)
        #expect(converted.conversion == .uniform)
        #expect(converted.rate == storedRate("USD", "21.84", declaredOn: "2025-12-31"))
        #expect(converted.czkNetHalere == 2_184_000)
        #expect(!converted.provisional)
        #expect(try await database.invoice(id: bankID)?.payment == bank.payment)
        #expect(try await database.invoice(id: crownsID)?.payment == crowns.payment)
        #expect(model.dataVersion == version + 1)
    }

    // MARK: The computation

    @Test func theInputOfAYearIsItsReceiptsAndItsSettings() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let database = try #require(model.database)
        let paid = Invoice.fixture(payment: Payment.fixture(on: "2026-10-03"))
        let id = try await database.saveInvoice(paid)
        var settings = try await database.yearSettings(2026)
        settings.expensePercent = 80
        settings.activityFrom = 3
        settings.secondaryMonths = [6]
        settings.healthExemptMonths = [12]
        settings.taxpayerCredit = false
        settings.advances.social[0] = 5_000
        settings.deductions.lifeInsurance = 6_480
        try await database.saveYearSettings(settings)

        let (input, loaded) = try await model.yearInput(for: 2026)

        #expect(loaded == settings)
        #expect(input.year == 2026)
        #expect(
            input.receipts == [
                Receipt(
                    day: civilDate("2026-10-03"), czkNetHalere: 450_000, czkVatHalere: 94_500, source: .invoice(id))
            ])
        #expect(input.expensePercent == 80)
        #expect(input.months == settings.monthActivities())
        #expect(input.healthExemptMonths == [12])
        #expect(input.deductions == settings.deductions)
        #expect(!input.taxpayerCredit)
        #expect(input.advances == settings.advances)
    }

    /// The input of a year holds its family as `Database.family(year:)` lists it, the oldest child first, with the
    /// spouse of the year's settings, and the year is computed with it.
    @Test func theInputOfAYearHoldsItsFamilyAsItIsStored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let database = try #require(model.database)
        // Tomáš is saved and put first; Anna, the older, lives with me until June and is claimed by the other parent.
        try await database.saveChild(
            Child(id: nil, name: "Tomáš", birthDate: civilDate("2024-04-12")), year: 2026,
            childYear: ChildYear(household: MonthRange.wholeYear, claimant: .me, order: 1, ztpp: nil, studies: nil))
        try await database.saveChild(
            Child(id: nil, name: "Anna", birthDate: civilDate("2019-09-03")), year: 2026,
            childYear: ChildYear(
                household: MonthRange(from: 1, to: 6), claimant: .otherParent, order: 2,
                ztpp: MonthRange(from: 3, to: 4), studies: nil))
        let spouse = SpouseYear(claim: true, months: MonthRange(from: 5, to: 12), ownIncomeKc: 12_000, ztpp: nil)
        try await database.saveSpouse(spouse, year: 2026)

        let (input, settings) = try await model.yearInput(for: 2026)

        #expect(settings.spouse == spouse)
        #expect(
            input.family
                == FamilyFacts(
                    children: [
                        ChildFacts(
                            label: "Anna", birthDate: civilDate("2019-09-03"), household: MonthRange(from: 1, to: 6),
                            claimant: .otherParent, order: 2, ztpp: MonthRange(from: 3, to: 4), studies: nil),
                        ChildFacts(
                            label: "Tomáš", birthDate: civilDate("2024-04-12"), household: MonthRange.wholeYear,
                            claimant: .me, order: 1, ztpp: nil, studies: nil),
                    ],
                    spouse: spouse))
        // 2026 as of 17. 10.: Tomáš is the first child the whole year (12 × 1 267 Kč) and the spouse counts from May
        // (8 × 2 070 Kč).
        let result = try await model.computeSelectedYear()
        #expect(result.family.childBenefit == 15_204)
        #expect(result.family.spouseCredit == 16_560)
        // A year before the children's births, without a spouse, has no family.
        #expect(try await model.yearInput(for: 2018).input.family == FamilyFacts())
    }

    /// The input of a year takes the family it is given whole, the children and the spouse together, and not the spouse
    /// of the settings: Zálohy a odpočty computes the spouse being edited with the stored children, and a year without
    /// a family is given an empty one.
    @Test func theInputOfAYearTakesTheWholeFamilyItIsGiven() {
        var settings = YearSettings(year: 2026)
        settings.spouse = SpouseYear(claim: true, months: MonthRange.wholeYear, ownIncomeKc: 0, ztpp: nil)
        let children = FamilyFacts(children: TaxEngineFamilyTests.sampleFamily.children)

        #expect(AppModel.yearInput(settings, receipts: [], family: children).family == children)
        #expect(
            AppModel.yearInput(settings, receipts: [], family: TaxEngineFamilyTests.sampleFamily).family
                == TaxEngineFamilyTests.sampleFamily)
        #expect(AppModel.yearInput(settings, receipts: [], family: FamilyFacts()).family == FamilyFacts())
    }

    @Test(arguments: BrokenYearInput.allCases)
    func aYearInputTheEngineWouldStopOnIsRefused(_ broken: BrokenYearInput) throws {
        var input = AppModel.yearInput(YearSettings(year: 2026), receipts: [], family: FamilyFacts())
        var asOf = civilDate("2026-10-17")
        #expect(throws: Never.self) { try AppModel.compute(input, asOf: asOf) }

        broken.apply(to: &input, asOf: &asOf)

        #expect(throws: ComputationError.invalidYear(2026)) {
            try AppModel.compute(input, asOf: asOf)
        }
    }

    @Test func aReceiptAddsToTheLeviesOfItsYearAsTheYearIsStored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let database = try #require(model.database)
        try await SampleYear2026.store(in: database)
        // The payment of 15. 10. 2026 is stored: its own receipt is the one the effect replaces.
        let stored = try #require(try await database.receipts(year: 2026).first { $0.source == .invoice(11) })

        let effect = try await model.effect(of: stored)

        #expect(effect.tax == 675)
        #expect(effect.social == 723)
        #expect(effect.health == 304)
        #expect(effect.total == 1_702)
        #expect(effect.receipt == stored)

        // Any other receipt is what the engine says of it for the year as it is stored.
        let other = Receipt(day: civilDate("2026-10-16"), czkNetHalere: 1_000_000, czkVatHalere: 0, source: .synthetic)
        let input = try await model.yearInput(for: 2026).input
        #expect(try await model.effect(of: other) == TaxEngine.effect(of: other, in: input))
    }

    @Test func aReceiptOfAYearWithoutRulesOfItsOwnIsAnEstimate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let receipt = Receipt(day: civilDate("2027-01-15"), czkNetHalere: 450_000, czkVatHalere: 0, source: .synthetic)

        let effect = try await model.effect(of: receipt)

        // The rules of the nearest year are used, so there is an answer, and it is the same as for the same income in 2026.
        let sameIn2026 = Receipt(day: civilDate("2026-01-15"), czkNetHalere: 450_000, czkVatHalere: 0, source: .synthetic)
        #expect(effect.total == (try await model.effect(of: sameIn2026)).total)
    }

    @Test(arguments: BrokenYearInput.allCases.filter { $0 != .asOfInAnotherYear })
    func aYearInputTheEngineWouldStopOnIsRefusedBeforeAReceiptsEffectIsWorkedOut(_ broken: BrokenYearInput) throws {
        var input = AppModel.yearInput(YearSettings(year: 2026), receipts: [], family: FamilyFacts())
        var asOf = civilDate("2026-10-17")
        #expect(throws: Never.self) { try AppModel.validate(input) }

        broken.apply(to: &input, asOf: &asOf)

        #expect(throws: ComputationError.invalidYear(2026)) {
            try AppModel.validate(input)
        }
    }

    @Test func theSelectedYearIsComputedAsOfTheDayShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = makeAppModel(in: directory)
        try await startFresh(model)
        let database = try #require(model.database)
        try await database.saveInvoice(Invoice.fixture(payment: Payment.fixture(on: "2026-10-03")))

        model.pickAsOf(civilDate("2026-09-30"))
        let before = try await model.computeSelectedYear()
        model.goToday()
        let after = try await model.computeSelectedYear()

        #expect(before.asOf == civilDate("2026-09-30"))
        #expect(before.incomeHalere == 0)
        #expect(!before.rulesAreEstimate)
        #expect(after.asOf == civilDate("2026-10-17"))
        #expect(after.incomeHalere == 450_000)
        #expect(model.asOf.asOf == civilDate("2026-10-31"))
    }
}

/// A value of a year that the tax engine would stop the app on, each in a year that is otherwise fine.
enum BrokenYearInput: String, CaseIterable, Sendable {
    case asOfInAnotherYear
    case expensesOfFiftyPercent
    case elevenMonthsOfActivity
    case healthExemptThirteenthMonth
    case elevenMonthsOfSocialAdvances
    case negativeHealthAdvance
    case negativeTaxAdvance
    case thirteenMonthsOfMortgage
    case negativeMonthsOfMortgage
    case negativeMortgageInterest
    case negativeLifeInsurance
    case negativePensionSavings
    case negativeDIP
    case negativeLongTermCare
    case negativeGifts
    case childOrderOfZero
    case reversedHouseholdMonths
    case ztppInAThirteenthMonth
    case studiesFromAMonthZero
    case reversedSpouseMonths
    case spouseZTPPInAThirteenthMonth
    case negativeSpouseIncome

    func apply(to input: inout YearInput, asOf: inout CivilDate) {
        switch self {
        case .asOfInAnotherYear: asOf = civilDate("2025-12-31")
        case .expensesOfFiftyPercent: input.expensePercent = 50
        case .elevenMonthsOfActivity: input.months.removeLast()
        case .healthExemptThirteenthMonth: input.healthExemptMonths = [13]
        case .elevenMonthsOfSocialAdvances: input.advances.social.removeLast()
        case .negativeHealthAdvance: input.advances.health[0] = -1
        case .negativeTaxAdvance: input.advances.tax[5] = -1
        case .thirteenMonthsOfMortgage: input.deductions.mortgageMonths = 13
        case .negativeMonthsOfMortgage: input.deductions.mortgageMonths = -1
        case .negativeMortgageInterest: input.deductions.mortgageInterestPaid = -1
        case .negativeLifeInsurance: input.deductions.lifeInsurance = -1
        case .negativePensionSavings: input.deductions.pensionSavings = -1
        case .negativeDIP: input.deductions.dip = -1
        case .negativeLongTermCare: input.deductions.longTermCare = -1
        case .negativeGifts: input.deductions.gifts = -1
        case .childOrderOfZero: input.family.children = [Self.child(order: 0)]
        case .reversedHouseholdMonths: input.family.children = [Self.child(household: MonthRange(from: 8, to: 3))]
        case .ztppInAThirteenthMonth: input.family.children = [Self.child(ztpp: MonthRange(from: 1, to: 13))]
        case .studiesFromAMonthZero: input.family.children = [Self.child(studies: MonthRange(from: 0, to: 6))]
        case .reversedSpouseMonths: input.family.spouse = Self.spouse(months: MonthRange(from: 7, to: 6))
        case .spouseZTPPInAThirteenthMonth: input.family.spouse = Self.spouse(ztpp: MonthRange(from: 12, to: 13))
        case .negativeSpouseIncome: input.family.spouse = Self.spouse(ownIncome: -1)
        }
    }

    /// A child the engine takes but for what is given: in the household the whole year, claimed by me, first.
    private static func child(
        order: Int = 1, household: MonthRange? = MonthRange.wholeYear, ztpp: MonthRange? = nil,
        studies: MonthRange? = nil
    ) -> ChildFacts {
        ChildFacts(
            label: "Anna", birthDate: civilDate("2019-09-03"), household: household, claimant: .me, order: order,
            ztpp: ztpp, studies: studies)
    }

    /// A spouse the engine takes but for what is given: claimed the whole year, without own income and ZTP/P.
    private static func spouse(
        months: MonthRange = MonthRange.wholeYear, ownIncome: Int64 = 0, ztpp: MonthRange? = nil
    ) -> SpouseYear {
        SpouseYear(claim: true, months: months, ownIncomeKc: ownIncome, ztpp: ztpp)
    }
}

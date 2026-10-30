import AppKit
import Foundation
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The sheet Obnovit ze zálohy while the data is open: the local backups to choose from, another file, which code a
/// choice needs, the question about the invoice that is being written, and the restore. A software key protector stands
/// in for the Secure Enclave, and the clock is at noon of 17. 10. 2026. The question is also looked at in the sheet
/// itself, in a window, as VoiceOver reads it. In every expected string `\u{00A0}` is the no-break space.
@Suite(.serialized, .settlesBackups)
@MainActor
struct RestoreSheetModelTests {
    /// The sheet of `app` with the local backups listed.
    private func loadedSheet(of app: AppModel) -> RestoreSheetModel {
        app.showSettings(.security)
        let security = SecurityTabModel(app: app)
        security.load()
        let sheet = RestoreSheetModel(app: app, security: security)
        sheet.load()
        return sheet
    }

    @Test func theLocalBackupsAreListedNewestFirstByTheirDayAndWhatTheyHold() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 15))
        let app = try await makeSettingsApp(in: directory, clock: clock)
        let database = try #require(app.database)
        try await database.saveInvoice(Invoice.fixture())
        await app.didWriteAndBackUp()
        clock.set(localNoon(2026, 10, 16) + 9 * 60 * 60 + 14 * 60)
        try await database.saveInvoice(Invoice.fixture(number: "20260902"))
        await app.didWriteAndBackUp()
        clock.set(localNoon(2026, 10, 17) + 2 * 60 * 60 + 5 * 60)
        try await database.saveInvoice(Invoice.fixture(number: "20260903"))
        await app.didWriteAndBackUp()
        app.handleDayChanged(civilDate("2026-10-17"))

        let sheet = loadedSheet(of: app)

        #expect(sheet.choices.map(\.title) == ["Dnes 14:05", "Včera 21:14", "15.\u{00A0}10.\u{00A0}2026 12:00"])
        #expect(
            sheet.choices.map(\.subtitle) == [
                "automatická záloha v tomto Macu · 3 faktury", "automatická záloha v tomto Macu · 2 faktury",
                "automatická záloha v tomto Macu · 1 faktura",
            ])
        #expect(sheet.selection == nil)
        #expect(!sheet.canRestore)
    }

    @Test func aLocalBackupOpensWithThisMacAndIsRestoredWithoutACode() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = try await makeSettingsApp(in: directory, clock: clock)
        let database = try #require(app.database)
        try await database.saveInvoice(Invoice.fixture())
        await app.didWriteAndBackUp()
        try await database.saveInvoice(Invoice.fixture(number: "20260902"))
        clock.advance(by: 60)
        let sheet = loadedSheet(of: app)
        let choice = try #require(sheet.choices.first)

        await sheet.select(choice)

        #expect(!sheet.needsCode)
        #expect(sheet.canRestore)
        #expect(sheet.summary == "Obnoví se stav ze zálohy „Dnes 12:00“.")
        #expect(sheet.keyText == "Otevře se přes Touch ID tohoto Macu, kód není potřeba.")

        #expect(await sheet.restore())

        #expect(try await #require(app.database).invoiceCount() == 1)
        #expect(
            app.banner?.text == "Data jsou obnovená ze zálohy „Dnes 12:00“. Předchozí stav je uložený jako záloha.")
    }

    @Test func obnovitCannotBePressedWhileABackupStartedElsewhereRuns() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeSettingsApp(in: directory)
        try await #require(app.database).saveInvoice(Invoice.fixture())
        await app.didWriteAndBackUp()
        let sheet = loadedSheet(of: app)
        await sheet.select(try #require(sheet.choices.first))
        #expect(sheet.canRestore)

        let backup = Task.immediate { try await app.backUpNow() }

        #expect(!sheet.canRestore)
        _ = try await backup.value
        #expect(sheet.canRestore)
    }

    @Test func anotherFileThatThisMacCannotOpenAsksForItsNamedCode() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let other = try await makeBackupOfAnotherMac(in: directory, invoices: 3)
        let app = try await makeSettingsApp(in: directory)
        let sheet = loadedSheet(of: app)

        await sheet.chooseFile(other.url)

        let choice = try #require(sheet.selection)
        #expect(choice.title == other.url.lastPathComponent)
        #expect(choice.subtitle == "soubor z jiného Macu · potřebuje " + other.label)
        #expect(sheet.needsCode)
        #expect(sheet.keyText == "Záloha vznikla na jiném Macu – odemkne ji " + other.label + ".")
        #expect(sheet.codeFieldLabel == "Kód pro obnovení – " + other.label)
        #expect(!sheet.canRestore)

        sheet.typed = "7777-7777-7777-7777-7777-7777-7777-7777"
        #expect(sheet.canRestore)
        #expect(!(await sheet.restore()))
        #expect(sheet.errorText == "Kód nesedí – tahle záloha potřebuje " + other.label + ".")
        #expect(app.phase == .ready)
        #expect(try await #require(app.database).invoiceCount() == 0)

        sheet.typed = other.code
        #expect(await sheet.restore())
        #expect(try await #require(app.database).invoiceCount() == 3)
    }

    /// An app whose data got a new key after its first local backup, so that this backup opens only with the device
    /// slot it carries, which the device key of this Mac takes for its own, or with code no. 1. Returns the app, the
    /// first code and the device key, which a test makes fail.
    private func appWithAnOlderBackup(
        in directory: URL
    ) async throws -> (app: AppModel, firstCode: String, device: ScriptedKeyProtector) {
        let device = ScriptedKeyProtector()
        let app = makeAppModel(in: directory, device: device)
        let firstCode = try await startFresh(app)
        try await #require(app.database).saveInvoice(Invoice.fixture())
        await app.didWriteAndBackUp()
        let security = SecurityTabModel(app: app)
        security.load()
        try await security.commitNewCode(try security.createNewCode())
        try await #require(app.database).saveInvoice(Invoice.fixture(number: "20260902"))
        return (app, firstCode, device)
    }

    @Test func aLocalBackupWhoseDeviceSlotDoesNotOpenAsksForItsCodeInWordsOfItsOwn() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, firstCode, device) = try await appWithAnOlderBackup(in: directory)
        device.openFailure = .deviceKeyUnusable
        let sheet = loadedSheet(of: app)
        let older = try #require(sheet.choices.first { $0.header.keys.newestRecoverySlot?.number == 1 })
        await sheet.select(older)
        #expect(!sheet.needsCode)

        #expect(!(await sheet.restore()))

        #expect(sheet.needsCode)
        #expect(sheet.errorText == nil)
        #expect(
            sheet.keyText
                == "Klíč tohoto Macu tuhle zálohu neotevřel – odemkne ji kód č. 1 z 17.\u{00A0}10.\u{00A0}2026.")
        sheet.typed = firstCode
        #expect(await sheet.restore())
        #expect(try await #require(app.database).invoiceCount() == 1)
    }

    @Test func aDismissedTouchIDPromptSaysNothingAndChangesNothing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let (app, _, device) = try await appWithAnOlderBackup(in: directory)
        let database = try #require(app.database)
        device.openFailure = .userCancelled
        let sheet = loadedSheet(of: app)
        let older = try #require(sheet.choices.first { $0.header.keys.newestRecoverySlot?.number == 1 })
        await sheet.select(older)

        #expect(!(await sheet.restore()))

        #expect(sheet.errorText == nil)
        #expect(!sheet.needsCode)
        #expect(app.phase == .ready)
        #expect(app.database === database)
        #expect(try await database.invoiceCount() == 2)
        #expect(app.vault.keys?.newestRecoverySlot?.number == 2)
        #expect(app.banner == nil)
    }

    @Test func anInvoiceBeingWrittenIsDiscardedOnlyAfterTheQuestion() async throws {
        try await EditorFixture.with { f in
            let app = f.app
            app.startNewInvoice(templateID: f.crownTemplate.id)
            await app.openEditor()
            let editor = try #require(app.editor)
            editor.note = "Rozepsaná poznámka"
            #expect(app.editorHasChanges)
            let sheet = loadedSheet(of: app)
            let choice = try #require(sheet.choices.first)
            await sheet.select(choice)

            #expect(!(await sheet.restore()))
            #expect(sheet.asksToDiscard)
            #expect(app.editor != nil)

            sheet.discard()
            #expect(await sheet.restore())
            #expect(app.editorRequest == nil)
            #expect(app.editor == nil)
            #expect(!sheet.asksToDiscard)
            #expect(app.phase == .ready)
        }
    }

    /// Obnovit with an invoice being written asks "Zahodit rozepsanou fakturu?" in a red box of the sheet, in place of
    /// its buttons, with no dialog over the sheet. Pokračovat v úpravách leaves the invoice as it was and restores
    /// nothing; Zahodit throws it away and restores the backup, and the sheet closes. The window of the sheet is made
    /// the key window, which takes the keyboard from the window of another test, so the test takes its turn among the
    /// tests that type into a window (`whileTypingAlone`).
    @Test func theQuestionAboutAnInvoiceBeingWrittenIsABoxOfTheSheet() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                let app = f.app
                app.startNewInvoice(templateID: f.crownTemplate.id)
                await app.openEditor()
                let editor = try #require(app.editor)
                editor.note = "Rozepsaná poznámka"
                app.showSettings(.security)
                let security = SecurityTabModel(app: app)
                security.load()
                let calls = Calls()
                let sheet = RestoreSheet(app: app, security: security) { calls.closed += 1 }

                try await withHostedView(sheet, size: CGSize(width: 600, height: 760)) { window in
                    try await withAccessibilityElements {
                        try await chooseTheNewestBackupAndRestore(in: window)

                        try await waitUntil { asksTheQuestion(in: window) }
                        #expect(window.attachedSheet == nil)
                        #expect(accessibilityButton(labelled: "Obnovit", in: window) == nil)
                        #expect(app.editor === editor)

                        let keepEditing = accessibilityButton(labelled: "Pokračovat v úpravách", in: window)
                        #expect(try #require(keepEditing).accessibilityPerformPress?() == true)
                        try await waitUntil { !asksTheQuestion(in: window) }
                        #expect(app.pendingDiscard == nil)
                        #expect(app.editor === editor)
                        #expect(editor.note == "Rozepsaná poznámka")
                        #expect(calls.closed == 0)

                        try await pressRestore(in: window)
                        try await waitUntil { asksTheQuestion(in: window) }
                        let discard = try #require(accessibilityButton(labelled: "Zahodit", in: window))
                        #expect(discard.accessibilityPerformPress?() == true)
                        try await waitUntil { calls.closed == 1 }
                        #expect(app.editor == nil)
                        #expect(app.phase == .ready)
                    }
                }
            }
        }
    }

    // MARK: The sheet in a window

    /// What the sheet was told to do.
    private final class Calls {
        var closed = 0
    }

    /// Chooses the newest local backup in the sheet in `window`, as a click on it chooses it, and presses Obnovit once
    /// it can be pressed.
    private func chooseTheNewestBackupAndRestore(in window: NSWindow) async throws {
        try await waitUntil { newestBackup(in: window) != nil }
        #expect(try #require(newestBackup(in: window)).accessibilityPerformPress?() == true)
        try await pressRestore(in: window)
    }

    /// Presses Obnovit in the sheet in `window` once it can be pressed.
    private func pressRestore(in window: NSWindow) async throws {
        try await waitUntil { accessibilityButton(labelled: "Obnovit", in: window)?.isAccessibilityEnabled?() == true }
        #expect(try #require(accessibilityButton(labelled: "Obnovit", in: window)).accessibilityPerformPress?() == true)
    }

    /// Whether the sheet in `window` asks "Zahodit rozepsanou fakturu?".
    private func asksTheQuestion(in window: NSWindow) -> Bool {
        frameOfText(startingWith: "Zahodit rozepsanou fakturu?", in: window) != nil
    }

    /// The first backup of the list "Zálohy" in `window`, which is the newest one, as VoiceOver reads it: a button.
    private func newestBackup(in window: NSWindow) -> AnyObject? {
        guard let list = accessibilityElement(labelled: "Zálohy", in: window) else { return nil }
        return firstButton(among: list.accessibilityChildren?() ?? [])
    }

    /// The first button among `elements` and their children, in the order of the tree.
    private func firstButton(among elements: [Any]) -> AnyObject? {
        for item in elements {
            let element = item as AnyObject
            if element.accessibilityRole?() == .button {
                return element
            }
            if let found = firstButton(among: element.accessibilityChildren?() ?? []) {
                return found
            }
        }
        return nil
    }
}

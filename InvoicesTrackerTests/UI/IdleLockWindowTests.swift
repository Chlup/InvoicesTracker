import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The window of the app while the app is locked after inactivity, made as the app makes it, on the data of
/// `EditorFixture`: Touch ID is on, the app locks after the 10 minutes of the default, and the prompt of Touch ID says
/// yes. The window then shows the lock card alone — no sidebar, page, toolbar or title — and VoiceOver reads nothing
/// else; a sheet or a dialog that is open is covered as well and keeps what was typed in it; no key reaches what is
/// under the lock; what the window would say meanwhile waits; the commands of the menu that act on the data are
/// disabled; and once Odemknout has proved the owner, the window is where it was. The window watches the activity in
/// the app while it shows.
///
/// The lock comes when a test checks it, 10 minutes of the app's clock after the data was opened. The cards, the fields
/// and the buttons are found and pressed as VoiceOver finds and presses them, and a test that types, or tells where the
/// focus is, takes its turn among the tests that type into a window (`whileTypingAlone`). One window at a time, so that
/// what a test sees settle is its own window.
@Suite(.serialized, .settlesBackups)
@MainActor
struct IdleLockWindowTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// The title of the card of the lock after inactivity: the name of the app, as the lock of a launch has it.
    private static let lockTitle = "InvoicesTracker je zamčený"

    /// The invoice 20260901 of `EditorFixture`, paid in dollars by Bravo.
    private static let invoiceID: Int64 = 10
    private static let invoiceNumber = "20260901"

    /// A line that says what went wrong, as a view shows it under what it was about.
    enum FailureLine: Sendable {
        /// In Nastavení, or in a sheet such as that of a new recovery code (`SettingsFailureLine`).
        case settings

        /// Under the field of a recovery code, as in the sheet of a restore (`WelcomeErrorLine`).
        case recoveryCode

        /// The line with `text`, in the window of `app`.
        @MainActor
        @ViewBuilder
        func view(_ text: String, of app: AppModel) -> some View {
            switch self {
            case .settings: SettingsFailureLine(text: text).environment(app)
            case .recoveryCode: WelcomeErrorLine(text: text).environment(app)
            }
        }
    }

    /// Whether a monitor of the test saw the event it waits for.
    @MainActor
    private final class Seen {
        var event = false
    }

    // MARK: The window

    @Test func theLockedWindowShowsOnlyTheLockCard() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.openInvoice(Self.invoiceID)
                try await withAccessibilityElements {
                    try await waitUntil { detailShows(Self.invoiceNumber, in: window) }
                    // What the lock is to hide is there to read before it comes: the sidebar with Nastavení at its
                    // foot, and the invoices.
                    let before = accessibilityReadings(in: window)
                    #expect(before.contains("Boční panel") && before.contains(Screen.settings.title))
                    #expect(!visibleToolbarItems(of: window).isEmpty)

                    try lock(f)

                    try await waitUntil { showsTheLock(in: window) }
                    let readings = accessibilityReadings(in: window)
                    #expect(
                        readings.contains(
                            "Zamkl se po 10\u{00A0}minutách nečinnosti a data skryl. Odemknete ho přes Touch ID nebo"
                                + " heslem k tomuto Macu."))
                    #expect(
                        readings.contains(
                            "Po odemčení budete tam, kde jste skončili. Dobu do zamčení změníte v Nastavení ›"
                                + " Zabezpečení a zálohy."))
                    #expect(accessibilityButton(labelled: "Odemknout", in: window) != nil)
                    // The Mac password always unlocks this lock: it has no way to the recovery code.
                    #expect(!readings.contains("Odemknout kódem pro obnovení…"))
                    #expect(!readings.contains { $0.contains(Self.invoiceNumber) }, "The lock reads \(readings)")
                    #expect(!readings.contains("Boční panel"))
                    for screen in Screen.allCases {
                        #expect(!readings.contains(screen.title), "The lock reads the item \(screen.title)")
                    }
                    // The window follows with its title bar a moment after its content.
                    try await waitUntil { window.title.isEmpty && window.subtitle.isEmpty }
                    try await waitUntil { visibleToolbarItems(of: window).isEmpty }
                }
            }
        }
    }

    /// The form of a new client, with "Acme" typed into its name and "cm" selected in it, is covered by the lock, which
    /// the sheet shows in its place with Odemknout of its own: the window's card is under the sheet, out of reach while
    /// the sheet is up. The field gives up the focus at the lock itself, before the window has followed it. Once
    /// unlocked, the sheet is there with the name as it was typed, and the focus is back in it with "cm" selected.
    @Test func anOpenSheetIsCoveredAndKeepsItsTypedText() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                    try await withAccessibilityElements {
                        let sheet = try await openNewClientForm(of: f.app, in: window)
                        let name = try await nameField(in: sheet)
                        try type("Acme", into: name, in: sheet)
                        try await waitUntil { accessibilityReadings(in: sheet).contains("Acme") }
                        let typing = try #require(name.currentEditor() as? NSTextView)
                        typing.setSelectedRange(NSRange(location: 1, length: 2))
                        // The sheet has the lock over it, as every sheet of the app is to have.
                        #expect(IdleLockSheets.guarded.contains(sheet))

                        try lock(f)

                        #expect(!hasFocus(name, in: sheet), "The field kept the focus until the window followed")
                        try await waitUntil { showsTheLock(in: sheet) }
                        #expect(!accessibilityReadings(in: sheet).contains { $0.contains("Acme") })
                        #expect(!hasFocus(name, in: sheet))
                        #expect(window.sheets.first === sheet)

                        try pressButton("Odemknout", in: sheet)

                        try await waitUntil { !f.app.isIdleLocked }
                        try await waitUntil { accessibilityReadings(in: sheet).contains("Acme") }
                        #expect(name.stringValue == "Acme")
                        try await waitUntil { hasFocus(name, in: sheet) }
                        let editor = try #require(name.currentEditor() as? NSTextView)
                        #expect(editor.selectedRange() == NSRange(location: 1, length: 2))
                    }
                }
            }
        }
    }

    /// On a sheet under the lock, Esc closes nothing, as the hidden Zrušit takes no key, and Return is the Odemknout of
    /// the lock, not the hidden Uložit odběratele: the sheet stays open, and nothing is saved.
    @Test func returnOnALockedSheetUnlocksItAndEscLeavesItOpen() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.large) { window in
                    try await withAccessibilityElements {
                        let sheet = try await openNewClientForm(of: f.app, in: window)
                        try type("Acme", into: try await nameField(in: sheet), in: sheet)
                        try lock(f)
                        try await waitUntil { showsTheLock(in: sheet) }
                        try await untilTheWindowHasCaughtUp(sheet)

                        try pressKey("\u{1B}", keyCode: 53, in: sheet)
                        try await layOut(sheet)

                        #expect(window.sheets.first === sheet)
                        #expect(f.app.isIdleLocked)

                        #expect(try press(.return, in: sheet))

                        try await waitUntil { !f.app.isIdleLocked }
                        try await layOut(sheet)
                        #expect(window.sheets.first === sheet)
                        #expect(try await f.database.clients().contains { $0.name == "Acme" } == false)
                    }
                }
            }
        }
    }

    /// The dialog of the window that deletes an invoice, with "2026" typed into it, is under the lock too: VoiceOver
    /// does not read it, Esc does not close it, its field gives up the focus, the dialog, disabled under the lock, does
    /// not take it back, and Tab brings it to nothing under the lock. Once unlocked, the dialog is there with what was
    /// typed, and the focus is back in its field.
    @Test func aDialogOfTheWindowIsCoveredAndGivesUpTheFocus() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    window.makeKeyAndOrderFront(nil)
                    try await withAccessibilityElements {
                        let question = "Smazat fakturu \(Self.invoiceNumber)?"
                        f.app.openInvoice(Self.invoiceID)
                        try await waitUntil { accessibilityButton(labelled: "Smazat fakturu…", in: window) != nil }
                        try pressButton("Smazat fakturu…", in: window)
                        try await waitUntil { frameOfText(startingWith: question, in: window) != nil }
                        try await waitUntil { numberField(in: window).map { hasFocus($0, in: window) } ?? false }
                        let field = try #require(numberField(in: window))
                        try type("2026", into: field, in: window)

                        try lock(f)

                        #expect(!hasFocus(field, in: window), "The field kept the focus until the window followed")
                        try await waitUntil { showsTheLock(in: window) }
                        #expect(frameOfText(startingWith: question, in: window) == nil)
                        try await untilTheWindowHasCaughtUp(window)
                        try pressKey("\u{1B}", keyCode: 53, in: window)
                        for _ in 0..<3 {
                            try await layOut(window)
                            #expect(focusUnderTheLock(in: window) == nil)
                            try pressKey("\t", keyCode: 48, in: window)
                        }
                        try await layOut(window)
                        #expect(focusUnderTheLock(in: window) == nil)

                        try pressButton("Odemknout", in: window)

                        try await waitUntil { !f.app.isIdleLocked }
                        try await waitUntil { frameOfText(startingWith: question, in: window) != nil }
                        try await waitUntil { hasFocus(field, in: window) }
                        #expect(field.stringValue == "2026")
                    }
                }
            }
        }
    }

    /// The menu of the rate capsule, which shows the levies of the year, closes when the app locks.
    @Test func theMenuOfTheRateCapsuleClosesWhenTheAppLocks() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    let capsule = "Přepočet cizích měn v roce 2026: denní kurz ČNB"
                    try await waitUntil { accessibilityButton(labelled: capsule, in: window) != nil }
                    try pressButton(capsule, in: window)
                    try await waitUntil { rateMenu(of: window) != nil }
                    let menu = try #require(rateMenu(of: window))

                    try lock(f)

                    try await waitUntil { !menu.isVisible }
                    #expect(rateMenu(of: window) == nil)
                }
            }
        }
    }

    /// The current toolbar is hidden under the idle lock, keyboard navigation stays on the lock, and unlocking
    /// restores its working year and invoice actions without changing the reporting cutoff.
    @Test func theToolbarActionsAreCoveredUntilTheAppUnlocks() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                    try await withAccessibilityElements {
                        try await waitUntil { yearMenu(in: window)?.isAccessibilityEnabled?() == true }
                        try await waitUntil { accessibilityButton(labelled: "Nová faktura", in: window) != nil }
                        let cutoff = f.app.asOf

                        try lock(f)

                        try await waitUntil { showsTheLock(in: window) }
                        #expect(yearMenu(in: window) == nil)
                        #expect(accessibilityButton(labelled: "Nová faktura", in: window) == nil)
                        for _ in 0..<3 {
                            try pressKey("\t", keyCode: 48, in: window)
                            try await layOut(window)
                            #expect(focusUnderTheLock(in: window) == nil)
                            #expect(showsTheLock(in: window))
                        }
                        #expect(f.app.asOf == cutoff)
                        #expect(f.app.editorRequest == nil)

                        try pressButton("Odemknout", in: window)

                        try await waitUntil { !f.app.isIdleLocked }
                        try await waitUntil { yearMenu(in: window)?.isAccessibilityEnabled?() == true }
                        try await waitUntil {
                            accessibilityButton(labelled: "Nová faktura", in: window)?.isAccessibilityEnabled?() == true
                        }
                        #expect(f.app.asOf == cutoff)
                    }
                }
            }
        }
    }

    // MARK: The card after unlocking

    /// The card after unlocking with the recovery code, which is over the app until Pokračovat, is under the lock too,
    /// and is there again once the app is unlocked.
    @Test func theCardAfterUnlockingWithTheCodeIsCoveredToo() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    await f.app.open(f.database, completing: UnlockCompletion(kind: .unlocked, codeLabel: nil))
                    try await waitUntil { accessibilityReadings(in: window).contains("Odemčeno") }
                    #expect(accessibilityButton(labelled: "Pokračovat", in: window) != nil)

                    try lock(f)

                    try await waitUntil { showsTheLock(in: window) }
                    let readings = accessibilityReadings(in: window)
                    #expect(!readings.contains("Odemčeno"), "The lock reads \(readings)")
                    #expect(accessibilityButton(labelled: "Pokračovat", in: window) == nil)

                    try pressButton("Odemknout", in: window)

                    try await waitUntil { !f.app.isIdleLocked }
                    try await waitUntil { accessibilityReadings(in: window).contains("Odemčeno") }
                    #expect(f.app.completion != nil)
                }
            }
        }
    }

    // MARK: The menu bar

    @Test func dataCommandsAreDisabledWhileLocked() async throws {
        try await EditorFixture.with { f in
            f.app.screen = .invoices
            let unlocked = AppCommands(model: f.app)
            // Nová faktura and Importovat…, Exportovat zálohu… and Obnovit ze zálohy…, and Hledat.
            #expect(unlocked.offersTheApp)
            #expect(unlocked.offersTheBackups)
            #expect(unlocked.offersSearch)

            try lock(f)

            let locked = AppCommands(model: f.app)
            #expect(!locked.offersTheApp)
            #expect(!locked.offersTheBackups)
            #expect(!locked.offersSearch)
            // ⌘F finds nothing to focus under the lock.
            f.app.focusSearch()
            #expect(f.app.searchFocusRequests == 0)

            await f.app.unlockAfterIdle()

            let again = AppCommands(model: f.app)
            #expect(again.offersTheApp && again.offersTheBackups && again.offersSearch)
        }
    }

    // MARK: After unlocking

    /// Faktury with the detail of 20260901 open and its rows scrolled: after the lock and Odemknout, the window shows
    /// the same screen, the same detail and the rows where they were.
    @Test func afterUnlockingTheScreenIsWhereItWas() async throws {
        try await EditorFixture.with { f in
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                f.app.openInvoice(Self.invoiceID)
                try await withAccessibilityElements {
                    try await waitUntil { detailShows(Self.invoiceNumber, in: window) }
                    try await layOut(window)
                    let rows = try #require(scrollingRows(in: window))
                    let top = rows.contentView.bounds.origin.y
                    let down: CGFloat = rows.documentView?.isFlipped == false ? -60 : 60
                    rows.contentView.scroll(to: NSPoint(x: rows.contentView.bounds.origin.x, y: top + down))
                    rows.reflectScrolledClipView(rows.contentView)
                    try await layOut(window)
                    let offset = rows.contentView.bounds.origin.y
                    #expect((offset - top).magnitude > 30, "The rows did not scroll: \(top) → \(offset)")

                    try lock(f)
                    try await waitUntil { showsTheLock(in: window) }
                    try await layOut(window)
                    try pressButton("Odemknout", in: window)

                    try await waitUntil { !f.app.isIdleLocked }
                    try await waitUntil { detailShows(Self.invoiceNumber, in: window) }
                    try await layOut(window)
                    #expect(f.app.screen == .invoices)
                    #expect(window.title == Screen.invoices.title)
                    #expect(rows.window === window)
                    #expect(
                        (rows.contentView.bounds.origin.y - offset).magnitude <= 1,
                        "The rows were at \(offset) and are at \(rows.contentView.bounds.origin.y)")
                }
            }
        }
    }

    // MARK: What waits for the unlock

    /// A banner that comes while the app is locked, as one of a step that ended under the lock, is under the cover:
    /// VoiceOver is told of it once the app is unlocked, not while the lock hides it.
    @Test func aBannerThatComesUnderTheLockIsToldOnceTheAppIsUnlocked() async throws {
        try await EditorFixture.with { f in
            var announced: [String] = []
            f.app.announce = { announced.append($0) }
            try await withAppWindow(of: f.app, size: AppWindowSize.minimum) { window in
                try await withAccessibilityElements {
                    try lock(f)
                    try await waitUntil { showsTheLock(in: window) }

                    f.app.showBanner("Záloha uložena v tomto Macu.")
                    try await layOut(window)

                    #expect(announced.isEmpty)

                    try pressButton("Odemknout", in: window)

                    try await waitUntil { !f.app.isIdleLocked }
                    try await waitUntil { announced == ["Záloha uložena v tomto Macu."] }
                }
            }
        }
    }

    /// A line of a failure that appears under the lock — in Nastavení or a sheet (`SettingsFailureLine`), or under the
    /// field of a recovery code in the sheet of a restore (`WelcomeErrorLine`) — is told to VoiceOver once the app is
    /// unlocked; with the app unlocked, at once.
    @Test(arguments: [FailureLine.settings, .recoveryCode])
    func aLineOfAFailureIsToldOnlyWhileTheAppIsUnlocked(line: FailureLine) async throws {
        try await EditorFixture.with { f in
            var announced: [String] = []
            f.app.announce = { announced.append($0) }
            try lock(f)

            try await withHostedView(line.view("Zálohu se nepodařilo uložit.", of: f.app)) { window in
                try await layOut(window)
                #expect(announced.isEmpty)
                await f.app.unlockAfterIdle()
                #expect(announced == ["Zálohu se nepodařilo uložit."])
            }

            try await withHostedView(line.view("Kurz se nepodařilo uložit.", of: f.app)) { _ in
                try await waitUntil { announced.count == 2 }
                #expect(announced.last == "Kurz se nepodařilo uložit.")
            }
        }
    }

    /// The summary of an import that ends under the lock, as an import goes on while the app is locked, is told to
    /// VoiceOver once the app is unlocked. The import is the invented sample of Fakturoid.
    @Test func theSummaryOfAnImportThatEndsUnderTheLockIsToldOnceTheAppIsUnlocked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let http = StubHTTPClient([CNBEndpoints.yearly(2026): try Data(contentsOf: fixtureURL("cnb_rok_2026", "txt"))])
        let app = makeAppModel(in: directory, clock: clock, http: http)
        try await startFresh(app)
        var announced: [String] = []
        app.announce = { announced.append($0) }
        try await withAppWindow(of: app, size: AppWindowSize.minimum) { window in
            try await withAccessibilityElements {
                app.screen = .importer
                try await waitUntil { window.title == "Import faktur" }
                clock.advance(by: 10 * 60)
                app.checkIdleLock(now: clock.now())
                try #require(app.isIdleLocked)
                try await waitUntil { showsTheLock(in: window) }

                await app.importModel.importFiles([try fixtureURL("fakturoid_sample", "csv")])
                let summary = app.importModel.summaryLines.joined(separator: " ")
                try #require(!summary.isEmpty)
                try await layOut(window)

                #expect(!announced.contains(summary))

                try pressButton("Odemknout", in: window)

                try await waitUntil { !app.isIdleLocked }
                try await waitUntil { announced.contains(summary) }
            }
        }
    }

    // MARK: The activity

    /// While its window shows, a move of the pointer in the app is activity, from which the lock counts; once the
    /// window is gone, nothing watches the activity in the app any more.
    @Test func theWindowWatchesTheActivityInTheAppWhileItShows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let clock = ManualClock(localNoon(2026, 10, 17))
        let app = makeAppModel(in: directory, clock: clock, startsIdleChecks: true)
        try await startFresh(app)

        try await withAppWindow(of: app, size: AppWindowSize.minimum) { _ in
            try await waitUntil { try await aMoveOfThePointerIsNoted(by: app, clock: clock) }
        }

        try await waitUntil { try await !aMoveOfThePointerIsNoted(by: app, clock: clock) }
        #expect(!app.isIdleLocked)
    }

    // MARK: Nastavení › Zabezpečení a zálohy

    /// The card Odemykání: the checkbox of Touch ID with what it does now, the menu of the time of the lock with what
    /// the lock does, and the note on the keys. The menu shows the time chosen. Without Touch ID the menu is disabled
    /// and says why. The menu is read as VoiceOver reads it.
    @Test func zabezpečeníOffersTheTimeOfTheLockWhileTouchIDIsOn() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        try await startFresh(app)

        try await withHostedView(SecurityTab(app: app), size: CGSize(width: 1_000, height: 900)) { window in
            try await withAccessibilityElements {
                try await waitUntil { idleLockMenu(in: window) != nil }
                let menu = try #require(idleLockMenu(in: window))
                let readings = accessibilityReadings(in: window)
                for text in [
                    "Odemykat přes Touch ID",
                    "Aplikace se zeptá na Touch ID nebo heslo k Macu při spuštění a po nečinnosti.",
                    "Zamknout při nečinnosti",
                    "Zamčená aplikace skryje všechna data. Po odemčení budete tam, kde jste skončili – i s rozepsanou"
                        + " fakturou.",
                    "Data jsou zašifrovaná vždy; klíč k nim chrání Secure Enclave tohoto Macu. Zapnutí nebo vypnutí"
                        + " Touch ID dá datům nový klíč a hned uloží zálohu.",
                ] {
                    #expect(readings.contains { $0.contains(text) }, "Nastavení does not read \(text)")
                }
                #expect(menu.isAccessibilityEnabled?() == true)
                #expect(value(of: menu) == "Po 10 minutách")

                await SecurityTabModel(app: app).setIdleLock(.oneMinute)

                try await waitUntil { value(of: menu) == "Po 1 minutě" }

                _ = try await app.setTouchID(false)

                try await waitUntil { menu.isAccessibilityEnabled?() == false }
                try await waitUntil {
                    accessibilityReadings(in: window).contains("Bez odemykání přes Touch ID se aplikace nezamyká.")
                }
            }
        }
    }

    // MARK: Helpers

    /// Locks the app of `f` after inactivity: its clock moves on by the 10 minutes of the default without any activity,
    /// and the check runs.
    private func lock(_ f: EditorFixture) throws {
        f.clock.advance(by: 10 * 60)
        f.app.checkIdleLock(now: f.clock.now())
        try #require(f.app.isIdleLocked)
    }

    /// The items of the toolbar of `window` that are on screen: none while the toolbar is hidden.
    private func visibleToolbarItems(of window: NSWindow) -> [NSToolbarItem] {
        guard let toolbar = window.toolbar, toolbar.isVisible else { return [] }
        return toolbar.visibleItems ?? []
    }

    /// Waits until `window` has caught up with the lock in its views as a person sees them: VoiceOver's tree follows
    /// the lock at once, the keyboard shortcuts of the window only when the window has been laid out again, which it
    /// has long before a person can press a key.
    private func untilTheWindowHasCaughtUp(_ window: NSWindow) async throws {
        try await layOut(window)
    }

    /// Whether `window` shows the card of the lock after inactivity, as VoiceOver reads its title.
    private func showsTheLock(in window: NSWindow) -> Bool {
        accessibilityReadings(in: window).contains(Self.lockTitle)
    }

    /// Presses the button that VoiceOver reads as `label` in `window`, as VoiceOver presses it. What the press answers
    /// is not looked at: a button that opens a popover answers that it did nothing. The test waits for what the press
    /// does.
    private func pressButton(_ label: String, in window: NSWindow) throws {
        let button = try #require(accessibilityButton(labelled: label, in: window), "No button \(label)")
        _ = button.accessibilityPerformPress?()
    }

    /// Whether the card of the detail of an invoice in `window` reads `number`.
    private func detailShows(_ number: String, in window: NSWindow) -> Bool {
        guard let card = accessibilityElement(labelled: "Detail faktury", in: window) else { return false }
        return accessibilityReadings(under: card).contains(number)
    }

    /// Shows Odběratelé in `window` and opens the form of a new client with Nový odběratel: the sheet it is in.
    private func openNewClientForm(of app: AppModel, in window: NSWindow) async throws -> NSWindow {
        app.screen = .clients
        try await waitUntil { accessibilityButton(labelled: "Nový odběratel", in: window) != nil }
        try pressButton("Nový odběratel", in: window)
        try await waitUntil { window.sheets.count == 1 }
        return try #require(window.sheets.first)
    }

    /// The field Název of the form of a client in `sheet`, once it is there as a text field of AppKit.
    private func nameField(in sheet: NSWindow) async throws -> NSTextField {
        try await waitUntil { textField(labelled: "Název", in: sheet) != nil }
        return try #require(textField(labelled: "Název", in: sheet))
    }

    /// The field of the dialog that deletes an invoice in `window`, where its number is typed.
    private func numberField(in window: NSWindow) -> NSTextField? {
        guard let content = window.contentView else { return nil }
        return editableTextFields(in: content).first { $0.placeholderString == "Číslo faktury" }
    }

    /// Types `text` into `field` as a person does: the field takes the focus and its text is replaced, and the change
    /// reaches the binding as the keys do.
    private func type(_ text: String, into field: NSTextField, in window: NSWindow) throws {
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    /// Whether `field` has the keyboard focus in `window`: its field editor is the first responder.
    private func hasFocus(_ field: NSTextField, in window: NSWindow) -> Bool {
        field.currentEditor() != nil && window.firstResponder === field.currentEditor()
    }

    /// Presses the key with `keyCode`, which types `characters`, as the keyboard does: a key-down event handed to
    /// `window`, to the view that has the focus.
    private func pressKey(_ characters: String, keyCode: UInt16, in window: NSWindow) throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
        window.sendEvent(event)
    }

    /// What has the keyboard focus of `window` under the lock: a field that is typed in, a control that the lock
    /// disabled, or a list such as the one of the sidebar. Nil while the window itself or the lock card has it.
    private func focusUnderTheLock(in window: NSWindow) -> String? {
        guard let responder = window.firstResponder else { return nil }
        if let editor = responder as? NSTextView, editor.isFieldEditor {
            return "the field editor of \(String(describing: editor.delegate))"
        }
        if responder is NSTableView {
            return "\(Swift.type(of: responder))"
        }
        if let control = responder as? NSControl, !control.isEnabled {
            return "\(Swift.type(of: control))"
        }
        return nil
    }

    /// The popover of the menu of the rate capsule over `window`, which has the choice "Denní kurz ČNB". Nil while it
    /// is closed.
    private func rateMenu(of window: NSWindow) -> NSWindow? {
        (window.childWindows ?? []).first { child in
            child.isVisible && accessibilityButton(labelled: "Denní kurz ČNB", in: child) != nil
        }
    }

    /// The scroll view of `window` that scrolls up and down by more than a row: the rows of the table of Faktury.
    private func scrollingRows(in window: NSWindow) -> NSScrollView? {
        guard let content = window.contentView else { return nil }
        return scrollViews(under: content).first { view in
            guard let document = view.documentView else { return false }
            return document.frame.height - view.contentView.bounds.height > 60
        }
    }

    /// The scroll views under `view`, in the order of the tree.
    private func scrollViews(under view: NSView) -> [NSScrollView] {
        let own = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap { scrollViews(under: $0) }
    }

    /// The menu Zamknout při nečinnosti in `window`, as VoiceOver reads it: a pop-up button.
    private func idleLockMenu(in window: NSWindow) -> AnyObject? {
        guard let element = accessibilityElement(labelled: "Zamknout při nečinnosti", in: window),
            element.accessibilityRole?() == .popUpButton
        else { return nil }
        return element
    }

    /// What VoiceOver reads as the value of `element`, such as the item a pop-up button shows.
    private func value(of element: AnyObject) -> String? {
        // Asked for as a function of its type, because the protocols of accessibility declare `accessibilityValue()`
        // with more than one type.
        let value: (() -> Any?)? = element.accessibilityValue
        return (value?() ?? nil) as? String
    }

    /// Moves the app's clock on by a second, posts a move of the pointer to the app, as the system does, and waits
    /// until the app has taken it from its queue of events: whether the app took it as activity, at the time of its
    /// clock.
    private func aMoveOfThePointerIsNoted(by app: AppModel, clock: ManualClock) async throws -> Bool {
        clock.advance(by: 1)
        let mark = NSPoint(x: -4_321, y: -1_234)
        let seen = Seen()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            if event.locationInWindow == mark {
                MainActor.assumeIsolated {
                    seen.event = true
                }
            }
            return event
        }
        defer {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        let event = try #require(
            NSEvent.mouseEvent(
                with: .mouseMoved, location: mark, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        NSApp.postEvent(event, atStart: false)
        try await waitUntil { seen.event }
        return app.lastActivity == clock.now()
    }
}

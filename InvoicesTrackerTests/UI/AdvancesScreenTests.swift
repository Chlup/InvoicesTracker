import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The screen of advances and deductions with its real text fields, in a window: what is typed in a field reaches the
/// data through the bindings and the model, when the field is left and when the screen is left, without waiting for
/// the delay (which these tests make an hour long, so that only those saves can have happened), and a text that is not
/// an amount in whole Kč is kept in its field and not saved. Přidat dítě opens the dialog of a child as a sheet of the
/// window, and what is typed in it is stored with Uložit dítě, or, when it cannot be, stays in the open sheet with the
/// failure. A test waits for what it expects to happen until it has happened; it waits a fixed moment only where it
/// expects that nothing happens. The data is the sample year of the
/// engine's regression test in a temporary database, as of 17. 10. 2026. In every expected string `\u{00A0}` is the
/// no-break space.
@Suite(.serialized, .settlesBackups)
@MainActor
struct AdvancesScreenTests {
    // MARK: Helpers

    /// Shows the screen of `app` alone in a window that is key, once it has loaded the plan, and gives the window to
    /// `body`, in the turn of this test to type into a window (`whileTypingAlone`). The window is closed afterwards,
    /// unless `body` has closed it.
    private func withScreen(
        of app: AppModel, saveDelay: Duration, _ body: (NSWindow, _ rows: [[NSTextField]]) async throws -> Void
    ) async throws {
        try await whileTypingAlone {
            let controller = NSHostingController(rootView: AdvancesScreen(app: app, saveDelay: saveDelay))
            // The window keeps the size it is given, not the size the page would like.
            controller.sizingOptions = []
            controller.preferredContentSize = CGSize(width: 1_000, height: 800)
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .resizable]
            // Never a tab of another test's window, whose size it would take (`withAppWindow`).
            window.tabbingMode = .disallowed
            window.setContentSize(CGSize(width: 1_000, height: 800))
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            try await waitUntil { Self.planRows(in: window).count == 12 }
            try await body(window, Self.planRows(in: window))
        }
    }

    /// The text fields of the table of months in the window, a row of them for each month, left to right. The prefill
    /// boxes above the table are no part of it.
    private static func planRows(in window: NSWindow) -> [[NSTextField]] {
        guard let content = window.contentView else { return [] }
        // The fields from the top of the page down, grouped in rows: those whose middles are not far apart.
        let fields = textFields(in: content).sorted { window.frameOfField($0).midY > window.frameOfField($1).midY }
        var rows: [[NSTextField]] = []
        var rowTop: CGFloat?
        for field in fields {
            let middle = window.frameOfField(field).midY
            if let top = rowTop, top - middle < 10 {
                rows[rows.count - 1].append(field)
            } else {
                rows.append([field])
                rowTop = middle
            }
        }
        rows = rows.map { row in row.sorted { window.frameOfField($0).minX < window.frameOfField($1).minX } }
        // The first row is the prefill, the next twelve are the months; the deductions follow them.
        let months = rows.dropFirst().prefix(12)
        return months.count == 12 && months.allSatisfy({ $0.count >= 2 }) ? Array(months) : []
    }

    private static func textFields(in view: NSView) -> [NSTextField] {
        var found: [NSTextField] = []
        if let field = view as? NSTextField, field.isEditable {
            found.append(field)
        }
        for subview in view.subviews {
            found.append(contentsOf: textFields(in: subview))
        }
        return found
    }

    /// Types `text` into `field` as a person does: the field takes the focus and its text is replaced, and the change
    /// reaches the binding as the keys do.
    private func type(_ text: String, into field: NSTextField, in window: NSWindow) throws {
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    /// Types `text` into `field` one character after the other, each of them a change of the text of its own.
    private func typeKeyByKey(_ text: String, into field: NSTextField, in window: NSWindow) throws {
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("", replacementRange: editor.selectedRange())
        for character in text {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }
    }

    /// Leaves the field that has the focus, as a person does by clicking elsewhere or with the Tab key.
    private func leaveField(in window: NSWindow) {
        #expect(window.makeFirstResponder(nil))
    }

    private func storedSocial(_ month: Int, in app: AppModel) async throws -> Int64 {
        let database = try #require(app.database)
        return try await database.yearSettings(2026).advances.social[month - 1]
    }

    // MARK: Tests

    @Test func theTableShowsThePlanInFieldsWithNothingInTheEmptyOnes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)

        try await withScreen(of: app, saveDelay: .seconds(3_600)) { _, rows in
            // The social and the health insurance of every month; the income tax only in March, June, September and
            // December.
            #expect(rows.map(\.count) == [2, 2, 3, 2, 2, 3, 2, 2, 3, 2, 2, 3])
            #expect(rows[0].map(\.stringValue) == ["13\u{00A0}340", "6\u{00A0}920"])
            #expect(rows[2].map(\.stringValue) == ["13\u{00A0}340", "6\u{00A0}920", ""])
            #expect(rows[5].map(\.stringValue) == ["12\u{00A0}150", "5\u{00A0}480", "23\u{00A0}000"])
            // A field that has no text shows none, no hint either.
            #expect(rows[2][2].placeholderString == nil || rows[2][2].placeholderString == "")
        }
    }

    @Test func aValueIsSavedWhenTheFieldIsLeftAndATextThatIsNoAmountIsNot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)

        try await withScreen(of: app, saveDelay: .seconds(3_600)) { window, rows in
            let march = rows[2][0]
            let april = rows[3][0]

            try type("13 000", into: march, in: window)
            // Typing alone saves nothing before the delay is over. Nothing is expected to happen: a fixed moment.
            try await Task.sleep(for: .milliseconds(300))
            #expect(try await storedSocial(3, in: app) == 13_340)

            // Leaving the field saves what was typed in it.
            leaveField(in: window)
            try await waitUntil { try await storedSocial(3, in: app) == 13_000 }

            // Haléře are not whole crowns: the text stays in the field and the plan keeps what it had.
            try type("13 340,50", into: april, in: window)
            leaveField(in: window)
            try await Task.sleep(for: .milliseconds(300))
            #expect(try await storedSocial(4, in: app) == 13_340)
            #expect(april.stringValue == "13 340,50")
            #expect(march.stringValue == "13 000")
        }
    }

    @Test func aValueTypedKeyByKeyIsSavedOnceAsItWasTypedToTheEnd() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)

        try await withScreen(of: app, saveDelay: .seconds(3_600)) { window, rows in
            let versionBefore = app.dataVersion

            try typeKeyByKey("12 150", into: rows[3][0], in: window)
            try await Task.sleep(for: .milliseconds(300))
            #expect(try await storedSocial(4, in: app) == 13_340)
            #expect(app.dataVersion == versionBefore)

            leaveField(in: window)
            try await waitUntil { try await storedSocial(4, in: app) == 12_150 }
            try await waitUntil { app.dataVersion > versionBefore }
            #expect(app.dataVersion == versionBefore + 1)
        }
    }

    @Test func returnReadsAndSavesWhatWasTypedWhileTheFieldKeepsTheFocus() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)

        try await withScreen(of: app, saveDelay: .seconds(3_600)) { window, rows in
            try type("13 500", into: rows[1][0], in: window)
            let editor = try #require(rows[1][0].currentEditor() as? NSTextView)

            editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))

            try await waitUntil { try await storedSocial(2, in: app) == 13_500 }
        }
    }

    @Test func leavingTheScreenSavesWhatWasTypedLast() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)

        try await withScreen(of: app, saveDelay: .seconds(3_600)) { window, rows in
            let database = try #require(app.database)
            try type("14 500", into: rows[7][1], in: window)
            leaveField(in: window)
            try await waitUntil { try await database.yearSettings(2026).advances.health[7] == 14_500 }

            try type("9 999", into: rows[8][0], in: window)
            try await Task.sleep(for: .milliseconds(200))
            #expect(try await storedSocial(9, in: app) == 12_150)

            // The window shows another screen: what is typed is saved though no field was left and no time passed.
            window.contentViewController = NSHostingController(rootView: Color.clear)

            try await waitUntil { try await storedSocial(9, in: app) == 9_999 }
            #expect(try await database.yearSettings(2026).advances.health[7] == 14_500)
        }
    }

    @Test func whatWasTypedStaysAsTypedThroughTheSaveAndTheLoadThatFollowsIt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)

        // The delay is short, so that the save comes by itself while the field still has the focus.
        try await withScreen(of: app, saveDelay: .milliseconds(100)) { window, rows in
            let database = try #require(app.database)
            let versionBefore = app.dataVersion
            try type("6480", into: rows[3][0], in: window)

            try await waitUntil { try await storedSocial(4, in: app) == 6_480 }
            try await waitUntil { app.dataVersion > versionBefore }

            // A change of another cell comes from elsewhere; the screen loads again and shows it. That the load has
            // finished is seen in the cell it changes: only a cell that nobody touched follows the stored value.
            var other = try await database.yearSettings(2026)
            other.advances.social[7] = 9_000
            try await database.saveYearSettings(other)
            await app.didWrite()
            try await waitUntil { rows[7][0].stringValue == "9\u{00A0}000" }

            // What the person typed is not written over with its own formatting; the others show what is stored.
            #expect(rows[3][0].stringValue == "6480")
            #expect(rows[0][0].stringValue == "13\u{00A0}340")
            #expect(window.firstResponder is NSTextView)
        }
    }

    @Test func aDeductionTypedInTheFormIsSavedWhenItsFieldIsLeft() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)

        try await withScreen(of: app, saveDelay: .seconds(3_600)) { window, _ in
            // The gifts are the lowest field of the page: the interest, its months, the life insurance, the pension
            // savings, DIP and long-term care insurance come above them.
            let fields = Self.textFields(in: try #require(window.contentView))
            let gifts = try #require(fields.min { window.frameOfField($0).minY < window.frameOfField($1).minY })
            #expect(gifts.stringValue == "0")

            try type("20 000", into: gifts, in: window)
            leaveField(in: window)

            let database = try #require(app.database)
            try await waitUntil { try await database.yearSettings(2026).deductions.gifts == 20_000 }
            #expect(try await database.yearSettings(2026).deductions.lifeInsurance == 6_480)
        }
    }

    // MARK: The family

    /// Přidat dítě opens the dialog of a new child as a sheet of the window, with the lock after inactivity over it.
    /// What the child comes to is said as it is typed; Uložit dítě stores it and closes the sheet, and the card shows
    /// the child's row once the screen has loaded again.
    @Test func aChildAddedInItsDialogIsStoredAndShownInTheCard() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)

        try await withScreen(of: app, saveDelay: .seconds(3_600)) { window, _ in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Přidat dítě", in: window) != nil }
                _ = try #require(accessibilityButton(labelled: "Přidat dítě", in: window)).accessibilityPerformPress?()
                try await waitUntil { window.attachedSheet != nil }
                let sheet = try #require(window.attachedSheet)
                #expect(IdleLockSheets.guarded.contains(sheet))

                try await waitUntil { textField(labelled: "Datum narození", in: sheet) != nil }
                try type("Anna", into: try #require(textField(labelled: "Jméno", in: sheet)), in: sheet)
                try type("3. 9. 2019", into: try #require(textField(labelled: "Datum narození", in: sheet)), in: sheet)
                try await waitUntil {
                    showsText("V roce 2026: 12\u{00A0}měsíců jako 1. dítě · 15\u{00A0}204\u{00A0}Kč", in: sheet)
                }

                _ = try #require(accessibilityButton(labelled: "Uložit dítě", in: sheet)).accessibilityPerformPress?()

                try await waitUntil { window.attachedSheet == nil }
                #expect(try await database.family(year: 2026).children.map(\.child.name) == ["Anna"])
                let row = "Anna · nar. 3.\u{00A0}9.\u{00A0}2019, 1. dítě · 12\u{00A0}měsíců, 15\u{00A0}204\u{00A0}Kč"
                try await waitUntil { accessibilityButton(labelled: row, in: window) != nil }
            }
        }
    }

    /// "Zvýhodnění uplatňuje" in the dialog is the segmented control of the design: Já and Druhý rodič are two buttons
    /// of one group, the chosen one is selected, and choosing the other changes what the dialog says the child comes
    /// to and who the child is stored as the benefit of.
    @Test func theClaimantOfAChildIsChosenInTheSegmentedControlOfTheDesign() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)

        try await withScreen(of: app, saveDelay: .seconds(3_600)) { window, _ in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Přidat dítě", in: window) != nil }
                _ = try #require(accessibilityButton(labelled: "Přidat dítě", in: window)).accessibilityPerformPress?()
                try await waitUntil { window.attachedSheet != nil }
                let sheet = try #require(window.attachedSheet)
                try await waitUntil { textField(labelled: "Datum narození", in: sheet) != nil }
                try type("Anna", into: try #require(textField(labelled: "Jméno", in: sheet)), in: sheet)
                try type("3. 9. 2019", into: try #require(textField(labelled: "Datum narození", in: sheet)), in: sheet)
                let mine = "V roce 2026: 12\u{00A0}měsíců jako 1. dítě · 15\u{00A0}204\u{00A0}Kč"
                try await waitUntil { showsText(mine, in: sheet) }

                // The elements are asked for each time: the control makes new ones when its choice changes.
                @MainActor func isSelected(_ title: String) -> Bool {
                    accessibilityButton(labelled: title, in: sheet)?.isAccessibilitySelected?() == true
                }
                try await waitUntil { accessibilityButton(labelled: "Druhý rodič", in: sheet) != nil }
                #expect(isSelected("Já"))
                #expect(!isSelected("Druhý rodič"))

                _ = try #require(accessibilityButton(labelled: "Druhý rodič", in: sheet)).accessibilityPerformPress?()
                let theirs = "V roce 2026: 12\u{00A0}měsíců · uplatňuje druhý rodič, ve vašem výpočtu se nepočítá."
                try await waitUntil { showsText(theirs, in: sheet) }
                #expect(isSelected("Druhý rodič"))
                #expect(!isSelected("Já"))

                _ = try #require(accessibilityButton(labelled: "Uložit dítě", in: sheet)).accessibilityPerformPress?()
                try await waitUntil { window.attachedSheet == nil }
                #expect(try await database.family(year: 2026).children.map(\.year.claimant) == [.otherParent])
            }
        }
    }

    /// A child that cannot be saved keeps its dialog open, with what is typed in it, and the dialog says so; nothing is
    /// stored. Once the data takes writes again, Uložit dítě saves the child and closes the sheet.
    @Test func aChildThatCannotBeSavedKeepsItsDialogOpenWithTheFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeAdvancesApp(in: directory)
        let database = try #require(app.database)

        try await withScreen(of: app, saveDelay: .seconds(3_600)) { window, _ in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Přidat dítě", in: window) != nil }
                _ = try #require(accessibilityButton(labelled: "Přidat dítě", in: window)).accessibilityPerformPress?()
                try await waitUntil { window.attachedSheet != nil }
                let sheet = try #require(window.attachedSheet)
                try await waitUntil { textField(labelled: "Datum narození", in: sheet) != nil }
                try type("Anna", into: try #require(textField(labelled: "Jméno", in: sheet)), in: sheet)
                try type("3. 9. 2019", into: try #require(textField(labelled: "Datum narození", in: sheet)), in: sheet)
                try await setDatabaseReadOnly(true, database)

                _ = try #require(accessibilityButton(labelled: "Uložit dítě", in: sheet)).accessibilityPerformPress?()

                try await waitUntil { showsText(ChildDialogModel.saveFailed, in: sheet) }
                #expect(window.attachedSheet === sheet)
                // What is typed stays; the field is found once the line of the failure has moved the buttons down.
                try await waitUntil { textField(labelled: "Jméno", in: sheet)?.stringValue == "Anna" }
                #expect(try await database.family(year: 2026).children.isEmpty)

                try await setDatabaseReadOnly(false, database)
                _ = try #require(accessibilityButton(labelled: "Uložit dítě", in: sheet)).accessibilityPerformPress?()

                try await waitUntil { window.attachedSheet == nil }
                #expect(try await database.family(year: 2026).children.map(\.child.name) == ["Anna"])
            }
        }
    }
}

private extension NSWindow {
    /// The frame of `field` in the coordinates of the window.
    func frameOfField(_ field: NSTextField) -> CGRect {
        field.convert(field.bounds, to: nil)
    }
}

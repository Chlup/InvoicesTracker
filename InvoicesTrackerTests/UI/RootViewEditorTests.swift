import AppKit
import Testing
@testable import InvoicesTracker

/// The window of the app with the invoice editor: what it shows in its title bar while an invoice is made or edited,
/// the chooser as a sheet over the screen or over the editor, where "Zahodit rozepsanou fakturu?" is asked (in the
/// chooser for a choice of the chooser, in the window for any other), the link of the chooser to Odběratelé, and what
/// leaving Faktury does to the editor. The window is a real one in the test host, with the data of `EditorFixture`, and
/// the question is read as VoiceOver reads it. Faktury itself is never on screen here: it comes back only when the
/// editor closes.
@Suite(.serialized, .settlesBackups)
@MainActor
struct RootViewEditorTests {
    /// What a page needs is measured in the font it is set in, so the fonts are registered before any test, as the app
    /// does at its launch.
    init() {
        InvoiceFonts.register()
    }

    /// Shows the window of the app on `app`, on the screen Výpočet, and gives it to `body`, and closes it afterwards
    /// (`withAppWindow`).
    private func withWindow(
        of app: AppModel, _ body: (NSWindow) async throws -> Void
    ) async throws {
        try await withAppWindow(of: app, size: CGSize(width: 1_280, height: 860), body)
    }

    @Test func theTitleBarNamesTheInvoiceThatIsMadeAndTheScreenThatIsLeftBehind() async throws {
        try await EditorFixture.with { f in
            try await withWindow(of: f.app) { window in
                f.app.startNewInvoice(templateID: f.dollarTemplate.id)

                try await waitUntil { window.subtitle == "Ze šablony Software development" }
                #expect(window.title == "Nová faktura")

                // Leaving Faktury keeps the editor, and the window shows it again when it comes back.
                f.app.screen = .overview
                try await waitUntil { window.title == "Přehled" }
                #expect(f.app.editorRequest == .new(templateID: f.dollarTemplate.id))
                #expect(f.app.editor != nil)
                f.app.screen = .invoices
                try await waitUntil { window.title == "Nová faktura" }
                #expect(window.subtitle == "Ze šablony Software development")
            }
        }
    }

    @Test func theEditorOfAnInvoiceIsTitledWithItsNumberAndState() async throws {
        try await EditorFixture.with { f in
            try await withWindow(of: f.app) { window in
                f.app.screen = .invoices
                f.app.editorRequest = .edit(10)

                try await waitUntil { window.title == "Upravit fakturu 20260901" }
                #expect(window.subtitle == "Uhrazená faktura")
            }
        }
    }

    @Test func anInvoiceThatWasDeletedMeanwhileIsSaidSoAndNotEdited() async throws {
        try await EditorFixture.with { f in
            try await f.database.deleteInvoice(id: 10)
            try await withWindow(of: f.app) { window in
                f.app.screen = .invoices
                f.app.editorRequest = .edit(10)

                try await waitUntil { window.title == "Upravit fakturu" }
                // The request stays until the editor is closed.
                #expect(f.app.editorRequest == .edit(10))
            }
        }
    }

    @Test func theQuestionIsAskedInTheChooserBeforeATypedInvoiceIsReplaced() async throws {
        try await EditorFixture.with { f in
            try await withWindow(of: f.app) { window in
                f.app.startNewInvoice(templateID: f.dollarTemplate.id)
                try await waitUntil { f.app.editor != nil }
                let editor = try #require(f.app.editor)
                editor.note = "Typed note"
                f.app.editorRequest = .chooser
                try await waitUntil { window.sheets.count == 1 }
                let chooser = try #require(window.sheets.first)

                f.app.startNewInvoice(templateID: nil)

                try await withAccessibilityElements {
                    // The chooser stays open and asks the question in a box of its own, with nothing over it; nothing
                    // is replaced yet.
                    try await waitUntil {
                        frameOfText(startingWith: "Zahodit rozepsanou fakturu?", in: chooser) != nil
                    }
                    #expect(chooser.sheets.isEmpty)
                    #expect(accessibilityButton(labelled: "Zahodit", in: chooser) != nil)
                    #expect(f.app.pendingDiscard == .newInvoice(templateID: nil))
                    #expect(f.app.editor === editor)

                    // Pokračovat v úpravách: the question and the chooser go, the invoice is there as it was.
                    let keepEditing = try #require(accessibilityButton(labelled: "Pokračovat v úpravách", in: chooser))
                    #expect(keepEditing.accessibilityPerformPress?() == true)
                }
                try await waitUntil { window.sheets.isEmpty }
                #expect(f.app.pendingDiscard == nil)
                #expect(f.app.editor === editor)
                #expect(editor.note == "Typed note")
                #expect(window.title == "Nová faktura")
            }
        }
    }

    /// Zrušit asks "Zahodit rozepsanou fakturu?" in a dialog over the editor, which takes the keyboard focus.
    /// Pokračovat v úpravách gives it back to the field that had it, here the description of the first item, with the
    /// insertion point where it was, so that the person types on where they were. The test types into the window, and
    /// so takes its turn among the tests that do (`whileTypingAlone`).
    @Test func keepingOnEditingGivesTheFocusBackToTheFieldThatHadIt() async throws {
        try await whileTypingAlone {
            try await EditorFixture.with { f in
                try await withWindow(of: f.app) { window in
                    window.makeKeyAndOrderFront(nil)
                    f.app.startNewInvoice(templateID: f.dollarTemplate.id)
                    try await waitUntil { f.app.editor != nil && window.title == "Nová faktura" }

                    try await withAccessibilityElements {
                        let label = "Popis, položka 1"
                        try await waitUntil { textField(labelled: label, in: window) != nil }
                        let description = try #require(textField(labelled: label, in: window))
                        #expect(window.makeFirstResponder(description))
                        let typing = try #require(description.currentEditor() as? NSTextView)
                        typing.insertText(" a údržba", replacementRange: typing.selectedRange())
                        try await waitUntil { f.app.editorHasChanges }

                        f.app.leaveEditor()

                        let keepOnLabel = "Pokračovat v úpravách"
                        try await waitUntil { accessibilityButton(labelled: keepOnLabel, in: window) != nil }
                        // The dialog has the focus, not the field under it.
                        try await waitUntil { !self.hasFocus(labelled: label, in: window) }
                        let keepOn = try #require(accessibilityButton(labelled: keepOnLabel, in: window))
                        #expect(keepOn.accessibilityPerformPress?() == true)

                        try await waitUntil { self.hasFocus(labelled: label, in: window) }
                        // The insertion point is where the typing stopped, at the end, with nothing selected that a key
                        // would replace.
                        let back = try #require(textField(labelled: label, in: window)?.currentEditor() as? NSTextView)
                        #expect(back.selectedRange() == NSRange(location: (back.string as NSString).length, length: 0))
                        #expect(f.app.pendingDiscard == nil)
                        #expect(f.app.editor?.items.first?.description.hasSuffix(" a údržba") == true)
                    }
                }
            }
        }
    }

    /// Whether the text field of `window` that VoiceOver reads under `label` is being typed in: its field editor is the
    /// first responder of the window.
    private func hasFocus(labelled label: String, in window: NSWindow) -> Bool {
        guard let field = textField(labelled: label, in: window), let editor = field.currentEditor() else {
            return false
        }
        return window.firstResponder === editor
    }

    @Test func aQuestionThatIsAskedOnTheScreenWithoutTheChooserIsAskedByTheWindow() async throws {
        try await EditorFixture.with { f in
            try await withWindow(of: f.app) { window in
                f.app.startNewInvoice(templateID: f.dollarTemplate.id)
                try await waitUntil { f.app.editor != nil }
                f.app.editor?.note = "Typed note"
                f.app.screen = .overview
                try await waitUntil { window.title == "Přehled" }

                try await withAccessibilityElements {
                    f.app.openInvoice(10)

                    // The window asks in a dialog of its own over Přehled, not in a sheet.
                    try await waitUntil {
                        frameOfText(startingWith: "Zahodit rozepsanou fakturu?", in: window) != nil
                    }
                    #expect(window.sheets.isEmpty)
                    #expect(f.app.pendingDiscard == .openInvoice(10))
                    #expect(window.title == "Přehled")
                    #expect(accessibilityButton(labelled: "Zahodit", in: window) != nil)

                    let keepEditing = try #require(accessibilityButton(labelled: "Pokračovat v úpravách", in: window))
                    #expect(keepEditing.accessibilityPerformPress?() == true)
                    try await waitUntil { window.title == "Nová faktura" }
                }
                #expect(f.app.pendingDiscard == nil)
                #expect(f.app.editor?.note == "Typed note")
            }
        }
    }

    @Test func theChooserIsASheetOverTheScreenAndOverTheEditor() async throws {
        try await EditorFixture.with { f in
            try await withWindow(of: f.app) { window in
                f.app.editorRequest = .chooser

                try await waitUntil { window.sheets.count == 1 }
                f.app.cancelChooser()
                try await waitUntil { window.sheets.isEmpty }
                #expect(window.title == "Výpočet")

                // Over an editor, the editor stays under the sheet, with its title, and is there again on Zrušit.
                f.app.startNewInvoice(templateID: f.dollarTemplate.id)
                try await waitUntil { window.subtitle == "Ze šablony Software development" }
                f.app.editorRequest = .chooser
                try await waitUntil { window.sheets.count == 1 }
                #expect(window.title == "Nová faktura")
                #expect(window.subtitle == "Ze šablony Software development")
                f.app.cancelChooser()
                try await waitUntil { window.sheets.isEmpty }
                #expect(f.app.editorRequest == .new(templateID: f.dollarTemplate.id))

                // A choice replaces it.
                f.app.editorRequest = .chooser
                try await waitUntil { window.sheets.count == 1 }
                f.app.startNewInvoice(templateID: nil)
                try await waitUntil { window.subtitle == "Prázdná faktura" }
                #expect(window.sheets.isEmpty)
            }
        }
    }

    /// The link under the choices of the chooser says where the templates are edited, "Šablony upravíte u odběratelů",
    /// and opens Odběratelé: the sheet closes and the window shows the screen. VoiceOver reads it as a link, not as a
    /// button.
    @Test func theLinkOfTheChooserOpensOdberatele() async throws {
        try await EditorFixture.with { f in
            try await withWindow(of: f.app) { window in
                f.app.editorRequest = .chooser
                try await waitUntil { window.sheets.count == 1 }
                let chooser = try #require(window.sheets.first)
                let label = "Šablony upravíte u odběratelů"

                try await withAccessibilityElements {
                    try await waitUntil { accessibilityElement(labelled: label, in: chooser) != nil }
                    let link = try #require(accessibilityElement(labelled: label, in: chooser))
                    #expect(link.accessibilityRole?() == .link)
                    #expect(link.accessibilityPerformPress?() == true)
                }

                try await waitUntil { window.sheets.isEmpty }
                #expect(f.app.editorRequest == nil)
                #expect(f.app.screen == .clients)
                try await waitUntil { window.title == "Odběratelé" }
            }
        }
    }
}

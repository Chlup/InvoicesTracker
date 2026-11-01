import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The payment sheet in a window of its own, as Faktury shows it, on the sample year 2026 with invented clients (the
/// app as of 17. 10. 2026): the way from a payment the invoice has into the removal step of the same sheet and back,
/// and the number of the invoice that has to be typed before Odebrat platbu removes the payment. The sheet asks Faktury
/// (`InvoicesModel`) what the step says and to remove the payment, as the screen does.
///
/// The views are found as VoiceOver reads them, and the field of the number as a text field of AppKit, which a test
/// types into in its turn among the tests that type (`withHostedView`). Keys are sent to the window as the application
/// sends them to the view that has the focus.
@Suite(.serialized, .settlesBackups)
@MainActor
struct MarkPaidSheetWindowTests {
    /// The invoice 20260902 of the sample year: 5 445,00 Kč, paid by Cetus Data on 15. 10. 2026.
    private static let invoiceID: Int64 = 11
    private static let removalTitle = "Odebrat platbu faktury 20260902?"

    /// The room the window gives the sheet, which is 620 points wide with the payment and 520 in the removal step.
    private static let size = CGSize(width: 700, height: 720)

    /// What the sheet told the screen: the texts it asked to remove the payment with, and how many times it said that
    /// the payment was removed, or that it was closed with Zrušit.
    @MainActor
    private final class Calls {
        var typed: [String] = []
        var removed = 0
        var cancelled = 0
    }

    // MARK: Helpers

    /// An app model on a new folder with the sample year stored, as of noon of 17. 10. 2026.
    private func makeApp(in directory: URL) async throws -> AppModel {
        let app = makeAppModel(in: directory, clock: ManualClock(localNoon(2026, 10, 17)))
        try await startFresh(app)
        try await SampleYear2026.store(in: try #require(app.database))
        await app.didWriteAndBackUp()
        return app
    }

    /// The sheet of `model` in `app`, which asks Faktury what its removal step says and to remove the payment; with
    /// `refusing`, every removal is refused instead, as one is when the payment is not there any more. `calls` keeps
    /// what the sheet told the screen.
    private func sheet(
        of model: PaymentSheetModel, in app: AppModel, calls: Calls, refusing: Bool = false
    ) -> MarkPaidSheet {
        let invoices = InvoicesModel(app: app)
        let id = model.invoice.id
        return MarkPaidSheet(
            model: model, timeZone: app.dependencies.timeZone(), cancel: { calls.cancelled += 1 }, saved: {},
            removalSummary: { await invoices.paymentRemovalSummary(for: id) },
            removePayment: { typed in
                calls.typed.append(typed)
                return refusing ? false : try await invoices.removePayment(id, typed: typed)
            },
            removed: { calls.removed += 1 })
    }

    /// Presses "Odebrat platbu…" of the sheet in `window`, as a click does, and waits for the removal step, until its
    /// field of the number is in the window and has the focus, which it takes when the step opens.
    private func openTheRemovalStep(in window: NSWindow) async throws -> NSTextField {
        try await waitUntil { accessibilityButton(labelled: "Odebrat platbu…", in: window) != nil }
        let link = try #require(accessibilityButton(labelled: "Odebrat platbu…", in: window))
        #expect(link.accessibilityPerformPress?() == true)
        try await waitUntil { heading(Self.removalTitle, in: window) != nil }
        try await waitUntil { numberField(in: window).map { hasFocus($0, in: window) } ?? false }
        return try #require(numberField(in: window))
    }

    /// The heading of the sheet in `window` that VoiceOver reads as `title`, or nil when the sheet has another one.
    private func heading(_ title: String, in window: NSWindow) -> AnyObject? {
        accessibilityElement(role: NSAccessibility.Role(rawValue: "AXHeading"), labelled: title, in: window)
    }

    /// Whether "Odebrat platbu" in `window` can be pressed; nil when the window has no such button.
    private func removalIsEnabled(in window: NSWindow) -> Bool? {
        accessibilityButton(labelled: "Odebrat platbu", in: window)?.isAccessibilityEnabled?()
    }

    /// The field of the removal step in `window` where the number of the invoice is typed: the one whose placeholder
    /// is "Číslo faktury".
    private func numberField(in window: NSWindow) -> NSTextField? {
        guard let content = window.contentView else { return nil }
        return editableTextFields(in: content).first { $0.placeholderString == "Číslo faktury" }
    }

    /// Whether `field` has the keyboard focus in `window`: its field editor is the first responder.
    private func hasFocus(_ field: NSTextField, in window: NSWindow) -> Bool {
        field.currentEditor() != nil && window.firstResponder === field.currentEditor()
    }

    /// Types `text` into `field` as a person does: the field takes the focus and its text is replaced, and the change
    /// reaches the binding as the keys do.
    private func type(_ text: String, into field: NSTextField, in window: NSWindow) throws {
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    /// Presses Esc as the keyboard does: a key-down event handed to `window` as the application hands it the keys, to
    /// the view that has the focus.
    private func pressEscape(in window: NSWindow) throws {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1B}",
                charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
        window.sendEvent(event)
    }

    // MARK: The removal step

    /// "Odebrat platbu…" stands at the leading end of the footer of a payment the invoice has and opens the removal
    /// step in the same window. Its Odebrat platbu is off until the number of the invoice is typed, and a press while
    /// it is off does nothing; once the number is typed it removes the payment and says so to the screen.
    @Test func odebratPlatbuIsEnabledOnlyByTheNumber() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = PaymentSheetModel(app: app, invoice: try #require(try await database.invoice(id: Self.invoiceID)))
        let calls = Calls()

        try await withHostedView(sheet(of: model, in: app, calls: calls), size: Self.size) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Odebrat platbu…", in: window) != nil }
                let link = try #require(
                    accessibilityButton(labelled: "Odebrat platbu…", in: window)?.accessibilityFrame?())
                let zrusit = try #require(accessibilityButton(labelled: "Zrušit", in: window)?.accessibilityFrame?())
                #expect(link.maxX < zrusit.minX)
                #expect(abs(link.midY - zrusit.midY) < 1)

                let field = try await openTheRemovalStep(in: window)

                #expect(frameOfText(startingWith: "Jen pro opravu omylu.", in: window) != nil)
                #expect(accessibilityButton(labelled: "Zpět", in: window) != nil)
                #expect(accessibilityButton(labelled: "Uložit platbu", in: window) == nil)
                #expect(removalIsEnabled(in: window) == false)
                try type("2026", into: field, in: window)
                try await layOut(window)
                #expect(removalIsEnabled(in: window) == false)
                _ = accessibilityButton(labelled: "Odebrat platbu", in: window)?.accessibilityPerformPress?()
                try await layOut(window)
                #expect(calls.typed.isEmpty)

                try type("20260902", into: field, in: window)

                try await waitUntil { removalIsEnabled(in: window) == true }
                #expect(
                    accessibilityButton(labelled: "Odebrat platbu", in: window)?.accessibilityPerformPress?() == true)
                try await waitUntil { calls.removed == 1 }
                #expect(calls.typed == ["20260902"])
                #expect(try await database.invoice(id: Self.invoiceID)?.payment == nil)
                #expect(calls.cancelled == 0)
            }
        }
    }

    /// Esc in the removal step is Zpět, not Zrušit: the sheet shows the payment again, with the day as it was changed
    /// before the step, and nothing is removed. "Odebrat platbu…" shows the step again with the number typed so far.
    @Test func escInTheRemovalStepGoesBackToThePaymentWithWhatWasTyped() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = PaymentSheetModel(app: app, invoice: try #require(try await database.invoice(id: Self.invoiceID)))
        model.date = civilDate("2026-10-16")
        let calls = Calls()

        try await withHostedView(sheet(of: model, in: app, calls: calls), size: Self.size) { window in
            try await withAccessibilityElements {
                let field = try await openTheRemovalStep(in: window)
                try type("2026", into: field, in: window)

                try pressEscape(in: window)

                try await waitUntil { accessibilityButton(labelled: "Uložit platbu", in: window) != nil }
                #expect(heading(Self.removalTitle, in: window) == nil)
                #expect(heading("Upravit platbu", in: window) != nil)
                #expect(model.removal == nil)
                #expect(model.date == civilDate("2026-10-16"))
                #expect(calls.cancelled == 0)
                #expect(calls.typed.isEmpty)
                #expect(try await database.invoice(id: Self.invoiceID)?.payment != nil)

                let again = try await openTheRemovalStep(in: window)
                #expect(again.stringValue == "2026")
                #expect(removalIsEnabled(in: window) == false)
            }
        }
    }

    /// A removal that removes nothing, as when the payment is not there any more, says so in the step, which stays
    /// open with the number typed.
    @Test func aRemovalThatRemovesNothingSaysSoAndTheStepStays() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = PaymentSheetModel(app: app, invoice: try #require(try await database.invoice(id: Self.invoiceID)))
        let calls = Calls()

        try await withHostedView(sheet(of: model, in: app, calls: calls, refusing: true), size: Self.size) { window in
            try await withAccessibilityElements {
                let field = try await openTheRemovalStep(in: window)
                try type("20260902", into: field, in: window)
                try await waitUntil { removalIsEnabled(in: window) == true }

                #expect(
                    accessibilityButton(labelled: "Odebrat platbu", in: window)?.accessibilityPerformPress?() == true)

                try await waitUntil {
                    showsText(
                        "Platbu se nepodařilo odebrat – číslo nesouhlasí nebo platba už neexistuje.", in: window)
                }
                #expect(calls.typed == ["20260902"])
                #expect(calls.removed == 0)
                #expect(heading(Self.removalTitle, in: window) != nil)
                #expect(numberField(in: window)?.stringValue == "20260902")
            }
        }
    }

    /// What removing the payment does is said in the red note of the step as paragraphs of the prototype's column, as
    /// the dialog that deletes an invoice says it: one under the other 6 points apart and 6 points under the title of
    /// the note (`Note(_:icon:title:paragraphs:)`), and not as one block of text.
    @Test func theNoteOfTheRemovalStepIsMadeOfParagraphsSixPointsApart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = PaymentSheetModel(app: app, invoice: try #require(try await database.invoice(id: Self.invoiceID)))

        try await withHostedView(sheet(of: model, in: app, calls: Calls()), size: Self.size) { window in
            try await withAccessibilityElements {
                _ = try await openTheRemovalStep(in: window)
                try await layOut(window)
                let lines = try #require(model.removal).lines
                let title = "Jen pro opravu omylu."
                let note = try #require(frameOfText(startingWith: title, in: window))

                #expect(lines.count > 1, "The step says \(lines)")
                expectNoteOfParagraphsSixPointsApart(height: note.height, width: note.width, title: title, lines: lines)
            }
        }
    }

    /// VoiceOver reads the sheet under its title (`dialogNamed(_:)`), which in the removal step is the title of that
    /// step and not the one of the payment: "Odebrat platbu faktury 20260902?" while the step shows, and "Upravit
    /// platbu" before it and after it.
    @Test func theSheetIsNamedAfterTheTitleOfTheStepThatShows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        let model = PaymentSheetModel(app: app, invoice: try #require(try await database.invoice(id: Self.invoiceID)))

        try await withHostedView(sheet(of: model, in: app, calls: Calls()), size: Self.size) { window in
            try await withAccessibilityElements {
                try await expectContainers(["Upravit platbu"], in: window, "The payment step")
                #expect(!containerLabels(in: window).contains(Self.removalTitle))

                _ = try await openTheRemovalStep(in: window)

                try await expectContainers([Self.removalTitle], in: window, "The removal step")
                #expect(!containerLabels(in: window).contains("Upravit platbu"))

                // Esc is Zpět in the removal step.
                try pressEscape(in: window)

                try await expectContainers(["Upravit platbu"], in: window, "The payment step again")
                #expect(!containerLabels(in: window).contains(Self.removalTitle))
            }
        }
    }

    /// The sheet that records the first payment of an invoice has no way into removing one.
    @Test func odebratPlatbuIsOfferedOnlyForAPaymentTheInvoiceHas() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try await makeApp(in: directory)
        let database = try #require(app.database)
        var unpaid = try #require(try await database.invoice(id: Self.invoiceID))
        unpaid.payment = nil
        try await database.saveInvoice(unpaid)
        let model = PaymentSheetModel(app: app, invoice: unpaid)

        try await withHostedView(sheet(of: model, in: app, calls: Calls()), size: Self.size) { window in
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Označit jako uhrazenou", in: window) != nil }
                try await layOut(window)

                #expect(accessibilityButton(labelled: "Odebrat platbu…", in: window) == nil)
                #expect(accessibilityButton(labelled: "Zrušit", in: window) != nil)
            }
        }
    }
}

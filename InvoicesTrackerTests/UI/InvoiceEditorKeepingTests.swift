import AppKit
import Foundation
import Testing
@testable import InvoicesTracker

/// What the app does with the invoice that is being written: the editor stays while the window shows other screens or
/// is closed, a choice that would replace it asks first when something typed would be lost, and quitting asks the same
/// question. The data is the invented clients, templates and invoices of `EditorFixture`.
@Suite(.settlesBackups)
@MainActor
struct InvoiceEditorKeepingTests {
    /// The editor of a new invoice from the dollar template, made as the window makes it, with a note typed into it
    /// unless `typing` says otherwise.
    private func editorOfANewInvoice(
        _ f: EditorFixture, typing: Bool = true
    ) async throws -> InvoiceEditorModel {
        f.app.startNewInvoice(templateID: f.dollarTemplate.id)
        await f.app.openEditor()
        let editor = try #require(f.app.editor)
        if typing {
            editor.note = "Typed note"
        }
        return editor
    }

    // MARK: Keeping it

    @Test func theAppMakesTheEditorForTheRequestThatIsShown() async throws {
        try await EditorFixture.with { f in
            f.app.startNewInvoice(templateID: f.dollarTemplate.id)
            #expect(f.app.editor == nil)

            await f.app.openEditor()

            let editor = try #require(f.app.editor)
            #expect(editor.template?.id == f.dollarTemplate.id)
            #expect(editor.number == "20261001")
            #expect(f.app.editorProblem == nil)

            f.app.editorRequest = .edit(10)
            await f.app.openEditor()

            #expect(f.app.editor?.editing?.id == 10)
            #expect(f.app.editor !== editor)
        }
    }

    @Test func theEditorStaysWhileTheWindowShowsOtherScreens() async throws {
        try await EditorFixture.with { f in
            let editor = try await editorOfANewInvoice(f)

            f.app.screen = .overview

            #expect(f.app.editorRequest == .new(templateID: f.dollarTemplate.id))
            #expect(f.app.isEditorOpen)
            #expect(f.app.editor === editor)

            f.app.screen = .computation
            f.app.screen = .invoices

            #expect(f.app.editor === editor)
            #expect(editor.note == "Typed note")
        }
    }

    @Test func theBackArrowIsShownOnlyWhereTheEditorIsShown() async throws {
        try await EditorFixture.with { f in
            #expect(f.app.showsEditorBackArrow == false)

            f.app.startNewInvoice(templateID: nil)
            #expect(f.app.showsEditorBackArrow)

            f.app.screen = .overview
            #expect(f.app.showsEditorBackArrow == false)

            f.app.screen = .invoices
            #expect(f.app.showsEditorBackArrow)

            // The chooser is not the editor.
            f.app.editorRequest = .chooser
            #expect(f.app.showsEditorBackArrow == false)
        }
    }

    @Test func aWindowThatIsShownAgainFindsTheEditorAsItWasLeft() async throws {
        try await EditorFixture.with { f in
            let editor = try await editorOfANewInvoice(f)

            // The window was closed and opened again: it asks for the editor of the request, which is there.
            await f.app.openEditor()
            await f.app.openEditor()

            #expect(f.app.editor === editor)
            #expect(editor.note == "Typed note")
        }
    }

    @Test func closingTheEditorLetsItGo() async throws {
        try await EditorFixture.with { f in
            _ = try await editorOfANewInvoice(f)

            f.app.closeEditor()

            #expect(f.app.editorRequest == nil)
            #expect(f.app.editor == nil)
            await f.app.openEditor()
            #expect(f.app.editor == nil)
        }
    }

    @Test func savingTheInvoiceLetsTheEditorGo() async throws {
        try await EditorFixture.with { f in
            let editor = try await editorOfANewInvoice(f)

            let id = try await editor.saveDraft()

            #expect(f.app.editorRequest == nil)
            #expect(f.app.editor == nil)
            #expect(f.app.pendingDetailInvoiceID == id)
        }
    }

    @Test func anInvoiceThatWasDeletedMeanwhileIsSaidSoAndHasNoEditor() async throws {
        try await EditorFixture.with { f in
            f.app.editorRequest = .edit(999)

            await f.app.openEditor()

            #expect(f.app.editor == nil)
            #expect(f.app.editorProblem == "Faktura mezitím byla smazána.")
            // The request stays until the editor is closed, and then the problem goes with it.
            f.app.closeEditor()
            #expect(f.app.editorProblem == nil)
        }
    }

    @Test func theChooserOverAnEditorKeepsItAndCancellingShowsItAsItWas() async throws {
        try await EditorFixture.with { f in
            let editor = try await editorOfANewInvoice(f)

            f.app.editorRequest = .chooser
            await f.app.openEditor()
            f.app.cancelChooser()

            #expect(f.app.editor === editor)
            #expect(editor.note == "Typed note")
        }
    }

    // MARK: Asking before it is thrown away

    @Test func aChoiceInTheChooserAsksBeforeItThrowsAwayWhatWasTyped() async throws {
        try await EditorFixture.with { f in
            let editor = try await editorOfANewInvoice(f)
            f.app.editorRequest = .chooser

            f.app.startNewInvoice(templateID: nil)

            // Nothing is replaced while the question is open.
            #expect(f.app.pendingDiscard == .newInvoice(templateID: nil))
            #expect(f.app.editorRequest == .chooser)
            #expect(f.app.editor === editor)
            #expect(editor.note == "Typed note")

            f.app.confirmDiscard()

            #expect(f.app.pendingDiscard == nil)
            #expect(f.app.editorRequest == .new(templateID: nil))
            #expect(f.app.screen == .invoices)
            #expect(f.app.editor == nil)
            await f.app.openEditor()
            let replacement = try #require(f.app.editor)
            #expect(replacement !== editor)
            #expect(replacement.template == nil)
            #expect(replacement.note == "")
        }
    }

    @Test func continuingToEditAfterTheQuestionShowsTheEditorAgain() async throws {
        try await EditorFixture.with { f in
            let editor = try await editorOfANewInvoice(f)
            f.app.screen = .computation
            f.app.editorRequest = .chooser
            f.app.startNewInvoice(templateID: nil)
            #expect(f.app.pendingDiscard != nil)

            f.app.cancelDiscard()

            #expect(f.app.pendingDiscard == nil)
            // The chooser is closed, the editor is on the screen as it was, on Faktury.
            #expect(f.app.editorRequest == .new(templateID: f.dollarTemplate.id))
            #expect(f.app.screen == .invoices)
            #expect(f.app.editor === editor)
            #expect(editor.note == "Typed note")
            // Answering twice does nothing more.
            f.app.cancelDiscard()
            f.app.confirmDiscard()
            #expect(f.app.editorRequest == .new(templateID: f.dollarTemplate.id))
        }
    }

    @Test func aChoiceReplacesAnEditorWithNothingTypedWithoutAsking() async throws {
        try await EditorFixture.with { f in
            let editor = try await editorOfANewInvoice(f, typing: false)
            f.app.editorRequest = .chooser

            f.app.startNewInvoice(templateID: nil)

            #expect(f.app.pendingDiscard == nil)
            #expect(f.app.editorRequest == .new(templateID: nil))
            #expect(f.app.editor == nil)
            #expect(editor.hasChanges == false)
        }
    }

    @Test func whatWasTypedAndThenTypedBackIsNoLossToAskAbout() async throws {
        try await EditorFixture.with { f in
            let editor = try await editorOfANewInvoice(f)
            #expect(editor.hasChanges)
            editor.note = f.dollarTemplate.note
            #expect(editor.hasChanges == false)
            f.app.editorRequest = .chooser

            f.app.startNewInvoice(templateID: nil)

            #expect(f.app.pendingDiscard == nil)
            #expect(f.app.editorRequest == .new(templateID: nil))
        }
    }

    @Test func zrusitAndTheBackArrowAskBeforeTheyThrowAwayWhatWasTyped() async throws {
        try await EditorFixture.with { f in
            let editor = try await editorOfANewInvoice(f)

            editor.cancel()

            #expect(f.app.pendingDiscard == .closeEditor)
            #expect(f.app.editorRequest == .new(templateID: f.dollarTemplate.id))
            #expect(f.app.editor === editor)

            f.app.cancelDiscard()

            #expect(f.app.pendingDiscard == nil)
            #expect(f.app.editor === editor)
            #expect(editor.note == "Typed note")

            // The back arrow of the toolbar is the same question.
            f.app.leaveEditor()
            #expect(f.app.pendingDiscard == .closeEditor)

            f.app.confirmDiscard()

            #expect(f.app.editorRequest == nil)
            #expect(f.app.editor == nil)
            #expect(f.app.screen == .invoices)
            #expect(f.app.pendingDetailInvoiceID == nil)
        }
    }

    @Test func zrusitAndTheBackArrowAskNothingWhenNothingWasTyped() async throws {
        try await EditorFixture.with { f in
            let editor = try await editorOfANewInvoice(f, typing: false)

            editor.cancel()

            #expect(f.app.pendingDiscard == nil)
            #expect(f.app.editorRequest == nil)
            #expect(f.app.editor == nil)
        }
    }

    @Test func zrusitOnAnEditedInvoiceShowsItsDetailAfterTheAnswer() async throws {
        try await EditorFixture.with { f in
            f.app.editorRequest = .edit(10)
            await f.app.openEditor()
            let editor = try #require(f.app.editor)
            editor.items[0].quantityText = "220"

            f.app.leaveEditor()
            #expect(f.app.pendingDiscard == .closeEditor)
            f.app.confirmDiscard()

            #expect(f.app.editorRequest == nil)
            #expect(f.app.pendingDetailInvoiceID == 10)
            #expect(try await f.stored(10).items[0].quantity == decimal("205"))
        }
    }

    @Test func theChooserLinkToOdberateleKeepsTheInvoiceThatWasBeingWritten() async throws {
        try await EditorFixture.with { f in
            let editor = try await editorOfANewInvoice(f)
            let chooser = NewInvoiceChooserModel(app: f.app)
            f.app.editorRequest = .chooser

            chooser.showClients()

            // Odběratelé is shown, and the invoice is there when Faktury is.
            #expect(f.app.screen == .clients)
            #expect(f.app.pendingDiscard == nil)
            #expect(f.app.editorRequest == .new(templateID: f.dollarTemplate.id))
            #expect(f.app.editor === editor)
            f.app.screen = .invoices
            #expect(f.app.editor === editor)
            #expect(editor.note == "Typed note")
        }
    }

    @Test func openingAnInvoiceOfTheListAsksBeforeItThrowsAwayWhatWasTyped() async throws {
        try await EditorFixture.with { f in
            let editor = try await editorOfANewInvoice(f)
            f.app.screen = .overview

            f.app.openInvoice(10)

            #expect(f.app.pendingDiscard == .openInvoice(10))
            #expect(f.app.screen == .overview)
            #expect(f.app.pendingDetailInvoiceID == nil)
            #expect(f.app.editor === editor)

            f.app.confirmDiscard()

            #expect(f.app.editorRequest == nil)
            #expect(f.app.editor == nil)
            #expect(f.app.screen == .invoices)
            #expect(f.app.pendingDetailInvoiceID == 10)
        }
    }

    @Test func openingAnInvoiceWhileTheEditorHoldsNothingTypedClosesTheEditorAtOnce() async throws {
        try await EditorFixture.with { f in
            _ = try await editorOfANewInvoice(f, typing: false)
            f.app.screen = .overview

            f.app.openInvoice(10)

            #expect(f.app.pendingDiscard == nil)
            #expect(f.app.editorRequest == nil)
            #expect(f.app.editor == nil)
            #expect(f.app.screen == .invoices)
            #expect(f.app.pendingDetailInvoiceID == 10)
        }
    }

    @Test func openingAnInvoiceWithoutAnEditorOpensItAtOnce() async throws {
        try await EditorFixture.with { f in
            f.app.openInvoice(10)

            #expect(f.app.pendingDiscard == nil)
            #expect(f.app.screen == .invoices)
            #expect(f.app.pendingDetailInvoiceID == 10)
        }
    }

    // MARK: What counts as something typed

    @Test func anEditorHasNothingTypedUntilSomethingIsTypedOrChosen() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor()
            // The first client and the number are what the editor starts with, not what the person typed.
            #expect(model.hasChanges == false)

            model.pickClient(f.cetusID)
            #expect(model.hasChanges)
            model.pickClient(f.alfaID)
            #expect(model.hasChanges == false)

            model.items[0].description = "Typed"
            #expect(model.hasChanges)
            model.items[0].description = ""
            #expect(model.hasChanges == false)

            model.dueDaysText = "21"
            #expect(model.hasChanges)
        }
    }

    @Test func anInvoiceThatIsEditedHasNothingTypedUntilItIsEdited() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice()
            let model = try await f.editor(editing: invoice.id)
            #expect(model.hasChanges == false)

            model.items[0].quantityText = "101"

            #expect(model.hasChanges)
        }
    }

    @Test func aProposedNumberThatMovesOnByItselfIsNoChangeOfThePerson() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            #expect(model.number == "20261001")

            // Another window takes the number that was proposed, and the proposal moves on by itself.
            try await f.storeIssuedDollarInvoice(number: "20261001")
            await f.app.didWrite()
            await model.recompute()
            #expect(model.number == "20261002")
            #expect(model.hasChanges == false)

            // A number that is typed is one, and the number the editor started with typed back is none.
            model.number = "20261003"
            #expect(model.hasChanges)
            model.number = "20261001"
            #expect(model.hasChanges == false)
        }
    }

    @Test func aNumberThatIsClearedIsAChangeEvenWhereTheEditorProposedNothing() async throws {
        try await EditorFixture.with { f in
            let draft = try await f.storeIssuedDollarInvoice(number: "FV-7", status: .draft)
            let model = try await f.editor(editing: draft.id)
            #expect(model.hasChanges == false)

            model.number = ""

            #expect(model.hasChanges)
        }
    }

    @Test func anEditorWhoseAppIsGoneDoesNothingAndDoesNotTrap() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        var model: InvoiceEditorModel?
        do {
            // The editor does not hold the app: when the app is gone, the editor has nothing to work with.
            let app = makeAppModel(in: directory)
            model = InvoiceEditorModel(app: app, template: nil, editing: nil)
        }
        let editor = try #require(model)

        await editor.load()
        await editor.recompute()
        editor.cancel()
        editor.chooseAnotherTemplate()

        #expect(editor.loadFailed)
        #expect(editor.document == nil)
        #expect(editor.refreshKey.dataVersion == 0)
        await #expect(throws: VaultError.locked) {
            try await editor.saveDraft()
        }
        #expect(editor.isSaving == false)
    }

    @Test func movingTheDUZPIsAChangeAndMovingItBackIsNone() async throws {
        try await EditorFixture.with { f in
            let model = await f.newEditor(template: f.dollarTemplate)
            #expect(model.number == "20261001")

            model.duzp = civilDate("2026-09-30")
            await model.recompute()
            #expect(model.number == "20260903")
            #expect(model.hasChanges)

            model.duzp = civilDate("2026-10-31")
            await model.recompute()
            #expect(model.number == "20261001")
            #expect(model.hasChanges == false)
        }
    }

    // MARK: Quitting

    /// The person at the question of a quit: what they answer, and how often they were asked.
    private final class Person {
        var answer = false
        var questions = 0
    }

    private func delegate(of app: AppModel, asking person: Person) -> AppDelegate {
        let delegate = AppDelegate()
        delegate.model = app
        delegate.asksToDiscard = {
            person.questions += 1
            return person.answer
        }
        return delegate
    }

    @Test func quittingWithNothingTypedDoesNotAsk() async throws {
        try await EditorFixture.with { f in
            let person = Person()
            let delegate = delegate(of: f.app, asking: person)
            #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)

            _ = try await editorOfANewInvoice(f, typing: false)

            #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
            #expect(person.questions == 0)
        }
    }

    @Test func quittingWithAnInvoiceTypedQuitsOnlyWhenThePersonSaysToDiscardIt() async throws {
        try await EditorFixture.with { f in
            let person = Person()
            let delegate = delegate(of: f.app, asking: person)
            _ = try await editorOfANewInvoice(f)

            #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateCancel)
            person.answer = true
            #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
            #expect(person.questions == 2)
        }
    }

    @Test func quittingAppsWithoutAModelAsksNothing() {
        let delegate = AppDelegate()
        delegate.asksToDiscard = {
            Issue.record("There is nothing to ask about")
            return false
        }

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }

    @Test func theQuestionIsTheOneTheWindowAsks() {
        #expect(DiscardQuestion.title == "Zahodit rozepsanou fakturu?")
        #expect(DiscardQuestion.discard == "Zahodit")
        #expect(DiscardQuestion.keepEditing == "Pokračovat v úpravách")
    }

    // MARK: The payments the app converts again

    /// Stores the dollar invoice of the fixture (7 000,00 USD), paid on 19. 10. 2026 and converted provisionally at its
    /// own rate, 21,359, as the ČNB has not declared the rate of that day yet, and opens it in the editor as the window
    /// does. Returns the invoice as stored and the editor.
    private func editorOfAProvisionalPayment(_ f: EditorFixture) async throws -> (Invoice, InvoiceEditorModel) {
        let rate = storedRate("USD", "21.359", declaredOn: "2026-09-30")
        let invoice = try await f.storeIssuedDollarInvoice(
            payment: Payment.fixture(
                on: "2026-10-19", conversion: .cnbDaily, net: 14_951_300, vat: 0, rate: rate, provisional: true))
        f.app.editorRequest = .edit(invoice.id)
        await f.app.openEditor()
        return (invoice, try #require(f.app.editor))
    }

    /// The rate of 19. 10. 2026 comes (an invented one, 21,5), and the app converts the payments that waited for it.
    private func rateOfTheDayComes(_ f: EditorFixture) async throws {
        try await f.database.insertCNBRates([
            CNBRateRow(declaredOn: civilDate("2026-10-19"), currency: .usd, amount: 1, rate: decimal("21.5"))
        ])
        try await f.app.recomputePayments(year: nil, in: f.database)
    }

    /// 7 000,00 USD at 21,5.
    private let convertedAtTheNewRate: Int64 = 15_050_000

    /// Stores the dollar invoice of the fixture (7 000,00 USD), paid on 16. 10. 2026 and converted at the ČNB rate of
    /// that day as the app converts it, and opens it in the editor as the window does. Returns the invoice as stored
    /// and the editor.
    private func editorOfAPaidInvoice(_ f: EditorFixture) async throws -> (Invoice, InvoiceEditorModel) {
        var invoice = try await f.storeIssuedDollarInvoice()
        invoice.payment = try await f.app.convert(
            invoice, paidOn: civilDate("2026-10-16"), method: .cnbDaily, in: f.database)
        try await f.database.saveInvoice(invoice)
        #expect(invoice.payment?.provisional == false)
        f.app.editorRequest = .edit(invoice.id)
        await f.app.openEditor()
        return (invoice, try #require(f.app.editor))
    }

    /// The uniform rate of dollars for 2026 (an invented one, 21,70 Kč) is stored, and the person switches the year to
    /// it in Nastavení › Rok, which converts the payments of the year again.
    private func yearSwitchedToTheUniformRate(_ f: EditorFixture) async throws {
        try await f.database.saveUniformRates(
            [
                UniformRate(
                    year: 2026, currency: .usd, amount: 1, rate: decimal("21.7"), instruction: "GFŘ-D-99",
                    origin: .manual)
            ], year: 2026)
        let year = YearTabModel(app: f.app)
        await year.load()
        await year.setFXMethod(.uniform)
        #expect(year.saveFailure == nil)
    }

    /// 7 000,00 USD at the uniform rate, 21,70.
    private let atTheUniformRate: Int64 = 15_190_000

    @Test func aYearSwitchedToTheUniformRateConvertsTheInvoiceInTheEditorAtOnceAndTheEditorStillSaves() async throws {
        try await EditorFixture.with { f in
            let (invoice, editor) = try await editorOfAPaidInvoice(f)

            try await yearSwitchedToTheUniformRate(f)

            // The stored invoice is converted at once, and the editor edits it as it is stored now.
            let converted = try await f.stored(invoice.id)
            let payment = try #require(converted.payment)
            #expect(payment.conversion == .uniform)
            #expect(payment.czkNetHalere == atTheUniformRate)
            #expect(editor.editing == converted)
            #expect(editor.hasChanges == false)

            try await editor.saveChanges()

            #expect(try await f.stored(invoice.id) == converted)
            // The data closed and opened again keep the conversion: nothing waited for the editor to let it go.
            await f.database.close()
            let reopened = makeAppModel(in: f.directory, clock: f.clock)
            await reopened.launch()
            let database = try #require(reopened.database)
            #expect(try await database.invoice(id: invoice.id)?.payment == payment)
        }
    }

    @Test func newRatesConvertTheInvoiceInTheEditorAndItsSaveAppliesThemToWhatWasTyped() async throws {
        try await EditorFixture.with { f in
            let (invoice, editor) = try await editorOfAProvisionalPayment(f)
            editor.items[0].quantityText = "110"

            try await rateOfTheDayComes(f)

            let converted = try await f.stored(invoice.id)
            let payment = try #require(converted.payment)
            #expect(payment.provisional == false)
            #expect(payment.czkNetHalere == convertedAtTheNewRate)
            #expect(editor.editing == converted)
            #expect(editor.hasChanges)

            try await editor.saveChanges()

            // The new conversion, applied to the 110 hours typed: 7 700,00 USD at 21,5.
            let saved = try await f.stored(invoice.id)
            #expect(saved.items[0].quantity == decimal("110"))
            #expect(saved.payment?.rate == payment.rate)
            #expect(saved.payment?.provisional == false)
            #expect(saved.payment?.czkNetHalere == 16_555_000)
        }
    }

    @Test func aPaymentChangedInAnotherWindowStillRefusesTheSaveOfTheEditor() async throws {
        try await EditorFixture.with { f in
            let (invoice, editor) = try await editorOfAPaidInvoice(f)

            // Another window moves the payment to another day.
            let sheet = PaymentSheetModel(app: f.app, invoice: invoice)
            sheet.date = civilDate("2026-10-15")
            try await sheet.save()
            editor.note = "Opraveno."

            await #expect(throws: InvoiceEditorError.invoiceChanged) {
                try await editor.saveChanges()
            }
            #expect(try await f.stored(invoice.id).payment?.date == civilDate("2026-10-15"))
        }
    }

    @Test func anEditorThatWasStaleAlreadyTakesNothingFromAConversionOfTheApp() async throws {
        try await EditorFixture.with { f in
            let (invoice, editor) = try await editorOfAPaidInvoice(f)
            // Another window moves the payment to another day: the editor holds the invoice as it was before that.
            let sheet = PaymentSheetModel(app: f.app, invoice: invoice)
            sheet.date = civilDate("2026-10-15")
            try await sheet.save()

            try await yearSwitchedToTheUniformRate(f)

            // The app converted the invoice as it is stored, with the day the other window gave it.
            let converted = try #require(try await f.stored(invoice.id).payment)
            #expect(converted.conversion == .uniform)
            #expect(converted.date == civilDate("2026-10-15"))
            // The editor took nothing: it still holds the invoice it opened, and saving it would undo the other window.
            #expect(editor.editing == invoice)
            editor.note = "Opraveno."
            await #expect(throws: InvoiceEditorError.invoiceChanged) {
                try await editor.saveChanges()
            }
        }
    }

    @Test func aPaymentRecordedMeanwhileStillRefusesTheSaveOfTheEditor() async throws {
        try await EditorFixture.with { f in
            let invoice = try await f.storeIssuedDollarInvoice()
            f.app.editorRequest = .edit(invoice.id)
            await f.app.openEditor()
            let editor = try #require(f.app.editor)

            // Another window records the payment.
            let sheet = PaymentSheetModel(app: f.app, invoice: invoice)
            sheet.date = civilDate("2026-10-16")
            try await sheet.save()
            editor.note = "Opraveno."

            await #expect(throws: InvoiceEditorError.invoiceChanged) {
                try await editor.saveChanges()
            }
        }
    }
}

import AppKit
import SwiftUI
import Testing
@testable import InvoicesTracker

/// The sheets of the forms of a client and of a template, shown in a window with what they load (the currencies, the
/// clients): they are 620 points wide, as the other sheets of the app are, and never taller than the window that
/// carries them, however much they hold. A hosting view that is in no window never runs the `.task` of its content, so
/// the sheets are measured in one. The row of the template form that names the bank account, the box that asks before
/// a template is deleted, the line of the preview under the first description, the chips of the clients and the
/// buttons of the template form are read as VoiceOver reads them.
@Suite(.serialized, .settlesBackups)
@MainActor
struct FormSheetViewTests {
    /// Shows `view` in a window, as a sheet is shown, and gives it and its window to `body`.
    private func inWindow<Content: View>(
        _ view: Content, _ body: (NSHostingView<Content>, NSWindow) async throws -> Void
    ) async throws {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await body(hosting, window)
    }

    /// The size the sheet asks for once the window has laid itself out.
    private func sheetSize<Content: View>(
        of hosting: NSHostingView<Content>, in window: NSWindow
    ) async throws -> CGSize {
        try await layOut(window)
        return hosting.fittingSize
    }

    /// A pound rate in the cache, so that the form of a client has a currency to load.
    private func storePoundRate(in database: Database) async throws {
        let pound = CNBRateRow(
            declaredOn: civilDate("2026-10-16"), currency: CurrencyCode("GBP")!, amount: 1, rate: decimal("27.5"))
        try await database.insertCNBRates([pound])
    }

    @Test func theClientFormIs620PointsWideAndNoTallerThanTheWindow() async throws {
        try await ClientsFixture.with { f in
            try await storePoundRate(in: f.database)
            let model = ClientFormModel(app: f.app, client: try await f.storedClient(f.bravoID))

            try await inWindow(ClientForm(model: model, cancel: {}, saved: { _ in })) { hosting, window in
                try await waitUntil { model.currencies.count == 4 }

                let size = try await sheetSize(of: hosting, in: window)

                #expect(size.width == 620)
                #expect(size.height > 300 && size.height <= 700, "The sheet is \(size.height) points tall")
            }
        }
    }

    @Test func theClientFormWithEveryErrorStillFits() async throws {
        try await ClientsFixture.with { f in
            try await storePoundRate(in: f.database)
            let model = ClientFormModel(app: f.app, client: nil)
            model.ico = "1"
            model.email = "x"
            model.dueDaysText = "x"

            try await inWindow(ClientForm(model: model, cancel: {}, saved: { _ in })) { hosting, window in
                try await waitUntil { model.currencies.count == 4 }
                let withoutErrors = try await sheetSize(of: hosting, in: window)
                await #expect(throws: FormSaveError.invalid) { try await model.save() }

                let size = try await sheetSize(of: hosting, in: window)

                #expect(model.errors.count == 4)
                #expect(size.width == 620)
                #expect(
                    size.height > withoutErrors.height && size.height <= 700, "The sheet is \(size.height) points tall")
            }
        }
    }

    @Test func theTemplateFormIs620PointsWideAndNoTallerThanTheWindowWithOneItemOrTwelve() async throws {
        try await ClientsFixture.with { f in
            let model = TemplateFormModel(app: f.app, template: nil)

            try await inWindow(TemplateForm(model: model, cancel: {}, finished: {})) { hosting, window in
                // With its clients: the pills of the two of them are in the sheet.
                try await waitUntil { model.clients.count == 2 }
                let one = try await sheetSize(of: hosting, in: window)

                for _ in 1..<EditorLimits.items {
                    model.addItem()
                }
                let twelve = try await sheetSize(of: hosting, in: window)

                #expect(model.clientID == f.alfaID)
                #expect(one.width == 620 && twelve.width == 620)
                #expect(one.height > 300 && one.height <= 700, "The sheet with one item is \(one.height) points tall")
                #expect(twelve.height <= 700, "The sheet with twelve items is \(twelve.height) points tall")
                #expect(twelve.height >= one.height)
            }
        }
    }

    /// A new template with one item, for a client whose currency has an account, shows all its fields without
    /// scrolling, the note at their end too, and no empty room under them, while the sheet stays no taller than the
    /// window.
    @Test func theNoteOfANewTemplateIsInTheSheetWithoutScrolling() async throws {
        try await ClientsFixture.with { f in
            try await f.database.saveBankAccounts([
                BankAccount(currency: .czk, accountNumber: "2000123456/2010", iban: "CZ6520100000002000123456")
            ])
            let model = TemplateFormModel(app: f.app, template: nil)

            try await inWindow(TemplateForm(model: model, cancel: {}, finished: {})) { hosting, window in
                try await waitUntil { model.clients.count == 2 && model.pickedClient != nil }
                window.setContentSize(try await sheetSize(of: hosting, in: window))
                let size = try await sheetSize(of: hosting, in: window)

                let scroll = try #require(firstScrollView(in: hosting))
                let fields = try #require(scroll.documentView).frame.height
                let shown = scroll.contentView.bounds.height
                #expect(fields <= shown + 0.5, "The fields are \(fields) points tall, the sheet shows \(shown) of them")
                #expect(shown <= fields + 0.5, "The sheet shows \(shown) points for fields \(fields) points tall")
                #expect(size.height <= 700, "The sheet is \(size.height) points tall")
            }
        }
    }

    /// The first scroll view in `view` and the views it holds.
    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView {
            return scroll
        }
        return view.subviews.lazy.compactMap { firstScrollView(in: $0) }.first
    }

    @Test func theTemplateFormOfAStoredTemplateWithDozensOfErrorsStillFits() async throws {
        try await ClientsFixture.with { f in
            let stored = try await f.store(ClientsFixture.template(for: f.alfaID))
            let model = TemplateFormModel(app: f.app, template: stored)
            for _ in 1..<EditorLimits.items {
                model.addItem()
            }
            for index in model.items.indices {
                model.items[index].quantityText = "x"
                model.items[index].unitPriceText = "y"
            }
            model.name = ""

            try await inWindow(TemplateForm(model: model, cancel: {}, finished: {})) { hosting, window in
                try await waitUntil { model.clients.count == 2 }
                await #expect(throws: FormSaveError.invalid) { try await model.save() }

                let size = try await sheetSize(of: hosting, in: window)

                #expect(model.errors.count > 20)
                #expect(size.width == 620)
                #expect(size.height <= 700, "The sheet is \(size.height) points tall")
            }
        }
    }

    /// The question before a template is deleted takes the place of the buttons and is taller than they are: with
    /// dozens of errors over it the sheet still keeps within the window, as the fields give way to both.
    @Test func theTemplateFormWithDozensOfErrorsAndTheQuestionBeforeADeletionStillFits() async throws {
        try await ClientsFixture.with { f in
            let stored = try await f.store(ClientsFixture.template(for: f.alfaID))
            let model = TemplateFormModel(app: f.app, template: stored)
            for _ in 1..<EditorLimits.items {
                model.addItem()
            }
            for index in model.items.indices {
                model.items[index].quantityText = "x"
            }

            try await inWindow(TemplateForm(model: model, cancel: {}, finished: {})) { hosting, window in
                try await waitUntil { model.clients.count == 2 }
                await #expect(throws: FormSaveError.invalid) { try await model.save() }
                model.askToDelete()

                let size = try await sheetSize(of: hosting, in: window)

                #expect(model.errors.count > 10 && model.confirmsDeletion)
                #expect(size.width == 620)
                #expect(size.height <= 700, "The sheet is \(size.height) points tall")
            }
        }
    }

    // MARK: The parts of the template form

    /// What a description may hold is said at the end of the line of the preview under the first description, and in
    /// no line of its own under the items. The form takes the focus in its name field, so the test takes its turn among
    /// the tests that type into a window (`whileTypingAlone`).
    @Test func theTemplateFormSaysWhatADescriptionMayHoldAtTheEndOfThePreview() async throws {
        try await whileTypingAlone {
            try await ClientsFixture.with { f in
                let model = TemplateFormModel(app: f.app, template: nil)
                let form = TemplateForm(model: model, cancel: {}, finished: {})
                // Today is 17. 10. 2026: the preview is for the end of October.
                let line = "Náhled: Vývoj – říjen 2026 · {měsíc}, {rok}, {month} a {year} se doplní podle DUZP"

                try await withHostedView(form, size: CGSize(width: 700, height: 900)) { window in
                    try await withAccessibilityElements {
                        try await waitUntil { frameOfText(startingWith: line, in: window) != nil }

                        #expect(frameOfText(startingWith: "V popisu lze použít", in: window) == nil)
                    }
                }
            }
        }
    }

    /// The form of a stored template chooses its client among filter chips of 28 points, its own client's selected,
    /// and its buttons are the capsules of a dialog, 32 points high: Smazat šablonu at the leading end, then Zrušit
    /// and Uložit šablonu at the trailing end. The form takes the focus in a field, so the test takes its turn among
    /// the tests that type into a window (`whileTypingAlone`).
    @Test func theTemplateFormChoosesItsClientWithChipsAndHasTheButtonsOfADialog() async throws {
        try await whileTypingAlone {
            try await ClientsFixture.with { f in
                let stored = try await f.store(ClientsFixture.template(for: f.bravoID, name: "Služby pro Bravo"))
                let model = TemplateFormModel(app: f.app, template: stored)
                let form = TemplateForm(model: model, cancel: {}, finished: {})

                try await withHostedView(form, size: CGSize(width: 700, height: 900)) { window in
                    try await withAccessibilityElements {
                        try await waitUntil { accessibilityButton(labelled: "Alfa Systems s.r.o.", in: window) != nil }
                        @MainActor func frame(of label: String) throws -> CGRect {
                            try #require(accessibilityButton(labelled: label, in: window)?.accessibilityFrame?())
                        }

                        let bravo = try #require(accessibilityButton(labelled: "Bravo Labs, Inc.", in: window))
                        let alfa = try #require(accessibilityButton(labelled: "Alfa Systems s.r.o.", in: window))
                        #expect(bravo.isAccessibilitySelected?() == true)
                        #expect(alfa.isAccessibilitySelected?() != true)
                        for chip in ["Alfa Systems s.r.o.", "Bravo Labs, Inc."] {
                            let height = try frame(of: chip).height
                            #expect((height - DesignMetrics.smallControlHeight).magnitude < 0.5, "\(chip): \(height)")
                        }
                        for button in ["Smazat šablonu", "Zrušit", "Uložit šablonu"] {
                            let height = try frame(of: button).height
                            let off = (height - DesignMetrics.regularControlHeight).magnitude
                            #expect(off < 0.5, "\(button): \(height)")
                        }
                        #expect(try frame(of: "Smazat šablonu").maxX < frame(of: "Zrušit").minX)
                        #expect(try frame(of: "Zrušit").maxX < frame(of: "Uložit šablonu").minX)
                    }
                }
            }
        }
    }

    /// The buttons of the form of a client are the capsules of a dialog, as those of the other sheets are, 32 points
    /// high: Zrušit on the grey fill and Uložit odběratele in the accent, at the trailing end. The form takes the focus
    /// in a field, so the test takes its turn among the tests that type into a window (`whileTypingAlone`).
    @Test(arguments: [ColorScheme.light, .dark])
    func theClientFormHasTheButtonsOfADialog(scheme: ColorScheme) async throws {
        try await whileTypingAlone {
            try await ClientsFixture.with { f in
                let model = ClientFormModel(app: f.app, client: try await f.storedClient(f.bravoID))
                let form = ClientForm(model: model, cancel: {}, saved: { _ in })

                try await withHostedView(form, size: CGSize(width: 700, height: 900)) { window in
                    window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                    try await withAccessibilityElements {
                        try await waitUntil { accessibilityButton(labelled: "Uložit odběratele", in: window) != nil }
                        try await layOut(window)
                        @MainActor func frame(of label: String) throws -> CGRect {
                            try #require(accessibilityButton(labelled: label, in: window)?.accessibilityFrame?())
                        }

                        for button in ["Zrušit", "Uložit odběratele"] {
                            let height = try frame(of: button).height
                            let off = (height - DesignMetrics.regularControlHeight).magnitude
                            #expect(off < 0.5, "\(scheme): \(button) is \(height) points tall")
                        }
                        #expect(try frame(of: "Zrušit").maxX < frame(of: "Uložit odběratele").minX)

                        let picture = try OffscreenPicture(of: window)
                        let cancel = try pictureFrame(ofScreenFrame: frame(of: "Zrušit"), in: window)
                        let save = try pictureFrame(ofScreenFrame: frame(of: "Uložit odběratele"), in: window)
                        let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
                        let accent = try OffscreenPicture.bytes(of: Palette.accent, in: scheme)
                        let onFill = picture.extent(near: fill, in: cancel.insetBy(dx: -2, dy: -2), by: 2)
                        let inAccent = picture.extent(near: accent, in: save.insetBy(dx: -2, dy: -2), by: 2)
                        #expect(onFill != nil, "\(scheme): Zrušit is not on the grey fill")
                        #expect(inAccent != nil, "\(scheme): Uložit odběratele is not in the accent")
                        let capsule = try #require(inAccent, "\(scheme): no accent capsule")
                        #expect(abs(capsule.height - DesignMetrics.regularControlHeight) <= 1.5, "\(capsule)")
                    }
                }
            }
        }
    }

    // MARK: The bank account of a template

    /// "Bankovní účet": the account that the invoices of the template print stands under the terms of the template (the
    /// due days and the VAT mode), and under it, in grey, where that account comes from. The form takes the focus in
    /// its name field, and so the test takes its turn among the tests that type into a window (`whileTypingAlone`).
    @Test func theTemplateFormShowsTheAccountItsInvoicesPrintAndWhereItComesFrom() async throws {
        try await whileTypingAlone {
            try await ClientsFixture.with { f in
                try await f.database.saveBankAccounts([
                    BankAccount(currency: .czk, accountNumber: "2000123456/2010", iban: "CZ6520100000002000123456")
                ])
                let model = TemplateFormModel(app: f.app, template: nil)
                let account = "2000123456/2010 · IBAN CZ6520100000002000123456"
                let source = "Tiskne se účet z Nastavení › Moje údaje podle měny faktury."
                let form = TemplateForm(model: model, cancel: {}, finished: {})

                try await withHostedView(form, size: CGSize(width: 700, height: 900)) { window in
                    try await withAccessibilityElements {
                        try await waitUntil { frameOfText(startingWith: account, in: window) != nil }

                        let label = try #require(frameOfText(startingWith: "Bankovní účet", in: window))
                        let printed = try #require(frameOfText(startingWith: account, in: window))
                        let comesFrom = try #require(frameOfText(startingWith: source, in: window))
                        let dueDays = try #require(textField(labelled: "Splatnost (dní)", in: window))
                        let terms = window.convertToScreen(frameInWindow(dueDays))
                        // The origin of the screen is at the bottom left, so what stands above has the larger y.
                        #expect(terms.minY >= label.maxY - 0.5, "The row is not under the terms: \(terms) and \(label)")
                        #expect(
                            label.minY >= printed.maxY - 0.5,
                            "The account is not under its label: \(label), \(printed)")
                        #expect(
                            printed.minY >= comesFrom.maxY - 0.5,
                            "The note is not under the account: \(printed), \(comesFrom)")
                    }
                }
            }
        }
    }

    /// Under the line that says the data holds no account in the currency of the client, the form does not say where
    /// an account comes from: the line itself says where to add one. A new template's form takes the focus in its
    /// name field, so the test takes its turn among the tests that type into a window (`whileTypingAlone`).
    @Test func theTemplateFormDoesNotSayWhereAnAccountComesFromUnderALineThatSaysThereIsNone() async throws {
        try await whileTypingAlone {
            try await ClientsFixture.with { f in
                // The data holds no account, so the first client, Alfa, in crowns, has none that its invoices print.
                let model = TemplateFormModel(app: f.app, template: nil)
                let form = TemplateForm(model: model, cancel: {}, finished: {})

                try await withHostedView(form, size: CGSize(width: 700, height: 900)) { window in
                    try await withAccessibilityElements {
                        try await waitUntil { frameOfText(startingWith: "Pro měnu CZK nemáte účet", in: window) != nil }

                        #expect(model.accountLine == .missing(.czk))
                        #expect(frameOfText(startingWith: "Bankovní účet", in: window) != nil)
                        #expect(frameOfText(startingWith: "Tiskne se účet", in: window) == nil)
                    }
                }
            }
        }
    }

    /// Under the line of an account in pounds, which Nastavení › Moje údaje has no boxes for and only imported data can
    /// hold, the form says that the account comes from the imported data, and not that it comes from Moje údaje by the
    /// currency of the invoice. A new template's form takes the focus in its name field, so the test takes its turn
    /// among the tests that type into a window (`whileTypingAlone`).
    @Test func theTemplateFormSaysAnAccountInPoundsComesFromImportedData() async throws {
        try await whileTypingAlone {
            try await ClientsFixture.with { f in
                let pounds = try #require(CurrencyCode("GBP"))
                try await f.database.saveBankAccounts([
                    BankAccount(
                        currency: pounds, accountNumber: "12345678", iban: "GB33BUKB20201555555555", bic: "BUKBGB22",
                        routingNumber: "200000", bankNameAndAddress: "Barclays, 1 Churchill Place, London")
                ])
                // A client in pounds, as an import brings one: Echo Ltd in London.
                var british = ClientsFixture.imported
                british.name = "Echo Ltd"
                british.country = "GB"
                british.currency = pounds
                british.vatMode = .outsideCountry
                let client = try await f.store(british)
                let model = TemplateFormModel(app: f.app, template: nil)
                // A client can be picked once the model has loaded its clients.
                await model.load()
                model.pickClient(client.id)
                let account = "12345678 · IBAN GB33BUKB20201555555555 · BIC BUKBGB22 · routing 200000"
                let source = "Tiskne se účet z importovaných dat. V Nastavení › Moje údaje ho neupravíte."
                let form = TemplateForm(model: model, cancel: {}, finished: {})

                try await withHostedView(form, size: CGSize(width: 700, height: 900)) { window in
                    try await withAccessibilityElements {
                        try await waitUntil { frameOfText(startingWith: account, in: window) != nil }

                        let printed = try #require(frameOfText(startingWith: account, in: window))
                        let comesFrom = try #require(frameOfText(startingWith: source, in: window))
                        // The origin of the screen is at the bottom left, so what stands above has the larger y.
                        #expect(
                            printed.minY >= comesFrom.maxY - 0.5,
                            "The hint is not under the account: \(printed), \(comesFrom)")
                        #expect(frameOfText(startingWith: "Tiskne se účet z Nastavení", in: window) == nil)
                    }
                }
            }
        }
    }

    // MARK: Deleting a template

    /// Smazat šablonu asks in a red box of the sheet, in place of its buttons, with no alert over the sheet: the title
    /// names the template and the text under it says what deleting it does. Esc is the Zrušit of the box, which deletes
    /// nothing and brings the buttons back; the Smazat šablonu of the box deletes the template and closes the sheet.
    /// The window is made the key window, which puts the focus in a field of the form, so the test takes its turn
    /// among the tests that type into a window (`whileTypingAlone`).
    @Test func theTemplateFormAsksBeforeDeletingInABoxOfItsOwn() async throws {
        try await whileTypingAlone {
            try await ClientsFixture.with { f in
                let stored = try await f.store(ClientsFixture.template(for: f.alfaID, name: "Služby pro Alfa"))
                let model = TemplateFormModel(app: f.app, template: stored)
                let calls = Calls()
                let form = TemplateForm(model: model, cancel: {}, finished: { calls.finished += 1 })
                let title = "Smazat šablonu „Služby pro Alfa“?"

                try await withHostedView(form, size: CGSize(width: 700, height: 900)) { window in
                    try await withAccessibilityElements {
                        try await waitUntil { model.clients.count == 2 }
                        try await pressButton(labelled: "Smazat šablonu", in: window)

                        try await waitUntil { frameOfText(startingWith: title, in: window) != nil }
                        #expect(window.attachedSheet == nil)
                        #expect(frameOfText(startingWith: TemplateFormModel.deleteMessage, in: window) != nil)
                        #expect(accessibilityButton(labelled: "Uložit šablonu", in: window) == nil)

                        #expect(try press(.escape, in: window))
                        try await waitUntil { accessibilityButton(labelled: "Uložit šablonu", in: window) != nil }
                        #expect(frameOfText(startingWith: title, in: window) == nil)
                        #expect(!model.confirmsDeletion)
                        #expect(try await f.database.templates() == [stored])
                        #expect(calls.finished == 0)

                        try await pressButton(labelled: "Smazat šablonu", in: window)
                        try await waitUntil { frameOfText(startingWith: title, in: window) != nil }
                        try await pressButton(labelled: "Smazat šablonu", in: window)
                        try await waitUntil { calls.finished == 1 }
                        #expect(try await f.database.templates().isEmpty)
                    }
                }
            }
        }
    }

    /// The red box that asks before what cannot be undone is a panel of the red tint with the question in bold red text
    /// and two capsules: Zrušit on the grey fill, and the answer that does it in solid red. The capsules are 32 points
    /// tall as the buttons of a sheet are, and 28 where the box stands in a card and is told so with a small control.
    @Test(arguments: [ColorScheme.light, .dark])
    func theQuestionOfABoxIsARedPanelWithTwoCapsules(scheme: ColorScheme) async throws {
        func box(_ size: String) -> some View {
            ConfirmationBox(
                title: "Smazat \(size)?", message: "Nejde to vrátit zpět.", cancelTitle: "Zrušit \(size)", cancel: {},
                confirmTitle: "Smazat \(size)", confirm: {})
        }
        let boxes = VStack(spacing: 24) {
            box("velké")
            box("malé").controlSize(.small)
        }
        .padding(24)
        .background(Palette.bgCard)

        try await withHostedView(boxes, size: CGSize(width: 520, height: 400)) { window in
            window.appearance = appearance(of: scheme)
            try await withAccessibilityElements {
                try await waitUntil { accessibilityButton(labelled: "Smazat malé", in: window) != nil }
                try await layOut(window)
                let picture = try OffscreenPicture(of: window)
                let fill = try OffscreenPicture.bytes(of: Palette.fill, in: scheme)
                let red = try OffscreenPicture.bytes(of: Palette.red, in: scheme)
                let redText = try OffscreenPicture.bytes(of: Palette.redText, in: scheme)
                let tint = try OffscreenPicture.bytes(of: Palette.redTint, in: scheme)

                for (size, height) in [("velké", CGFloat(32)), ("malé", CGFloat(28))] {
                    let confirm = try pictureFrame(
                        ofScreenFrame: try #require(
                            accessibilityButton(labelled: "Smazat \(size)", in: window)?.accessibilityFrame?()),
                        in: window)
                    let cancel = try pictureFrame(
                        ofScreenFrame: try #require(
                            accessibilityButton(labelled: "Zrušit \(size)", in: window)?.accessibilityFrame?()),
                        in: window)
                    #expect(abs(confirm.height - height) < 0.5, "Smazat \(size) is \(confirm.height) points tall")
                    #expect(abs(cancel.height - height) < 0.5, "Zrušit \(size) is \(cancel.height) points tall")
                    #expect(pixelIs(red, at: CGPoint(x: confirm.minX + 8, y: confirm.midY), in: picture))
                    #expect(pixelIs(fill, at: CGPoint(x: cancel.minX + 8, y: cancel.midY), in: picture))
                    let title = try pictureFrame(
                        ofScreenFrame: try #require(frameOfText(startingWith: "Smazat \(size)?", in: window)),
                        in: window)
                    #expect(
                        picture.count(near: redText, in: title, by: 6) > 10,
                        "\(scheme): the question is not in the red text")
                    #expect(
                        pixelIs(tint, at: CGPoint(x: title.minX - 8, y: title.midY), in: picture),
                        "\(scheme): the question is not on the red tint")
                }
            }
        }
    }

    /// What the form was told to do.
    private final class Calls {
        var finished = 0
    }

    /// Presses the button of `window` that VoiceOver reads under `label`, as a click does, once it is there.
    private func pressButton(labelled label: String, in window: NSWindow) async throws {
        try await waitUntil { accessibilityButton(labelled: label, in: window) != nil }
        let button = try #require(accessibilityButton(labelled: label, in: window))
        #expect(button.accessibilityPerformPress?() == true)
    }

    /// The currency of a template is the one of its client, so a form without a client has no account to show yet.
    @Test func theTemplateFormShowsNoAccountWhileItHasNoClient() async throws {
        try await whileTypingAlone {
            try await ClientsFixture.with { f in
                try await f.deleteClient(f.alfaID)
                try await f.deleteClient(f.bravoID)
                let model = TemplateFormModel(app: f.app, template: nil)
                let form = TemplateForm(model: model, cancel: {}, finished: {})

                try await withHostedView(form, size: CGSize(width: 700, height: 900)) { window in
                    try await withAccessibilityElements {
                        // The form has loaded its clients, of which there are none, once it says so.
                        try await waitUntil { frameOfText(startingWith: EditorText.noClients, in: window) != nil }

                        #expect(frameOfText(startingWith: "Bankovní účet", in: window) == nil)
                        #expect(frameOfText(startingWith: "Pro měnu", in: window) == nil)
                        #expect(frameOfText(startingWith: "Tiskne se účet", in: window) == nil)
                    }
                }
            }
        }
    }
}

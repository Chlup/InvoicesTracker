import Foundation
import Testing
@testable import InvoicesTracker

/// The chooser of a new invoice: a blank invoice and the templates, each with what it starts the invoice with, and what
/// choosing one, cancelling and going to the templates do. The data is the invented clients and templates of
/// `EditorFixture`. In every expected string `\u{00A0}` is the no-break space.
@Suite(.settlesBackups)
@MainActor
struct NewInvoiceChooserTests {
    @Test func theChooserOffersABlankInvoiceAndEveryTemplate() async throws {
        try await EditorFixture.with { f in
            let chooser = NewInvoiceChooserModel(app: f.app)
            #expect(chooser.rows.isEmpty)

            await chooser.load()

            #expect(chooser.title == "Nová faktura")
            #expect(chooser.subtitle == "Vyberte šablonu, nebo začněte s prázdnou fakturou.")
            #expect(
                chooser.rows == [
                    ChooserRow(
                        id: 0, title: "Prázdná faktura", subtitle: "bez předvyplnění · odběratel Alfa Systems s.r.o.",
                        amount: ""),
                    ChooserRow(
                        id: f.dollarTemplate.id, title: "Software development",
                        subtitle: "Bravo Labs, Inc. · 172\u{00A0}h × 70,00\u{00A0}USD",
                        amount: "12\u{00A0}040,00\u{00A0}USD"),
                    ChooserRow(
                        id: f.crownTemplate.id, title: "Služby pro Alfa",
                        subtitle: "Alfa Systems s.r.o. · 2 položky", amount: "4\u{00A0}600,00\u{00A0}Kč"),
                ])
            #expect(chooser.errorText == nil)
        }
    }

    @Test func aTemplateOfOneItemNamesTheItemAndOfSeveralTheirNumber() {
        let client = Client(name: "Alfa Systems s.r.o.")
        func template(items: Int) -> InvoiceTemplate {
            InvoiceTemplate(
                name: "T", clientID: 1,
                items: (0..<items).map { _ in
                    TemplateItem(description: "x", quantity: decimal("7.5"), unit: "hod", unitPriceMinor: 60_000)
                },
                vatMode: .domestic21, dueDays: 14)
        }

        let one = NewInvoiceChooserModel.row(for: template(items: 1), client: client)
        let two = NewInvoiceChooserModel.row(for: template(items: 2), client: client)
        let five = NewInvoiceChooserModel.row(for: template(items: 5), client: client)
        let none = NewInvoiceChooserModel.row(for: template(items: 0), client: client)

        #expect(one.subtitle == "Alfa Systems s.r.o. · 7,5\u{00A0}hod × 600,00\u{00A0}Kč")
        #expect(one.amount == "4\u{00A0}500,00\u{00A0}Kč")
        #expect(two.subtitle == "Alfa Systems s.r.o. · 2 položky")
        #expect(two.amount == "9\u{00A0}000,00\u{00A0}Kč")
        #expect(five.subtitle == "Alfa Systems s.r.o. · 5 položek")
        #expect(none.subtitle == "Alfa Systems s.r.o. · bez položek")
        #expect(none.amount == "0,00\u{00A0}Kč")
    }

    @Test func withoutClientsTheBlankInvoiceHasNoClientToName() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        try await startFresh(app)

        let chooser = NewInvoiceChooserModel(app: app)
        await chooser.load()

        #expect(chooser.rows == [ChooserRow(id: 0, title: "Prázdná faktura", subtitle: "bez předvyplnění", amount: "")])
    }

    @Test func choosingTheBlankInvoiceOpensAnEditorOnFakturyWithoutATemplate() async throws {
        try await EditorFixture.with { f in
            let chooser = NewInvoiceChooserModel(app: f.app)
            await chooser.load()
            f.app.screen = .overview
            f.app.editorRequest = .chooser

            chooser.choose(try #require(chooser.rows.first))

            #expect(f.app.screen == .invoices)
            #expect(f.app.editorRequest == .new(templateID: nil))
        }
    }

    @Test func choosingATemplateOpensAnEditorOnFakturyFromIt() async throws {
        try await EditorFixture.with { f in
            let chooser = NewInvoiceChooserModel(app: f.app)
            await chooser.load()
            f.app.screen = .computation
            f.app.editorRequest = .chooser

            chooser.choose(try #require(chooser.rows.first { $0.title == "Software development" }))

            #expect(f.app.screen == .invoices)
            #expect(f.app.editorRequest == .new(templateID: f.dollarTemplate.id))
        }
    }

    @Test func cancellingClosesTheChooserAndStaysOnTheScreen() async throws {
        try await EditorFixture.with { f in
            let chooser = NewInvoiceChooserModel(app: f.app)
            f.app.screen = .computation
            f.app.editorRequest = .chooser

            chooser.cancel()

            #expect(f.app.editorRequest == nil)
            #expect(f.app.screen == .computation)
        }
    }

    @Test func cancellingShowsTheEditorTheChooserWasOpenOver() async throws {
        try await EditorFixture.with { f in
            let chooser = NewInvoiceChooserModel(app: f.app)
            f.app.startNewInvoice(templateID: f.dollarTemplate.id)
            f.app.editorRequest = .chooser

            chooser.cancel()

            #expect(f.app.editorRequest == .new(templateID: f.dollarTemplate.id))
            #expect(f.app.screen == .invoices)
        }
    }

    @Test func spravovatSablonyGoesToTheTemplates() async throws {
        try await EditorFixture.with { f in
            let chooser = NewInvoiceChooserModel(app: f.app)
            f.app.screen = .overview
            f.app.editorRequest = .chooser

            chooser.manageTemplates()

            #expect(f.app.editorRequest == nil)
            #expect(f.app.screen == .templates)
        }
    }

    @Test func spravovatSablonyLeavesTheEditorItWasOpenOverWhereItIs() async throws {
        try await EditorFixture.with { f in
            let chooser = NewInvoiceChooserModel(app: f.app)
            f.app.startNewInvoice(templateID: nil)
            f.app.editorRequest = .chooser

            chooser.manageTemplates()

            #expect(f.app.editorRequest == .new(templateID: nil))
            #expect(f.app.requestBeforeChooser == nil)
            #expect(f.app.shownEditorRequest == .new(templateID: nil))
            #expect(f.app.screen == .templates)
        }
    }

    @Test func aTemplateWhoseClientIsGoneIsStillOfferedWithoutAClient() {
        var template = InvoiceTemplate(
            name: "Bez odběratele", clientID: 99,
            items: [TemplateItem(description: "x", quantity: decimal("2"), unit: "ks", unitPriceMinor: 10_000)],
            vatMode: .domestic21, dueDays: 14)
        template.id = 5
        var empty = template
        empty.items = []

        let row = NewInvoiceChooserModel.row(for: template, client: nil)
        let none = NewInvoiceChooserModel.row(for: empty, client: nil)

        // Its amounts are in no currency, so they are not shown.
        #expect(row == ChooserRow(id: 5, title: "Bez odběratele", subtitle: "bez odběratele · 1 položka", amount: ""))
        #expect(none.subtitle == "bez odběratele · bez položek")
    }

    @Test func theRowsOfTheChooserOfferEveryTemplateWhetherOrNotItsClientIsThere() async throws {
        try await EditorFixture.with { f in
            // The two reads of the chooser can come apart: the client is deleted between them. The editor handles a
            // template without a client by asking for one.
            let rows = NewInvoiceChooserModel.rows(templates: [f.dollarTemplate], clients: [])

            #expect(rows.map(\.title) == ["Prázdná faktura", "Software development"])
            #expect(rows.first?.subtitle == "bez předvyplnění")
            #expect(rows.last?.subtitle == "bez odběratele · 1 položka")
        }
    }

    @Test func aChooserThatCannotLoadSaysSoAndStillOffersABlankInvoice() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        // No data is open: the app model has no database.
        let app = makeAppModel(in: directory)
        let chooser = NewInvoiceChooserModel(app: app)

        await chooser.load()

        #expect(chooser.errorText == "Šablony se nepodařilo načíst.")
        #expect(chooser.rows == [ChooserRow(id: 0, title: "Prázdná faktura", subtitle: "bez předvyplnění", amount: "")])
    }
}

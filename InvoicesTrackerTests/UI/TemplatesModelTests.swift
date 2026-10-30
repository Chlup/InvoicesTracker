import Foundation
import Testing
@testable import InvoicesTracker

/// The cards of Šablony faktur: what each says of its template, and what the buttons of the screen do.
@Suite(.settlesBackups)
@MainActor
struct TemplatesModelTests {
    private func loaded(_ app: AppModel) async -> TemplatesModel {
        let model = TemplatesModel(app: app)
        await model.load()
        return model
    }

    // MARK: The cards

    @Test func theCardsSayWhatTheTemplatesAreInTheOrderTheyWereMade() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)

            let cards = try #require(model.cards)

            #expect(
                cards == [
                    TemplateCard(
                        id: f.dollarTemplate.id, name: "Software development", client: "Bravo Labs, Inc.",
                        itemLines: ["172\u{00A0}h × 70,00\u{00A0}USD · Software development {month} {year}"],
                        options: "splatnost 30 dní"
                            + " · Mimo tuzemsko – § 9 odst. 1 (bez DPH) · s poznámkou"),
                    TemplateCard(
                        id: f.crownTemplate.id, name: "Služby pro Alfa", client: "Alfa Systems s.r.o.",
                        itemLines: [
                            "7,5\u{00A0}hod × 600,00\u{00A0}Kč · Služby {měsíc} {rok}",
                            "1\u{00A0}ks × 100,00\u{00A0}Kč · Hosting",
                        ],
                        options: "splatnost 14 dní · Tuzemsko 21 %"),
                ])
            #expect(model.errorText == nil)
        }
    }

    @Test func aTemplateOfAClientThatIsNotThereIsWrittenForAnUnknownClientInCrowns() {
        let template = InvoiceTemplate(
            name: "Osiřelá", clientID: 99,
            items: [TemplateItem(description: "", quantity: decimal("2"), unit: "", unitPriceMinor: 12_345)],
            vatMode: .none, dueDays: 1, duzpAtMonthEnd: true, note: "  ")

        let card = TemplateCardBuilder.cards(templates: [template], clients: [])[0]

        #expect(card.client == "Neznámý odběratel")
        #expect(card.itemLines == ["2 × 123,45\u{00A0}Kč"])
        #expect(card.options == "splatnost 1 den · Bez DPH")
    }

    @Test func theCardsLoadAgainWhenTheAppSaysItWroteOrDeleted() async throws {
        try await ClientsFixture.with { f in
            let template = try await f.store(ClientsFixture.template(for: f.alfaID))
            let model = await loaded(f.app)
            #expect(model.cards?.map(\.name) == ["Měsíční služby"])

            let form = try #require(model.form(editing: template.id))
            form.name = "Přejmenovaná"
            try await form.save()
            await model.load()
            #expect(model.cards?.map(\.name) == ["Přejmenovaná"])

            try await form.delete()
            await model.load()
            #expect(model.cards == [])
        }
    }

    @Test func aLoadThatFailsSaysSoInPlaceOfTheCards() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = TemplatesModel(app: makeAppModel(in: directory))

        await model.load()

        #expect(model.cards == nil)
        #expect(model.errorText == "Šablony se nepodařilo načíst.")
    }

    @Test func theScreenHasNoCardsBeforeTheFirstLoad() async throws {
        try await ClientsFixture.with { f in
            let model = TemplatesModel(app: f.app)

            #expect(model.cards == nil)
            #expect(model.errorText == nil)
        }
    }

    // MARK: The buttons

    @Test func upravitOpensTheFormOfTheTemplateAsLoadedAndNovaSablonaThatOfANewOne() async throws {
        try await ClientsFixture.with { f in
            let template = try await f.store(ClientsFixture.template(for: f.alfaID, name: "Služby pro Alfa"))
            let model = await loaded(f.app)

            let edit = try #require(model.form(editing: template.id))
            #expect(!edit.isNew)
            #expect(edit.template == template)
            #expect(edit.name == "Služby pro Alfa")

            #expect(model.newTemplateForm().isNew)
            #expect(model.form(editing: 999) == nil)
        }
    }

    /// What the question before a deletion says: the invoices made from the template are not touched.
    @Test func anInvoiceMadeFromATemplateStaysAsItWasAfterTheTemplateIsDeleted() async throws {
        try await EditorFixture.with { f in
            let editor = await f.newEditor(template: f.dollarTemplate)
            let id = try await editor.saveDraft()
            let before = try await f.stored(id)
            #expect(before.items.map(\.description) == ["Software development October 2026"])
            #expect(before.note == "Payment due within 30 days.")
            let form = TemplateFormModel(app: f.app, template: f.dollarTemplate)

            try await form.delete()

            let templates = try await f.database.templates()
            #expect(templates.map(\.id) == [f.crownTemplate.id])
            #expect(try await f.stored(id) == before)
        }
    }

    @Test func pouzitOpensANewInvoiceMadeFromTheTemplateOnFaktury() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)
            f.app.screen = .templates

            model.use(f.crownTemplate.id)

            #expect(f.app.screen == .invoices)
            #expect(f.app.editorRequest == .new(templateID: f.crownTemplate.id))
            await f.app.openEditor()
            let editor = try #require(f.app.editor)
            #expect(editor.template == f.crownTemplate)
            #expect(editor.clientID == f.alfaID)
            #expect(editor.items.map(\.description) == ["Služby říjen 2026", "Hosting"])
        }
    }
}

import Foundation
import Testing
@testable import InvoicesTracker

/// Odběratelé: the summary row on top of the table, with the clients and the templates counted in Czech and the money
/// received in whole Kč; the rows, one line each, with what each says of its client and of the year, in the order of
/// the names in Czech, and what VoiceOver reads for a row; which client is selected, from a click, from a save and
/// across a change of the year; and what the buttons of the screen and of the detail do.
@Suite(.settlesBackups)
@MainActor
struct ClientsModelTests {
    private func loaded(_ app: AppModel) async -> ClientsModel {
        let model = ClientsModel(app: app)
        await model.load()
        return model
    }

    /// What the builder makes of `clients`, `templates` and `figures` (by the ids of the clients) in `year`.
    private func built(
        clients: [Client], templates: [InvoiceTemplate] = [], figures: [Int64: ClientFigures] = [:], year: Int = 2026
    ) -> ClientsData {
        ClientsBuilder.build(ClientsInput(year: year, clients: clients, templates: templates, figures: figures))
    }

    /// The row the builder makes of `client` (whose id is 0, as a client that is not stored has it) with `templates`
    /// templates of its own and `figures`.
    private func builtRow(of client: Client, templates: Int = 0, figures: ClientFigures? = nil) throws -> ClientRow {
        let own = (0..<templates).map { ClientsFixture.template(for: client.id, name: "Šablona \($0)") }
        let data = built(clients: [client], templates: own, figures: figures.map { [client.id: $0] } ?? [:])
        return try #require(data.rows.first)
    }

    /// `count` clients with the ids 1, 2, and so on.
    private func clients(_ count: Int) -> [Client] {
        (0..<count).map { Client(id: Int64($0 + 1), name: "Klient \($0 + 1)") }
    }

    /// What a client paid in a year, `halere` haléře, and nothing else.
    private func received(_ halere: Int64) -> ClientFigures {
        ClientFigures(invoiceCount: 0, receivedHalere: halere, lastIssueDate: nil)
    }

    // MARK: The summary row

    @Test(arguments: [
        (0, "0\u{00A0}odběratelů"), (1, "1\u{00A0}odběratel"), (2, "2\u{00A0}odběratelé"), (4, "4\u{00A0}odběratelé"),
        (5, "5\u{00A0}odběratelů"), (21, "21\u{00A0}odběratelů"),
    ])
    func theSummaryCountsTheClientsInCzech(count: Int, text: String) {
        #expect(built(clients: clients(count)).countText == text)
    }

    @Test(arguments: [
        (0, " · 0\u{00A0}šablon faktur"), (1, " · 1\u{00A0}šablona faktur"), (2, " · 2\u{00A0}šablony faktur"),
        (4, " · 4\u{00A0}šablony faktur"), (5, " · 5\u{00A0}šablon faktur"),
    ])
    func theSummaryCountsTheTemplatesInCzechAfterTheClients(count: Int, text: String) {
        // Every template of the data counts, of whichever client.
        let both = clients(2)
        let templates = (0..<count).map { ClientsFixture.template(for: both[$0 % 2].id, name: "Šablona \($0)") }

        #expect(built(clients: both, templates: templates).templatesText == text)
    }

    /// The total is the money the clients paid in the year in whole Kč, rounded once from the sum in haléře: two
    /// clients that paid 100,50 Kč each have 101 Kč in their rows, and 201 Kč in the summary.
    @Test func theTotalIsTheMoneyReceivedInWholeKcRoundedOnceFromTheSum() {
        let both = clients(2)

        let data = built(clients: both, figures: [1: received(10_050), 2: received(10_050)])

        #expect(data.rows.map(\.received) == ["101\u{00A0}Kč", "101\u{00A0}Kč"])
        #expect(data.totalText == "201\u{00A0}Kč")
        #expect(built(clients: both).totalText == "0\u{00A0}Kč")
    }

    @Test func theColumnOfTheMoneyIsNamedAfterTheYear() {
        #expect(built(clients: clients(1), year: 2026).receivedHeader == "Přijato 2026")
        #expect(built(clients: clients(1), year: 2025).receivedHeader == "Přijato 2025")
    }

    // MARK: The rows

    @Test func theSummaryAndTheRowsSayWhatTheClientsAreAndWhatTheyDidInTheYear() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)

            let data = try #require(model.data)

            #expect(data.countText == "3\u{00A0}odběratelé")
            #expect(data.templatesText == " · 2\u{00A0}šablony faktur")
            // 305 726,75 Kč from Bravo and 4 500,00 Kč from Cetus.
            #expect(data.totalText == "310\u{00A0}227\u{00A0}Kč")
            #expect(data.receivedHeader == "Přijato 2026")
            #expect(
                data.rows == [
                    ClientRow(
                        id: f.alfaID, name: "Alfa Systems s.r.o.", currency: "CZK", vatShort: "DPH 21 %",
                        templates: "1\u{00A0}šablona", received: "—"),
                    ClientRow(
                        id: f.bravoID, name: "Bravo Labs, Inc.", currency: "USD", vatShort: "mimo tuzemsko",
                        templates: "1\u{00A0}šablona", received: "305\u{00A0}727\u{00A0}Kč"),
                    ClientRow(
                        id: f.cetusID, name: "Cetus Data s.r.o.", currency: "CZK", vatShort: "DPH 21 %",
                        templates: "žádná", received: "4\u{00A0}500\u{00A0}Kč"),
                ])
            #expect(model.errorText == nil)
        }
    }

    @Test func theRowsFollowTheYearAndTheDayShown() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)

            // Bravo and Cetus were paid on 2. 10. and on 15. 10.: on 1. 10. the money has not come.
            f.app.pickAsOf(civilDate("2026-10-01"))
            await model.load()
            #expect(model.data?.rows.map(\.received) == Array(repeating: "—", count: 3))
            #expect(model.data?.totalText == "0\u{00A0}Kč")

            f.app.selectYear(2025)
            await model.load()
            #expect(model.data?.receivedHeader == "Přijato 2025")
            #expect(model.data?.rows.map(\.received) == Array(repeating: "—", count: 3))
            // The templates are not of a year.
            #expect(model.data?.rows.map(\.templates) == ["1\u{00A0}šablona", "1\u{00A0}šablona", "žádná"])
        }
    }

    /// The database puts "Čapek" before "Cibulka" and "Chalupa" before "Hrubý", as it ignores diacritics and reads
    /// "Ch" as two letters. In Czech "Č" is a letter of its own after "C", and "Ch" is one after "H".
    @Test func rowsAreSortedByNameWithCzechCollation() async throws {
        try await ClientsFixture.with { f in
            for name in ["Dvořák", "Čapek", "Chalupa a.s.", "Cibulka", "Hrubý s.r.o."] {
                try await f.store(Client(name: name))
            }

            let model = await loaded(f.app)

            #expect(
                model.data?.rows.map(\.name) == [
                    "Alfa Systems s.r.o.", "Bravo Labs, Inc.", "Cibulka", "Čapek", "Dvořák", "Hrubý s.r.o.",
                    "Chalupa a.s.",
                ])
        }
    }

    @Test func theRowSaysWhatWasReceivedInTheYearInWholeKc() async throws {
        try await ClientsFixture.with { f in
            // Three invoices of 2026 for Alfa, paid with 50 000,00 Kč, 50 000,00 Kč and 6 720,00 Kč before the day
            // shown, 17. 10. 2026.
            let invoices = [
                ("20260201", "2026-02-27", "2026-03-10", Int64(5_000_000)),
                ("20260601", "2026-06-30", "2026-07-15", Int64(5_000_000)),
                ("20261001", "2026-10-15", "2026-10-16", Int64(672_000)),
            ]
            for (number, issued, paid, net) in invoices {
                var invoice = Invoice.fixture(
                    number: number, issued: issued, duzp: issued, payment: .fixture(on: paid, net: net))
                invoice.clientID = f.alfaID
                try await f.database.saveInvoice(invoice)
            }

            let model = await loaded(f.app)

            let alfa = try #require(model.data?.rows.first { $0.id == f.alfaID })
            #expect(alfa.received == "106\u{00A0}720\u{00A0}Kč")
            #expect(alfa.hasReceived)
            // Bravo has paid nothing.
            let bravo = try #require(model.data?.rows.first { $0.id == f.bravoID })
            #expect(bravo.received == "—")
            #expect(!bravo.hasReceived)
            #expect(model.data?.totalText == "106\u{00A0}720\u{00A0}Kč")
        }
    }

    @Test func theNumberOfTemplatesOfAClientIsInCzechAndNoneIsZadna() throws {
        let texts = try [0, 1, 2, 4, 5, 21].map { try builtRow(of: Client(name: "Alfa"), templates: $0).templates }

        #expect(
            texts == [
                "žádná", "1\u{00A0}šablona", "2\u{00A0}šablony", "4\u{00A0}šablony", "5\u{00A0}šablon",
                "21\u{00A0}šablon",
            ])
        #expect(try !builtRow(of: Client(name: "Alfa")).hasTemplates)
        #expect(try builtRow(of: Client(name: "Alfa"), templates: 1).hasTemplates)
    }

    /// A template counts in the row of its own client and in the summary, and in no other row.
    @Test func aTemplateCountsInTheRowOfItsClientAndInTheSummary() async throws {
        try await ClientsFixture.with { f in
            let model = await loaded(f.app)
            #expect(model.data?.rows.map(\.templates) == ["žádná", "žádná"])
            #expect(model.data?.templatesText == " · 0\u{00A0}šablon faktur")

            try await f.store(ClientsFixture.template(for: f.bravoID, name: "Měsíční služby"))
            try await f.store(ClientsFixture.template(for: f.bravoID, name: "Podpora"))
            await model.load()

            #expect(model.data?.rows.map(\.templates) == ["žádná", "2\u{00A0}šablony"])
            #expect(model.data?.templatesText == " · 2\u{00A0}šablony faktur")
        }
    }

    @Test func aClientWithNoFiguresHasReceivedNothing() throws {
        let row = try builtRow(of: Client(name: "Alfa"))

        #expect(row.received == "—")
        #expect(!row.hasReceived)
    }

    @Test func aClientThatWasInvoicedButHasNotPaidHasReceivedNothing() throws {
        let figures = ClientFigures(invoiceCount: 1, receivedHalere: 0, lastIssueDate: civilDate("2026-10-15"))

        let row = try builtRow(of: Client(name: "Alfa"), figures: figures)

        #expect(row.received == "—")
        #expect(!row.hasReceived)
    }

    @Test func moneyForAnInvoiceOfAnEarlierYearIsReceivedWithNoInvoiceIssued() throws {
        let row = try builtRow(of: Client(name: "Alfa"), figures: received(450_000))

        #expect(row.received == "4\u{00A0}500\u{00A0}Kč")
        #expect(row.hasReceived)
    }

    // MARK: What the row leaves to the detail

    /// The row is one line: the city, the country and the IČO of the client belong to its detail, not to its row, which
    /// is the same whatever they are.
    @Test(arguments: [
        ("Brno", "CZ", "87654321"), ("Brno", "cz", ""), ("Wien", "AT", "ATU12345678"), ("Austin, TX", "US", ""),
        ("", "DE", ""), ("", "CZ", "12345678"), ("Praha", "Česká republika", ""), ("Praha", "Česko", ""),
        ("Berlin", "Brazil", "HRB 123456"), ("  Brno ", "CZ", " 87654321 "), ("", "CZ", ""), ("", "", ""),
    ])
    func theRowSaysNothingOfTheCityTheCountryOrTheICO(city: String, country: String, ico: String) throws {
        var client = Client(name: "Alfa")
        client.city = city
        client.country = country
        client.ico = ico

        #expect(try builtRow(of: client) == builtRow(of: Client(name: "Alfa")))
    }

    /// The street, the postcode, the city, the numbers, the e-mail, the phone, the way of payment, the due days and the
    /// language of the invoices belong to the detail of the client, not to its row.
    @Test func theRowLeavesTheAddressTheNumbersTheContactsAndTheTermsToTheDetail() throws {
        var client = Client(
            name: "Alfa", street: "Hlavní 1", postcode: "261 01", city: "Příbram", country: "CZ", ico: "12345678",
            dic: "CZ12345678", email: "ucetni@example.com", phone: "+420 777 000 111", dueDays: 99,
            paymentMethod: "Hotově")
        client.language = .en

        let row = try builtRow(of: client)

        let said = row.spokenText(receivedHeader: "Přijato 2026")
        let shown = [row.name, row.currency, row.vatShort, row.templates, row.received]
        for left in ["Hlavní", "261 01", "Příbram", "12345678", "ucetni@", "777", "99", "Hotově", "anglicky"] {
            #expect(!said.contains(left), "\(left) in \(said)")
            #expect(!shown.contains { $0.contains(left) }, "\(left) in \(shown)")
        }
        #expect(said.hasPrefix("Alfa, "))
    }

    // MARK: The currency and the VAT

    @Test(arguments: [
        (VatMode.domestic21, "DPH 21 %"), (VatMode.domestic12, "DPH 12 %"), (VatMode.outsideCountry, "mimo tuzemsko"),
        (VatMode.euReverseCharge, "přenesená povinnost"), (VatMode.none, "bez DPH"),
    ])
    func theVatModeIsSaidInAFewWords(mode: VatMode, text: String) throws {
        var client = Client(name: "Alfa")
        client.vatMode = mode

        #expect(try builtRow(of: client).vatShort == text)
    }

    @Test func theCurrencyIsSaidByItsCode() throws {
        var client = Client(name: "Alfa")
        #expect(try builtRow(of: client).currency == "CZK")

        client.currency = .usd
        #expect(try builtRow(of: client).currency == "USD")
    }

    // MARK: The import

    /// The row of a client the import created and nobody has edited says no more than that of the same client entered
    /// in the app, or edited since: nothing on the screen tells how a client came into the app.
    @Test func anImportedClientShowsNoImportMark() async throws {
        try await ClientsFixture.with { f in
            let imported = try await f.store(ClientsFixture.imported)
            #expect(imported.origin == .imported && !imported.editedAfterImport)
            let model = await loaded(f.app)
            let shown = try #require(model.data?.rows.first { $0.id == imported.id })

            var byHand = imported
            byHand.origin = .app
            var edited = imported
            edited.editedAfterImport = true
            for twin in [byHand, edited] {
                let twinRow = try #require(built(clients: [twin]).rows.first)
                #expect(shown == twinRow)
            }
            // The name of the client is its own, "Delta Import GmbH"; nothing else in the row may say "import".
            let texts = [shown.currency, shown.vatShort, shown.templates, shown.received]
            #expect(texts.allSatisfy { !$0.localizedCaseInsensitiveContains("import") }, "\(texts)")
        }
    }

    /// A client of the import with a country and a registration number the app does not know as such has the row of any
    /// other client: its currency and VAT mode as stored.
    @Test func aClientOfTheImportHasTheRowOfAnyOtherClient() async throws {
        try await ClientsFixture.with { f in
            var client = ClientsFixture.imported
            client.country = "Brazil"
            client.ico = "HRB 123456"
            try await f.store(client)

            let row = try #require(await loaded(f.app).data?.rows.first { $0.name == "Delta Import GmbH" })

            #expect(row.currency == "EUR")
            #expect(row.vatShort == "přenesená povinnost")
            #expect(row.templates == "žádná")
            #expect(row.received == "—")
        }
    }

    // MARK: What VoiceOver reads

    @Test func aRowIsReadWithTheNamesOfItsColumns() {
        let row = ClientRow(
            id: 1, name: "Cetus Data s.r.o.", currency: "CZK", vatShort: "DPH 21 %", templates: "žádná",
            received: "4\u{00A0}500\u{00A0}Kč")

        let expected = "Cetus Data s.r.o., Měna a DPH CZK, DPH 21 %, Šablony žádná, Přijato 2026 4\u{00A0}500\u{00A0}Kč"
        #expect(row.spokenText(receivedHeader: "Přijato 2026") == expected)
    }

    /// The money received is left out where nothing came, as the dash in its column says nothing to a listener.
    @Test func aRowOfAClientThatPaidNothingIsReadWithoutTheMoney() {
        let row = ClientRow(
            id: 2, name: "Bez údajů", currency: "USD", vatShort: "mimo tuzemsko", templates: "1\u{00A0}šablona",
            received: "—")

        let expected = "Bez údajů, Měna a DPH USD, mimo tuzemsko, Šablony 1\u{00A0}šablona"
        #expect(row.spokenText(receivedHeader: "Přijato 2025") == expected)
    }

    // MARK: Loading

    @Test func theRowsLoadAgainWhenTheAppSaysItWrote() async throws {
        try await ClientsFixture.with { f in
            let model = await loaded(f.app)
            #expect(model.data?.rows.count == 2)

            let form = model.newClientForm()
            form.name = "Epsilon Group a.s."
            try await form.save()
            await model.load()

            #expect(
                model.data?.rows.map(\.name) == ["Alfa Systems s.r.o.", "Bravo Labs, Inc.", "Epsilon Group a.s."])
            #expect(model.data?.countText == "3\u{00A0}odběratelé")
        }
    }

    @Test func aLoadThatFailsSaysSoInPlaceOfTheTable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = ClientsModel(app: makeAppModel(in: directory))

        await model.load()

        #expect(model.data == nil)
        #expect(model.errorText == "Odběratele se nepodařilo načíst.")
    }

    @Test func theScreenHasNoTableBeforeTheFirstLoad() async throws {
        try await ClientsFixture.with { f in
            let model = ClientsModel(app: f.app)

            #expect(model.data == nil)
            #expect(model.errorText == nil)
        }
    }

    @Test func withoutClientsTheTableSaysSoUnderItsSummary() {
        let data = built(clients: [])

        #expect(data.rows.isEmpty)
        #expect(data.emptyText == "Zatím nemáte žádného odběratele.")
        #expect(data.countText == "0\u{00A0}odběratelů")
        #expect(built(clients: clients(1)).emptyText == nil)
    }

    // MARK: The selection

    @Test func nothingIsSelectedAfterTheLoad() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)

            #expect(model.data != nil)
            #expect(model.selectedClientID == nil)
        }
    }

    @Test func aClickSelectsTheClientAndASecondClickClearsIt() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)

            model.click(f.bravoID)
            #expect(model.selectedClientID == f.bravoID)
            model.click(f.cetusID)
            #expect(model.selectedClientID == f.cetusID)
            model.click(f.cetusID)
            #expect(model.selectedClientID == nil)

            model.click(f.alfaID)
            model.closeDetail()
            #expect(model.selectedClientID == nil)
        }
    }

    /// A load that finds the selected client gone (deleted in another window, or by a restore) clears the selection; a
    /// load that finds it keeps it.
    @Test func theSelectionIsClearedWhenItsClientDisappears() async throws {
        try await ClientsFixture.with { f in
            let model = await loaded(f.app)
            model.click(f.bravoID)
            await model.load()
            #expect(model.selectedClientID == f.bravoID)

            try await f.deleteClient(f.bravoID)
            await model.load()

            #expect(model.selectedClientID == nil)
            #expect(model.data?.rows.map(\.name) == ["Alfa Systems s.r.o."])
        }
    }

    /// The selected client stays selected when another year is shown, and its row says what it paid in that year.
    @Test func theSelectionSurvivesAChangeOfTheYear() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)
            model.click(f.bravoID)

            f.app.selectYear(2025)
            await model.load()
            #expect(model.selectedClientID == f.bravoID)
            #expect(model.data?.rows.first { $0.id == f.bravoID }?.received == "—")

            f.app.selectYear(2026)
            await model.load()
            #expect(model.selectedClientID == f.bravoID)
            #expect(model.data?.rows.first { $0.id == f.bravoID }?.received == "305\u{00A0}727\u{00A0}Kč")
        }
    }

    /// A client saved in the form of Nový odběratel becomes the selected one, also while another client is selected,
    /// and a client saved in its own form stays selected.
    @Test func aClientSavedThroughTheFormBecomesTheSelectedOne() async throws {
        try await ClientsFixture.with { f in
            let model = await loaded(f.app)
            model.click(f.alfaID)

            let form = model.newClientForm()
            form.name = "Epsilon Group a.s."
            let id = try await form.save()
            model.didSaveClient(id)
            await model.load()

            #expect(model.selectedClientID == id)
            #expect(model.data?.rows.contains { $0.id == id && $0.name == "Epsilon Group a.s." } == true)

            let edit = try #require(model.form(editing: id))
            edit.name = "Epsilon Group, a.s."
            let editedID = try await edit.save()
            model.didSaveClient(editedID)
            await model.load()

            #expect(model.selectedClientID == id)
        }
    }

    // MARK: The buttons

    @Test func upravitOpensTheFormOfTheClientAsLoadedAndNovyOdberatelThatOfANewOne() async throws {
        try await ClientsFixture.with { f in
            let model = await loaded(f.app)

            let edit = try #require(model.form(editing: f.bravoID))
            #expect(!edit.isNew)
            #expect(edit.client.id == f.bravoID)
            #expect(edit.name == "Bravo Labs, Inc.")

            let new = model.newClientForm()
            #expect(new.isNew)
            #expect(model.form(editing: 999) == nil)
        }
    }

    @Test func upravitOfATemplateOpensItsFormAsLoaded() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)

            let form = try #require(model.templateForm(editing: f.dollarTemplate.id))
            #expect(!form.isNew)
            #expect(form.template?.id == f.dollarTemplate.id)
            #expect(form.name == "Software development")
            #expect(form.clientID == f.bravoID)
            #expect(model.templateForm(editing: 999) == nil)
        }
    }

    @Test func novaFakturaOpensABlankInvoiceForTheClientOnFaktury() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)
            f.app.screen = .clients

            model.newInvoice(forClient: f.cetusID)

            #expect(f.app.screen == .invoices)
            #expect(f.app.editorRequest == .new(templateID: nil, clientID: f.cetusID))
            await f.app.openEditor()
            let editor = try #require(f.app.editor)
            #expect(editor.template == nil)
            #expect(editor.clientID == f.cetusID)
            #expect(editor.pickedClient?.name == "Cetus Data s.r.o.")
            #expect(editor.vatMode == .domestic21)
            #expect(editor.dueDays == 14)
        }
    }

    @Test func theInvoiceForAClientTakesItsTermsAndNotThoseOfTheFirstClient() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)

            model.newInvoice(forClient: f.bravoID)
            await f.app.openEditor()

            let editor = try #require(f.app.editor)
            #expect(editor.clientID == f.bravoID)
            #expect(editor.vatMode == .outsideCountry)
            #expect(editor.dueDays == 30)
            #expect(editor.terms?.currency == .usd)
        }
    }

    @Test func aClientThatWasDeletedMeanwhileGivesAnInvoiceWithTheFirstClient() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)
            try await deleteClientRow(f.bravoID, in: f.database)

            model.newInvoice(forClient: f.bravoID)
            await f.app.openEditor()

            let editor = try #require(f.app.editor)
            #expect(editor.clientID == f.alfaID)
        }
    }

    @Test func novaFakturaAsksBeforeItThrowsAwayAnInvoiceThatIsBeingWritten() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)
            f.app.startNewInvoice(templateID: nil)
            await f.app.openEditor()
            let editor = try #require(f.app.editor)
            editor.note = "Něco jsem napsal."
            #expect(f.app.editorHasChanges)
            f.app.screen = .clients

            model.newInvoice(forClient: f.cetusID)

            #expect(f.app.pendingDiscard == .newInvoice(templateID: nil, clientID: f.cetusID))
            #expect(f.app.editorRequest == .new(templateID: nil, clientID: nil))
            f.app.confirmDiscard()
            #expect(f.app.editorRequest == .new(templateID: nil, clientID: f.cetusID))
            #expect(f.app.screen == .invoices)
        }
    }
}

import Foundation
import Testing
@testable import InvoicesTracker

/// The rows of Odběratelé: what each says of its client and of the year, in the order of the names in Czech, what
/// VoiceOver reads for a row, and what the buttons of the screen do.
@Suite(.settlesBackups)
@MainActor
struct ClientsModelTests {
    private func loaded(_ app: AppModel) async -> ClientsModel {
        let model = ClientsModel(app: app)
        await model.load()
        return model
    }

    /// The row the builder makes of `client` (whose id is 0, as a client that is not stored has it) with `figures`.
    private func builtRow(of client: Client, figures: ClientFigures? = nil) throws -> ClientRow {
        try #require(ClientRowBuilder.rows(clients: [client], figures: figures.map { [0: $0] } ?? [:]).first)
    }

    // MARK: The rows

    @Test func theRowsSayWhatTheClientsAreAndWhatTheyDidInTheYear() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)

            let rows = try #require(model.rows)

            #expect(
                rows == [
                    ClientRow(
                        id: f.alfaID, name: "Alfa Systems s.r.o.", detailLine: "Příbram · IČO 12345678",
                        currency: "CZK", vatShort: "DPH 21 %", language: "česky", received: "nic nepřijato",
                        countLine: "žádná faktura"),
                    ClientRow(
                        id: f.bravoID, name: "Bravo Labs, Inc.", detailLine: "Austin, TX · Spojené státy americké",
                        currency: "USD", vatShort: "mimo tuzemsko", language: "anglicky",
                        received: "přijato 305\u{00A0}726,75\u{00A0}Kč",
                        countLine: "1 faktura · poslední 30.\u{00A0}9."),
                    ClientRow(
                        id: f.cetusID, name: "Cetus Data s.r.o.", detailLine: "Brno · IČO 87654321", currency: "CZK",
                        vatShort: "DPH 21 %", language: "česky", received: "přijato 4\u{00A0}500,00\u{00A0}Kč",
                        countLine: "1 faktura · poslední 30.\u{00A0}9."),
                ])
            #expect(model.year == 2026)
            #expect(model.errorText == nil)
        }
    }

    @Test func theRowsFollowTheYearAndTheDayShown() async throws {
        try await EditorFixture.with { f in
            let model = await loaded(f.app)

            // Bravo and Cetus were issued an invoice on 30. 9. 2026 and were paid on 2. 10. and on 15. 10.: on 1. 10.
            // the invoices are there and the money is not.
            f.app.pickAsOf(civilDate("2026-10-01"))
            await model.load()
            #expect(model.rows?.map(\.received) == Array(repeating: "nic nepřijato", count: 3))
            #expect(
                model.rows?.map(\.countLine) == [
                    "žádná faktura", "1 faktura · poslední 30.\u{00A0}9.", "1 faktura · poslední 30.\u{00A0}9.",
                ])

            // On 29. 9. the invoices are not issued yet: they are neither counted nor the last one.
            f.app.pickAsOf(civilDate("2026-09-29"))
            await model.load()
            #expect(model.rows?.map(\.countLine) == Array(repeating: "žádná faktura", count: 3))

            f.app.selectYear(2025)
            await model.load()
            #expect(model.year == 2025)
            #expect(model.rows?.map(\.received) == Array(repeating: "nic nepřijato", count: 3))
            #expect(model.rows?.map(\.countLine) == Array(repeating: "žádná faktura", count: 3))
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
                model.rows?.map(\.name) == [
                    "Alfa Systems s.r.o.", "Bravo Labs, Inc.", "Cibulka", "Čapek", "Dvořák", "Hrubý s.r.o.",
                    "Chalupa a.s.",
                ])
        }
    }

    @Test func theRowSaysWhatWasReceivedAndWhenTheLastInvoiceWasIssued() async throws {
        try await ClientsFixture.with { f in
            // Three invoices of 2026 for Alfa, the last issued on 15. 10., paid with 50 000,00 Kč, 50 000,00 Kč and
            // 6 720,00 Kč before the day shown, 17. 10. 2026.
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

            let alfa = try #require(model.rows?.first { $0.id == f.alfaID })
            #expect(alfa.received == "přijato 106\u{00A0}720,00\u{00A0}Kč")
            #expect(alfa.countLine == "3 faktury · poslední 15.\u{00A0}10.")
            // Bravo has done nothing.
            let bravo = try #require(model.rows?.first { $0.id == f.bravoID })
            #expect(bravo.received == "nic nepřijato")
            #expect(bravo.countLine == "žádná faktura")
        }
    }

    @Test func theNumberOfInvoicesIsInCzechForOneTwoFourAndFive() {
        let counts = [0, 1, 2, 4, 5, 21].map { WelcomeTexts.invoiceCount($0) }

        #expect(counts == ["0 faktur", "1 faktura", "2 faktury", "4 faktury", "5 faktur", "21 faktur"])
    }

    @Test func theCountLineHasTheNumberOfInvoicesInCzechAndTheDayOfTheLastOne() throws {
        let lastDay = civilDate("2026-10-15")
        let lines = try [0, 1, 2, 4, 5, 21].map { count in
            let figures = ClientFigures(
                invoiceCount: count, receivedHalere: 0, lastIssueDate: count == 0 ? nil : lastDay)
            return try builtRow(of: Client(name: "Alfa"), figures: figures).countLine
        }

        let day = "poslední 15.\u{00A0}10."
        #expect(
            lines == [
                "žádná faktura", "1 faktura · \(day)", "2 faktury · \(day)", "4 faktury · \(day)",
                "5 faktur · \(day)", "21 faktur · \(day)",
            ])
    }

    @Test func aClientWithNoFiguresHasDoneNothing() throws {
        let row = try builtRow(of: Client(name: "Alfa"))

        #expect(row.received == "nic nepřijato")
        #expect(!row.hasReceived)
        #expect(row.countLine == "žádná faktura")
    }

    @Test func aClientThatWasInvoicedButHasNotPaidHasReceivedNothing() throws {
        let figures = ClientFigures(invoiceCount: 1, receivedHalere: 0, lastIssueDate: civilDate("2026-10-15"))

        let row = try builtRow(of: Client(name: "Alfa"), figures: figures)

        #expect(row.received == "nic nepřijato")
        #expect(!row.hasReceived)
        #expect(row.countLine == "1 faktura · poslední 15.\u{00A0}10.")
    }

    @Test func moneyForAnInvoiceOfAnEarlierYearIsReceivedWithNoInvoiceIssued() throws {
        let figures = ClientFigures(invoiceCount: 0, receivedHalere: 450_000, lastIssueDate: nil)

        let row = try builtRow(of: Client(name: "Alfa"), figures: figures)

        #expect(row.received == "přijato 4\u{00A0}500,00\u{00A0}Kč")
        #expect(row.hasReceived)
        #expect(row.countLine == "žádná faktura")
    }

    // MARK: The line under the name

    /// The city, the country unless it is Česko, and the IČO, in that order, as far as the client has them. A country
    /// that the import left as typed stays as typed, and so do the names of Česko that the import knows.
    @Test(arguments: [
        ("Brno", "CZ", "87654321", "Brno · IČO 87654321"),
        ("Brno", "cz", "", "Brno"),
        ("Wien", "AT", "ATU12345678", "Wien · Rakousko · IČO ATU12345678"),
        ("Austin, TX", "US", "", "Austin, TX · Spojené státy americké"),
        ("", "DE", "", "Německo"),
        ("", "CZ", "12345678", "IČO 12345678"),
        ("Praha", "Česká republika", "", "Praha"),
        ("Praha", "Česko", "", "Praha"),
        ("Berlin", "Brazil", "HRB 123456", "Berlin · Brazil · IČO HRB 123456"),
        ("  Brno ", "CZ", " 87654321 ", "Brno · IČO 87654321"),
        ("", "CZ", "", "—"),
        ("", "", "", "—"),
    ])
    func theLineUnderTheNameHasTheCityTheCountryUnlessItIsCzechiaAndTheICO(
        city: String, country: String, ico: String, line: String
    ) throws {
        var client = Client(name: "Alfa")
        client.city = city
        client.country = country
        client.ico = ico

        #expect(try builtRow(of: client).detailLine == line)
    }

    /// The street, the postcode, the DIČ, the e-mail, the phone, the way of payment and the due days are shown in the
    /// form of the client, which a click on the row opens, not in the row.
    @Test func theRowLeavesTheStreetTheDICTheEmailAndTheTermsToTheForm() throws {
        let client = Client(
            name: "Alfa", street: "Hlavní 1", postcode: "261 01", city: "Příbram", country: "CZ", ico: "12345678",
            dic: "CZ12345678", email: "ucetni@example.com", phone: "+420 777 000 111", dueDays: 99,
            paymentMethod: "Hotově")

        let row = try builtRow(of: client)

        let said = row.spokenText(year: 2026)
        for left in ["Hlavní", "261 01", "CZ12345678", "ucetni@", "777", "99", "Hotově"] {
            #expect(!said.contains(left), "\(left) in \(said)")
        }
        #expect(said.contains("Příbram") && said.contains("12345678"))
    }

    // MARK: The currency, the VAT and the language

    @Test(arguments: [
        (VatMode.domestic21, "DPH 21 %"), (VatMode.domestic12, "DPH 12 %"), (VatMode.outsideCountry, "mimo tuzemsko"),
        (VatMode.euReverseCharge, "přenesená povinnost"), (VatMode.none, "bez DPH"),
    ])
    func theVatModeIsSaidInAFewWords(mode: VatMode, text: String) throws {
        var client = Client(name: "Alfa")
        client.vatMode = mode

        #expect(try builtRow(of: client).vatShort == text)
    }

    @Test func theCurrencyAndTheLanguageAreSaidAsTheInvoiceHasThem() throws {
        var client = Client(name: "Alfa")
        #expect(try builtRow(of: client).currency == "CZK")
        #expect(try builtRow(of: client).language == "česky")

        client.currency = .usd
        client.language = .en
        #expect(try builtRow(of: client).currency == "USD")
        #expect(try builtRow(of: client).language == "anglicky")
    }

    // MARK: The import

    /// The row of a client the import created and nobody has edited says no more than that of the same client entered
    /// in the app, or edited since: nothing on the screen tells how a client came into the app.
    @Test func anImportedClientShowsNoImportMark() async throws {
        try await ClientsFixture.with { f in
            let imported = try await f.store(ClientsFixture.imported)
            #expect(imported.origin == .imported && !imported.editedAfterImport)
            let model = await loaded(f.app)
            let shown = try #require(model.rows?.first { $0.id == imported.id })

            var byHand = imported
            byHand.origin = .app
            var edited = imported
            edited.editedAfterImport = true
            for twin in [byHand, edited] {
                let twinRow = try #require(ClientRowBuilder.rows(clients: [twin], figures: [:]).first)
                #expect(shown == twinRow)
            }
            let texts = [
                shown.detailLine, shown.currency, shown.vatShort, shown.language, shown.received, shown.countLine,
            ]
            #expect(texts.allSatisfy { !$0.localizedCaseInsensitiveContains("import") }, "\(texts)")
        }
    }

    @Test func aClientOfTheImportKeepsItsCountryAndRegistrationAsTheRowWritesThem() async throws {
        try await ClientsFixture.with { f in
            var client = ClientsFixture.imported
            client.country = "Brazil"
            client.ico = "HRB 123456"
            try await f.store(client)

            let row = try #require(await loaded(f.app).rows?.first { $0.name == "Delta Import GmbH" })

            #expect(row.detailLine == "Berlin · Brazil · IČO HRB 123456")
            #expect(row.vatShort == "přenesená povinnost")
            #expect(row.currency == "EUR")
            #expect(row.language == "anglicky")
        }
    }

    // MARK: What VoiceOver reads

    @Test func aRowIsReadWithTheNamesOfItsColumns() {
        let row = ClientRow(
            id: 1, name: "Cetus Data s.r.o.", detailLine: "Brno · IČO 87654321", currency: "CZK", vatShort: "DPH 21 %",
            language: "česky", received: "přijato 4\u{00A0}500,00\u{00A0}Kč",
            countLine: "1 faktura · poslední 30.\u{00A0}9.")

        let expected =
            "Cetus Data s.r.o., Brno, IČO 87654321, Měna a DPH CZK, DPH 21 %, Jazyk faktury česky,"
            + " Rok 2026: přijato 4\u{00A0}500,00\u{00A0}Kč, 1 faktura, poslední 30.\u{00A0}9."
        #expect(row.spokenText(year: 2026) == expected)
    }

    @Test func aRowWithNothingToSayAboutTheClientOrTheYearIsReadWithoutTheDash() {
        let row = ClientRow(
            id: 2, name: "Bez údajů", detailLine: "—", currency: "USD", vatShort: "mimo tuzemsko", language: "anglicky",
            received: "nic nepřijato", countLine: "žádná faktura")

        let expected =
            "Bez údajů, Měna a DPH USD, mimo tuzemsko, Jazyk faktury anglicky, Rok 2025: nic nepřijato, žádná faktura"
        #expect(row.spokenText(year: 2025) == expected)
    }

    // MARK: Loading

    @Test func theRowsLoadAgainWhenTheAppSaysItWrote() async throws {
        try await ClientsFixture.with { f in
            let model = await loaded(f.app)
            #expect(model.rows?.count == 2)

            let form = model.newClientForm()
            form.name = "Epsilon Group a.s."
            try await form.save()
            await model.load()

            #expect(model.rows?.map(\.name) == ["Alfa Systems s.r.o.", "Bravo Labs, Inc.", "Epsilon Group a.s."])
        }
    }

    @Test func aLoadThatFailsSaysSoInPlaceOfTheRows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let model = ClientsModel(app: makeAppModel(in: directory))

        await model.load()

        #expect(model.rows == nil)
        #expect(model.errorText == "Odběratele se nepodařilo načíst.")
    }

    @Test func theScreenHasNoRowsBeforeTheFirstLoad() async throws {
        try await ClientsFixture.with { f in
            let model = ClientsModel(app: f.app)

            #expect(model.rows == nil)
            #expect(model.errorText == nil)
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

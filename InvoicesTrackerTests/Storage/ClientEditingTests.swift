import Foundation
import Testing
@testable import InvoicesTracker

/// What the forms of a client and of a template write: the changes to a stored one, which never bring back one that
/// was deleted meanwhile, and what Odběratelé says of a client in a year.
struct ClientEditingTests {
    private static func client(name: String = "Delta Studio s.r.o.") -> Client {
        Client(
            name: name, street: "Lipová 8", postcode: "130 00", city: "Praha", country: "CZ", ico: "11223344",
            dic: "CZ11223344", email: "delta@example.com", phone: "+420 777 000 111", dueDays: 30,
            paymentMethod: "Převodem", language: .cs
        )
    }

    private static func template(clientID: Int64, name: String = "Měsíční služby") -> InvoiceTemplate {
        InvoiceTemplate(
            name: name, clientID: clientID,
            items: [
                TemplateItem(
                    description: "Služby {měsíc} {rok}", quantity: decimal("7.5"), unit: "hod", unitPriceMinor: 60_000)
            ],
            vatMode: .domestic21, dueDays: 14, duzpAtMonthEnd: true, note: "")
    }

    // MARK: Updating a client

    @Test func updatingAStoredClientChangesItInPlaceAndKeepsItsTemplates() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var client = Self.client()
        client.id = try await database.saveClient(client)
        let template = Self.template(clientID: client.id)
        try await database.saveTemplate(template)

        client.name = "Delta Studio a.s."
        client.vatMode = .none
        try await database.updateClient(client)

        #expect(try await database.clients() == [client])
        #expect(try await database.templates().map(\.clientID) == [client.id])
    }

    @Test func updatingAClientThatIsNotStoredWritesNothingAndSaysSo() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var gone = Self.client()
        gone.id = 7
        let writes = await database.writeCount

        await #expect(throws: ClientError.notFound) { try await database.updateClient(gone) }
        var unsaved = Self.client()
        unsaved.id = 0
        await #expect(throws: ClientError.notFound) { try await database.updateClient(unsaved) }

        #expect(try await database.clients().isEmpty)
        // `saveClient` brings a client with an id back; the form of a client that was deleted must not.
        #expect(await database.writeCount == writes)
    }

    @Test func updatingAClientMakesTheSearchDocumentsOfItsInvoicesAgain() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        var client = SearchFixtures.alfa
        client.id = try await database.saveClient(client)
        try await database.saveInvoice(SearchFixtures.crownInvoice(clientID: client.id))
        let asOf = civilDate("2026-10-17")
        #expect(try await database.searchInvoiceIDs("zlatnice", scope: .issued, year: 2026, asOf: asOf).isEmpty)

        client.name = "Zlatnice Systems s.r.o."
        try await database.updateClient(client)

        #expect(try await database.searchInvoiceIDs("zlatnice", scope: .issued, year: 2026, asOf: asOf).count == 1)
    }

    // MARK: Updating a template

    @Test func updatingAStoredTemplateReplacesItsContentsAndItsItemsAndKeepsItsId() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        var template = Self.template(clientID: clientID)
        template.id = try await database.saveTemplate(template)

        template.name = "Roční licence"
        template.items = [
            TemplateItem(description: "Licence {rok}", quantity: decimal("12"), unit: "měs.", unitPriceMinor: 99_900),
            TemplateItem(description: "Podpora", quantity: decimal("1"), unit: "ks", unitPriceMinor: 0),
        ]
        template.duzpAtMonthEnd = false
        template.note = "Děkuji"
        try await database.updateTemplate(template)

        #expect(try await database.templates() == [template])
        #expect(try await database.integer("SELECT count(*) FROM template_item") == 2)
    }

    @Test func updatingATemplateThatIsNotStoredWritesNothingAndSaysSo() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        var gone = Self.template(clientID: clientID)
        gone.id = 5
        let writes = await database.writeCount

        await #expect(throws: TemplateError.notFound) { try await database.updateTemplate(gone) }
        gone.id = 0
        await #expect(throws: TemplateError.notFound) { try await database.updateTemplate(gone) }

        #expect(try await database.templates().isEmpty)
        #expect(try await database.integer("SELECT count(*) FROM template_item") == 0)
        #expect(await database.writeCount == writes)
    }

    @Test func aTemplateUpdatedToAClientThatIsGoneKeepsItsOldContents() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let clientID = try await database.saveClient(Self.client())
        var template = Self.template(clientID: clientID)
        template.id = try await database.saveTemplate(template)

        var broken = template
        broken.clientID = 99
        broken.items = []
        await #expect { try await database.updateTemplate(broken) } throws: { isConstraintViolation($0) }

        #expect(try await database.templates() == [template])
    }

    // MARK: What a client did in a year

    private func store(_ database: Database, client: Client, invoices: (Int64) -> [Invoice]) async throws -> Int64 {
        let id = try await database.saveClient(client)
        for invoice in invoices(id) {
            try await database.saveInvoice(invoice)
        }
        return id
    }

    @Test func aClientHasItsIssuedInvoicesOfTheYearAndTheMoneyReceivedByTheDay() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let alfa = try await store(database, client: SearchFixtures.alfa) { id in
            [SearchFixtures.crownInvoice(clientID: id), SearchFixtures.earlierCrownInvoice(clientID: id)]
        }
        let bravo = try await store(database, client: SearchFixtures.bravo) { id in
            [SearchFixtures.dollarInvoice(clientID: id)]
        }
        let cetus = try await database.saveClient(ClientEditingTests.client())

        let figures = try await database.clientFigures(year: 2026, asOf: civilDate("2026-10-17"))

        // The invoice of 2025 is not in 2026, in the count, in the money or in the day of the last invoice.
        #expect(
            figures[alfa]
                == ClientFigures(invoiceCount: 1, receivedHalere: 450_000, lastIssueDate: civilDate("2026-09-30")))
        #expect(
            figures[bravo]
                == ClientFigures(invoiceCount: 1, receivedHalere: 30_572_675, lastIssueDate: civilDate("2026-09-30")))
        #expect(figures[cetus] == nil)
    }

    @Test func moneyThatHasNotArrivedByTheDayShownIsNotReceivedYet() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let alfa = try await store(database, client: SearchFixtures.alfa) { id in
            [SearchFixtures.crownInvoice(clientID: id)]
        }
        let bravo = try await store(database, client: SearchFixtures.bravo) { id in
            [SearchFixtures.dollarInvoice(clientID: id)]
        }

        // The crown invoice was paid on 15. 10. 2026 and the dollar one on 2. 10. 2026.
        let figures = try await database.clientFigures(year: 2026, asOf: civilDate("2026-10-02"))

        let issuedOn = civilDate("2026-09-30")
        #expect(figures[alfa] == ClientFigures(invoiceCount: 1, receivedHalere: 0, lastIssueDate: issuedOn))
        #expect(figures[bravo] == ClientFigures(invoiceCount: 1, receivedHalere: 30_572_675, lastIssueDate: issuedOn))
        let before = try await database.clientFigures(year: 2026, asOf: civilDate("2026-09-30"))
        #expect(before[alfa] == ClientFigures(invoiceCount: 1, receivedHalere: 0, lastIssueDate: issuedOn))
        #expect(before[bravo] == ClientFigures(invoiceCount: 1, receivedHalere: 0, lastIssueDate: issuedOn))
    }

    @Test func aPastYearIsShownWhole() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let alfa = try await store(database, client: SearchFixtures.alfa) { id in
            [SearchFixtures.crownInvoice(clientID: id), SearchFixtures.earlierCrownInvoice(clientID: id)]
        }

        let figures = try await database.clientFigures(year: 2025, asOf: civilDate("2025-12-31"))

        #expect(
            figures[alfa]
                == ClientFigures(invoiceCount: 1, receivedHalere: 450_000, lastIssueDate: civilDate("2025-09-30")))
    }

    @Test func aDraftIsNotCountedAndAnInvoiceInReviewIsCountedButNotReceived() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let alfa = try await store(database, client: SearchFixtures.alfa) { id in
            var draft = SearchFixtures.crownInvoice(clientID: id)
            draft.number = "20260905"
            draft.status = .draft
            draft.payment = nil
            var review = SearchFixtures.crownInvoice(clientID: id)
            review.number = "20260906"
            review.review = ReviewFlag(reason: "Záporná částka")
            return [draft, review]
        }

        let figures = try await database.clientFigures(year: 2026, asOf: civilDate("2026-10-17"))

        #expect(
            figures[alfa]
                == ClientFigures(invoiceCount: 1, receivedHalere: 0, lastIssueDate: civilDate("2026-09-30")))
    }

    /// An invoice of the fixture linked to the client `clientID`, issued and supplied on `day` (written `YYYY-MM-DD`),
    /// with no payment.
    private static func invoice(
        _ number: String, issued day: String, status: InvoiceStatus = .issued, clientID: Int64
    ) -> Invoice {
        var invoice = Invoice.fixture(number: number, issued: day, duzp: day, status: status)
        invoice.clientID = clientID
        return invoice
    }

    @Test func lastIssueDateIsTheLatestNonDraftInvoiceOfTheYear() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let alfa = try await store(database, client: SearchFixtures.alfa) { id in
            [
                Self.invoice("20260601", issued: "2026-06-30", clientID: id),
                Self.invoice("20261001", issued: "2026-10-15", clientID: id),
                Self.invoice("20260301", issued: "2026-03-05", clientID: id),
                // Dated after all of them, but a draft is not issued.
                Self.invoice("20261101", issued: "2026-11-20", status: .draft, clientID: id),
                SearchFixtures.earlierCrownInvoice(clientID: id),
            ]
        }
        // Money of 2026 for an invoice of 2025: a client with figures in 2026 and no invoice issued in it.
        let bravo = try await store(database, client: SearchFixtures.bravo) { id in
            var invoice = Self.invoice("20251201", issued: "2025-12-30", clientID: id)
            invoice.payment = Payment.fixture(on: "2026-01-02")
            return [invoice]
        }
        let delta = try await store(database, client: ClientEditingTests.client()) { id in
            [Self.invoice("20260701", issued: "2026-07-01", status: .draft, clientID: id)]
        }
        let epsilon = try await database.saveClient(ClientEditingTests.client(name: "Epsilon s.r.o."))

        let figures = try await database.clientFigures(year: 2026, asOf: civilDate("2026-10-17"))

        #expect(figures[alfa]?.invoiceCount == 3)
        #expect(figures[alfa]?.lastIssueDate == civilDate("2026-10-15"))
        #expect(figures[bravo]?.invoiceCount == 0)
        #expect(figures[bravo]?.receivedHalere == 450_000)
        #expect(figures[bravo]?.lastIssueDate == nil)
        // A draft alone and no invoice at all give no figures, so no day.
        #expect(figures[delta] == nil)
        #expect(figures[epsilon] == nil)

        // The year before has its own latest day, and a year with no invoice has no day.
        let before = try await database.clientFigures(year: 2025, asOf: civilDate("2025-12-31"))
        #expect(before[alfa]?.lastIssueDate == civilDate("2025-09-30"))
        #expect(before[bravo]?.lastIssueDate == civilDate("2025-12-30"))
        #expect(try await database.clientFigures(year: 2024, asOf: civilDate("2024-12-31")).isEmpty)
    }

    /// The day shown, "K datu", cuts the invoices of the year as it cuts the money: an invoice issued after it is
    /// neither counted nor the last one, and one issued on it is.
    @Test func anInvoiceIssuedAfterTheDayShownIsNeitherCountedNorTheLastOne() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let alfa = try await store(database, client: SearchFixtures.alfa) { id in
            [
                Self.invoice("20260301", issued: "2026-03-05", clientID: id),
                Self.invoice("20260601", issued: "2026-06-30", clientID: id),
                Self.invoice("20261001", issued: "2026-10-15", clientID: id),
            ]
        }
        func figures(asOf day: String) async throws -> ClientFigures? {
            try await database.clientFigures(year: 2026, asOf: civilDate(day))[alfa]
        }

        // Before the first of them nothing of the year was issued yet, and nor was anything before the year.
        #expect(try await figures(asOf: "2026-03-04") == nil)
        #expect(try await database.clientFigures(year: 2026, asOf: civilDate("2025-12-31")).isEmpty)
        // The day of an invoice counts it.
        #expect(
            try await figures(asOf: "2026-03-05")
                == ClientFigures(invoiceCount: 1, receivedHalere: 0, lastIssueDate: civilDate("2026-03-05")))
        // Between two of them the later one is not there yet.
        #expect(
            try await figures(asOf: "2026-10-14")
                == ClientFigures(invoiceCount: 2, receivedHalere: 0, lastIssueDate: civilDate("2026-06-30")))
        // After all of them, in the year and after the year, they are all there.
        for day in ["2026-10-15", "2026-12-31", "2027-05-01"] {
            #expect(
                try await figures(asOf: day)
                    == ClientFigures(invoiceCount: 3, receivedHalere: 0, lastIssueDate: civilDate("2026-10-15")),
                "as of \(day)")
        }
    }

    @Test func moneyIsReceivedInTheYearOfThePaymentWhateverTheYearOfTheInvoice() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let alfa = try await store(database, client: SearchFixtures.alfa) { id in
            var invoice = SearchFixtures.crownInvoice(clientID: id)
            invoice.number = "20251201"
            invoice.issueDate = civilDate("2025-12-30")
            invoice.duzp = civilDate("2025-12-30")
            invoice.dueDate = civilDate("2026-01-13")
            invoice.payment = Payment.fixture(on: "2026-01-02")
            return [invoice]
        }

        let ofIssue = try await database.clientFigures(year: 2025, asOf: civilDate("2025-12-31"))
        let ofPayment = try await database.clientFigures(year: 2026, asOf: civilDate("2026-10-17"))

        #expect(
            ofIssue[alfa]
                == ClientFigures(invoiceCount: 1, receivedHalere: 0, lastIssueDate: civilDate("2025-12-30")))
        // Money arrived in 2026 for an invoice of 2025: received in 2026, and no invoice issued in it.
        #expect(ofPayment[alfa] == ClientFigures(invoiceCount: 0, receivedHalere: 450_000, lastIssueDate: nil))
    }

    /// A screen asks for one year, and the statements find that year's rows in an index, so they cost the same with one
    /// year of invoices stored and with ten.
    @Test func theStatementsOfTheFiguresSearchIndexesAndNeverScanATable() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let year: [SQLValue] = [.day(civilDate("2026-01-01")), .day(civilDate("2026-12-31"))]
        let statements = [
            ("issued invoices", ClientQueries.issuedInvoices), ("received money", ClientQueries.receivedMoney),
        ]

        for (name, sql) in statements {
            let plan = try await database.read { connection in
                try connection.query("EXPLAIN QUERY PLAN " + sql, year).map { $0.text(3) }
            }
            #expect(plan.contains { $0.hasPrefix("SEARCH") }, "\(name): \(plan)")
            for table in ["invoice", "payment"] {
                #expect(!plan.contains { $0.hasPrefix("SCAN \(table)") }, "\(name) scans \(table): \(plan)")
            }
        }
    }

    @Test func anInvoiceWithoutAClientBelongsToNoone() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveInvoice(SearchFixtures.crownInvoice(clientID: nil))

        #expect(try await database.clientFigures(year: 2026, asOf: civilDate("2026-10-17")).isEmpty)
    }
}

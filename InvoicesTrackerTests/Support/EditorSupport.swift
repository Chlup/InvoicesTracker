import Foundation
import Testing
@testable import InvoicesTracker

/// The data the tests of the invoice editor and of its chooser work on: an app model of a temporary folder, as of
/// 17. 10. 2026, with the invented supplier and accounts of the invoice page, three invented clients (Alfa and Cetus in
/// crowns, Bravo in dollars), the sample year 2026 without its October draft (so that October has no invoice yet, and
/// August and September have two each), the ČNB rates of the fixtures (the newest is 16. 10. 2026) and two templates.
/// The server answers what `http` says (nothing, unless a test gives it files), after `gate` where a test gives one,
/// and the clock of the app is `clock` (noon of 17. 10. 2026, a Saturday).
@MainActor
struct EditorFixture {
    let app: AppModel
    let database: Database
    let clock: ManualClock
    let http: StubHTTPClient

    /// The temporary folder the data are in, for a test that opens them again with another app model.
    let directory: URL

    /// The ids the database gave the clients.
    let alfaID: Int64
    let bravoID: Int64
    let cetusID: Int64

    /// 176 hours at 70,00 USD for Bravo Labs with the description "Software development {month} {year}", due in 30
    /// days, the DUZP at the end of the month and a note.
    let dollarTemplate: InvoiceTemplate

    /// 7,5 hours at 600,00 Kč plus 1 piece at 100,00 Kč for Alfa Systems, the DUZP on the day shown.
    let crownTemplate: InvoiceTemplate

    static let cetus = Client(
        name: "Cetus Data s.r.o.", street: "Zahradní 5", postcode: "602 00", city: "Brno", country: "CZ",
        ico: "87654321", dic: "CZ87654321", email: "fakturace@example.com")

    /// Runs `body` with a fixture in a temporary folder that is removed afterwards. With a `gate`, every request to the
    /// server waits at it before `http` answers it, so that a test can look at what goes on while a file is on its way.
    static func with(
        http: StubHTTPClient = StubHTTPClient(), gate: Gate? = nil,
        clock: ManualClock = ManualClock(localNoon(2026, 10, 17)), _ body: (EditorFixture) async throws -> Void
    ) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        try await body(try await make(in: directory, http: http, gate: gate, clock: clock))
    }

    /// The fixture in `directory`: its server answers what `http` says, after `gate` where there is one, and its clock
    /// is `clock`.
    static func make(
        in directory: URL, http: StubHTTPClient, gate: Gate? = nil, clock: ManualClock
    ) async throws -> EditorFixture {
        let server: any HTTPClient
        if let gate {
            server = GatedHTTPClient(base: http, gate: gate)
        } else {
            server = http
        }
        let app = makeAppModel(in: directory, clock: clock, http: server)
        try await startFresh(app)
        let database = try #require(app.database)
        try await database.saveSupplier(InvoicePageFixtures.supplier)
        try await database.saveBankAccounts(InvoicePageFixtures.accounts)
        let alfaID = try await database.saveClient(SearchFixtures.alfa)
        var bravo = SearchFixtures.bravo
        bravo.dueDays = 30
        bravo.paymentMethod = "ACH (USD)"
        let bravoID = try await database.saveClient(bravo)
        let cetusID = try await database.saveClient(cetus)
        try await SampleYear2026.store(in: database)
        // The sample year ends with a draft for October; the tests need an October without an invoice.
        try await database.deleteInvoice(id: 12)
        // The invoices of the sample are written for a client that has since been deleted: two are linked to theirs.
        var dollars = try #require(try await database.invoice(id: 10))
        dollars.clientID = bravoID
        dollars.invoiceRate = storedRate("USD", "21.359", declaredOn: "2026-09-30")
        try await database.saveInvoice(dollars)
        var crowns = try #require(try await database.invoice(id: 11))
        crowns.clientID = cetusID
        try await database.saveInvoice(crowns)
        let dollarTemplate = InvoiceTemplate(
            name: "Software development", clientID: bravoID,
            items: [
                TemplateItem(
                    description: "Software development {month} {year}", quantity: decimal("172"), unit: "h",
                    unitPriceMinor: 7_000)
            ],
            vatMode: .outsideCountry, dueDays: 30, duzpAtMonthEnd: true, note: "Payment due within 30 days.")
        var storedDollarTemplate = dollarTemplate
        storedDollarTemplate.id = try await database.saveTemplate(dollarTemplate)
        let crownTemplate = InvoiceTemplate(
            name: "Služby pro Alfa", clientID: alfaID,
            items: [
                TemplateItem(
                    description: "Služby {měsíc} {rok}", quantity: decimal("7.5"), unit: "hod", unitPriceMinor: 60_000),
                TemplateItem(description: "Hosting", quantity: decimal("1"), unit: "ks", unitPriceMinor: 10_000),
            ],
            vatMode: .domestic21, dueDays: 14, duzpAtMonthEnd: false, note: "")
        var storedCrownTemplate = crownTemplate
        storedCrownTemplate.id = try await database.saveTemplate(crownTemplate)
        await app.didWriteAndBackUp()
        return EditorFixture(
            app: app, database: database, clock: clock, http: http, directory: directory, alfaID: alfaID,
            bravoID: bravoID, cetusID: cetusID, dollarTemplate: storedDollarTemplate,
            crownTemplate: storedCrownTemplate)
    }

    /// Adds the dollar rates of the yearly files of `years` to the cache of the ČNB.
    func addDollarRates(ofYears years: [Int]) async throws {
        try await database.insertCNBRates(try cnbYearlyRows(years).filter { $0.currency == .usd })
    }

    // MARK: Editors

    /// A new invoice, blank or from `template`, with the data loaded as the screen loads it.
    func newEditor(template: InvoiceTemplate? = nil) async -> InvoiceEditorModel {
        let model = InvoiceEditorModel(app: app, template: template, editing: nil)
        await model.load()
        return model
    }

    /// The editor of the stored invoice `id`.
    func editor(editing id: Int64) async throws -> InvoiceEditorModel {
        let invoice = try #require(try await database.invoice(id: id))
        let model = InvoiceEditorModel(app: app, template: nil, editing: invoice)
        await model.load()
        return model
    }

    // MARK: Invoices

    /// Stores an invoice of 100 hours at 70,00 USD for Bravo, supplied on 30. 9. 2026, issued on `issued` (the day of
    /// supply unless given) and due on 30. 10. 2026, with the rate of the day of supply fixed on it (21,359, which is
    /// not the one of the fixtures, 21,522), and returns it as stored.
    @discardableResult
    func storeIssuedDollarInvoice(
        number: String = "20260903", issued: String? = nil, payment: Payment? = nil, source: InvoiceSource = .app,
        status: InvoiceStatus = .issued, review: ReviewFlag? = nil
    ) async throws -> Invoice {
        var invoice = Invoice.fixture(
            number: number, currency: .usd, issued: issued, dueDate: "2026-10-30",
            items: [
                InvoiceItem(
                    description: "Software development", quantity: decimal("100"), unit: "h", unitPriceMinor: 7_000)
            ],
            vatMode: .outsideCountry, invoiceRate: storedRate("USD", "21.359", declaredOn: "2026-09-30"),
            status: status, review: review, payment: payment)
        invoice.clientID = bravoID
        invoice.client = ClientSnapshot(client: SearchFixtures.bravo)
        invoice.language = .en
        invoice.paymentMethod = "ACH (USD)"
        invoice.source = source
        invoice.id = try await database.saveInvoice(invoice)
        return invoice
    }

    /// Records an issue unless `expected` invoices are stored, drafts included.
    func expectInvoiceCount(_ expected: Int, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let count = try await database.invoiceCount()
        #expect(count == expected, sourceLocation: sourceLocation)
    }

    /// The invoice `id` as stored.
    func stored(_ id: Int64) async throws -> Invoice {
        try #require(try await database.invoice(id: id))
    }
}

extension EditableItem {
    /// An item of the editor as a person would have typed it.
    static func typed(_ description: String, _ quantity: String, _ unit: String, _ price: String) -> EditableItem {
        EditableItem(description: description, quantityText: quantity, unit: unit, unitPriceText: price)
    }
}

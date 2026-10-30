import Foundation
import Testing
@testable import InvoicesTracker

/// The data the tests of the forms and of the screens Odběratelé and Šablony faktur work on: an app model of a
/// temporary folder, as of 17. 10. 2026, with two invented clients that are stored, Alfa Systems (crowns, Tuzemsko
/// 21 %, 14 days, Czech) and Bravo Labs (dollars, outside the country, 30 days, English), and nothing else.
@MainActor
struct ClientsFixture {
    let app: AppModel
    let database: Database

    /// The ids the database gave the clients.
    let alfaID: Int64
    let bravoID: Int64

    /// Runs `body` with a fixture in a temporary folder that is removed afterwards.
    static func with(_ body: (ClientsFixture) async throws -> Void) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory)
        try await startFresh(app)
        let database = try #require(app.database)
        let alfaID = try await database.saveClient(SearchFixtures.alfa)
        var bravo = SearchFixtures.bravo
        bravo.dueDays = 30
        bravo.paymentMethod = "ACH (USD)"
        let bravoID = try await database.saveClient(bravo)
        await app.didWriteAndBackUp()
        try await body(ClientsFixture(app: app, database: database, alfaID: alfaID, bravoID: bravoID))
    }

    /// Stores `client` and tells the app, as a screen that wrote it would; returns it with the id it got.
    @discardableResult
    func store(_ client: Client) async throws -> Client {
        var stored = client
        stored.id = try await database.saveClient(client)
        await app.didWriteAndBackUp()
        return stored
    }

    /// Stores `template` and tells the app; returns it with the id it got.
    @discardableResult
    func store(_ template: InvoiceTemplate) async throws -> InvoiceTemplate {
        var stored = template
        stored.id = try await database.saveTemplate(template)
        await app.didWriteAndBackUp()
        return stored
    }

    /// The client `id` as stored.
    func storedClient(_ id: Int64) async throws -> Client {
        try #require(try await database.client(id: id))
    }

    /// Deletes the client `id` and its templates, as the deletion of a client by another window would, without telling
    /// this app.
    func deleteClient(_ id: Int64) async throws {
        try await deleteClientRow(id, in: database)
    }

    /// A client created by the import, which has not been edited since: Delta Import in Berlin, in euros.
    static let imported = Client(
        name: "Delta Import GmbH", street: "Hauptstraße 5", postcode: "10115", city: "Berlin", country: "DE",
        dic: "DE123456789", email: "buchhaltung@example.com", phone: "+49 30 000000", currency: .eur,
        vatMode: .euReverseCharge, dueDays: 21, paymentMethod: "SEPA", language: .en, origin: .imported,
        editedAfterImport: false)

    /// A template of one item for the client `clientID`.
    static func template(for clientID: Int64, name: String = "Měsíční služby") -> InvoiceTemplate {
        InvoiceTemplate(
            name: name, clientID: clientID,
            items: [
                TemplateItem(
                    description: "Služby {měsíc} {rok}", quantity: decimal("7.5"), unit: "hod", unitPriceMinor: 60_000)
            ],
            vatMode: .domestic21, dueDays: 14, duzpAtMonthEnd: true, note: "")
    }
}

/// Stores a rate whose currency no code can be read from, so that reading the currencies the ČNB quotes fails. (A
/// closure made on the main actor cannot be handed to the database, so the statement is run from here.)
func storeUnreadableRate(in database: Database) async throws {
    try await database.write { connection in
        try SchemaRows.cnbRate(connection, declaredOn: "2026-10-16", currency: "usd")
    }
}

/// Deletes the row of the client `id` from `database`, which deletes its templates with it and unlinks its invoices.
/// (A closure made on the main actor cannot be handed to the database, so the statement is run from here.)
func deleteClientRow(_ id: Int64, in database: Database) async throws {
    try await database.write { connection in
        try connection.run("DELETE FROM client WHERE id = ?", [.integer(id)])
    }
}

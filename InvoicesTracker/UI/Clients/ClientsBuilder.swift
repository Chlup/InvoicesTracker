import Foundation

/// What Odběratelé is built from: the clients, the templates of invoices and what each client did in the year shown.
nonisolated struct ClientsInput: Sendable {
    /// The year shown, which names the column of the money received.
    var year: Int

    /// The clients, in any order.
    var clients: [Client]

    /// Every template of an invoice, of whichever client.
    var templates: [InvoiceTemplate]

    /// What each client did in the year (`Database.clientFigures`), by the id of the client. A client without figures
    /// did nothing in the year.
    var figures: [Int64: ClientFigures]
}

/// What Odběratelé shows: the summary row on top of the table, the name of the column of the money received, and the
/// rows. Every text of the table that depends on the data is here; the names of the other columns are the view's.
nonisolated struct ClientsData: Sendable, Hashable {
    /// How many clients the table lists, with the noun in the form Czech asks for the number: "3 odběratelé".
    var countText: String

    /// How many templates of invoices there are, after the count, with its own leading separator:
    /// " · 3 šablony faktur".
    var templatesText: String

    /// "Celkem přijato bez DPH": the money received from the clients in the year, up to the day it is counted to, in
    /// whole Kč, rounded once from the sum of their figures in haléře: "2 138 544 Kč".
    var totalText: String

    /// The name of the column of the money received: "Přijato 2026".
    var receivedHeader: String

    /// The rows, in the order of the names of the clients in Czech.
    var rows: [ClientRow]

    /// What the table says in place of rows, or nil when it has rows.
    var emptyText: String? {
        rows.isEmpty ? ClientsBuilder.noClientsText : nil
    }
}

/// Turns the clients, their templates and their figures in the year into what Odběratelé shows.
nonisolated enum ClientsBuilder {
    /// What the table says when there is no client yet.
    static let noClientsText = "Zatím nemáte žádného odběratele."

    /// The summary row and the rows of `input`. Every template counts in the summary, and each in the row of its own
    /// client. The total is the sum of what the clients paid in the year, in haléře, rounded to whole Kč once, so it
    /// can differ by a crown or two from the sum of the rows, which are rounded each.
    static func build(_ input: ClientsInput) -> ClientsData {
        var templateCounts: [Int64: Int] = [:]
        for template in input.templates {
            templateCounts[template.clientID, default: 0] += 1
        }
        let received = input.clients.reduce(Int64(0)) { sum, client in
            sum + (input.figures[client.id]?.receivedHalere ?? 0)
        }
        return ClientsData(
            countText: counted(input.clients.count, one: "odběratel", few: "odběratelé", many: "odběratelů"),
            templatesText: " · " + counted(input.templates.count, one: "šablona", few: "šablony", many: "šablon")
                + " faktur",
            totalText: PredictionBuilder.kc(ofHalere: received),
            receivedHeader: "Přijato \(input.year)",
            rows: ClientRowBuilder.rows(
                clients: input.clients, templateCounts: templateCounts, figures: input.figures))
    }

    /// `count` with the noun in the form Czech asks for the number, and a no-break space between them, which keeps
    /// them on one line where the summary row wraps: "3 odběratelé", "1 šablona".
    static func counted(_ count: Int, one: String, few: String, many: String) -> String {
        WelcomeTexts.counted(count, one: one, few: few, many: many, separator: "\u{00A0}")
    }
}

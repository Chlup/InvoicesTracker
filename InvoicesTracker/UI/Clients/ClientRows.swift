import Foundation

/// A row of the table of Odběratelé: what it says of one client, as text, on one line. The address, the numbers, the
/// contacts, the terms and the invoices of the client are not in the row; they belong to the detail of the client.
nonisolated struct ClientRow: Identifiable, Hashable, Sendable {
    var id: Int64
    var name: String

    /// "CZK": the code of the currency of the invoices of the client, in the chip of Měna a DPH.
    var currency: String

    /// The VAT mode in a few words: "DPH 21 %", "mimo tuzemsko", "přenesená povinnost" or "bez DPH".
    var vatShort: String

    /// How many templates of invoices the client has: "1 šablona", "2 šablony", "5 šablon", or "žádná".
    var templates: String

    /// The money received from the client in the year, up to the day it is counted to, without VAT, in whole Kč:
    /// "1 105 464 Kč", or "—" where nothing came.
    var received: String

    /// Whether the client has a template, so that `templates` counts them and is not "žádná".
    var hasTemplates: Bool {
        templates != ClientRowBuilder.noTemplates
    }

    /// Whether some money came from the client in the year, so that `received` is an amount and not the dash.
    var hasReceived: Bool {
        received != ClientRowBuilder.nothingReceived
    }
}

/// Turns the clients, how many templates each has and what each did in the year into the rows of Odběratelé.
nonisolated enum ClientRowBuilder {
    /// What `templates` says of a client without a template.
    static let noTemplates = "žádná"

    /// What `received` says of a client that paid nothing in the year.
    static let nothingReceived = "—"

    /// The rows of `clients`, in the order of their names in Czech, with the number of templates of each
    /// (`templateCounts`, by the id of the client) and their figures for the year (`figures`, by the id of the client).
    /// A client with no count has no template, and one without figures has done nothing in the year.
    static func rows(
        clients: [Client], templateCounts: [Int64: Int], figures: [Int64: ClientFigures]
    ) -> [ClientRow] {
        sortedByName(clients).map { client in
            ClientRow(
                id: client.id, name: client.name, currency: client.currency.code,
                vatShort: vatShort(of: client.vatMode),
                templates: templatesText(count: templateCounts[client.id] ?? 0),
                received: receivedText(halere: figures[client.id]?.receivedHalere ?? 0))
        }
    }

    private static let czech = Locale(identifier: "cs_CZ")

    /// `clients` by their names in Czech (where "Č" comes after "C" and "Ch" after "H", which the order of the
    /// database does not know), then by their ids.
    private static func sortedByName(_ clients: [Client]) -> [Client] {
        clients.sorted { first, second in
            switch first.name.compare(second.name, locale: czech) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: first.id < second.id
            }
        }
    }

    /// The VAT mode in the few words of the column Měna a DPH.
    private static func vatShort(of mode: VatMode) -> String {
        switch mode {
        case .domestic21, .domestic12: "DPH \(mode.ratePercent) %"
        case .outsideCountry: "mimo tuzemsko"
        case .euReverseCharge: "přenesená povinnost"
        case .none: "bez DPH"
        }
    }

    /// "1 šablona", "2 šablony", "5 šablon" with a no-break space, as the summary row counts them, or "žádná" for none.
    private static func templatesText(count: Int) -> String {
        guard count > 0 else { return noTemplates }
        return ClientsBuilder.counted(count, one: "šablona", few: "šablony", many: "šablon")
    }

    /// The money received in whole Kč, rounded half up, or the dash where nothing came.
    private static func receivedText(halere: Int64) -> String {
        halere == 0 ? nothingReceived : PredictionBuilder.kc(ofHalere: halere)
    }
}

nonisolated extension ClientRow {
    /// What VoiceOver reads for the row in a table whose last column is named `receivedHeader`, "Přijato 2026": the
    /// name of the client, then each other column with its name. The money received is left out where nothing came,
    /// as a dash in a column says nothing to a listener, and as a column that is empty for an invoice is left out of
    /// the rows of Faktury.
    func spokenText(receivedHeader: String) -> String {
        var parts = [name, "Měna a DPH \(currency)", vatShort, "Šablony \(templates)"]
        if hasReceived {
            parts.append("\(receivedHeader) \(received)")
        }
        return parts.joined(separator: ", ")
    }
}

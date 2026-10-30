import Foundation

/// A row of Odběratelé: what the table says of one client, as text.
nonisolated struct ClientRow: Identifiable, Equatable, Sendable {
    var id: Int64
    var name: String

    /// "Příbram · IČO 12345678": the city, the country unless it is Česko, and the IČO, as far as the client has them.
    /// "—" where it has none of them.
    var detailLine: String

    /// "CZK".
    var currency: String

    /// The VAT mode in a few words: "DPH 21 %", "mimo tuzemsko", "přenesená povinnost" or "bez DPH".
    var vatShort: String

    /// The language of its invoices: "česky" or "anglicky".
    var language: String

    /// What the client paid in the year, up to the day shown: "přijato 106 720,00 Kč", or "nic nepřijato".
    var received: String

    /// How many invoices of the client were issued in the year up to the day shown, and the day of the last of them:
    /// "3 faktury · poslední 15. 10.", or "žádná faktura".
    var countLine: String

    /// Whether `received` says that some money came, not "nic nepřijato".
    var hasReceived: Bool {
        received != ClientRowBuilder.nothingReceived
    }
}

/// Turns the clients and what they did in the year into the rows of Odběratelé.
nonisolated enum ClientRowBuilder {
    /// What `detailLine` says of a client with no city, no country to name and no IČO.
    static let noDetail = "—"

    /// What `received` says of a client that was paid nothing.
    static let nothingReceived = "nic nepřijato"

    /// What `countLine` says of a client that was issued no invoice.
    static let noInvoice = "žádná faktura"

    /// The rows of `clients`, in the order of their names in Czech (where "Č" comes after "C" and "Ch" after "H", which
    /// the order of the database does not know), for the year the `figures` are of. A client without figures has done
    /// nothing in it.
    static func rows(clients: [Client], figures: [Int64: ClientFigures]) -> [ClientRow] {
        let nothing = ClientFigures(invoiceCount: 0, receivedHalere: 0, lastIssueDate: nil)
        return sortedByName(clients).map { row(for: $0, figures: figures[$0.id] ?? nothing) }
    }

    private static let czech = Locale(identifier: "cs_CZ")

    /// `clients` by their names in Czech, then by their ids.
    private static func sortedByName(_ clients: [Client]) -> [Client] {
        clients.sorted { first, second in
            switch first.name.compare(second.name, locale: czech) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: first.id < second.id
            }
        }
    }

    private static func row(for client: Client, figures: ClientFigures) -> ClientRow {
        ClientRow(
            id: client.id, name: client.name, detailLine: detailLine(of: client), currency: client.currency.code,
            vatShort: vatShort(of: client.vatMode), language: client.language == .en ? "anglicky" : "česky",
            received: figures.receivedHalere == 0
                ? nothingReceived : "přijato " + CzechFormat.halere(figures.receivedHalere),
            countLine: countLine(of: figures))
    }

    /// The city, the country by its name in Czech unless it is Česko, and "IČO" with the registration number, as far as
    /// the client has them, apart by a dot.
    private static func detailLine(of client: Client) -> String {
        let country = isCzechia(client.country) ? "" : Countries.name(client.country, language: .cs)
        let ico = FormInput.trimmed(client.ico)
        let parts = [FormInput.trimmed(client.city), country, ico.isEmpty ? "" : "IČO " + ico]
        let said = parts.filter { !$0.isEmpty }
        return said.isEmpty ? noDetail : said.joined(separator: " · ")
    }

    /// Whether `country` is Česko: its code, or a name the import takes for it (Česko, Česká republika).
    private static func isCzechia(_ country: String) -> Bool {
        ImportPlanner.countryCode(of: FormInput.trimmed(country)) == "CZ"
    }

    private static func vatShort(of mode: VatMode) -> String {
        switch mode {
        case .domestic21, .domestic12: "DPH \(mode.ratePercent) %"
        case .outsideCountry: "mimo tuzemsko"
        case .euReverseCharge: "přenesená povinnost"
        case .none: "bez DPH"
        }
    }

    private static func countLine(of figures: ClientFigures) -> String {
        guard figures.invoiceCount > 0 else { return noInvoice }
        let count = WelcomeTexts.invoiceCount(figures.invoiceCount)
        guard let last = figures.lastIssueDate else { return count }
        return count + " · poslední " + CzechFormat.dayMonth(last)
    }
}

nonisolated extension ClientRow {
    /// What VoiceOver reads for the row in the table of `year`: the name of the client, the line under it, and each
    /// other column with its name, the year with what the client did in it. The line under the name is left out where
    /// it is only a dash, and the dots that part the lines are read as pauses.
    func spokenText(year: Int) -> String {
        var parts = [name]
        if detailLine != ClientRowBuilder.noDetail {
            parts.append(Self.paused(detailLine))
        }
        parts.append("Měna a DPH \(currency)")
        parts.append(vatShort)
        parts.append("Jazyk faktury \(language)")
        parts.append("Rok \(year): \(received)")
        parts.append(Self.paused(countLine))
        return parts.joined(separator: ", ")
    }

    private static func paused(_ line: String) -> String {
        line.replacingOccurrences(of: " · ", with: ", ")
    }
}

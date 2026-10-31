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

/// What Odběratelé shows: the summary row on top of the table, the name of the column of the money received, the rows,
/// and the detail of the selected client. Every text of the table and of the detail that depends on the data is here;
/// the names of the other columns and the fixed words of the detail are the views'.
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

    /// The detail of the selected client, or nil while no client is selected, and while the selected client is not
    /// among the clients (a client just saved, until the load that its save starts has it).
    var detail: ClientDetail?

    /// What the table says in place of rows, or nil when it has rows.
    var emptyText: String? {
        rows.isEmpty ? ClientsBuilder.noClientsText : nil
    }
}

/// The detail of a client beside the table of Odběratelé: what the client paid in the year and how many invoices it
/// was issued in it, the facts that new invoices for it start from, and a panel for each of its templates.
nonisolated struct ClientDetail: Sendable, Hashable {
    /// The id of the client.
    var id: Int64

    /// The name of the client, the title of the detail.
    var name: String

    /// "Přijato v roce 2026 bez DPH": the label over the figure.
    var figureLabel: String

    /// The money received from the client in the year, up to the day it is counted to, without VAT, in whole Kč:
    /// "1 105 464 Kč", or "0 Kč" where nothing came.
    var figure: String

    /// Whether some money came from the client in the year, so that `figure` is in the colour of text; "0 Kč" for
    /// nothing is muted.
    var hasReceived: Bool

    /// How many invoices of the client were issued in the year, up to the day the year is counted to, and the day the
    /// last of them was issued: "4 faktury · poslední 30. 9.", or "0 faktur" where there is none.
    var context: String

    /// Adresa, IČO, DIČ, E-mail, Měna, DPH, Splatnost, Platba and Jazyk faktury, in that order, those without a value
    /// left out.
    var facts: [DetailFact]

    /// A panel for each template of the client, in the order the templates were made.
    var templates: [TemplatePanel]

    /// What the detail says under "Šablony faktur" where the client has no template: what a template does.
    var emptyTemplatesText: String
}

/// The panel of a template in the detail of its client: its name and amount, a line for each of its items, and its
/// options.
nonisolated struct TemplatePanel: Sendable, Hashable, Identifiable {
    /// The id of the template.
    var id: Int64

    /// The name of the template, which its panel starts with.
    var name: String

    /// The items added up without VAT, in the currency of the client, as the chooser of a new invoice shows a template:
    /// "12 432,00 USD", or "—" where that is more than an invoice carries.
    var amount: String

    /// A line for every item, its description as the template has it, with the placeholders in it:
    /// "168 h × 74,00 USD · Software development {month} {year}".
    var itemLines: [String]

    /// The due days, then the VAT mode where it is not the client's, then whether the template has a note:
    /// "splatnost 30 dní · Bez DPH · s poznámkou".
    var options: String
}

/// Turns the clients, their templates, their figures in the year and the selection into what Odběratelé shows.
nonisolated enum ClientsBuilder {
    /// What the table says when there is no client yet.
    static let noClientsText = "Zatím nemáte žádného odběratele."

    /// What the detail of a client without templates says under "Šablony faktur".
    static let noTemplatesText =
        "Zatím žádná šablona. Šablona předvyplní položku, cenu, DPH a splatnost, takže opakovanou fakturu vystavíte "
        + "jedním klikem."

    /// The summary row, the rows and the detail of `input`. Every template counts in the summary, and each in the row
    /// of its own client. The total is the sum of what the clients paid in the year, in haléře, rounded to whole Kč
    /// once, so it can differ by a crown or two from the sum of the rows, which are rounded each. The detail is that of
    /// the client `selectedClientID`, where it is among the clients, and there is none while no client is selected.
    static func build(_ input: ClientsInput, selectedClientID: Int64? = nil) -> ClientsData {
        var templateCounts: [Int64: Int] = [:]
        for template in input.templates {
            templateCounts[template.clientID, default: 0] += 1
        }
        let received = input.clients.reduce(Int64(0)) { sum, client in
            sum + (input.figures[client.id]?.receivedHalere ?? 0)
        }
        let selected = selectedClientID.flatMap { id in input.clients.first { $0.id == id } }
        return ClientsData(
            countText: CzechCount.counted(
                input.clients.count, one: "odběratel", few: "odběratelé", many: "odběratelů", separator: noBreakSpace),
            templatesText: " · "
                + CzechCount.counted(
                    input.templates.count, one: "šablona", few: "šablony", many: "šablon", separator: noBreakSpace)
                + " faktur",
            totalText: PredictionBuilder.kc(ofHalere: received),
            receivedHeader: "Přijato \(input.year)",
            rows: ClientRowBuilder.rows(
                clients: input.clients, templateCounts: templateCounts, figures: input.figures),
            detail: selected.map { client in
                detail(
                    of: client, year: input.year, figures: input.figures[client.id],
                    templates: input.templates.filter { $0.clientID == client.id })
            })
    }

    /// The space between a count and its noun in the texts of Odběratelé, which keeps them on one line where the
    /// summary row wraps: "3 odběratelé", "1 šablona".
    static let noBreakSpace = "\u{00A0}"

    // MARK: The detail

    /// The detail of `client` in `year`: what it did in the year (`figures`, nothing where there are none) and a panel
    /// for each of `templates`, its own, in their order.
    private static func detail(
        of client: Client, year: Int, figures: ClientFigures?, templates: [InvoiceTemplate]
    ) -> ClientDetail {
        let figures = figures ?? ClientFigures(invoiceCount: 0, receivedHalere: 0, lastIssueDate: nil)
        return ClientDetail(
            id: client.id, name: client.name, figureLabel: "Přijato v roce \(year) bez DPH",
            figure: PredictionBuilder.kc(ofHalere: figures.receivedHalere), hasReceived: figures.receivedHalere != 0,
            context: context(of: figures), facts: facts(of: client),
            templates: templates.map { panel(of: $0, for: client) }, emptyTemplatesText: noTemplatesText)
    }

    /// "4 faktury · poslední 30. 9.": the invoices issued in the year, counted in Czech with a no-break space, and the
    /// day the last of them was issued; "0 faktur" where there is none, as the last day is only said of the year.
    private static func context(of figures: ClientFigures) -> String {
        let count = CzechCount.counted(
            figures.invoiceCount, one: "faktura", few: "faktury", many: "faktur", separator: noBreakSpace)
        guard figures.invoiceCount > 0, let last = figures.lastIssueDate else { return count }
        return count + " · poslední " + CzechFormat.dayMonth(last)
    }

    /// The facts of `client` in the order of the design, without the white space around them, and those that are
    /// empty left out: the address, the IČO, the DIČ, the e-mail, the currency by its code, the VAT mode in full, the
    /// due days counted in Czech, the way of payment as the client has it, and the language of its invoices.
    private static func facts(of client: Client) -> [DetailFact] {
        [
            DetailFact(label: "Adresa", value: address(of: client)),
            DetailFact(label: "IČO", value: FormInput.trimmed(client.ico)),
            DetailFact(label: "DIČ", value: FormInput.trimmed(client.dic)),
            DetailFact(label: "E-mail", value: FormInput.trimmed(client.email)),
            DetailFact(label: "Měna", value: client.currency.code),
            DetailFact(label: "DPH", value: client.vatMode.label),
            DetailFact(label: "Splatnost", value: CzechCount.days(client.dueDays, separator: "\u{00A0}")),
            DetailFact(label: "Platba", value: FormInput.trimmed(client.paymentMethod)),
            DetailFact(label: "Jazyk faktury", value: client.language == .en ? "anglicky" : "česky"),
        ]
        .filter { !$0.value.isEmpty }
    }

    /// "Na Výsluní 112, 256 01 Benešov, Česko": the street, the postcode with the city, and the country by its name in
    /// Czech (Česko too), or as it was typed where that is no code, as far as the client has them, apart by commas.
    private static func address(of client: Client) -> String {
        let place = [client.postcode, client.city].map(FormInput.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        let parts = [FormInput.trimmed(client.street), place, Countries.name(client.country, language: .cs)]
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The panel of `template` in the detail of `client`: its amount and the prices of its items in the currency of the
    /// client, and in its options the VAT mode only where it is not the client's.
    private static func panel(of template: InvoiceTemplate, for client: Client) -> TemplatePanel {
        let itemLines = template.items.map { item in
            ItemLine.text(
                quantity: item.quantity, unit: item.unit, unitPriceMinor: item.unitPriceMinor,
                currency: client.currency, description: item.description)
        }
        var options = ["splatnost " + CzechCount.days(template.dueDays, separator: "\u{00A0}")]
        if template.vatMode != client.vatMode {
            options.append(template.vatMode.label)
        }
        if !FormInput.trimmed(template.note).isEmpty {
            options.append("s poznámkou")
        }
        return TemplatePanel(
            id: template.id, name: template.name,
            amount: NewInvoiceChooserModel.netAmount(of: template, in: client.currency), itemLines: itemLines,
            options: options.joined(separator: " · "))
    }
}

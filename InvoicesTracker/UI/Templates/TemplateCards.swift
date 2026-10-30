import Foundation

/// A card of Šablony faktur: what the screen says of one template, as text.
nonisolated struct TemplateCard: Identifiable, Equatable, Sendable {
    var id: Int64
    var name: String

    /// The name of the client of the template.
    var client: String

    /// A line for every item: "172 h × 70,00 USD · Software development {month} {year}", the description as the
    /// template has it, with the placeholders in it.
    var itemLines: [String]

    /// "splatnost 30 dní · Tuzemsko 21 % · s poznámkou".
    var options: String
}

/// Turns the templates into the cards of Šablony faktur.
nonisolated enum TemplateCardBuilder {
    /// What a template of a client that is not there is written for.
    static let unknownClient = "Neznámý odběratel"

    /// The cards of `templates`, in their order, each written for its client among `clients`: the prices are in the
    /// currency of the client.
    static func cards(templates: [InvoiceTemplate], clients: [Client]) -> [TemplateCard] {
        templates.map { template in
            let client = clients.first { $0.id == template.clientID }
            let currency = client?.currency ?? .czk
            return TemplateCard(
                id: template.id, name: template.name, client: client?.name ?? unknownClient,
                itemLines: template.items.map { line(for: $0, currency: currency) }, options: options(of: template))
        }
    }

    /// "7,5 hod × 600,00 Kč · Služby {měsíc} {rok}": the quantity with its unit, the price of one unit and the text.
    private static func line(for item: TemplateItem, currency: CurrencyCode) -> String {
        ItemLine.text(
            quantity: item.quantity, unit: item.unit, unitPriceMinor: item.unitPriceMinor, currency: currency,
            description: item.description)
    }

    private static func options(of template: InvoiceTemplate) -> String {
        [
            "splatnost " + CzechCount.days(template.dueDays), template.vatMode.label,
        ].joined(separator: " · ") + (FormInput.trimmed(template.note).isEmpty ? "" : " · s poznámkou")
    }
}

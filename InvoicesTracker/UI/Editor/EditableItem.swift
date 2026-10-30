import Foundation

/// A line of the invoice as it is typed in the editor. The quantity and the price are texts, because what is typed need
/// not be a number yet (or ever); `quantity` and `unitPriceMinor` read them with `AmountParser`, as every form of the
/// app does, and say nil for a text that is not a number.
nonisolated struct EditableItem: Sendable, Identifiable {
    /// Tells the rows apart while they are added and removed. It is no part of what is saved.
    let id = UUID()
    var description: String
    var quantityText: String
    var unit: String
    var unitPriceText: String

    /// The text of the template this description was filled in from, and what it was filled in as. The description
    /// follows the DUZP (`{month}`, `{year}`…) for as long as it is still what was filled in, and not once it is typed
    /// over.
    var templateText: String?
    var filledText: String?

    /// Quantities have at most this many digits after the decimal separator.
    static let quantityFractionDigits = 6

    static let quantityMessage = "Zadejte počet, například 6,5."
    static let priceMessage = "Zadejte částku ve tvaru 13 340 nebo 13 340,50."

    // MARK: Reading the texts

    /// The quantity, or nil when the text is not a number (and when it is empty).
    var quantity: Decimal? {
        AmountParser.decimal(quantityText, maxFractionDigits: Self.quantityFractionDigits)
    }

    /// The price of one unit in minor units, or nil when the text is not an amount (and when it is empty).
    var unitPriceMinor: Int64? {
        AmountParser.minor(unitPriceText)
    }

    var quantityIsBlank: Bool {
        Self.isBlank(quantityText)
    }

    var priceIsBlank: Bool {
        Self.isBlank(unitPriceText)
    }

    /// What to say under the quantity: only for a text that is there and is not a number.
    var quantityError: String? {
        quantityIsBlank || quantity != nil ? nil : Self.quantityMessage
    }

    /// What to say under the price: only for a text that is there and is not an amount.
    var priceError: String? {
        priceIsBlank || unitPriceMinor != nil ? nil : Self.priceMessage
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Template text

    /// Whether the description is what the template made of it for some DUZP, so that a new DUZP fills it in again.
    var isFilledFromTemplate: Bool {
        templateText != nil && description == filledText
    }

    /// Fills the description in from its template for `duzp`. Does nothing for a row that has no template.
    mutating func fillFromTemplate(for duzp: CivilDate) {
        guard let templateText else { return }
        let filled = TemplateText.fill(templateText, duzp: duzp)
        description = filled
        filledText = filled
    }
}

nonisolated extension EditableItem {
    /// The row a person starts a blank invoice with: one hour, with no description and no price yet.
    static func blank(unit: String = "h") -> EditableItem {
        EditableItem(description: "", quantityText: "1", unit: unit, unitPriceText: "")
    }

    /// The row of an item that is stored: its numbers written the way they are typed in Czech.
    init(item: InvoiceItem) {
        self.init(
            description: item.description, quantityText: Self.text(of: item.quantity), unit: item.unit,
            unitPriceText: CzechFormat.amount(item.unitPriceMinor))
    }

    /// The row of an item of a template, with its description filled in for `duzp`.
    init(templateItem item: TemplateItem, duzp: CivilDate) {
        let filled = TemplateText.fill(item.description, duzp: duzp)
        self.init(
            description: filled, quantityText: Self.text(of: item.quantity), unit: item.unit,
            unitPriceText: CzechFormat.amount(item.unitPriceMinor), templateText: item.description,
            filledText: filled)
    }

    /// The row of an item of a template that is edited: its description as the template has it, with the placeholders
    /// in it (`{month}`, `{year}`…), and its numbers written the way they are typed in Czech.
    init(editingTemplateItem item: TemplateItem) {
        self.init(
            description: item.description, quantityText: Self.text(of: item.quantity), unit: item.unit,
            unitPriceText: CzechFormat.amount(item.unitPriceMinor))
    }

    /// A quantity as it is typed in Czech: `176`, `6,5`.
    private static func text(of quantity: Decimal) -> String {
        DecimalMath.canonical(quantity).replacing(".", with: ",")
    }
}

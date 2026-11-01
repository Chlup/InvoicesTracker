import Foundation

/// The line that says an item of an invoice or of a template: "205 h × 70,00 USD · Software development". The detail of
/// an invoice, the panel of a template in the detail of its client and the chooser of a new invoice write it alike.
nonisolated enum ItemLine {
    /// The quantity with a decimal comma and its unit after a no-break space, "×" and the price of one unit in
    /// `currency`, and after a dot the description without the white space around it, when there is any.
    static func text(
        quantity: Decimal, unit: String, unitPriceMinor: Int64, currency: CurrencyCode, description: String = ""
    ) -> String {
        var line = DecimalMath.canonical(quantity).replacing(".", with: ",")
        if !unit.isEmpty {
            line += "\u{00A0}" + unit
        }
        line += " × " + CzechFormat.money(Money(minor: unitPriceMinor, currency: currency))
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            line += " · " + text
        }
        return line
    }
}

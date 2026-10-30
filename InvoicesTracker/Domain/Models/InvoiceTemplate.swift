import Foundation

/// A line of a template. The description may hold the placeholders `{měsíc}`, `{rok}`, `{month}` and `{year}`.
nonisolated struct TemplateItem: Sendable, Hashable, Codable {
    var description: String
    var quantity: Decimal
    var unit: String

    /// The price of one unit in minor units of the invoice currency.
    var unitPriceMinor: Int64
}

/// A recurring invoice to start from: the items and terms of an invoice for one client.
nonisolated struct InvoiceTemplate: Identifiable, Sendable, Hashable, Codable {
    /// 0 until the template is saved.
    var id: Int64 = 0
    var name: String
    var clientID: Int64
    var items: [TemplateItem]
    var vatMode: VatMode
    var dueDays: Int

    /// The old setting of whether the DUZP (the date of the taxable supply) is the last day of the month. It is only
    /// kept as stored, so that older data stays intact: a new invoice always starts on the last day of the real
    /// current month, whatever a template says.
    var duzpAtMonthEnd = true
    var note = ""
}

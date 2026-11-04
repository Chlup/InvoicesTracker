import Foundation

/// Which net income the budget divides.
nonisolated enum BudgetSource: String, Codable, Sendable {
    /// The income received so far.
    case actual
    /// The predicted income of the year.
    case prediction
    /// The net income of one invoice, chosen by `BudgetSettings.invoiceID`.
    case invoice
}

/// The choices the person made on the budget screen. They are kept in `AppSettings`.
nonisolated struct BudgetSettings: Hashable, Sendable, Codable {
    /// How the net income is divided among the four categories.
    var split = BudgetSplit.empty

    /// Which net income is divided.
    var source = BudgetSource.actual

    /// The invoice whose net income is divided while `source` is `invoice`.
    var invoiceID: Int64?
}

nonisolated extension BudgetSettings {
    /// Reads the choices written by this or another version of the app one field at a time. A field that is missing,
    /// or that this version cannot read, takes its default alone: a source this version does not know, such as one a
    /// newer version saved, reads as Skutečnost and leaves the split as it was saved, and a split that cannot be read
    /// reads as the empty one and leaves the source and the invoice.
    init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        split = (try? values.decodeIfPresent(BudgetSplit.self, forKey: .split)) ?? split
        source = (try? values.decodeIfPresent(BudgetSource.self, forKey: .source)) ?? source
        invoiceID = (try? values.decodeIfPresent(Int64.self, forKey: .invoiceID)) ?? invoiceID
    }
}

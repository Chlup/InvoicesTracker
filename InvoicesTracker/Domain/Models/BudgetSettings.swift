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

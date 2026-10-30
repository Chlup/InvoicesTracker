import Foundation

/// The check behind the button that deletes an invoice: it unlocks only when the person has typed the number of the
/// invoice.
nonisolated enum DeleteConfirmation {
    /// Whether `typed`, without the spaces around it, is `number` or the digits of it (`20260501` for `2026-05-01`).
    /// An empty text never matches, not even for a number that has no digits.
    static func matches(typed: String, number: String) -> Bool {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return text == number || text == InvoiceNumbering.digits(of: number)
    }
}

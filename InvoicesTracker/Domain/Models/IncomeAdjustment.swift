import Foundation

/// Income that is not the payment of an invoice: a credit note, a refund, or money received outside the normal
/// flow. It counts as a receipt without VAT.
nonisolated struct IncomeAdjustment: Identifiable, Sendable, Hashable, Codable {
    /// 0 until the adjustment is saved.
    var id: Int64 = 0

    /// The day the money was received. It decides the year the adjustment belongs to.
    var date: CivilDate

    /// The amount in haléře. A refund or a credit note is negative.
    var amountHalere: Int64
    var description: String
}

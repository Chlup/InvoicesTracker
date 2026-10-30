import Foundation

/// A rate for converting a foreign currency to crowns, as the ČNB quotes it: `rate` crowns per `amount` units of
/// `currency`. The amount is 1 for most currencies and 100 or 1000 for those with a small unit value.
nonisolated struct ExchangeRate: Hashable, Sendable, Codable {
    var currency: CurrencyCode
    var amount: Int
    var rate: Decimal

    /// The value in haléře of `minor` hundredths of the currency: minor × rate ÷ amount, rounded half up in a
    /// single step. The hundredths of the foreign unit and the haléře of a koruna cancel out, so no factor of 100
    /// appears.
    func czkHalere(fromMinor minor: Int64) -> Int64 {
        precondition(amount > 0, "The quoted amount of an exchange rate must be positive.")
        return DecimalMath.halfUp(Decimal(minor) * rate / Decimal(amount))
    }
}

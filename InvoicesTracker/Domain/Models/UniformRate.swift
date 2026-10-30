import Foundation

/// Where a uniform rate came from.
nonisolated enum UniformRateOrigin: String, Sendable, Hashable, Codable {
    /// Shipped with the app: the published table of a past year.
    case builtIn

    /// Read from the GFŘ publication and confirmed by the person.
    case fetched

    /// Typed in by the person.
    case manual
}

/// The uniform annual rate (jednotný kurz) of the GFŘ for one currency in one year: `rate` crowns for `amount`
/// units of `currency`.
nonisolated struct UniformRate: Sendable, Hashable, Codable {
    var year: Int
    var currency: CurrencyCode

    /// The number of units the rate is for: 1, 100 or 1000.
    var amount: Int
    var rate: Decimal

    /// The number of the GFŘ instruction that published the rate, such as `GFŘ-D-75`.
    var instruction: String

    /// The publication the rate was read from, for a fetched rate.
    var sourceURL: String?

    /// When the person confirmed a fetched rate.
    var confirmedAt: Date?
    var origin: UniformRateOrigin

    /// The same rate as an `ExchangeRate`, to convert amounts with.
    var exchangeRate: ExchangeRate {
        ExchangeRate(currency: currency, amount: amount, rate: rate)
    }

    /// The currencies whose uniform rate Nastavení › Rok takes by hand, dollars first. The rate of any other currency
    /// comes with the app or from the GFŘ publication and cannot be typed, as the texts that name a missing rate say.
    nonisolated static let currenciesEnteredByHand: [CurrencyCode] = [.usd, .eur]
}

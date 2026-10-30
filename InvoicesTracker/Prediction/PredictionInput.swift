import Foundation

/// Everything the prediction of a year's income is made from: the clients with their invoices and templates, the
/// person's choices of months, the money received and the rates that convert expected amounts in other currencies.
nonisolated struct PredictionInput: Sendable, Hashable {
    /// The year predicted.
    var year: Int

    /// The app's today. The current year is predicted as of it, any other year as of its 31 December: that day is
    /// "now" (`now(year:today:)`).
    var today: CivilDate

    var clients: [Client]

    /// The issued invoices of every year with their payments, and the drafts. A draft counts only in the current year.
    /// An invoice in review counts nowhere: it is not income until it is resolved.
    var invoices: [Invoice]

    var templates: [InvoiceTemplate]

    /// The person's choices of months where they differ from the app's own: client id → month (1 to 12) → whether an
    /// invoice is expected.
    var changes: [Int64: [Int: Bool]]

    /// The year's payments and income adjustments, of every day of the year, also those after today.
    var receipts: [Receipt]

    /// The rate of each foreign currency: the year's uniform rate when the year converts with its uniform rates and has
    /// one for the currency, otherwise the latest ČNB rate of the currency. An amount in a currency without a rate is
    /// unknown, unless it is that of an unpaid invoice that keeps a rate of its own.
    var rates: [CurrencyCode: ExchangeRate]

    /// Whether the year converts its income with its uniform rates, which `rates` then hold for the currencies the year
    /// has one for.
    var usesUniformRate: Bool

    /// The day the page names for the rates; nil with the uniform rates. Otherwise the day the ČNB declared the newest
    /// of the ČNB rates in `rates`, or, when `rates` holds none, "now" (the business day before it on a weekend or a
    /// holiday).
    var rateDay: CivilDate?

    /// Daily conversions keyed by each qualifying invoice’s original payment or issue day.
    var averageRates: [PredictionRateKey: StoredRate] = [:]
}

nonisolated extension PredictionInput {
    /// The day a prediction of `year` is made as of, "now": `today` in the year of today, otherwise 31 December of
    /// `year`.
    static func now(year: Int, today: CivilDate) -> CivilDate {
        year == today.year ? today : lastDay(of: year)
    }

    /// Whether the prediction of `year` as of `today` is closed, so that nothing is expected any more: the year is
    /// over, or `today` is its 31 December. "Now" is then the year's last day, as it is for a year after the year of
    /// today, which the app does not show.
    static func isClosed(year: Int, today: CivilDate) -> Bool {
        now(year: year, today: today) == lastDay(of: year)
    }

    /// 31 December of `year`. Traps outside the years 1 to 9999.
    static func lastDay(of year: Int) -> CivilDate {
        guard let day = CivilDate(year: year, month: 12, day: 31) else {
            preconditionFailure("31 December \(year) is not a date in the years 1 to 9999.")
        }
        return day
    }

    /// `minor` hundredths of `currency` in haléře: the same amount for crowns, otherwise converted at the rate of the
    /// currency and rounded once. Without a rate the amount is unknown, 0.
    func czkHalere(fromMinor minor: Int64, in currency: CurrencyCode) -> Int64 {
        if currency.isCZK {
            return minor
        }
        guard let rate = rates[currency] else { return 0 }
        return rate.czkHalere(fromMinor: minor)
    }
}

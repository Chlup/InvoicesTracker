import Foundation

/// The preliminary uniform rate (jednotný kurz) of a year, computed from the ČNB rates of the last day of each month
/// that has ended (§ 38 odst. 7 zákona o daních z příjmů). The rate is the mean of those month-end rates, so it is
/// preliminary until the GFŘ publishes the official one. This only computes: the rates it uses come from the caller.
nonisolated enum PreliminaryUniformRates {
    /// The currencies the app computes a rate for, as many as it takes by hand (`UniformRate.currenciesEnteredByHand`).
    static let currencies: [CurrencyCode] = UniformRate.currenciesEnteredByHand

    /// One month of the year, with the ČNB rates that are valid on its last day.
    nonisolated struct MonthEnd: Sendable, Equatable {
        /// The month, 1 to 12.
        let month: Int

        /// The last day of the month.
        let lastDay: CivilDate

        /// Whether the month has ended: its last day is before today.
        let hasEnded: Bool

        /// The answer of the rate lookup for each currency. Empty unless the month has ended.
        let rates: [CurrencyCode: RateLookupResult]
    }

    /// What the month-end rates give.
    nonisolated enum Outcome: Sendable, Equatable {
        /// No month of the year has ended yet, so there is nothing to average.
        case none

        /// A month-end rate is not available yet: it is not declared or not loaded. The caller loads more rates.
        case incomplete

        /// The computed rates, dollars before euros. A currency the ČNB did not quote on a month-end is left out.
        case rates([UniformRate])
    }

    /// The months of a year and what they give.
    nonisolated struct Computation: Sendable, Equatable {
        let year: Int

        /// All twelve months, in order.
        let months: [MonthEnd]
        let outcome: Outcome

        /// The number of months that have ended.
        var endedMonths: Int {
            months.filter(\.hasEnded).count
        }
    }

    /// Computes the preliminary uniform rates of `year` as of `today`.
    /// - Parameters:
    ///   - year: The year the rates are for.
    ///   - today: The current day. A month counts once its last day is before it.
    ///   - lookup: The rule that finds the ČNB rate valid on a day, such as `RateTable.lookup` or
    ///     `Database.cnbRate`. It is asked for each currency on the last day of each month that has ended.
    static func compute(
        year: Int,
        today: CivilDate,
        lookup: (CurrencyCode, CivilDate) throws -> RateLookupResult
    ) rethrows -> Computation {
        var months: [MonthEnd] = []
        for month in 1...12 {
            let lastDay = lastDay(year: year, month: month)
            let hasEnded = lastDay < today
            var rates: [CurrencyCode: RateLookupResult] = [:]
            if hasEnded {
                for currency in currencies {
                    rates[currency] = try lookup(currency, lastDay)
                }
            }
            months.append(MonthEnd(month: month, lastDay: lastDay, hasEnded: hasEnded, rates: rates))
        }
        return Computation(year: year, months: months, outcome: outcome(year: year, months: months))
    }

    /// The outcome for `months`, which are the twelve months of `year`.
    private static func outcome(year: Int, months: [MonthEnd]) -> Outcome {
        let ended = months.filter(\.hasEnded)
        guard !ended.isEmpty else { return .none }
        let answers = ended.flatMap { $0.rates.values }
        guard !answers.contains(.notYetAvailable) else { return .incomplete }
        var computed: [UniformRate] = []
        for currency in currencies {
            let perUnitRates: [Decimal] = ended.compactMap { month in
                guard case .declared(let rate, _)? = month.rates[currency] else { return nil }
                return rate.rate / Decimal(rate.amount)
            }
            guard perUnitRates.count == ended.count else { continue }
            var mean = perUnitRates.reduce(0, +) / Decimal(perUnitRates.count)
            var rounded = Decimal()
            NSDecimalRound(&rounded, &mean, 2, .plain)
            computed.append(
                UniformRate(
                    year: year,
                    currency: currency,
                    amount: 1,
                    rate: rounded,
                    instruction: "",
                    sourceURL: nil,
                    confirmedAt: nil,
                    origin: .computed,
                    computedMonths: ended.count
                )
            )
        }
        return .rates(computed)
    }

    /// The last day of `month` of `year`: the day before the first day of the next month.
    private static func lastDay(year: Int, month: Int) -> CivilDate {
        let firstOfNext = month == 12
            ? CivilDate(year: year + 1, month: 1, day: 1)
            : CivilDate(year: year, month: month + 1, day: 1)
        guard let firstOfNext else { preconditionFailure("The year \(year) is outside the supported dates.") }
        return firstOfNext.adding(days: -1)
    }
}

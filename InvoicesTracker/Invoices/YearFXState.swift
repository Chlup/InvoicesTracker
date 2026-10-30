import Foundation

/// Whether a year has the uniform rate its income in other currencies needs, and why not.
nonisolated enum UniformAvailability: Sendable, Equatable {
    /// The year has the uniform rate of every currency it was paid in (of some currency, when it was paid in none):
    /// the rates of 1 USD and 1 EUR in crowns, nil for one it has none of, the GFŘ instruction they were published
    /// by, nil when they have none (entered by hand without one), and where they are from: entered by hand when any of
    /// them was, which every screen says (`BuilderText.uniformSource(instruction:origin:)`).
    case ready(usd: Decimal?, eur: Decimal?, instruction: String?, origin: UniformRateOrigin)

    /// The year has uniform rates, but not that of this currency, in which it was paid: the first such one by code.
    case missingCurrency(CurrencyCode)

    /// The year has no uniform rate, and the app has not started looking for it (`UniformRateSearch.notStarted`): the
    /// GFŘ publishes it in January of the next year. So the current year, and the year just over until 1 January.
    case notPublishedYet(year: Int)

    /// The year has no uniform rate, and the app looks for it once a day (`UniformRateSearch.looking`): from 2 January
    /// to 31 March of the next year.
    case searchedFor(year: Int)

    /// The year has no uniform rate, and the app no longer looks for it (`UniformRateSearch.over`), from 1 April of
    /// the next year: the app does not have it, and it is entered in Nastavení › Rok.
    case notInApp(year: Int)

    /// Whether the year has what it needs to convert at the uniform rate, so that the rate can be chosen for it.
    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

/// Where the search of the app for the uniform rate of a year stands on a day. The GFŘ publishes the rate of a year in
/// January of the next one, and the app looks for it in the Finanční zpravodaj once a day from 2 January to 31 March of
/// that year (`RefreshPlanner`). What the app says of a year without its rate follows this, so that it never promises a
/// January that has passed, and never says it looks for a rate it does not look for.
nonisolated enum UniformRateSearch: Sendable, Equatable {
    /// Before 2 January of the next year: the year is current, or it ended the day before.
    case notStarted

    /// From 2 January to 31 March of the next year, the days the app looks for the rate.
    case looking

    /// From 1 April of the next year: the app no longer looks for the rate, which has to be entered by hand.
    case over

    /// The stage of the search for the rate of `year` on `today`.
    init(year: Int, today: CivilDate) {
        guard let first = Self.firstDay(of: year), let last = Self.lastDay(of: year) else {
            // A year at the end of the calendar has no next one, so its search never starts.
            self = .notStarted
            return
        }
        if today < first {
            self = .notStarted
        } else if today <= last {
            self = .looking
        } else {
            self = .over
        }
    }

    /// 2 January of the year after `year`, the first day the app looks for the rate of `year`.
    static func firstDay(of year: Int) -> CivilDate? {
        CivilDate(year: year + 1, month: 1, day: 2)
    }

    /// 31 March of the year after `year`, the last day the app looks for the rate of `year`: a search on it, or after
    /// it, that does not find the rate ends the search with a reminder to enter the rate by hand.
    static func lastDay(of year: Int) -> CivilDate? {
        CivilDate(year: year + 1, month: 3, day: 31)
    }
}

/// How a year converts its income in other currencies: the method chosen for it, the method it uses, and whether it has
/// the uniform rate. `effective` is the uniform rate only when that is chosen and the year has it (`uniform` is
/// `.ready`); otherwise the year is converted at the ČNB rates of the days, and the choice is kept for when it has it.
nonisolated struct YearFXState: Sendable, Equatable {
    let year: Int
    let chosen: IncomeFXMethod
    let effective: IncomeFXMethod
    let uniform: UniformAvailability

    /// Whether money in another currency than crowns came in the year, other than amounts the bank credited in crowns:
    /// without it the choice changes nothing.
    let hasForeignPayments: Bool
}

nonisolated extension YearFXState {
    /// The state of `year`, chosen to convert by `chosen`, with the uniform rates `rates` stored for it, paid in
    /// `paidCurrencies` (the currencies of its payments that are converted at a rate), on the day `today`. Crowns need
    /// no rate, and a rate of another year or of nothing is no rate of the year.
    init(
        year: Int, chosen: IncomeFXMethod, rates: [UniformRate], paidCurrencies: [CurrencyCode], today: CivilDate
    ) {
        let uniform = UniformAvailability(year: year, rates: rates, paidCurrencies: paidCurrencies, today: today)
        self.init(
            year: year, chosen: chosen, effective: chosen == .uniform && uniform.isReady ? .uniform : .cnbDaily,
            uniform: uniform, hasForeignPayments: paidCurrencies.contains { !$0.isCZK })
    }
}

nonisolated extension UniformAvailability {
    /// Whether `year` has the uniform rate its income needs, with the uniform rates `rates` stored for it and paid in
    /// `paidCurrencies`, on the day `today`:
    /// - ready when it has the rate of every currency it was paid in, or any rate when it was paid in none;
    /// - otherwise the first currency without a rate, by code, when it has rates of other currencies;
    /// - otherwise, with no rate at all, where the search of the app for it stands on `today` (`UniformRateSearch`):
    ///   not published yet before it starts, searched for while it runs, and not in the app once it is over.
    init(year: Int, rates: [UniformRate], paidCurrencies: [CurrencyCode], today: CivilDate) {
        let known = rates.filter { $0.year == year && $0.rate > 0 && $0.amount > 0 }
        let rated = Set(known.map(\.currency))
        if known.isEmpty {
            switch UniformRateSearch(year: year, today: today) {
            case .notStarted:
                self = .notPublishedYet(year: year)
            case .looking:
                self = .searchedFor(year: year)
            case .over:
                self = .notInApp(year: year)
            }
        } else if let missing = paidCurrencies.filter({ !$0.isCZK && !rated.contains($0) }).sorted().first {
            self = .missingCurrency(missing)
        } else {
            self = Self.ready(of: known)
        }
    }

    /// `.ready` with the rates of 1 USD and 1 EUR of `rates`, and the instruction of those two, or of all of `rates`
    /// when it has neither: the first that has one. They were entered by hand when any of them was; otherwise they
    /// are from where the first of them is from.
    private static func ready(of rates: [UniformRate]) -> UniformAvailability {
        func perUnit(_ currency: CurrencyCode) -> Decimal? {
            rates.first { $0.currency == currency }.map { $0.rate / Decimal($0.amount) }
        }
        let dollarsAndEuros = rates.filter { $0.currency == .usd || $0.currency == .eur }
        let named = (dollarsAndEuros.isEmpty ? rates : dollarsAndEuros).sorted { $0.currency < $1.currency }
        let instruction = named.lazy.map { $0.instruction.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let origin: UniformRateOrigin =
            named.contains { $0.origin == .manual } ? .manual : named.first?.origin ?? .builtIn
        return .ready(usd: perUnit(.usd), eur: perUnit(.eur), instruction: instruction, origin: origin)
    }
}

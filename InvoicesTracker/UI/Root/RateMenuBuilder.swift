import Foundation

/// What the rate capsule of the toolbar shows: how the year shown converts its income in other currencies.
nonisolated struct RateCapsuleContent: Equatable, Sendable {
    /// "Denní kurz" or "Jednotný kurz".
    var title: String

    /// What VoiceOver reads it as: "Přepočet cizích měn v roce 2025: jednotný kurz".
    var accessibilityLabel: String

    /// Whether it is tinted blue: while the year uses its uniform rate.
    var isTinted: Bool
}

/// One choice of the menu of the rate capsule.
nonisolated struct RateMenuItem: Equatable, Sendable {
    /// The method the item chooses for the year.
    var method: IncomeFXMethod

    /// "Denní kurz ČNB", "Jednotný kurz 2025".
    var title: String

    /// The line under the title: what the method converts with, or why it cannot be chosen.
    var detail: String

    /// The levies of the year with the method and how they differ from those with the other one, such as "odvody
    /// 548 037 Kč · o 3 063 Kč méně", when both methods can be chosen and the year has payments in other currencies;
    /// nil otherwise.
    var comparison: String?

    /// Whether the year converts by the method now (`YearFXState.effective`): the item has a check mark.
    var isChecked: Bool

    /// Whether the method can be chosen: the daily ČNB rates always, the uniform rate when the year has it.
    var isEnabled: Bool
}

/// The menu of the rate capsule: a heading, the two methods and a note under them.
nonisolated struct RateMenuContent: Equatable, Sendable {
    /// "Cizí měny v roce 2025".
    var heading: String

    /// The daily ČNB rates, then the uniform rate of the year.
    var items: [RateMenuItem]

    /// What the choice does, or why it changes nothing or cannot be made yet.
    var footer: String
}

/// The texts of the rate capsule of the toolbar and of its menu, in Czech, for a year in a state `YearFXState` tells.
///
/// The capsule names the method the year converts its income in other currencies with now. The menu offers the daily
/// ČNB rates, which can always be chosen (also for a year set to the uniform rate that lacks it: choosing them drops
/// that choice), and the uniform rate of the year with its rates and instruction, or disabled with the reason it
/// cannot be chosen. The method the year uses is checked.
nonisolated enum RateMenuBuilder {
    /// The capsule of `year`, which converts by `effective`.
    static func capsule(year: Int, effective: IncomeFXMethod) -> RateCapsuleContent {
        let uniform = effective == .uniform
        return RateCapsuleContent(
            title: uniform ? "Jednotný kurz" : "Denní kurz",
            accessibilityLabel: "Přepočet cizích měn v roce \(year): " + (uniform ? "jednotný kurz" : "denní kurz ČNB"),
            isTinted: uniform)
    }

    /// "Cizí měny v roce 2025": the heading of the menu of `year`.
    static func heading(year: Int) -> String {
        "Cizí měny v roce \(year)"
    }

    /// The menu of the year in `state`. `comparison` is the levies of the year with each method
    /// (`AppModel.levyComparison(year:)`), shown on the items where both methods can be chosen and the year has
    /// payments in other currencies: a comparison read before the year lost its uniform rate is left out.
    static func content(state: YearFXState, comparison: (daily: Int64, uniform: Int64)?) -> RateMenuContent {
        let year = state.year
        let compared = state.uniform.isReady && state.hasForeignPayments ? comparison : nil
        let daily = RateMenuItem(
            method: .cnbDaily, title: "Denní kurz ČNB", detail: "kurz ke dni přijetí každé platby",
            comparison: compared.map { levies(of: $0.daily, against: $0.uniform) },
            isChecked: state.effective == .cnbDaily, isEnabled: true)
        let uniform = RateMenuItem(
            method: .uniform, title: "Jednotný kurz \(year)", detail: uniformDetail(of: state.uniform, year: year),
            comparison: compared.map { levies(of: $0.uniform, against: $0.daily) },
            isChecked: state.effective == .uniform, isEnabled: state.uniform.isReady)
        return RateMenuContent(heading: heading(year: year), items: [daily, uniform], footer: footer(of: state))
    }

    // MARK: Helpers

    /// The line under the uniform rate: its rates of 1 USD and 1 EUR with where they are from, or why the year cannot
    /// use it (`BuilderText.uniformRateMissing(_:year:)`).
    private static func uniformDetail(of uniform: UniformAvailability, year: Int) -> String {
        guard case .ready(let usd, let eur, let instruction, let origin) = uniform else {
            return BuilderText.uniformRateMissing(uniform, year: year) ?? ""
        }
        let rates = [(CurrencyCode.usd, usd), (CurrencyCode.eur, eur)].compactMap { code, rate in
            rate.map { BuilderText.uniformRate($0, of: code, amount: 1) }
        }
        let source = BuilderText.uniformSource(instruction: instruction, origin: origin)
        return (rates + [source].compactMap { $0 }).joined(separator: " · ")
    }

    /// "odvody 548 037 Kč · o 3 063 Kč méně": `levies` against `other`, the levies with the other method.
    private static func levies(of levies: Int64, against other: Int64) -> String {
        let difference = levies - other
        let compared =
            difference == 0
            ? "stejně" : "o " + CzechFormat.wholeKc(abs(difference)) + (difference < 0 ? " méně" : " více")
        return "odvody " + CzechFormat.wholeKc(levies) + " · " + compared
    }

    /// The note under the items: that the choice changes nothing in a year without payments in other currencies, that
    /// the year is computed at the daily rates until it has its uniform rate, or what the choice applies to.
    private static func footer(of state: YearFXState) -> String {
        let year = state.year
        guard state.hasForeignPayments else {
            return "V roce \(year) nepřišla žádná platba v cizí měně – volba nic nemění."
        }
        guard state.uniform.isReady else {
            if state.chosen == .uniform {
                return "Rok \(year) se zatím počítá denními kurzy ČNB. Jednotným kurzem, který jste pro něj zvolili, se"
                    + " přepočte, až bude kurz v aplikaci."
            }
            return "Rok \(year) se počítá denními kurzy ČNB. Jednotný kurz půjde zvolit, až bude pro rok \(year) známý."
        }
        return "Platí pro všechny platby v cizí měně přijaté v roce \(year) – v Přehledu, Fakturách i Výpočtu."
            + " Každý rok si volbu pamatuje zvlášť."
    }
}

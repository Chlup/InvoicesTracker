import SwiftUI

/// The texts of the notice that tells a year converts its income in other currencies at a preliminary uniform rate,
/// one the app computed from the month-end rates of the ČNB.
nonisolated enum PreliminaryRateNoticeText {
    /// The title and the sentence of the notice of `state`, on the day `today`. Nil unless the year converts at a
    /// computed rate (`YearFXState.usesComputedRate`), was paid in other currencies and was paid in dollars or euros,
    /// the currencies whose rate is computed. The sentence names those currencies and their rates, how many months the
    /// rate averages, and what happens next: the rate gets more exact, should match the GFŘ rate, or has to be entered
    /// by hand once the search for it is over (`UniformRateSearch`).
    static func content(state: YearFXState, today: CivilDate) -> (title: String, sentence: String)? {
        guard state.usesComputedRate, state.hasForeignPayments,
            case .ready(let usd, let eur, _, _, let computedMonths) = state.uniform, let months = computedMonths,
            (1...12).contains(months)
        else { return nil }
        let rates = [(CurrencyCode.usd, usd), (CurrencyCode.eur, eur)].filter { code, rate in
            rate != nil && state.paidCurrencies.contains(code)
        }
        guard !rates.isEmpty else { return nil }
        let currencies = rates.map(\.0.code).joined(separator: " a ")
        let shown = rates.compactMap { code, rate in
            rate.map { BuilderText.uniformRate($0, of: code, amount: 1, computed: true) }
        }.joined(separator: ", ")
        let title = "Předběžný jednotný kurz \(state.year)"
        let start = "Platby v \(currencies) jsou přepočtené "
        if months < 12 {
            let sentence =
                start + "průměrem kurzů ČNB za \(BuilderText.monthSpan(months)) (\(shown))."
                + " Po každém skončeném měsíci se kurz zpřesní; oficiální vyhlásí GFŘ v lednu \(state.year + 1)."
            return (title, sentence)
        }
        let computed = start + "kurzem, který aplikace spočítala ze všech 12 měsíců (\(shown))."
        if UniformRateSearch(year: state.year, today: today) == .over {
            return (title, computed + " Aplikace kurz GFŘ nenašla – zadejte ho podle pokynu GFŘ v Nastavení › Rok.")
        }
        return (
            title,
            computed + " Měl by se shodovat s kurzem GFŘ; až ho GFŘ vyhlásí, aplikace vám ho dá potvrdit."
        )
    }
}

/// The calm orange line under the banner of the window, on every screen whose numbers a computed uniform rate affects:
/// a clock, the title in bold orange, a dash and the sentence, and Podrobnosti, which shows where the rate is set
/// (`showDetails`). It cannot be closed. The text wraps on a narrow window, and VoiceOver reads the notice as one
/// container named by its title, with Podrobnosti reachable inside it.
struct PreliminaryRateNotice: View {
    let title: String
    let sentence: String
    let showDetails: () -> Void

    /// The weight of the edge around the notice, in points.
    private static var edgeWidth: CGFloat {
        0.5
    }

    var body: some View {
        let panel = RoundedRectangle(cornerRadius: DesignMetrics.panelRadius)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "clock")
                .foregroundStyle(Palette.orangeText)
                .accessibilityHidden(true)
            (Text(verbatim: title).bold().foregroundStyle(Palette.orangeText)
                + Text(verbatim: " – " + sentence).foregroundStyle(Palette.text))
                .font(Typography.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Podrobnosti", action: showDetails)
                .buttonStyle(CapsuleButtonStyle(.secondary, size: .small))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.orangeTint, in: panel)
        .overlay(panel.strokeBorder(Palette.orangeText.opacity(0.35), lineWidth: Self.edgeWidth))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

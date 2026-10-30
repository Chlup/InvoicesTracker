import SwiftUI

/// A warning that the figures of the year are not final: they are an estimate with the rules of another year
/// (`message(year:rulesYear:)`), or part of the income is converted at a provisional rate (`provisionalIncome`). It
/// stands above the content of Přehled, Výpočet and Odhad odvodů, the second under the first when both show, and above
/// the cards of Nastavení › Rok, which show the first only. An orange box, in the semantic colour at a low opacity.
struct RulesWarning: View {
    let text: String

    /// The text for a year that is computed with the rules of another year, `rulesYear`, the nearest year the app has
    /// rules for. Přehled, Výpočet, Odhad odvodů and Nastavení › Rok show the same one.
    nonisolated static func message(year: Int, rulesYear: Int) -> String {
        "Pravidla pro rok \(year) zatím nejsou v aplikaci – výpočet je odhad podle roku \(rulesYear)."
    }

    /// The text for a year with a receipt up to the day shown that is converted at a provisional rate, until the ČNB
    /// rate of its day or the uniform rate of its year is there.
    nonisolated static let provisionalIncome =
        "≈ Část příjmů je zatím přepočtená předběžným kurzem. Přepočte se sama, až budou kurzy ČNB k dispozici."

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(Color(.simulationText))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

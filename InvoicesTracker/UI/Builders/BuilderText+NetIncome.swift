import Foundation

/// The texts that the cards of the net income ("čistý příjem") of Výpočet, Odhad odvodů, Simulátor and Přehled write
/// the same way.
nonisolated extension BuilderText {
    /// The months an average of the net income is over, as the card says it: "celý rok" for a whole year, "leden" for
    /// the first month alone, and otherwise the months so far from January through the last one, "leden–říjen".
    static func months(of net: NetIncome) -> String {
        if net.isWholeYear {
            return "celý rok"
        }
        return net.months == 1 ? "leden" : "leden–" + CzechFormat.monthNames[net.months - 1]
    }

    /// A share of the income given in tenths of a percent as a percentage with one decimal: 118 is "11,8 %" and −12 is
    /// "−1,2 %".
    static func share(tenths: Int64) -> String {
        CzechFormat.percent(Decimal(tenths) / 1_000, fractionDigits: 1)
    }

    /// The note under the net income that the actual expenses of the business are not taken off it: the app knows only
    /// the flat-rate expenses, which are no money spent.
    static let expensesNotSubtracted = "skutečné výdaje podnikání tu odečtené nejsou"
}

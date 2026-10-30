import Foundation

/// A rate of the flat-rate expenses as the menus of Zálohy a odpočty and of Simulátor offer it: the percentage with
/// what it is for.
nonisolated struct ExpenseRateChoice: Sendable, Hashable {
    let percent: Int
    let label: String

    /// The four rates, the highest first.
    static let all = [
        ExpenseRateChoice(percent: 80, label: "80 % – řemeslné živnosti, zemědělství"),
        ExpenseRateChoice(percent: 60, label: "60 % – volné, vázané a koncesované živnosti"),
        ExpenseRateChoice(percent: 40, label: "40 % – jiné podnikání, svobodná povolání"),
        ExpenseRateChoice(percent: 30, label: "30 % – nájem obchodního majetku"),
    ]

    /// What the screens say next to the rate of 30 %, which is for the rent of business property: ordinary rent is
    /// income under § 9 of the income tax act, which the app does not compute. Nil for any other rate.
    static func note(forPercent percent: Int) -> String? {
        percent == 30 ? "Běžný pronájem podle § 9 aplikace nepočítá – není to příjem z podnikání." : nil
    }
}

nonisolated extension MortgageCap {
    /// The limits as the menus of the interest offer them, the one of housing acquired from 2021 first.
    static let choices: [MortgageCap] = [.after2021, .before2021]

    /// "150 000 Kč – pořízeno od 1. 1. 2021" and "300 000 Kč – pořízeno do 31. 12. 2020": the limit with when the
    /// housing was acquired.
    var choiceLabel: String {
        let limit = CzechFormat.wholeKc(annualCap)
        switch self {
        case .after2021: return limit + " – pořízeno od 1.\u{00A0}1.\u{00A0}2021"
        case .before2021: return limit + " – pořízeno do 31.\u{00A0}12.\u{00A0}2020"
        }
    }
}

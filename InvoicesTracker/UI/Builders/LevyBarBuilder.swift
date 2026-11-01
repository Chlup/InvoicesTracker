import Foundation

// MARK: - The names of the authorities

nonisolated extension Authority {
    /// The full name of the authority, as a row, a popover or VoiceOver names it: "Daň z příjmů", "Sociální pojištění",
    /// "Zdravotní pojištění".
    var title: String {
        switch self {
        case .tax: "Daň z příjmů"
        case .social: "Sociální pojištění"
        case .health: "Zdravotní pojištění"
        }
    }

    /// The short name of the authority, as an inline split, a legend, a column or a tile names it: "Daň", "Sociální",
    /// "Zdravotní".
    var shortTitle: String {
        switch self {
        case .tax: "Daň"
        case .social: "Sociální"
        case .health: "Zdravotní"
        }
    }

    /// The office that the levy is paid to, as the popover of the levy bar names it: "Finanční úřad", "ČSSZ", "VZP".
    var office: String {
        switch self {
        case .tax: "Finanční úřad"
        case .social: "ČSSZ"
        case .health: "VZP"
        }
    }
}

// MARK: - The bar

/// Which levies a bar of the balances shows, which decides how the rows of its popovers are named.
nonisolated enum LevyBarKind: Sendable, Hashable {
    /// The levies of the income counted so far, with the advances paid so far ("Zaplaceno zálohami"), as Přehled and
    /// Výpočet show them: "Odvody z příjmů" with what is left of them, "Zbývá", in a year in progress, and "Odvody za
    /// rok" with the "Doplatek" in a year that is over (`isOver`).
    case toDate(isOver: Bool)

    /// The levies of a whole year, as Odhad odvodů shows them: "Odvody za rok", the advances of the whole year ("Zálohy
    /// za rok") and the "Doplatek".
    case wholeYear
}

/// Builds the levy bar of Výpočet, Přehled and Odhad odvodů from the balances of a result (`balances`), and that of
/// the Simulátor from the levies of the whole year of a simulation (`simulation`). Both name what VoiceOver reads with
/// `accessibilityLabel(of:rows:shareLine:note:)` and `accessibilityLabel(header:parts:)`.
nonisolated enum LevyBarBuilder {
    /// The bar of `result`'s balances under `header`, with the total of the levies and its share of the income when
    /// `showsTotal` (where the key figure beside the bar does not show them). Each part has the levy of its authority,
    /// in the legend and as the first row of its popover (`BuilderText.taxOrBonus`), then the advances, then the
    /// overpayment where the advances are more than the levy, "Vrátí se" for a tax bonus and "Přeplatek" otherwise, or
    /// else what is left to pay, named after `kind`; all in whole Kč. The share lines are the shares of the income
    /// (`IncomeShares`), and they and the share of the total are nil when there is no income above zero.
    static func balances(of result: TaxResult, kind: LevyBarKind, header: String, showsTotal: Bool) -> LevyBarData {
        let shares = IncomeShares(result)
        let parts = Authority.allCases.map { authority in
            part(of: result.balance(authority), kind: kind, shareTenths: shares?.tenths[authority])
        }
        return LevyBarData(
            header: header,
            total: showsTotal ? CzechFormat.wholeKc(result.liabilityTotal) : nil,
            totalShare: showsTotal ? shares.map { BuilderText.share(tenths: $0.leviesTenths) + " z příjmů" } : nil,
            parts: parts,
            accessibilityLabel: accessibilityLabel(header: header, parts: parts))
    }

    /// The bar of the Simulátor under `header`: the levies of the whole year of a simulation, with no total, as the key
    /// figure beside the bar is the total. Each part weighs the levy of its authority, so a tax bonus, a levy below
    /// zero, draws no part. The legend and the first row of the popover, "Za rok", say the levy
    /// (`BuilderText.taxOrBonus`), the second row, "Měsíčně", a twelfth of it rounded half up (a bonus reads with the
    /// minus sign: "−3 127 Kč"), and the third, "Z příjmu", its share of the income, which is `IncomeShares`' so that
    /// the three add up to the share of the three levies together ("−25,0 %" for a bonus), or "—" where there is no
    /// income above zero. All the amounts are whole Kč. `notes` are the conditions that apply to an authority, such as
    /// "platíte minimum": each stands under the rows of its popover and is read after them.
    static func simulation(of result: TaxResult, header: String, notes: [Authority: String]) -> LevyBarData {
        let shares = IncomeShares(result)
        let parts = Authority.allCases.map { authority in
            let levy = result.balance(authority).liability
            let year = BuilderText.taxOrBonus(levy)
            let share = shares?.tenths[authority].map { BuilderText.share(tenths: $0) } ?? noShare
            let rows = [
                LevyPopoverRow(label: "Za rok", value: year, style: .strong),
                LevyPopoverRow(
                    label: "Měsíčně", value: CzechFormat.wholeKc(DecimalMath.halfUp(Decimal(levy) / 12)),
                    style: .muted),
                LevyPopoverRow(label: "Z příjmu", value: share, style: .muted),
            ]
            let note = notes[authority]
            return LevyBarPart(
                authority: authority, weight: levy, legendValue: year, rows: rows, shareLine: nil, note: note,
                accessibilityLabel: accessibilityLabel(of: authority, rows: rows, shareLine: nil, note: note))
        }
        return LevyBarData(
            header: header, total: nil, totalShare: nil, parts: parts,
            accessibilityLabel: accessibilityLabel(header: header, parts: parts))
    }

    /// What a share of the income says where there is no income to take a share of: a dash.
    private static let noShare = "—"

    /// What VoiceOver reads for the item of the legend of `authority`: its full name, then each of `rows` as its label
    /// with a small first letter and its value, then `shareLine` and `note` where there are any, one after the other:
    /// "Daň z příjmů: odvody z příjmů 94 440 Kč, zaplaceno zálohami 23 000 Kč, zbývá 71 440 Kč, 4,3 % z příjmů bez
    /// DPH".
    static func accessibilityLabel(
        of authority: Authority, rows: [LevyPopoverRow], shareLine: String?, note: String?
    ) -> String {
        let phrases = rows.map { smallFirstLetter($0.label) + " " + $0.value } + [shareLine, note].compactMap { $0 }
        return authority.title + ": " + phrases.joined(separator: ", ")
    }

    /// What VoiceOver reads for the bar of `parts` under `header`: the header, then the full name of each authority
    /// with its value in the legend, "Odvody z příjmů do 17. 10.: Daň z příjmů 94 440 Kč, Sociální pojištění
    /// 159 279 Kč, Zdravotní pojištění 66 945 Kč".
    static func accessibilityLabel(header: String, parts: [LevyBarPart]) -> String {
        header + ": " + parts.map { $0.authority.title + " " + $0.legendValue }.joined(separator: ", ")
    }

    /// The part of `balance`'s authority in a bar of `kind`, with the share of the income of `shareTenths` tenths of a
    /// percent, or none for nil.
    private static func part(of balance: AuthorityBalance, kind: LevyBarKind, shareTenths: Int64?) -> LevyBarPart {
        let levy = BuilderText.taxOrBonus(balance.liability)
        let rows = [
            LevyPopoverRow(label: levyLabel(kind), value: levy, style: .strong),
            LevyPopoverRow(
                label: advancesLabel(kind), value: CzechFormat.wholeKc(balance.advancesPaid), style: .muted),
            lastRow(of: balance, kind: kind),
        ]
        let shareLine = shareTenths.map { BuilderText.share(tenths: $0) + " z příjmů bez DPH" }
        return LevyBarPart(
            authority: balance.authority, weight: balance.liability, legendValue: levy, rows: rows,
            shareLine: shareLine, note: nil,
            accessibilityLabel: accessibilityLabel(of: balance.authority, rows: rows, shareLine: shareLine, note: nil))
    }

    /// The row that ends the popover of `balance`'s authority: the overpayment in green where the advances are more
    /// than the levy, "Vrátí se" while the levy is a tax bonus and "Přeplatek" otherwise, and else what is left to pay,
    /// "Zbývá" in a year in progress and "Doplatek" in a year that is over or a whole year.
    private static func lastRow(of balance: AuthorityBalance, kind: LevyBarKind) -> LevyPopoverRow {
        if balance.overpayment > 0 {
            return LevyPopoverRow(
                label: balance.liability < 0 ? "Vrátí se" : "Přeplatek",
                value: CzechFormat.wholeKc(balance.overpayment), style: .positive)
        }
        let label =
            switch kind {
            case .toDate(isOver: false): "Zbývá"
            case .toDate(isOver: true), .wholeYear: "Doplatek"
            }
        return LevyPopoverRow(label: label, value: CzechFormat.wholeKc(balance.remaining), style: .strong)
    }

    /// The label of the levy in a bar of `kind`: "Odvody z příjmů" in a year in progress, "Odvody za rok" in a year
    /// that is over or a whole year.
    private static func levyLabel(_ kind: LevyBarKind) -> String {
        switch kind {
        case .toDate(isOver: false): "Odvody z příjmů"
        case .toDate(isOver: true), .wholeYear: "Odvody za rok"
        }
    }

    /// The label of the advances in a bar of `kind`: the advances paid so far, "Zaplaceno zálohami", or those of the
    /// whole year, "Zálohy za rok".
    private static func advancesLabel(_ kind: LevyBarKind) -> String {
        switch kind {
        case .toDate: "Zaplaceno zálohami"
        case .wholeYear: "Zálohy za rok"
        }
    }

    /// `text` with its first letter small, as a label reads in the middle of a sentence: "Zbývá" is "zbývá".
    private static func smallFirstLetter(_ text: String) -> String {
        text.prefix(1).lowercased() + String(text.dropFirst())
    }
}

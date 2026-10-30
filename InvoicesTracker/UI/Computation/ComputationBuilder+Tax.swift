import Foundation

/// The income tax card: from the profit through the deductions, the base and the two rates to the tax, the credits of
/// the family and the tax bonus, and what the advances leave of it.
nonisolated extension ComputationBuilder {
    static func taxSection(_ facts: Facts) -> ComputationSection {
        let result = facts.result
        var rows = [
            ComputationRow(label: "Zisk", value: crowns(result.DZ)),
            ComputationRow(
                label: "Nezdanitelné části základu", value: crowns(-result.deductionsTotal),
                note: deductionsNote(result), sign: .minus),
            ComputationRow(
                label: "Základ daně", value: CzechFormat.grouped(result.B), note: "zaokrouhleno na celé stovky dolů",
                sign: .equals, style: .strong),
        ]
        rows += bandRows(facts)
        rows += [
            ComputationRow(
                label: "Daň před slevou", value: CzechFormat.grouped(result.taxBeforeCredit), note: roundedUp,
                sign: .equals),
            ComputationRow(
                label: "Sleva na poplatníka", value: CzechFormat.grouped(-result.creditApplied),
                note: creditNote(facts), sign: .minus),
        ]
        rows += familyRows(result)
        // The net tax: a tax bonus makes it negative.
        rows.append(
            ComputationRow(
                label: facts.isOver ? "Daň za rok \(result.year)" : "Daň z dosavadních příjmů",
                value: CzechFormat.grouped(result.netTax), note: result.netTax < 0 ? bonusNote : nil,
                sign: .equals, style: .strong))
        rows += tailRows(of: .tax, facts)
        return ComputationSection(title: "Daň z příjmů", rows: rows, authority: .tax, tag: "Finanční úřad")
    }

    // MARK: The family

    /// The note of a negative tax, the tax less a tax bonus.
    static let bonusNote = "záporná daň je daňový bonus – vyplatí ho finanční úřad"

    /// The steps of the family after the taxpayer credit, while the spouse credit or the child benefit of the year is
    /// more than nothing: the spouse credit, while it is; the tax the two credits leave, which they take down to zero
    /// at most; and the child benefit, while it is, as the credit it takes and the bonus that is paid. Each value is
    /// the part used, as with the taxpayer credit, so the rows add up to the net tax. A year without them has none of
    /// the rows. The card of the tax of the Simulátor has them too.
    static func familyRows(_ result: TaxResult) -> [ComputationRow] {
        let family = result.family
        guard family.spouseCredit > 0 || family.childBenefit > 0 else { return [] }
        var rows: [ComputationRow] = []
        if family.spouseCredit > 0 {
            rows.append(
                ComputationRow(
                    label: "Sleva na manžela / manželku", value: CzechFormat.grouped(-result.spouseCreditApplied),
                    note: spouseNote(result), sign: .minus))
        }
        rows.append(
            ComputationRow(
                label: "Daň po slevách", value: CzechFormat.grouped(result.taxAfterCredits),
                note: "slevy snižují daň nejvýš na nulu", sign: .equals, style: .strong))
        if family.childBenefit > 0 {
            rows.append(
                ComputationRow(
                    label: "Daňové zvýhodnění na děti",
                    value: CzechFormat.grouped(-(result.childCredit + result.childBonus)), note: childNote(result),
                    sign: .minus))
        }
        return rows
    }

    /// "12 měsíců s dítětem do 3 let · 3 se ZTP/P": the months the spouse credit counts, from 2024 those with a child
    /// under three, with the months of ZTP/P, which count twice, and why less of the credit is used, when it is.
    private static func spouseNote(_ result: TaxResult) -> String {
        let family = result.family
        var note = months(family.spouseMonths) + (result.rules.spouseNeedsYoungChild ? " s dítětem do 3 let" : "")
        if family.spouseZTPPMonths > 0 {
            note += " · \(family.spouseZTPPMonths) se ZTP/P"
        }
        let applied = result.spouseCreditApplied
        if applied < family.spouseCredit {
            note +=
                applied > 0
                ? " · uplatní se jen " + CzechFormat.wholeKc(applied) + ", víc daně nezbývá"
                : " · daň už je nulová, sleva se neprojeví"
        }
        return note
    }

    /// "Anna 15 204 · Tomáš 22 320": each child of mine that brings something, in the order of the family, "dítě" for
    /// one without a name, and what the benefit leaves after its credit: the bonus that is paid, or why it is not.
    private static func childNote(_ result: TaxResult) -> String {
        let children = result.family.children.filter { !$0.claimedByOther && $0.amount > 0 }.map { child in
            (child.label.isEmpty ? "dítě" : child.label) + " " + CzechFormat.grouped(child.amount)
        }
        var note = children.joined(separator: " · ")
        switch result.bonusWithheld {
        case nil:
            if result.childBonus > 0 {
                note += " · z toho daňový bonus " + CzechFormat.grouped(result.childBonus)
            }
        case .belowMinimum:
            note +=
                " · bonus \(CzechFormat.grouped(result.withheldBonus)) se nevyplatí: je pod "
                + CzechFormat.wholeKc(result.rules.bonusMinimum)
        case .incomeBelowThreshold(let threshold):
            note +=
                " · bonus \(CzechFormat.grouped(result.withheldBonus)) se nevyplatí: příjmy pod 6× minimální mzdu"
                + " (\(CzechFormat.grouped(threshold)))"
        }
        return note
    }

    /// The tax of the part of the base in each band, each at its rate. The rates are whole percents, so each part is a
    /// whole number of haléře and the two add up exactly; the tax before the credit is their sum rounded up.
    private static func bandRows(_ facts: Facts) -> [ComputationRow] {
        let result = facts.result
        let rules = result.rules
        let threshold = CzechFormat.grouped(rules.taxBandThreshold)
        let lowBase = result.taxBaseInLowBand
        let highBase = result.taxBaseInHighBand
        let lowPart = DecimalMath.halfUp(TaxRules.taxRateLow * Decimal(lowBase) * 100)
        let highPart = DecimalMath.halfUp(TaxRules.taxRateHigh * Decimal(highBase) * 100)
        let lowNote =
            "z \(CzechFormat.grouped(lowBase)) základu (pásmo do \(threshold)) · " + rulesVersion(of: rules)
        let highNote =
            highBase > 0
            ? "z \(CzechFormat.grouped(highBase)) základu (pásmo nad \(threshold))"
            : "pásmo nad \(threshold) \(facts.isOver ? "" : "zatím ")nedosaženo"
        return [
            ComputationRow(
                label: "Sazba " + percent(TaxRules.taxRateLow, fractionDigits: 0), value: wholeOrHalere(lowPart),
                note: lowNote, sign: .times),
            ComputationRow(
                label: "Sazba " + percent(TaxRules.taxRateHigh, fractionDigits: 0), value: wholeOrHalere(highPart),
                note: highNote, sign: .times),
        ]
    }

    /// The deductions that count, one after the other, each with what the law allows of it and where the limit cut it.
    /// Výpočet and Odhad odvodů write them so.
    static func deductionsNote(_ result: TaxResult) -> String {
        var items = result.deductionLines.compactMap(deductionItem)
        let allowed = result.deductionLines.reduce(0) { $0 + $1.allowed }
        if !items.isEmpty && result.deductionsTotal < allowed {
            items.append("celkem nejvýše do výše zisku")
        }
        return items.isEmpty ? "žádné" : items.joined(separator: " · ")
    }

    private static func deductionItem(_ line: DeductionLine) -> String? {
        guard line.claimed > 0 else { return nil }
        let name =
            switch line.kind {
            case .mortgageInterest: "úroky z hypotéky"
            case .pensionSavings: "penzijní spoření"
            case .lifeInsurance: "životní pojištění"
            case .retirementProducts: "spoření a pojištění"
            case .gifts: "dary"
            }
        let claimed = CzechFormat.grouped(line.claimed)
        // Gifts that count are capped by a limit; gifts that are allowed nothing while the limit is above zero are
        // below the minimum.
        if line.kind == .gifts && line.allowed == 0 && (line.limit ?? 0) > 0 {
            return "\(name) \(claimed) (pod minimem – neuplatní se)"
        }
        if line.allowed < line.claimed {
            return "\(name) \(CzechFormat.grouped(line.allowed)) z \(claimed) (limit)"
        }
        return "\(name) \(claimed)"
    }

    /// What the row of the taxpayer credit says: that it is not claimed, that only part of it can be used because the
    /// tax is lower, or that the whole of it is. Výpočet and Odhad odvodů write it so.
    static func creditNote(_ facts: Facts) -> String {
        let credit = facts.result.rules.taxpayerCredit
        if !facts.input.taxpayerCredit {
            return "neuplatňuje se"
        }
        if facts.result.creditApplied < credit {
            return "roční sleva \(CzechFormat.grouped(credit)) se uplatní nejvýše do výše daně"
        }
        return "celá roční částka"
    }
}

import Foundation

/// The social insurance card: the base and its minimum and maximum, and for a year with secondary activity how it is
/// insured, then the insurance and what the advances leave of it.
nonisolated extension ComputationBuilder {
    static func socialSection(_ facts: Facts) -> ComputationSection {
        ComputationSection(
            title: "Sociální pojištění", rows: socialRows(facts) + tailRows(of: .social, facts), authority: .social,
            tag: "ČSSZ")
    }

    /// The rows of the card above the advances and what is left (`tailRows(of:_:)`): the base, for a year with
    /// secondary activity how it is insured, and the insurance. Odhad odvodů ends them with rows of its own.
    static func socialRows(_ facts: Facts) -> [ComputationRow] {
        let social = facts.result.social
        var rows: [ComputationRow]
        if social.mainMonths > 0 && social.secondaryMonths > 0 {
            rows = mixedYearRows(facts)
        } else {
            rows = social.secondaryMonths > 0 ? secondaryActivityRows(facts) : []
            rows += baseRows(facts)
        }
        rows.append(
            ComputationRow(
                label: "Sazba " + percent(TaxRules.socialRate, fractionDigits: 1),
                value: CzechFormat.grouped(social.insurance), note: roundedUp, sign: .times))
        return rows
    }

    /// The computed base and the base: the rows of a year with one kind of activity. The note of the base names the
    /// minimum with its months and the maximum. When the secondary activity is not insured, nothing is assessed.
    private static func baseRows(_ facts: Facts) -> [ComputationRow] {
        let social = facts.result.social
        let rules = facts.result.rules
        let isSecondary = social.secondaryMonths > 0
        let isInsured = !isSecondary || social.secondaryInsured == true
        let monthlyMinimum = isSecondary ? rules.socialMinimumMonthlySecondary : rules.socialMinimumMonthlyMain
        let countedMonths = isSecondary ? social.secondaryMonths : social.mainMonths
        let kind = isSecondary ? "vedlejší" : "hlavní"
        let share = assessmentShare(rules)
        let minimum =
            "min. \(CzechFormat.grouped(social.minimumBase))"
            + " (\(CzechFormat.grouped(monthlyMinimum)) × \(months(countedMonths)) \(kind) činnosti)"
        let baseNote =
            isInsured
            ? "\(share) zisku, nahoru · \(minimum) · max. \(CzechFormat.grouped(social.maximumBase)) (\(annualMaximum))"
            : "nic se nevyměřuje"
        return [
            ComputationRow(
                label: "Vypočtený základ", value: CzechFormat.grouped(social.computedBase),
                note: isInsured ? "\(share) zisku, zaokrouhleno nahoru" : secondaryNotInsured),
            ComputationRow(label: "Vyměřovací základ", value: CzechFormat.grouped(social.base), note: baseNote),
        ]
    }

    /// The rows that come first when the activity of the counted months is secondary only: the reduced decisive amount
    /// and whether the profit reaches it.
    private static func secondaryActivityRows(_ facts: Facts) -> [ComputationRow] {
        let profit = CzechFormat.grouped(max(0, facts.result.DZ))
        return [
            reducedDecisiveAmountRow(facts),
            insuredRow(facts, subject: "zisk \(profit)"),
        ]
    }

    /// The decisive amount less a twelfth of it, rounded up, for each month without secondary activity, with how that
    /// was worked out. Before the end of the year the months after the day shown count as such months, which is a
    /// convention of the app and is said so.
    private static func reducedDecisiveAmountRow(_ facts: Facts) -> ComputationRow {
        let result = facts.result
        let rules = result.rules
        let withoutSecondary = 12 - result.social.secondaryMonths
        var note =
            "\(CzechFormat.grouped(rules.socialDecisiveAmount)) − \(withoutSecondary) × "
            + "\(CzechFormat.grouped(rules.decisiveTwelfth)) "
            + "(\(months(withoutSecondary)) bez vedlejší činnosti)"
        if result.lastCountedMonth < 12 {
            note += " · " + notReachedMonthsConvention
        }
        return ComputationRow(
            label: "Snížená rozhodná částka", value: CzechFormat.grouped(result.social.reducedDecisiveAmount ?? 0),
            note: note)
    }

    private static func insuredRow(_ facts: Facts, subject: String) -> ComputationRow {
        let isInsured = facts.result.social.secondaryInsured == true
        return ComputationRow(
            label: "Vedlejší činnost", value: isInsured ? "pojištěná" : "nepojištěná",
            note: "\(subject) \(isInsured ? "dosáhl" : "nedosáhl") snížené rozhodné částky")
    }

    /// A year with both main and secondary months: the rows 23 to 27 of the overview of the social security
    /// administration. The result holds row 23, the sums of rows 25 and 26 and the base (row 27); the shares of row 24
    /// and the parts of the sums are worked out here from them the way the engine does.
    private static func mixedYearRows(_ facts: Facts) -> [ComputationRow] {
        let result = facts.result
        let social = result.social
        let rules = result.rules
        let row23 = social.row23 ?? 0
        let isInsured = social.secondaryInsured == true
        let mainMonths = Int64(social.mainMonths)
        let secondaryMonths = Int64(social.secondaryMonths)

        let row23Halere = DecimalMath.halfUp(row23 * 100)
        let mainShare = row23 * Decimal(social.mainMonths)
        let secondaryShare = row23 * Decimal(social.secondaryMonths)
        let mainBase = DecimalMath.ceil(rules.socialAssessmentPercent * mainShare)
        let secondaryBase = isInsured ? DecimalMath.ceil(rules.socialAssessmentPercent * secondaryShare) : 0
        let mainMinimum = rules.socialMinimumMonthlyMain * mainMonths
        let secondaryMinimum = isInsured ? rules.socialMinimumMonthlySecondary * secondaryMonths : 0

        let activityMonths = social.mainMonths + social.secondaryMonths
        let profit = CzechFormat.grouped(max(0, result.DZ))
        let secondaryMinimumText =
            isInsured
            ? "\(CzechFormat.grouped(rules.socialMinimumMonthlySecondary)) × \(secondaryMonths) = "
                + CzechFormat.grouped(secondaryMinimum)
            : CzechFormat.grouped(0)
        let candidates = [
            "ř.\u{00A0}25 celkem \(CzechFormat.grouped(social.computedBase))",
            "ř.\u{00A0}26 celkem \(CzechFormat.grouped(social.minimumBase))",
            "ř.\u{00A0}26 hlavní + ř.\u{00A0}25 vedlejší \(CzechFormat.grouped(mainMinimum + secondaryBase))",
        ]
        return [
            ComputationRow(
                label: "Zisk na měsíc činnosti (ř.\u{00A0}23)", value: CzechFormat.amount(row23Halere),
                note:
                    "zisk \(profit) ÷ \(months(activityMonths)) činnosti,"
                    + " na haléře od poloviny nahoru"),
            ComputationRow(
                label: "Podíl zisku, hlavní činnost (ř.\u{00A0}24)",
                value: CzechFormat.amount(row23Halere * mainMonths),
                note: "ř.\u{00A0}23 × " + months(social.mainMonths)),
            ComputationRow(
                label: "Podíl zisku, vedlejší činnost (ř.\u{00A0}24)",
                value: CzechFormat.amount(row23Halere * secondaryMonths),
                note: "ř.\u{00A0}23 × " + months(social.secondaryMonths)),
            reducedDecisiveAmountRow(facts),
            insuredRow(facts, subject: "podíl zisku \(CzechFormat.amount(row23Halere * secondaryMonths))"),
            ComputationRow(
                label: "Základ z podílů zisku (ř.\u{00A0}25)", value: CzechFormat.grouped(social.computedBase),
                note:
                    "\(assessmentShare(rules)) podílů, nahoru: hlavní \(CzechFormat.grouped(mainBase))"
                    + " + vedlejší \(CzechFormat.grouped(secondaryBase))"),
            ComputationRow(
                label: "Minimální základ (ř.\u{00A0}26)", value: CzechFormat.grouped(social.minimumBase),
                note:
                    "hlavní \(CzechFormat.grouped(rules.socialMinimumMonthlyMain)) × \(mainMonths)"
                    + " = \(CzechFormat.grouped(mainMinimum)) + vedlejší \(secondaryMinimumText)"),
            ComputationRow(
                label: "Vyměřovací základ (ř.\u{00A0}27)", value: CzechFormat.grouped(social.base),
                note:
                    "nejvyšší z: " + candidates.joined(separator: " · ")
                    + "; nejvýše max. \(CzechFormat.grouped(social.maximumBase)) (\(annualMaximum))"),
        ]
    }

    /// "55 %": the share of the profit that is the social assessment base.
    private static func assessmentShare(_ rules: TaxRules) -> String {
        percent(rules.socialAssessmentPercent, fractionDigits: 0)
    }
}

import Foundation

/// The banner and the cards of Výpočet around the breakdown: what the computation counts, the equation of what is left
/// to pay, the marginal levy, the thresholds of the year and the assumptions. As with the breakdown, every figure comes
/// from the result; the receipts are read only for the day the cap of the expenses was reached.
nonisolated extension ComputationBuilder {
    /// The whole page for `result`, the computation of `input` as of the day in it. `today` tells a year that is over
    /// from one in progress, `incomeFXMethod` how the year converts the income in other currencies, and
    /// `uniformSource` where its uniform rate is from (`BuilderText.uniformSource(of:)`), when it is known.
    static func buildPage(
        _ result: TaxResult, input: YearInput, today: CivilDate, incomeFXMethod: IncomeFXMethod,
        uniformSource: String? = nil
    ) -> ComputationPage {
        let facts = makeFacts(
            result, input: input, today: today, incomeFXMethod: incomeFXMethod, uniformSource: uniformSource)
        return ComputationPage(
            year: result.year, banner: banner(facts), sections: sections(facts), equation: equation(facts),
            marginal: marginal(of: result), thresholds: thresholds(facts), assumptions: assumptions(facts))
    }

    // MARK: Banner

    /// What the computation counts. A year that is over, shown as of its last day, counts everything of it; any other
    /// day counts the payments received up to it, and the advances of the months up to it as paid in their own months.
    private static func banner(_ facts: Facts) -> String {
        let result = facts.result
        if facts.isOver {
            return "Rok \(result.year) celý: všechny přijaté platby, všechny zálohy, odpočty a slevy za celý rok."
        }
        // In January there is one month of advances to name, not a span from January to January.
        let months = result.asOf.month == 1 ? "leden" : "leden až " + CzechFormat.monthNames[result.asOf.month - 1]
        return "Počítáno jen ze skutečně přijatých plateb od 1.\u{00A0}1. do \(CzechFormat.date(result.asOf))."
            + " Zálohy za \(months) bereme jako zaplacené v jejich měsíci."
            + " Odpočty a sleva na poplatníka se berou za celý rok,"
            + " minimální pojistné jen za uplynulé měsíce hlavní činnosti."
    }

    // MARK: Equation

    /// What each authority still has to get, added up. Only what is still owed is added: an overpayment at one never
    /// pays what is owed at another.
    private static func equation(_ facts: Facts) -> ComputationEquation {
        let result = facts.result
        let shares = Authority.allCases.enumerated().map { index, authority in
            ComputationTile(
                sign: index == 0 ? .blank : .plus, label: shortName(of: authority),
                value: CzechFormat.grouped(result.balance(authority).remaining), isResult: false)
        }
        let sum = ComputationTile(
            sign: .equals, label: facts.isOver ? "Doplatek za rok" : "Zbývá zaplatit",
            value: CzechFormat.wholeKc(result.remainingTotal), isResult: true)
        let split: String
        if facts.isOver {
            let returned: String
            if result.childBonus > 0 {
                // A tax bonus comes back with the overpaid advances, and is no overpayment of them.
                returned =
                    ", vrátí se \(CzechFormat.wholeKc(result.overpaymentTotal))"
                    + " (z toho daňový bonus \(CzechFormat.wholeKc(result.childBonus)))."
            } else if result.overpaymentTotal > 0 {
                returned = ", přeplatky \(CzechFormat.wholeKc(result.overpaymentTotal)) se vrací."
            } else {
                returned = "."
            }
            split = "Zálohami se za rok zaplatilo \(CzechFormat.wholeKc(result.advancesPaidTotal))" + returned
        } else {
            split =
                "Z toho \(CzechFormat.wholeKc(result.leavesViaPlannedAdvances)) odejde naplánovanými zálohami"
                + " do konce roku a \(CzechFormat.wholeKc(result.settlementTotal))"
                + " doplatíte po podání přiznání a přehledů."
        }
        return ComputationEquation(
            heading: facts.isOver
                ? "Doplatek za rok \(result.year)" : "Zbývá zaplatit k " + CzechFormat.date(result.asOf),
            caption: "sčítají se jen kladné zůstatky – přeplatek u jednoho úřadu nezaplatí dluh u jiného",
            tiles: shares + [sum], split: split)
    }

    // MARK: Marginal levy

    /// What the three levies take of the next crown, from the levies with 100 000 Kč more income that the engine
    /// worked out, and each authority's part of the sum for the bar. The sentence names the sum and the three parts per
    /// hundred crowns, with the haléře, and the parts add up to the sum shown. Only the result is read, so the
    /// Simulátor shows the same card.
    static func marginal(of result: TaxResult) -> ComputationMarginal {
        // Tax, social, health: the order of `Authority.allCases`, which the text and the bar follow.
        let rates = Authority.allCases.map { result.marginal[$0] ?? 0 }
        let sum = result.marginalTotal
        let shares = zip(Authority.allCases, rates).map { authority, rate in
            MarginalShare(authority: authority, fraction: sum > 0 ? fraction(of: max(0, rate), in: sum) : 0)
        }
        // Hundredths of a crown per hundred crowns (0,3781 is 3 781), the parts adding up to the rounded sum.
        let (parts, total) = DecimalMath.roundedKeepingSum(rates.map { $0 * 10_000 }, total: sum * 10_000)
        let text =
            "Ze 100\u{00A0}Kč dalšího příjmu bez DPH odvedete \(CzechFormat.amount(total))\u{00A0}Kč:"
            + " daň \(CzechFormat.amount(parts[0])) · sociální \(CzechFormat.amount(parts[1]))"
            + " · zdravotní \(CzechFormat.amount(parts[2]))."
        return ComputationMarginal(total: CzechFormat.percent(sum), shares: shares, text: text)
    }

    /// `part` of `whole` for drawing a bar, 0 to 1.
    private static func fraction(of part: Decimal, in whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: part / whole).doubleValue))
    }

    // MARK: Thresholds

    /// How far the year is from the cap of the flat-rate expenses, the band of 23 % and the maximum of the social base.
    private static func thresholds(_ facts: Facts) -> ComputationThresholds {
        let result = facts.result
        let rules = result.rules
        let capIncome = result.expenseCap * 100 / Int64(result.expensePercent)
        let capReached = facts.capIsReached
        let capValue: String
        if capReached {
            // The day is there whenever the cap is reached: the income of the whole year is counted on its last day.
            let day = dayIncomeReached(capIncome, in: facts).map { BuilderText.date($0, omittingYear: result.year) }
            capValue = "dosažen" + (day.map { " " + $0 } ?? "")
        } else {
            capValue = "zbývá " + CzechFormat.grouped(capIncome - result.P)
        }
        let bandReached = result.B > rules.taxBandThreshold
        let socialReached = result.social.base >= result.social.maximumBase
        return ComputationThresholds(
            heading: "Hranice roku \(result.year)",
            bars: [
                ThresholdBar(
                    title: "Strop paušálu (příjmy " + IncomeChartLayout.label(forKc: capIncome) + "\u{00A0}Kč)",
                    value: capValue,
                    fraction: fraction(of: Decimal(result.incomeHalere), in: Decimal(capIncome * 100)), authority: nil,
                    isReached: capReached, isHighlighted: capReached),
                ThresholdBar(
                    title: "23% pásmo daně",
                    value: bandReached
                        ? "překročeno" : "zbývá " + CzechFormat.grouped(rules.taxBandThreshold - result.B),
                    fraction: fraction(of: Decimal(result.B), in: Decimal(rules.taxBandThreshold)), authority: .tax,
                    isReached: bandReached, isHighlighted: false),
                ThresholdBar(
                    title: "Strop sociálního pojištění",
                    value: socialReached
                        ? "dosažen" : "zbývá " + CzechFormat.grouped(result.social.maximumBase - result.social.base),
                    fraction: fraction(of: Decimal(result.social.base), in: Decimal(result.social.maximumBase)),
                    authority: .social, isReached: socialReached, isHighlighted: false),
            ])
    }

    /// The first day by whose end the income of the year, counted to the crown as the engine counts it, was `income`
    /// whole crowns, or nil when it never was up to the day shown. The receipts of a day are added up before the day is
    /// judged.
    private static func dayIncomeReached(_ income: Int64, in facts: Facts) -> CivilDate? {
        let year = facts.result.year
        let asOf = facts.result.asOf
        let counted = facts.input.receipts.filter { $0.day.year == year && $0.day <= asOf }.sorted { $0.day < $1.day }
        var total: Int64 = 0
        var index = 0
        while index < counted.count {
            let day = counted[index].day
            while index < counted.count && counted[index].day == day {
                total += counted[index].czkNetHalere
                index += 1
            }
            if DecimalMath.halfUp(Decimal(total) / 100) >= income {
                return day
            }
        }
        return nil
    }

    // MARK: Assumptions

    /// What the computation takes for granted, among it that the minimum insurance counts only the months through the
    /// day shown. The conversion of the income in other currencies is the one the year uses, with where its uniform
    /// rate is from when that is known.
    private static func assumptions(_ facts: Facts) -> ComputationAssumptions {
        let result = facts.result
        let conversion: String
        if facts.incomeFXMethod == .uniform {
            let source = facts.uniformSource.map { " (\($0))" } ?? ""
            conversion = "Cizí měny v Kč jednotným kurzem \(result.year)" + source
        } else {
            conversion = "Cizí měny v Kč kurzem ČNB ke dni přijetí platby"
        }
        return ComputationAssumptions(
            items: [
                "Zálohy zaplacené v měsíci, ke kterému patří",
                "Bez zaměstnání a jiných zdanitelných příjmů",
                "Plátce DPH měsíčně, výdaje paušálem "
                    + percent(Decimal(result.expensePercent) / 100, fractionDigits: 0),
                conversion,
                "Minimální pojistné jen za měsíce hlavní činnosti do data výpočtu – celý rok ukazuje Odhad odvodů",
            ])
    }
}

import Foundation

/// The card of the net income ("Čistý příjem"): the income of the year less the tax, the social insurance and the
/// health insurance, what that leaves, and the average of it per month. Výpočet, Odhad odvodů and Simulátor show the
/// same card and word the few texts that differ among them themselves (`NetIncomeWording`). Every figure comes from
/// `NetIncome` and `IncomeShares`, which work it out from the result of the engine.
nonisolated extension ComputationBuilder {
    /// The texts of the card of the net income that a screen words for itself: what it calls the income and the result,
    /// what stands at the right of the title, the note of the number of months, and the word for the income in the
    /// share.
    nonisolated struct NetIncomeWording: Sendable, Hashable {
        /// The label of the first row, the income the levies are taken from: "Příjmy z podnikání (§ 7)".
        var incomeLabel: String

        /// The label of the row with the net income, the result of the rows above it: "Čistý příjem".
        var resultLabel: String

        /// What stands at the right of the title, such as the day the card is of, or nil for nothing.
        var tag: String?

        /// The note of the row with the number of months, such as the months so far, or nil for none.
        var divisorNote: String?

        /// The word for the income after the share in the note of the result: "příjmů" in "88,2 % příjmů".
        var incomeWord: String
    }

    /// The card of the net income of `result`, worded by `wording`. The income less the tax (or plus the tax bonus,
    /// which the tax office pays) and less the two insurances is the net income, and the net income divided by the
    /// months so far is the average per month. The income is written as in Příjmy a zisk, to the haléř, and the rest in
    /// whole crowns. The note of the result gives the part of the income that is left, while there is an income to take
    /// a part of, and says that the actual expenses of the business are not taken off.
    static func netIncomeSection(_ result: TaxResult, wording: NetIncomeWording) -> ComputationSection {
        let net = NetIncome(result)
        let rows = [
            ComputationRow(label: wording.incomeLabel, value: crowns(result.P), note: "bez DPH"),
            taxRow(of: result),
            ComputationRow(
                label: "Sociální pojištění", value: CzechFormat.grouped(-result.social.insurance), sign: .minus),
            ComputationRow(
                label: "Zdravotní pojištění", value: CzechFormat.grouped(-result.health.insurance), sign: .minus),
            ComputationRow(
                label: wording.resultLabel, value: CzechFormat.grouped(net.yearKc),
                note: resultNote(of: result, wording: wording), sign: .equals, style: .strong),
            ComputationRow(
                label: months(net.months), value: String(net.months), note: wording.divisorNote, sign: .divided),
            ComputationRow(
                label: "Průměrně za měsíc", value: CzechFormat.wholeKc(net.monthlyKc),
                note: "čistý příjem na jeden měsíc", sign: .equals, style: .total),
        ]
        return ComputationSection(title: "Čistý příjem", rows: rows, tag: wording.tag, isNetIncome: true)
    }

    /// The row of the tax: taken off the income, or, where the tax is negative because a tax bonus is paid, added to
    /// it.
    private static func taxRow(of result: TaxResult) -> ComputationRow {
        guard result.netTax < 0 else {
            return ComputationRow(label: "Daň z příjmů", value: CzechFormat.grouped(-result.netTax), sign: .minus)
        }
        return ComputationRow(
            label: "Daňový bonus", value: CzechFormat.grouped(-result.netTax), note: "vyplatí ho finanční úřad",
            sign: .plus)
    }

    /// The note of the net income: its share of the income and the expenses that are not taken off, or only the latter
    /// where the income is not above zero and there is nothing for the levies to take a part of.
    private static func resultNote(of result: TaxResult, wording: NetIncomeWording) -> String {
        guard let shares = IncomeShares(result) else { return BuilderText.expensesNotSubtracted }
        return BuilderText.share(tenths: shares.netTenths) + " " + wording.incomeWord + " · "
            + BuilderText.expensesNotSubtracted
    }
}

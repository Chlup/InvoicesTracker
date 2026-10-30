import Foundation

/// The health insurance card, and the two rows that end the card of each authority: the advances paid and what is
/// left to pay.
nonisolated extension ComputationBuilder {
    // MARK: Health insurance

    /// The health insurance card. The bases are in haléře because the minimum can be a half crown; they are not
    /// rounded.
    static func healthSection(_ facts: Facts) -> ComputationSection {
        let result = facts.result
        let health = result.health
        let rules = result.rules
        let monthlyMinimum = DecimalMath.halfUp(rules.healthMinimumMonthlyBase * 100)
        // Months of activity that are exempt from the minimum are not counted in it, and the note says so.
        let activeMonths = result.social.mainMonths + result.social.secondaryMonths
        let minimumMonths = months(health.minimumMonths) + (health.minimumMonths == activeMonths ? "" : " s minimem")
        let share = percent(TaxRules.healthAssessmentPercent, fractionDigits: 0)
        var rows = [
            ComputationRow(
                label: "Vypočtený základ", value: CzechFormat.amount(health.computedBaseHalere),
                note: "\(share) zisku"),
            ComputationRow(
                label: "Vyměřovací základ", value: CzechFormat.amount(health.baseHalere),
                note:
                    "\(share) zisku · min. \(CzechFormat.amount(health.minimumBaseHalere))"
                    + " (\(CzechFormat.amount(monthlyMinimum)) × \(minimumMonths))"
                    + " · bez maxima, nezaokrouhluje se"),
            ComputationRow(
                label: "Sazba " + percent(TaxRules.healthRate, fractionDigits: 1),
                value: CzechFormat.grouped(health.insurance), note: roundedUp, sign: .times),
        ]
        rows += tailRows(of: .health, facts)
        return ComputationSection(title: "Zdravotní pojištění", rows: rows, authority: .health, tag: "VZP")
    }

    // MARK: Advances and what is left

    /// The advances paid to an authority, taken off its levy, and what is left (`leftValue(_:)`): a Zbývá as of the day
    /// shown, or for a year that is over the Doplatek. An overpayment says how it comes back.
    static func tailRows(of authority: Authority, _ facts: Facts) -> [ComputationRow] {
        let result = facts.result
        let balance = result.balance(authority)
        return [
            ComputationRow(
                label: "Zálohy", value: CzechFormat.grouped(-balance.advancesPaid),
                note: advancesNote(plan(of: authority, facts.input.advances), throughMonth: result.asOf.month),
                sign: .minus),
            ComputationRow(
                label: facts.isOver ? "Doplatek" : "Zbývá", value: leftValue(balance), note: leftNote(balance, facts),
                sign: .equals, style: .total),
        ]
    }

    /// What the advances leave of a levy, as the row of what is left says it: "71 440 Kč", or an overpayment as such,
    /// "přeplatek 46 000 Kč". With a tax bonus, a negative tax, the tax office returns the advances and the bonus,
    /// which "vrátí se".
    static func leftValue(_ balance: AuthorityBalance) -> String {
        if balance.overpayment > 0 {
            return (balance.liability < 0 ? "vrátí se " : "přeplatek ") + CzechFormat.wholeKc(balance.overpayment)
        }
        return CzechFormat.wholeKc(balance.remaining)
    }

    /// What the amount left says besides itself. For a year as of a day: how much of it the planned advances pay and
    /// how much is paid after the return or the overview. For an overpayment: how it comes back. Nothing for a year
    /// that is over with something to pay, or when there is nothing left and nothing planned.
    private static func leftNote(_ balance: AuthorityBalance, _ facts: Facts) -> String? {
        let isTax = balance.authority == .tax
        if balance.overpayment > 0 {
            return isTax ? "vrací se po podání přiznání, na žádost" : "vrací se po přehledu"
        }
        guard !facts.isOver, balance.remaining > 0 || balance.plannedAfterAsOf > 0 else { return nil }
        var leaves = "odejde plánovanými zálohami \(CzechFormat.grouped(balance.leavesViaPlannedAdvances))"
        if balance.plannedAfterAsOf > balance.leavesViaPlannedAdvances {
            leaves +=
                " z plánovaných \(CzechFormat.grouped(balance.plannedAfterAsOf))"
                + " (započte se nejvýše to, co zbývá)"
        }
        return leaves + " · doplatek po \(isTax ? "přiznání" : "přehledu") \(CzechFormat.grouped(balance.settlement))"
    }

    /// "1 ze 2 · v měsíci, ke kterému patří": how many of the advances in the plan are paid by the end of the month
    /// `throughMonth`. An advance counts in its own month.
    private static func advancesNote(_ plan: [Int64], throughMonth: Int) -> String {
        let planned = plan.filter { $0 != 0 }.count
        guard planned > 0 else { return "žádné zálohy v plánu" }
        let paid = plan.prefix(throughMonth).filter { $0 != 0 }.count
        return "\(paid) \(preposition(before: planned)) \(planned) · v měsíci, ke kterému patří"
    }

    /// "ze" before the number of the advances where Czech says it (ze dvou, tří, čtyř, šesti, sedmi, dvanácti), "z"
    /// everywhere else (z jednoho, pěti, osmi, devíti, deseti, jedenácti).
    private static func preposition(before count: Int) -> String {
        [2, 3, 4, 6, 7, 12].contains(count) ? "ze" : "z"
    }

    private static func plan(of authority: Authority, _ advances: AdvancePlan) -> [Int64] {
        switch authority {
        case .tax: advances.tax
        case .social: advances.social
        case .health: advances.health
        }
    }
}

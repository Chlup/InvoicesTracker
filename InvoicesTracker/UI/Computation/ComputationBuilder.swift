import Foundation

// MARK: - Builder

/// Turns the result of the tax engine for a year into the page of Výpočet, so that each number of the tax return and of
/// the overviews can be checked: the five cards of the breakdown (here, in `+Tax`, `+Social`, `+Authorities` and
/// `+NetIncome`), and the result, the cards under it and the note in `+Cards`. Nothing of the levies is worked out
/// again: every figure comes from the result. What the result does not hold as a number is derived from it for the rows
/// and notes alone (the shares and bases of the rows of a year with both main and secondary activity, the day the cap
/// of the expenses was reached), and the tests check that these add up to what the engine worked out.
///
/// A card is one calculation from the top down: each row has the sign of what it does to the rows above, a subtracted
/// value carries its minus, and an amount has no currency except the amount left to pay and the average per month of
/// the net income. What a rounding, a minimum or a cap did to a value is in the notes; the values that are steps of
/// their own (the income to the haléř, the computed base, the two bands of the tax, the rows of the overview of the
/// social security administration) are rows of their own.
nonisolated enum ComputationBuilder {
    // MARK: Texts

    /// The first two conventions of the app: how the income and the expenses are rounded to whole crowns. The law and
    /// the instructions of the tax office only require whole crowns.
    static let roundingConvention =
        "zaokrouhlení příjmů na celé Kč a výdajů dolů je konvence aplikace – zákon směr nepředepisuje"

    /// The note of the income rounded to whole crowns, in Výpočet and in Nastavení › Rok, which names the conventions
    /// in the words of Výpočet.
    static let incomeRoundingNote = "od poloviny nahoru · " + roundingConvention

    /// The third: the months after the day shown count as months without secondary activity in the reduced decisive
    /// amount of the social insurance.
    static let notReachedMonthsConvention =
        "měsíce po zvoleném dni se u snížené rozhodné částky počítají jako měsíce bez vedlejší činnosti"
        + " – konvence aplikace, zákon to neřeší"

    /// "pravidla 2026 · ověřeno 20. 10. 2026": the rules a year is computed with, and when they were checked.
    static func rulesVersion(of rules: TaxRules) -> String {
        "pravidla \(rules.year) · \(rules.verification)"
    }

    static let roundedUp = "zaokrouhleno na celé koruny nahoru"
    static let annualMaximum = "roční strop, nekrátí se"

    /// The note of the share of the profit when the secondary activity is not insured, in Výpočet and in Simulátor.
    static let secondaryNotInsured = "vedlejší činnost není pojištěná"

    // MARK: Cards

    /// The cards of the breakdown for `result`, the computation of `input` as of the day in it. `today` tells a year
    /// that is over from one in progress, `incomeFXMethod` how the year converts the income in other currencies, and
    /// `uniformSource` where its uniform rate is from (`BuilderText.uniformSource(of:)`), when it is known.
    static func build(
        _ result: TaxResult, input: YearInput, today: CivilDate, incomeFXMethod: IncomeFXMethod,
        uniformSource: String? = nil
    ) -> [ComputationSection] {
        sections(
            makeFacts(
                result, input: input, today: today, incomeFXMethod: incomeFXMethod, uniformSource: uniformSource))
    }

    /// The cards of the breakdown in the order they are built: the income, the tax, the social insurance, the health
    /// insurance and the net income, which the screen sets in two columns (`ComputationSection.standsRight`).
    static func sections(_ facts: Facts) -> [ComputationSection] {
        [
            incomeSection(facts), taxSection(facts), socialSection(facts), healthSection(facts),
            netIncomeSection(facts.result, wording: netIncomeWording(of: facts.result)),
        ]
    }

    /// How Výpočet words the card of the net income of `result`: the income as the first card of the breakdown calls
    /// it, and at the right of the title the year of a whole year ("za rok 2025") or otherwise the day the card is of
    /// ("do 17. 10."). The months so far are named under their number.
    private static func netIncomeWording(of result: TaxResult) -> NetIncomeWording {
        let net = NetIncome(result)
        let day = BuilderText.date(result.asOf, omittingYear: result.year)
        return NetIncomeWording(
            incomeLabel: "Příjmy z podnikání (§ 7)", resultLabel: "Čistý příjem",
            tag: net.isWholeYear ? "za rok \(result.year)" : "do " + day, divisorNote: BuilderText.months(of: net),
            incomeWord: "příjmů")
    }

    static func makeFacts(
        _ result: TaxResult, input: YearInput, today: CivilDate, incomeFXMethod: IncomeFXMethod,
        uniformSource: String? = nil
    ) -> Facts {
        Facts(
            result: result, input: input, isOver: AsOfState.isFinishedYear(asOf: result.asOf, today: today),
            incomeFXMethod: incomeFXMethod, uniformSource: uniformSource)
    }

    /// What every card is made from.
    nonisolated struct Facts {
        var result: TaxResult
        var input: YearInput

        /// Whether the year is over and shown as of its last day, so that its levies are a final bill. Any other day of
        /// a year, a past one too, is a state of the year as of that day, with the later advances still to come.
        var isOver: Bool

        /// The method the year converts its income in other currencies with, and where its uniform rate is from.
        var incomeFXMethod: IncomeFXMethod
        var uniformSource: String?

        /// Whether the cap of the flat-rate expenses is reached: the expenses at the percentage are the cap or more.
        /// The note of the expenses, the note of the profit and the bar of the thresholds all go by it.
        var capIsReached: Bool {
            result.uncappedExpenses >= result.expenseCap
        }
    }

    // MARK: Income, expenses and profit

    private static func incomeSection(_ facts: Facts) -> ComputationSection {
        let result = facts.result
        // What was paid in: the payments with their VAT, without the adjustments.
        let received = result.incomeHalere - result.adjustmentsHalere + result.vatHalere
        let conversion = facts.incomeFXMethod == .uniform ? "jednotným kurzem \(result.year)" : "ke dni přijetí"
        let period = "1.\u{00A0}1. – " + CzechFormat.dayMonth(result.asOf)
        var rows = [
            ComputationRow(
                label: "Přijaté platby", value: CzechFormat.amount(received),
                note: period + " · cizí měny v Kč \(conversion)"),
            ComputationRow(
                label: "DPH z přijatých plateb", value: CzechFormat.amount(-result.vatHalere),
                note: "vede se zvlášť, do příjmů nepatří", sign: .minus),
        ]
        if result.adjustmentsHalere != 0 {
            rows.append(
                ComputationRow(
                    label: "Úpravy příjmů", value: CzechFormat.amount(result.adjustmentsHalere),
                    note: "Nastavení › Rok · dobropisy, vratky a platby mimo faktury", sign: .plus))
        }
        rows.append(
            ComputationRow(label: "Příjmy bez DPH", value: CzechFormat.amount(result.incomeHalere), sign: .equals))
        rows.append(
            ComputationRow(
                label: "Příjmy z podnikání (§ 7)", value: crowns(result.P),
                note: incomeRoundingNote, sign: .equals, style: .strong))
        rows += expenseRows(facts)
        return ComputationSection(title: "Příjmy a zisk", rows: rows, tag: payments(result.receiptCount))
    }

    /// The flat-rate expenses and the profit they leave. The note of the expenses says whether the cap cut them, and
    /// the note of the profit that the cap is used up, so that the next crown of income is all profit.
    private static func expenseRows(_ facts: Facts) -> [ComputationRow] {
        let result = facts.result
        let rate = percent(Decimal(result.expensePercent) / 100, fractionDigits: 0)
        let cap = CzechFormat.grouped(result.expenseCap)
        let note: String
        if result.uncappedExpenses > result.expenseCap {
            note = "\(rate) je \(crowns(result.uncappedExpenses)) → použije se strop \(cap)"
        } else if facts.capIsReached {
            note = "\(rate) je přesně strop \(cap)"
        } else {
            note = "\(rate) z příjmů, zaokrouhleno dolů · strop \(cap) \(facts.isOver ? "" : "zatím ")nedosažen"
        }
        return [
            ComputationRow(label: "Výdajový paušál \(rate)", value: crowns(-result.V), note: note, sign: .minus),
            ComputationRow(
                label: "Zisk (dílčí základ daně)", value: crowns(result.DZ),
                note: facts.capIsReached ? "strop paušálu je vyčerpaný – další příjem je celý ziskem" : nil,
                sign: .equals, style: .strong),
        ]
    }

    // MARK: Texts of numbers

    /// A whole number of crowns written as an amount with haléře: `1 200 000,00`.
    static func crowns(_ kc: Int64) -> String {
        CzechFormat.amount(kc * 100)
    }

    /// An amount in haléře that is written as whole crowns when it has no haléře: `125 280`, but `264 421,80`.
    static func wholeOrHalere(_ halere: Int64) -> String {
        halere % 100 == 0 ? CzechFormat.grouped(halere / 100) : CzechFormat.amount(halere)
    }

    /// A share as a percentage: "15 %", "29,2 %".
    static func percent(_ share: Decimal, fractionDigits: Int) -> String {
        CzechFormat.percent(share, fractionDigits: fractionDigits)
    }

    private static func payments(_ count: Int) -> String {
        counted(count, "platba", "platby", "plateb")
    }

    static func months(_ count: Int) -> String {
        counted(count, "měsíc", "měsíce", "měsíců")
    }

    /// `count` with the noun in the form Czech wants and a no-break space between them: "1 měsíc", "2 měsíce",
    /// "5 měsíců".
    static func counted(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let noun =
            switch count {
            case 1: one
            case 2...4: few
            default: many
            }
        return "\(count)\u{00A0}\(noun)"
    }

    /// The name of an authority in a column or a tile, its short name (`Authority.shortTitle`): "Daň", "Sociální",
    /// "Zdravotní".
    static func shortName(of authority: Authority) -> String {
        authority.shortTitle
    }
}

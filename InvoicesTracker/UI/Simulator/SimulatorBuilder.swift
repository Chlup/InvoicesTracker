import Foundation

// MARK: - The choices

/// The activity a simulation assumes for its months.
nonisolated enum SimulatorActivity: String, CaseIterable, Sendable, Hashable {
    case main
    case secondary
}

/// What is chosen on the Simulátor screen: the year, the expected income, the flat-rate expenses, the activity with its
/// months and whether a secondary one is exempt from the health minimum, the deductions, the taxpayer credit and the
/// family.
nonisolated struct SimulatorInput: Sendable, Hashable {
    var year: Int

    /// The expected income of the year without VAT, in whole Kč.
    var incomeKc: Int64

    /// The flat-rate expense percentage: 80, 60, 40 or 30.
    var expensePercent: Int
    var activity: SimulatorActivity

    /// Whether the person says that for the whole of the months of a secondary activity they are also employed with
    /// insurance from at least the minimum wage, study, receive a pension, are on parental leave, have a ZTP/P card or
    /// the like, so that these months have no health minimum. It counts for a secondary activity only
    /// (`isExemptFromHealthMinimum`).
    var healthMinimumExempt: Bool

    /// The months of the activity, counted from January: 1 to 12.
    var months: Int
    var deductions: Deductions
    var taxpayerCredit: Bool

    /// The children, each with what the year says about it, listed as `Database.family(year:)` lists them, and the
    /// spouse: the family of the simulation, of whichever year is simulated.
    var family: FamilyYear

    /// Whether the months of the activity have no health minimum: those of a secondary activity whose
    /// `healthMinimumExempt` is on. A secondary activity alone grants no exemption, and a main activity has the minimum
    /// whatever `healthMinimumExempt` says.
    var isExemptFromHealthMinimum: Bool {
        activity == .secondary && healthMinimumExempt
    }
}

// MARK: - The page

/// A line of the result card: a levy with its amount, and, where something applies to it, a note.
nonisolated struct SimulatorLevyLine: Identifiable, Sendable, Hashable {
    var authority: Authority
    var label: String

    /// In whole Kč: "164 160 Kč".
    var amount: String
    var note: String?

    var id: Authority {
        authority
    }
}

/// What the income leaves after the levies ("čistý příjem"), as the line under the divider of the result card shows it:
/// its average per month with the words for it, and under them the sum of the whole year. Both figures are texts in
/// whole Kč, and both are negative where the levies are more than the income, which the minimum of the insurance makes
/// possible.
nonisolated struct SimulatorNetIncome: Sendable, Hashable {
    /// The words of the line: "Čistý příjem průměrně za měsíc".
    var label: String

    /// The average per month: "169 943 Kč", or "−8 310 Kč" where the levies are more than the income.
    var amount: String

    /// The sum of the whole year that the amount is the average of, and the reminder that the actual expenses of the
    /// business are not taken off: "za rok 2 039 310 Kč · skutečné výdaje podnikání tu odečtené nejsou". The sum is
    /// negative, "za rok −99 720 Kč", where the levies are more than the income.
    var sub: String

    /// Whether the levies are more than the income, that is, whether the sum of the year is below zero. The amount is
    /// below zero then too, except for a sum less than 6 Kč below it, whose average per month rounds to 0 Kč. The view
    /// shows the amount in the orange of a warning.
    var isNegative: Bool
}

/// The result card: the three levies together, what they come to a month and of the income, the bar of their parts, a
/// line for each, and what the income leaves after them.
nonisolated struct SimulatorSummary: Sendable, Hashable {
    /// "Zaplatíte za rok 2026".
    var heading: String

    /// The three levies together in whole Kč, the tax less a tax bonus: "460 690 Kč".
    var total: String

    /// "≈ 38 391 Kč měsíčně · 18,4 % z příjmu", or "Zadejte příjem" while there is no income.
    var subline: String

    /// The parts of the bar: tax, social, health, of what is paid to each, so a tax bonus is no part of it. All of them
    /// are 0 when there is nothing to pay. It is for drawing only; the money is in the lines.
    var shares: [MarginalShare]
    var lines: [SimulatorLevyLine]

    /// What the income leaves after the three levies, as an average per month and as the sum of the whole year.
    var netIncome: SimulatorNetIncome
}

/// Everything the Simulátor shows for one simulation besides its inputs.
nonisolated struct SimulatorPage: Sendable, Hashable {
    var summary: SimulatorSummary
    var marginal: ComputationMarginal

    /// "Rozpis výpočtu": the cards of the tax, the social insurance and the health insurance, and the card of the net
    /// income that these levies leave.
    var sections: [ComputationSection]

    /// The sentences under the fields of the deductions.
    var hints: DeductionHints

    /// What the flat-rate expenses come to and where their cap is, then, while the percentage comes from the settings
    /// of the year, that it does, and last, for the percentage of 30, that ordinary rent is not counted.
    var expenseNote: String

    /// "≈ 208 333 Kč měsíčně". Nil while there is no income.
    var incomePerMonth: String?

    /// The cards of the children and of the spouse, without what the tax return asks for.
    var family: FamilyCardsContent
}

// MARK: - Builder

/// Turns the choices of a simulation into the input of the tax engine, and what the engine works out for it into the
/// page of the Simulátor. Nothing of the levies is worked out here: every figure comes from the result. What the result
/// does not hold as a number (the tax of each band) is derived from it for the rows alone, the way the breakdown of
/// Výpočet does it, and the rows write the same quantities as Výpočet does: with the same helpers for the amounts and
/// the same words for what a cap, a rounding or a minimum did. The steps of the family are the rows of Výpočet, and
/// its cards those of Zálohy a odpočty. The card of the net income is that of Výpočet, in the Simulátor's own words.
nonisolated enum SimulatorBuilder {
    private static let taxName = "Daň z příjmů"
    private static let socialName = "Sociální pojištění"
    private static let healthName = "Zdravotní pojištění"
    private static let minimumName = "Minimální vyměřovací základ"
    private static let payingMinimum = "platíte minimum"
    private static let exemptFromMinimum =
        "minimum neplatíte – po celé měsíce zaměstnání, studium, důchod, rodičovská, ZTP/P a podobně"

    // MARK: Input

    /// The year of `choices` as the engine takes it: the income as one payment on the last day of the year, so that all
    /// of it counts, and the activity in the months from January. A secondary activity pays the health minimum like a
    /// main one, unless `healthMinimumExempt` says that for the whole of those months the person is also employed with
    /// insurance from at least the minimum wage, studies, receives a pension, is on parental leave, has a ZTP/P card or
    /// the like; then none of its months has that minimum. A main activity has it whatever `healthMinimumExempt` says.
    /// The family is taken whole, its children in their order, as for a stored year (`AppModel.yearInput`).
    static func input(_ choices: SimulatorInput) -> YearInput {
        let activeMonths = (1...12).filter { $0 <= choices.months }
        let activity = choices.activity == .secondary ? MonthActivity.secondary : MonthActivity.main
        let income = Receipt(
            day: lastDay(of: choices.year), czkNetHalere: choices.incomeKc * 100, czkVatHalere: 0, source: .synthetic)
        return YearInput(
            year: choices.year, receipts: [income], expensePercent: choices.expensePercent,
            months: (1...12).map { activeMonths.contains($0) ? activity : .inactive },
            healthExemptMonths: choices.isExemptFromHealthMinimum ? Set(activeMonths) : [],
            deductions: choices.deductions, taxpayerCredit: choices.taxpayerCredit, advances: .empty,
            family: FamilyFacts(choices.family))
    }

    // MARK: Page

    /// The page for `result`, which the engine worked out for `choices`. `rateFromSettings` says whether the expense
    /// percentage still comes from the settings of the year.
    static func page(_ result: TaxResult, choices: SimulatorInput, rateFromSettings: Bool) -> SimulatorPage {
        SimulatorPage(
            summary: summary(result, income: choices.incomeKc),
            marginal: ComputationBuilder.marginal(of: result),
            sections: [
                taxSection(result, choices), socialSection(result, choices), healthSection(result, choices),
                netIncomeSection(result),
            ],
            hints: DeductionHints.make(from: result.deductionLines, deductions: choices.deductions),
            expenseNote: expenseNote(result, rateFromSettings: rateFromSettings),
            incomePerMonth: choices.incomeKc > 0 ? perMonth(choices.incomeKc) : nil,
            family: FamilyCardsBuilder.content(
                family: choices.family, result: result, mode: .simulation, isWholeYear: true))
    }

    /// The rules `year` is computed with, and when they were checked: "Pravidla 2026 · 23 % nad 1 762 812 Kč ·
    /// minimální základ 17 139 Kč měsíčně · ověřeno 20. 10. 2026".
    static func rulesLine(year: Int) -> String {
        let rules = TaxRules.forYear(year).rules
        let threshold = CzechFormat.wholeKc(rules.taxBandThreshold)
        let minimum = CzechFormat.wholeKc(rules.socialMinimumMonthlyMain)
        return
            "Pravidla \(rules.year) · \(CzechFormat.percent(TaxRules.taxRateHigh, fractionDigits: 0)) nad \(threshold)"
            + " · minimální základ \(minimum) měsíčně · \(rules.verification)"
    }

    // MARK: Result card

    /// What the year costs counts the tax less a tax bonus, which the tax office pays, so a bonus lowers it. The bar is
    /// of what is paid to each authority: a bonus is no part of it.
    private static func summary(_ result: TaxResult, income: Int64) -> SimulatorSummary {
        let total = result.netTax + result.social.insurance + result.health.insurance
        let paid = [result.tax, result.social.insurance, result.health.insurance]
        let paidTotal = paid.reduce(0, +)
        let subline: String
        if income > 0 {
            let share = CzechFormat.percent(Decimal(total) / Decimal(income), fractionDigits: 1)
            subline = perMonth(total) + " · " + share + " z příjmu"
        } else {
            subline = "Zadejte příjem"
        }
        let shares = zip(Authority.allCases, paid).map { authority, levy in
            MarginalShare(authority: authority, fraction: paidTotal > 0 ? Double(levy) / Double(paidTotal) : 0)
        }
        return SimulatorSummary(
            heading: "Zaplatíte za rok \(result.year)", total: CzechFormat.wholeKc(total), subline: subline,
            shares: shares, lines: levyLines(result), netIncome: netIncome(result))
    }

    /// The net income of the year: the income less the three levies, as an average per month, with the sum of the year
    /// under it. The Simulátor computes the whole year, as of its last day, so the average is over twelve months. Both
    /// come from `NetIncome`, as on Výpočet, and are negative where the levies are more than the income.
    private static func netIncome(_ result: TaxResult) -> SimulatorNetIncome {
        let net = NetIncome(result)
        return SimulatorNetIncome(
            label: "Čistý příjem průměrně za měsíc", amount: CzechFormat.wholeKc(net.monthlyKc),
            sub: "za rok " + CzechFormat.wholeKc(net.yearKc) + " · " + BuilderText.expensesNotSubtracted,
            isNegative: net.yearKc < 0)
    }

    /// The three levies, each with the note that applies to it: a minimum that is paid, the maximum base that is
    /// reached, or a secondary activity that pays no social insurance. A negative tax, a tax bonus, reads as the bonus.
    private static func levyLines(_ result: TaxResult) -> [SimulatorLevyLine] {
        let social = result.social
        let health = result.health
        let socialNote: String?
        if social.secondaryInsured == false {
            socialNote = "vedlejší činnost pod rozhodnou částkou – neplatí se"
        } else if social.computedBase >= social.maximumBase {
            socialNote = "dosažen maximální vyměřovací základ"
        } else if social.computedBase < social.minimumBase {
            socialNote = payingMinimum
        } else {
            socialNote = nil
        }
        return [
            SimulatorLevyLine(
                authority: .tax, label: taxName, amount: BuilderText.taxOrBonus(result.netTax)),
            SimulatorLevyLine(
                authority: .social, label: socialName, amount: CzechFormat.wholeKc(social.insurance),
                note: socialNote),
            SimulatorLevyLine(
                authority: .health, label: healthName, amount: CzechFormat.wholeKc(health.insurance),
                note: health.computedBaseHalere < health.minimumBaseHalere ? payingMinimum : nil),
        ]
    }

    /// "≈ 38 391 Kč měsíčně": a twelfth of `kc`, rounded half up.
    private static func perMonth(_ kc: Int64) -> String {
        "≈ " + CzechFormat.wholeKc(DecimalMath.halfUp(Decimal(kc) / 12)) + " měsíčně"
    }

    /// "Paušál je na stropu 1 200 000 Kč." or "Paušál 600 000 Kč, strop 1 200 000 Kč.", then, while the percentage
    /// comes from the settings of the year, the sentence that says so, and last, for the percentage of 30, the sentence
    /// that ordinary rent is not counted (`ExpenseRateChoice.note(forPercent:)`). The expenses are on the cap once the
    /// percentage of the income reaches it, also exactly, which `expensesCapped` (over it) does not say.
    private static func expenseNote(_ result: TaxResult, rateFromSettings: Bool) -> String {
        let cap = CzechFormat.wholeKc(result.expenseCap)
        var note =
            result.uncappedExpenses >= result.expenseCap
            ? "Paušál je na stropu \(cap)." : "Paušál \(CzechFormat.wholeKc(result.V)), strop \(cap)."
        if rateFromSettings {
            note += " Předvyplněno podle Nastavení roku \(result.year)."
        }
        if let rent = ExpenseRateChoice.note(forPercent: result.expensePercent) {
            note += " " + rent
        }
        return note
    }

    // MARK: Tax

    /// The card of the tax: from the income through the deductions and the bands to the credits, then the steps of the
    /// family as Výpočet has them, to the tax less a tax bonus, negative when a bonus is paid.
    private static func taxSection(_ result: TaxResult, _ choices: SimulatorInput) -> ComputationSection {
        let rate = CzechFormat.percent(Decimal(result.expensePercent) / 100, fractionDigits: 0)
        var rows = [
            ComputationRow(label: "Příjmy", value: ComputationBuilder.crowns(result.P)),
            ComputationRow(
                label: "Výdaje paušálem \(rate)", value: ComputationBuilder.crowns(-result.V),
                note: capNote(result, rate: rate), sign: .minus),
            ComputationRow(label: "Zisk", value: ComputationBuilder.crowns(result.DZ), sign: .equals, style: .strong),
            ComputationRow(
                label: "Odpočty", value: ComputationBuilder.crowns(-result.deductionsTotal),
                note: deductionsNote(result), sign: .minus),
            ComputationRow(
                label: "Základ daně", value: CzechFormat.grouped(result.B), note: "zaokrouhlený dolů na stovky",
                sign: .equals, style: .strong),
        ]
        let (lowPart, highPart) = bandParts(result)
        let threshold = CzechFormat.grouped(result.rules.taxBandThreshold)
        rows.append(
            ComputationRow(
                label: "Daň " + CzechFormat.percent(TaxRules.taxRateLow, fractionDigits: 0),
                value: ComputationBuilder.wholeOrHalere(lowPart),
                note: "z \(CzechFormat.grouped(result.taxBaseInLowBand)) základu (pásmo do \(threshold))"))
        if result.taxBaseInHighBand > 0 {
            rows.append(
                ComputationRow(
                    label: "Daň " + CzechFormat.percent(TaxRules.taxRateHigh, fractionDigits: 0),
                    value: ComputationBuilder.wholeOrHalere(highPart),
                    note: "z \(CzechFormat.grouped(result.taxBaseInHighBand)) základu (pásmo nad \(threshold))",
                    sign: .plus))
        }
        // The two parts are in haléře and the tax before the credit is their sum rounded up to whole crowns.
        let roundingNote =
            lowPart + highPart == result.taxBeforeCredit * 100
            ? nil : "daň před slevou \(CzechFormat.grouped(result.taxBeforeCredit)), \(ComputationBuilder.roundedUp)"
        rows.append(creditRow(result, claimed: choices.taxpayerCredit))
        rows += ComputationBuilder.familyRows(result)
        let notes = [roundingNote, result.netTax < 0 ? ComputationBuilder.bonusNote : nil].compactMap { $0 }
        rows.append(totalRow(taxName, result.netTax, note: notes.isEmpty ? nil : notes.joined(separator: " · ")))
        return ComputationSection(title: taxName, rows: rows, authority: .tax)
    }

    /// The tax of the part of the base in each band, in haléře. The rates are whole percents, so each part is a whole
    /// number of haléře.
    private static func bandParts(_ result: TaxResult) -> (low: Int64, high: Int64) {
        (
            DecimalMath.halfUp(TaxRules.taxRateLow * Decimal(result.taxBaseInLowBand) * 100),
            DecimalMath.halfUp(TaxRules.taxRateHigh * Decimal(result.taxBaseInHighBand) * 100)
        )
    }

    /// What the cap of the flat-rate expenses did to them: it cut them, they are exactly the cap, or they are below it.
    private static func capNote(_ result: TaxResult, rate: String) -> String {
        let cap = CzechFormat.grouped(result.expenseCap)
        if result.uncappedExpenses > result.expenseCap {
            return "\(rate) je \(ComputationBuilder.crowns(result.uncappedExpenses)) → použije se strop \(cap)"
        }
        if result.uncappedExpenses == result.expenseCap {
            return "\(rate) je přesně strop \(cap)"
        }
        return "\(rate) z příjmů, zaokrouhleno dolů · strop \(cap) nedosažen"
    }

    /// What the deductions are made of. When together they are more than the profit, they are held to it, and the note
    /// says so.
    private static func deductionsNote(_ result: TaxResult) -> String {
        let note = "úroky · spoření · dary"
        let allowed = result.deductionLines.reduce(0) { $0 + $1.allowed }
        return result.deductionsTotal < allowed ? note + " – celkem nejvýše do výše zisku" : note
    }

    private static func creditRow(_ result: TaxResult, claimed: Bool) -> ComputationRow {
        let credit = result.rules.taxpayerCredit
        let note: String
        if !claimed {
            note = "neuplatňuje se"
        } else if result.creditApplied < credit {
            note = "roční sleva \(CzechFormat.grouped(credit)) se uplatní nejvýše do výše daně"
        } else {
            note = "celá roční částka"
        }
        return ComputationRow(
            label: "Sleva na poplatníka", value: CzechFormat.grouped(-result.creditApplied), note: note, sign: .minus)
    }

    // MARK: Insurance

    private static func socialSection(_ result: TaxResult, _ choices: SimulatorInput) -> ComputationSection {
        let social = result.social
        let rules = result.rules
        let isSecondary = choices.activity == .secondary
        let isInsured = !isSecondary || social.secondaryInsured == true
        let monthlyMinimum = isSecondary ? rules.socialMinimumMonthlySecondary : rules.socialMinimumMonthlyMain
        let countedMonths = isSecondary ? social.secondaryMonths : social.mainMonths
        let baseNote: String
        if isInsured {
            baseNote =
                "vyšší z obou · max. \(CzechFormat.grouped(social.maximumBase)) (\(ComputationBuilder.annualMaximum))"
        } else {
            baseNote =
                "zisk \(CzechFormat.grouped(max(0, result.DZ))) nedosáhl snížené rozhodné částky"
                + " \(CzechFormat.grouped(social.reducedDecisiveAmount ?? 0)) – nic se nevyměřuje"
        }
        return ComputationSection(
            title: socialName,
            rows: [
                ComputationRow(label: "Zisk", value: ComputationBuilder.crowns(result.DZ)),
                ComputationRow(
                    label: CzechFormat.percent(rules.socialAssessmentPercent, fractionDigits: 0) + " zisku",
                    value: CzechFormat.grouped(social.computedBase),
                    note: isInsured ? "zaokrouhleno nahoru" : ComputationBuilder.secondaryNotInsured, sign: .times),
                ComputationRow(
                    label: minimumName, value: CzechFormat.grouped(social.minimumBase),
                    note: isInsured
                        ? "\(CzechFormat.grouped(monthlyMinimum)) × \(ComputationBuilder.months(countedMonths))" : nil),
                ComputationRow(
                    label: "Vyměřovací základ", value: CzechFormat.grouped(social.base), note: baseNote, sign: .equals,
                    style: .strong),
                ComputationRow(
                    label: CzechFormat.percent(TaxRules.socialRate, fractionDigits: 1),
                    value: CzechFormat.grouped(social.insurance), note: ComputationBuilder.roundedUp, sign: .times),
                totalRow(socialName, social.insurance),
            ], authority: .social)
    }

    /// The bases are in haléře because the minimum can be a half crown; they are not rounded.
    private static func healthSection(_ result: TaxResult, _ choices: SimulatorInput) -> ComputationSection {
        let health = result.health
        let monthlyMinimum = CzechFormat.amount(DecimalMath.halfUp(result.rules.healthMinimumMonthlyBase * 100))
        return ComputationSection(
            title: healthName,
            rows: [
                ComputationRow(label: "Zisk", value: ComputationBuilder.crowns(result.DZ)),
                ComputationRow(
                    label: CzechFormat.percent(TaxRules.healthAssessmentPercent, fractionDigits: 0) + " zisku",
                    value: CzechFormat.amount(health.computedBaseHalere), sign: .times),
                ComputationRow(
                    label: minimumName, value: CzechFormat.amount(health.minimumBaseHalere),
                    note: choices.isExemptFromHealthMinimum
                        ? exemptFromMinimum
                        : "\(monthlyMinimum) × \(ComputationBuilder.months(health.minimumMonths))"),
                ComputationRow(
                    label: "Vyměřovací základ", value: CzechFormat.amount(health.baseHalere),
                    note: "vyšší z obou · bez maxima, nezaokrouhluje se", sign: .equals, style: .strong),
                ComputationRow(
                    label: CzechFormat.percent(TaxRules.healthRate, fractionDigits: 1),
                    value: CzechFormat.grouped(health.insurance), note: ComputationBuilder.roundedUp, sign: .times),
                totalRow(healthName, health.insurance),
            ], authority: .health)
    }

    // MARK: Net income

    /// The card of the net income, the one Výpočet shows (`ComputationBuilder.netIncomeSection`), worded for the
    /// Simulátor: the income is "Příjmy", as on the card of the tax, the result is the net income "za rok", and its
    /// share of the income is written with "příjmu", in the singular, as the result card writes it. The title has no
    /// tag at its right, and the row of the twelve months has no note.
    private static func netIncomeSection(_ result: TaxResult) -> ComputationSection {
        let wording = ComputationBuilder.NetIncomeWording(
            incomeLabel: "Příjmy", resultLabel: "Čistý příjem za rok", tag: nil, divisorNote: nil,
            incomeWord: "příjmu")
        return ComputationBuilder.netIncomeSection(result, wording: wording)
    }

    /// The row that ends a card: the levy, as the amount to pay.
    private static func totalRow(_ label: String, _ levy: Int64, note: String? = nil) -> ComputationRow {
        ComputationRow(label: label, value: CzechFormat.wholeKc(levy), note: note, sign: .equals, style: .total)
    }

    private static func lastDay(of year: Int) -> CivilDate {
        guard let day = CivilDate(year: year, month: 12, day: 31) else {
            preconditionFailure("31 December \(year) is not a date in the years 1 to 9999.")
        }
        return day
    }
}

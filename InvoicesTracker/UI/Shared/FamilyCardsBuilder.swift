import Foundation

/// Where the cards of the family are shown: in Zálohy a odpočty, where the family is stored, or in the Simulátor, where
/// it lives only in the simulation. The Simulátor leaves out what the tax return asks for, such as the proof of the
/// other parent.
nonisolated enum FamilyCardsMode: Sendable, Hashable {
    case stored
    case simulation
}

/// What the cards "Děti · daňové zvýhodnění" and "Manžel / manželka · sleva na dani" say about the family of a year.
nonisolated struct FamilyCardsContent: Sendable, Hashable {
    var children: ChildrenCardContent
    var spouse: SpouseCardContent
}

/// The card of the children.
nonisolated struct ChildrenCardContent: Sendable, Hashable {
    /// Beside the title: what the children bring me for the year, "37 524 Kč za rok", while a child of mine counts.
    var total: String?

    /// Under the title: for which months the benefit is, and the rates of the year.
    var rates: String

    /// A row for each child of the year, in the order of the family.
    var rows: [ChildCardRow]

    /// In Zálohy a odpočty, while a child of mine counts: what to agree with the other parent and what to attach to the
    /// return.
    var proofHint: String?

    /// While the benefit is more than the tax: what it leaves after its credit, and whether that is paid as a bonus.
    var bonusHint: String?

    /// Beside Přidat dítě in the Simulátor: that nothing of the simulation is stored (`simulationNote`). Nil in Zálohy
    /// a odpočty, which stores the family.
    var addNote: String?

    /// What the card says while the year has no child.
    static let noChildren = "Zatím žádné dítě. Přidejte děti, které s vámi žijí ve společné domácnosti."

    /// "Jen pro simulaci – nic se neukládá.": what the card of the Simulátor says beside Přidat dítě.
    static let simulationNote = "Jen pro simulaci – nic se neukládá."

    /// The box under the rows: the hints together, or nil when there is none.
    var hint: String? {
        let hints = [proofHint, bonusHint].compactMap { $0 }
        return hints.isEmpty ? nil : hints.joined(separator: " ")
    }
}

/// The row of a child: a button that opens the dialog of the child.
nonisolated struct ChildCardRow: Sendable, Hashable {
    /// The child with what the year says about it, which the dialog opens on.
    var member: FamilyChild

    /// The name of the child, "Dítě" for one without a name.
    var name: String

    /// "nar. 3. 9. 2019".
    var birth: String

    /// The rates and the months of the child, "1. dítě · 12 měsíců", "uplatňuje druhý rodič · 12 měsíců", or why it
    /// counts in no month of the year.
    var status: String

    /// Whether the child counts in no month of the year, so that `status` says why.
    var countsInNoMonth: Bool

    /// What the child brings me for the year, "15 204 Kč", or "—" when nothing.
    var amount: String

    /// Whether `amount` is something the child brings me, not "—".
    var hasAmount: Bool

    /// "Anna · nar. 3. 9. 2019": the first line of the row.
    var heading: String {
        name + " · " + birth
    }

    /// What VoiceOver reads for the row: its lines and the amount.
    var spokenText: String {
        [heading, status, amount].joined(separator: ", ")
    }
}

/// The card of the spouse.
nonisolated struct SpouseCardContent: Sendable, Hashable {
    /// Beside the title: "24 840 Kč za rok" while the credit counts, "neuplatní se" while the spouse is claimed without
    /// it, and nil while the spouse is not claimed.
    var total: String?

    /// Whether `total` is a credit, not "neuplatní se".
    var totalCounts: Bool

    /// Under the claim: what the credit is, with its amounts of the year.
    var claimLine: String

    /// The title of the field of the spouse's own income, with the year.
    var incomeTitle: String

    /// For a claimed spouse: whether the income is within the limit, "do limitu 68 000 Kč", or over it.
    var incomeStatus: String?

    /// Whether the income is over the limit, so that `incomeStatus` is a warning.
    var incomeIsOverLimit: Bool

    /// For a claimed spouse, from 2024: the children under three who live in the household, or what the credit needs
    /// while there is none.
    var youngChild: YoungChildNote?

    /// For a claimed spouse: the months and the amount that result, or why nothing does.
    var result: String?

    /// Under the field of the income: what counts in it.
    static let incomeNote =
        "Hrubé příjmy za celý rok: mzda, podnikání, nájem, důchod, nemocenská, peněžitá pomoc v mateřství,"
        + " podpora v nezaměstnanosti. Nepočítá se rodičovský příspěvek, porodné, přídavek na dítě, stipendium ani"
        + " výživné."
}

/// The box of the spouse card about the children under three, from 2024.
nonisolated struct YoungChildNote: Sendable, Hashable {
    var text: String

    /// Whether a child under three lives in the household in a month of the year: the box is green, otherwise amber.
    var isMet: Bool
}

nonisolated enum FamilyCardsBuilder {
    /// The rates of the child benefit by the place of the child among those who count in a month: the first child, the
    /// second, and the third and every further one.
    static let rateNames = ["1. dítě", "2. dítě", "3. a další dítě"]

    /// The name of `rate`, 1 to 3, as `ChildCredit.monthsByRate` has it.
    static func rateName(_ rate: Int) -> String {
        rateNames[min(max(rate, 1), rateNames.count) - 1]
    }

    /// What the cards say about `family`, the family of a year, with the figures of `result`, the computation of the
    /// year with that family: its children in the same order, and its spouse. Every amount and every count of months is
    /// the engine's; the cards only put them into words. In the Simulátor (`mode`) the cards leave out what the tax
    /// return asks for. `isWholeYear` says whether `result` counts all the income of the year, which grows no more: a
    /// year that is over, shown as of its last day, and a simulation, which is always of a whole year. A bonus that
    /// such income does not bring is not paid, rather than not paid yet.
    static func content(
        family: FamilyYear, result: TaxResult, mode: FamilyCardsMode, isWholeYear: Bool
    ) -> FamilyCardsContent {
        // A screen that gives another family than the one it computed would show the rows without their figures.
        assert(
            family.children.count == result.family.children.count,
            "The result is the computation of the family: it has a credit for each of its children.")
        return FamilyCardsContent(
            children: children(of: family, result: result, mode: mode, isWholeYear: isWholeYear),
            spouse: spouse(of: family, result: result))
    }

    // MARK: The children

    private static func children(
        of family: FamilyYear, result: TaxResult, mode: FamilyCardsMode, isWholeYear: Bool
    ) -> ChildrenCardContent {
        let credits = result.family.children
        let rows = family.children.enumerated().map { index, member in
            row(of: member, credit: credits.indices.contains(index) ? credits[index] : nil, year: result.year)
        }
        let mine = credits.contains { !$0.claimedByOther && $0.amount > 0 }
        let theirs = credits.contains { $0.claimedByOther && !$0.monthsByRate.isEmpty }
        var proofHint: String?
        if mode == .stored && mine {
            proofHint =
                theirs
                ? "Pořadí dětí se s druhým rodičem dohodněte – sazbu 1. dítěte nemůžete uplatnit oba. K přiznání"
                    + " přiložte jeho prohlášení, že na vaše děti zvýhodnění neuplatňuje (u zaměstnance potvrzení"
                    + " zaměstnavatele)."
                : "Druhý rodič, který s vámi žije, na stejné dítě ve stejném měsíci zvýhodnění uplatnit nemůže."
                    + " K přiznání se přikládá potvrzení jeho zaměstnavatele, nebo prohlášení na volném listu."
        }
        return ChildrenCardContent(
            total: mine ? CzechFormat.wholeKc(result.family.childBenefit) + " za rok" : nil,
            rates: ratesLine(result.rules), rows: rows, proofHint: proofHint,
            bonusHint: bonusHint(result, isWholeYear: isWholeYear),
            addNote: mode == .simulation ? ChildrenCardContent.simulationNote : nil)
    }

    /// "Za každý měsíc, …": the rates of the year for a whole year, twelve times the monthly amounts of the rules.
    private static func ratesLine(_ rules: TaxRules) -> String {
        let yearly = rules.childMonthly.map { CzechFormat.wholeKc($0 * 12) }
        guard yearly.count == 3 else { return "" }
        return "Za každý měsíc, na jehož začátku s vámi dítě žilo a bylo vyživované, a za měsíc narození. Sazba podle"
            + " pořadí v domácnosti: 1. dítě \(yearly[0]), 2. dítě \(yearly[1]), 3. a další \(yearly[2]) za rok, se"
            + " ZTP/P dvojnásobek."
    }

    /// The row of `member`, with its figures in `credit`.
    private static func row(of member: FamilyChild, credit: ChildCredit?, year: Int) -> ChildCardRow {
        let name = member.child.name.isEmpty ? "Dítě" : member.child.name
        let birth = "nar. " + CzechFormat.date(member.child.birthDate)
        guard let credit else {
            return ChildCardRow(
                member: member, name: name, birth: birth, status: "", countsInNoMonth: false, amount: "—",
                hasAmount: false)
        }
        let status: String
        if let reason = credit.ineligibility {
            status = Self.reason(reason, year: year)
        } else if credit.claimedByOther {
            status = "uplatňuje druhý rodič · " + ComputationBuilder.months(credit.monthsByRate.values.reduce(0, +))
        } else {
            let rates = credit.monthsByRate.keys.sorted().map { rate in
                rateName(rate) + " · " + ComputationBuilder.months(credit.monthsByRate[rate] ?? 0)
            }
            status = rates.joined(separator: ", ") + (credit.ztppMonths > 0 ? " · se ZTP/P" : "")
        }
        let hasAmount = !credit.claimedByOther && credit.amount > 0
        return ChildCardRow(
            member: member, name: name, birth: birth, status: status, countsInNoMonth: credit.ineligibility != nil,
            amount: hasAmount ? CzechFormat.wholeKc(credit.amount) : "—", hasAmount: hasAmount)
    }

    /// Why a child counts in no month of `year`.
    static func reason(_ reason: ChildIneligibility, year: Int) -> String {
        switch reason {
        case .notBornYet(let day): "narodí se až " + CzechFormat.date(day)
        case .notInHousehold: "v roce \(year) s vámi nežije"
        case .over26: "už 26 let – zvýhodnění nelze uplatnit"
        case .adultNotStudying: "zletilé a nestuduje – zvýhodnění nelze uplatnit"
        case .noQualifyingMonth: "v roce \(year) nesplňuje podmínky"
        }
    }

    /// While the benefit is more than the tax: what it leaves after its credit, which is the engine's benefit less the
    /// part of it that is a credit, and whether that is paid as a bonus or why not. Income below six minimum wages
    /// pays no bonus yet in a year that goes on, and none at all once it is all the year's (`isWholeYear`).
    private static func bonusHint(_ result: TaxResult, isWholeYear: Bool) -> String? {
        // What the benefit leaves after its credit: the bonus that is paid, or the one that is not.
        let left = result.bonusWithheld == nil ? result.childBonus : result.withheldBonus
        guard left > 0 else { return nil }
        let over = "Zvýhodnění převyšuje daň o " + CzechFormat.wholeKc(left)
        switch result.bonusWithheld {
        case nil:
            return over + " – tolik vám finanční úřad vyplatí jako daňový bonus."
        case .belowMinimum:
            return over + ", bonus se ale pod " + CzechFormat.wholeKc(result.rules.bonusMinimum) + " nevyplácí."
        case .incomeBelowThreshold(let threshold):
            return over + ", bonus se ale" + (isWholeYear ? "" : " zatím")
                + " nevyplatí: příjmy roku nedosáhly 6× minimální mzdy (" + CzechFormat.wholeKc(threshold) + ")."
        }
    }

    // MARK: The spouse

    private static func spouse(of family: FamilyYear, result: TaxResult) -> SpouseCardContent {
        let rules = result.rules
        let year = result.year
        let monthly = rules.spouseCreditMonthly
        let claimLine =
            CzechFormat.wholeKc(monthly * 12) + " za rok – " + CzechFormat.wholeKc(monthly)
            + " za každý měsíc, na jehož začátku byly podmínky splněné. Snižuje jen daň, nejvýš na nulu."
        let incomeTitle = "Vlastní příjmy manžela / manželky za rok \(year)"
        guard let spouse = family.spouse, spouse.claim else {
            return SpouseCardContent(
                total: nil, totalCounts: false, claimLine: claimLine, incomeTitle: incomeTitle, incomeStatus: nil,
                incomeIsOverLimit: false, youngChild: nil, result: nil)
        }
        let limit = CzechFormat.wholeKc(rules.spouseIncomeLimit)
        let isOverLimit = spouse.ownIncomeKc > rules.spouseIncomeLimit
        let credits = result.family
        let total: String
        var line: String
        if credits.spouseCredit > 0 {
            total = CzechFormat.wholeKc(credits.spouseCredit) + " za rok"
            let ztpp = credits.spouseZTPPMonths > 0 ? ", z toho \(credits.spouseZTPPMonths) se ZTP/P" : ""
            line =
                "Sleva za " + ComputationBuilder.months(credits.spouseMonths) + ztpp + ": "
                + CzechFormat.wholeKc(credits.spouseCredit)
            let applied = result.spouseCreditApplied
            if applied < credits.spouseCredit {
                line +=
                    applied > 0
                    ? " – uplatní se jen " + CzechFormat.wholeKc(applied) + ", víc daně nezbývá"
                    : " – daň už je nulová, sleva se neprojeví"
            }
        } else {
            total = "neuplatní se"
            line =
                "V roce \(year) se sleva neuplatní"
                + (isOverLimit ? " – příjmy jsou nad limitem." : " – žádný měsíc nesplňuje podmínky.")
        }
        return SpouseCardContent(
            total: total, totalCounts: credits.spouseCredit > 0, claimLine: claimLine, incomeTitle: incomeTitle,
            incomeStatus: isOverLimit ? "nad limitem \(limit) – slevu nejde uplatnit" : "do limitu \(limit)",
            incomeIsOverLimit: isOverLimit,
            youngChild: rules.spouseNeedsYoungChild ? youngChildNote(of: family, result: result) : nil,
            result: line)
    }

    /// The box about the children under three: each child under three in the household in a month of the year, with
    /// its own months ("celý rok" for all twelve), or what the credit needs while there is none. A child's own months
    /// are the engine's months of a child under three for a family of the spouse and that child alone.
    private static func youngChildNote(of family: FamilyYear, result: TaxResult) -> YoungChildNote {
        guard result.family.spouseYoungChildMonths > 0 else {
            return YoungChildNote(
                text: "Od roku 2024 se sleva uplatní jen za měsíce, kdy s vámi žije i vaše vyživované dítě mladší 3"
                    + " let. Mezi dětmi žádné takové není – přidejte ho, i když na něj zvýhodnění uplatňuje druhý"
                    + " rodič.",
                isMet: false)
        }
        let children = family.children.compactMap { member -> String? in
            let alone = FamilyCredits.evaluate(
                FamilyFacts(children: [ChildFacts(member)], spouse: family.spouse), year: result.year,
                rules: result.rules)
            guard alone.spouseYoungChildMonths > 0 else { return nil }
            let name = member.child.name.isEmpty ? "dítě" : member.child.name
            let months = alone.spouseYoungChildMonths
            return name + " (" + (months == 12 ? "celý rok" : ComputationBuilder.months(months)) + ")"
        }
        return YoungChildNote(
            text: "Dítě do 3 let ve společné domácnosti: " + children.joined(separator: ", ")
                + ". Od roku 2024 se sleva počítá jen za tyto měsíce.",
            isMet: true)
    }
}

nonisolated extension MonthRange {
    /// The range with `month` as its first month; its last month moves along when it is earlier. A card that saves at
    /// once chooses its months so, as it has no place to say that a range is not one.
    func withFrom(_ month: Int) -> MonthRange {
        MonthRange(from: month, to: max(month, to))
    }

    /// The range with `month` as its last month; its first month moves along when it is later.
    func withTo(_ month: Int) -> MonthRange {
        MonthRange(from: min(from, month), to: month)
    }
}

import Foundation

/// The effect of one deduction on the income tax of the year, in whole Kč. The deductions are taken one after the
/// other in the order of the lines, and all of them together come off the profit at most, so each line has what is
/// left of the profit after the ones above it to take from.
nonisolated struct ImpactLine: Sendable, Hashable, Identifiable {
    var kind: DeductionKind
    var title: String

    /// What the person entered.
    var claimedKc: Int64

    /// What comes off the tax base for it: what the law allows of it, as far as the profit has room for it after the
    /// deductions above it. The lines add up to the deductions that come off in all (`ImpactTotals.deductionsKc`).
    var appliedKc: Int64

    /// How much lower the tax is because of this deduction, once the deductions above it are counted. It is the net
    /// tax, so what the deduction adds to a tax bonus counts as saved too.
    var taxSavedKc: Int64

    var id: DeductionKind {
        kind
    }
}

/// The totals of the panel "Dopad odpočtů a slev na daň", in whole Kč.
nonisolated struct ImpactTotals: Sendable, Hashable {
    /// What comes off the tax base in the end: the allowed deductions together, at most the profit.
    var deductionsKc: Int64

    /// The tax with no deduction claimed and without the credits of the family, the spouse credit and the child
    /// benefit; the taxpayer credit is applied. It is the net tax (`TaxResult.netTax`), which without the child benefit
    /// is never below zero.
    var taxWithoutKc: Int64

    /// The tax with the deductions and every credit: the net tax, negative when a tax bonus is paid.
    var taxWithKc: Int64

    /// The part of the spouse credit used, while the year has a spouse credit; nil while it has none.
    var spouseCreditKc: Int64? = nil

    /// The child tax benefit used, its credit and the bonus paid, while the year has a child benefit; nil while it has
    /// none.
    var childBenefitKc: Int64? = nil

    /// The part of `childBenefitKc` paid as a tax bonus.
    var childBonusKc: Int64 = 0

    /// What the deductions and the credits of the family save.
    var savedKc: Int64 {
        taxWithoutKc - taxWithKc
    }

    /// The title of the saving, over its big numerals.
    static let savedTitle = "Ušetříte na dani"

    /// The saving: "85 839 Kč".
    var savedText: String {
        CzechFormat.wholeKc(savedKc)
    }

    /// The lines under the saving: the deductions, the spouse credit and the child benefit used while the year has
    /// them, with what of the benefit is paid as a bonus, the tax without all of them, and the tax after them, which is
    /// "bonus …" while it is below zero.
    var rows: [ImpactTotalRow] {
        var rows = [ImpactTotalRow(title: "Odpočty celkem", value: CzechFormat.wholeKc(deductionsKc))]
        if let spouseCreditKc {
            rows.append(
                ImpactTotalRow(title: "Sleva na manžela / manželku", value: CzechFormat.wholeKc(-spouseCreditKc)))
        }
        if let childBenefitKc {
            let bonus = childBonusKc > 0 ? " (z toho bonus " + CzechFormat.wholeKc(childBonusKc) + ")" : ""
            rows.append(
                ImpactTotalRow(title: "Zvýhodnění na děti", value: CzechFormat.wholeKc(-childBenefitKc) + bonus))
        }
        rows.append(ImpactTotalRow(title: "Daň bez odpočtů a slev na rodinu", value: CzechFormat.wholeKc(taxWithoutKc)))
        rows.append(
            ImpactTotalRow(
                title: "Daň po odpočtech a slevách", value: BuilderText.taxOrBonus(taxWithKc), isEmphasized: true))
        return rows
    }
}

/// A line of the totals of the panel: its title and its value. The last one, the tax after everything, is emphasized.
nonisolated struct ImpactTotalRow: Sendable, Hashable {
    var title: String
    var value: String
    var isEmphasized = false
}

/// What the screen of advances and deductions says about the deductions and the credits of a year as of a day: the
/// effect of each deduction on the tax, the totals, and the hints under the fields of the form. All of it is worked
/// out by the tax engine from one input, so the hints, the lines and the totals can never disagree.
nonisolated struct AdvanceImpact: Sendable, Hashable {
    /// One line for each deduction that is claimed, in the order of the form: interest, retirement products, gifts.
    var lines: [ImpactLine]
    var totals: ImpactTotals
    var hints: DeductionHints

    /// The computation of the whole input, which the cards of the family say in words.
    var result: TaxResult
}

nonisolated enum AdvanceImpactBuilder {
    /// The impact of the deductions and the credits in `input`, as of `asOf`. The computation checks the input first
    /// and throws `ComputationError.invalidYear` for values the engine would stop the app on, so nothing is worked out
    /// for them.
    ///
    /// The effect of a deduction is the difference it makes when it is added to the deductions before it, in the order
    /// of the engine's lines (interest, retirement products, gifts). That way the lines add up to the saving of all of
    /// them, whichever tax band each one falls in. For the same reason what each line takes off the profit is held to
    /// what the deductions above it left of it, so the lines add up to the deductions that come off in all. Each effect
    /// counts the credits of the family, which are no deductions; the totals leave them out of the tax without the
    /// deductions too, as the panel says, so the saving is that of the deductions and the credits of the family.
    static func build(_ input: YearInput, asOf: CivilDate) throws -> AdvanceImpact {
        let result = try AppModel.compute(input, asOf: asOf)
        let kinds = result.deductionLines.map(\.kind)
        // The net tax with the first `count` deductions of the engine's order: none of them up to all but the last, and
        // then the net tax of the whole input. A deduction that adds to a tax bonus saves what it adds.
        var taxes: [Int64] = []
        for count in 0..<kinds.count {
            var partial = input
            partial.deductions = input.deductions.keeping(Set(kinds.prefix(count)))
            taxes.append(try AppModel.compute(partial, asOf: asOf).netTax)
        }
        taxes.append(result.netTax)
        // The tax without the deductions and without the credits of the family: the taxpayer credit stays.
        var bare = input
        bare.deductions = input.deductions.keeping([])
        bare.family = FamilyFacts()
        let taxWithout = try AppModel.compute(bare, asOf: asOf).netTax

        var lines: [ImpactLine] = []
        // The deductions together take off at most the profit; each takes what the ones before it left.
        var room = max(0, result.DZ)
        for (index, line) in result.deductionLines.enumerated() {
            let applied = min(line.allowed, room)
            room -= applied
            if line.claimed > 0 {
                lines.append(
                    ImpactLine(
                        kind: line.kind, title: line.kind.title, claimedKc: line.claimed, appliedKc: applied,
                        taxSavedKc: taxes[index] - taxes[index + 1]))
            }
        }
        // The credits of the family that are used, while the year has them: the spouse credit, and the child benefit's
        // credit and bonus.
        let family = result.family
        return AdvanceImpact(
            lines: lines,
            totals: ImpactTotals(
                deductionsKc: result.deductionsTotal, taxWithoutKc: taxWithout, taxWithKc: result.netTax,
                spouseCreditKc: family.spouseCredit > 0 ? result.spouseCreditApplied : nil,
                childBenefitKc: family.childBenefit > 0 ? result.childCredit + result.childBonus : nil,
                childBonusKc: result.childBonus),
            hints: DeductionHints.make(from: result.deductionLines, deductions: input.deductions),
            result: result)
    }
}

nonisolated extension DeductionKind {
    /// What the deduction is called on the screen.
    var title: String {
        switch self {
        case .mortgageInterest: "Úroky z úvěru na bydlení"
        case .pensionSavings: "Penzijní spoření"
        case .lifeInsurance: "Soukromé životní pojištění"
        case .retirementProducts: "Spoření a pojištění na stáří"
        case .gifts: "Dary"
        }
    }
}

nonisolated extension Deductions {
    /// The same deductions with the claims of the kinds that are not in `kinds` taken away (set to zero). The months of
    /// the mortgage and its limit stay. `.retirementProducts` stands for pension savings, life insurance, DIP and
    /// long-term care insurance together, `.pensionSavings` and `.lifeInsurance` for those two alone.
    func keeping(_ kinds: Set<DeductionKind>) -> Deductions {
        var kept = self
        if !kinds.contains(.mortgageInterest) {
            kept.mortgageInterestPaid = 0
        }
        if !kinds.contains(.retirementProducts) {
            kept.dip = 0
            kept.longTermCare = 0
            if !kinds.contains(.pensionSavings) {
                kept.pensionSavings = 0
            }
            if !kinds.contains(.lifeInsurance) {
                kept.lifeInsurance = 0
            }
        }
        if !kinds.contains(.gifts) {
            kept.gifts = 0
        }
        return kept
    }
}

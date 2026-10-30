import Foundation

/// The three authorities a self-employed person pays.
nonisolated enum Authority: String, Sendable, CaseIterable, Hashable {
    /// Income tax, paid to the tax office.
    case tax

    /// Social insurance, paid to ČSSZ.
    case social

    /// Health insurance, paid to the health insurer.
    case health
}

/// What one authority is owed and how the advances cover it, as of the computed day. Amounts are whole Kč.
nonisolated struct AuthorityBalance: Sendable, Hashable {
    var authority: Authority

    /// The tax or insurance computed from the income counted so far. For the tax office it is the net tax
    /// (`TaxResult.netTax`), which is negative when a tax bonus is paid.
    var liability: Int64

    /// The advances of the months from January through the as-of month.
    var advancesPaid: Int64

    /// What the paid advances leave unpaid: max(0, liability − advancesPaid).
    var remaining: Int64

    /// What the paid advances pay beyond the liability: max(0, advancesPaid − liability). With a tax bonus it is the
    /// advances and the bonus together. It never lowers what another authority is owed.
    var overpayment: Int64

    /// The advances planned for the months after the as-of month.
    var plannedAfterAsOf: Int64

    /// The part of `remaining` the planned advances will pay: min(remaining, plannedAfterAsOf).
    var leavesViaPlannedAdvances: Int64

    /// The part of `remaining` left to pay after the return or the overview: remaining − leavesViaPlannedAdvances.
    var settlement: Int64
}

/// A deduction from the tax base.
nonisolated enum DeductionKind: String, Sendable, Hashable {
    case mortgageInterest

    /// Pension savings with a limit of their own (2022 and 2023).
    case pensionSavings

    /// Life insurance with a limit of its own (2022 and 2023).
    case lifeInsurance

    /// Pension savings, life insurance, DIP and long-term care insurance under one limit (from 2024).
    case retirementProducts

    case gifts
}

/// One deduction from the tax base: what was claimed, what the law allows and the limit that applied, in whole Kč.
nonisolated struct DeductionLine: Sendable, Hashable {
    var kind: DeductionKind

    var claimed: Int64

    /// What the law allows, before the deductions together are capped at the tax base.
    var allowed: Int64

    /// The most that may be deducted, or nil when no limit applies.
    var limit: Int64?
}

/// How the social insurance was assessed (§ 5b, § 7, § 14 and § 15a zákona č. 589/1992 Sb.). Amounts are whole Kč.
nonisolated struct SocialAssessment: Sendable, Hashable {
    /// The months of main activity among the counted months.
    var mainMonths: Int

    /// The months of secondary activity among the counted months.
    var secondaryMonths: Int

    /// Whether the secondary activity reached the reduced decisive amount and is insured. Nil when no counted month is
    /// secondary.
    var secondaryInsured: Bool?

    /// The decisive amount less a rounded-up twelfth of it for each month of the year without a secondary activity.
    /// Before the end of the year the months after the counted ones count as such months too; that is a convention of
    /// this app, not a legal rule. Nil when no counted month is secondary.
    var reducedDecisiveAmount: Int64?

    /// Row 23 of the ČSSZ overview: the profit per active month, rounded half-up to two decimal places. Only a year
    /// with both main and secondary months has it.
    var row23: Decimal?

    /// The base worked out from the profit: the assessment share of it, rounded up. In a year with both main and
    /// secondary months it is the sum of row 25 (only the main share when the secondary activity is not insured).
    /// Zero when only secondary months are counted and the activity is not insured.
    var computedBase: Int64

    /// The minimum base of the counted months: the monthly minimum times the months. In a year with both main and
    /// secondary months it is the sum of row 26 (only the main minimum when the secondary activity is not insured).
    /// Zero when only secondary months are counted and the activity is not insured.
    var minimumBase: Int64

    /// The maximum yearly base. It is not prorated.
    var maximumBase: Int64

    /// The assessment base: the larger of the computed and the minimum base, at most the maximum. In a year with both
    /// main and secondary months it can also be the main minimum plus the secondary share of the profit (row 27).
    var base: Int64

    /// The insurance: 29.2 % of the base, rounded up.
    var insurance: Int64
}

/// How the health insurance was assessed (§ 3a zákona č. 592/1992 Sb.). The bases are in haléře because the minimum
/// can be a half crown; they are never rounded. The insurance is whole Kč.
nonisolated struct HealthAssessment: Sendable, Hashable {
    /// The counted active months in which the minimum applies.
    var minimumMonths: Int

    /// Half the profit (a loss counts as zero).
    var computedBaseHalere: Int64

    /// The monthly minimum times `minimumMonths`.
    var minimumBaseHalere: Int64

    /// The larger of the two; there is no maximum.
    var baseHalere: Int64

    /// 13.5 % of the base, rounded up.
    var insurance: Int64
}

/// Everything the engine works out for one year as of one day: each step of the computation, the balance with each
/// authority and the marginal rate. Amounts are whole Kč unless the name says haléře.
nonisolated struct TaxResult: Sendable, Hashable {
    var year: Int
    var asOf: CivilDate

    /// The rules used. For a year without rules of its own they are the nearest supported year's.
    var rules: TaxRules

    /// Whether `rules` belong to another year, so the numbers are only an estimate.
    var rulesAreEstimate: Bool

    /// The last month counted for the minimum bases: the as-of month.
    var lastCountedMonth: Int

    /// The income counted so far: every receipt of the year up to the as-of day, adjustments included, in haléře.
    var incomeHalere: Int64

    /// The part of `incomeHalere` that comes from income adjustments.
    var adjustmentsHalere: Int64

    /// The VAT of the counted receipts, in haléře. It is not income.
    var vatHalere: Int64

    /// The number of counted payments. Income adjustments are not counted here; `adjustmentsHalere` shows them.
    var receiptCount: Int

    /// The income in whole Kč (příjmy).
    var P: Int64

    var expensePercent: Int

    /// The cap on the flat-rate expenses at `expensePercent`.
    var expenseCap: Int64

    /// The flat-rate expenses at `expensePercent` of the income, rounded down, before the cap: what `V` would be
    /// without it. Zero when the income is not positive.
    var uncappedExpenses: Int64

    /// The flat-rate expenses (výdaje).
    var V: Int64

    /// Whether the cap, not the percentage, decided `V`.
    var expensesCapped: Bool

    /// The profit (dílčí základ daně of § 7). With no other income it is also the tax base; it can be negative.
    var DZ: Int64

    /// Each deduction with its limit, in a fixed order: mortgage interest, the retirement products, gifts.
    var deductionLines: [DeductionLine]

    /// The deductions taken off the tax base: the allowed amounts together, at most the tax base.
    var deductionsTotal: Int64

    /// The tax base after the deductions, rounded down to whole hundreds and never negative.
    var B: Int64

    /// The part of `B` taxed at the lower rate, up to the threshold of the higher one.
    var taxBaseInLowBand: Int64

    /// The part of `B` above the threshold, taxed at the higher rate.
    var taxBaseInHighBand: Int64

    var taxBeforeCredit: Int64

    /// The part of the taxpayer credit used: never more than the tax.
    var creditApplied: Int64

    /// The part of the spouse credit used: never more than the tax the taxpayer credit leaves. `family` holds the whole
    /// credit and its months.
    var spouseCreditApplied: Int64

    /// The part of the child tax benefit taken off the tax as a credit: never more than the tax the taxpayer credit and
    /// the spouse credit leave ("Daň po slevách").
    var childCredit: Int64

    /// The tax bonus paid: what the child benefit leaves after its credit, when it is paid, otherwise 0.
    var childBonus: Int64

    /// Why what the child benefit leaves after its credit is not paid as a bonus. Nil when it is paid, or when the
    /// credit takes all of the benefit.
    var bonusWithheld: BonusWithholding?

    /// The tax bonus that is not paid: what the child benefit leaves after its credit while `bonusWithheld` says why it
    /// is not paid, otherwise 0.
    var withheldBonus: Int64 {
        bonusWithheld == nil ? 0 : family.childBenefit - childCredit
    }

    /// The spouse credit and the child tax benefit of the year, with their months, before they are set against the
    /// tax. Every month of the year counts, also those after the as-of day.
    var family: FamilyCredits

    /// The income tax after the credits: the taxpayer credit, the spouse credit and the child benefit's credit. Never
    /// below zero; a tax bonus is `childBonus`.
    var tax: Int64

    /// The tax less the tax bonus, negative when a bonus is paid. The tax office's balance, the totals, the marginal
    /// rate and the effect of a receipt count it, so a bonus lowers what the levies take.
    var netTax: Int64 {
        tax - childBonus
    }

    /// "Daň po slevách": the tax that the taxpayer credit and the spouse credit leave, never below zero. The child
    /// benefit is a credit up to it, and what it leaves is a tax bonus.
    var taxAfterCredits: Int64 {
        taxBeforeCredit - creditApplied - spouseCreditApplied
    }

    var social: SocialAssessment
    var health: HealthAssessment

    /// The balance with each authority, in the order tax, social, health.
    var balances: [AuthorityBalance]

    /// The sums of the balances. An overpayment at one authority never offsets what another is owed. The liabilities
    /// count the net tax, so a tax bonus lowers their sum.
    var liabilityTotal: Int64
    var advancesPaidTotal: Int64
    var remainingTotal: Int64
    var overpaymentTotal: Int64
    var leavesViaPlannedAdvances: Int64
    var settlementTotal: Int64

    /// What each authority takes of the next crown: the levies with 100 000 Kč more income minus the levies now,
    /// divided by 100 000. A share, so 0.15 is 15 %. The tax office's share counts the net tax: income that takes away
    /// some of a tax bonus is levied by as much. The bonus is paid, or not, with the 100 000 Kč more as it is now: the
    /// income of six minimum wages brings the whole bonus at once, a step that is no rate of the next crown, so a
    /// receipt that brings it names it instead (`LevyThreshold.bonusIncome`).
    var marginal: [Authority: Decimal]

    /// The same for the three together.
    var marginalTotal: Decimal

    /// The balance with one authority.
    func balance(_ authority: Authority) -> AuthorityBalance {
        guard let balance = balances.first(where: { $0.authority == authority }) else {
            preconditionFailure("A result has a balance for every authority.")
        }
        return balance
    }
}

/// What one receipt adds to the levies of its year, on its own day. Amounts are whole Kč.
nonisolated struct ReceiptEffect: Sendable, Hashable {
    var receipt: Receipt

    /// What the receipt adds to the net tax: a tax bonus that it lowers, or that it brings by bringing the income to
    /// six minimum wages, counts too.
    var tax: Int64
    var social: Int64
    var health: Int64

    /// The three together.
    var total: Int64

    /// The thresholds the receipt's income reaches, in the order of `LevyThreshold`. Past each of them a further crown
    /// is levied differently, or, past the income of the tax bonus, the bonus is paid, so they explain why the levies
    /// take a share of this income so unlike that of an earlier one. Empty when the income stays below all of them, and
    /// for a receipt of another year.
    var crossings: [ThresholdCrossing] = []
}

/// A threshold of a year's levies past which a further crown of income is levied differently, or, for the income of
/// the tax bonus, from which the bonus is paid, in the order the income reaches them.
nonisolated enum LevyThreshold: Sendable, Hashable, CaseIterable {
    /// Six minimum wages of income (§ 35c odst. 4 zákona č. 586/1992 Sb.), from which what the child benefit leaves
    /// after its credit is paid as a tax bonus. It is a step, not a rate: reaching it pays the whole bonus at once, and
    /// a further crown is levied as before. So only the receipt that brings the bonus reaches it, and the crossing says
    /// how much the bonus is. The income reaches it before every other threshold.
    case bonusIncome

    /// The cap of the flat-rate expenses (§ 7 odst. 7 zákona č. 586/1992 Sb.), reached at an income of 2 000 000 Kč at
    /// every percentage. Past it the expenses stay at the cap, so every further crown is profit.
    case expenseCap

    /// The band of 23 % (§ 16 odst. 1 zákona č. 586/1992 Sb.): the part of the tax base above the threshold of the year
    /// is taxed at 23 % instead of 15 %.
    case taxBand

    /// The maximum social insurance assessment base. Past it no further social insurance is due.
    case socialMaximum
}

/// A threshold that a receipt's income reaches, and how much of the income is past it.
nonisolated struct ThresholdCrossing: Sendable, Hashable {
    /// How much of the income is past the threshold.
    nonisolated enum Extent: Sendable, Hashable {
        /// All of it: the income of the year was past the threshold before the receipt.
        case whole

        /// This many whole Kč of it, the income counted as the engine counts it, to the crown; the rest is below the
        /// threshold.
        case part(Int64)
    }

    var threshold: LevyThreshold

    /// The threshold in whole Kč, in its own terms: the income from which the tax bonus is paid, the income at which
    /// the expenses reach the cap, the tax base above which the tax is 23 %, or the maximum assessment base.
    var limit: Int64

    /// How much of the income is past the threshold. The income of the tax bonus counts it as the others do, though a
    /// receipt that ends exactly at it brings the bonus with no crown past it.
    var extent: Extent

    /// For the income of the tax bonus, the bonus that reaching it brings, in whole Kč. 0 for every other threshold.
    var bonus: Int64 = 0
}

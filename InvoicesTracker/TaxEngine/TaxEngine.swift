import Foundation

/// Income tax, social insurance and health insurance of a self-employed person (OSVČ) who taxes cash income with
/// flat-rate expenses, for one year as of one day.
///
/// Amounts stay exact (`Int64` haléře or Kč, `Decimal` for shares of them) until a rule says to round, and every
/// rounding goes through `DecimalMath`, so no value is rounded twice.
nonisolated enum TaxEngine {
    // MARK: A year

    /// The levies and balances of `input.year` as of `asOf`.
    ///
    /// The income is every receipt of the year up to and including `asOf`. Deductions and the taxpayer credit are
    /// full-year amounts, and the spouse credit and the child tax benefit count every month of the year whose
    /// conditions are met, also the months after `asOf`. Only the tax bonus asks about the income so far: it is paid
    /// once the income counted reaches six minimum wages. The minimum assessment bases count the active months from
    /// January through the as-of month. Advances of January through the as-of month count as paid. A year without
    /// rules of its own uses the nearest supported year's rules and is marked as an estimate.
    ///
    /// `asOf` must be in `input.year`. It can be any day of it, also of a year that is over: the year as it was on that
    /// day. The whole year is the year as of its 31 December.
    static func compute(_ input: YearInput, asOf: CivilDate) -> TaxResult {
        checkInput(input)
        precondition(asOf.year == input.year, "The as-of day must be in the computed year.")
        let (rules, rulesAreEstimate) = TaxRules.forYear(input.year)

        let counted = countedReceipts(input.receipts, year: input.year, through: asOf)
        let adjustments = counted.filter(isAdjustment)
        let incomeHalere = netTotal(counted)
        let months = monthCounts(input, through: asOf.month)

        let levies = liabilities(incomeHalere: incomeHalere, months: months, input: input, rules: rules)
        // The marginal rate compares with the levies of 100 000 Kč more income, everything else unchanged, also whether
        // the tax bonus is paid: the bonus that six minimum wages bring is a step, not a rate of the next crown.
        let raised = liabilities(
            incomeHalere: incomeHalere + marginalStepHalere,
            months: months,
            input: input,
            rules: rules,
            holdingTheBonusOf: levies
        )

        let balances = Authority.allCases.map { authority in
            balance(
                authority,
                liability: levies.amount(for: authority),
                plan: advances(of: authority, in: input.advances),
                asOfMonth: asOf.month
            )
        }
        let marginal = Dictionary(uniqueKeysWithValues: Authority.allCases.map { authority in
            (authority, marginalRate(raised.amount(for: authority) - levies.amount(for: authority)))
        })

        return TaxResult(
            year: input.year,
            asOf: asOf,
            rules: rules,
            rulesAreEstimate: rulesAreEstimate,
            lastCountedMonth: asOf.month,
            incomeHalere: incomeHalere,
            adjustmentsHalere: netTotal(adjustments),
            vatHalere: counted.reduce(0) { $0 + $1.czkVatHalere },
            receiptCount: counted.count - adjustments.count,
            P: levies.P,
            expensePercent: input.expensePercent,
            expenseCap: levies.expenseCap,
            uncappedExpenses: levies.uncappedExpenses,
            V: levies.V,
            expensesCapped: levies.expensesCapped,
            DZ: levies.DZ,
            deductionLines: levies.deductionLines,
            deductionsTotal: levies.deductionsTotal,
            B: levies.B,
            taxBaseInLowBand: levies.taxBaseInLowBand,
            taxBaseInHighBand: levies.taxBaseInHighBand,
            taxBeforeCredit: levies.taxBeforeCredit,
            creditApplied: levies.creditApplied,
            spouseCreditApplied: levies.spouseCreditApplied,
            childCredit: levies.childCredit,
            childBonus: levies.childBonus,
            bonusWithheld: levies.bonusWithheld,
            family: levies.family,
            tax: levies.tax,
            social: levies.social,
            health: levies.health,
            balances: balances,
            liabilityTotal: balances.reduce(0) { $0 + $1.liability },
            advancesPaidTotal: balances.reduce(0) { $0 + $1.advancesPaid },
            remainingTotal: balances.reduce(0) { $0 + $1.remaining },
            overpaymentTotal: balances.reduce(0) { $0 + $1.overpayment },
            leavesViaPlannedAdvances: balances.reduce(0) { $0 + $1.leavesViaPlannedAdvances },
            settlementTotal: balances.reduce(0) { $0 + $1.settlement },
            marginal: marginal,
            marginalTotal: marginalRate(raised.total - levies.total)
        )
    }

    /// What `receipt` adds to each levy on its own day: the levies with the year's other receipts up to that day, with
    /// and without it. The minimum bases count the months through the receipt's month. A receipt of another year adds
    /// nothing. The effect also names the thresholds of the year that the receipt's income reaches, which explain a
    /// share of it unlike that of an earlier receipt.
    ///
    /// The tax is the net tax, so a receipt that lowers the tax bonus, or brings it by bringing the income to six
    /// minimum wages, adds that too; one that brings it names that threshold with the bonus.
    ///
    /// The receipt need not be in `input.receipts`, so a preview works too. A receipt of an invoice or an income
    /// adjustment replaces the input's receipt of the same invoice or adjustment, which may be an older version with
    /// another amount or day, so an edited payment is never counted twice. A synthetic receipt replaces one equal
    /// receipt of the input, if there is one.
    static func effect(of receipt: Receipt, in input: YearInput) -> ReceiptEffect {
        checkInput(input)
        guard receipt.day.year == input.year else {
            return ReceiptEffect(receipt: receipt, tax: 0, social: 0, health: 0, total: 0)
        }
        let rules = TaxRules.forYear(input.year).rules
        let others = receipts(input.receipts, without: receipt)
        let incomeWithout = netTotal(countedReceipts(others, year: input.year, through: receipt.day))
        let months = monthCounts(input, through: receipt.day.month)
        let withoutReceipt = liabilities(incomeHalere: incomeWithout, months: months, input: input, rules: rules)
        let withReceipt = liabilities(
            incomeHalere: incomeWithout + receipt.czkNetHalere,
            months: months,
            input: input,
            rules: rules
        )
        return ReceiptEffect(
            receipt: receipt,
            tax: withReceipt.netTax - withoutReceipt.netTax,
            social: withReceipt.social.insurance - withoutReceipt.social.insurance,
            health: withReceipt.health.insurance - withoutReceipt.health.insurance,
            total: withReceipt.total - withoutReceipt.total,
            crossings: crossings(without: withoutReceipt, with: withReceipt, months: months, input: input, rules: rules)
        )
    }

    // MARK: Insurance

    /// The social insurance of the profit `dz` over the counted months: `mainMonths` of main and `secondaryMonths` of
    /// secondary activity (§ 5b, § 7, § 14 and § 15a zákona č. 589/1992 Sb.). A loss counts as zero profit.
    ///
    /// With no secondary month the whole profit is assessed as main activity. With secondary months the secondary
    /// activity is insured only when its profit reaches the reduced decisive amount, and a year with both kinds of
    /// month follows the rows of the ČSSZ overview.
    static func socialAssessment(
        dz: Int64,
        mainMonths: Int,
        secondaryMonths: Int,
        rules: TaxRules
    ) -> SocialAssessment {
        precondition(
            mainMonths >= 0 && secondaryMonths >= 0 && mainMonths + secondaryMonths <= 12,
            "The counted months are 0 to 12 in all."
        )
        let profit = max(0, dz)
        guard secondaryMonths > 0 else {
            return mainActivityAssessment(profit: profit, mainMonths: mainMonths, rules: rules)
        }
        // A secondary activity is insured when its profit reaches at least ("dosáhl aspoň") the decisive amount less
        // ⌈D ÷ 12⌉ for each month of the year without secondary activity, main months and months without activity
        // alike (§ 9 and § 10 odst. 2 zákona č. 155/1995 Sb.; § 5b zákona č. 589/1992 Sb.).
        // A convention chosen here, not a legal rule: as of a day before the end of the year, the months after the
        // counted ones also count as months without secondary activity, so the decisive amount shrinks to the
        // secondary months counted so far.
        let reducedDecisiveAmount = rules.reducedDecisiveAmount(monthsWithoutSecondary: 12 - secondaryMonths)
        guard mainMonths > 0 else {
            return secondaryActivityAssessment(
                profit: profit,
                secondaryMonths: secondaryMonths,
                reducedDecisiveAmount: reducedDecisiveAmount,
                rules: rules
            )
        }
        return mixedYearAssessment(
            profit: profit,
            mainMonths: mainMonths,
            secondaryMonths: secondaryMonths,
            reducedDecisiveAmount: reducedDecisiveAmount,
            rules: rules
        )
    }

    /// Main activity only, or no active month: the assessment share of the profit, rounded up, at least the
    /// main-activity minimum for each main month and at most the yearly maximum, which is not prorated.
    private static func mainActivityAssessment(profit: Int64, mainMonths: Int, rules: TaxRules) -> SocialAssessment {
        let computedBase = DecimalMath.ceil(rules.socialAssessmentPercent * Decimal(profit))
        let minimumBase = rules.socialMinimumMonthlyMain * Int64(mainMonths)
        let base = min(max(computedBase, minimumBase), rules.socialMaximumAnnualBase)
        return SocialAssessment(
            mainMonths: mainMonths,
            secondaryMonths: 0,
            secondaryInsured: nil,
            reducedDecisiveAmount: nil,
            row23: nil,
            computedBase: computedBase,
            minimumBase: minimumBase,
            maximumBase: rules.socialMaximumAnnualBase,
            base: base,
            insurance: socialInsurance(of: base)
        )
    }

    /// Secondary activity only. When it is insured, the base is the assessment share of the profit, rounded up, at
    /// least the secondary-activity minimum for each secondary month and at most the yearly maximum. When it is not,
    /// nothing is assessed and nothing is owed.
    private static func secondaryActivityAssessment(
        profit: Int64,
        secondaryMonths: Int,
        reducedDecisiveAmount: Int64,
        rules: TaxRules
    ) -> SocialAssessment {
        let insured = profit >= reducedDecisiveAmount
        let computedBase = insured ? DecimalMath.ceil(rules.socialAssessmentPercent * Decimal(profit)) : 0
        let minimumBase = insured ? rules.socialMinimumMonthlySecondary * Int64(secondaryMonths) : 0
        let base = min(max(computedBase, minimumBase), rules.socialMaximumAnnualBase)
        return SocialAssessment(
            mainMonths: 0,
            secondaryMonths: secondaryMonths,
            secondaryInsured: insured,
            reducedDecisiveAmount: reducedDecisiveAmount,
            row23: nil,
            computedBase: computedBase,
            minimumBase: minimumBase,
            maximumBase: rules.socialMaximumAnnualBase,
            base: base,
            insurance: socialInsurance(of: base)
        )
    }

    /// Both main and secondary months, by the rows of the ČSSZ overview (přehled o příjmech a výdajích OSVČ) and its
    /// instructions. Row 23 is the profit per active month, rounded half-up to two decimal places. Row 24 splits it by
    /// months into a main and a secondary share, unrounded. Row 25 is the assessment share of each, rounded up, and
    /// row 26 the minimum of each. Row 27, the base, is the highest of the two rows 25 added, the two rows 26 added,
    /// and the main row 26 plus the secondary row 25, at most the yearly maximum. A secondary share below the reduced
    /// decisive amount is not insured: its rows 25 and 26 are 0, so the base is the higher of the main rows 25 and 26.
    private static func mixedYearAssessment(
        profit: Int64,
        mainMonths: Int,
        secondaryMonths: Int,
        reducedDecisiveAmount: Int64,
        rules: TaxRules
    ) -> SocialAssessment {
        let assessmentShare = rules.socialAssessmentPercent
        let row23 = DecimalMath.rounded(Decimal(profit) / Decimal(mainMonths + secondaryMonths), scale: 2, .plain)
        let mainShare = row23 * Decimal(mainMonths)
        let secondaryShare = row23 * Decimal(secondaryMonths)
        let insured = secondaryShare >= Decimal(reducedDecisiveAmount)
        let row25Main = DecimalMath.ceil(assessmentShare * mainShare)
        let row25Secondary = insured ? DecimalMath.ceil(assessmentShare * secondaryShare) : 0
        let row26Main = rules.socialMinimumMonthlyMain * Int64(mainMonths)
        let row26Secondary = insured ? rules.socialMinimumMonthlySecondary * Int64(secondaryMonths) : 0
        let row27 = min(
            max(row25Main + row25Secondary, row26Main + row26Secondary, row26Main + row25Secondary),
            rules.socialMaximumAnnualBase
        )
        return SocialAssessment(
            mainMonths: mainMonths,
            secondaryMonths: secondaryMonths,
            secondaryInsured: insured,
            reducedDecisiveAmount: reducedDecisiveAmount,
            row23: row23,
            computedBase: row25Main + row25Secondary,
            minimumBase: row26Main + row26Secondary,
            maximumBase: rules.socialMaximumAnnualBase,
            base: row27,
            insurance: socialInsurance(of: row27)
        )
    }

    /// The health insurance of the profit `dz`, with the minimum applying in `minimumMonths` months (§ 2 odst. 2 and
    /// § 3a zákona č. 592/1992 Sb.). A loss counts as zero profit.
    static func healthAssessment(dz: Int64, minimumMonths: Int, rules: TaxRules) -> HealthAssessment {
        precondition((0...12).contains(minimumMonths), "The health minimum applies in 0 to 12 months.")
        // The base is half the profit, at least the monthly minimum for each month in which it applies; there is no
        // maximum. It is not rounded: a half-crown minimum stays in haléře.
        let computedBaseHalere = halere(TaxRules.healthAssessmentPercent * Decimal(max(0, dz)))
        let minimumBaseHalere = halere(rules.healthMinimumMonthlyBase * Decimal(minimumMonths))
        let baseHalere = max(computedBaseHalere, minimumBaseHalere)
        // The insurance is 13.5 % of the base, rounded up to whole Kč.
        let insurance = DecimalMath.ceil(TaxRules.healthRate * Decimal(baseHalere) / 100)
        return HealthAssessment(
            minimumMonths: minimumMonths,
            computedBaseHalere: computedBaseHalere,
            minimumBaseHalere: minimumBaseHalere,
            baseHalere: baseHalere,
            insurance: insurance
        )
    }

    // MARK: The core

    /// The levies that follow from one counted income. `compute`, its marginal rate and `effect` all use this one
    /// function, so they can never disagree. Only the expense percentage, the deductions, the credits and the family
    /// come from `input`; the income and the counted months are the arguments. The income also decides whether a tax
    /// bonus is paid, unless the levies of a lower income are `held`: then what the child benefit leaves after its
    /// credit is paid, or not, as it is in them, which is how the marginal rate leaves out the step of the bonus.
    private static func liabilities(
        incomeHalere: Int64,
        months: MonthCounts,
        input: YearInput,
        rules: TaxRules,
        holdingTheBonusOf held: Liabilities? = nil
    ) -> Liabilities {
        // Flat-rate expenses are a percentage of the income up to a cap (§ 7 odst. 7 zákona č. 586/1992 Sb.).
        guard let expenseCap = TaxRules.expenseCap(percent: input.expensePercent) else {
            preconditionFailure("Flat-rate expenses are 80, 60, 40 or 30 %.")
        }
        // A convention chosen here, not a legal rule: the income is rounded half-up to whole Kč, once. The law and the
        // FS instructions only require whole Kč and prescribe no direction; they forbid rounding in steps
        // ("Postupné zaokrouhlování ve dvou nebo více stupních je nepřípustné").
        let P = DecimalMath.halfUp(Decimal(incomeHalere) / 100)
        // A convention chosen here, not a legal rule: the expenses are rounded down to whole Kč, so they never exceed
        // the statutory percentage. The law and the FS instructions only require whole Kč and prescribe no direction.
        let uncappedExpenses = P > 0 ? DecimalMath.floor(Decimal(input.expensePercent) / 100 * Decimal(P)) : 0
        let V = min(uncappedExpenses, expenseCap)
        // The profit is the partial tax base of § 7 (dílčí základ daně). With no other income it is the tax base.
        let DZ = P - V

        let lines = deductionLines(input.deductions, taxBase: DZ, rules: rules)
        // Together the deductions take off at most the tax base (§ 15 zákona č. 586/1992 Sb.).
        let deductionsTotal = min(lines.reduce(0) { $0 + $1.allowed }, max(0, DZ))
        // The base after the deductions is rounded down to whole hundreds of Kč and is never negative (§ 16 odst. 2
        // zákona č. 586/1992 Sb.).
        let B = max(0, DecimalMath.floor(Decimal(DZ - deductionsTotal) / 100) * 100)
        // 15 % up to the threshold and 23 % above it (§ 16 odst. 1 zákona č. 586/1992 Sb.), computed exactly and
        // rounded up to whole Kč (§ 146 odst. 1 zákona č. 280/2009 Sb., daňový řád).
        let lowBand = min(B, rules.taxBandThreshold)
        let highBand = max(0, B - rules.taxBandThreshold)
        let taxBeforeCredit = DecimalMath.ceil(
            TaxRules.taxRateLow * Decimal(lowBand) + TaxRules.taxRateHigh * Decimal(highBand)
        )
        // The taxpayer credit is the whole yearly amount, never prorated, and takes the tax down to zero at most
        // (§ 35ba odst. 1 písm. a) zákona č. 586/1992 Sb.).
        let creditApplied = input.taxpayerCredit ? min(rules.taxpayerCredit, taxBeforeCredit) : 0
        // The spouse credit comes next. The credits of § 35ba together take the tax down to zero at most, so it is used
        // only as far as there is tax left (§ 35ba odst. 1 písm. b) and odst. 3, § 35bb zákona č. 586/1992 Sb.).
        let family = FamilyCredits.evaluate(input.family, year: input.year, rules: rules)
        let spouseCreditApplied = min(family.spouseCredit, taxBeforeCredit - creditApplied)
        // The child benefit is a credit up to the tax that is left after them, "Daň po slevách", and the rest is a tax
        // bonus (§ 35c odst. 3 zákona č. 586/1992 Sb.), paid only under the conditions of `bonusWithholding`.
        let taxAfterCredits = taxBeforeCredit - creditApplied - spouseCreditApplied
        let childCredit = min(family.childBenefit, taxAfterCredits)
        let rest = family.childBenefit - childCredit
        let bonusWithheld: BonusWithholding?
        if let held {
            // Paid as it is there, or withheld for the same reason. The lower income leaves at least as much of the
            // benefit, so whatever is left here was left there too.
            bonusWithheld = rest > 0 ? held.bonusWithheld : nil
        } else {
            bonusWithheld = bonusWithholding(of: rest, income: P, rules: rules)
        }

        return Liabilities(
            P: P,
            expenseCap: expenseCap,
            uncappedExpenses: uncappedExpenses,
            V: V,
            expensesCapped: uncappedExpenses > expenseCap,
            DZ: DZ,
            deductionLines: lines,
            deductionsTotal: deductionsTotal,
            B: B,
            taxBaseInLowBand: lowBand,
            taxBaseInHighBand: highBand,
            taxBeforeCredit: taxBeforeCredit,
            creditApplied: creditApplied,
            family: family,
            spouseCreditApplied: spouseCreditApplied,
            childCredit: childCredit,
            childBonus: bonusWithheld == nil ? rest : 0,
            bonusWithheld: bonusWithheld,
            tax: taxAfterCredits - childCredit,
            social: socialAssessment(dz: DZ, mainMonths: months.main, secondaryMonths: months.secondary, rules: rules),
            health: healthAssessment(dz: DZ, minimumMonths: months.healthMinimum, rules: rules)
        )
    }

    /// The levies of one counted income, with the steps between.
    private nonisolated struct Liabilities {
        var P: Int64
        var expenseCap: Int64
        var uncappedExpenses: Int64
        var V: Int64
        var expensesCapped: Bool
        var DZ: Int64
        var deductionLines: [DeductionLine]
        var deductionsTotal: Int64
        var B: Int64
        var taxBaseInLowBand: Int64
        var taxBaseInHighBand: Int64
        var taxBeforeCredit: Int64
        var creditApplied: Int64
        var family: FamilyCredits
        var spouseCreditApplied: Int64
        var childCredit: Int64
        var childBonus: Int64
        var bonusWithheld: BonusWithholding?
        var tax: Int64
        var social: SocialAssessment
        var health: HealthAssessment

        /// The tax less the tax bonus: negative when a bonus is paid.
        var netTax: Int64 {
            tax - childBonus
        }

        /// The three levies together, the tax less the bonus.
        var total: Int64 {
            netTax + social.insurance + health.insurance
        }

        /// What `authority` gets: the tax office the tax less the bonus.
        func amount(for authority: Authority) -> Int64 {
            switch authority {
            case .tax: netTax
            case .social: social.insurance
            case .health: health.insurance
            }
        }
    }

    /// Why `rest`, what the child benefit leaves after its credit, is not paid as a tax bonus, or nil when it is paid
    /// or nothing is left. A bonus is paid when it is at least 100 Kč (§ 35c odst. 3 zákona č. 586/1992 Sb.) and the
    /// income `P`, that of § 7 received by the as-of day, is at least six minimum wages (§ 35c odst. 4). A convention
    /// chosen here, not a legal rule: the income is the one the engine counts, rounded half-up to whole Kč once. When
    /// both conditions fail, the bonus under 100 Kč is the reason given, because more income would only make it
    /// smaller.
    private static func bonusWithholding(of rest: Int64, income P: Int64, rules: TaxRules) -> BonusWithholding? {
        guard rest > 0 else { return nil }
        if rest < rules.bonusMinimum {
            return .belowMinimum
        }
        if P < rules.bonusIncomeThreshold {
            return .incomeBelowThreshold(rules.bonusIncomeThreshold)
        }
        return nil
    }

    // MARK: Thresholds

    /// The thresholds that the income between the levies `without` a receipt and `with` it reaches, and how much of it
    /// is past each. A receipt which lowers the income counts what it takes away. The income of the tax bonus is a
    /// step: it is named only when the receipt brings the bonus (`bonusCrossing(without:with:rules:)`).
    ///
    /// Once an income is past a threshold, every higher income is too. So the first crown past it is found by halving
    /// the span between the two incomes, with the levies worked out by the same function as every other figure.
    private static func crossings(
        without: Liabilities,
        with: Liabilities,
        months: MonthCounts,
        input: YearInput,
        rules: TaxRules
    ) -> [ThresholdCrossing] {
        let (low, high) = without.P <= with.P ? (without, with) : (with, without)
        guard low.P < high.P else { return [] }
        return LevyThreshold.allCases.compactMap { threshold in
            if threshold == .bonusIncome {
                return bonusCrossing(without: without, with: with, rules: rules)
            }
            guard isPast(threshold, high, rules: rules) else { return nil }
            let limit = limit(of: threshold, high, input: input, rules: rules)
            if isPast(threshold, low, rules: rules) {
                return ThresholdCrossing(threshold: threshold, limit: limit, extent: .whole)
            }
            // The first income past the threshold is above `low.P` and at most `high.P`.
            var below = low.P
            var past = high.P
            while past - below > 1 {
                let middle = below + (past - below) / 2
                let levies = liabilities(incomeHalere: middle * 100, months: months, input: input, rules: rules)
                if isPast(threshold, levies, rules: rules) {
                    past = middle
                } else {
                    below = middle
                }
            }
            // An income that ends exactly at the threshold has no crown past it.
            let amount = high.P - past
            return amount > 0 ? ThresholdCrossing(threshold: threshold, limit: limit, extent: .part(amount)) : nil
        }
    }

    /// The income of the tax bonus, when the receipt brings the bonus: without it the income is below six minimum
    /// wages, which is why what the child benefit leaves after its credit is not paid, and with it the bonus is paid.
    /// Nil otherwise, also for a receipt after it, which is levied as one before it is. How much of the income is past
    /// it is counted as for the other thresholds; the income that ends exactly at it brings the bonus too.
    private static func bonusCrossing(without: Liabilities, with: Liabilities, rules: TaxRules) -> ThresholdCrossing? {
        guard case .incomeBelowThreshold = without.bonusWithheld, with.childBonus > 0 else { return nil }
        let limit = rules.bonusIncomeThreshold
        return ThresholdCrossing(
            threshold: .bonusIncome, limit: limit, extent: .part(with.P - limit), bonus: with.childBonus)
    }

    /// Whether the levies of an income are past `threshold`: the income is six minimum wages or more, the expenses at
    /// the percentage are the cap or more, part of the tax base is taxed at 23 %, or the social base is at its maximum.
    private static func isPast(_ threshold: LevyThreshold, _ levies: Liabilities, rules: TaxRules) -> Bool {
        switch threshold {
        case .bonusIncome: levies.P >= rules.bonusIncomeThreshold
        case .expenseCap: levies.uncappedExpenses >= levies.expenseCap
        case .taxBand: levies.taxBaseInHighBand > 0
        case .socialMaximum: levies.social.base >= levies.social.maximumBase
        }
    }

    /// The threshold in whole Kč, in its own terms (`ThresholdCrossing.limit`).
    private static func limit(
        of threshold: LevyThreshold,
        _ levies: Liabilities,
        input: YearInput,
        rules: TaxRules
    ) -> Int64 {
        switch threshold {
        case .bonusIncome: rules.bonusIncomeThreshold
        // The income whose percentage is the cap: 2 000 000 Kč at every percentage.
        case .expenseCap: levies.expenseCap * 100 / Int64(input.expensePercent)
        case .taxBand: rules.taxBandThreshold
        case .socialMaximum: levies.social.maximumBase
        }
    }

    // MARK: Deductions

    /// Each deduction the law allows from the tax base `taxBase` (ZD), with its limit, in the order mortgage interest,
    /// the retirement products, gifts (§ 15 zákona č. 586/1992 Sb.).
    private static func deductionLines(_ claims: Deductions, taxBase: Int64, rules: TaxRules) -> [DeductionLine] {
        // Mortgage interest: the household's yearly cap, a twelfth of it for each month in which interest was paid
        // (§ 15 odst. 3 and 4 zákona č. 586/1992 Sb.). Both caps are multiples of 12, so nothing is actually rounded.
        let mortgageLimit = DecimalMath.floor(
            Decimal(claims.mortgageCap.annualCap) * Decimal(claims.mortgageMonths) / 12
        )
        var lines = [
            DeductionLine(
                kind: .mortgageInterest,
                claimed: claims.mortgageInterestPaid,
                allowed: min(claims.mortgageInterestPaid, mortgageLimit),
                limit: mortgageLimit
            )
        ]

        // Retirement products (§ 15 zákona č. 586/1992 Sb.), with the limits of the year.
        switch rules.retirementLimit {
        case .separate(let pensionSavingsLimit, let lifeInsuranceLimit):
            // Pension savings and life insurance each have a limit; DIP and long-term care insurance do not exist yet,
            // so they count for nothing.
            lines.append(
                DeductionLine(
                    kind: .pensionSavings,
                    claimed: claims.pensionSavings,
                    allowed: min(claims.pensionSavings, pensionSavingsLimit),
                    limit: pensionSavingsLimit
                )
            )
            lines.append(
                DeductionLine(
                    kind: .lifeInsurance,
                    claimed: claims.lifeInsurance,
                    allowed: min(claims.lifeInsurance, lifeInsuranceLimit),
                    limit: lifeInsuranceLimit
                )
            )
        case .combined(let limit):
            // One limit covers pension savings, life insurance, DIP and long-term care insurance together.
            let claimed = claims.pensionSavings + claims.lifeInsurance + claims.dip + claims.longTermCare
            lines.append(
                DeductionLine(kind: .retirementProducts, claimed: claimed, allowed: min(claimed, limit), limit: limit)
            )
        }

        // Gifts count when they are more than 2 % of the tax base or at least 1 000 Kč (§ 15 odst. 1 zákona
        // č. 586/1992 Sb.), up to 30 % of the tax base rounded down to whole Kč (zákon č. 128/2022 Sb., § 1 odst. 1,
        // extended by zákon č. 349/2023 Sb., Čl. CVII, and zákon č. 24/2025 Sb., Čl. X).
        let giftsLimit = DecimalMath.floor(TaxRules.giftsCapPercent * Decimal(max(0, taxBase)))
        let giftsCount = claims.gifts >= TaxRules.giftsMinimumKc
            || Decimal(claims.gifts) > TaxRules.giftsMinimumPercent * Decimal(taxBase)
        lines.append(
            DeductionLine(
                kind: .gifts,
                claimed: claims.gifts,
                allowed: giftsCount ? min(claims.gifts, giftsLimit) : 0,
                limit: giftsLimit
            )
        )
        return lines
    }

    // MARK: Months

    /// The counted months: those of main and of secondary activity, and those in which the health minimum applies.
    private nonisolated struct MonthCounts {
        var main = 0
        var secondary = 0
        var healthMinimum = 0
    }

    /// Counts the months from January through `lastMonth`. A month without activity counts for nothing; an active month
    /// counts for the health minimum unless it is exempt.
    private static func monthCounts(_ input: YearInput, through lastMonth: Int) -> MonthCounts {
        var counts = MonthCounts()
        for month in 1...lastMonth {
            switch input.months[month - 1] {
            case .inactive:
                continue
            case .main:
                counts.main += 1
            case .secondary:
                counts.secondary += 1
            }
            if !input.healthExemptMonths.contains(month) {
                counts.healthMinimum += 1
            }
        }
        return counts
    }

    // MARK: Advances

    /// The balance with one authority: the advances of January through the as-of month are paid, the later ones are
    /// planned. The tax office's liability is the net tax, so a tax bonus is a negative liability that comes back
    /// together with the advances paid.
    private static func balance(
        _ authority: Authority,
        liability: Int64,
        plan: [Int64],
        asOfMonth: Int
    ) -> AuthorityBalance {
        let paid = plan[..<asOfMonth].reduce(0, +)
        let planned = plan[asOfMonth...].reduce(0, +)
        let remaining = max(0, liability - paid)
        let leavesViaPlannedAdvances = min(remaining, planned)
        return AuthorityBalance(
            authority: authority,
            liability: liability,
            advancesPaid: paid,
            remaining: remaining,
            overpayment: max(0, paid - liability),
            plannedAfterAsOf: planned,
            leavesViaPlannedAdvances: leavesViaPlannedAdvances,
            settlement: remaining - leavesViaPlannedAdvances
        )
    }

    private static func advances(of authority: Authority, in plan: AdvancePlan) -> [Int64] {
        switch authority {
        case .tax: plan.tax
        case .social: plan.social
        case .health: plan.health
        }
    }

    // MARK: Helpers

    /// The income the marginal rate adds: 100 000 Kč.
    private static let marginalStepKc: Int64 = 100_000
    private static let marginalStepHalere = marginalStepKc * 100

    /// A difference in levies per crown of the marginal step: 15 000 Kč more on 100 000 Kč more income is 0.15. Exact,
    /// because the step is a power of ten.
    private static func marginalRate(_ difference: Int64) -> Decimal {
        Decimal(difference) / Decimal(marginalStepKc)
    }

    /// 29.2 % of the base, rounded up to whole Kč (§ 7 zákona č. 589/1992 Sb.).
    private static func socialInsurance(of base: Int64) -> Int64 {
        DecimalMath.ceil(TaxRules.socialRate * Decimal(base))
    }

    /// An amount in Kč with at most two decimal places, in haléře. Traps if a haléř would have to be rounded, because
    /// the health base is never rounded.
    private static func halere(_ kc: Decimal) -> Int64 {
        let amount = kc * 100
        let whole = DecimalMath.floor(amount)
        precondition(Decimal(whole) == amount, "The amount has a fraction of a haléř.")
        return whole
    }

    /// `receipts` without `receipt`. A receipt of an invoice or an income adjustment is identified by it: an invoice
    /// has one payment (partial payments are not modelled), so every receipt of the same invoice or adjustment is a
    /// version of this one and is left out, whatever its amount or day. A synthetic receipt has no identity, so only
    /// one equal receipt is left out, if there is one.
    private static func receipts(_ receipts: [Receipt], without receipt: Receipt) -> [Receipt] {
        var others = receipts
        switch receipt.source {
        case .invoice, .adjustment:
            others.removeAll { $0.source == receipt.source }
        case .synthetic:
            if let index = others.firstIndex(of: receipt) {
                others.remove(at: index)
            }
        }
        return others
    }

    /// The receipts of `year` received on or before `asOf`.
    private static func countedReceipts(_ receipts: [Receipt], year: Int, through asOf: CivilDate) -> [Receipt] {
        receipts.filter { $0.day.year == year && $0.day <= asOf }
    }

    private static func netTotal(_ receipts: [Receipt]) -> Int64 {
        receipts.reduce(0) { $0 + $1.czkNetHalere }
    }

    private static func isAdjustment(_ receipt: Receipt) -> Bool {
        switch receipt.source {
        case .adjustment: true
        case .invoice, .synthetic: false
        }
    }

    /// Traps on an input that would make every number wrong, because a wrong number shown with confidence is worse
    /// than none. The forms that edit a year validate what is typed, so this only catches mistakes in the code.
    private static func checkInput(_ input: YearInput) {
        precondition(input.months.count == 12, "A year has twelve months of activity.")
        precondition(input.healthExemptMonths.allSatisfy { (1...12).contains($0) }, "Health-exempt months are 1 to 12.")
        precondition(
            TaxRules.expenseCap(percent: input.expensePercent) != nil,
            "Flat-rate expenses are 80, 60, 40 or 30 %."
        )
        for plan in [input.advances.social, input.advances.health, input.advances.tax] {
            precondition(plan.count == 12, "An advance plan has twelve months.")
            precondition(plan.allSatisfy { $0 >= 0 }, "Advances are not negative.")
        }
        let claims = input.deductions
        precondition((0...12).contains(claims.mortgageMonths), "Mortgage interest is paid in 0 to 12 months of a year.")
        let amounts = [
            claims.mortgageInterestPaid, claims.lifeInsurance, claims.pensionSavings, claims.dip, claims.longTermCare,
            claims.gifts,
        ]
        precondition(amounts.allSatisfy { $0 >= 0 }, "Deductions are not negative.")
        precondition(
            input.family.isValid,
            "A family's months are 1 to 12 with from no later than to, an order is 1 or more and no income is negative."
        )
    }
}

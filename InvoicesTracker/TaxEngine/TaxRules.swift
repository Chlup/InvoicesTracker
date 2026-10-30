import Foundation

/// How much a taxpayer may deduct from the tax base for retirement products (§ 15 zákona č. 586/1992 Sb.).
nonisolated enum RetirementLimit: Sendable, Hashable {
    /// Pension savings and life insurance each have their own yearly limit in Kč. This is how 2022 and 2023 work.
    case separate(pensionSavings: Int64, lifeInsurance: Int64)

    /// One yearly limit in Kč for pension savings, life insurance, DIP and long-term care insurance together. This is
    /// how it works from 2024.
    case combined(Int64)
}

/// The legal parameters of one tax year for an OSVČ (self-employed person) who taxes cash income with flat-rate
/// expenses: income tax, social insurance and health insurance.
///
/// Amounts are whole crowns unless stated otherwise. Rates and shares are fractions: `0.15` is 15 %. The values of each
/// year are in `TaxRules+Years.swift`, together with where they come from.
nonisolated struct TaxRules: Sendable, Hashable {
    /// The year these rules apply to.
    let year: Int

    /// The average wage (průměrná mzda) of the year, in Kč a month. The limits below are multiples of it.
    let averageWage: Int64

    /// The rounded tax base above which the 23 % rate applies: 48 times the average wage in 2022 and 2023, 36 times
    /// from 2024.
    let taxBandThreshold: Int64

    /// The yearly tax credit for the taxpayer (sleva na poplatníka). It is never prorated.
    let taxpayerCredit: Int64

    /// The limit on the deduction for retirement products.
    let retirementLimit: RetirementLimit

    /// Whether DIP (the long-term investment product) and long-term care insurance exist as deductible items. They
    /// exist from 2024.
    let hasDIPAndLongTermCare: Bool

    /// The share of the profit that is the social insurance assessment base: `0.55` is 55 %.
    let socialAssessmentPercent: Decimal

    /// The minimum monthly social insurance assessment base of a main activity, in Kč.
    let socialMinimumMonthlyMain: Int64

    /// The minimum monthly social insurance assessment base of a secondary activity, in Kč.
    let socialMinimumMonthlySecondary: Int64

    /// The decisive amount (rozhodná částka) for a secondary activity, in Kč a year: the profit from a secondary
    /// activity must reach it for the activity to be insured.
    let socialDecisiveAmount: Int64

    /// The maximum yearly social insurance assessment base, in Kč. It is 48 times the average wage and is not
    /// prorated.
    let socialMaximumAnnualBase: Int64

    /// The minimum monthly health insurance assessment base, in Kč. It is a `Decimal` because it can be a half crown.
    let healthMinimumMonthlyBase: Decimal

    /// Whether a month in which the person cared full-day for a child under 7 is exempt from the health insurance
    /// minimum. This exemption exists from 2022 to 2025 only.
    let childCareHealthExemption: Bool

    /// The spouse credit (sleva na manžela / manželku) of one month, in Kč: a twelfth of the yearly amount. A month in
    /// which the spouse holds the ZTP/P card counts twice.
    let spouseCreditMonthly: Int64

    /// The child tax benefit of one month, in Kč, of the first child, the second, and the third and every further one,
    /// in this order. A month in which the child holds the ZTP/P card counts twice.
    let childMonthly: [Int64]

    /// The minimum wage in force on 1 January, in Kč a month. The tax bonus asks for an income of six times as much.
    let minimumWage: Int64

    /// The most the spouse's own income for the year may be for the spouse credit, in Kč.
    let spouseIncomeLimit: Int64

    /// Whether a month counts for the spouse credit only with a child under three in the household, as it does from
    /// 2024.
    let spouseNeedsYoungChild: Bool

    /// The smallest tax bonus that is paid, in Kč.
    let bonusMinimum: Int64

    /// When the values were checked against the primary sources, as a sentence the app can show.
    let verification: String

    /// The legal sources of the values, one line each.
    let sources: [String]

    // MARK: Constants of every supported year

    /// The years that have rules.
    static let supportedYears = 2022...2026

    /// Income tax rate up to `taxBandThreshold` (§ 16 odst. 1 zákona č. 586/1992 Sb.).
    static let taxRateLow = DecimalMath.decimal("0.15")!

    /// Income tax rate on the part of the base above `taxBandThreshold` (§ 16 odst. 1 zákona č. 586/1992 Sb.).
    static let taxRateHigh = DecimalMath.decimal("0.23")!

    /// Social insurance rate of an OSVČ (§ 7 zákona č. 589/1992 Sb.).
    static let socialRate = DecimalMath.decimal("0.292")!

    /// Health insurance rate (§ 2 odst. 2 zákona č. 592/1992 Sb.).
    static let healthRate = DecimalMath.decimal("0.135")!

    /// The share of the profit that is the health insurance assessment base (§ 3a zákona č. 592/1992 Sb.).
    static let healthAssessmentPercent = DecimalMath.decimal("0.5")!

    /// The most of the tax base that gifts may take off, in every year from 2022 to 2026. The income tax act's own cap
    /// is 15 %, but the special act prevails (zákon č. 128/2022 Sb., § 1 odst. 1, extended by zákon č. 349/2023 Sb.,
    /// Čl. CVII, and zákon č. 24/2025 Sb., Čl. X).
    static let giftsCapPercent = DecimalMath.decimal("0.30")!

    /// Gifts are deductible when their total is at least this many Kč; below that, the total must be more than
    /// `giftsMinimumPercent` of the tax base (§ 15 odst. 1 zákona č. 586/1992 Sb.).
    static let giftsMinimumKc: Int64 = 1_000

    /// Gifts are deductible when their total is more than this share of the tax base, even if it is below
    /// `giftsMinimumKc` (§ 15 odst. 1 zákona č. 586/1992 Sb.).
    static let giftsMinimumPercent = DecimalMath.decimal("0.02")!

    /// The cap in Kč on the flat-rate expenses at the given percentage: 80 % up to 1 600 000, 60 % up to 1 200 000,
    /// 40 % up to 800 000 and 30 % up to 600 000 (§ 7 odst. 7 zákona č. 586/1992 Sb.). Nil for any other percentage.
    static func expenseCap(percent: Int) -> Int64? {
        switch percent {
        case 80: 1_600_000
        case 60: 1_200_000
        case 40: 800_000
        case 30: 600_000
        default: nil
        }
    }

    // MARK: Lookup

    /// The rules of `year`, and whether they are only an estimate.
    ///
    /// A year outside `supportedYears` gets the rules of the nearest supported year with `isEstimate` set: 2027 uses
    /// the 2026 rules and 2021 the 2022 rules. The returned rules keep their own `year`.
    static func forYear(_ year: Int) -> (rules: TaxRules, isEstimate: Bool) {
        let nearest = min(max(year, supportedYears.lowerBound), supportedYears.upperBound)
        guard let rules = byYear[nearest] else {
            preconditionFailure("The rules table has no entry for \(nearest).")
        }
        return (rules, nearest != year)
    }

    // MARK: Decisive amount

    /// One twelfth of the decisive amount, rounded up to whole crowns: ⌈D ÷ 12⌉.
    var decisiveTwelfth: Int64 {
        let (quotient, remainder) = socialDecisiveAmount.quotientAndRemainder(dividingBy: 12)
        return remainder > 0 ? quotient + 1 : quotient
    }

    /// The decisive amount reduced for the months in which there was no secondary activity: D − k × ⌈D ÷ 12⌉, where
    /// k is the number of such months (§ 5b zákona č. 589/1992 Sb.). `k` must be 0 to 12.
    func reducedDecisiveAmount(monthsWithoutSecondary k: Int) -> Int64 {
        precondition((0...12).contains(k), "A year has 0 to 12 months without a secondary activity.")
        return socialDecisiveAmount - Int64(k) * decisiveTwelfth
    }

    // MARK: Tax bonus

    /// The income the tax bonus asks for, in Kč: six times the minimum wage (§ 35c odst. 4 zákona č. 586/1992 Sb.).
    var bonusIncomeThreshold: Int64 {
        6 * minimumWage
    }
}

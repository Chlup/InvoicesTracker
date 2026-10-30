import Foundation

/// What a year leaves of its income after the tax, the social insurance and the health insurance ("čistý příjem"), as
/// of the day its result was worked out, and the average of that per month, in whole Kč. The flat-rate expenses are not
/// taken off, as they are no money spent. Nor are the advances: the levies are what the income owes, not what has been
/// paid of them so far.
nonisolated struct NetIncome: Sendable, Hashable {
    /// The income counted, before the flat-rate expenses (`TaxResult.P`).
    let incomeKc: Int64

    /// The three levies together (`TaxResult.liabilityTotal`). The tax is the net tax, so a tax bonus lowers them. They
    /// can be more than the income, because the insurance has a minimum.
    let leviesKc: Int64

    /// The months that `monthlyKc` is the average of, 1 to 12: all twelve of a whole year, otherwise the months from
    /// January through the month of the day the result was worked out for.
    let months: Int

    /// Whether the result is of a whole year: it was worked out for 31 December. Any other day of December is a year in
    /// progress that has twelve months so far.
    let isWholeYear: Bool

    /// What the income leaves after the levies. It is negative when the levies are more than the income.
    var yearKc: Int64 {
        incomeKc - leviesKc
    }

    /// `yearKc` over `months`, with a half rounded away from zero (`DecimalMath.halfUp`), so a loss rounds as a gain
    /// does.
    var monthlyKc: Int64 {
        DecimalMath.halfUp(Decimal(yearKc) / Decimal(months))
    }
}

nonisolated extension NetIncome {
    /// The net income of `result`: its income and its levies, over twelve months when it was worked out for 31 December
    /// and over the months through the month of its day otherwise. The initializer is in an extension so that the
    /// struct keeps its memberwise one.
    init(_ result: TaxResult) {
        let isWholeYear = result.asOf.month == 12 && result.asOf.day == 31
        self.init(
            incomeKc: result.P, leviesKc: result.liabilityTotal, months: isWholeYear ? 12 : result.asOf.month,
            isWholeYear: isWholeYear)
    }
}

/// The part of the income that each levy takes, and what is left, in tenths of a percent of the income (118 is 11,8 %).
/// The parts are whole tenths that add up to the share of the three levies together, so the percentages shown add up as
/// well.
nonisolated struct IncomeShares: Sendable, Hashable {
    /// The three levies together. It is negative when a tax bonus is more than the two insurances.
    let leviesTenths: Int64

    /// The part of each authority, adding up to `leviesTenths`. The tax office's is of the net tax, so it is negative
    /// while a tax bonus is paid.
    let tenths: [Authority: Int64]

    /// What the income leaves after the levies: 1 000 less `leviesTenths`.
    var netTenths: Int64 {
        1_000 - leviesTenths
    }

    /// The shares of the levies in the income of `result`, or nil when the income is not above zero, as there is
    /// nothing for them to take a part of. Each part is rounded down, and the tenths that are then left go to the
    /// largest remainders (`DecimalMath.roundedKeepingSum`).
    init?(_ result: TaxResult) {
        guard result.P > 0 else { return nil }
        let income = Decimal(result.P)
        let parts = Authority.allCases.map { Decimal(result.balance($0).liability) * 1_000 / income }
        let rounded = DecimalMath.roundedKeepingSum(parts, total: Decimal(result.liabilityTotal) * 1_000 / income)
        leviesTenths = rounded.total
        tenths = Dictionary(uniqueKeysWithValues: zip(Authority.allCases, rounded.parts))
    }
}

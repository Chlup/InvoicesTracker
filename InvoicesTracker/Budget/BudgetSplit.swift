import Foundation

/// One of the four parts a net income is divided into, in the order the budget shows them.
nonisolated enum BudgetCategory: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    /// Náklady: what the person must pay.
    case costs
    /// Útrata: what the person spends.
    case spending
    /// Úspory: what is put aside.
    case savings
    /// Investice: what is invested.
    case investments
}

/// How a category is held: by a share of the net income, or by a fixed amount of whole Kč a month.
///
/// In JSON a share is `{"share":"0.15"}`, the decimal written as a string so that it is stored without loss, and a
/// fixed amount is `{"fixed":25000}`.
nonisolated enum BudgetHolding: Hashable, Sendable, Codable {
    /// A fraction of the net income, 0 to 1.
    case share(Decimal)
    /// Whole Kč a month, never negative.
    case fixed(Int64)

    private enum CodingKeys: String, CodingKey {
        case share
        case fixed
    }

    /// Reads a holding written by `encode(to:)`. Anything else, such as a share that is not a number, is an error.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.share) {
            let text = try container.decode(String.self, forKey: .share)
            guard let value = Decimal(string: text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .share, in: container, debugDescription: "The share is not a number.")
            }
            self = .share(value)
        } else {
            self = .fixed(try container.decode(Int64.self, forKey: .fixed))
        }
    }

    /// Writes the share as text and the fixed amount as a number.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .share(let share):
            try container.encode(share.description, forKey: .share)
        case .fixed(let kc):
            try container.encode(kc, forKey: .fixed)
        }
    }
}

/// What a `BudgetSplit` makes of a net income: the amount of every category and the share each one is of the income.
nonisolated struct BudgetAllocation: Hashable, Sendable {
    /// The amount of all four categories in whole Kč. The remainder's can be negative.
    let amounts: [BudgetCategory: Int64]

    /// The share of the net income of each category where there is one: always for a share-held category, and for a
    /// fixed one and the remainder only when the net income is above zero.
    let shares: [BudgetCategory: Decimal]

    /// The category that gets what the others leave.
    let remainder: BudgetCategory

    /// How much the other categories take beyond the net income, 0 when the remainder is not below zero.
    var shortfall: Int64 {
        max(0, -(amounts[remainder] ?? 0))
    }
}

/// How a net income is divided among the four categories. Each is held by a share or a fixed amount, except one, the
/// remainder, which gets what the others leave. So changing any category changes only the remainder.
nonisolated struct BudgetSplit: Hashable, Sendable, Codable {
    /// The holding of each category. One missing reads as a share of 0, and the remainder's is ignored.
    var holdings: [BudgetCategory: BudgetHolding]

    /// The category that gets what the others leave.
    var remainder: BudgetCategory

    /// The split of a budget nobody has set up: nothing for costs, savings and investments, and all to spending.
    static let empty = BudgetSplit(
        holdings: [.costs: .fixed(0), .savings: .share(0), .investments: .share(0), .spending: .share(0)],
        remainder: .spending)

    /// The holding of `category`, a share of 0 when there is none.
    func holding(of category: BudgetCategory) -> BudgetHolding {
        holdings[category] ?? .share(0)
    }

    /// Divides `net`, in whole Kč. A share amount is the share of `net` rounded half away from zero, a fixed one is
    /// its amount times `fixedMultiplier` (1 for a month, 12 for a year), and the remainder is what is left of `net`.
    func allocation(net: Int64, fixedMultiplier: Int64) -> BudgetAllocation {
        var amounts: [BudgetCategory: Int64] = [:]
        var others: Int64 = 0
        for category in BudgetCategory.allCases where category != remainder {
            let amount: Int64
            switch holding(of: category) {
            case .share(let share):
                amount = DecimalMath.halfUp(Decimal(net) * share)
            case .fixed(let kc):
                amount = kc * fixedMultiplier
            }
            amounts[category] = amount
            others += amount
        }
        amounts[remainder] = net - others

        var shares: [BudgetCategory: Decimal] = [:]
        for category in BudgetCategory.allCases {
            if category != remainder, case .share(let share) = holding(of: category) {
                shares[category] = share
            } else if net > 0, let amount = amounts[category] {
                shares[category] = Decimal(amount) / Decimal(net)
            }
        }
        return BudgetAllocation(amounts: amounts, shares: shares, remainder: remainder)
    }

    /// The largest share `category` can have: the one at which the remainder reaches 0, so it takes what it holds now
    /// and what the remainder has to spare. With no net income to divide it is what the other share-held categories
    /// leave of the whole.
    func shareLimit(of category: BudgetCategory, net: Int64?) -> Decimal {
        if let net, net > 0 {
            let month = allocation(net: net, fixedMultiplier: 1)
            let own = month.amounts[category] ?? 0
            let spare = max(0, month.amounts[remainder] ?? 0)
            return Decimal(own + spare) / Decimal(net)
        }
        var taken: Decimal = 0
        for other in BudgetCategory.allCases where other != category && other != remainder {
            if case .share(let share) = holding(of: other) {
                taken += share
            }
        }
        return max(0, 1 - taken)
    }

    /// The split with `category` held by `share`, kept between 0 and `shareLimit(of:net:)`. The remainder is left as
    /// it is.
    func settingShare(_ share: Decimal, of category: BudgetCategory, net: Int64?) -> BudgetSplit {
        guard category != remainder else { return self }
        var result = self
        let limit = shareLimit(of: category, net: net)
        result.holdings[category] = .share(min(max(0, share), limit))
        return result
    }

    /// The split with `category` set to `kc` a month. A share-held category gets the share that makes that amount of
    /// `net`, kept to what the remainder can spare, and stays as it is when there is no net income to divide. A fixed
    /// one gets the amount itself, never kept down. The remainder is left as it is.
    func settingAmount(_ kc: Int64, of category: BudgetCategory, net: Int64?) -> BudgetSplit {
        guard category != remainder else { return self }
        var result = self
        switch holding(of: category) {
        case .share:
            guard let net, net > 0 else { return self }
            let month = allocation(net: net, fixedMultiplier: 1)
            let own = month.amounts[category] ?? 0
            let spare = max(0, month.amounts[remainder] ?? 0)
            let amount = min(max(0, kc), own + spare)
            result.holdings[category] = .share(Decimal(amount) / Decimal(net))
        case .fixed:
            result.holdings[category] = .fixed(max(0, kc))
        }
        return result
    }

    /// The split with `category` changed from a share to the fixed amount it comes to a month now, or from a fixed
    /// amount to the share it is of `net`, so no number changes. Without a net income to divide that amount, or share,
    /// is 0. The remainder is left as it is.
    func togglingFixed(_ category: BudgetCategory, net: Int64?) -> BudgetSplit {
        guard category != remainder else { return self }
        var result = self
        let month = net.flatMap { $0 > 0 ? allocation(net: $0, fixedMultiplier: 1) : nil }
        switch holding(of: category) {
        case .share:
            result.holdings[category] = .fixed(month?.amounts[category] ?? 0)
        case .fixed:
            result.holdings[category] = .share(month?.shares[category] ?? 0)
        }
        return result
    }

    /// The split with `category` as the remainder. The old remainder is held by the share it comes to now (0 when
    /// there is no net income to divide, or it is below zero), so no number changes. A category that was fixed gets a
    /// share of 0, as its holding is ignored while it is the remainder.
    func withRemainder(_ category: BudgetCategory, net: Int64?) -> BudgetSplit {
        guard category != remainder else { return self }
        var result = self
        let month = net.flatMap { $0 > 0 ? allocation(net: $0, fixedMultiplier: 1) : nil }
        result.holdings[remainder] = .share(max(0, month?.shares[remainder] ?? 0))
        if case .fixed = holding(of: category) {
            result.holdings[category] = .share(0)
        }
        result.remainder = category
        return result
    }
}

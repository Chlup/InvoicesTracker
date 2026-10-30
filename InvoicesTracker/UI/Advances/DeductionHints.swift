import Foundation

/// How much of a limit the claim uses, for a line and a bar under the fields of the retirement products.
nonisolated struct LimitUse: Sendable, Hashable, Identifiable {
    /// What the limit is for: "Společný limit", or one of the products.
    var title: String

    /// "6 480 z 48 000 Kč": the claim and the limit.
    var usedText: String

    /// How full the bar is, from 0 to 1 000: the claim as a share of the limit in thousandths, at most the whole limit.
    var usedPermille: Int

    var id: String {
        title
    }
}

/// The sentences under the fields of the deductions, worked out from the lines of the tax engine for the year, so they
/// say what the engine counts. The amounts are texts in whole Kč with a no-break space before "Kč".
nonisolated struct DeductionHints: Sendable, Hashable {
    /// What the interest allows: "150 000 Kč".
    var mortgageAllowed: String

    /// What of the interest is over the limit and does not count: "100 000 Kč". Nil when it is within the limit.
    var mortgageOverLimit: String?

    /// "limit 150 000 Kč za 12 měsíců": the limit for the months of the interest.
    var mortgageLimit: String

    /// The limits of the retirement products: one that they share from 2024, one each before.
    var retirementLimits: [LimitUse]

    /// What the retirement products allow together: "6 480 Kč".
    var retirementAllowed: String

    /// Which gifts count, or why the gifts that are claimed do not.
    var giftsNote: String

    /// What the gifts allow: "20 000 Kč".
    var giftsAllowed: String

    /// The hints for the deductions in `lines`, the lines of a result of the engine, and the months of interest in
    /// `deductions`.
    static func make(from lines: [DeductionLine], deductions: Deductions) -> DeductionHints {
        let mortgage = lines.first { $0.kind == .mortgageInterest }
        let mortgageLimit = mortgage?.limit ?? 0
        let mortgageClaimed = mortgage?.claimed ?? 0

        let retirement = lines.filter { [.retirementProducts, .pensionSavings, .lifeInsurance].contains($0.kind) }
        let limits = retirement.map { line in
            let limit = line.limit ?? 0
            return LimitUse(
                title: line.kind == .retirementProducts ? "Společný limit" : line.kind.title,
                usedText: CzechFormat.grouped(line.claimed) + " z " + CzechFormat.wholeKc(limit),
                usedPermille: limit > 0 ? Int(min(1_000, line.claimed * 1_000 / limit)) : 0)
        }

        let gifts = lines.first { $0.kind == .gifts }
        let giftsClaimed = gifts?.claimed ?? 0
        let giftsAllowed = gifts?.allowed ?? 0
        return DeductionHints(
            mortgageAllowed: CzechFormat.wholeKc(mortgage?.allowed ?? 0),
            mortgageOverLimit: mortgageClaimed > mortgageLimit
                ? CzechFormat.wholeKc(mortgageClaimed - mortgageLimit) : nil,
            mortgageLimit: "limit " + CzechFormat.wholeKc(mortgageLimit) + " za " + months(deductions.mortgageMonths),
            retirementLimits: limits,
            retirementAllowed: CzechFormat.wholeKc(retirement.reduce(0) { $0 + $1.allowed }),
            giftsNote: giftsClaimed > 0 && giftsAllowed == 0
                ? "pod minimem – neuplatní se" : "od 1 000 Kč (nebo nad 2 % základu), nejvýš 30 % základu",
            giftsAllowed: CzechFormat.wholeKc(giftsAllowed))
    }

    /// What to enter for pension savings: the amount the pension company certifies, which is the part of each monthly
    /// contribution above 1 000 Kč, and from 1. 7. 2024 above 1 700 Kč. The sentence names the contributions that count
    /// in `year`.
    static func pensionAdvice(year: Int) -> String {
        let thousand = CzechFormat.wholeKc(1_000)
        let seventeenHundred = CzechFormat.wholeKc(1_700)
        let contributions =
            switch year {
            case ...2023:
                "příspěvky nad \(thousand) měsíčně"
            case 2024:
                "příspěvky nad \(thousand) měsíčně, od 1.\u{00A0}7.\u{00A0}2024 nad \(seventeenHundred)"
            default:
                "příspěvky nad \(seventeenHundred) měsíčně"
            }
        return "U penzijního spoření zadejte částku z potvrzení penzijní společnosti (\(contributions))"
    }

    /// A number of months with the noun in the form Czech wants: "1 měsíc", "2 měsíce", "5 měsíců".
    static func months(_ count: Int) -> String {
        let noun =
            switch count {
            case 1: "měsíc"
            case 2...4: "měsíce"
            default: "měsíců"
            }
        return "\(count) \(noun)"
    }
}

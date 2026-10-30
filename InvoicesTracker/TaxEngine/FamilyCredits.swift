import Foundation

/// What a year says about a child, as the tax engine takes it: for the child tax benefit (daňové zvýhodnění na
/// vyživované dítě, § 35c zákona č. 586/1992 Sb.) and for the spouse credit's condition of a child under three
/// (§ 35bb).
nonisolated struct ChildFacts: Sendable, Hashable {
    /// The name that labels the child in the app.
    var label: String

    var birthDate: CivilDate

    /// The months of the year the child lived in the household, or nil when it did not live there that year.
    var household: MonthRange?

    /// Who claims the benefit for the child.
    var claimant: Claimant

    /// The child's order in the household, 1 or more: of the children who qualify in a month, the one with the lowest
    /// order is the first child.
    var order: Int

    /// The months in which the child held the ZTP/P card, or nil for none.
    var ztpp: MonthRange?

    /// The months of studies (soustavná příprava na budoucí povolání), or nil for none. They matter only in the months
    /// in which the child is an adult.
    var studies: MonthRange?
}

/// The family of a year as the tax engine takes it: the children and the spouse. An empty family changes nothing.
nonisolated struct FamilyFacts: Sendable, Hashable {
    /// The children. Their place in the list only settles a tie: of two children with the same order and the same date
    /// of birth, the one listed first ranks first. The app lists them as `Database.family(year:)` does, so that is the
    /// one with the lower id.
    var children: [ChildFacts] = []

    /// The spouse of the year, or nil for none.
    var spouse: SpouseYear? = nil
}

/// Why a child counts in no month of the year.
nonisolated enum ChildIneligibility: Sendable, Hashable {
    /// The child is born after the year, on this day.
    case notBornYet(CivilDate)

    /// The child does not live in the household that year.
    case notInHousehold

    /// The child is 26 by 1 January of the year, so no month of it counts, studies or not.
    case over26

    /// The child is an adult by 1 January of the year and no months of studies are entered.
    case adultNotStudying

    /// No month meets every condition for another reason: for example, the months in the household are before the
    /// birth, or the months of studies are outside them.
    case noQualifyingMonth
}

/// The child tax benefit of one child for the year, in whole Kč.
nonisolated struct ChildCredit: Sendable, Hashable {
    var label: String

    /// The months in which the child qualified, by the rate it had in them: 1 for the first child's rate, 2 for the
    /// second's and 3 for that of the third and every further child. Only rates with a month are keys. A child that the
    /// other parent claims has its months too, because it keeps its rank in the household.
    var monthsByRate: [Int: Int]

    /// How many of those months the child held the ZTP/P card, which doubles their amount.
    var ztppMonths: Int

    /// What the taxpayer gets for the child for the year: 0 when the other parent claims it.
    var amount: Int64

    /// Whether the other parent claims the child.
    var claimedByOther: Bool

    /// Why the child counts in no month of the year, or nil when it counts in at least one.
    var ineligibility: ChildIneligibility?
}

/// The spouse credit and the child tax benefit of a year, in whole Kč, before they are set against the tax.
nonisolated struct FamilyCredits: Sendable, Hashable {
    /// The months the spouse credit counts: those on whose 1st the spouse is claimed, married and in the household,
    /// and, from 2024, a child under three lives in the household. None when the spouse's own income for the year is
    /// over the limit.
    var spouseMonths: Int

    /// How many of `spouseMonths` the spouse held the ZTP/P card, which doubles their amount.
    var spouseZTPPMonths: Int

    /// The months of the year on whose 1st a child under three lives in the household, whoever claims it: the condition
    /// of the spouse credit from 2024. They are counted in every year, with a spouse or without one.
    var spouseYoungChildMonths: Int

    /// The spouse credit: the monthly amount for each of `spouseMonths`, twice in a month with ZTP/P.
    var spouseCredit: Int64

    /// Each child of the family, in the order of `FamilyFacts.children`.
    var children: [ChildCredit]

    /// The child tax benefit the taxpayer claims: the children's amounts together.
    var childBenefit: Int64
}

/// Why what the child benefit leaves after its credit is not paid as a tax bonus (§ 35c odst. 3 and 4 zákona
/// č. 586/1992 Sb.).
nonisolated enum BonusWithholding: Sendable, Hashable {
    /// It is less than the smallest bonus that is paid, 100 Kč. More income only makes it smaller.
    case belowMinimum

    /// The income received by the as-of day is less than six minimum wages of the year, which is this many Kč.
    case incomeBelowThreshold(Int64)
}

nonisolated extension FamilyCredits {
    /// The spouse credit and the child tax benefit of `family` in `year`, under `rules`.
    ///
    /// Every month of the year is evaluated on its 1st (§ 35ba odst. 3 and § 35c odst. 10 zákona č. 586/1992 Sb.), ages
    /// included: a birthday on the 1st of a month is reached that day.
    ///
    /// A child counts in a month when it lives in the household, is born (the month of its birth counts whatever its
    /// day), is not 26 yet, and is a minor or studies in the month. The children who count in a month are ranked across
    /// both parents by their order, then the older first, then the one listed first. The first has the first child's
    /// rate, the second the second's, and every further child the third's; ZTP/P doubles the month. A child the other
    /// parent claims takes its rank but adds nothing to the taxpayer's benefit.
    ///
    /// The spouse counts in a month when claimed, married and in the household, and, where the rules ask for it (from
    /// 2024), with a child under three in the household: born on or before the 1st and three after it, claimed by
    /// either parent. The spouse's own income for the year must be within the limit.
    ///
    /// The months after the as-of day of a computation count as well: the conditions are taken as entered for the year.
    static func evaluate(_ family: FamilyFacts, year: Int, rules: TaxRules) -> FamilyCredits {
        let children = family.children
        var monthsByRate = [[Int: Int]](repeating: [:], count: children.count)
        var ztppMonths = [Int](repeating: 0, count: children.count)
        var amounts = [Int64](repeating: 0, count: children.count)
        var youngChildMonths = 0
        var spouseMonths = 0
        var spouseZTPPMonths = 0
        let spouse = family.spouse.flatMap { $0.claim && $0.ownIncomeKc <= rules.spouseIncomeLimit ? $0 : nil }

        for month in 1...12 {
            // The children who qualify in the month, the first child first.
            let ranked = children.indices
                .filter { children[$0].qualifies(inMonth: month, of: year) }
                .sorted { first, second in
                    (children[first].order, children[first].birthDate, first)
                        < (children[second].order, children[second].birthDate, second)
                }
            for (place, index) in ranked.enumerated() {
                let rate = min(place + 1, rules.childMonthly.count)
                monthsByRate[index][rate, default: 0] += 1
                var amount = rules.childMonthly[rate - 1]
                if children[index].ztpp?.contains(month) == true {
                    ztppMonths[index] += 1
                    amount *= 2
                }
                amounts[index] += amount
            }

            let youngChild = children.contains { $0.isUnderThree(onTheFirstOf: month, of: year) }
            if youngChild {
                youngChildMonths += 1
            }
            if let spouse, spouse.months.contains(month), youngChild || !rules.spouseNeedsYoungChild {
                spouseMonths += 1
                if spouse.ztpp?.contains(month) == true {
                    spouseZTPPMonths += 1
                }
            }
        }

        let credits = children.indices.map { index in
            let child = children[index]
            let claimedByOther = child.claimant == .otherParent
            return ChildCredit(
                label: child.label, monthsByRate: monthsByRate[index], ztppMonths: ztppMonths[index],
                amount: claimedByOther ? 0 : amounts[index], claimedByOther: claimedByOther,
                ineligibility: monthsByRate[index].isEmpty ? child.ineligibility(in: year) : nil)
        }
        return FamilyCredits(
            spouseMonths: spouseMonths, spouseZTPPMonths: spouseZTPPMonths, spouseYoungChildMonths: youngChildMonths,
            spouseCredit: rules.spouseCreditMonthly * Int64(spouseMonths + spouseZTPPMonths), children: credits,
            childBenefit: credits.reduce(0) { $0 + $1.amount })
    }
}

nonisolated extension FamilyFacts {
    /// Whether the engine takes the family: every range of months is one (`MonthRange.isValid`), every child's order is
    /// 1 or more, and the spouse's own income is not negative.
    var isValid: Bool {
        let childrenAreValid = children.allSatisfy { child in
            child.order >= 1 && [child.household, child.ztpp, child.studies].allSatisfy { $0?.isValid ?? true }
        }
        guard let spouse else { return childrenAreValid }
        return childrenAreValid && spouse.months.isValid && (spouse.ztpp?.isValid ?? true) && spouse.ownIncomeKc >= 0
    }
}

private nonisolated extension ChildFacts {
    /// Whether the child counts in `month` of `year`, on its 1st: in the household; born, the month of birth counting
    /// whatever the day; not 26 yet; and a minor, or an adult in a month of studies (§ 35c odst. 6 and 10 zákona
    /// č. 586/1992 Sb.).
    func qualifies(inMonth month: Int, of year: Int) -> Bool {
        guard household?.contains(month) == true, (birthDate.year, birthDate.month) <= (year, month),
            !hasReached(age: 26, onTheFirstOf: month, of: year)
        else {
            return false
        }
        return !hasReached(age: 18, onTheFirstOf: month, of: year) || studies?.contains(month) == true
    }

    /// Whether the child is under three and in the household on the 1st of `month` of `year`, as the spouse credit asks
    /// from 2024 (§ 35bb zákona č. 586/1992 Sb.): born on or before that day, and three after it.
    func isUnderThree(onTheFirstOf month: Int, of year: Int) -> Bool {
        household?.contains(month) == true && hasReached(age: 0, onTheFirstOf: month, of: year)
            && !hasReached(age: 3, onTheFirstOf: month, of: year)
    }

    /// Whether the child is `age` on the 1st of `month` of `year`: whether that birthday falls on that day or before
    /// it. Age 0 is the birth itself. A birthday on 29 February is reached by 1 March of any year, leap or not, and not
    /// by 1 February.
    func hasReached(age: Int, onTheFirstOf month: Int, of year: Int) -> Bool {
        (birthDate.year + age, birthDate.month, birthDate.day) <= (year, month, 1)
    }

    /// Why the child counts in no month of `year`, for a child that counts in none.
    func ineligibility(in year: Int) -> ChildIneligibility {
        if birthDate.year > year {
            return .notBornYet(birthDate)
        }
        if household == nil {
            return .notInHousehold
        }
        if hasReached(age: 26, onTheFirstOf: 1, of: year) {
            return .over26
        }
        if hasReached(age: 18, onTheFirstOf: 1, of: year) && studies == nil {
            return .adultNotStudying
        }
        return .noQualifyingMonth
    }
}

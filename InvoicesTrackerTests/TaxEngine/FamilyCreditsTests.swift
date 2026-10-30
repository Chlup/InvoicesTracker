import Foundation
import Testing
@testable import InvoicesTracker

/// The spouse credit and the child tax benefit of a year, month by month, as `FamilyCredits.evaluate` works them out:
/// every condition holds or not on the 1st of a month, ages included, and the month of a child's birth counts whatever
/// its day; the children who qualify in a month are ranked by their order across both parents. The amounts were worked
/// out by hand: 2 070 Kč a month for the spouse, and 1 267, 1 860 and 2 320 Kč a month for the first, the second and
/// the third and every further child, each doubled with ZTP/P.
struct FamilyCreditsTests {
    // MARK: The family of the tests

    /// A child in the household the whole year and claimed by me unless told otherwise, with no ZTP/P and no studies.
    private static func child(
        _ label: String, born day: String, order: Int, household: MonthRange? = MonthRange.wholeYear,
        claimant: Claimant = .me, ztpp: MonthRange? = nil, studies: MonthRange? = nil
    ) -> ChildFacts {
        ChildFacts(
            label: label, birthDate: civilDate(day), household: household, claimant: claimant, order: order, ztpp: ztpp,
            studies: studies)
    }

    /// Anna, born 3. 9. 2019.
    private static func anna(
        order: Int = 1, household: MonthRange? = MonthRange.wholeYear, claimant: Claimant = .me
    ) -> ChildFacts {
        child("Anna", born: "2019-09-03", order: order, household: household, claimant: claimant)
    }

    /// Tomáš, born 12. 4. 2024.
    private static func tomas(
        order: Int = 2, household: MonthRange? = MonthRange.wholeYear, claimant: Claimant = .me,
        ztpp: MonthRange? = nil
    ) -> ChildFacts {
        child("Tomáš", born: "2024-04-12", order: order, household: household, claimant: claimant, ztpp: ztpp)
    }

    /// Ema, born 15. 6. 2026.
    private static func ema(order: Int) -> ChildFacts {
        child("Ema", born: "2026-06-15", order: order)
    }

    /// A spouse who is claimed, married and in the household in `months`, without own income and without ZTP/P unless
    /// told otherwise.
    private static func spouse(
        months: MonthRange = MonthRange.wholeYear, ownIncome: Int64 = 0, ztpp: MonthRange? = nil, claim: Bool = true
    ) -> SpouseYear {
        SpouseYear(claim: claim, months: months, ownIncomeKc: ownIncome, ztpp: ztpp)
    }

    /// The credits of `children` and `spouse` in `year`, with the rules of the year.
    private static func credits(
        _ children: [ChildFacts], spouse: SpouseYear? = nil, year: Int = 2026
    ) -> FamilyCredits {
        FamilyCredits.evaluate(
            FamilyFacts(children: children, spouse: spouse), year: year, rules: TaxRules.forYear(year).rules)
    }

    /// What I get for a child of mine that qualifies: its months by rate, `ztpp` of them with ZTP/P, and the amount.
    private static func mine(_ label: String, _ months: [Int: Int], _ amount: Int64, ztpp: Int = 0) -> ChildCredit {
        ChildCredit(
            label: label, monthsByRate: months, ztppMonths: ztpp, amount: amount, claimedByOther: false,
            ineligibility: nil)
    }

    // MARK: The checked cases

    /// 2024: Anna is the first child all year (12 × 1 267 = 15 204 Kč). Tomáš is born on 12. 4., so April counts, and
    /// he is the second child from April on (9 × 1 860 = 16 740 Kč). The spouse counts from May, the first month on
    /// whose 1st Tomáš is born (8 × 2 070 = 16 560 Kč).
    @Test func year2024() {
        let credits = Self.credits([Self.anna(), Self.tomas()], spouse: Self.spouse(), year: 2024)

        #expect(credits.children == [Self.mine("Anna", [1: 12], 15_204), Self.mine("Tomáš", [2: 9], 16_740)])
        #expect(credits.childBenefit == 31_944)
        #expect(credits.spouseYoungChildMonths == 8)
        #expect(credits.spouseMonths == 8)
        #expect(credits.spouseZTPPMonths == 0)
        #expect(credits.spouseCredit == 16_560)
    }

    /// The spouse's own income for the year may be 68 000 Kč at most.
    @Test func spouseIncome70000GivesNoSpouseCredit() {
        let over = Self.credits([Self.anna(), Self.tomas()], spouse: Self.spouse(ownIncome: 70_000))
        #expect(over.spouseMonths == 0)
        #expect(over.spouseCredit == 0)
        // The child under three is there all the same, and so are the children's amounts.
        #expect(over.spouseYoungChildMonths == 12)
        #expect(over.childBenefit == 37_524)

        let atTheLimit = Self.credits([Self.anna(), Self.tomas()], spouse: Self.spouse(ownIncome: 68_000))
        #expect(atTheLimit.spouseMonths == 12)
        #expect(atTheLimit.spouseCredit == 24_840)
    }

    /// From 2024 a month counts for the spouse only with a child under three in the household. Anna was three in 2022.
    @Test(arguments: [2024, 2025, 2026])
    func withoutAChildUnder3ThereIsNoSpouseCreditFrom2024(_ year: Int) {
        let credits = Self.credits([Self.anna()], spouse: Self.spouse(), year: year)

        #expect(credits.spouseYoungChildMonths == 0)
        #expect(credits.spouseMonths == 0)
        #expect(credits.spouseCredit == 0)
        #expect(credits.childBenefit == 15_204)
    }

    /// 2022 and 2023 had no condition of a young child: a spouse claimed for the whole year gets 12 × 2 070 Kč.
    @Test func year2023NeedsNoYoungChild() {
        let credits = Self.credits([], spouse: Self.spouse(), year: 2023)

        #expect(credits.spouseMonths == 12)
        #expect(credits.spouseCredit == 24_840)
        #expect(Self.credits([], spouse: Self.spouse(), year: 2022).spouseCredit == 24_840)
    }

    /// Born 1. 3. 2007, the child is an adult the whole of 2026, so it counts only in the months of its studies.
    @Test func anAdultCountsOnlyInStudyMonths() {
        let studying = Self.child("Petr", born: "2007-03-01", order: 1, studies: MonthRange(from: 1, to: 6))
        #expect(Self.credits([studying]).children == [Self.mine("Petr", [1: 6], 7_602)])

        let notStudying = Self.credits([Self.child("Petr", born: "2007-03-01", order: 1)])
        #expect(notStudying.children.map(\.monthsByRate) == [[:]])
        #expect(notStudying.childBenefit == 0)
    }

    /// Ema, born 15. 6. 2026, is put first: from June she has the first rate and Anna and Tomáš move down a rate.
    /// Before June Anna is still the first child and Tomáš the second.
    @Test func orderOneForANewChildMovesTheOthersDown() {
        let credits = Self.credits([Self.anna(order: 2), Self.tomas(order: 3), Self.ema(order: 1)])

        #expect(
            credits.children == [
                Self.mine("Anna", [1: 5, 2: 7], 19_355), Self.mine("Tomáš", [2: 5, 3: 7], 25_540),
                Self.mine("Ema", [1: 7], 8_869),
            ])
        #expect(credits.childBenefit == 53_764)
    }

    /// Ema, born 15. 6. 2026, put third: 7 months at the third rate, and Anna and Tomáš keep theirs.
    @Test func aNewYoungestChildAtTheThirdRate() {
        let credits = Self.credits([Self.anna(), Self.tomas(), Self.ema(order: 3)])

        #expect(
            credits.children == [
                Self.mine("Anna", [1: 12], 15_204), Self.mine("Tomáš", [2: 12], 22_320),
                Self.mine("Ema", [3: 7], 16_240),
            ])
    }

    /// Anna is claimed by the other parent. She is still the household's first child, so Tomáš stays the second, and
    /// only he counts in my total.
    @Test func aChildClaimedByTheOtherParentKeepsItsRank() {
        let credits = Self.credits([Self.anna(claimant: .otherParent), Self.tomas()])

        #expect(
            credits.children == [
                ChildCredit(
                    label: "Anna", monthsByRate: [1: 12], ztppMonths: 0, amount: 0, claimedByOther: true,
                    ineligibility: nil),
                Self.mine("Tomáš", [2: 12], 22_320),
            ])
        #expect(credits.childBenefit == 22_320)
    }

    /// ZTP/P doubles the month's amount: with it the whole year Tomáš gets 2 × 22 320 Kč, and with it from March to May
    /// 22 320 + 3 × 1 860 Kč. A month of ZTP/P outside the household's months does not count.
    @Test func ztppDoubles() {
        let wholeYear = Self.credits([Self.anna(), Self.tomas(ztpp: MonthRange.wholeYear)])
        #expect(wholeYear.children.last == Self.mine("Tomáš", [2: 12], 44_640, ztpp: 12))
        #expect(wholeYear.childBenefit == 59_844)

        let spring = Self.credits([Self.anna(), Self.tomas(ztpp: MonthRange(from: 3, to: 5))])
        #expect(spring.children.last == Self.mine("Tomáš", [2: 12], 27_900, ztpp: 3))

        let halfYear = Self.credits([
            Self.anna(), Self.tomas(household: MonthRange(from: 1, to: 6), ztpp: MonthRange.wholeYear),
        ])
        #expect(halfYear.children.last == Self.mine("Tomáš", [2: 6], 22_320, ztpp: 6))
    }

    // MARK: Births and birthdays

    /// A child born on 1. 2. 2026 is born on the 1st of February, so the spouse counts from February.
    @Test func aChildBornOnTheFirstCountsForTheSpouseThatMonth() {
        let credits = Self.credits([Self.child("Ema", born: "2026-02-01", order: 1)], spouse: Self.spouse())

        #expect(credits.spouseYoungChildMonths == 11)
        #expect(credits.spouseMonths == 11)
        #expect(credits.spouseCredit == 22_770)
        #expect(credits.children == [Self.mine("Ema", [1: 11], 13_937)])
    }

    /// A child born on 15. 5. 2026 is not born on the 1st of May, so the spouse counts from June. The child's own
    /// benefit counts from May, the month of its birth.
    @Test func aChildBornOnTheFifteenthCountsForTheSpouseFromTheNextMonth() {
        let credits = Self.credits([Self.child("Ema", born: "2026-05-15", order: 1)], spouse: Self.spouse())

        #expect(credits.spouseYoungChildMonths == 7)
        #expect(credits.spouseMonths == 7)
        #expect(credits.spouseCredit == 14_490)
        #expect(credits.children == [Self.mine("Ema", [1: 8], 10_136)])
    }

    /// Born 1. 12. 2023, the child is three on 1. 12. 2026, so December is not a month with a child under three. Born a
    /// day later, it still is.
    @Test func aThirdBirthdayOnTheFirstOfDecemberEndsTheSpouseMonthBefore() {
        let onTheFirst = Self.credits([Self.child("Ema", born: "2023-12-01", order: 1)], spouse: Self.spouse())
        #expect(onTheFirst.spouseYoungChildMonths == 11)
        #expect(onTheFirst.spouseMonths == 11)
        #expect(onTheFirst.spouseCredit == 22_770)

        let onTheSecond = Self.credits([Self.child("Ema", born: "2023-12-02", order: 1)], spouse: Self.spouse())
        #expect(onTheSecond.spouseMonths == 12)
        #expect(onTheSecond.spouseCredit == 24_840)
    }

    /// Born 15. 6. 2008, the child is 18 on 15. 6. 2026. On the 1st of June it is still a minor, so June counts without
    /// studies; July does not.
    @Test func theEighteenthBirthdayMonthCounts() {
        let credits = Self.credits([Self.child("Petr", born: "2008-06-15", order: 1)])

        #expect(credits.children == [Self.mine("Petr", [1: 6], 7_602)])
    }

    /// Born 15. 6. 2000 and studying the whole year, the child is 26 on 15. 6. 2026: June counts, July does not.
    @Test func theTwentySixthBirthdayMonthCountsButNotTheNext() {
        let credits = Self.credits([
            Self.child("Petr", born: "2000-06-15", order: 1, studies: MonthRange.wholeYear)
        ])

        #expect(credits.children == [Self.mine("Petr", [1: 6], 7_602)])
    }

    /// Born 1. 6. 2008, the child is 18 on the 1st of June 2026, so June is an adult's month: it counts only with
    /// studies.
    @Test func anEighteenthBirthdayOnTheFirstMakesThatMonthAnAdultsMonth() {
        let withoutStudies = Self.credits([Self.child("Petr", born: "2008-06-01", order: 1)])
        #expect(withoutStudies.children == [Self.mine("Petr", [1: 5], 6_335)])

        let studying = Self.credits([
            Self.child("Petr", born: "2008-06-01", order: 1, studies: MonthRange(from: 6, to: 12))
        ])
        #expect(studying.children == [Self.mine("Petr", [1: 12], 15_204)])
    }

    /// Born 1. 6. 2000 and studying the whole year, the child is 26 on the 1st of June 2026: June does not count.
    @Test func aTwentySixthBirthdayOnTheFirstDoesNotCountThatMonth() {
        let credits = Self.credits([
            Self.child("Petr", born: "2000-06-01", order: 1, studies: MonthRange.wholeYear)
        ])

        #expect(credits.children == [Self.mine("Petr", [1: 5], 6_335)])
    }

    // MARK: The ranking

    /// Of two children with the same order the older one ranks first, and of two born on the same day the one listed
    /// first, which is the one with the lower id in a family the app reads.
    @Test func equalOrdersRankTheOlderChildFirstAndThenTheOneListedFirst() {
        let byAge = Self.credits([Self.tomas(order: 1), Self.anna(order: 1)])
        #expect(byAge.children == [Self.mine("Tomáš", [2: 12], 22_320), Self.mine("Anna", [1: 12], 15_204)])

        let jan = Self.child("Jan", born: "2020-05-05", order: 1)
        let jana = Self.child("Jana", born: "2020-05-05", order: 1)
        #expect(
            Self.credits([jan, jana]).children == [
                Self.mine("Jan", [1: 12], 15_204), Self.mine("Jana", [2: 12], 22_320),
            ])
        #expect(
            Self.credits([jana, jan]).children == [
                Self.mine("Jana", [1: 12], 15_204), Self.mine("Jan", [2: 12], 22_320),
            ])
    }

    /// Anna lives in the household until June. From July Tomáš is the first child who qualifies, so he has the first
    /// rate.
    @Test func aChildWhoStopsQualifyingLetsTheNextOneMoveUp() {
        let credits = Self.credits([Self.anna(household: MonthRange(from: 1, to: 6)), Self.tomas()])

        #expect(credits.children == [Self.mine("Anna", [1: 6], 7_602), Self.mine("Tomáš", [1: 6, 2: 6], 18_762)])
    }

    // MARK: Why a child gets nothing

    /// A child that counts in no month of the year says why: it is born after the year, it does not live in the
    /// household, it is 26 on 1 January, it is an adult on 1 January without studies, or for any other reason no month
    /// meets all the conditions.
    @Test func aChildWithoutAQualifyingMonthSaysWhy() {
        func reason(_ child: ChildFacts, year: Int = 2026) -> ChildIneligibility? {
            Self.credits([child], year: year).children.first?.ineligibility
        }

        #expect(reason(Self.tomas(order: 1), year: 2023) == .notBornYet(civilDate("2024-04-12")))
        #expect(reason(Self.anna(household: nil)) == .notInHousehold)
        #expect(reason(Self.child("Petr", born: "2000-01-01", order: 1, studies: MonthRange.wholeYear)) == .over26)
        #expect(reason(Self.child("Petr", born: "2007-03-01", order: 1)) == .adultNotStudying)
        // In the household only before the birth, and studies only outside the months in the household.
        #expect(
            reason(Self.child("Ema", born: "2026-06-15", order: 1, household: MonthRange(from: 1, to: 5)))
                == .noQualifyingMonth)
        #expect(
            reason(
                Self.child(
                    "Petr", born: "2007-03-01", order: 1, household: MonthRange(from: 1, to: 6),
                    studies: MonthRange(from: 9, to: 12)))
                == .noQualifyingMonth)
        // A child that counts in a month has no reason.
        #expect(reason(Self.anna()) == nil)
        #expect(
            Self.credits([Self.anna(household: nil)]).children == [
                ChildCredit(
                    label: "Anna", monthsByRate: [:], ztppMonths: 0, amount: 0, claimedByOther: false,
                    ineligibility: .notInHousehold)
            ])
        // A child that is not born yet takes no rank: in 2023 Anna is the first child although Tomáš is put first.
        let in2023 = Self.credits([Self.tomas(order: 1), Self.anna(order: 2)], spouse: Self.spouse(), year: 2023)
        #expect(in2023.children.map(\.amount) == [0, 15_204])
        #expect(in2023.children.last?.monthsByRate == [1: 12])
        #expect(in2023.spouseYoungChildMonths == 0)
    }

    // MARK: The spouse

    /// The child under three may be claimed by either parent, but it has to live in the household in the month.
    @Test func theYoungChildOfTheSpouseCreditMayBeClaimedByEitherParentButMustLiveInTheHousehold() {
        let claimedByOther = Self.credits([Self.anna(), Self.tomas(claimant: .otherParent)], spouse: Self.spouse())
        #expect(claimedByOther.spouseYoungChildMonths == 12)
        #expect(claimedByOther.spouseCredit == 24_840)

        let firstHalf = Self.credits(
            [Self.anna(), Self.tomas(household: MonthRange(from: 1, to: 6))], spouse: Self.spouse())
        #expect(firstHalf.spouseYoungChildMonths == 6)
        #expect(firstHalf.spouseMonths == 6)
        #expect(firstHalf.spouseCredit == 12_420)

        let away = Self.credits([Self.anna(), Self.tomas(household: nil)], spouse: Self.spouse())
        #expect(away.spouseYoungChildMonths == 0)
        #expect(away.spouseCredit == 0)
    }

    /// The spouse counts in the months claimed, twice in a month with ZTP/P. A spouse who is not claimed, or no spouse,
    /// counts in none.
    @Test func theSpouseCountsInTheMonthsClaimedAndTwiceWithZTPP() {
        let tomas = [Self.tomas(order: 1)]

        let fromMay = Self.credits(
            tomas, spouse: Self.spouse(months: MonthRange(from: 5, to: 12), ztpp: MonthRange(from: 9, to: 10)))
        #expect(fromMay.spouseMonths == 8)
        #expect(fromMay.spouseZTPPMonths == 2)
        #expect(fromMay.spouseCredit == 20_700)

        // ZTP/P the whole year counts only in the months claimed.
        let ztppAllYear = Self.credits(
            tomas, spouse: Self.spouse(months: MonthRange(from: 5, to: 12), ztpp: MonthRange.wholeYear))
        #expect(ztppAllYear.spouseZTPPMonths == 8)
        #expect(ztppAllYear.spouseCredit == 33_120)
        #expect(Self.credits(tomas, spouse: Self.spouse(ztpp: MonthRange.wholeYear)).spouseCredit == 49_680)

        let unclaimed = Self.credits(tomas, spouse: Self.spouse(claim: false))
        #expect(unclaimed.spouseMonths == 0)
        #expect(unclaimed.spouseCredit == 0)
        #expect(Self.credits(tomas).spouseCredit == 0)
    }
}

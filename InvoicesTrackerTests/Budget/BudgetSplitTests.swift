import Foundation
import Testing

@testable import InvoicesTracker

struct BudgetSplitTests {
    private let sample = BudgetSplit(
        holdings: [
            .costs: .fixed(25_000), .savings: .share(Decimal(string: "0.15")!),
            .investments: .share(Decimal(string: "0.25")!), .spending: .share(0),
        ],
        remainder: .spending)

    @Test func theSampleSplitDividesTheMonthAndTheYearExactly() {
        let month = sample.allocation(net: 190_037, fixedMultiplier: 1)
        #expect(month.amounts == [.costs: 25_000, .spending: 89_022, .savings: 28_506, .investments: 47_509])
        let year = sample.allocation(net: 2_280_444, fixedMultiplier: 12)
        #expect(year.amounts == [.costs: 300_000, .spending: 1_068_266, .savings: 342_067, .investments: 570_111])
    }

    @Test func typingKorunyOnAShareComesOutExactlyInTheMonthAndTheYear() {
        let typed = sample.settingAmount(30_000, of: .savings, net: 190_037)
        #expect(typed.allocation(net: 190_037, fixedMultiplier: 1).amounts[.savings] == 30_000)
        #expect(typed.allocation(net: 190_037, fixedMultiplier: 1).amounts[.spending] == 87_528)
        #expect(typed.allocation(net: 2_280_444, fixedMultiplier: 12).amounts[.savings] == 360_000)
    }

    @Test func aShareStopsWhereTheRemainderReachesZero() {
        let typed = sample.settingAmount(30_000, of: .savings, net: 190_037)
            .settingShare(Decimal(string: "0.8")!, of: .investments, net: 190_037)
        let month = typed.allocation(net: 190_037, fixedMultiplier: 1)
        #expect(month.amounts[.investments] == 135_037)
        #expect(month.amounts[.spending] == 0)
        #expect(typed.allocation(net: 2_280_444, fixedMultiplier: 12).amounts[.spending] == 0)
    }

    @Test func fixedAmountsAreNeverClampedAndMakeAShortfall() {
        let small = sample.settingAmount(32_500, of: .costs, net: 3_140).allocation(net: 3_140, fixedMultiplier: 1)
        #expect(small.amounts == [.costs: 32_500, .spending: -30_616, .savings: 471, .investments: 785])
        #expect(small.shortfall == 30_616)
    }

    @Test func tickingAndUntickingAFixedAmountChangesNoNumber() {
        let fixed = sample.togglingFixed(.investments, net: 190_037)
        #expect(fixed.holdings[.investments] == .fixed(47_509))
        let before = sample.allocation(net: 190_037, fixedMultiplier: 1).amounts
        #expect(fixed.allocation(net: 190_037, fixedMultiplier: 1).amounts == before)
        let back = fixed.togglingFixed(.investments, net: 190_037)
        #expect(back.allocation(net: 190_037, fixedMultiplier: 1).amounts == before)
    }

    @Test func choosingAnotherRemainderChangesNoNumber() {
        let moved = sample.withRemainder(.costs, net: 190_037)
        #expect(moved.remainder == .costs)
        #expect(
            moved.allocation(net: 190_037, fixedMultiplier: 1).amounts
                == sample.allocation(net: 190_037, fixedMultiplier: 1).amounts)
        #expect(moved.holdings[.spending] == .share(Decimal(89_022) / Decimal(190_037)))
        #expect(moved.holdings[.costs] == .share(0))
    }

    @Test func theEmptySplitGivesEverythingToSpending() {
        let amounts = BudgetSplit.empty.allocation(net: 190_037, fixedMultiplier: 1).amounts
        #expect(amounts == [.costs: 0, .spending: 190_037, .savings: 0, .investments: 0])
    }

    @Test func withNoAmountToDivideTheLimitIsWhatTheOtherSharesLeave() {
        #expect(sample.shareLimit(of: .savings, net: nil) == Decimal(string: "0.75")!)
        #expect(
            sample.settingShare(Decimal(string: "0.9")!, of: .savings, net: nil).holdings[.savings]
                == .share(Decimal(string: "0.75")!))
        #expect(sample.settingAmount(1_000, of: .savings, net: nil) == sample)
    }

    @Test func theSplitRoundTripsThroughJSONWithTheDecimalAsAString() throws {
        let data = try JSONEncoder().encode(sample)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"share\":\"0.15\""))
        #expect(text.contains("\"fixed\":25000"))
        #expect(try JSONDecoder().decode(BudgetSplit.self, from: data) == sample)
    }
}

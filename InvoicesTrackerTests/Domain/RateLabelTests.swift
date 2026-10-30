import Foundation
import Testing
@testable import InvoicesTracker

/// The label of an exchange rate as the screens write it: the rate in crowns and what it is for, "21,622 Kč/USD". A
/// rate that the ČNB or the GFŘ quotes for 100 or 1 000 units says how many. In every expected string `\u{00A0}` is
/// the no-break space.
struct RateLabelTests {
    @Test func aRateForOneUnitNamesTheCurrencyAlone() {
        let dollar = ExchangeRate(currency: .usd, amount: 1, rate: decimal("21.32"))

        #expect(CzechFormat.rateLabel(dollar) == "21,320\u{00A0}Kč/USD")
    }

    @Test func aRateForOneHundredUnitsNamesTheQuantityBeforeTheCurrency() {
        let forint = ExchangeRate(currency: CurrencyCode("HUF")!, amount: 100, rate: decimal("6.22"))

        #expect(CzechFormat.rateLabel(forint) == "6,220\u{00A0}Kč/100 HUF")
    }

    @Test func aRateForOneThousandUnitsGroupsTheQuantityWithANoBreakSpace() {
        let rupiah = ExchangeRate(currency: CurrencyCode("IDR")!, amount: 1_000, rate: decimal("1.204"))

        #expect(CzechFormat.rateLabel(rupiah) == "1,204\u{00A0}Kč/1\u{00A0}000 IDR")
    }
}

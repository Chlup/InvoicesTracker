import Foundation
import Testing
@testable import InvoicesTracker

/// In every expected string `\u{00A0}` is the no-break space and `\u{2212}` the minus sign.
struct CzechFormatTests {
    // MARK: Whole numbers

    @Test func groupedSeparatesThousandsWithANoBreakSpace() {
        #expect(CzechFormat.grouped(0) == "0")
        #expect(CzechFormat.grouped(7) == "7")
        #expect(CzechFormat.grouped(999) == "999")
        #expect(CzechFormat.grouped(1000) == "1\u{00A0}000")
        #expect(CzechFormat.grouped(13340) == "13\u{00A0}340")
        #expect(CzechFormat.grouped(110844) == "110\u{00A0}844")
        #expect(CzechFormat.grouped(1234567) == "1\u{00A0}234\u{00A0}567")
    }

    @Test func groupedUsesTheTypographicMinus() {
        #expect(CzechFormat.grouped(-5) == "−5")
        #expect(CzechFormat.grouped(-5) == "\u{2212}5")
        #expect(CzechFormat.grouped(-1234) == "\u{2212}1\u{00A0}234")
    }

    @Test func groupedCoversTheWholeInt64Range() {
        #expect(CzechFormat.grouped(Int64.max) == "9\u{00A0}223\u{00A0}372\u{00A0}036\u{00A0}854\u{00A0}775\u{00A0}807")
        let smallest = "\u{2212}9\u{00A0}223\u{00A0}372\u{00A0}036\u{00A0}854\u{00A0}775\u{00A0}808"
        #expect(CzechFormat.grouped(Int64.min) == smallest)
    }

    @Test func wholeKcAppendsTheCurrencySymbol() {
        #expect(CzechFormat.wholeKc(110844) == "110\u{00A0}844\u{00A0}Kč")
        #expect(CzechFormat.wholeKc(0) == "0\u{00A0}Kč")
        #expect(CzechFormat.wholeKc(-13340) == "\u{2212}13\u{00A0}340\u{00A0}Kč")
    }

    // MARK: Amounts in minor units

    @Test func halereShowsKorunasWithTwoDecimals() {
        #expect(CzechFormat.halere(219177135) == "2\u{00A0}191\u{00A0}771,35\u{00A0}Kč")
        #expect(CzechFormat.halere(0) == "0,00\u{00A0}Kč")
        #expect(CzechFormat.halere(99) == "0,99\u{00A0}Kč")
        #expect(CzechFormat.halere(100) == "1,00\u{00A0}Kč")
        #expect(CzechFormat.halere(100050) == "1\u{00A0}000,50\u{00A0}Kč")
    }

    @Test func halereKeepsTheSignOfAmountsBelowOneKoruna() {
        #expect(CzechFormat.halere(5) == "0,05\u{00A0}Kč")
        #expect(CzechFormat.halere(-5) == "\u{2212}0,05\u{00A0}Kč")
        #expect(CzechFormat.halere(-99) == "\u{2212}0,99\u{00A0}Kč")
        #expect(CzechFormat.halere(-219177135) == "\u{2212}2\u{00A0}191\u{00A0}771,35\u{00A0}Kč")
    }

    @Test func amountIsTheNumberWithoutACurrency() {
        #expect(CzechFormat.amount(1435000) == "14\u{00A0}350,00")
        #expect(CzechFormat.amount(0) == "0,00")
        #expect(CzechFormat.amount(-1) == "\u{2212}0,01")
        #expect(CzechFormat.amount(-105) == "\u{2212}1,05")
        #expect(CzechFormat.amount(Int64.max) == "92\u{00A0}233\u{00A0}720\u{00A0}368\u{00A0}547\u{00A0}758,07")
        #expect(CzechFormat.amount(Int64.min) == "\u{2212}92\u{00A0}233\u{00A0}720\u{00A0}368\u{00A0}547\u{00A0}758,08")
    }

    @Test func moneyNamesTheCurrency() {
        #expect(CzechFormat.money(Money(minor: 1435000, currency: .usd)) == "14\u{00A0}350,00\u{00A0}USD")
        #expect(CzechFormat.money(Money(minor: -105, currency: .eur)) == "\u{2212}1,05\u{00A0}EUR")
        #expect(CzechFormat.money(Money(minor: 100000, currency: CurrencyCode("JPY")!)) == "1\u{00A0}000,00\u{00A0}JPY")
    }

    @Test func moneyInCrownsUsesTheSymbol() {
        #expect(CzechFormat.money(Money(minor: 219177135, currency: .czk)) == "2\u{00A0}191\u{00A0}771,35\u{00A0}Kč")
        #expect(CzechFormat.money(Money(minor: -5, currency: .czk)) == "\u{2212}0,05\u{00A0}Kč")
    }

    // MARK: Dates

    @Test func dateHasNoLeadingZerosAndANoBreakSpaceAfterEachDot() {
        #expect(CzechFormat.date(CivilDate(iso: "2026-10-17")!) == "17.\u{00A0}10.\u{00A0}2026")
        #expect(CzechFormat.date(CivilDate(iso: "2026-03-05")!) == "5.\u{00A0}3.\u{00A0}2026")
        #expect(CzechFormat.date(CivilDate(iso: "2027-01-01")!) == "1.\u{00A0}1.\u{00A0}2027")
        #expect(CzechFormat.date(CivilDate(iso: "2026-12-31")!) == "31.\u{00A0}12.\u{00A0}2026")
    }

    @Test func dayMonthEndsWithADot() {
        #expect(CzechFormat.dayMonth(CivilDate(iso: "2026-10-17")!) == "17.\u{00A0}10.")
        #expect(CzechFormat.dayMonth(CivilDate(iso: "2026-03-05")!) == "5.\u{00A0}3.")
    }

    // MARK: Rates and percentages

    @Test func rateUsesADecimalComma() {
        #expect(CzechFormat.rate(Decimal(string: "21.622")!) == "21,622")
        #expect(CzechFormat.rate(Decimal(string: "21.84")!, fractionDigits: 2) == "21,84")
    }

    @Test func rateAlwaysShowsTheRequestedNumberOfDecimals() {
        #expect(CzechFormat.rate(Decimal(string: "21.84")!) == "21,840")
        #expect(CzechFormat.rate(Decimal(string: "6.5")!) == "6,500")
        #expect(CzechFormat.rate(Decimal(22)) == "22,000")
        #expect(CzechFormat.rate(Decimal(string: "14.232")!, fractionDigits: 5) == "14,23200")
        #expect(CzechFormat.rate(Decimal(string: "21.5")!, fractionDigits: 0) == "22")
        #expect(CzechFormat.rate(Decimal(22), fractionDigits: 0) == "22")
    }

    @Test func rateRoundsHalfUp() {
        #expect(CzechFormat.rate(Decimal(string: "21.3055")!) == "21,306")
        #expect(CzechFormat.rate(Decimal(string: "21.30549")!) == "21,305")
        #expect(CzechFormat.rate(Decimal(string: "21.305")!, fractionDigits: 2) == "21,31")
        #expect(CzechFormat.rate(Decimal(string: "-21.305")!, fractionDigits: 2) == "\u{2212}21,31")
        #expect(CzechFormat.rate(Decimal(string: "0.9995")!) == "1,000")
    }

    @Test func rateGroupsThousandsAndKeepsTheSign() {
        #expect(CzechFormat.rate(Decimal(string: "1234.5")!, fractionDigits: 2) == "1\u{00A0}234,50")
        #expect(CzechFormat.rate(Decimal(string: "-21.622")!) == "\u{2212}21,622")
        #expect(CzechFormat.rate(Decimal(string: "1234567.891")!) == "1\u{00A0}234\u{00A0}567,891")
    }

    @Test func rateNeverShowsANegativeZero() {
        #expect(CzechFormat.rate(Decimal(0)) == "0,000")
        #expect(CzechFormat.rate(Decimal(string: "-0.0004")!) == "0,000")
        #expect(CzechFormat.rate(Decimal(string: "-0.0005")!) == "\u{2212}0,001")
    }

    @Test func percentShowsAFractionAsPercentWithANoBreakSpace() {
        #expect(CzechFormat.percent(Decimal(string: "0.3781")!) == "37,8\u{00A0}%")
        #expect(CzechFormat.percent(Decimal(string: "0.15")!, fractionDigits: 0) == "15\u{00A0}%")
        #expect(CzechFormat.percent(Decimal(string: "0.15")!) == "15,0\u{00A0}%")
        #expect(CzechFormat.percent(Decimal(1)) == "100,0\u{00A0}%")
        #expect(CzechFormat.percent(Decimal(0)) == "0,0\u{00A0}%")
        #expect(CzechFormat.percent(Decimal(string: "0.015")!) == "1,5\u{00A0}%")
        #expect(CzechFormat.percent(Decimal(string: "1234.56")!) == "123\u{00A0}456,0\u{00A0}%")
    }

    @Test func percentRoundsHalfUpAfterScalingToPercent() {
        #expect(CzechFormat.percent(Decimal(string: "0.3785")!) == "37,9\u{00A0}%")
        #expect(CzechFormat.percent(Decimal(string: "0.37849")!) == "37,8\u{00A0}%")
        #expect(CzechFormat.percent(Decimal(string: "0.12345")!, fractionDigits: 2) == "12,35\u{00A0}%")
        #expect(CzechFormat.percent(Decimal(string: "0.125")!, fractionDigits: 0) == "13\u{00A0}%")
    }

    @Test func percentKeepsTheSignUnlessItRoundsToZero() {
        #expect(CzechFormat.percent(Decimal(string: "-0.05")!) == "\u{2212}5,0\u{00A0}%")
        #expect(CzechFormat.percent(Decimal(string: "-0.0004")!) == "0,0\u{00A0}%")
        #expect(CzechFormat.percent(Decimal(string: "-0.0005")!) == "\u{2212}0,1\u{00A0}%")
    }

    // MARK: Month names

    @Test func monthNamesAreTheNominativeCzechNames() {
        #expect(CzechFormat.monthNames == [
            "leden", "únor", "březen", "duben", "květen", "červen",
            "červenec", "srpen", "září", "říjen", "listopad", "prosinec",
        ])
    }

    @Test func monthShortNamesAreThreeLetterAbbreviations() {
        #expect(CzechFormat.monthShort == [
            "led", "úno", "bře", "dub", "kvě", "čvn",
            "čvc", "srp", "zář", "říj", "lis", "pro",
        ])
        #expect(CzechFormat.monthShort.count == CzechFormat.monthNames.count)
        #expect(CzechFormat.monthShort.allSatisfy { $0.count == 3 })
    }

    /// Swift compares strings by canonical equivalence, so the scalars are checked directly:
    /// č is U+010D, ř is U+0159, í is U+00ED, not a letter followed by a combining mark.
    @Test func monthNamesAreStoredPrecomposed() {
        #expect(CzechFormat.monthNames[5].unicodeScalars.map(\.value) == [0x010D, 0x65, 0x72, 0x76, 0x65, 0x6E])
        #expect(CzechFormat.monthShort[9].unicodeScalars.map(\.value) == [0x0159, 0x00ED, 0x6A])
        #expect(CzechFormat.monthShort[5].unicodeScalars.map(\.value) == [0x010D, 0x76, 0x6E])
        for name in CzechFormat.monthNames + CzechFormat.monthShort {
            let scalars = name.unicodeScalars.map(\.value)
            let precomposed = name.precomposedStringWithCanonicalMapping.unicodeScalars.map(\.value)
            #expect(scalars == precomposed, "\(name)")
        }
    }
}

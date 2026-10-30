import Foundation
import Testing
@testable import InvoicesTracker

/// Amounts typed by hand are parsed exactly or rejected, never silently mis-scaled.
struct AmountParserTests {
    // MARK: The pinned examples

    @Test func minorParsesGroupedCzechAndEnglishStyleAmounts() {
        #expect(AmountParser.minor("1 000,50") == 100050)
        #expect(AmountParser.minor("1\u{00A0}000,50") == 100050)
        #expect(AmountParser.minor("1\u{202F}000.5") == 100050)
        #expect(AmountParser.minor("−12,5") == -1250)
        #expect(AmountParser.minor("-12") == -1200)
        #expect(AmountParser.minor("14350") == 1435000)
    }

    @Test func minorRejectsAmbiguousAndForeignText() {
        #expect(AmountParser.minor("1.234,50") == nil)
        #expect(AmountParser.minor("1,234.50") == nil)
        #expect(AmountParser.minor("12,345") == nil)
        #expect(AmountParser.minor("") == nil)
        #expect(AmountParser.minor("12 Kč") == nil)
    }

    @Test func wholeKcAcceptsWholeCrownsOnly() {
        #expect(AmountParser.wholeKc("13 340") == 13340)
        #expect(AmountParser.wholeKc("13 340,50") == nil)
    }

    @Test func decimalParsesWithinTheAllowedFractionDigits() {
        #expect(AmountParser.decimal("6,5", maxFractionDigits: 3) == Decimal(string: "6.5"))
        #expect(AmountParser.decimal("21,622", maxFractionDigits: 3) == Decimal(string: "21.622"))
        #expect(AmountParser.decimal("0,0001", maxFractionDigits: 3) == nil)
    }

    // MARK: minor(_:)

    @Test func minorAcceptsBothDecimalSeparators() {
        #expect(AmountParser.minor("12,5") == 1250)
        #expect(AmountParser.minor("12.5") == 1250)
        #expect(AmountParser.minor("12,50") == 1250)
        #expect(AmountParser.minor("12.50") == 1250)
        #expect(AmountParser.minor("12,05") == 1205)
        #expect(AmountParser.minor("12,00") == 1200)
        #expect(AmountParser.minor("0,5") == 50)
        #expect(AmountParser.minor("0.05") == 5)
        #expect(AmountParser.minor("0,01") == 1)
    }

    @Test func minorAcceptsIntegersAndLeadingZeros() {
        #expect(AmountParser.minor("0") == 0)
        #expect(AmountParser.minor("1000") == 100_000)
        #expect(AmountParser.minor("007") == 700)
        #expect(AmountParser.minor("00,5") == 50)
    }

    @Test func minorAcceptsAnyMixOfTheThreeGroupingSpaces() {
        #expect(AmountParser.minor("1 000 000,00") == 100_000_000)
        #expect(AmountParser.minor("1 000\u{00A0}000") == 100_000_000)
        #expect(AmountParser.minor("1\u{202F}000\u{202F}000,5") == 100_000_050)
        #expect(AmountParser.minor("1  000") == 100_000)
        #expect(AmountParser.minor("13 340") == 1_334_000)
    }

    @Test func minorAcceptsCzechDigitGroups() {
        #expect(AmountParser.minor("1 000") == 100_000)
        #expect(AmountParser.minor("12 345 678,90") == 1_234_567_890)
        #expect(AmountParser.minor("1\u{00A0}000\u{00A0}000") == 100_000_000)
        #expect(AmountParser.minor("999 999") == 99_999_900)
        #expect(AmountParser.minor("123 456 789") == 12_345_678_900)
        #expect(AmountParser.minor("1 000 000 000,01") == 100_000_000_001)
        #expect(AmountParser.minor("0 000") == 0)
    }

    /// Digits without a space are not groups: the size rule applies only when a space is typed.
    @Test func minorAcceptsRunsOfDigitsWithoutSpaces() {
        #expect(AmountParser.minor("1234567") == 123_456_700)
        #expect(AmountParser.minor("1234567,89") == 123_456_789)
        #expect(AmountParser.minor("9999999999") == 999_999_999_900)
    }

    @Test func minorAcceptsBothMinusSignsAndNegativeZero() {
        #expect(AmountParser.minor("-12,5") == -1250)
        #expect(AmountParser.minor("\u{2212}12,5") == -1250)
        #expect(AmountParser.minor("-0") == 0)
        #expect(AmountParser.minor("\u{2212}0,00") == 0)
        #expect(AmountParser.minor("-0,01") == -1)
        #expect(AmountParser.minor("\u{2212}1 000,50") == -100_050)
    }

    @Test func minorIgnoresWhitespaceAroundTheNumber() {
        #expect(AmountParser.minor(" 12 ") == 1200)
        #expect(AmountParser.minor("\u{00A0}1 000,50\u{00A0}") == 100_050)
        #expect(AmountParser.minor("\u{202F}12\u{202F}") == 1200)
        #expect(AmountParser.minor("12\n") == 1200)
        #expect(AmountParser.minor("\t-12,5") == -1250)
    }

    /// A space typed instead of a comma must not turn `12,50` into 1 250: when there are spaces, the first group has
    /// one to three digits and every later group exactly three.
    @Test(arguments: [
        "12 50", "1 5", "10 00", "100 0", "1 0000",
        "1234 567", "12 3456", "12 34 56", "1 00 000", "1 000 00", "1 000 0000", "0 00", "1  00",
        "1 000 0,5", "12 50,00", "-12 50", "\u{2212}1 5", "12\u{00A0}50", "1\u{202F}5",
    ])
    func minorRejectsDigitGroupsOfTheWrongSize(_ text: String) {
        #expect(AmountParser.minor(text) == nil)
    }

    @Test func minorAcceptsAmountsBelowTenBillionCurrencyUnits() {
        #expect(AmountParser.minor("9 999 999 999,99") == 999_999_999_999)
        #expect(AmountParser.minor("9999999999,99") == 999_999_999_999)
        #expect(AmountParser.minor("9 999 999 999.99") == 999_999_999_999)
        #expect(AmountParser.minor("\u{2212}9 999 999 999,99") == -999_999_999_999)
        #expect(AmountParser.minor("-9999999999,99") == -999_999_999_999)
        #expect(AmountParser.minor("9 999 999 999") == 999_999_999_900)
    }

    @Test(arguments: [
        "10 000 000 000", "10 000 000 000,00", "10000000000", "10 000 000 000,01", "10 000 000 000,5",
        "-10 000 000 000", "\u{2212}10 000 000 000,01", "-10000000000", "99 999 999 999",
        // What used to be the largest accepted amounts, and absurd ones.
        "92233720368547758,07", "-92233720368547758,08", "92233720368547759",
        "999999999999999999999", "1000000000000000000000000000000", "-1000000000000000000000000000000,5",
    ])
    func minorRejectsAmountsFromTenBillionCurrencyUnits(_ text: String) {
        #expect(AmountParser.minor(text) == nil)
    }

    @Test func minorIgnoresLeadingZerosWhenCheckingTheLimit() {
        #expect(AmountParser.minor("00000009999999999,99") == 999_999_999_999)
        #expect(AmountParser.minor("000000000000000000005") == 500)
        #expect(AmountParser.minor("0000000010000000000") == nil)
    }

    /// Anything that could be read as a different amount, or is not an amount, is refused.
    @Test(arguments: [
        // Thousands separators that are not spaces, and more than one separator.
        "1.234,50", "1,234.50", "1.234.567", "1,234,567", "1,234,567.89", "12,345", "12.345", "1,5,5", "1.5.5",
        "1,5.5", "1..5", "1,,5", "1'234", "1\u{2019}234",
        // More than two fraction digits, even when they are zeros.
        "12,500", "12.000", "0,001",
        // Signs.
        "--5", "-\u{2212}5", "\u{2212}-5", "5-", "5\u{2212}", "+5", "-+5", "- 12", "\u{2212}\u{00A0}12", "1-2",
        // Currency symbols, units and other text.
        "12 Kč", "Kč 12", "12Kč", "12 CZK", "\u{20AC}12", "12%", "1e3", "1E3", "1_000", "0x10", "NaN", "inf",
        "\u{221E}", "twelve",
        // A separator needs digits on both sides.
        ",5", ".5", "-,5", "5,", "5.", ",", ".", "-,", "-", "\u{2212}", "",
        // Nothing but spaces.
        " ", "   ", "\t", "\u{00A0}",
        // Spaces anywhere but between the digits of the integer part.
        "12 ,5", "12, 5", "12 .5", "1,5 0", "1 2,5 0", "12 ,", "1 - 2",
        // Spaces that are not the three grouping spaces, and invisible characters.
        "1\u{2009}000", "1\u{2003}000", "1\t000", "1\n000", "1\u{200B}000",
        // Digits of other scripts.
        "\u{0661}\u{0662}", "\u{FF11}\u{FF12}",
    ])
    func minorRejectsEverythingElse(_ text: String) {
        #expect(AmountParser.minor(text) == nil)
    }

    // MARK: wholeKc(_:)

    @Test func wholeKcAcceptsZeroFractions() {
        #expect(AmountParser.wholeKc("13340,00") == 13340)
        #expect(AmountParser.wholeKc("13 340,0") == 13340)
        #expect(AmountParser.wholeKc("\u{2212}1 000") == -1000)
        #expect(AmountParser.wholeKc("0") == 0)
        #expect(AmountParser.wholeKc("-0,00") == 0)
        #expect(AmountParser.wholeKc("110\u{00A0}844") == 110_844)
    }

    @Test func wholeKcAcceptsCzechDigitGroups() {
        #expect(AmountParser.wholeKc("1 000") == 1000)
        #expect(AmountParser.wholeKc("1\u{00A0}000\u{00A0}000") == 1_000_000)
        #expect(AmountParser.wholeKc("12 345 678") == 12_345_678)
        #expect(AmountParser.wholeKc("12 345 678,00") == 12_345_678)
        // With haléře there is no whole number of crowns.
        #expect(AmountParser.wholeKc("12 345 678,90") == nil)
    }

    @Test(arguments: [
        "13 340,50", "13 340,5", "13 340,01", "13 340,005", "13 340,000", "0,5", "-0,01", "13 340 Kč", "1.234,50",
        "abc", "",
    ])
    func wholeKcRejectsFractionsAndForeignText(_ text: String) {
        #expect(AmountParser.wholeKc(text) == nil)
    }

    @Test(arguments: ["12 50", "1 5", "10 00", "100 0", "1 0000", "1234 567", "12 34 56", "12 50,00"])
    func wholeKcRejectsDigitGroupsOfTheWrongSize(_ text: String) {
        #expect(AmountParser.wholeKc(text) == nil)
    }

    @Test func wholeKcAcceptsCrownsBelowTenBillion() {
        #expect(AmountParser.wholeKc("9 999 999 999") == 9_999_999_999)
        #expect(AmountParser.wholeKc("9999999999") == 9_999_999_999)
        #expect(AmountParser.wholeKc("9 999 999 999,00") == 9_999_999_999)
        #expect(AmountParser.wholeKc("\u{2212}9 999 999 999") == -9_999_999_999)
    }

    @Test(arguments: [
        "10 000 000 000", "10000000000", "10 000 000 000,00", "-10 000 000 000", "99 999 999 999",
        // What used to be the largest accepted amounts.
        "92233720368547758", "-92233720368547758", "92233720368547759",
    ])
    func wholeKcRejectsCrownsFromTenBillion(_ text: String) {
        #expect(AmountParser.wholeKc(text) == nil)
    }

    // MARK: decimal(_:maxFractionDigits:)

    @Test func decimalAcceptsEitherSeparator() {
        let commaStyle = AmountParser.decimal("21,622", maxFractionDigits: 3)
        #expect(commaStyle != nil)
        #expect(commaStyle == AmountParser.decimal("21.622", maxFractionDigits: 3))
        #expect(AmountParser.decimal("0.15", maxFractionDigits: 2) == Decimal(string: "0.15"))
        #expect(AmountParser.decimal("35,5", maxFractionDigits: 1) == Decimal(string: "35.5"))
        #expect(AmountParser.decimal("12", maxFractionDigits: 3) == Decimal(12))
    }

    @Test func decimalCountsFractionDigitsAsTyped() {
        #expect(AmountParser.decimal("0,000", maxFractionDigits: 3) == Decimal(0))
        #expect(AmountParser.decimal("6,50", maxFractionDigits: 3) == Decimal(string: "6.5"))
        #expect(AmountParser.decimal("6,500", maxFractionDigits: 3) == Decimal(string: "6.5"))
        #expect(AmountParser.decimal("6,500", maxFractionDigits: 2) == nil)
        #expect(AmountParser.decimal("6,5", maxFractionDigits: 0) == nil)
        #expect(AmountParser.decimal("6,0", maxFractionDigits: 0) == nil)
        #expect(AmountParser.decimal("6", maxFractionDigits: 0) == Decimal(6))
    }

    @Test func decimalHandlesSignsAndGrouping() {
        #expect(AmountParser.decimal("-0,5", maxFractionDigits: 3) == Decimal(string: "-0.5"))
        #expect(AmountParser.decimal("\u{2212}2,25", maxFractionDigits: 2) == Decimal(string: "-2.25"))
        #expect(AmountParser.decimal("-0", maxFractionDigits: 2) == Decimal(0))
        #expect(AmountParser.decimal("1 000,5", maxFractionDigits: 1) == Decimal(string: "1000.5"))
        #expect(AmountParser.decimal("999\u{202F}999", maxFractionDigits: 0) == Decimal(999_999))
        #expect(AmountParser.decimal("12\u{00A0}345,5", maxFractionDigits: 1) == Decimal(string: "12345.5"))
        #expect(AmountParser.decimal(" 21,622 ", maxFractionDigits: 3) == Decimal(string: "21.622"))
    }

    @Test(arguments: ["1 5", "12 50,5", "1 0000", "1234 567,5", "12 34", "1 00 000", "1 000 00"])
    func decimalRejectsDigitGroupsOfTheWrongSize(_ text: String) {
        #expect(AmountParser.decimal(text, maxFractionDigits: 3) == nil)
    }

    @Test func decimalAcceptsNumbersBelowAMillion() {
        #expect(AmountParser.decimal("999 999,999", maxFractionDigits: 3) == Decimal(string: "999999.999"))
        #expect(AmountParser.decimal("999999.999", maxFractionDigits: 3) == Decimal(string: "999999.999"))
        #expect(AmountParser.decimal("\u{2212}999 999,999", maxFractionDigits: 3) == Decimal(string: "-999999.999"))
        #expect(AmountParser.decimal("999999", maxFractionDigits: 0) == Decimal(999_999))
        #expect(AmountParser.decimal("000999999", maxFractionDigits: 0) == Decimal(999_999))
    }

    @Test(arguments: [
        "1 000 000", "1000000", "1 000 000,5", "1000000.000", "\u{2212}1 000 000", "-1000000", "1234567,5",
        "0001000000", "99999999999999999999", "1000000000000000000000000000000",
    ])
    func decimalRejectsNumbersFromAMillion(_ text: String) {
        #expect(AmountParser.decimal(text, maxFractionDigits: 3) == nil)
    }

    @Test(arguments: [
        "1.234,5", "1,234.5", "1.234.567", "1,5,5", ",5", "5,", "", "-", "21,622 Kč", "1e3", "+5",
        "12,3456",  // four fraction digits, three allowed
    ])
    func decimalRejectsWhatMinorRejects(_ text: String) {
        #expect(AmountParser.decimal(text, maxFractionDigits: 3) == nil)
    }

    /// Digits that `Decimal` cannot hold exactly are refused rather than rounded: 38 digits fit, 40 do not.
    @Test func decimalNeverRoundsDigitsAway() {
        let ones = String(repeating: "1", count: 32)
        #expect(AmountParser.decimal("123456," + ones, maxFractionDigits: 32) == Decimal(string: "123456." + ones))
        #expect(AmountParser.decimal("123456," + ones + "11", maxFractionDigits: 34) == nil)
        #expect(AmountParser.decimal("0," + String(repeating: "1", count: 40), maxFractionDigits: 40) == nil)
    }

    // MARK: Agreement with CzechFormat

    @Test func minorParsesWhatCzechFormatPrints() {
        let amounts: [Int64] = [
            -999_999_999_999, -219_177_135, -105, -99, -1, 0, 1, 5, 99, 100, 100_050, 1_435_000, 219_177_135,
            999_999_999_999,
        ]
        for minor in amounts {
            #expect(AmountParser.minor(CzechFormat.amount(minor)) == minor, "amount \(minor)")
        }
    }

    /// The limit on typed amounts also applies to text that `CzechFormat` printed, including the extremes of Int64.
    @Test func minorRefusesWhatCzechFormatPrintsBeyondTheLimit() {
        let amounts: [Int64] = [1_000_000_000_000, -1_000_000_000_000, .max, .min]
        for minor in amounts {
            #expect(AmountParser.minor(CzechFormat.amount(minor)) == nil, "amount \(minor)")
        }
    }

    @Test func wholeKcParsesWhatCzechFormatPrints() {
        let crowns: [Int64] = [-9_999_999_999, -110_844, -1, 0, 1, 13_340, 110_844, 9_999_999_999]
        for kc in crowns {
            #expect(AmountParser.wholeKc(CzechFormat.grouped(kc)) == kc, "crowns \(kc)")
        }
    }

    @Test func wholeKcRefusesWhatCzechFormatPrintsBeyondTheLimit() {
        let crowns: [Int64] = [10_000_000_000, -10_000_000_000, 92_233_720_368_547_758, -92_233_720_368_547_758]
        for kc in crowns {
            #expect(AmountParser.wholeKc(CzechFormat.grouped(kc)) == nil, "crowns \(kc)")
        }
    }

    @Test func decimalParsesWhatCzechFormatPrints() {
        for text in ["21.622", "6.5", "0.15", "1234.5", "-0.001", "999999.999", "-999999.999"] {
            let value = Decimal(string: text)!
            let printed = CzechFormat.rate(value)
            #expect(AmountParser.decimal(printed, maxFractionDigits: 3) == value, "rate \(printed)")
        }
    }

    @Test func theCurrencySymbolIsNotPartOfAnAmount() {
        #expect(AmountParser.minor(CzechFormat.halere(100_050)) == nil)
        #expect(AmountParser.minor(CzechFormat.money(Money(minor: 100_050, currency: .usd))) == nil)
        #expect(AmountParser.wholeKc(CzechFormat.wholeKc(13_340)) == nil)
    }
}

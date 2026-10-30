import Foundation
import Testing
@testable import InvoicesTracker

struct MoneyTests {
    // MARK: CurrencyCode

    @Test func currencyCodeAcceptsThreeAsciiCapitals() {
        #expect(CurrencyCode("USD")?.code == "USD")
        #expect(CurrencyCode("CZK") == CurrencyCode.czk)
        #expect(CurrencyCode("JPY")?.code == "JPY")
    }

    @Test(arguments: [
        "usd", "Usd", "US", "USDX", "", " USD", "USD ", "US$", "U1D", "EUR\n",
        "\u{010C}ZK",  // Č is not an ASCII capital
        "\u{0415}UR",  // Cyrillic Е, not the Latin E
        "\u{FF35}\u{FF33}\u{FF24}",  // fullwidth capitals
    ])
    func currencyCodeRejectsAnythingElse(_ text: String) {
        #expect(CurrencyCode(text) == nil)
    }

    @Test func currencyCodeConstants() {
        #expect(CurrencyCode.czk.code == "CZK")
        #expect(CurrencyCode.usd.code == "USD")
        #expect(CurrencyCode.eur.code == "EUR")
        #expect(CurrencyCode.czk.isCZK)
        #expect(!CurrencyCode.usd.isCZK)
        #expect(!CurrencyCode.eur.isCZK)
    }

    @Test func currencyCodesAreOrderedAlphabetically() {
        #expect(CurrencyCode.eur < CurrencyCode.usd)
        #expect(!(CurrencyCode.usd < CurrencyCode.eur))
        #expect(!(CurrencyCode.usd < CurrencyCode.usd))
        #expect([CurrencyCode.usd, .czk, .eur].sorted() == [.czk, .eur, .usd])
    }

    @Test func currencyCodeDescriptionIsTheCode() {
        #expect("\(CurrencyCode.eur)" == "EUR")
        #expect(String(describing: CurrencyCode.czk) == "CZK")
    }

    @Test func currencyCodeIsCodedAsABareString() throws {
        let encoded = try JSONEncoder().encode(CurrencyCode.usd)
        #expect(String(decoding: encoded, as: UTF8.self) == "\"USD\"")
        #expect(try JSONDecoder().decode(CurrencyCode.self, from: Data("\"EUR\"".utf8)) == .eur)
    }

    @Test(arguments: ["\"eur\"", "\"EURO\"", "\"\"", "7", "null", "{\"code\":\"EUR\"}"])
    func currencyCodeDecodingRejectsMalformedInput(_ json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CurrencyCode.self, from: Data(json.utf8))
        }
    }

    // MARK: Money

    @Test func moneyHoldsMinorUnitsAndCurrency() {
        var price = Money(minor: 1435000, currency: .usd)
        #expect(price.minor == 1435000)
        #expect(price.currency == .usd)
        price.minor = -5
        price.currency = .czk
        #expect(price == Money(minor: -5, currency: .czk))
    }

    @Test func moneyEqualityAndHashingUseBothFields() {
        let hundredCrowns = Money(minor: 100, currency: .czk)
        #expect(hundredCrowns == Money(minor: 100, currency: .czk))
        #expect(hundredCrowns != Money(minor: 101, currency: .czk))
        #expect(hundredCrowns != Money(minor: 100, currency: .eur))
        let distinct: Set = [hundredCrowns, Money(minor: 100, currency: .czk), Money(minor: 100, currency: .eur)]
        #expect(distinct.count == 2)
    }

    @Test func moneyJSONShape() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Money(minor: 1435000, currency: .usd))
        #expect(String(decoding: data, as: UTF8.self) == "{\"currency\":\"USD\",\"minor\":1435000}")
    }

    @Test func moneyRoundTripsThroughJSONAcrossTheInt64Range() throws {
        for minor in [Int64.min, -1, 0, 1, Int64.max] {
            let money = Money(minor: minor, currency: .czk)
            let decoded = try JSONDecoder().decode(Money.self, from: JSONEncoder().encode(money))
            #expect(decoded == money)
        }
    }

    // MARK: DecimalMath — rounding to an integer

    @Test func halfUpRoundsHalvesAwayFromZero() {
        #expect(DecimalMath.halfUp(Decimal(string: "2.5")!) == 3)
        #expect(DecimalMath.halfUp(Decimal(string: "-2.5")!) == -3)
        #expect(DecimalMath.halfUp(Decimal(string: "0.5")!) == 1)
        #expect(DecimalMath.halfUp(Decimal(string: "-0.5")!) == -1)
        // Banker's rounding would give 2130 here.
        #expect(DecimalMath.halfUp(Decimal(string: "2130.5")!) == 2131)
    }

    @Test func halfUpRoundsEverythingElseToTheNearestInteger() {
        let cases: [(String, Int64)] = [
            ("0", 0), ("0.4999", 0), ("-0.4999", 0), ("1.4999", 1), ("1.5001", 2),
            ("-1.4999", -1), ("-1.5001", -2), ("30572675", 30_572_675), ("-30572675.49", -30_572_675),
            ("123456.164", 123_456), ("-123456.164", -123_456),
            ("0.4999999999999999999999999999999999999", 0),
            ("0.5000000000000000000000000000000000001", 1),
        ]
        for (input, expected) in cases {
            #expect(DecimalMath.halfUp(Decimal(string: input)!) == expected, "halfUp(\(input))")
        }
    }

    @Test func floorRoundsTowardNegativeInfinity() {
        #expect(DecimalMath.floor(Decimal(string: "-1.5")!) == -2)
        let cases: [(String, Int64)] = [
            ("1.5", 1), ("-0.4", -1), ("0.4", 0), ("-0.0001", -1), ("0.9999", 0),
            ("123456.164", 123_456), ("-123456.164", -123_457), ("2", 2), ("-2", -2), ("0", 0),
        ]
        for (input, expected) in cases {
            #expect(DecimalMath.floor(Decimal(string: input)!) == expected, "floor(\(input))")
        }
    }

    @Test func ceilRoundsTowardPositiveInfinity() {
        #expect(DecimalMath.ceil(Decimal(string: "123456.164")!) == 123457)
        let cases: [(String, Int64)] = [
            ("-1.5", -1), ("1.5", 2), ("-0.4", 0), ("0.0001", 1), ("-0.9999", 0),
            ("-123456.164", -123_456), ("2", 2), ("-2", -2), ("0", 0),
        ]
        for (input, expected) in cases {
            #expect(DecimalMath.ceil(Decimal(string: input)!) == expected, "ceil(\(input))")
        }
    }

    @Test func integerResultsCoverTheWholeInt64Range() {
        #expect(DecimalMath.halfUp(Decimal(Int64.max)) == Int64.max)
        #expect(DecimalMath.halfUp(Decimal(Int64.min)) == Int64.min)
        #expect(DecimalMath.floor(Decimal(Int64.max)) == Int64.max)
        #expect(DecimalMath.ceil(Decimal(Int64.min)) == Int64.min)
        #expect(DecimalMath.halfUp(Decimal(string: "9223372036854775806.5")!) == Int64.max)
        #expect(DecimalMath.halfUp(Decimal(string: "-9223372036854775807.5")!) == Int64.min)
        #expect(DecimalMath.floor(Decimal(string: "9223372036854775807.9")!) == Int64.max)
        #expect(DecimalMath.ceil(Decimal(string: "-9223372036854775808.9")!) == Int64.min)
    }

    // MARK: DecimalMath — rounded(_:scale:_:)

    @Test func roundedHonoursScaleAndMode() {
        let x = Decimal(string: "21.305")!
        #expect(DecimalMath.rounded(x, scale: 2, .plain) == Decimal(string: "21.31")!)
        #expect(DecimalMath.rounded(x, scale: 2, .bankers) == Decimal(string: "21.3")!)
        #expect(DecimalMath.rounded(x, scale: 2, .down) == Decimal(string: "21.3")!)
        #expect(DecimalMath.rounded(x, scale: 2, .up) == Decimal(string: "21.31")!)
        #expect(DecimalMath.rounded(Decimal(string: "-21.305")!, scale: 2, .plain) == Decimal(string: "-21.31")!)
        #expect(DecimalMath.rounded(Decimal(string: "-21.305")!, scale: 2, .down) == Decimal(string: "-21.31")!)
        #expect(DecimalMath.rounded(Decimal(string: "-21.305")!, scale: 2, .up) == Decimal(string: "-21.3")!)
        #expect(DecimalMath.rounded(x, scale: 5, .plain) == x)
    }

    @Test func roundedWithNegativeScaleRoundsToHundreds() {
        // The rounded tax base is the floor to 100 Kč.
        let base = Decimal(string: "123456.164")!
        #expect(DecimalMath.rounded(base, scale: -2, .down) == Decimal(string: "123400")!)
        #expect(DecimalMath.rounded(base, scale: -2, .up) == Decimal(string: "123500")!)
        #expect(DecimalMath.rounded(base, scale: -2, .plain) == Decimal(string: "123500")!)
        #expect(DecimalMath.rounded(Decimal(string: "-123456.164")!, scale: -2, .down) == Decimal(string: "-123500")!)
    }

    // MARK: DecimalMath — decimal(_:)

    @Test func decimalParsesPlainPosixNumbers() {
        #expect(DecimalMath.decimal("21.622") == Decimal(string: "21.622")!)
        #expect(DecimalMath.decimal("0.15") == Decimal(string: "0.15")!)
        #expect(DecimalMath.decimal("-0.5") == Decimal(string: "-0.5")!)
        #expect(DecimalMath.decimal("100") == Decimal(100))
        #expect(DecimalMath.decimal("007") == Decimal(7))
        #expect(DecimalMath.decimal("21.60") == Decimal(string: "21.6")!)
        #expect(DecimalMath.decimal("0") == Decimal(0))
        #expect(DecimalMath.decimal("-0") == Decimal(0))
        #expect(DecimalMath.decimal("0.0") == Decimal(0))
        #expect(DecimalMath.decimal("9223372036854775807") == Decimal(Int64.max))
        #expect(DecimalMath.decimal("-9223372036854775808") == Decimal(Int64.min))
    }

    /// `Decimal(string:)` alone would read "21,622" as 21 and "12abc" as 12, so the parser must not rely on it.
    @Test(arguments: [
        "", "-", ".", "-.", "21,622", "12abc", " 12", "12 ", "+5", ".5", "5.", "-.5", "1e3", "1E3", "1.2.3",
        "--5", "1..5", "5-", "NaN", "Infinity", "1 000", "1_000", "0x10",
        "\u{2212}5",  // U+2212 is not the ASCII hyphen
        "\u{0661}\u{0662}",  // Arabic-Indic digits
        "\u{FF11}\u{FF12}",  // fullwidth digits
    ])
    func decimalRejectsAnythingButPlainPosixText(_ text: String) {
        #expect(DecimalMath.decimal(text) == nil)
    }

    @Test func decimalNeverRoundsSilently() {
        let thirtyEightNines = String(repeating: "9", count: 38)
        #expect(DecimalMath.decimal(thirtyEightNines) == Decimal(string: thirtyEightNines)!)
        #expect(DecimalMath.decimal(String(repeating: "9", count: 39)) == nil)
        #expect(DecimalMath.decimal("0." + String(repeating: "1", count: 38)) != nil)
        #expect(DecimalMath.decimal("0." + String(repeating: "1", count: 40)) == nil)
        #expect(DecimalMath.decimal("1." + String(repeating: "0", count: 5) + "1") != nil)
        // Exact because the digits after the leading 1 are zeros.
        let tenToTheFortieth = "1" + String(repeating: "0", count: 40)
        #expect(DecimalMath.decimal(tenToTheFortieth).map(DecimalMath.canonical) == tenToTheFortieth)
        // Beyond the exponent range.
        #expect(DecimalMath.decimal("1" + String(repeating: "0", count: 200)) == nil)
        #expect(DecimalMath.decimal("0." + String(repeating: "0", count: 200) + "1") == nil)
    }

    // MARK: DecimalMath — canonical(_:)

    @Test func canonicalPrintsPlainPosixText() {
        #expect(DecimalMath.canonical(Decimal(string: "21.622")!) == "21.622")
        #expect(DecimalMath.canonical(Decimal(0)) == "0")
        #expect(DecimalMath.canonical(Decimal(string: "-0.5")!) == "-0.5")
        #expect(DecimalMath.canonical(Decimal(1000)) == "1000")
        #expect(DecimalMath.canonical(Decimal(sign: .plus, exponent: 3, significand: 1)) == "1000")
        #expect(DecimalMath.canonical(Decimal(string: "0.0000000001")!) == "0.0000000001")
        #expect(DecimalMath.canonical(Decimal(Int64.max)) == "9223372036854775807")
        #expect(DecimalMath.canonical(Decimal(Int64.min)) == "-9223372036854775808")
    }

    @Test func canonicalHasNoTrailingZerosAndNoNegativeZero() {
        #expect(DecimalMath.canonical(Decimal(string: "21.60")!) == "21.6")
        #expect(DecimalMath.canonical(Decimal(string: "100.00")!) == "100")
        #expect(DecimalMath.canonical(Decimal(string: "0.0")!) == "0")
        #expect(DecimalMath.canonical(Decimal(string: "-0.0")!) == "0")
        #expect(DecimalMath.canonical(DecimalMath.rounded(Decimal(string: "-0.4")!, scale: 0, .plain)) == "0")
        #expect(DecimalMath.canonical(Decimal(string: "2.50")! * Decimal(2)) == "5")
    }

    /// A decimal whose mantissa still carries trailing zeros (2160 × 10⁻², not compacted) prints the same as 21.6.
    @Test func canonicalIsTheSameForDifferentInternalForms() {
        let uncompacted = Decimal(
            _exponent: -2, _length: 1, _isNegative: 0, _isCompact: 0, _reserved: 0,
            _mantissa: (2160, 0, 0, 0, 0, 0, 0, 0)
        )
        #expect(uncompacted == Decimal(string: "21.6")!)
        #expect(DecimalMath.canonical(uncompacted) == "21.6")
        let negativeUncompacted = Decimal(
            _exponent: -4, _length: 1, _isNegative: 1, _isCompact: 0, _reserved: 0,
            _mantissa: (1200, 0, 0, 0, 0, 0, 0, 0)
        )
        #expect(DecimalMath.canonical(negativeUncompacted) == "-0.12")
    }

    @Test func canonicalAndDecimalAreInverseForCanonicalText() {
        let texts = [
            "0", "1", "-1", "21.622", "0.15", "-0.0001", "100", "12345.6789", "9223372036854775807",
            "-9223372036854775808", "99999999999999999999999999999999999999",
            "0.00000000000000000000000000000000000001",
        ]
        for text in texts {
            #expect(DecimalMath.decimal(text).map(DecimalMath.canonical) == text, "round trip of \(text)")
        }
    }

    // MARK: ExchangeRate

    @Test func exchangeRateConvertsHalfUp() {
        let usd = ExchangeRate(currency: .usd, amount: 1, rate: Decimal(string: "21.305")!)
        // Banker's rounding would give 2130.
        #expect(usd.czkHalere(fromMinor: 100) == 2131)
        #expect(usd.czkHalere(fromMinor: 1435000) == 30572675)
        let yen = ExchangeRate(currency: CurrencyCode("JPY")!, amount: 100, rate: Decimal(string: "14.232")!)
        #expect(yen.czkHalere(fromMinor: 1000000) == 142320)
    }

    @Test func exchangeRateRoundsNegativeAmountsAwayFromZero() {
        let usd = ExchangeRate(currency: .usd, amount: 1, rate: Decimal(string: "21.305")!)
        #expect(usd.czkHalere(fromMinor: -100) == -2131)
        #expect(usd.czkHalere(fromMinor: 0) == 0)
    }

    @Test func exchangeRateDividesByTheQuotedAmount() {
        // 10 000,00 IDR at 1,289 Kč per 1000 IDR is 12,89 Kč.
        let rupiah = ExchangeRate(currency: CurrencyCode("IDR")!, amount: 1000, rate: Decimal(string: "1.289")!)
        #expect(rupiah.czkHalere(fromMinor: 1_000_000) == 1289)
        // The formula is minor × rate ÷ amount, so a quoted amount that is not a power of ten works too:
        // 333 × 0,5 ÷ 3 is exactly 55,5 haléře, which rounds up to 56.
        let odd = ExchangeRate(currency: .eur, amount: 3, rate: Decimal(string: "0.5")!)
        #expect(odd.czkHalere(fromMinor: 333) == 56)
    }

    @Test func exchangeRateIsExactBeyondDoublePrecision() {
        let usd = ExchangeRate(currency: .usd, amount: 1, rate: Decimal(string: "21.305")!)
        // The product is 21 305 000 000 000 021,305 haléře: 20 significant digits, while a Double holds about 16,
        // so only exact decimal arithmetic gets the last digits right.
        #expect(usd.czkHalere(fromMinor: 1_000_000_000_000_001) == 21_305_000_000_000_021)
    }

    @Test func exchangeRateEqualityUsesAllFields() {
        let base = ExchangeRate(currency: .usd, amount: 1, rate: Decimal(string: "21.305")!)
        #expect(base == ExchangeRate(currency: .usd, amount: 1, rate: Decimal(string: "21.3050")!))
        #expect(base != ExchangeRate(currency: .eur, amount: 1, rate: Decimal(string: "21.305")!))
        #expect(base != ExchangeRate(currency: .usd, amount: 100, rate: Decimal(string: "21.305")!))
        #expect(base != ExchangeRate(currency: .usd, amount: 1, rate: Decimal(string: "21.306")!))
    }

    @Test func exchangeRateRoundTripsThroughJSONExactly() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let yen = ExchangeRate(currency: CurrencyCode("JPY")!, amount: 100, rate: Decimal(string: "14.232")!)
        let data = try encoder.encode(yen)
        #expect(String(decoding: data, as: UTF8.self) == "{\"amount\":100,\"currency\":\"JPY\",\"rate\":14.232}")
        #expect(try JSONDecoder().decode(ExchangeRate.self, from: data) == yen)
    }
}

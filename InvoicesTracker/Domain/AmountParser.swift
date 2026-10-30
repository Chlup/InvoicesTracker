import Foundation

/// Reads amounts and numbers typed by hand, in Czech style (`1 000,50`) or English style (`1000.5`).
///
/// A text is accepted only when there is exactly one way to read it, so a typed amount is parsed exactly or
/// rejected, never silently mis-scaled:
/// - an optional leading `-` or `−` (U+2212),
/// - ASCII digits, in one run or grouped the Czech way by spaces (U+0020, U+00A0 or U+202F) in the whole part:
///   the first group has one to three digits and every later group exactly three (`13 340`, `1 000 000`),
/// - optionally one decimal separator, `,` or `.`, with digits on both sides.
///
/// Anything else gives nil: a second separator (`1.234,50` and `1,234.50` could mean two different amounts), more
/// fraction digits than allowed (`12,345` could be 12.345 or 12 345), a space where a group of three digits belongs
/// (`12 50` is most likely a comma typed as a space), a `+`, a currency symbol, digits of other scripts.
/// Whitespace around the whole text is ignored.
///
/// Typed values are also bounded, far from overflowing `Int64`: an amount must be below 10 000 000 000 currency
/// units and a rate, quantity or percentage below 1 000 000. Leading zeros do not count.
nonisolated enum AmountParser {
    /// Amounts have at most this many digits in the whole part, so they are below 10¹⁰ currency units and
    /// 10¹² minor units. Times a typed rate (below 10⁶) they stay below 10¹⁸, which fits in `Int64`.
    private static let maxAmountIntegerDigits = 10

    /// Rates, quantities and percentages have at most this many digits in the whole part: they are below 10⁶.
    private static let maxNumberIntegerDigits = 6

    /// A typed amount in minor units (hundredths), with at most two fraction digits: `1 000,50` gives 100050.
    /// Nil if the text is not an amount or the amount is 10 000 000 000 currency units or more.
    static func minor(_ text: String) -> Int64? {
        guard let number = scan(text),
            number.fractionDigits.count <= 2,
            number.significantIntegerDigitCount <= maxAmountIntegerDigits
        else {
            return nil
        }
        let zero = UInt8(ascii: "0")
        let fractionDigits = number.fractionDigits + Array(repeating: zero, count: 2 - number.fractionDigits.count)
        // At most 12 significant digits, far from the 19 that Int64 holds.
        var value: Int64 = 0
        for digit in number.integerDigits + fractionDigits {
            value = value * 10 + Int64(digit - zero)
        }
        return number.isNegative ? -value : value
    }

    /// A typed amount in whole crowns: `13 340` gives 13340. A fraction is accepted only when it is zero
    /// (`13 340,00`). Nil if the amount has haléře or is 10 000 000 000 Kč or more.
    static func wholeKc(_ text: String) -> Int64? {
        guard let halere = minor(text), halere % 100 == 0 else { return nil }
        return halere / 100
    }

    /// A typed number such as a rate, a quantity or a percentage, with at most `maxFractionDigits` digits after
    /// the separator, counted as typed (`6,500` has three). Nil if the text is not such a number, the number is
    /// 1 000 000 or more, or `Decimal` cannot hold it exactly.
    static func decimal(_ text: String, maxFractionDigits: Int) -> Decimal? {
        precondition(maxFractionDigits >= 0, "The number of fraction digits cannot be negative.")
        guard let number = scan(text),
            number.fractionDigits.count <= maxFractionDigits,
            number.significantIntegerDigitCount <= maxNumberIntegerDigits
        else {
            return nil
        }
        var posix = number.isNegative ? "-" : ""
        posix += String(decoding: number.integerDigits, as: UTF8.self)
        if !number.fractionDigits.isEmpty {
            posix += "." + String(decoding: number.fractionDigits, as: UTF8.self)
        }
        return DecimalMath.decimal(posix)
    }

    /// The parts of a typed number. The digits are ASCII bytes.
    private nonisolated struct Number {
        var isNegative = false
        var integerDigits: [UInt8] = []
        var fractionDigits: [UInt8] = []

        /// The digits of the whole part without leading zeros, which is what the size limits count.
        var significantIntegerDigitCount: Int {
            integerDigits.drop(while: { $0 == UInt8(ascii: "0") }).count
        }
    }

    /// Splits a typed number into sign, whole-part digits and fraction digits, or returns nil if it is not
    /// written in one of the accepted forms.
    private static func scan(_ text: String) -> Number? {
        var number = Number()
        var groupLengths = [0]  // the digits in each space-separated group of the whole part
        var isInFraction = false
        var isGroupingPending = false
        var isAtStart = true
        for scalar in text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
            switch scalar {
            case "-", "\u{2212}":
                guard isAtStart else { return nil }
                number.isNegative = true
            case "0"..."9":
                if isInFraction {
                    number.fractionDigits.append(UInt8(scalar.value))
                } else {
                    number.integerDigits.append(UInt8(scalar.value))
                    groupLengths[groupLengths.count - 1] += 1
                }
                isGroupingPending = false
            case " ", "\u{00A0}", "\u{202F}":
                // Grouping only separates digits of the whole part. Several spaces in a row are one separator.
                guard !isInFraction, !number.integerDigits.isEmpty else { return nil }
                if !isGroupingPending {
                    groupLengths.append(0)
                }
                isGroupingPending = true
            case ",", ".":
                guard !isInFraction, !number.integerDigits.isEmpty, !isGroupingPending else { return nil }
                isInFraction = true
            default:
                return nil
            }
            isAtStart = false
        }
        guard !number.integerDigits.isEmpty,
            !isInFraction || !number.fractionDigits.isEmpty,
            hasCzechGroups(groupLengths)
        else {
            return nil
        }
        return number
    }

    /// Whether the digit groups of a whole part are the Czech ones: if a space separates any, the first has one to
    /// three digits and every later one exactly three. Digits without a space form one group of any length.
    private static func hasCzechGroups(_ lengths: [Int]) -> Bool {
        guard lengths.count > 1 else { return true }
        return (1...3).contains(lengths[0]) && lengths.dropFirst().allSatisfy { $0 == 3 }
    }
}

import Foundation

/// Exact decimal helpers. Rates and quantities are `Decimal` values made from strings or integers, never from
/// floating-point literals, and every rounding goes through here so the mode is always spelled out.
nonisolated enum DecimalMath {
    /// Rounds to the nearest whole number, halves away from zero (2.5 gives 3, −2.5 gives −3).
    /// Traps if the result does not fit in `Int64`.
    static func halfUp(_ x: Decimal) -> Int64 {
        int64(rounded(x, scale: 0, .plain))
    }

    /// Rounds toward negative infinity (−1.5 gives −2). Traps if the result does not fit in `Int64`.
    static func floor(_ x: Decimal) -> Int64 {
        int64(rounded(x, scale: 0, .down))
    }

    /// Rounds toward positive infinity (123456.164 gives 123457). Traps if the result does not fit in `Int64`.
    static func ceil(_ x: Decimal) -> Int64 {
        int64(rounded(x, scale: 0, .up))
    }

    /// Rounds `x` to `scale` digits after the decimal point. A negative scale rounds to tens, hundreds and so on,
    /// so `scale: -2` with `.down` is the floor to 100.
    static func rounded(_ x: Decimal, scale: Int, _ mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = x
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, mode)
        return result
    }

    /// Rounds each of `values` to a whole number so that the numbers add up to `total` rounded to a whole number
    /// (`halfUp`), which is returned too. Rounding each value on its own could leave the numbers a unit short of that
    /// sum, or a unit over it, so each is rounded down (`floor`) and the units that are left go one each to the values
    /// with the largest remainders, the one with the lower index first when two remainders are equal. The values are
    /// meant to add up to `total`: then there are no more units left than values, and the numbers add up to the rounded
    /// total. Traps if a rounded number does not fit in `Int64`.
    static func roundedKeepingSum(_ values: [Decimal], total: Decimal) -> (parts: [Int64], total: Int64) {
        var parts = values.map { floor($0) }
        let rounded = halfUp(total)
        var left = rounded - parts.reduce(0, +)
        let remainders = zip(values, parts).map { $0 - Decimal($1) }
        let byRemainder = values.indices.sorted { first, second in
            remainders[first] != remainders[second] ? remainders[first] > remainders[second] : first < second
        }
        for index in byRemainder where left > 0 {
            parts[index] += 1
            left -= 1
        }
        return (parts, rounded)
    }

    /// Parses plain POSIX text such as `21.622`: an optional `-`, ASCII digits, and optionally a point followed by
    /// digits. Anything else gives nil, and so does a number that `Decimal` cannot hold exactly.
    ///
    /// `Decimal(string:)` alone is not safe for this: it reads a prefix (`21,622` becomes 21, `12abc` becomes 12) and
    /// rounds digits beyond its 38-digit precision without a word. So the text is validated first, and the parsed
    /// value must print back as the same number.
    static func decimal(_ text: String) -> Decimal? {
        guard let plain = PlainText(text),
            let value = Decimal(string: text),
            value.isFinite,
            canonical(value) == plain.normalized
        else {
            return nil
        }
        return value
    }

    /// The one plain text for a value: a point as the separator, no exponent, no trailing zeros and no negative
    /// zero (`21.6`, `100`, `-0.5`, `0`). It is the form to store, and `decimal(_:)` reads it back exactly.
    /// Traps for NaN, which has no text.
    static func canonical(_ d: Decimal) -> String {
        precondition(d.isFinite, "A decimal that is not a number has no canonical text.")
        var value = d
        NSDecimalCompact(&value)
        return NSDecimalString(&value, nil)
    }

    /// Converts a decimal that is already a whole number. Going through the text keeps every digit and, unlike
    /// `NSDecimalNumber.int64Value`, reports an overflow instead of wrapping around.
    private static func int64(_ whole: Decimal) -> Int64 {
        guard whole.isFinite, let value = Int64(canonical(whole)) else {
            preconditionFailure("A rounded decimal does not fit in Int64.")
        }
        return value
    }

    /// The digits of a text that matches `-?[0-9]+(\.[0-9]+)?`.
    private nonisolated struct PlainText {
        var isNegative = false
        var integerDigits: [UInt8] = []
        var fractionDigits: [UInt8] = []

        init?(_ text: String) {
            let bytes = Array(text.utf8)
            var index = 0
            if bytes.first == UInt8(ascii: "-") {
                isNegative = true
                index = 1
            }
            let integerStart = index
            while index < bytes.count, Self.isDigit(bytes[index]) {
                index += 1
            }
            integerDigits = Array(bytes[integerStart..<index])
            guard !integerDigits.isEmpty else { return nil }
            guard index < bytes.count else { return }
            guard bytes[index] == UInt8(ascii: ".") else { return nil }
            index += 1
            let fractionStart = index
            while index < bytes.count, Self.isDigit(bytes[index]) {
                index += 1
            }
            fractionDigits = Array(bytes[fractionStart..<index])
            guard !fractionDigits.isEmpty, index == bytes.count else { return nil }
        }

        /// The text `canonical(_:)` prints for this number: no leading zeros, no trailing zeros in the fraction
        /// and no sign on zero.
        var normalized: String {
            let zero = UInt8(ascii: "0")
            let integer = integerDigits.drop(while: { $0 == zero })
            var fraction = fractionDigits[...]
            while fraction.last == zero {
                fraction = fraction.dropLast()
            }
            let isZero = integer.isEmpty && fraction.isEmpty
            var text = isNegative && !isZero ? "-" : ""
            text += integer.isEmpty ? "0" : String(decoding: integer, as: UTF8.self)
            if !fraction.isEmpty {
                text += "." + String(decoding: fraction, as: UTF8.self)
            }
            return text
        }

        private static func isDigit(_ byte: UInt8) -> Bool {
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
        }
    }
}

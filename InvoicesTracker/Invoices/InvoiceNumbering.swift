import Foundation

/// Invoice numbers and the variable symbol that goes with them.
///
/// A number written by the app is `YYYYMMNN`: the year and the month of the taxable supply, and the sequence number of
/// the invoice in that month. An imported invoice may carry any text (`2026-05-01`, `Z20261001`). What numbers are
/// unique by, and what the variable symbol is, are their digits, so `2026-05-01` and `20260501` are the same number.
nonisolated enum InvoiceNumbering {
    private static let yearDigitCount = 4
    private static let monthDigitCount = 2
    private static let sequenceDigitCount = 2
    private static let asciiDigits: ClosedRange<Unicode.Scalar> = "0"..."9"

    /// The digits of `number`, in order: `20260501` for `2026-05-01`. Only the ASCII digits 0 to 9 are digits.
    static func digits(of number: String) -> String {
        String(String.UnicodeScalarView(number.unicodeScalars.filter { asciiDigits.contains($0) }))
    }

    /// The variable symbol of an invoice: the digits of its number.
    static func variableSymbol(of number: String) -> String {
        digits(of: number)
    }

    /// The number to propose for an invoice whose taxable supply is on `duzp`: the year and the month of the DUZP and a
    /// sequence number one above the highest one among the numbers already used in that month. A gap is not filled.
    ///
    /// A number counts when its digits are eight long and start with the year and the month, so an imported
    /// `2026-09-02` counts as `20260902` and a number of another shape (`2026090007`) does not count at all.
    ///
    /// The sequence number has two digits. The hundredth number of a month would be nine digits long and is not
    /// counted afterwards, so the proposal repeats it, and the person has to type a number of their own.
    static func next(forDUZP duzp: CivilDate, existingNumbers: [String]) -> String {
        let prefix = padded(duzp.year, width: yearDigitCount) + padded(duzp.month, width: monthDigitCount)
        let length = prefix.utf8.count + sequenceDigitCount
        var highest = 0
        for number in existingNumbers {
            let numberDigits = digits(of: number)
            if numberDigits.utf8.count == length, numberDigits.hasPrefix(prefix) {
                highest = max(highest, sequence(of: numberDigits))
            }
        }
        return prefix + padded(highest + 1, width: sequenceDigitCount)
    }

    /// The value of the last digits of a number, where the sequence number is.
    private static func sequence(of numberDigits: String) -> Int {
        let zero = UInt8(ascii: "0")
        return numberDigits.utf8.suffix(sequenceDigitCount).reduce(0) { $0 * 10 + Int($1 - zero) }
    }

    private static func padded(_ value: Int, width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}

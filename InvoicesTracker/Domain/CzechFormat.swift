import Foundation

/// Czech number and date text. It is built by hand rather than with `NumberFormatter` or `DateFormatter`, so the
/// result is the same on every Mac whatever its locale: a no-break space (U+00A0) between thousands and after each
/// dot of a date, a decimal comma, and the minus sign U+2212.
nonisolated enum CzechFormat {
    private static let noBreakSpace = "\u{00A0}"
    private static let minus = "\u{2212}"

    /// A whole number with its thousands separated: `1 234 567`.
    static func grouped(_ n: Int64) -> String {
        sign(of: n) + groupThousands(String(n.magnitude))
    }

    /// Whole crowns: `110 844 Kč`.
    static func wholeKc(_ kc: Int64) -> String {
        grouped(kc) + noBreakSpace + "Kč"
    }

    /// An amount in haléře shown as crowns: `2 191 771,35 Kč`.
    static func halere(_ h: Int64) -> String {
        amount(h) + noBreakSpace + "Kč"
    }

    /// An amount in minor units with two decimals and no currency: `14 350,00`.
    static func amount(_ minor: Int64) -> String {
        let magnitude = minor.magnitude
        let fraction = magnitude % 100
        let wholePart = groupThousands(String(magnitude / 100))
        return sign(of: minor) + wholePart + "," + (fraction < 10 ? "0" : "") + String(fraction)
    }

    /// An amount with its currency: `14 350,00 USD`, and `Kč` for crowns.
    static func money(_ m: Money) -> String {
        if m.currency.isCZK {
            return halere(m.minor)
        }
        return amount(m.minor) + noBreakSpace + m.currency.code
    }

    /// `17. 10. 2026`: no leading zeros, a no-break space after each dot.
    static func date(_ d: CivilDate) -> String {
        dayMonth(d) + noBreakSpace + String(d.year)
    }

    /// `17. 10.`
    static func dayMonth(_ d: CivilDate) -> String {
        "\(d.day).\(noBreakSpace)\(d.month)."
    }

    /// An exchange rate with exactly `fractionDigits` decimals, rounded half up: `21,622`.
    /// `fractionDigits` must not be negative.
    static func rate(_ r: Decimal, fractionDigits: Int = 3) -> String {
        fixed(r, fractionDigits: fractionDigits)
    }

    /// An exchange rate with what it is for: `21,622 Kč/USD`. A rate quoted for more than one unit says how many,
    /// before the currency and with its thousands grouped: `6,220 Kč/100 HUF` and `1,204 Kč/1 000 IDR`. The rate has
    /// three decimals and a no-break space before `Kč`; the quantity has a plain space before the currency.
    static func rateLabel(_ rate: ExchangeRate) -> String {
        let code = rate.currency.code
        let unit = rate.amount == 1 ? code : grouped(Int64(rate.amount)) + " " + code
        return Self.rate(rate.rate) + noBreakSpace + "Kč/" + unit
    }

    /// A fraction shown as a percentage with exactly `fractionDigits` decimals, rounded half up: `37,8 %`.
    /// `fractionDigits` must not be negative.
    static func percent(_ fraction: Decimal, fractionDigits: Int = 1) -> String {
        fixed(fraction * 100, fractionDigits: fractionDigits) + noBreakSpace + "%"
    }

    /// The months in the nominative, January first.
    static let monthNames = [
        "leden", "únor", "březen", "duben", "květen", "červen",
        "červenec", "srpen", "září", "říjen", "listopad", "prosinec",
    ]

    /// Three-letter month abbreviations, January first.
    static let monthShort = [
        "led", "úno", "bře", "dub", "kvě", "čvn",
        "čvc", "srp", "zář", "říj", "lis", "pro",
    ]

    // MARK: Helpers

    private static func sign(of n: Int64) -> String {
        n < 0 ? minus : ""
    }

    /// `value` rounded half up to `fractionDigits` decimals, always showing all of them. Going through the canonical
    /// text keeps every digit, whatever the size of the number. A value that rounds to zero has no sign.
    private static func fixed(_ value: Decimal, fractionDigits: Int) -> String {
        precondition(fractionDigits >= 0, "The number of fraction digits cannot be negative.")
        let text = DecimalMath.canonical(DecimalMath.rounded(value, scale: fractionDigits, .plain))
        let isNegative = text.hasPrefix("-")
        let parts = (isNegative ? text.dropFirst() : text[...]).split(separator: ".", omittingEmptySubsequences: false)
        var result = (isNegative ? minus : "") + groupThousands(parts[0])
        if fractionDigits > 0 {
            let fraction = parts.count > 1 ? parts[1] : ""
            result += "," + fraction + String(repeating: "0", count: fractionDigits - fraction.count)
        }
        return result
    }

    private static func groupThousands(_ digits: some StringProtocol) -> String {
        let count = digits.count
        var result = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0 && (count - offset) % 3 == 0 {
                result += noBreakSpace
            }
            result.append(digit)
        }
        return result
    }
}

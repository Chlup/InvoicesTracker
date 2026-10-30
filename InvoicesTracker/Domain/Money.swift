import Foundation

/// An ISO 4217 currency code: exactly three ASCII capitals. It is coded as the bare string, `"USD"`.
nonisolated struct CurrencyCode: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    let code: String

    /// Returns nil unless `code` is exactly three ASCII capital letters (`[A-Z]{3}`).
    init?(_ code: String) {
        let capitals = UInt8(ascii: "A")...UInt8(ascii: "Z")
        guard code.utf8.count == 3, code.utf8.allSatisfy({ capitals.contains($0) }) else {
            return nil
        }
        self.code = code
    }

    private init(validated code: String) {
        self.code = code
    }

    static let czk = CurrencyCode(validated: "CZK")
    static let usd = CurrencyCode(validated: "USD")
    static let eur = CurrencyCode(validated: "EUR")

    var isCZK: Bool {
        self == .czk
    }

    var description: String {
        code
    }

    static func < (lhs: CurrencyCode, rhs: CurrencyCode) -> Bool {
        lhs.code < rhs.code
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let parsed = CurrencyCode(text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a currency code of three capital letters."
            )
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }
}

/// An amount in the minor units of its currency: haléře for CZK and hundredths for every other currency.
nonisolated struct Money: Hashable, Sendable, Codable {
    var minor: Int64
    var currency: CurrencyCode
}

import Foundation

/// Counts with their Czech nouns, which change with the number: 1 den, 2 až 4 dny, otherwise dní.
nonisolated enum CzechCount {
    /// The word for `count` days: "den" for 1, "dny" for 2 to 4, and "dní" for any other number.
    static func dayWord(_ count: Int) -> String {
        switch count {
        case 1: "den"
        case 2...4: "dny"
        default: "dní"
        }
    }

    /// "1 den", "3 dny", "14 dní", "0 dní".
    static func days(_ count: Int) -> String {
        "\(count) \(dayWord(count))"
    }
}

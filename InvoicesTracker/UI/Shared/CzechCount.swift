import Foundation

/// Counts with their Czech nouns, which change with the number: one form for 1 (1 den), one for 2 to 4 (2 dny) and one
/// for any other number, 0 included (5 dní). The rule is written here and nowhere else. It looks at the whole number,
/// so 22 takes the form of the many.
nonisolated enum CzechCount {
    /// The form of the noun that Czech asks for `count`: `one` for 1, `few` for 2 to 4, and `many` for any other
    /// number, 0 and 22 included.
    static func noun(for count: Int, one: String, few: String, many: String) -> String {
        switch count {
        case 1: one
        case 2...4: few
        default: many
        }
    }

    /// "13 faktur", "1 faktura", "1 000 faktur": `count` grouped in thousands (`CzechFormat.grouped`), `separator` and
    /// the noun in the form for the count. This is the one formatter of a count that the app has, for every count it
    /// shows. The separator is a plain space, as the lines of the screens have it, or a no-break space
    /// (`CzechFormat.noBreakSpace`) where the number must stay on the line of its noun, as in the summary row of
    /// Odběratelé ("3 odběratelé", "1 šablona").
    static func counted(_ count: Int, one: String, few: String, many: String, separator: String = " ") -> String {
        CzechFormat.grouped(Int64(count)) + separator + noun(for: count, one: one, few: few, many: many)
    }

    /// The word for `count` days: "den" for 1, "dny" for 2 to 4, and "dní" for any other number.
    static func dayWord(_ count: Int) -> String {
        noun(for: count, one: "den", few: "dny", many: "dní")
    }

    /// "1 den", "3 dny", "14 dní", "0 dní": the number and its word apart by `separator`, a plain space, or a no-break
    /// space where the number must stay on the line of its word, as in the detail of a client ("30 dní"). Days are
    /// counted like any other noun (`counted(_:one:few:many:separator:)`), so a thousand days are "1 000 dní".
    static func days(_ count: Int, separator: String = " ") -> String {
        counted(count, one: "den", few: "dny", many: "dní", separator: separator)
    }
}

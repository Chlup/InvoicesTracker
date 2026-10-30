import Foundation

/// The months `from` to `to` of one year, both 1 to 12, `from` no later than `to`: the part of the year in which
/// something held, such as a child living in the household.
nonisolated struct MonthRange: Sendable, Hashable, Codable {
    var from: Int
    var to: Int

    /// January to December.
    static let wholeYear = MonthRange(from: 1, to: 12)

    /// Whether the range is one: months 1 to 12, `from` no later than `to`. This is the one place of the rule: the
    /// engine, the stored values and the forms all ask it.
    var isValid: Bool {
        1 <= from && from <= to && to <= 12
    }

    /// Whether `month` is one of the months from `from` to `to`.
    func contains(_ month: Int) -> Bool {
        from <= month && month <= to
    }
}

/// Who claims the child tax benefit for a child in a year: the person the app is for, or the child's other parent.
nonisolated enum Claimant: String, Sendable, Hashable {
    case me
    case otherParent
}

/// A child, kept across the years: the date of birth, which the calculation needs, and a name that only labels the
/// child in the app. `id` is nil until the child is saved.
nonisolated struct Child: Sendable, Hashable, Identifiable {
    var id: Int64?
    var name: String
    var birthDate: CivilDate
}

/// What one year says about a child.
nonisolated struct ChildYear: Sendable, Hashable {
    /// The months the child lived in the household, or nil when it did not live there that year ("V roce Y s vámi
    /// nežije").
    var household: MonthRange?

    /// Who claims the benefit for the child.
    var claimant: Claimant

    /// The order of the child in the household, 1 for the first, which decides the rate of each month.
    var order: Int

    /// The months in which the child held the ZTP/P card, or nil for none.
    var ztpp: MonthRange?

    /// The months of studies after the 18th birthday, or nil for none.
    var studies: MonthRange?
}

/// A child with what a year says about it. `isStored` tells whether the year has a row of its own for the child;
/// without one, `year` is what the year takes from an earlier year or from the defaults (`FamilyResolution`).
nonisolated struct FamilyChild: Sendable, Hashable {
    var child: Child
    var year: ChildYear
    var isStored: Bool
}

/// What one year says about the spouse, for the spouse credit.
nonisolated struct SpouseYear: Sendable, Hashable, Codable {
    /// Whether the credit is claimed. A spouse who is not claimed keeps what was entered.
    var claim: Bool

    /// The months of the year married and living in the household.
    var months: MonthRange

    /// The spouse's own income for the whole year, in whole Kč.
    var ownIncomeKc: Int64

    /// The months in which the spouse held the ZTP/P card, or nil for none.
    var ztpp: MonthRange?
}

/// The family of one year: the children born by its end, oldest first, each with what the year says about it, and the
/// spouse of the year, or nil for none.
nonisolated struct FamilyYear: Sendable, Hashable {
    var year: Int
    var children: [FamilyChild]
    var spouse: SpouseYear?
}

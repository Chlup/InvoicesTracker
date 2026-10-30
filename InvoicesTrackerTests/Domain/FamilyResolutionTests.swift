import Testing
@testable import InvoicesTracker

/// What a year says about a child when it has no row of its own for the child: the row of the nearest earlier year,
/// read for a new year, or the defaults. The children are invented.
struct FamilyResolutionTests {
    private static let anna = Child(id: 1, name: "Anna", birthDate: civilDate("2019-09-03"))
    private static let tomas = Child(id: 2, name: "Tomáš", birthDate: civilDate("2024-04-12"))

    /// A row of a year: in the household the whole year and claimed by me unless told otherwise.
    private static func row(
        household: MonthRange? = MonthRange(from: 1, to: 12),
        claimant: Claimant = .me,
        order: Int = 1,
        ztpp: MonthRange? = nil,
        studies: MonthRange? = nil
    ) -> ChildYear {
        ChildYear(household: household, claimant: claimant, order: order, ztpp: ztpp, studies: studies)
    }

    private static func resolve(
        _ child: Child,
        in year: Int,
        stored: [Int: ChildYear],
        defaultOrder: Int = 1
    ) -> ChildYear {
        FamilyResolution.childYear(for: child, year: year, stored: stored, defaultOrder: defaultOrder)
    }

    @Test func aYearWithoutARowTakesTheEarlierYearsRow() {
        let row2025 = Self.row(household: MonthRange(from: 1, to: 12), claimant: .otherParent, order: 2)

        #expect(Self.resolve(Self.anna, in: 2026, stored: [2025: row2025]) == row2025)
        // The nearest earlier year counts, not an older one, and a later year never does. A year with a row of its
        // own has that row, whatever it says.
        let older = Self.row(order: 3)
        let own = Self.row(household: MonthRange(from: 2, to: 5), claimant: .otherParent, order: 4)
        let stored = [2022: older, 2025: row2025, 2027: own]
        #expect(Self.resolve(Self.anna, in: 2026, stored: stored) == row2025)
        #expect(Self.resolve(Self.anna, in: 2024, stored: stored) == older)
        #expect(Self.resolve(Self.anna, in: 2027, stored: stored) == own)
        #expect(
            Self.resolve(Self.anna, in: 2030, stored: stored)
                == Self.row(household: nil, claimant: .otherParent, order: 4)
        )
    }

    @Test func aChildWhoLeftTheHouseholdStaysOutInLaterYears() {
        let left = Self.row(household: nil, claimant: .otherParent, order: 2)

        #expect(Self.resolve(Self.anna, in: 2026, stored: [2025: left]) == left)
        #expect(Self.resolve(Self.anna, in: 2031, stored: [2025: left]).household == nil)
    }

    @Test func aHouseholdEndingBeforeDecemberMeansOutNextYear() {
        let leftInJune = [2025: Self.row(household: MonthRange(from: 1, to: 6))]
        // One that reaches December is the whole of the next year, from whichever month it started.
        let cameInSeptember = [2025: Self.row(household: MonthRange(from: 9, to: 12))]

        #expect(Self.resolve(Self.anna, in: 2026, stored: leftInJune).household == nil)
        #expect(Self.resolve(Self.anna, in: 2026, stored: cameInSeptember).household == MonthRange(from: 1, to: 12))
    }

    @Test func ztppAndStudiesCarryOnlyWhenTheyReachDecember() {
        let reaching = [2025: Self.row(ztpp: MonthRange(from: 3, to: 12), studies: MonthRange(from: 9, to: 12))]
        let ending = [2025: Self.row(ztpp: MonthRange(from: 1, to: 11), studies: MonthRange(from: 1, to: 6))]

        let carried = Self.resolve(Self.anna, in: 2026, stored: reaching)
        let dropped = Self.resolve(Self.anna, in: 2026, stored: ending)

        #expect(carried.ztpp == MonthRange(from: 1, to: 12))
        #expect(carried.studies == MonthRange(from: 1, to: 12))
        #expect(dropped.ztpp == nil)
        #expect(dropped.studies == nil)
        // Neither is ever made up: none stays none.
        #expect(Self.resolve(Self.anna, in: 2026, stored: [2025: Self.row()]) == Self.row())
    }

    @Test func withoutAnyRowTheDefaultsApply() {
        let resolved = Self.resolve(Self.tomas, in: 2024, stored: [:], defaultOrder: 2)

        #expect(
            resolved
                == ChildYear(household: MonthRange(from: 4, to: 12), claimant: .me, order: 2, ztpp: nil, studies: nil)
        )
        // After the year of birth, the whole year.
        #expect(
            Self.resolve(Self.tomas, in: 2025, stored: [:], defaultOrder: 2)
                == ChildYear(household: MonthRange(from: 1, to: 12), claimant: .me, order: 2, ztpp: nil, studies: nil)
        )
        // A row of a later year is no earlier row: the defaults still apply.
        let later = [2026: Self.row(claimant: .otherParent, order: 5)]
        #expect(Self.resolve(Self.tomas, in: 2024, stored: later, defaultOrder: 2) == resolved)
    }
}

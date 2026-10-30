import Foundation

/// What a year says about a child when the year has no row of its own for the child.
nonisolated enum FamilyResolution {
    /// What `year` says about `child`, given the child's stored rows by year in `stored`.
    ///
    /// A year with a row of its own has that row. A year without one takes the row of the nearest earlier year that
    /// has one, read for a new year:
    /// - the household: the whole year if that row's household reached December, otherwise none (the child left);
    /// - the same claimant and order;
    /// - ZTP/P and studies: the whole year if they reached December, otherwise none.
    ///
    /// With no earlier row, the defaults: in the household the whole year, and in the year of birth from the month of
    /// birth; claimed by me; `defaultOrder`, which is the child's place by the date of birth, the oldest first; no
    /// ZTP/P and no studies. A row of a later year is never used.
    static func childYear(for child: Child, year: Int, stored: [Int: ChildYear], defaultOrder: Int) -> ChildYear {
        if let own = stored[year] {
            return own
        }
        if let earlier = stored.keys.filter({ $0 < year }).max(), let row = stored[earlier] {
            return ChildYear(
                household: carried(row.household), claimant: row.claimant, order: row.order, ztpp: carried(row.ztpp),
                studies: carried(row.studies)
            )
        }
        let firstMonth = child.birthDate.year == year ? child.birthDate.month : 1
        return ChildYear(
            household: MonthRange(from: firstMonth, to: 12), claimant: .me, order: defaultOrder, ztpp: nil,
            studies: nil
        )
    }

    /// A range of an earlier year as a later year takes it: the whole year when it reached December, otherwise none.
    private static func carried(_ range: MonthRange?) -> MonthRange? {
        guard let range, range.to == 12 else { return nil }
        return MonthRange.wholeYear
    }
}

import Foundation

extension Database {
    /// The family of `year`: the children born by 31 December of the year, the oldest first (children born on the same
    /// day in the order they were saved in), each with what the year says about it, and the spouse of the year.
    ///
    /// What the year says about a child is its row of the year, or, for a year without one, what the year takes from
    /// an earlier year's row or from the defaults (`FamilyResolution`), where the default order is the child's place in
    /// the list. Nothing is stored for a year that takes it. The spouse is the year's own, never one of an earlier
    /// year.
    func family(year: Int) throws -> FamilyYear {
        try read { connection in
            try family(year: year, in: connection)
        }
    }

    /// Saves `child` and what `year` says about it, replacing what was stored for the child and that year, and returns
    /// the child's id: a child with `id` nil is inserted and gets a new id, any other is updated in place, or inserted
    /// with that id if no child has it. A year without settings of its own gets them stored first, as
    /// `yearSettings(_:)` gives them, because the row of a child's year belongs to the settings of the year. A value
    /// the tax engine would refuse (a range of months that is not one, an order below 1) is refused with
    /// `SQLiteError.constraint` and nothing is changed, and so is a year before the year of the child's birth: its row
    /// would be the one that the year of birth takes. For the same reason a date of birth moved to a later year takes
    /// the child's rows of the years before the birth with it, in the same write.
    ///
    /// `otherOrders` gives other children of the year their new orders, by id, in the same write, as `setChildOrders`
    /// does: so the orders of the year change together with the child or not at all. Among them, a child that is not in
    /// the family of the year, the child that is saved, and an order below 1 are refused, and nothing is changed.
    @discardableResult
    func saveChild(
        _ child: Child, year: Int, childYear: ChildYear, otherOrders: [Int64: Int] = [:]
    ) throws -> Int64 {
        guard child.birthDate.year <= year else {
            throw SQLiteError.constraint("child_year: the year is before the child's birth.")
        }
        return try write { connection in
            // The others as the year has them: what it says about them does not depend on the child, and the orders
            // that depend on it are given.
            let children = try family(year: year, in: connection).children
            try storeYearSettingsIfMissing(year, in: connection)
            let id = try child.store(in: connection)
            try connection.run(
                "DELETE FROM child_year WHERE child_id = ? AND year < ?", [.integer(id), .int(child.birthDate.year)])
            try childYear.store(childID: id, year: year, in: connection)
            try store(otherOrders, of: children, besides: child.id, year: year, in: connection)
            return id
        }
    }

    /// Gives the children with the ids of `orders` their new order in `year`, in one transaction. A child without a row
    /// of its own for the year gets one: what the year shows for it (`family(year:)`) with the new order. A year
    /// without settings of its own gets them stored first, as `saveChild` does. A child that is not in the family of
    /// the year (no child has the id, or it is born after the year) is refused with `SQLiteError.constraint`, and so
    /// is an order below 1; then nothing is changed.
    func setChildOrders(year: Int, orders: [Int64: Int]) throws {
        guard !orders.isEmpty else { return }
        try write { connection in
            let children = try family(year: year, in: connection).children
            try storeYearSettingsIfMissing(year, in: connection)
            try store(orders, of: children, besides: nil, year: year, in: connection)
        }
    }

    /// Removes the child with `id` from every year: the child and the rows of all its years. One that is not there is
    /// not an error.
    func removeChild(id: Int64) throws {
        try write { connection in
            try connection.run("DELETE FROM child WHERE id = ?", [.integer(id)])
        }
    }

    /// Removes the child with `id` from every year, as `removeChild(id:)` does, and gives the other children of `year`
    /// the orders of `otherOrders`, by id, as `setChildOrders` does, in the same write: the child goes together with
    /// the orders of the year or not at all. Among them, a child that is not in the family of the year once the child
    /// is gone (the child itself too) and an order below 1 are refused with `SQLiteError.constraint`, and nothing is
    /// changed.
    func removeChild(id: Int64, year: Int, otherOrders: [Int64: Int]) throws {
        try write { connection in
            try connection.run("DELETE FROM child WHERE id = ?", [.integer(id)])
            guard !otherOrders.isEmpty else { return }
            let children = try family(year: year, in: connection).children
            try storeYearSettingsIfMissing(year, in: connection)
            try store(otherOrders, of: children, besides: nil, year: year, in: connection)
        }
    }

    /// Stores, for each child with an id of `orders`, what `children`, the family of `year`, say about it with the
    /// order of `orders`: a child without a row of its own for the year gets one. A child that is not among `children`,
    /// or that is `excluded`, is refused with `SQLiteError.constraint`, and so is an order below 1 (by the check of the
    /// table).
    private func store(
        _ orders: [Int64: Int], of children: [FamilyChild], besides excluded: Int64?, year: Int,
        in connection: SQLiteConnection
    ) throws {
        for (id, order) in orders {
            guard id != excluded, var childYear = children.first(where: { $0.child.id == id })?.year else {
                throw SQLiteError.constraint("child_year: the child is not in the family of the year.")
            }
            childYear.order = order
            try childYear.store(childID: id, year: year, in: connection)
        }
    }

    /// Saves the spouse of `year`, nil for none, with the rest of the year's settings as they are: a year without
    /// settings of its own gets those `yearSettings(_:)` gives it, as `updateYearSettings` does. A spouse the tax
    /// engine would refuse (a range of months that is not one, an income below zero) is refused with
    /// `SQLiteError.constraint` and nothing is changed.
    func saveSpouse(_ spouse: SpouseYear?, year: Int) throws {
        try updateYearSettings(year) { $0.spouse = spouse }
    }

    /// The family of `year` read with the connection of a read or a write that runs already.
    private func family(year: Int, in connection: SQLiteConnection) throws -> FamilyYear {
        let children = try connection.query("SELECT id, name, birth_date FROM child")
            .map { try Child(row: $0) }
            .filter { $0.birthDate.year <= year }
            .sorted { ($0.birthDate, $0.id ?? 0) < ($1.birthDate, $1.id ?? 0) }
        var stored: [Int64: [Int: ChildYear]] = [:]
        let rows = try connection.query(
            "SELECT child_id, year, \(ChildYear.columns) FROM child_year WHERE year <= ?", [.int(year)]
        )
        for row in rows {
            stored[row.int64(0), default: [:]][row.int(1)] = try ChildYear(row: row, from: 2)
        }
        let members = children.enumerated().map { index, child in
            let years = child.id.flatMap { stored[$0] } ?? [:]
            return FamilyChild(
                child: child,
                year: FamilyResolution.childYear(for: child, year: year, stored: years, defaultOrder: index + 1),
                isStored: years[year] != nil
            )
        }
        return FamilyYear(year: year, children: members, spouse: try spouse(ofYear: year, in: connection))
    }
}

private nonisolated extension Child {
    /// A row of `SELECT id, name, birth_date`.
    init(row: SQLRow) throws {
        self.init(id: row.int64(0), name: row.text(1), birthDate: try row.day(2))
    }

    /// Inserts the child, or updates the stored child with its id, and returns the id. The child's row is updated in
    /// place: replacing it would delete the rows of its years.
    func store(in connection: SQLiteConnection) throws -> Int64 {
        try connection.run(
            """
            INSERT INTO child(id, name, birth_date) VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name = excluded.name, birth_date = excluded.birth_date
            """,
            [id.map { SQLValue.integer($0) } ?? .null, .text(name), .day(birthDate)]
        )
        return id ?? connection.lastInsertRowID
    }
}

private nonisolated extension ChildYear {
    /// The columns of `child_year` after the child and the year, in the order `store` binds them.
    static let columns = """
        household_from, household_to, claimant, child_order, ztpp_from, ztpp_to, studies_from, studies_to
        """

    /// The columns of `columns` in a row, from `first` on.
    init(row: SQLRow, from first: Int) throws {
        self.init(
            household: try row.optionalMonthRange(first), claimant: try row.choice(first + 2),
            order: row.int(first + 3), ztpp: try row.optionalMonthRange(first + 4),
            studies: try row.optionalMonthRange(first + 6)
        )
    }

    /// Stores what `year` says about the child with `childID`, replacing what was stored for them.
    func store(childID: Int64, year: Int, in connection: SQLiteConnection) throws {
        try connection.run(
            """
            INSERT INTO child_year(child_id, year, \(Self.columns)) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(child_id, year) DO UPDATE SET
                household_from = excluded.household_from, household_to = excluded.household_to,
                claimant = excluded.claimant, child_order = excluded.child_order, ztpp_from = excluded.ztpp_from,
                ztpp_to = excluded.ztpp_to, studies_from = excluded.studies_from, studies_to = excluded.studies_to
            """,
            [.integer(childID), .int(year)] + SQLValue.monthRangeColumns(household)
                + [.choice(claimant), .int(order)] + SQLValue.monthRangeColumns(ztpp)
                + SQLValue.monthRangeColumns(studies)
        )
    }
}

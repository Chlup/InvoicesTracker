import Foundation

extension Database {
    /// The settings of `year`. A year that has none stored yet gets the choices of the nearest earlier year that has:
    /// the expense rate, the reduced social base, the taxpayer credit and the method of converting income. Its
    /// advances, deductions and months of activity start as for any new year, it has no spouse, and nothing is stored
    /// until a write stores the year, such as `updateYearSettings`.
    func yearSettings(_ year: Int) throws -> YearSettings {
        try read { connection in
            if let stored = try YearSettings.stored(year: year, in: connection) {
                return stored
            }
            return try YearSettings.startingPoint(year: year, in: connection)
        }
    }

    /// Saves `settings` with its advances, deductions and spouse, replacing what was stored for that year: the spouse
    /// too, so settings read before another write stored a spouse would remove it. To change some of the settings, use
    /// `updateYearSettings`, which keeps what it does not touch. A value the tax engine would refuse is refused with
    /// `SQLiteError.constraint` and nothing is changed.
    func saveYearSettings(_ settings: YearSettings) throws {
        try settings.validateForStoring()
        try write { connection in
            try settings.store(in: connection)
        }
    }

    /// Changes the settings of `year` with `change` and saves them, in one transaction: no other write comes in
    /// between, so a change of one field never undoes a change of another that was made meanwhile. A year that has none
    /// stored is changed from the settings `yearSettings(_:)` gives it. The year of the settings stays `year`. A result
    /// the tax engine would refuse is refused with `SQLiteError.constraint` and nothing is changed. Returns the settings
    /// as saved.
    @discardableResult
    func updateYearSettings(_ year: Int, _ change: @Sendable (inout YearSettings) -> Void) throws -> YearSettings {
        try write { connection in
            var settings =
                try YearSettings.stored(year: year, in: connection)
                ?? YearSettings.startingPoint(year: year, in: connection)
            change(&settings)
            settings.year = year
            try settings.validateForStoring()
            try settings.store(in: connection)
            return settings
        }
    }

    /// The years that have stored settings, the oldest first.
    func storedSettingsYears() throws -> [Int] {
        try read { connection in
            try connection.query("SELECT year FROM year_settings ORDER BY year").map { $0.int(0) }
        }
    }

    /// Stores the settings `yearSettings(_:)` gives `year` when the year has none of its own, for a write that adds a
    /// row belonging to the year (the year of a child), so it takes the connection of that write. They are the
    /// defaults with the choices of the nearest earlier stored year, the method of converting income included: what
    /// the year took from that year stays as it was, and so do the years after it that take their choices from it.
    func storeYearSettingsIfMissing(_ year: Int, in connection: SQLiteConnection) throws {
        guard try connection.query("SELECT 1 FROM year_settings WHERE year = ?", [.int(year)]).isEmpty else {
            return
        }
        try YearSettings.startingPoint(year: year, in: connection).store(in: connection)
    }

    /// The spouse stored for `year`, or nil when the year has no settings of its own or no spouse. For a read or a
    /// write that runs already, so it takes its connection.
    func spouse(ofYear year: Int, in connection: SQLiteConnection) throws -> SpouseYear? {
        let rows = try connection.query(
            "SELECT \(SpouseYear.columns) FROM year_settings WHERE year = ?", [.int(year)]
        )
        return try rows.first?.optionalSpouse(0)
    }

    /// The income adjustments dated in `year`, by date. Adjustments of the same day come in the order they were
    /// saved in.
    func adjustments(year: Int) throws -> [IncomeAdjustment] {
        guard let first = CivilDate(year: year, month: 1, day: 1), let last = CivilDate(year: year, month: 12, day: 31)
        else {
            return []
        }
        return try read { connection in
            try connection.query(
                """
                SELECT id, date, amount_halere, description FROM income_adjustment
                WHERE date BETWEEN ? AND ? ORDER BY date, id
                """,
                [.day(first), .day(last)]
            ).map { try IncomeAdjustment(row: $0) }
        }
    }

    /// Saves `adjustment` and returns its id: an adjustment with `id == 0` is inserted and gets a new id, any other
    /// is updated in place, or inserted with that id if no adjustment has it.
    @discardableResult
    func saveAdjustment(_ adjustment: IncomeAdjustment) throws -> Int64 {
        try write { connection in
            try connection.run(
                """
                INSERT INTO income_adjustment(id, date, amount_halere, description) VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    date = excluded.date, amount_halere = excluded.amount_halere,
                    description = excluded.description
                """,
                [
                    adjustment.id == 0 ? .null : .integer(adjustment.id), .day(adjustment.date),
                    .integer(adjustment.amountHalere), .text(adjustment.description),
                ]
            )
            return adjustment.id == 0 ? connection.lastInsertRowID : adjustment.id
        }
    }

    /// Deletes the adjustment. One that is not there is not an error.
    func deleteAdjustment(id: Int64) throws {
        try write { connection in
            try connection.run("DELETE FROM income_adjustment WHERE id = ?", [.integer(id)])
        }
    }
}

private nonisolated extension IncomeAdjustment {
    /// A row of `SELECT id, date, amount_halere, description`.
    init(row: SQLRow) throws {
        self.init(id: row.int64(0), date: try row.day(1), amountHalere: row.int64(2), description: row.text(3))
    }
}

private nonisolated extension YearSettings {
    /// The settings stored for `year` with its advances, deductions and spouse, or nil if the year has none.
    static func stored(year: Int, in connection: SQLiteConnection) throws -> YearSettings? {
        let rows = try connection.query(
            """
            SELECT expense_percent, reduced_social_base, activity_from, activity_to, secondary_months,
                   health_exempt_months, taxpayer_credit, income_fx_method, \(SpouseYear.columns)
            FROM year_settings WHERE year = ?
            """,
            [.int(year)]
        )
        guard let row = rows.first else { return nil }
        return try YearSettings(
            year: year, expensePercent: row.int(0), reducedSocialBase: row.bool(1), activityFrom: row.int(2),
            activityTo: row.int(3), secondaryMonths: row.months(4), healthExemptMonths: row.months(5),
            advances: advances(ofYear: year, in: connection), deductions: deductions(ofYear: year, in: connection),
            taxpayerCredit: row.bool(6), incomeFXMethod: row.choice(7), spouse: row.optionalSpouse(8)
        )
    }

    /// The settings of a year with none stored: the defaults, with the choices of the nearest earlier stored year. The
    /// spouse is not one of them.
    static func startingPoint(year: Int, in connection: SQLiteConnection) throws -> YearSettings {
        var settings = YearSettings(year: year)
        let rows = try connection.query(
            """
            SELECT expense_percent, reduced_social_base, taxpayer_credit, income_fx_method
            FROM year_settings WHERE year < ? ORDER BY year DESC LIMIT 1
            """,
            [.int(year)]
        )
        if let row = rows.first {
            settings.expensePercent = row.int(0)
            settings.reducedSocialBase = row.bool(1)
            settings.taxpayerCredit = row.bool(2)
            settings.incomeFXMethod = try row.choice(3)
        }
        return settings
    }

    /// The advances of the year: a row for each month that has one, and no advance in the others.
    private static func advances(ofYear year: Int, in connection: SQLiteConnection) throws -> AdvancePlan {
        var plan = AdvancePlan.empty
        let rows = try connection.query(
            "SELECT month, social, health, tax FROM advance_month WHERE year = ?", [.int(year)]
        )
        for row in rows {
            let month = row.int(0)
            guard (1...12).contains(month) else {
                throw StoredValueError.unreadable(column: 0, expected: "month")
            }
            plan.social[month - 1] = row.int64(1)
            plan.health[month - 1] = row.int64(2)
            plan.tax[month - 1] = row.int64(3)
        }
        return plan
    }

    private static func deductions(ofYear year: Int, in connection: SQLiteConnection) throws -> Deductions {
        let rows = try connection.query(
            """
            SELECT mortgage_interest_paid, mortgage_months, mortgage_cap, life_insurance, pension_savings, dip,
                   long_term_care, gifts
            FROM deduction WHERE year = ?
            """,
            [.int(year)]
        )
        guard let row = rows.first else { return Deductions() }
        return try Deductions(
            mortgageInterestPaid: row.int64(0), mortgageMonths: row.int(1), mortgageCap: row.choice(2),
            lifeInsurance: row.int64(3), pensionSavings: row.int64(4), dip: row.int64(5),
            longTermCare: row.int64(6), gifts: row.int64(7)
        )
    }

    /// Refuses what the tables have no check for: a month outside 1 to 12 in a set of months, an activity that ends
    /// before it starts, and an advance plan that does not have a value for each of the twelve months.
    func validateForStoring() throws {
        let months = secondaryMonths.union(healthExemptMonths)
        guard months.allSatisfy({ (1...12).contains($0) }) else {
            throw SQLiteError.constraint("year_settings: a month is 1 to 12.")
        }
        guard activityFrom <= activityTo else {
            throw SQLiteError.constraint("year_settings: the activity ends no earlier than it starts.")
        }
        guard [advances.social, advances.health, advances.tax].allSatisfy({ $0.count == 12 }) else {
            throw SQLiteError.constraint("advance_month: an advance plan has a value for each of the twelve months.")
        }
    }

    /// Writes the settings with the spouse, a row for each of the twelve advance months and the deductions, replacing
    /// what is stored for the year. The year's row is updated in place: replacing it would delete its advances,
    /// deductions and the years of its children.
    func store(in connection: SQLiteConnection) throws {
        try connection.run(
            """
            INSERT INTO year_settings(
                year, expense_percent, reduced_social_base, activity_from, activity_to, secondary_months,
                health_exempt_months, taxpayer_credit, income_fx_method, \(SpouseYear.columns))
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(year) DO UPDATE SET
                expense_percent = excluded.expense_percent, reduced_social_base = excluded.reduced_social_base,
                activity_from = excluded.activity_from, activity_to = excluded.activity_to,
                secondary_months = excluded.secondary_months, health_exempt_months = excluded.health_exempt_months,
                taxpayer_credit = excluded.taxpayer_credit,
                income_fx_method = excluded.income_fx_method, spouse_claim = excluded.spouse_claim,
                spouse_from = excluded.spouse_from, spouse_to = excluded.spouse_to,
                spouse_own_income = excluded.spouse_own_income, spouse_ztpp_from = excluded.spouse_ztpp_from,
                spouse_ztpp_to = excluded.spouse_ztpp_to
            """,
            [
                .int(year), .int(expensePercent), .flag(reducedSocialBase), .int(activityFrom), .int(activityTo),
                .months(secondaryMonths), .months(healthExemptMonths), .flag(taxpayerCredit), .choice(incomeFXMethod),
            ] + SQLValue.spouseColumns(spouse)
        )
        try connection.run("DELETE FROM advance_month WHERE year = ?", [.int(year)])
        for month in 1...12 {
            try connection.run(
                "INSERT INTO advance_month(year, month, social, health, tax) VALUES (?, ?, ?, ?, ?)",
                [
                    .int(year), .int(month), .integer(advances.social[month - 1]),
                    .integer(advances.health[month - 1]), .integer(advances.tax[month - 1]),
                ]
            )
        }
        try connection.run(
            """
            INSERT INTO deduction(
                year, mortgage_interest_paid, mortgage_months, mortgage_cap, life_insurance, pension_savings, dip,
                long_term_care, gifts)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(year) DO UPDATE SET
                mortgage_interest_paid = excluded.mortgage_interest_paid, mortgage_months = excluded.mortgage_months,
                mortgage_cap = excluded.mortgage_cap, life_insurance = excluded.life_insurance,
                pension_savings = excluded.pension_savings, dip = excluded.dip,
                long_term_care = excluded.long_term_care, gifts = excluded.gifts
            """,
            [
                .int(year), .integer(deductions.mortgageInterestPaid), .int(deductions.mortgageMonths),
                .choice(deductions.mortgageCap), .integer(deductions.lifeInsurance),
                .integer(deductions.pensionSavings), .integer(deductions.dip), .integer(deductions.longTermCare),
                .integer(deductions.gifts),
            ]
        )
    }
}

private nonisolated extension SpouseYear {
    /// The columns of `year_settings` that hold the spouse, in the order `SQLValue.spouseColumns` binds them.
    static let columns = "spouse_claim, spouse_from, spouse_to, spouse_own_income, spouse_ztpp_from, spouse_ztpp_to"
}

private nonisolated extension SQLValue {
    /// The values of `SpouseYear.columns`: the claim, the months, the own income and the months of ZTP/P, all NULL for
    /// a year without a spouse.
    static func spouseColumns(_ spouse: SpouseYear?) -> [SQLValue] {
        guard let spouse else { return [.null, .null, .null, .null, .null, .null] }
        return [.flag(spouse.claim)] + monthRangeColumns(spouse.months) + [.integer(spouse.ownIncomeKc)]
            + monthRangeColumns(spouse.ztpp)
    }
}

private nonisolated extension SQLRow {
    /// The spouse in the columns of `SpouseYear.columns` from `i`, or nil when the year has none.
    func optionalSpouse(_ i: Int) throws -> SpouseYear? {
        guard optionalInt64(i) != nil else { return nil }
        return SpouseYear(
            claim: bool(i), months: try monthRange(i + 1), ownIncomeKc: int64(i + 3),
            ztpp: try optionalMonthRange(i + 4)
        )
    }
}

import Foundation

/// The statements `cnbRate`, `latestCNBRate` and `meanCNBRate` run. Each finds its rows in an index of `cnb_rate`, the
/// key `(declared_on, currency)` or the index `(currency, declared_on)`, so it costs the same with one year of rates
/// stored and with ten.
nonisolated enum CNBRateQueries {
    /// The rate of a currency declared on a day. Arguments: the day, the currency.
    static let rate = "SELECT declared_on, currency, amount, rate FROM cnb_rate WHERE declared_on = ? AND currency = ?"

    /// A row if a rate of any currency was declared on a day. Arguments: the day.
    static let anyRateOnDay = "SELECT 1 FROM cnb_rate WHERE declared_on = ? LIMIT 1"

    /// The latest rate of a currency declared on or before a day. Arguments: the currency, the day.
    static let latestRate = """
        SELECT declared_on, currency, amount, rate FROM cnb_rate
        WHERE currency = ? AND declared_on <= ? ORDER BY declared_on DESC LIMIT 1
        """

    /// The rates of a currency declared between two days, both included, with the amounts they are for. Arguments:
    /// the currency, the first day, the last day.
    static let ratesBetween = """
        SELECT amount, rate FROM cnb_rate WHERE currency = ? AND declared_on BETWEEN ? AND ?
        """
}

/// The statement `paidForeignCurrencies(year:)` runs. It finds the payments of the year in the index of their days, so
/// it costs the same with one year of payments stored and with ten.
nonisolated enum UniformRateQueries {
    /// The currencies other than crowns of the invoices with a payment dated between two days, both included, that is
    /// converted at a rate (an amount the bank credited in crowns is not), whatever the state of the invoice, each
    /// once and in the order of the codes. Arguments: the first day, the last day.
    static let paidForeignCurrencies = """
        SELECT DISTINCT invoice.currency FROM payment JOIN invoice ON invoice.id = payment.invoice_id
        WHERE payment.date BETWEEN ? AND ? AND invoice.currency <> '\(CurrencyCode.czk.code)'
          AND payment.conversion <> '\(PaymentConversion.bankCZK.rawValue)'
        ORDER BY 1
        """
}

// MARK: - Uniform rates

extension Database {
    /// The uniform rates of `year`, ordered by currency. Empty for a year that has none yet.
    func uniformRates(year: Int) throws -> [UniformRate] {
        try read { connection in
            try connection.query(
                "SELECT \(UniformRate.columns) FROM uniform_rate WHERE year = ? ORDER BY currency", [.int(year)]
            ).map { try UniformRate(row: $0) }
        }
    }

    func uniformRate(_ currency: CurrencyCode, year: Int) throws -> UniformRate? {
        try read { connection in
            let rows = try connection.query(
                "SELECT \(UniformRate.columns) FROM uniform_rate WHERE year = ? AND currency = ?",
                [.int(year), .currency(currency)]
            )
            return try rows.first.map { try UniformRate(row: $0) }
        }
    }

    /// Replaces the uniform rates of `year` with `rates`, which may be none, and leaves the other years alone. Each
    /// rate must be of `year`, above zero and quoted for an amount above zero, and a currency can be there once:
    /// otherwise nothing is changed and `SQLiteError.constraint` is thrown.
    func saveUniformRates(_ rates: [UniformRate], year: Int) throws {
        try Self.checkUniformRates(rates, year: year)
        try write { connection in
            try connection.run("DELETE FROM uniform_rate WHERE year = ?", [.int(year)])
            try Self.insertUniformRates(rates, year: year, in: connection)
        }
    }

    /// Deletes the uniform rates of `year`, of every currency, and leaves the other years alone.
    func deleteUniformRates(year: Int) throws {
        try write { connection in
            try connection.run("DELETE FROM uniform_rate WHERE year = ?", [.int(year)])
        }
    }

    /// Replaces the uniform rates of `year` with the table that ships with the app for it (`BuiltInUniformRates`), row
    /// by row as a new database has it: every currency of the table, with the instruction that published it, built
    /// in. A year without such a table (any but 2022 to 2025) is left as it is.
    func restoreBuiltInUniformRates(year: Int) throws {
        let table = BuiltInUniformRates.uniformRates(year: year)
        guard !table.isEmpty else { return }
        try saveUniformRates(table, year: year)
    }

    /// Stores `rates` as the uniform rates of `year` only when the year has none, which is looked at in the same
    /// transaction that stores them, so that rates saved meanwhile are never replaced. Returns whether they were
    /// stored: false, with nothing changed, when the year has rates already or `rates` is empty. The rates are checked
    /// as `saveUniformRates(_:year:)` checks them.
    func storeUniformRatesIfNone(_ rates: [UniformRate], year: Int) throws -> Bool {
        try Self.checkUniformRates(rates, year: year)
        guard !rates.isEmpty else { return false }
        return try write { connection in
            let stored = try connection.query("SELECT count(*) FROM uniform_rate WHERE year = ?", [.int(year)])
            guard stored[0].int64(0) == 0 else { return false }
            try Self.insertUniformRates(rates, year: year, in: connection)
            return true
        }
    }

    /// The currencies other than crowns that money came in during `year` and that is converted at a rate: those of
    /// the invoices with a payment dated in the year, whatever their state, except a payment of an amount the bank
    /// credited in crowns. Each once, in the order of the codes. A year outside the calendar has none.
    func paidForeignCurrencies(year: Int) throws -> [CurrencyCode] {
        guard let period = Period(year: year) else { return [] }
        return try read { connection in
            try connection.query(UniformRateQueries.paidForeignCurrencies, period.arguments).map { try $0.currency(0) }
        }
    }

    /// How `year` converts its income in other currencies (`YearFXState`): the method chosen for it, its uniform rates
    /// and the currencies it was paid in, read in one call on the database, so that no write comes in between.
    /// `today` only decides where a year without its uniform rate stands (`UniformRateSearch`): the rate is not
    /// published yet, the app looks for it once a day, or the app does not have it.
    func fxState(year: Int, today: CivilDate) throws -> YearFXState {
        YearFXState(
            year: year, chosen: try yearSettings(year).incomeFXMethod, rates: try uniformRates(year: year),
            paidCurrencies: try paidForeignCurrencies(year: year), today: today)
    }

    /// The method `year` converts its income in other currencies with now (`YearFXState.effective`): the uniform rate
    /// only when it is chosen and the year has it for every currency it was paid in.
    func effectiveFXMethod(year: Int) throws -> IncomeFXMethod {
        // The day only names why a year has no rate, which the method does not depend on: any day will do. A year that
        // has no days is no year of a payment, and has no uniform rate.
        guard let anyDay = CivilDate(year: year, month: 1, day: 1) else { return .cnbDaily }
        return try fxState(year: year, today: anyDay).effective
    }

    private nonisolated static func checkUniformRates(_ rates: [UniformRate], year: Int) throws {
        guard rates.allSatisfy({ $0.year == year }) else {
            throw SQLiteError.constraint("uniform_rate: every rate must be of the year it is saved for.")
        }
        guard rates.allSatisfy({ $0.rate > 0 }) else {
            throw SQLiteError.constraint("uniform_rate: a rate must be above zero.")
        }
    }

    private nonisolated static func insertUniformRates(
        _ rates: [UniformRate], year: Int, in connection: SQLiteConnection
    ) throws {
        for rate in rates {
            try connection.run(
                """
                INSERT INTO uniform_rate(
                    year, currency, amount, rate, instruction, source_url, confirmed_at, origin)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .int(year), .currency(rate.currency), .int(rate.amount), .decimal(rate.rate),
                    .text(rate.instruction), .optionalText(rate.sourceURL), .optionalInstant(rate.confirmedAt),
                    .choice(rate.origin),
                ]
            )
        }
    }
}

// MARK: - ČNB rates

extension Database {
    /// Stores `rows`, replacing a stored rate of the same currency and day. Of two rows for one currency and day,
    /// the later one in `rows` counts. Each rate must be above zero and quoted for an amount above zero: otherwise
    /// none of the rows is stored and `SQLiteError.constraint` is thrown.
    func insertCNBRates(_ rows: [CNBRateRow]) throws {
        guard !rows.isEmpty else { return }
        guard rows.allSatisfy({ $0.rate > 0 }) else {
            throw SQLiteError.constraint("cnb_rate: a rate must be above zero.")
        }
        try write { connection in
            for row in rows {
                try connection.run(
                    "INSERT OR REPLACE INTO cnb_rate(declared_on, currency, amount, rate) VALUES (?, ?, ?, ?)",
                    [.day(row.declaredOn), .currency(row.currency), .int(row.amount), .decimal(row.rate)]
                )
            }
        }
    }

    /// The ČNB rate of `currency` that is valid on `day`, by the one rule in `RateLookup`. This only finds out the
    /// facts the rule asks for, with an index lookup for each, and asks it. It finds out all of them whatever the
    /// answer will be (also for crowns), so that no part of the rule is repeated here.
    func cnbRate(_ currency: CurrencyCode, on day: CivilDate) throws -> RateLookupResult {
        let expectedDay = CzechCalendar.rateDeclarationDay(for: day)
        let previousBusinessDay = CzechCalendar.previousBusinessDay(onOrBefore: expectedDay.adding(days: -1))
        let nextBusinessDay = CzechCalendar.nextBusinessDay(onOrAfter: day.adding(days: 1))
        return try read { connection in
            let rowOnExpectedDay = try CNBRateRow.declared(on: expectedDay, currency: currency, in: connection)
            let latestRowOnOrBeforeDay = try CNBRateRow.latest(of: currency, onOrBefore: day, in: connection)
            let anyRowOnExpectedDay = try CNBRateRow.anyDeclared(on: expectedDay, in: connection)
            let anyRowOnPreviousBusinessDay = try CNBRateRow.anyDeclared(on: previousBusinessDay, in: connection)
            let anyRowOnNextBusinessDay = try CNBRateRow.anyDeclared(on: nextBusinessDay, in: connection)
            return RateLookup.resolve(
                currency: currency,
                day: day,
                rowOnExpectedDay: rowOnExpectedDay,
                anyRowOnExpectedDay: anyRowOnExpectedDay,
                anyRowOnPreviousBusinessDay: anyRowOnPreviousBusinessDay,
                anyRowOnNextBusinessDay: anyRowOnNextBusinessDay,
                latestRowOnOrBeforeDay: latestRowOnOrBeforeDay
            )
        }
    }

    /// The latest rate of `currency` declared on or before `day`, with the day it was declared, or nil if there is
    /// none. This is the newest row, not the rate valid on `day`: it is also given for a day after the newest
    /// declaration, and there are no rows for crowns.
    func latestCNBRate(_ currency: CurrencyCode, onOrBefore day: CivilDate) throws -> StoredRate? {
        try read { connection in
            let row = try CNBRateRow.latest(of: currency, onOrBefore: day, in: connection)
            return row.map { StoredRate(rate: $0.exchangeRate, declaredOn: $0.declaredOn) }
        }
    }

    /// The latest day the ČNB declared rates on, or nil if no rates are stored.
    func newestCNBDeclaration() throws -> CivilDate? {
        try read { connection in
            guard case .text(let text)? = try connection.scalar("SELECT max(declared_on) FROM cnb_rate") else {
                return nil
            }
            guard let day = CivilDate(iso: text) else {
                throw StoredValueError.unreadable(column: 0, expected: "date")
            }
            return day
        }
    }

    /// The days of the provisional payments in a foreign currency whose ČNB rate the stored rates cannot tell yet
    /// (`cnbRate` says `.notYetAvailable`), oldest first, each once: the ČNB has not declared it, or the rows that hold
    /// it, or those around it, are not stored. The refresh fetches the yearly files of such days once their rates are
    /// declared. A payment converted at its rate meanwhile is no longer provisional, and a currency the ČNB does not
    /// quote that day (`.notPublished`) has nothing to wait for.
    func provisionalPaymentDaysWithoutRate() throws -> [CivilDate] {
        let payments = try read { connection in
            try connection.query(InvoiceQueries.provisionalForeignPayments).map { row in
                (day: try row.day(0), currency: try row.currency(1))
            }
        }
        var days: Set<CivilDate> = []
        for payment in payments where !days.contains(payment.day) {
            if try cnbRate(payment.currency, on: payment.day) == .notYetAvailable {
                days.insert(payment.day)
            }
        }
        return days.sorted()
    }

    /// The mean of the stored ČNB rates of `currency` declared in `year`, each for one unit of the currency (a rate
    /// quoted for 100 units counts as a hundredth of it), or nil when the year has none stored.
    func meanCNBRate(_ currency: CurrencyCode, year: Int) throws -> Decimal? {
        guard let period = Period(year: year) else { return nil }
        let rates = try read { connection in
            try connection.query(CNBRateQueries.ratesBetween, [.currency(currency)] + period.arguments).map { row in
                try row.decimal(1) / Decimal(row.int(0))
            }
        }
        guard !rates.isEmpty else { return nil }
        return rates.reduce(Decimal(0), +) / Decimal(rates.count)
    }

    /// The currencies that have at least one stored rate.
    func cnbCurrencies() throws -> Set<CurrencyCode> {
        try read { connection in
            Set(try connection.query("SELECT DISTINCT currency FROM cnb_rate").map { try $0.currency(0) })
        }
    }
}

private nonisolated extension UniformRate {
    /// The columns of a uniform rate row, in the order `init(row:)` reads them.
    static let columns = "year, currency, amount, rate, instruction, source_url, confirmed_at, origin"

    init(row: SQLRow) throws {
        self.init(
            year: row.int(0), currency: try row.currency(1), amount: row.int(2), rate: try row.decimal(3),
            instruction: row.text(4), sourceURL: row.optionalText(5), confirmedAt: row.optionalInstant(6),
            origin: try row.choice(7)
        )
    }
}

private nonisolated extension CNBRateRow {
    /// A row of `CNBRateQueries.rate` or `CNBRateQueries.latestRate`.
    init(row: SQLRow) throws {
        self.init(
            declaredOn: try row.day(0), currency: try row.currency(1), amount: row.int(2), rate: try row.decimal(3)
        )
    }

    /// The rate of `currency` declared on `day`, if the ČNB declared one.
    static func declared(
        on day: CivilDate, currency: CurrencyCode, in connection: SQLiteConnection
    ) throws -> CNBRateRow? {
        let rows = try connection.query(CNBRateQueries.rate, [.day(day), .currency(currency)])
        return try rows.first.map { try CNBRateRow(row: $0) }
    }

    /// The latest rate of `currency` declared on or before `day`.
    static func latest(
        of currency: CurrencyCode, onOrBefore day: CivilDate, in connection: SQLiteConnection
    ) throws -> CNBRateRow? {
        let rows = try connection.query(CNBRateQueries.latestRate, [.currency(currency), .day(day)])
        return try rows.first.map { try CNBRateRow(row: $0) }
    }

    /// Whether the ČNB declared a rate of any currency on `day`.
    static func anyDeclared(on day: CivilDate, in connection: SQLiteConnection) throws -> Bool {
        try connection.scalar(CNBRateQueries.anyRateOnDay, [.day(day)]) != nil
    }
}

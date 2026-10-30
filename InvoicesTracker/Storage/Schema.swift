import Foundation

/// One numbered step of the database schema. `apply` changes the schema and the data from the previous version's to
/// this one's. `SearchIndexKind` is the kind of search table that was asked for, which only a step that creates it
/// looks at.
nonisolated struct Migration: Sendable {
    let version: Int
    let apply: @Sendable (SQLiteConnection, SearchIndexKind) throws -> Void
}

/// A database this version of the app cannot work with.
nonisolated enum SchemaError: Error, Equatable {
    /// The file was written by a newer version of the app. Opening it anyway could misread or damage it.
    case newerThanApp(found: Int, supported: Int)

    /// `meta` does not say which kind of table `invoice_search` is, so a search could not be written for it.
    case unknownSearchIndexKind
}

/// The schema of the database, as a list of migrations. Version 0 is a file with no tables.
///
/// What the tables store, which every repository follows:
/// - Amounts are INTEGER minor units (haléře for CZK), whole Kč where the model says so.
/// - Dates are TEXT `YYYY-MM-DD` (`CivilDate.iso`).
/// - Instants (`confirmed_at`, `at`) are INTEGER seconds since 1 January 1970 UTC.
/// - Exact decimals (quantities, rates) are TEXT in `DecimalMath.canonical` form.
/// - Booleans are INTEGER 0 or 1, enums their raw value as TEXT, and an unset value is NULL.
/// - A set of months is TEXT: the months in ascending order, separated by commas, no spaces (`11,12`), empty for none.
/// - A range of months (`MonthRange`) is two INTEGER columns, `…_from` and `…_to`: the first and the last month, 1 to
///   12, the first no later than the last. Both are NULL for none.
/// - A rate (`StoredRate`) is four columns, all set or all NULL: currency, quoted amount, rate and the day declared.
/// - Ids of clients, templates, invoices, adjustments and children are never reused. A dependent row is deleted with
///   its parent (`ON DELETE CASCADE`); an invoice only loses its link to a deleted client, because it keeps a copy of
///   the client's data.
nonisolated enum Schema {
    /// The migrations, in ascending order of `version`. Each runs in a transaction of its own (`Migrator`).
    ///
    /// A later migration that has to rebuild a table (SQLite cannot change a CHECK constraint or a foreign key in
    /// place) must follow SQLite's procedure for it: the connection turns its foreign keys on (`PRAGMA foreign_keys =
    /// ON`), and while they are on, dropping the old table deletes every child row with `ON DELETE CASCADE` and nulls
    /// the links with `ON DELETE SET NULL`. So the foreign keys are turned off before the rebuild and on again after
    /// it, outside its transaction, as the pragma does nothing inside one; the new table is made, filled from the old
    /// one, the old one dropped and the new one renamed in one transaction; and `PRAGMA foreign_key_check` must find
    /// nothing before that transaction commits. The `Migrator` does not do this by itself yet.
    static let migrations: [Migration] = [
        Migration(version: 1, apply: createVersion1),
        Migration(version: 2, apply: createVersion2),
        Migration(version: 3, apply: createVersion3),
    ]

    /// The version a database has after all migrations ran.
    static var latestVersion: Int {
        migrations.last?.version ?? 0
    }

    /// The key in `meta` under which the kind of `invoice_search` is kept.
    static let searchIndexKey = "search_index"

    /// The kind of `invoice_search` the database was created with: `.fts5` or `.plain`, never `.automatic`.
    static func recordedSearchIndexKind(in connection: SQLiteConnection) throws -> SearchIndexKind {
        let recorded = try connection.scalar("SELECT value FROM meta WHERE key = ?", [.text(searchIndexKey)])
        guard case .text(let name)? = recorded, let kind = SearchIndexKind(rawValue: name), kind != .automatic else {
            throw SchemaError.unknownSearchIndexKind
        }
        return kind
    }
}

/// Brings a database up to date.
nonisolated enum Migrator {
    /// Runs the migrations a database at its `user_version` has not had yet, up to `version`. Each one is one
    /// transaction that also sets the new `user_version`, so a step that fails leaves the database as it was.
    ///
    /// Throws `SchemaError.newerThanApp` for a database that is already beyond the latest version.
    static func migrate(
        _ connection: SQLiteConnection,
        searchIndex: SearchIndexKind,
        upTo version: Int = Schema.latestVersion
    ) throws {
        try migrate(connection, migrations: Schema.migrations, searchIndex: searchIndex, upTo: version)
    }

    /// The same for any list of migrations, which must be in ascending order of `version`.
    static func migrate(
        _ connection: SQLiteConnection,
        migrations: [Migration],
        searchIndex: SearchIndexKind,
        upTo version: Int
    ) throws {
        let current = try connection.userVersion()
        let latest = migrations.last?.version ?? 0
        guard current <= latest else {
            throw SchemaError.newerThanApp(found: current, supported: latest)
        }
        for migration in migrations where migration.version > current && migration.version <= version {
            try connection.transaction {
                try migration.apply(connection, searchIndex)
                try connection.setUserVersion(migration.version)
            }
        }
    }
}

// MARK: - Version 1

private nonisolated extension Schema {
    static func createVersion1(_ connection: SQLiteConnection, _ searchIndex: SearchIndexKind) throws {
        try connection.execute(settingsTables)
        try connection.execute(clientTables)
        try connection.execute(invoiceTables)
        try connection.execute(yearTables)
        try connection.execute(rateTables)
        try connection.execute(logTables)
        try connection.execute(indexes)
        let kind = try createSearchTable(connection, requested: searchIndex)
        try connection.run(
            "INSERT INTO meta(key, value) VALUES (?, ?)", [.text(searchIndexKey), .text(kind.rawValue)]
        )
        try insertBuiltInUniformRates(connection)
    }

    /// Creates `invoice_search` and returns its kind. The row id of a search row is the id of its invoice.
    ///
    /// A full-text table cannot have foreign keys, so whoever deletes an invoice deletes its search row too. The
    /// plain table deletes it with the invoice.
    static func createSearchTable(
        _ connection: SQLiteConnection,
        requested: SearchIndexKind
    ) throws -> SearchIndexKind {
        let kind: SearchIndexKind
        switch requested {
        case .automatic: kind = connection.supportsFTS5Trigram() ? .fts5 : .plain
        case .fts5, .plain: kind = requested
        }
        if kind == .fts5 {
            try connection.execute("CREATE VIRTUAL TABLE invoice_search USING fts5(doc, tokenize='trigram')")
        } else {
            try connection.execute(
                """
                CREATE TABLE invoice_search(
                    rowid INTEGER PRIMARY KEY REFERENCES invoice(id) ON DELETE CASCADE,
                    doc TEXT NOT NULL)
                """
            )
        }
        return kind
    }

    /// The published tables of 2022 to 2025, so that a past year's uniform rates are known from the start.
    static func insertBuiltInUniformRates(_ connection: SQLiteConnection) throws {
        for (year, instruction) in BuiltInUniformRates.instructions.sorted(by: { $0.key < $1.key }) {
            for entry in BuiltInUniformRates.rates(year: year) {
                try connection.run(
                    """
                    INSERT INTO uniform_rate(
                        year, currency, amount, rate, instruction, source_url, confirmed_at, origin)
                    VALUES (?, ?, ?, ?, ?, NULL, NULL, ?)
                    """,
                    [
                        .integer(Int64(year)), .text(entry.currency.code), .integer(Int64(entry.amount)),
                        .text(DecimalMath.canonical(entry.rate)), .text(instruction),
                        .text(UniformRateOrigin.builtIn.rawValue),
                    ]
                )
            }
        }
    }

    /// `meta` keeps facts about the database itself, `app_settings` the choices of the person as JSON values by key
    /// (`app` holds `AppSettings`). The supplier is one row, and a currency has one bank account.
    static let settingsTables = """
        CREATE TABLE meta (
            key TEXT NOT NULL PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE app_settings (
            key TEXT NOT NULL PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE supplier (
            id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
            name TEXT NOT NULL,
            street TEXT NOT NULL,
            postcode TEXT NOT NULL,
            city TEXT NOT NULL,
            country TEXT NOT NULL,
            ico TEXT NOT NULL,
            dic TEXT NOT NULL,
            email TEXT NOT NULL,
            phone TEXT NOT NULL,
            czech_footer TEXT NOT NULL
        );

        CREATE TABLE bank_account (
            currency TEXT NOT NULL PRIMARY KEY,
            account_number TEXT NOT NULL,
            iban TEXT NOT NULL,
            bic TEXT NOT NULL,
            routing_number TEXT NOT NULL,
            account_type TEXT NOT NULL,
            bank_name_and_address TEXT NOT NULL
        );
        """

    /// A template belongs to its client and goes with it. The items of a template are numbered by `position`.
    static let clientTables = """
        CREATE TABLE client (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            street TEXT NOT NULL,
            postcode TEXT NOT NULL,
            city TEXT NOT NULL,
            country TEXT NOT NULL,
            ico TEXT NOT NULL,
            dic TEXT NOT NULL,
            email TEXT NOT NULL,
            phone TEXT NOT NULL,
            currency TEXT NOT NULL,
            vat_mode TEXT NOT NULL,
            due_days INTEGER NOT NULL,
            payment_method TEXT NOT NULL,
            language TEXT NOT NULL,
            origin TEXT NOT NULL,
            edited_after_import INTEGER NOT NULL
        );

        CREATE TABLE template (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            client_id INTEGER NOT NULL REFERENCES client(id) ON DELETE CASCADE,
            vat_mode TEXT NOT NULL,
            due_days INTEGER NOT NULL,
            duzp_at_month_end INTEGER NOT NULL,
            note TEXT NOT NULL
        );

        CREATE TABLE template_item (
            template_id INTEGER NOT NULL REFERENCES template(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            description TEXT NOT NULL,
            quantity TEXT NOT NULL,
            unit TEXT NOT NULL,
            unit_price_minor INTEGER NOT NULL,
            PRIMARY KEY (template_id, position)
        );
        """

    /// The invoice row carries the computed totals so that lists and sums need no items. The columns `client_*` are
    /// the snapshot of the client, `rate_*` the invoice rate. An invoice from the import has both `fakturoid_id` and
    /// `import_fingerprint`, any other has neither. The review flag is the reason in `review_reason`, NULL for none.
    /// The number is unique by its digits, so `2026-05-01` and `20260501` cannot both exist.
    ///
    /// The payment is its own row, at most one for an invoice, and `invoice_id` is its key. Its `rate_*` columns
    /// are the rate the conversion used.
    static let invoiceTables = """
        CREATE TABLE invoice (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            number TEXT NOT NULL,
            number_digits TEXT NOT NULL,
            client_id INTEGER REFERENCES client(id) ON DELETE SET NULL,
            client_name TEXT NOT NULL,
            client_street TEXT NOT NULL,
            client_postcode TEXT NOT NULL,
            client_city TEXT NOT NULL,
            client_country TEXT NOT NULL,
            client_ico TEXT NOT NULL,
            client_dic TEXT NOT NULL,
            client_email TEXT NOT NULL,
            currency TEXT NOT NULL,
            issue_date TEXT NOT NULL,
            duzp TEXT NOT NULL,
            due_date TEXT NOT NULL,
            vat_mode TEXT NOT NULL,
            rate_currency TEXT,
            rate_amount INTEGER,
            rate_value TEXT,
            rate_declared_on TEXT,
            qr_enabled INTEGER NOT NULL,
            note TEXT NOT NULL,
            language TEXT NOT NULL,
            payment_method TEXT NOT NULL,
            status TEXT NOT NULL,
            review_reason TEXT,
            fakturoid_id TEXT,
            import_fingerprint TEXT,
            changed_in_app INTEGER NOT NULL,
            net_minor INTEGER NOT NULL,
            vat_minor INTEGER NOT NULL,
            total_minor INTEGER NOT NULL,
            CHECK (
                (rate_currency IS NULL) = (rate_amount IS NULL)
                AND (rate_currency IS NULL) = (rate_value IS NULL)
                AND (rate_currency IS NULL) = (rate_declared_on IS NULL)),
            CHECK (rate_amount IS NULL OR rate_amount > 0),
            CHECK ((fakturoid_id IS NULL) = (import_fingerprint IS NULL))
        );

        CREATE TABLE invoice_item (
            invoice_id INTEGER NOT NULL REFERENCES invoice(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            description TEXT NOT NULL,
            quantity TEXT NOT NULL,
            unit TEXT NOT NULL,
            unit_price_minor INTEGER NOT NULL,
            PRIMARY KEY (invoice_id, position)
        );

        CREATE TABLE payment (
            invoice_id INTEGER NOT NULL PRIMARY KEY REFERENCES invoice(id) ON DELETE CASCADE,
            date TEXT NOT NULL,
            conversion TEXT NOT NULL,
            czk_net_halere INTEGER NOT NULL,
            czk_vat_halere INTEGER NOT NULL,
            rate_currency TEXT,
            rate_amount INTEGER,
            rate_value TEXT,
            rate_declared_on TEXT,
            provisional INTEGER NOT NULL,
            bank_czk_total_halere INTEGER,
            CHECK (
                (rate_currency IS NULL) = (rate_amount IS NULL)
                AND (rate_currency IS NULL) = (rate_value IS NULL)
                AND (rate_currency IS NULL) = (rate_declared_on IS NULL)),
            CHECK (rate_amount IS NULL OR rate_amount > 0)
        );
        """

    /// A year's settings, advances (a row per month) and deductions (one row) are kept apart, and the checks make a
    /// value the tax engine would refuse impossible to store, because a bad value found on reading would stop the
    /// app from opening at all. The month sets are in the `secondary_months` and `health_exempt_months` columns.
    /// Deductions are whole Kč.
    static let yearTables = """
        CREATE TABLE year_settings (
            year INTEGER NOT NULL PRIMARY KEY,
            expense_percent INTEGER NOT NULL CHECK (expense_percent IN (80, 60, 40, 30)),
            reduced_social_base INTEGER NOT NULL,
            activity_from INTEGER NOT NULL CHECK (activity_from BETWEEN 1 AND 12),
            activity_to INTEGER NOT NULL CHECK (activity_to BETWEEN 1 AND 12),
            secondary_months TEXT NOT NULL,
            health_exempt_months TEXT NOT NULL,
            taxpayer_credit INTEGER NOT NULL,
            minimum_mode TEXT NOT NULL,
            income_fx_method TEXT NOT NULL
        );

        CREATE TABLE advance_month (
            year INTEGER NOT NULL REFERENCES year_settings(year) ON DELETE CASCADE,
            month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
            social INTEGER NOT NULL CHECK (social >= 0),
            health INTEGER NOT NULL CHECK (health >= 0),
            tax INTEGER NOT NULL CHECK (tax >= 0),
            PRIMARY KEY (year, month)
        );

        CREATE TABLE deduction (
            year INTEGER NOT NULL PRIMARY KEY REFERENCES year_settings(year) ON DELETE CASCADE,
            mortgage_interest_paid INTEGER NOT NULL CHECK (mortgage_interest_paid >= 0),
            mortgage_months INTEGER NOT NULL CHECK (mortgage_months BETWEEN 0 AND 12),
            mortgage_cap TEXT NOT NULL,
            life_insurance INTEGER NOT NULL CHECK (life_insurance >= 0),
            pension_savings INTEGER NOT NULL CHECK (pension_savings >= 0),
            dip INTEGER NOT NULL CHECK (dip >= 0),
            long_term_care INTEGER NOT NULL CHECK (long_term_care >= 0),
            gifts INTEGER NOT NULL CHECK (gifts >= 0)
        );

        CREATE TABLE income_adjustment (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            amount_halere INTEGER NOT NULL,
            description TEXT NOT NULL
        );
        """

    /// A uniform rate is one currency in one year. A ČNB rate is one currency on the day it was declared, quoted for
    /// `amount` units, which is never zero because a conversion divides by it.
    static let rateTables = """
        CREATE TABLE uniform_rate (
            year INTEGER NOT NULL,
            currency TEXT NOT NULL,
            amount INTEGER NOT NULL CHECK (amount > 0),
            rate TEXT NOT NULL,
            instruction TEXT NOT NULL,
            source_url TEXT,
            confirmed_at INTEGER,
            origin TEXT NOT NULL,
            PRIMARY KEY (year, currency)
        );

        CREATE TABLE cnb_rate (
            declared_on TEXT NOT NULL,
            currency TEXT NOT NULL,
            amount INTEGER NOT NULL CHECK (amount > 0),
            rate TEXT NOT NULL,
            PRIMARY KEY (declared_on, currency)
        );
        """

    /// The fetch log has a row per request. The import log keeps the summary of each import as JSON bytes.
    static let logTables = """
        CREATE TABLE fetch_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            at INTEGER NOT NULL,
            kind TEXT NOT NULL,
            target TEXT NOT NULL,
            ok INTEGER NOT NULL,
            message TEXT NOT NULL
        );

        CREATE TABLE import_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            at INTEGER NOT NULL,
            json BLOB NOT NULL
        );
        """

    /// For the year queries (by issue date, by DUZP, by payment date), the lookups by number, by client and by
    /// Fakturoid id (the import looks up the invoices it has imported), and the latest rate of one currency up to a
    /// day. The keys of the other tables serve their queries.
    static let indexes = """
        CREATE UNIQUE INDEX invoice_number_digits ON invoice(number_digits);
        CREATE INDEX invoice_issue_date ON invoice(issue_date);
        CREATE INDEX invoice_duzp ON invoice(duzp);
        CREATE INDEX invoice_client ON invoice(client_id);
        CREATE INDEX invoice_fakturoid_id ON invoice(fakturoid_id);
        CREATE INDEX payment_date ON payment(date);
        CREATE INDEX template_client ON template(client_id);
        CREATE INDEX income_adjustment_date ON income_adjustment(date);
        CREATE INDEX cnb_rate_currency_day ON cnb_rate(currency, declared_on);
        """
}

// MARK: - Version 2

private nonisolated extension Schema {
    /// The family: the children, what each year says about each of them, and the spouse of each year.
    static func createVersion2(_ connection: SQLiteConnection, _ searchIndex: SearchIndexKind) throws {
        try connection.execute(familyTables)
        try connection.execute(spouseColumns)
    }

    /// A child is kept across the years, and `child_year` holds what a year says about it, a row for a year that says
    /// something of its own (a year without one takes it from an earlier year, see `FamilyResolution`). The row goes
    /// with its child and with the settings of its year, so a year gets its settings stored before a row of it is.
    /// A household of NULL is a year in which the child does not live in the household, and ZTP/P or studies of NULL
    /// are none. `child_order` is the order of the child in the household, 1 for the first.
    static let familyTables = """
        CREATE TABLE child (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            birth_date TEXT NOT NULL
        );

        CREATE TABLE child_year (
            child_id INTEGER NOT NULL REFERENCES child(id) ON DELETE CASCADE,
            year INTEGER NOT NULL REFERENCES year_settings(year) ON DELETE CASCADE,
            household_from INTEGER,
            household_to INTEGER,
            claimant TEXT NOT NULL,
            child_order INTEGER NOT NULL CHECK (child_order >= 1),
            ztpp_from INTEGER,
            ztpp_to INTEGER,
            studies_from INTEGER,
            studies_to INTEGER,
            PRIMARY KEY (child_id, year),
            CHECK ((household_from IS NULL) = (household_to IS NULL)),
            CHECK (household_from BETWEEN 1 AND 12 AND household_to BETWEEN household_from AND 12),
            CHECK ((ztpp_from IS NULL) = (ztpp_to IS NULL)),
            CHECK (ztpp_from BETWEEN 1 AND 12 AND ztpp_to BETWEEN ztpp_from AND 12),
            CHECK ((studies_from IS NULL) = (studies_to IS NULL)),
            CHECK (studies_from BETWEEN 1 AND 12 AND studies_to BETWEEN studies_from AND 12)
        );
        """

    /// The spouse of a year in its settings: the claim (0 or 1), the months married and in the household, the spouse's
    /// own income for the year in whole Kč and the months of ZTP/P. All are NULL for a year without a spouse, and the
    /// months of ZTP/P are NULL for none. An added column can only have checks of its own, so each column is checked
    /// against those added before it.
    static let spouseColumns = """
        ALTER TABLE year_settings ADD COLUMN spouse_claim INTEGER CHECK (spouse_claim IN (0, 1));

        ALTER TABLE year_settings ADD COLUMN spouse_from INTEGER
            CHECK ((spouse_from IS NULL) = (spouse_claim IS NULL))
            CHECK (spouse_from BETWEEN 1 AND 12);

        ALTER TABLE year_settings ADD COLUMN spouse_to INTEGER
            CHECK ((spouse_to IS NULL) = (spouse_claim IS NULL))
            CHECK (spouse_to BETWEEN spouse_from AND 12);

        ALTER TABLE year_settings ADD COLUMN spouse_own_income INTEGER
            CHECK ((spouse_own_income IS NULL) = (spouse_claim IS NULL))
            CHECK (spouse_own_income >= 0);

        ALTER TABLE year_settings ADD COLUMN spouse_ztpp_from INTEGER
            CHECK (spouse_ztpp_from IS NULL OR spouse_claim IS NOT NULL)
            CHECK (spouse_ztpp_from BETWEEN 1 AND 12);

        ALTER TABLE year_settings ADD COLUMN spouse_ztpp_to INTEGER
            CHECK ((spouse_ztpp_to IS NULL) = (spouse_ztpp_from IS NULL))
            CHECK (spouse_ztpp_to BETWEEN spouse_ztpp_from AND 12);
        """
}

// MARK: - Version 3

private nonisolated extension Schema {
    /// The months in which a client is expected to send an invoice, as far as the person changed them, and the end of
    /// the minimum insurance as a choice of a year.
    static func createVersion3(_ connection: SQLiteConnection, _ searchIndex: SearchIndexKind) throws {
        try connection.execute(expectedInvoiceMonthTable)
        try connection.execute(dropMinimumChoice)
    }

    /// A row is a month of a client in a year in which the person's choice differs from the app's own: `expected` is 1
    /// for a month in which an invoice is expected and 0 for one in which it is not. A month that is left to the app
    /// has no row. The row goes with its client and with the settings of its year, so a year gets its settings stored
    /// before a row of it is.
    static let expectedInvoiceMonthTable = """
        CREATE TABLE expected_invoice_month (
            year INTEGER NOT NULL REFERENCES year_settings(year) ON DELETE CASCADE,
            client_id INTEGER NOT NULL REFERENCES client(id) ON DELETE CASCADE,
            month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
            expected INTEGER NOT NULL CHECK (expected IN (0, 1)),
            PRIMARY KEY (year, client_id, month)
        );
        """

    /// A year no longer chooses between counting the minimum insurance for the months through the day of the
    /// computation and for the whole year: it counts through the day, so nothing reads the column of that choice any
    /// more. The column is in no index, key or check, so SQLite drops it in place. The table is not rebuilt, and the
    /// rows of the tables that refer to it stay.
    static let dropMinimumChoice = """
        ALTER TABLE year_settings DROP COLUMN minimum_mode;
        """
}

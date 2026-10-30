import CryptoKit
import Foundation
import Testing
@testable import InvoicesTracker

struct SchemaTests {
    private struct Rollback: Error {}

    /// Every table of schema v1. The full-text table has shadow tables of its own (`invoice_search_data` …) on top.
    private static let versionOneTables = [
        "meta", "app_settings", "supplier", "bank_account", "client", "template", "template_item", "invoice",
        "invoice_item", "payment", "year_settings", "advance_month", "deduction", "income_adjustment", "uniform_rate",
        "cnb_rate", "fetch_log", "import_log", "invoice_search",
    ]

    /// Every table of the schema: those of v1, the family, which v2 adds, and the months of the expected invoices that
    /// the person changed, which v3 adds.
    private static let expectedTables = versionOneTables + ["child", "child_year", "expected_invoice_month"]

    /// Whether this SQLCipher build has FTS5 with the trigram tokenizer, found out on a throwaway database.
    private static func buildSupportsTrigram() -> Bool {
        guard let directory = try? makeTemporaryDirectory() else { return false }
        defer { removeTemporaryDirectory(directory) }
        let path = directory.appending(path: "probe.sqlite").path(percentEncoded: false)
        return (try? SQLiteConnection(path: path, key: randomKey()))?.supportsFTS5Trigram() ?? false
    }

    private func tableNames(in database: Database) async throws -> [String] {
        try await database.read { connection in
            try connection.query("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").map { $0.text(0) }
        }
    }

    private func createStatement(of table: String, in database: Database) async throws -> String? {
        let sql = try await database.read { connection in
            try connection.scalar("SELECT sql FROM sqlite_master WHERE name = ?", [.text(table)])
        }
        guard case .text(let statement)? = sql else { return nil }
        return statement
    }

    /// The names of the columns of `table`, in their order.
    private static func columnNames(of table: String, in connection: SQLiteConnection) throws -> [String] {
        try connection.query("SELECT name FROM pragma_table_info(?)", [.text(table)]).map { $0.text(0) }
    }

    /// The names of the columns of every table in `connection`, by table. SQLite's own tables are left out.
    private static func columnsOfEveryTable(in connection: SQLiteConnection) throws -> [String: [String]] {
        var columns: [String: [String]] = [:]
        let tables = try connection.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
        ).map { $0.text(0) }
        for table in tables {
            columns[table] = try columnNames(of: table, in: connection)
        }
        return columns
    }

    /// `columns` without the column `minimum_mode` of `year_settings`, which the migration to version 3 drops: what a
    /// migrated database keeps of a database of version 1 or 2.
    private static func withoutTheDroppedColumn(_ columns: [String: [String]]) -> [String: [String]] {
        var kept = columns
        kept["year_settings"] = columns["year_settings"]?.filter { $0 != "minimum_mode" }
        return kept
    }

    /// Every row of each table of `columns`, with those columns, in the order of the row ids.
    private static func rows(
        of columns: [String: [String]],
        in connection: SQLiteConnection
    ) throws -> [String: [[SQLValue]]] {
        var rows: [String: [[SQLValue]]] = [:]
        for (table, names) in columns {
            let list = names.map { "\"\($0)\"" }.joined(separator: ", ")
            rows[table] = try connection.query("SELECT \(list) FROM \"\(table)\" ORDER BY rowid").map(\.values)
        }
        return rows
    }

    /// Puts a row of invented data into every table of schema v1 that has none from the start (`meta` and
    /// `uniform_rate` have theirs).
    private static func fillVersionOne(_ c: SQLiteConnection) throws {
        try c.run("INSERT INTO app_settings(key, value) VALUES ('app', '{\"appearance\":\"dark\"}')")
        try c.run(
            """
            INSERT INTO supplier(id, name, street, postcode, city, country, ico, dic, email, phone, czech_footer)
            VALUES (1, 'Jan Novák', 'Dlouhá 1', '110 00', 'Praha', 'CZ', '00000001', '', '', '', 'Zapsán.')
            """
        )
        try c.run(
            """
            INSERT INTO bank_account(
                currency, account_number, iban, bic, routing_number, account_type, bank_name_and_address)
            VALUES ('CZK', '1234567890/0300', '', '', '', '', '')
            """
        )
        try SchemaRows.client(c, id: 1)
        try SchemaRows.template(c, id: 2, clientID: 1)
        try SchemaRows.invoice(c, id: 3, digits: "20260901", clientID: 1)
        try SchemaRows.invoiceItem(c, invoiceID: 3)
        try SchemaRows.payment(c, invoiceID: 3)
        try c.run("INSERT INTO invoice_search(rowid, doc) VALUES (3, 'alfa systems')")
        try SchemaRows.yearSettingsBeforeVersionThree(c, year: 2025, expensePercent: 40)
        try SchemaRows.yearSettingsBeforeVersionThree(c, year: 2026, activityFrom: 3)
        try SchemaRows.advanceMonth(c, year: 2026, month: 3)
        try SchemaRows.deduction(c, year: 2026, mortgageInterestPaid: 90_000)
        try c.run(
            "INSERT INTO income_adjustment(date, amount_halere, description) VALUES ('2026-02-01', -25050, 'Dobropis')"
        )
        try SchemaRows.cnbRate(c, declaredOn: "2026-10-16", currency: "USD")
        try c.run("INSERT INTO fetch_log(at, kind, target, ok, message) VALUES (1760000000, 'cnbDaily', 'x', 1, '')")
        try c.run("INSERT INTO import_log(at, json) VALUES (1760000000, X'7B7D')")
    }

    // MARK: A fresh database

    @Test func freshDatabaseIsAtLatestVersion() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        #expect(try await database.schemaVersion() == Schema.latestVersion)
        #expect(Schema.latestVersion == 3)
        let names = try await tableNames(in: database)
        for table in Self.expectedTables {
            #expect(names.contains(table), "table \(table)")
        }
        // Nothing else is created but the tables of the full-text index and SQLite's own bookkeeping.
        let extra = names.filter { name in
            !Self.expectedTables.contains(name) && !name.hasPrefix("invoice_search_") && !name.hasPrefix("sqlite_")
        }
        #expect(extra.isEmpty, "unexpected tables \(extra)")
    }

    @Test func migrationsAreNumberedFromOneWithoutGaps() {
        #expect(Schema.migrations.map(\.version) == Array(1...Schema.latestVersion))
    }

    @Test func migrationIsIdempotent() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(key: key)
        defer { removeTemporaryDirectory(directory) }
        #expect(try await database.integer("SELECT count(*) FROM uniform_rate") == 125)
        await database.close()

        let reopened = try Database(fileURL: database.fileURL, key: key)

        #expect(try await reopened.schemaVersion() == Schema.latestVersion)
        // The built-in rates were inserted by the first migration only: 32 + 31 + 31 + 31.
        #expect(try await reopened.integer("SELECT count(*) FROM uniform_rate") == 125)
        #expect(try await reopened.integer("SELECT count(*) FROM meta WHERE key = 'search_index'") == 1)
    }

    @Test func migratesEmptyVersionZeroFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileURL = directory.appending(path: "empty.sqlite")
        let key = randomKey()
        let empty = try SQLiteConnection(path: fileURL.path(percentEncoded: false), key: key)
        try empty.setUserVersion(0)
        #expect(try empty.userVersion() == 0)
        #expect(try empty.scalar("SELECT count(*) FROM sqlite_master") == .integer(0))
        empty.close()

        let database = try Database(fileURL: fileURL, key: key)

        #expect(try await database.schemaVersion() == Schema.latestVersion)
        let names = try await tableNames(in: database)
        for table in Self.expectedTables {
            #expect(names.contains(table), "table \(table)")
        }
    }

    @Test func versionTwoAddsTheFamilyTables() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        let (children, childYears, years, keys) = try await database.read { c in
            (
                try Self.columnNames(of: "child", in: c), try Self.columnNames(of: "child_year", in: c),
                try Self.columnNames(of: "year_settings", in: c),
                try c.query(
                    """
                    SELECT "table", "from", "to", on_delete FROM pragma_foreign_key_list('child_year')
                    ORDER BY "from"
                    """
                ).map(\.values)
            )
        }

        #expect(try await database.integer("PRAGMA user_version") == 3)
        #expect(children == ["id", "name", "birth_date"])
        #expect(
            childYears == [
                "child_id", "year", "household_from", "household_to", "claimant", "child_order", "ztpp_from", "ztpp_to",
                "studies_from", "studies_to",
            ]
        )
        // The spouse of a year is kept in columns of its settings, after those of v1, which v3 left without
        // minimum_mode.
        #expect(
            years == [
                "year", "expense_percent", "reduced_social_base", "activity_from", "activity_to", "secondary_months",
                "health_exempt_months", "taxpayer_credit", "income_fx_method", "spouse_claim", "spouse_from",
                "spouse_to", "spouse_own_income", "spouse_ztpp_from", "spouse_ztpp_to",
            ]
        )
        // A child's year goes with its child and with the settings of its year.
        #expect(
            keys == [
                [.text("child"), .text("child_id"), .text("id"), .text("CASCADE")],
                [.text("year_settings"), .text("year"), .text("year"), .text("CASCADE")],
            ]
        )
    }

    @Test func versionThreeAddsTheExpectedInvoiceMonths() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            try SchemaRows.client(c, id: 1)
            try SchemaRows.yearSettings(c, year: 2026)
        }

        let (columns, keys) = try await database.read { c in
            (
                try Self.columnNames(of: "expected_invoice_month", in: c),
                try c.query(
                    """
                    SELECT "table", "from", "to", on_delete FROM pragma_foreign_key_list('expected_invoice_month')
                    ORDER BY "from"
                    """
                ).map(\.values)
            )
        }

        #expect(columns == ["year", "client_id", "month", "expected"])
        // A change goes with its client and with the settings of its year.
        #expect(
            keys == [
                [.text("client"), .text("client_id"), .text("id"), .text("CASCADE")],
                [.text("year_settings"), .text("year"), .text("year"), .text("CASCADE")],
            ]
        )
        // A month has one row for a client in a year, whatever its choice, and the choice is a flag: the stored month
        // again with either choice, and a month with a choice that is none.
        let insert = "INSERT INTO expected_invoice_month(year, client_id, month, expected) VALUES (2026, 1, ?, ?)"
        try await database.write { try $0.run(insert, [.integer(5), .integer(1)]) }
        let refused: [(month: Int64, expected: Int64)] = [(5, 0), (5, 1), (6, 2), (6, -1)]
        for (month, expected) in refused {
            await #expect("month \(month), \(expected)") {
                try await database.write { try $0.run(insert, [.integer(month), .integer(expected)]) }
            } throws: { isConstraintViolation($0) }
        }
        #expect(try await database.integer("SELECT count(*) FROM expected_invoice_month") == 1)
    }

    @Test func aVersionOneDatabaseMigratesKeepingItsData() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileURL = directory.appending(path: "version1.sqlite")
        let key = randomKey()
        // A database the previous version of the app made and filled, with rows in every table.
        let old = try SQLiteConnection(path: fileURL.path(percentEncoded: false), key: key)
        try Migrator.migrate(old, searchIndex: .plain, upTo: 1)
        try old.transaction {
            try Self.fillVersionOne(old)
        }
        let columns = try Self.columnsOfEveryTable(in: old)
        let kept = Self.withoutTheDroppedColumn(columns)
        let before = try Self.rows(of: kept, in: old)
        old.close()
        #expect(Set(columns.keys) == Set(Self.versionOneTables))
        #expect(columns["year_settings"]?.contains("minimum_mode") == true)
        #expect(before.filter { $0.value.isEmpty }.isEmpty, "every table has rows")

        let database = try Database(fileURL: fileURL, key: key)

        #expect(try await database.schemaVersion() == 3)
        // Every row of every table is there, with every value it had but the column that version 3 drops.
        let after = try await database.read { try Self.rows(of: kept, in: $0) }
        #expect(after == before)
        let years = try await database.read { try Self.columnNames(of: "year_settings", in: $0) }
        #expect(!years.contains("minimum_mode"))
        // No month of an expected invoice was changed yet.
        #expect(try await database.integer("SELECT count(*) FROM expected_invoice_month") == 0)
        // No year has a spouse, and there are no children: the family starts empty.
        #expect(
            try await database.integer(
                """
                SELECT count(*) FROM year_settings WHERE spouse_claim IS NULL AND spouse_from IS NULL
                    AND spouse_to IS NULL AND spouse_own_income IS NULL AND spouse_ztpp_from IS NULL
                    AND spouse_ztpp_to IS NULL
                """
            ) == 2
        )
        #expect(try await database.yearSettings(2026).spouse == nil)
        #expect(try await database.family(year: 2026) == FamilyYear(year: 2026, children: [], spouse: nil))
        // The years of v1 take a family.
        let child = Child(id: nil, name: "Anna", birthDate: civilDate("2019-09-03"))
        let childYear = ChildYear(
            household: MonthRange(from: 1, to: 12), claimant: .me, order: 1, ztpp: nil, studies: nil
        )
        let id = try await database.saveChild(child, year: 2026, childYear: childYear)
        let spouse = SpouseYear(claim: true, months: MonthRange(from: 1, to: 12), ownIncomeKc: 0, ztpp: nil)
        try await database.saveSpouse(spouse, year: 2026)
        #expect(
            try await database.family(year: 2026)
                == FamilyYear(
                    year: 2026,
                    children: [
                        FamilyChild(
                            child: Child(id: id, name: "Anna", birthDate: civilDate("2019-09-03")), year: childYear,
                            isStored: true
                        )
                    ],
                    spouse: spouse
                )
        )
        // The clients of v1 take a change of a month.
        try await database.setExpectedInvoiceMonth(year: 2026, clientID: 1, month: 7, expected: true)
        #expect(try await database.expectedInvoiceMonths(year: 2026) == [1: [7: true]])
    }

    @Test func aVersionTwoDatabaseMigratesKeepingItsData() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileURL = directory.appending(path: "version2.sqlite")
        let key = randomKey()
        // A database the previous version of the app made: a client with an invoice, and a year that counted the
        // minimum insurance for the whole year, with what hangs on the settings of the year.
        let old = try SQLiteConnection(path: fileURL.path(percentEncoded: false), key: key)
        try Migrator.migrate(old, searchIndex: .plain, upTo: 2)
        try old.transaction {
            try SchemaRows.client(old, id: 1)
            try SchemaRows.invoice(old, id: 3, digits: "20260901", clientID: 1)
            try SchemaRows.yearSettingsBeforeVersionThree(old, year: 2026, expensePercent: 40, mode: "wholeYear")
            try SchemaRows.advanceMonth(old, year: 2026, month: 3)
            try SchemaRows.deduction(old, year: 2026, mortgageInterestPaid: 90_000)
            try SchemaRows.child(old, id: 1)
            try SchemaRows.childYear(old, childID: 1, year: 2026)
            try SchemaRows.spouse(old, year: 2026)
        }
        let columns = try Self.columnsOfEveryTable(in: old)
        let kept = Self.withoutTheDroppedColumn(columns)
        let before = try Self.rows(of: kept, in: old)
        let storedMode = try old.scalar("SELECT minimum_mode FROM year_settings WHERE year = 2026")
        old.close()
        #expect(Set(columns.keys) == Set(Self.versionOneTables + ["child", "child_year"]))
        #expect(storedMode == .text("wholeYear"))

        let database = try Database(fileURL: fileURL, key: key)

        #expect(try await database.schemaVersion() == 3)
        // Every row of every table is there, with every value it had but the column that version 3 drops. The rows
        // that hang on the settings of the year are there too: rebuilding the table would have deleted them.
        let after = try await database.read { try Self.rows(of: kept, in: $0) }
        #expect(after == before)
        let years = try await database.read { try Self.columnNames(of: "year_settings", in: $0) }
        #expect(!years.contains("minimum_mode"))
        // The months of the expected invoices exist, and nothing has changed one yet.
        #expect(try await database.integer("SELECT count(*) FROM expected_invoice_month") == 0)
        // The year reads as it was stored.
        let settings = try await database.yearSettings(2026)
        #expect(settings.expensePercent == 40)
        #expect(settings.advances.social[2] == 3852)
        #expect(settings.deductions.mortgageInterestPaid == 90_000)
        let spouse = SpouseYear(claim: true, months: MonthRange(from: 1, to: 12), ownIncomeKc: 0, ztpp: nil)
        #expect(settings.spouse == spouse)
        #expect(try await database.family(year: 2026).children.map(\.child.id) == [1])
        // The client takes a change of a month from now on.
        try await database.setExpectedInvoiceMonth(year: 2026, clientID: 1, month: 7, expected: false)
        #expect(try await database.expectedInvoiceMonths(year: 2026) == [1: [7: false]])
    }

    @Test func aDatabaseOfANewerVersionIsRefusedAndLeftAlone() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let fileURL = directory.appending(path: "newer.sqlite")
        let path = fileURL.path(percentEncoded: false)
        let key = randomKey()
        let newer = try SQLiteConnection(path: path, key: key)
        try newer.setUserVersion(Schema.latestVersion + 1)
        newer.close()

        #expect(throws: SchemaError.newerThanApp(found: Schema.latestVersion + 1, supported: Schema.latestVersion)) {
            _ = try Database(fileURL: fileURL, key: key)
        }

        let reopened = try SQLiteConnection(path: path, key: key)
        #expect(try reopened.userVersion() == Schema.latestVersion + 1)
        #expect(try reopened.scalar("SELECT count(*) FROM sqlite_master") == .integer(0))
    }

    @Test(arguments: [nil, "automatic", "gin"] as [String?])
    func aDatabaseWithoutAKnownKindOfSearchTableIsRefused(recorded: String?) async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(searchIndex: .plain, key: key)
        defer { removeTemporaryDirectory(directory) }
        try await database.write { connection in
            try connection.run("DELETE FROM meta WHERE key = 'search_index'")
            if let recorded {
                try connection.run("INSERT INTO meta(key, value) VALUES ('search_index', ?)", [.text(recorded)])
            }
        }
        await database.close()

        #expect(throws: SchemaError.unknownSearchIndexKind) {
            _ = try Database(fileURL: database.fileURL, key: key)
        }
    }

    // MARK: The migration framework

    @Test func eachStepRunsOnceAndOnlyUpToTheRequestedVersion() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let connection = try SQLiteConnection(
            path: directory.appending(path: "steps.sqlite").path(percentEncoded: false),
            key: randomKey()
        )
        // A database made by the first version is at 1; a second step, the test's own, upgrades it.
        let addTable = Migration(version: 2) { c, _ in
            try c.run("CREATE TABLE step_two(x INTEGER NOT NULL)")
            try c.run("INSERT INTO step_two(x) VALUES (1)")
        }
        let steps = [Schema.migrations[0], addTable]

        try Migrator.migrate(connection, migrations: steps, searchIndex: .plain, upTo: 0)
        #expect(try connection.userVersion() == 0)
        #expect(try connection.scalar("SELECT count(*) FROM sqlite_master") == .integer(0))

        try Migrator.migrate(connection, migrations: steps, searchIndex: .plain, upTo: 1)
        #expect(try connection.userVersion() == 1)
        #expect(try connection.scalar("SELECT count(*) FROM sqlite_master WHERE name = 'step_two'") == .integer(0))

        try Migrator.migrate(connection, migrations: steps, searchIndex: .plain, upTo: 2)
        #expect(try connection.userVersion() == 2)
        #expect(try connection.scalar("SELECT count(*) FROM step_two") == .integer(1))

        // Nothing is left to do, so nothing runs again (a second run would fail: the table exists).
        try Migrator.migrate(connection, migrations: steps, searchIndex: .plain, upTo: 2)
        #expect(try connection.userVersion() == 2)
        #expect(try connection.scalar("SELECT count(*) FROM step_two") == .integer(1))
    }

    @Test func aFailingStepLeavesTheDatabaseAndItsVersionAsTheyWere() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let connection = try SQLiteConnection(
            path: directory.appending(path: "failing.sqlite").path(percentEncoded: false),
            key: randomKey()
        )
        let broken = Migration(version: 2) { c, _ in
            try c.run("CREATE TABLE half_done(x INTEGER NOT NULL)")
            try c.run("INSERT INTO half_done(x) VALUES (1)")
            try c.setUserVersion(99)
            throw Rollback()
        }

        #expect(throws: Rollback.self) {
            try Migrator.migrate(connection, migrations: [Schema.migrations[0], broken], searchIndex: .plain, upTo: 2)
        }

        // Step 1 is complete and committed; step 2 left no trace, not even the version it had set.
        #expect(try connection.userVersion() == 1)
        #expect(try connection.scalar("SELECT count(*) FROM sqlite_master WHERE name = 'half_done'") == .integer(0))
        #expect(try connection.scalar("SELECT count(*) FROM uniform_rate") == .integer(125))
    }

    // MARK: Search index kinds

    @Test func automaticSearchIndexFollowsTheTrigramSupportOfTheBuild() async throws {
        let (database, directory) = try makeDatabase(searchIndex: .automatic)
        defer { removeTemporaryDirectory(directory) }

        let expected: SearchIndexKind = Self.buildSupportsTrigram() ? .fts5 : .plain

        #expect(await database.searchIndexKind == expected)
        let recorded = try await database.read { connection in
            try connection.scalar("SELECT value FROM meta WHERE key = 'search_index'")
        }
        #expect(recorded == .text(expected.rawValue))
    }

    @Test(.enabled(if: SchemaTests.buildSupportsTrigram()))
    func fullTextSearchIndexIsAVirtualTableWithTheTrigramTokenizer() async throws {
        let (database, directory) = try makeDatabase(searchIndex: .fts5)
        defer { removeTemporaryDirectory(directory) }

        #expect(await database.searchIndexKind == .fts5)
        let statement = try #require(try await createStatement(of: "invoice_search", in: database))
        #expect(statement.hasPrefix("CREATE VIRTUAL TABLE invoice_search USING fts5"))
        #expect(statement.contains("tokenize='trigram'"))
        // Any three letters of a word find it. No invoice row is needed: a virtual table cannot have foreign keys.
        let found = try await database.write { c in
            try c.run("INSERT INTO invoice_search(rowid, doc) VALUES (10, 'alfa systems | pribram')")
            try c.run("INSERT INTO invoice_search(rowid, doc) VALUES (11, 'beta | brno')")
            let rows = try c.query("SELECT rowid FROM invoice_search WHERE invoice_search MATCH '\"tem\"'")
            return rows.map { $0.int64(0) }
        }
        #expect(found == [10])
    }

    @Test func plainSearchIndexIsAnOrdinaryTableKeyedByTheInvoice() async throws {
        let (database, directory) = try makeDatabase(searchIndex: .plain)
        defer { removeTemporaryDirectory(directory) }

        #expect(await database.searchIndexKind == .plain)
        let statement = try #require(try await createStatement(of: "invoice_search", in: database))
        #expect(statement.hasPrefix("CREATE TABLE invoice_search("))
        #expect(!statement.contains("VIRTUAL"))
        // Its row id is the id of the invoice, so a search row cannot exist without one.
        await #expect {
            try await database.write { try $0.run("INSERT INTO invoice_search(rowid, doc) VALUES (99, 'x')") }
        } throws: { isConstraintViolation($0) }
        let found = try await database.write { c in
            try SchemaRows.invoice(c, id: 5, digits: "20260901")
            try c.run("INSERT INTO invoice_search(rowid, doc) VALUES (5, 'alfa')")
            return try c.query("SELECT rowid FROM invoice_search WHERE doc LIKE '%lf%'").map { $0.int64(0) }
        }
        #expect(found == [5])
    }

    @Test func rememberedSearchIndexKind() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(searchIndex: .plain, key: key)
        defer { removeTemporaryDirectory(directory) }
        #expect(await database.searchIndexKind == .plain)
        await database.close()

        // Whatever a later open asks for, the kind the database was created with wins.
        for later in [SearchIndexKind.automatic, .plain, .fts5] {
            let reopened = try Database(fileURL: database.fileURL, key: key, searchIndex: later)
            #expect(await reopened.searchIndexKind == .plain, "reopened with \(later)")
            await reopened.close()
        }
    }

    @Test(.enabled(if: SchemaTests.buildSupportsTrigram()))
    func rememberedFullTextSearchIndexKind() async throws {
        let key = randomKey()
        let (database, directory) = try makeDatabase(searchIndex: .fts5, key: key)
        defer { removeTemporaryDirectory(directory) }
        await database.close()

        for later in [SearchIndexKind.automatic, .plain, .fts5] {
            let reopened = try Database(fileURL: database.fileURL, key: key, searchIndex: later)
            #expect(await reopened.searchIndexKind == .fts5, "reopened with \(later)")
            await reopened.close()
        }
    }

    // MARK: Built-in uniform rates

    @Test func builtInUniformRatesAreSeededExactlyAsPublished() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        for (year, instruction) in BuiltInUniformRates.instructions {
            let expected = BuiltInUniformRates.rates(year: year)
            let rows = try await database.read { connection in
                try connection.query(
                    """
                    SELECT currency, amount, rate, instruction, source_url, confirmed_at, origin
                    FROM uniform_rate WHERE year = ?
                    """,
                    [.integer(Int64(year))]
                )
            }

            #expect(rows.count == expected.count, "\(year)")
            let stored = Set(rows.map { "\($0.text(0)) \($0.int64(1)) \($0.text(2))" })
            let published = Set(expected.map { "\($0.currency.code) \($0.amount) \(DecimalMath.canonical($0.rate))" })
            #expect(stored == published, "\(year)")
            #expect(rows.allSatisfy { $0.text(3) == instruction }, "\(year)")
            #expect(rows.allSatisfy { $0.optionalText(4) == nil && $0.optionalInt64(5) == nil }, "\(year)")
            #expect(rows.allSatisfy { $0.text(6) == "builtIn" }, "\(year)")
        }
        #expect(try await database.integer("SELECT count(*) FROM uniform_rate WHERE year = 2026") == 0)
        #expect(try await database.integer("SELECT count(*) FROM uniform_rate") == 125)
    }

    @Test func builtInUniformRatesAreStoredAsExactText() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        let rows = try await database.read { connection in
            try connection.query(
                """
                SELECT year, currency, amount, rate, instruction FROM uniform_rate
                WHERE (year = 2025 AND currency = 'USD') OR (year = 2022 AND currency = 'HUF')
                   OR (year = 2024 AND currency = 'TRY') ORDER BY year
                """
            )
        }

        #expect(rows.map { [$0.int64(0), $0.int64(2)] } == [[2022, 100], [2024, 100], [2025, 1]])
        #expect(rows.map { $0.text(3) } == ["6.26", "70.48", "21.84"])
        #expect(rows.map { $0.text(4) } == ["GFŘ-D-60", "GFŘ-D-65", "GFŘ-D-75"])
    }

    // MARK: The write counter

    @Test func writeCountIncrements() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        #expect(await database.writeCount == 0)

        try await database.write { try $0.run("INSERT INTO meta(key, value) VALUES ('a', '1')") }
        try await database.write { try $0.run("INSERT INTO meta(key, value) VALUES ('b', '2')") }

        #expect(await database.writeCount == 2)
        // Reading is not writing.
        _ = try await database.read { try $0.query("SELECT key FROM meta") }
        #expect(await database.writeCount == 2)

        // A body that throws rolls the transaction back and does not count.
        await #expect(throws: Rollback.self) {
            try await database.write { connection in
                try connection.run("INSERT INTO meta(key, value) VALUES ('c', '3')")
                throw Rollback()
            }
        }
        #expect(await database.writeCount == 2)
        #expect(try await database.integer("SELECT count(*) FROM meta WHERE key = 'c'") == 0)
        // A failing statement does the same.
        await #expect(throws: SQLiteError.self) {
            try await database.write { try $0.run("INSERT INTO meta(key, value) VALUES ('a', 'again')") }
        }
        #expect(await database.writeCount == 2)
    }
}

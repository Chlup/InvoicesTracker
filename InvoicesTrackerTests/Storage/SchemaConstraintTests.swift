import Foundation
import Testing
@testable import InvoicesTracker

/// What the tables of the schema refuse and what they delete along: the keys, the checks, the indexes and the
/// cascades that repositories rely on.
struct SchemaConstraintTests {
    // MARK: Cascades

    @Test func deletingAnInvoiceDeletesItsItemsAndItsPayment() async throws {
        let (database, directory) = try makeDatabase(searchIndex: .plain)
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            try SchemaRows.invoice(c, id: 10, digits: "20260901")
            try SchemaRows.invoice(c, id: 11, digits: "20260902")
            for id in [Int64(10), 11] {
                try SchemaRows.invoiceItem(c, invoiceID: id)
                try SchemaRows.payment(c, invoiceID: id)
                try c.run("INSERT INTO invoice_search(rowid, doc) VALUES (?, 'alfa')", [.integer(id)])
            }
        }

        try await database.write { try $0.run("DELETE FROM invoice WHERE id = 10") }

        for table in ["invoice_item", "payment"] {
            #expect(try await database.integer("SELECT count(*) FROM \(table) WHERE invoice_id = 10") == 0, "\(table)")
            #expect(try await database.integer("SELECT count(*) FROM \(table) WHERE invoice_id = 11") == 1, "\(table)")
        }
        // The plain search table deletes the search row too. A full-text table cannot, so its owner does.
        #expect(try await database.integer("SELECT count(*) FROM invoice_search WHERE rowid = 10") == 0)
        #expect(try await database.integer("SELECT count(*) FROM invoice_search WHERE rowid = 11") == 1)
    }

    @Test func deletingAClientDeletesItsTemplatesButKeepsItsInvoices() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            try SchemaRows.client(c, id: 1)
            try SchemaRows.client(c, id: 2)
            try SchemaRows.template(c, id: 5, clientID: 1)
            try SchemaRows.template(c, id: 6, clientID: 2)
            try SchemaRows.invoice(c, id: 10, digits: "20260901", clientID: 1)
            try SchemaRows.invoice(c, id: 11, digits: "20260902", clientID: 2)
        }

        try await database.write { try $0.run("DELETE FROM client WHERE id = 1") }

        #expect(try await database.integer("SELECT count(*) FROM template") == 1)
        #expect(try await database.integer("SELECT count(*) FROM template_item") == 1)
        #expect(try await database.integer("SELECT count(*) FROM template WHERE id = 6") == 1)
        // The invoice is a financial record with its own copy of the client's data, so it survives, detached.
        #expect(try await database.integer("SELECT count(*) FROM invoice") == 2)
        #expect(try await database.integer("SELECT count(*) FROM invoice WHERE id = 10 AND client_id IS NULL") == 1)
        #expect(try await database.integer("SELECT count(*) FROM invoice WHERE id = 11 AND client_id = 2") == 1)
    }

    @Test func deletingATemplateDeletesItsItems() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            try SchemaRows.client(c, id: 1)
            try SchemaRows.template(c, id: 5, clientID: 1)
            try SchemaRows.template(c, id: 6, clientID: 1)
        }

        try await database.write { try $0.run("DELETE FROM template WHERE id = 5") }

        #expect(try await database.integer("SELECT count(*) FROM template_item WHERE template_id = 5") == 0)
        #expect(try await database.integer("SELECT count(*) FROM template_item WHERE template_id = 6") == 1)
    }

    @Test func deletingAYearDeletesItsAdvancesAndDeductions() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            for year in [Int64(2025), 2026] {
                try SchemaRows.yearSettings(c, year: year)
                try SchemaRows.advanceMonth(c, year: year, month: 1)
                try SchemaRows.advanceMonth(c, year: year, month: 2)
                try SchemaRows.deduction(c, year: year)
            }
        }

        try await database.write { try $0.run("DELETE FROM year_settings WHERE year = 2025") }

        #expect(try await database.integer("SELECT count(*) FROM advance_month WHERE year = 2025") == 0)
        #expect(try await database.integer("SELECT count(*) FROM deduction WHERE year = 2025") == 0)
        #expect(try await database.integer("SELECT count(*) FROM advance_month WHERE year = 2026") == 2)
        #expect(try await database.integer("SELECT count(*) FROM deduction WHERE year = 2026") == 1)
    }

    /// Two children with a row in each of two years.
    private func makeFamily(in database: Database) async throws {
        try await database.write { c in
            for year in [Int64(2025), 2026] {
                try SchemaRows.yearSettings(c, year: year)
            }
            try SchemaRows.child(c, id: 1)
            try SchemaRows.child(c, id: 2, birthDate: "2024-04-12")
            for year in [Int64(2025), 2026] {
                try SchemaRows.childYear(c, childID: 1, year: year)
                try SchemaRows.childYear(c, childID: 2, year: year, order: 2)
            }
        }
    }

    @Test func removingAChildRemovesItsYears() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await makeFamily(in: database)

        try await database.write { try $0.run("DELETE FROM child WHERE id = 1") }

        #expect(try await database.integer("SELECT count(*) FROM child_year WHERE child_id = 1") == 0)
        #expect(try await database.integer("SELECT count(*) FROM child_year WHERE child_id = 2") == 2)
        #expect(try await database.integer("SELECT count(*) FROM year_settings") == 2)
    }

    @Test func removingAYearRemovesItsChildYears() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await makeFamily(in: database)

        try await database.write { try $0.run("DELETE FROM year_settings WHERE year = 2025") }

        #expect(try await database.integer("SELECT count(*) FROM child_year WHERE year = 2025") == 0)
        #expect(try await database.integer("SELECT count(*) FROM child_year WHERE year = 2026") == 2)
        // The children are kept across years, so they stay.
        #expect(try await database.integer("SELECT count(*) FROM child") == 2)
    }

    @Test func idsOfDeletedRowsAreNotReused() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            try SchemaRows.client(c, id: 1)
            try SchemaRows.invoice(c, id: 1, digits: "20260901")
        }
        try await database.write { c in
            try c.run("DELETE FROM client WHERE id = 1")
            try c.run("DELETE FROM invoice WHERE id = 1")
        }

        // Without AUTOINCREMENT a new row would take the id of the one that was deleted last.
        let ids = try await database.write { c in
            try SchemaRows.client(c, id: nil)
            let client = c.lastInsertRowID
            try SchemaRows.invoice(c, id: nil, digits: "20260902")
            return [client, c.lastInsertRowID]
        }
        #expect(ids == [2, 2])
    }

    // MARK: Keys

    @Test func aPaymentBelongsToExactlyOneInvoice() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            try SchemaRows.invoice(c, id: 10, digits: "20260901")
            try SchemaRows.payment(c, invoiceID: 10)
        }

        // One row per paid invoice, and none for an invoice that does not exist.
        await #expect {
            try await database.write { try SchemaRows.payment($0, invoiceID: 10) }
        } throws: { isConstraintViolation($0) }
        await #expect {
            try await database.write { try SchemaRows.payment($0, invoiceID: 404) }
        } throws: { isConstraintViolation($0) }
    }

    @Test func invoiceNumbersAreUniqueByTheirDigits() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { try SchemaRows.invoice($0, id: 1, digits: "20260501") }

        await #expect {
            try await database.write { try SchemaRows.invoice($0, id: 2, digits: "20260501") }
        } throws: { isConstraintViolation($0) }
        try await database.write { try SchemaRows.invoice($0, id: 2, digits: "20260502") }
        #expect(try await database.integer("SELECT count(*) FROM invoice") == 2)
    }

    @Test func foreignKeysAreEnforced() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        await #expect {
            try await database.write { try SchemaRows.invoiceItem($0, invoiceID: 404) }
        } throws: { isConstraintViolation($0) }
        await #expect {
            try await database.write { try SchemaRows.template($0, id: 1, clientID: 404) }
        } throws: { isConstraintViolation($0) }
        await #expect {
            try await database.write { try SchemaRows.invoice($0, id: 1, digits: "20260501", clientID: 404) }
        } throws: { isConstraintViolation($0) }
    }

    @Test func aRateOfTheCNBIsKeyedByDayAndCurrency() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            try SchemaRows.cnbRate(c, declaredOn: "2026-10-16", currency: "USD")
            try SchemaRows.cnbRate(c, declaredOn: "2026-10-16", currency: "EUR", rate: "24.325")
            try SchemaRows.cnbRate(c, declaredOn: "2026-10-15", currency: "USD", rate: "21.500")
        }

        await #expect {
            try await database.write { try SchemaRows.cnbRate($0, declaredOn: "2026-10-16", currency: "USD") }
        } throws: { isConstraintViolation($0) }
        // The rate is for `amount` units, and a conversion divides by it.
        await #expect {
            try await database.write {
                try SchemaRows.cnbRate($0, declaredOn: "2026-10-17", currency: "USD", amount: 0)
            }
        } throws: { isConstraintViolation($0) }
        #expect(try await database.integer("SELECT count(*) FROM cnb_rate") == 3)
    }

    // MARK: Indexes

    @Test func theLatestRateOfOneCurrencyUpToADayUsesTheIndexOfThatCurrency() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }

        let plan = try await database.read { connection in
            try connection.query(
                """
                EXPLAIN QUERY PLAN
                SELECT declared_on FROM cnb_rate
                WHERE currency = 'USD' AND declared_on <= '2026-10-18' ORDER BY declared_on DESC LIMIT 1
                """
            ).map { $0.text(3) }.joined(separator: " ")
        }

        #expect(plan.contains("cnb_rate_currency_day"), "plan: \(plan)")
    }

    @Test func theYearQueriesOfInvoicesUseTheirIndexes() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let year = "BETWEEN '2026-01-01' AND '2026-12-31'"
        let queries = [
            ("SELECT id FROM invoice WHERE issue_date \(year)", "invoice_issue_date"),
            ("SELECT id FROM invoice WHERE duzp \(year)", "invoice_duzp"),
            ("SELECT invoice_id FROM payment WHERE date \(year)", "payment_date"),
            ("SELECT id FROM invoice WHERE number_digits = '20260501'", "invoice_number_digits"),
            ("SELECT id FROM invoice WHERE client_id = 1", "invoice_client"),
            ("SELECT id FROM template WHERE client_id = 1", "template_client"),
            ("SELECT id FROM income_adjustment WHERE date \(year)", "income_adjustment_date"),
        ]

        for (sql, index) in queries {
            let plan = try await database.read { connection in
                try connection.query("EXPLAIN QUERY PLAN " + sql).map { $0.text(3) }.joined(separator: " ")
            }
            #expect(plan.contains(index), "\(sql): \(plan)")
        }
    }

    @Test func theLookupsOfTheImportFindInvoicesByTheirNumberDigitsAndByTheirFakturoidIdThroughIndexes() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let queries = [
            (ImportQueries.byNumberDigits(count: 3), "invoice_number_digits"),
            (ImportQueries.byFakturoidIDs(count: 3), "invoice_fakturoid_id"),
        ]

        for (condition, index) in queries {
            let plan = try await database.read { connection in
                try connection.query(
                    "EXPLAIN QUERY PLAN " + InvoiceQueries.invoices(where: condition),
                    [.text("20260501"), .text("20260502"), .text("20260503")]
                ).map { $0.text(3) }.joined(separator: " ")
            }
            #expect(plan.contains(index), "\(condition): \(plan)")
        }
    }

    // MARK: Checks

    @Test(arguments: [("invoice", "id"), ("payment", "invoice_id")])
    func aRateIsStoredCompletelyOrNotAtAll(table: String, key: String) async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            try SchemaRows.invoice(c, id: 1, digits: "20260501")
            try SchemaRows.payment(c, invoiceID: 1)
        }

        // A half-written rate would be unreadable (a missing part traps), and an amount of zero cannot convert.
        let invalid = [
            "rate_currency = 'USD'",
            "rate_currency = 'USD', rate_amount = 1, rate_value = '21.359'",
            "rate_amount = 1, rate_value = '21.359', rate_declared_on = '2026-09-30'",
            "rate_currency = 'USD', rate_amount = 0, rate_value = '21.359', rate_declared_on = '2026-09-30'",
        ]
        for assignments in invalid {
            await #expect(throws: SQLiteError.self, "\(assignments)") {
                try await database.write { try $0.run("UPDATE \(table) SET \(assignments) WHERE \(key) = 1") }
            }
        }
        try await database.write {
            try $0.run(
                """
                UPDATE \(table) SET rate_currency = 'USD', rate_amount = 100, rate_value = '21.359',
                    rate_declared_on = '2026-09-30' WHERE \(key) = 1
                """
            )
        }
        // No rate at all is complete, too.
        try await database.write {
            try $0.run(
                """
                UPDATE \(table) SET rate_currency = NULL, rate_amount = NULL, rate_value = NULL,
                    rate_declared_on = NULL WHERE \(key) = 1
                """
            )
        }
    }

    @Test func anImportedInvoiceKeepsBothPartsOfItsImportKey() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { try SchemaRows.invoice($0, id: 1, digits: "20260501") }

        await #expect(throws: SQLiteError.self) {
            try await database.write { try $0.run("UPDATE invoice SET fakturoid_id = '123' WHERE id = 1") }
        }
        await #expect(throws: SQLiteError.self) {
            try await database.write { try $0.run("UPDATE invoice SET import_fingerprint = 'abc' WHERE id = 1") }
        }
        try await database.write {
            try $0.run("UPDATE invoice SET fakturoid_id = '123', import_fingerprint = 'abc' WHERE id = 1")
        }
    }

    @Test func yearSettingsCannotHoldWhatTheEngineRejects() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        // The four percentages the engine knows are stored (the year is only a key here).
        try await database.write { c in
            try SchemaRows.yearSettings(c, year: 2026)
            for percent in [Int64(80), 40, 30] {
                try SchemaRows.yearSettings(c, year: 2000 + percent, expensePercent: percent)
            }
        }

        let invalid: [@Sendable (SQLiteConnection) throws -> Void] = [
            { try SchemaRows.yearSettings($0, year: 2027, expensePercent: 50) },
            { try SchemaRows.yearSettings($0, year: 2027, activityFrom: 0) },
            { try SchemaRows.yearSettings($0, year: 2027, activityTo: 13) },
            { try SchemaRows.advanceMonth($0, year: 2026, month: 0) },
            { try SchemaRows.advanceMonth($0, year: 2026, month: 13) },
            { try SchemaRows.advanceMonth($0, year: 2026, month: 2, social: -1) },
            { try SchemaRows.advanceMonth($0, year: 2026, month: 2, health: -1) },
            { try SchemaRows.advanceMonth($0, year: 2026, month: 2, tax: -1) },
            { try SchemaRows.advanceMonth($0, year: 2099, month: 1) },
            { try SchemaRows.deduction($0, year: 2026, mortgageInterestPaid: -1) },
            { try SchemaRows.deduction($0, year: 2026, mortgageMonths: 13) },
            { try SchemaRows.deduction($0, year: 2026, mortgageMonths: -1) },
        ]
        for (index, insert) in invalid.enumerated() {
            await #expect(throws: SQLiteError.self, "case \(index)") {
                try await database.write { try insert($0) }
            }
        }

        #expect(try await database.integer("SELECT count(*) FROM year_settings") == 4)
        #expect(try await database.integer("SELECT count(*) FROM advance_month") == 0)
        #expect(try await database.integer("SELECT count(*) FROM deduction") == 0)
        // The edges of the allowed values are allowed.
        try await database.write { c in
            try SchemaRows.advanceMonth(c, year: 2026, month: 1, social: 0, health: 0, tax: 0)
            try SchemaRows.advanceMonth(c, year: 2026, month: 12)
            try SchemaRows.deduction(c, year: 2026, mortgageInterestPaid: 90_000, mortgageMonths: 0)
            try SchemaRows.deduction(c, year: 2080, mortgageMonths: 12)
        }
    }

    /// A range of months is both of its months or neither, each 1 to 12, the first no later than the last; the order of
    /// a child is 1 or more; the spouse is all there or not at all, with an income of no less than zero; and a child's
    /// year needs its child and the settings of its year.
    @Test func theFamilyCannotHoldWhatTheEngineRejects() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.write { c in
            try SchemaRows.yearSettings(c, year: 2026)
            try SchemaRows.child(c, id: 1)
        }

        let invalid: [@Sendable (SQLiteConnection) throws -> Void] = [
            { try SchemaRows.childYear($0, childID: 1, year: 2026, householdFrom: 0) },
            { try SchemaRows.childYear($0, childID: 1, year: 2026, householdTo: 13) },
            { try SchemaRows.childYear($0, childID: 1, year: 2026, householdFrom: 7, householdTo: 6) },
            { try SchemaRows.childYear($0, childID: 1, year: 2026, householdFrom: 5, householdTo: nil) },
            { try SchemaRows.childYear($0, childID: 1, year: 2026, householdFrom: nil, householdTo: 5) },
            { try SchemaRows.childYear($0, childID: 1, year: 2026, ztppFrom: 9, ztppTo: 3) },
            { try SchemaRows.childYear($0, childID: 1, year: 2026, ztppFrom: 1) },
            { try SchemaRows.childYear($0, childID: 1, year: 2026, ztppFrom: 0, ztppTo: 12) },
            { try SchemaRows.childYear($0, childID: 1, year: 2026, studiesFrom: 13, studiesTo: 13) },
            { try SchemaRows.childYear($0, childID: 1, year: 2026, studiesTo: 6) },
            { try SchemaRows.childYear($0, childID: 1, year: 2026, studiesFrom: 10, studiesTo: 9) },
            { try SchemaRows.childYear($0, childID: 1, year: 2026, order: 0) },
            { try SchemaRows.childYear($0, childID: 404, year: 2026) },
            { try SchemaRows.childYear($0, childID: 1, year: 2099) },
            { try SchemaRows.spouse($0, year: 2026, from: 8, to: 4) },
            { try SchemaRows.spouse($0, year: 2026, from: 0) },
            { try SchemaRows.spouse($0, year: 2026, to: 13) },
            { try SchemaRows.spouse($0, year: 2026, from: nil, to: nil) },
            { try SchemaRows.spouse($0, year: 2026, to: nil) },
            { try SchemaRows.spouse($0, year: 2026, ownIncome: nil) },
            { try SchemaRows.spouse($0, year: 2026, claim: nil) },
            { try SchemaRows.spouse($0, year: 2026, claim: 2) },
            { try SchemaRows.spouse($0, year: 2026, ownIncome: -1) },
            { try SchemaRows.spouse($0, year: 2026, ztppFrom: 6, ztppTo: 2) },
            { try SchemaRows.spouse($0, year: 2026, ztppFrom: 6) },
            { try SchemaRows.spouse($0, year: 2026, ztppFrom: 1, ztppTo: 13) },
            {
                try SchemaRows.spouse(
                    $0, year: 2026, claim: nil, from: nil, to: nil, ownIncome: nil, ztppFrom: 1, ztppTo: 12
                )
            },
        ]
        for (index, write) in invalid.enumerated() {
            await #expect(throws: SQLiteError.self, "case \(index)") {
                try await database.write { try write($0) }
            }
        }

        #expect(try await database.integer("SELECT count(*) FROM child_year") == 0)
        #expect(try await database.integer("SELECT count(*) FROM year_settings WHERE spouse_claim IS NULL") == 1)
        // The edges of the allowed values are allowed, and so is a range of none.
        try await database.write { c in
            try SchemaRows.yearSettings(c, year: 2025)
            try SchemaRows.yearSettings(c, year: 2027)
            try SchemaRows.childYear(c, childID: 1, year: 2025, householdFrom: 1, householdTo: 1, order: 1)
            try SchemaRows.childYear(
                c, childID: 1, year: 2026, householdFrom: 12, householdTo: 12, order: 4, ztppFrom: 1, ztppTo: 12,
                studiesFrom: 9, studiesTo: 12
            )
            try SchemaRows.childYear(c, childID: 1, year: 2027, householdFrom: nil, householdTo: nil)
            try SchemaRows.spouse(c, year: 2025, claim: 0, from: 12, to: 12, ownIncome: 68_000)
            try SchemaRows.spouse(c, year: 2026, from: 1, to: 12, ztppFrom: 12, ztppTo: 12)
        }
        #expect(try await database.integer("SELECT count(*) FROM child_year") == 3)
        #expect(try await database.integer("SELECT count(*) FROM year_settings WHERE spouse_claim IS NOT NULL") == 2)
    }

    @Test func aSupplierIsASingleRow() async throws {
        let (database, directory) = try makeDatabase()
        defer { removeTemporaryDirectory(directory) }
        let insert = """
            INSERT INTO supplier(id, name, street, postcode, city, country, ico, dic, email, phone, czech_footer)
            VALUES (?, 'Jan Novák', 'Dlouhá 1', '110 00', 'Praha', 'CZ', '00000001', '', '', '', 'Zapsán.')
            """

        try await database.write { try $0.run(insert, [.integer(1)]) }

        await #expect {
            try await database.write { try $0.run(insert, [.integer(2)]) }
        } throws: { isConstraintViolation($0) }
        await #expect {
            try await database.write { try $0.run(insert, [.integer(1)]) }
        } throws: { isConstraintViolation($0) }
    }
}

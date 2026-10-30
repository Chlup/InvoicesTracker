import Foundation
import Testing
@testable import InvoicesTracker

/// The changes the person made to the months in which a client is expected to send an invoice: stored, read and
/// cleared per year and client, removed with the client and with the settings of their year, and refused for a month
/// that is not one. The clients are the two of `ClientsFixture`.
@Suite(.settlesBackups)
@MainActor
struct ExpectedInvoiceMonthRepositoryTests {
    /// Something other than the app, which the table has a check against, stores a change of month 13 for the client in
    /// 2026, whose settings it stores first. (A closure made on the main actor cannot be handed to the database, so the
    /// statements are run from here.)
    private nonisolated static func storeMonthThirteen(of clientID: Int64, in database: Database) async throws {
        try await database.updateYearSettings(2026) { _ in }
        try await database.write { connection in
            try connection.run("PRAGMA ignore_check_constraints = ON")
            try connection.run(
                "INSERT INTO expected_invoice_month(year, client_id, month, expected) VALUES (2026, ?, 13, 1)",
                [.integer(clientID)]
            )
            try connection.run("PRAGMA ignore_check_constraints = OFF")
        }
    }

    @Test func aMonthChangeIsStoredReadAndCleared() async throws {
        try await ClientsFixture.with { f in
            #expect(try await f.database.expectedInvoiceMonths(year: 2026).isEmpty)

            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 3, expected: false)
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 9, expected: true)
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.bravoID, month: 3, expected: true)
            try await f.database.setExpectedInvoiceMonth(year: 2025, clientID: f.alfaID, month: 12, expected: true)

            // By client and then by month, and each year has its own.
            #expect(
                try await f.database.expectedInvoiceMonths(year: 2026)
                    == [f.alfaID: [3: false, 9: true], f.bravoID: [3: true]]
            )
            #expect(try await f.database.expectedInvoiceMonths(year: 2025) == [f.alfaID: [12: true]])
            #expect(try await f.database.expectedInvoiceMonths(year: 2027).isEmpty)

            // A month that is set again takes the new choice and stays one row.
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 3, expected: true)
            #expect(
                try await f.database.expectedInvoiceMonths(year: 2026)
                    == [f.alfaID: [3: true, 9: true], f.bravoID: [3: true]]
            )
            #expect(try await f.database.integer("SELECT count(*) FROM expected_invoice_month WHERE year = 2026") == 3)

            // Clearing takes the changes of one client in one year, and clearing again takes nothing.
            try await f.database.clearExpectedInvoiceMonths(year: 2026, clientID: f.alfaID)
            try await f.database.clearExpectedInvoiceMonths(year: 2026, clientID: f.alfaID)
            #expect(try await f.database.expectedInvoiceMonths(year: 2026) == [f.bravoID: [3: true]])
            #expect(try await f.database.expectedInvoiceMonths(year: 2025) == [f.alfaID: [12: true]])
        }
    }

    @Test func aMonthSetBackToNilIsDeleted() async throws {
        try await ClientsFixture.with { f in
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 3, expected: false)
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 4, expected: true)
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.bravoID, month: 3, expected: true)

            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 3, expected: nil)

            #expect(
                try await f.database.expectedInvoiceMonths(year: 2026) == [f.alfaID: [4: true], f.bravoID: [3: true]]
            )
            // The last change of a client takes the client out of the answer, and a month with no change has nothing
            // to delete.
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 4, expected: nil)
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 4, expected: nil)
            #expect(try await f.database.expectedInvoiceMonths(year: 2026) == [f.bravoID: [3: true]])
            #expect(try await f.database.integer("SELECT count(*) FROM expected_invoice_month") == 1)
        }
    }

    @Test func storingAChangeStoresTheYearsSettingsWhenMissing() async throws {
        try await ClientsFixture.with { f in
            // 2026 has no settings of its own, so it shows the choices of 2025.
            try await f.database.updateYearSettings(2025) { $0.expensePercent = 40 }
            #expect(try await f.database.storedSettingsYears() == [2025])

            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 5, expected: false)

            // The year is stored as it showed itself, so that the change has the settings it belongs to.
            #expect(try await f.database.storedSettingsYears() == [2025, 2026])
            #expect(try await f.database.yearSettings(2026) == YearSettings(year: 2026, expensePercent: 40))
            #expect(try await f.database.expectedInvoiceMonths(year: 2026) == [f.alfaID: [5: false]])

            // Settings that are stored already are left as they are.
            try await f.database.updateYearSettings(2026) { $0.expensePercent = 30 }
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 6, expected: true)
            #expect(try await f.database.yearSettings(2026).expensePercent == 30)

            // A deletion has no row to belong to the settings of a year, so it stores none.
            try await f.database.setExpectedInvoiceMonth(year: 2027, clientID: f.alfaID, month: 6, expected: nil)
            try await f.database.clearExpectedInvoiceMonths(year: 2027, clientID: f.alfaID)
            #expect(try await f.database.storedSettingsYears() == [2025, 2026])
        }
    }

    @Test func deletingAClientDeletesItsChanges() async throws {
        try await ClientsFixture.with { f in
            try await f.database.setExpectedInvoiceMonth(year: 2025, clientID: f.alfaID, month: 12, expected: true)
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 3, expected: false)
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.bravoID, month: 3, expected: true)

            try await f.deleteClient(f.alfaID)

            #expect(try await f.database.expectedInvoiceMonths(year: 2025).isEmpty)
            #expect(try await f.database.expectedInvoiceMonths(year: 2026) == [f.bravoID: [3: true]])
            #expect(try await f.database.integer("SELECT count(*) FROM expected_invoice_month") == 1)
            // The settings of the years stay.
            #expect(try await f.database.storedSettingsYears() == [2025, 2026])
        }
    }

    @Test func deletingAYearsSettingsDeletesItsChanges() async throws {
        try await ClientsFixture.with { f in
            try await f.database.setExpectedInvoiceMonth(year: 2025, clientID: f.alfaID, month: 12, expected: true)
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 3, expected: false)
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.bravoID, month: 3, expected: true)

            try await f.database.execute("DELETE FROM year_settings WHERE year = 2025")

            #expect(try await f.database.expectedInvoiceMonths(year: 2025).isEmpty)
            #expect(
                try await f.database.expectedInvoiceMonths(year: 2026) == [f.alfaID: [3: false], f.bravoID: [3: true]]
            )
            // The clients stay.
            #expect(try await f.database.clientCount() == 2)
        }
    }

    @Test func aMonthOutsideOneToTwelveIsRefused() async throws {
        try await ClientsFixture.with { f in
            for month in [-1, 0, 13, 100] {
                await #expect("month \(month)") {
                    try await f.database.setExpectedInvoiceMonth(
                        year: 2026, clientID: f.alfaID, month: month, expected: true)
                } throws: { isConstraintViolation($0) }
            }

            // Nothing is changed, not even the settings of the year that the write stored first.
            #expect(try await f.database.expectedInvoiceMonths(year: 2026).isEmpty)
            #expect(try await f.database.storedSettingsYears().isEmpty)
            // The first and the last month are months.
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 1, expected: false)
            try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.alfaID, month: 12, expected: true)
            #expect(try await f.database.expectedInvoiceMonths(year: 2026) == [f.alfaID: [1: false, 12: true]])
        }
    }

    @Test func aChangeForAClientThatIsNotStoredIsRefused() async throws {
        try await ClientsFixture.with { f in
            // The client was deleted meanwhile, by another window.
            try await f.deleteClient(f.bravoID)

            await #expect {
                try await f.database.setExpectedInvoiceMonth(year: 2026, clientID: f.bravoID, month: 5, expected: true)
            } throws: { isConstraintViolation($0) }

            #expect(try await f.database.integer("SELECT count(*) FROM expected_invoice_month") == 0)
            #expect(try await f.database.storedSettingsYears().isEmpty)
        }
    }

    @Test func aStoredMonthThatIsNotOneToTwelveIsReportedAsUnreadable() async throws {
        try await ClientsFixture.with { f in
            try await Self.storeMonthThirteen(of: f.alfaID, in: f.database)

            await #expect(throws: StoredValueError.unreadable(column: 1, expected: "month")) {
                _ = try await f.database.expectedInvoiceMonths(year: 2026)
            }
        }
    }
}

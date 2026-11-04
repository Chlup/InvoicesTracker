import Foundation
import Testing
@testable import InvoicesTracker

/// The invoices a budget can be made from (`Database.budgetInvoices(year:asOf:)`): the paid and the unpaid ones that
/// count as income, each once, newest first.
struct BudgetRepositoryTests {
    // MARK: Helpers

    /// An invoice issued on `issued` (`YYYY-MM-DD`), paid on `paid` when that is given.
    private func invoice(
        _ number: String, issued: String, paid: String? = nil, status: InvoiceStatus = .issued,
        review: ReviewFlag? = nil
    ) -> Invoice {
        Invoice.fixture(
            number: number, issued: issued, duzp: issued, dueDate: issued, status: status, review: review,
            payment: paid.map { Payment.fixture(on: $0) })
    }

    /// A database with an issued paid and an issued unpaid invoice of 2025, a draft and one in review of 2025, and one
    /// issued on 20. 12. 2025 and paid on 5. 1. 2026.
    private func makeStoredDatabase() async throws -> (Database, URL) {
        let (database, directory) = try makeDatabase()
        do {
            try await database.saveInvoice(invoice("20250301", issued: "2025-03-01", paid: "2025-03-20"))
            try await database.saveInvoice(invoice("20250501", issued: "2025-05-01"))
            try await database.saveInvoice(invoice("20250601", issued: "2025-06-01", status: .draft))
            try await database.saveInvoice(
                invoice("20250701", issued: "2025-07-01", review: ReviewFlag(reason: "Částka nesedí s výpisem")))
            try await database.saveInvoice(invoice("20251220", issued: "2025-12-20", paid: "2026-01-05"))
        } catch {
            removeTemporaryDirectory(directory)
            throw error
        }
        return (database, directory)
    }

    // MARK: The lists

    @Test func aYearListsItsPaidAndUnpaidInvoicesThatCountAsIncomeNewestFirst() async throws {
        let (database, directory) = try await makeStoredDatabase()
        defer { removeTemporaryDirectory(directory) }

        let listed = try await database.budgetInvoices(year: 2025, asOf: civilDate("2025-12-31"))

        // The draft and the one in review are no income, and the one paid in 2026 belongs to that year.
        #expect(listed.map(\.number) == ["20250501", "20250301"])
    }

    @Test func anInvoicePaidInALaterYearIsOnlyInThatYearsList() async throws {
        let (database, directory) = try await makeStoredDatabase()
        defer { removeTemporaryDirectory(directory) }

        let listed = try await database.budgetInvoices(year: 2026, asOf: civilDate("2026-10-17"))

        #expect(listed.map(\.number) == ["20251220"])
    }

    @Test func anInvoiceWithAPaymentAfterTheAsOfDayIsInNeitherList() async throws {
        let (database, directory) = try await makeStoredDatabase()
        defer { removeTemporaryDirectory(directory) }

        let paidLater = try await database.budgetInvoices(year: 2026, asOf: civilDate("2026-01-04"))

        #expect(paidLater.isEmpty)
    }

    @Test func anInvoiceBothIssuedAndPaidInTheYearIsListedOnce() async throws {
        let (database, directory) = try await makeStoredDatabase()
        defer { removeTemporaryDirectory(directory) }
        try await database.saveInvoice(invoice("20260201", issued: "2026-02-01", paid: "2026-02-10"))

        let listed = try await database.budgetInvoices(year: 2026, asOf: civilDate("2026-10-17"))

        #expect(listed.map(\.number) == ["20260201", "20251220"])
    }
}

import Foundation
import Testing
@testable import InvoicesTracker

/// The invoices the budget offers for the selected year (`AppModel.budgetInvoices()`), with their figures in whole Kč.
@Suite(.settlesBackups)
@MainActor
struct BudgetInvoicesTests {
    @Test func aPaidCrownInvoiceHasItsIncomeItsVatAndItsLeviesInWholeCrowns() async throws {
        try await EditorFixture.with { f in
            // 4 500,00 Kč and 945,00 Kč VAT, paid on 1. 10. 2026.
            var invoice = Invoice.fixture(
                number: "20260990", issued: "2026-09-30", payment: Payment.fixture(on: "2026-10-01"))
            invoice.id = try await f.database.saveInvoice(invoice)

            let listed = try await f.app.budgetInvoices()

            let entry = try #require(listed.first { $0.invoice.id == invoice.id })
            let stored = try await f.stored(invoice.id)
            let nets = await f.app.invoiceNetIncomes(of: [stored], asOf: f.app.receivedThrough)
            let net = try #require(nets[invoice.id])
            #expect(entry.net == net)
            #expect(entry.incomeKc == 4_500)
            #expect(entry.vatKc == 945)
            #expect(entry.leviesKc == net.effect.total)
        }
    }

    @Test func theListHoldsTheSelectedYearNewestFirst() async throws {
        try await EditorFixture.with { f in
            let listed = try await f.app.budgetInvoices()

            #expect(!listed.isEmpty)
            #expect(Set(listed.map(\.invoice.id)).count == listed.count)
            let order = listed.map { [$0.invoice.issueDate.description, $0.invoice.number] }
            #expect(order == order.sorted { $0[0] > $1[0] || ($0[0] == $1[0] && $0[1] > $1[1]) })
        }
    }

    @Test func lockedDataThrows() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = makeAppModel(in: directory, clock: ManualClock(localNoon(2026, 10, 17)))

        await #expect(throws: VaultError.locked) {
            _ = try await app.budgetInvoices()
        }
    }
}
